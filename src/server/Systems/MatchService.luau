--!strict
-- Match flow (docs/DEFINICOES.md §4): Lobby (pick a class, press PRONTO) → Prep → Wave 1 → … →
-- Prep → Final wave with the Brute (survive finalDuration) → Extract (reach the helicopter) →
-- Result → Lobby.
--
-- Only the players in the lobby when the match starts take part (up to MATCH.maxPlayers; their
-- `InMatch` attribute is true). Anyone who joins later has no character and spectates until
-- the next lobby. In a portal group's reserved server (the normal case once the hub is live)
-- the lobby waits for the whole party from the teleport data, and after the result everyone
-- flies back to the camp hub. State is published as attributes on ReplicatedStorage.Match (Phase, Wave,
-- EndsAt in server time, Remaining, BossHealth/BossMaxHealth, Outcome, LobbyCount,
-- ReadyCount) so the HUD needs no remotes. Participants who die during combat stay down until
-- the next Prep; if every participant is down or gone, the match is lost.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local BarricadeService = require(script.Parent.BarricadeService)
local ClassService = require(script.Parent.ClassService)
local EconomyService = require(script.Parent.EconomyService)
local HordeService = require(script.Parent.HordeService)
local TurretService = require(script.Parent.TurretService)

local MatchService = {}

-- Progression hooks: a new match began; a wave was cleared (its number); the match ended
-- with the players who made it onto the helicopter (empty on a defeat).
MatchService.started = Signal.new() :: Signal.Signal<()>
MatchService.waveCleared = Signal.new() :: Signal.Signal<number>
MatchService.finished = Signal.new() :: Signal.Signal<"Victory" | "Defeat", { Player }>

local MATCH = Config.MATCH
local EXTRACT_TIME = 25
local RESPAWN_DELAY = 3 -- outside combat
local LEAVE_GRACE = 30 -- after sending everyone to the hub, don't reopen the lobby this long

local state: Configuration
local phase: Types.MatchPhase = "Waiting"
local phaseEndsAt = 0 -- os.clock() deadline, 0 = no timer
local wave = 0
local spawnQueue: { Types.ZombieKind } = {}
local spawnAccumulator = 0
local queueEmptiedAt = 0
local boss: HordeService.Zombie? = nil
local helicopter: Model? = nil
local participants: { [Player]: boolean } = {}
-- A hub portal group's private server (or Studio simulating one): wait for `party`, then
-- send everyone back to the hub after the result.
local reserved = (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
	or (RunService:IsStudio() and Config.DEBUG.simulateReserved)
local party: { number }? = nil
local notifyRemote: RemoteEvent
local leavingUntil = 0 -- os.clock(); the group is on its way back to the hub

local function setPhase(newPhase: Types.MatchPhase, duration: number?)
	phase = newPhase
	local now = os.clock()
	phaseEndsAt = if duration then now + duration else 0
	-- Phase last: clients react to its change and read the others.
	state:SetAttribute("Wave", wave)
	state:SetAttribute("EndsAt", if duration then workspace:GetServerTimeNow() + duration else 0)
	state:SetAttribute("Phase", newPhase)
end

function MatchService.isParticipant(player: Player): boolean
	return participants[player] == true
end

local function participantCount(): number
	local count = 0
	for _ in participants do
		count += 1
	end
	return count
end

local function aliveHumanoids(): { [Player]: BasePart }
	local alive = {}
	for player in participants do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			alive[player] = root
		end
	end
	return alive
end

local function loadMissingCharacters()
	for player in participants do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			task.spawn(player.LoadCharacter, player)
		end
	end
end

local function playerScale(): number
	return 1 + MATCH.extraPlayerScale * math.max(0, participantCount() - 1)
end

local function buildQueue(composition: { [string]: number }): { Types.ZombieKind }
	local queue: { Types.ZombieKind } = {}
	local scale = playerScale()
	for kind, count in composition do
		for _ = 1, math.round(count * scale) do
			table.insert(queue, kind :: Types.ZombieKind)
		end
	end
	-- Shuffle so special zombies arrive mixed into the crowd.
	for i = #queue, 2, -1 do
		local j = math.random(i)
		queue[i], queue[j] = queue[j], queue[i]
	end
	return queue
end

local function pickFinalKind(): Types.ZombieKind
	local roll = math.random()
	for kind, weight in MATCH.finalMix do
		roll -= weight
		if roll <= 0 then
			return kind :: Types.ZombieKind
		end
	end
	return "Runner"
end

-- Helicopter ---------------------------------------------------------------------------------

local function extractionZone(): BasePart?
	local zone = CollectionService:GetTagged(Tags.Extraction)[1]
	return if zone and zone:IsA("BasePart") then zone else nil
end

local function inZone(zone: BasePart, position: Vector3): boolean
	local offset = zone.CFrame:PointToObjectSpace(position)
	return math.abs(offset.X) <= zone.Size.X / 2 and math.abs(offset.Z) <= zone.Size.Z / 2
end

-- Greybox helicopter that descends onto the extraction field.
local function spawnHelicopter(zone: BasePart)
	local model = Instance.new("Model")
	model.Name = "Helicopter"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(8, 6, 18)
	body.Color = Color3.fromRGB(70, 80, 60)
	body.Material = Enum.Material.Metal
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model
	local rotor = Instance.new("Part")
	rotor.Name = "Rotor"
	rotor.Size = Vector3.new(30, 0.3, 1.5)
	rotor.Color = Color3.fromRGB(30, 30, 30)
	rotor.Anchored = true
	rotor.CanCollide = false
	rotor.Parent = model
	local tail = Instance.new("Part")
	tail.Name = "Tail"
	tail.Size = Vector3.new(1.5, 1.5, 12)
	tail.Color = body.Color
	tail.Material = Enum.Material.Metal
	tail.Anchored = true
	tail.CanCollide = false
	tail.Parent = model
	model.PrimaryPart = body

	local landed = zone.Position + Vector3.new(0, 5, 0)
	local function place(at: Vector3)
		body.CFrame = CFrame.new(at)
		rotor.CFrame = CFrame.new(at + Vector3.new(0, 3.5, 0))
		tail.CFrame = CFrame.new(at + Vector3.new(0, 1, 14))
	end
	place(landed + Vector3.new(0, 80, 0))
	model.Parent = workspace
	helicopter = model

	local height = Instance.new("NumberValue")
	height.Value = 80
	height.Changed:Connect(function(value)
		place(landed + Vector3.new(0, value, 0))
	end)
	TweenService:Create(
		height,
		TweenInfo.new(6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = 0 }
	):Play()
end

-- Phases -------------------------------------------------------------------------------------

local function startPrep()
	local index = math.min(wave + 1, #MATCH.prepTimes)
	setPhase("Prep", MATCH.prepTimes[index])
	loadMissingCharacters()
end

local function startWave()
	wave += 1
	spawnQueue = buildQueue(MATCH.waves[wave])
	queueEmptiedAt = 0
	setPhase("Wave")
end

local function startFinal()
	wave = #MATCH.waves + 1
	spawnQueue = {}
	setPhase("Final", MATCH.finalDuration)
	local stats = Config.ZOMBIES.Brute
	local health = stats.health + Config.BRUTE.healthPerPlayer * #Players:GetPlayers()
	boss = HordeService.spawnRandom("Brute", health)
	state:SetAttribute("BossMaxHealth", health)
end

local function finish(outcome: "Victory" | "Defeat", extracted: { Player }?)
	MatchService.finished:fire(outcome, extracted or {})
	state:SetAttribute("Outcome", outcome)
	state:SetAttribute("BossMaxHealth", 0)
	boss = nil
	-- The horde leaves with the match, so nobody respawns into it during the result screen.
	spawnQueue = {}
	HordeService.clear()
	setPhase("Result", MATCH.resultTime)
end

-- Back to the lobby: a clean farm, everyone (participants and spectators) on their feet and
-- free to pick a class, nobody ready yet.
local function enterLobby()
	HordeService.clear()
	BarricadeService.resetAll()
	TurretService.clear()
	spawnQueue = {}
	boss = nil
	if helicopter then
		helicopter:Destroy()
		helicopter = nil
	end
	table.clear(participants)
	wave = 0
	state:SetAttribute("Outcome", "")
	state:SetAttribute("Remaining", 0)
	state:SetAttribute("BossHealth", 0)
	state:SetAttribute("BossMaxHealth", 0)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("InMatch", false)
		player:SetAttribute("Ready", false)
		task.spawn(player.LoadCharacter, player)
	end
	setPhase("Lobby", if reserved then MATCH.reservedLobbyTime else MATCH.lobbyTime)
end

-- Teleports `players` to the camp hub. Returns false when it can't (no hub, Studio, failure).
local function sendToHub(players: { Player }): boolean
	local hub = Config.PLACES.hub
	if #players == 0 or hub <= 0 or hub == game.PlaceId then
		return false
	end
	if RunService:IsStudio() then
		for _, player in players do
			notifyRemote:FireClient(player, "(Studio) teleporte simulado para o acampamento")
		end
		return false
	end
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, hub, players)
	if not ok then
		warn(`[Match] teleport back to the hub failed: {err}`)
	end
	return ok
end

-- The players in the lobby (up to maxPlayers, earliest first) become the match roster.
local function startMatch()
	ClassService.reset()
	EconomyService.resetAll()
	for _, player in Players:GetPlayers() do
		local joins = participantCount() < MATCH.maxPlayers
		participants[player] = if joins then true else nil
		player:SetAttribute("InMatch", joins)
		player:SetAttribute("Ready", false)
		local leaderstats = player:FindFirstChild("leaderstats")
		local kills = leaderstats and leaderstats:FindFirstChild("Abates")
		if kills and kills:IsA("IntValue") then
			kills.Value = 0
		end
		if joins then
			-- Fresh characters: full health and a reset loadout (CombatService resets on spawn).
			task.spawn(player.LoadCharacter, player)
		elseif player.Character then
			player.Character:Destroy() -- over the cap: watch this match, play the next
		end
	end
	setPhase("Prep", MATCH.prepTimes[1])
	MatchService.started:fire()
end

local function updateLobby(now: number)
	local present, ready = 0, 0
	for _, player in Players:GetPlayers() do
		present += 1
		if player:GetAttribute("Ready") == true then
			ready += 1
		end
	end
	state:SetAttribute("LobbyCount", present)
	state:SetAttribute("ReadyCount", ready)
	-- A portal group waits for its stragglers still loading in (up to the lobby timer).
	local expected = if party then #party else 0
	-- Everyone ready: start shortly instead of waiting out the lobby timer.
	if
		present > 0
		and present >= expected
		and ready == present
		and phaseEndsAt - now > MATCH.readyStartDelay
	then
		phaseEndsAt = now + MATCH.readyStartDelay
		state:SetAttribute("EndsAt", workspace:GetServerTimeNow() + MATCH.readyStartDelay)
	end
end

-- Tick ---------------------------------------------------------------------------------------

local function spawnFromQueue(dt: number, interval: number)
	spawnAccumulator += dt
	while spawnAccumulator >= interval and #spawnQueue > 0 do
		spawnAccumulator -= interval
		if not HordeService.spawnRandom(spawnQueue[#spawnQueue]) then
			break -- horde at its cap: try again next tick
		end
		spawnQueue[#spawnQueue] = nil
	end
	spawnAccumulator = math.min(spawnAccumulator, interval)
end

local function tick(dt: number)
	local now = os.clock()
	local timeUp = phaseEndsAt > 0 and now >= phaseEndsAt

	if phase == "Waiting" then
		if #Players:GetPlayers() > 0 and now >= leavingUntil then
			enterLobby()
		end
		return
	elseif phase == "Lobby" then
		if #Players:GetPlayers() == 0 then
			setPhase("Waiting")
		else
			updateLobby(now)
			if now >= phaseEndsAt then
				startMatch()
			end
		end
		return
	elseif phase == "Result" then
		if timeUp then
			if #Players:GetPlayers() == 0 then
				setPhase("Waiting")
			elseif reserved then
				-- TeleportAsync yields: wait in Waiting (not here, where every frame would
				-- teleport again) and reopen the lobby only if the trip can't happen.
				leavingUntil = now + LEAVE_GRACE
				setPhase("Waiting")
				local leaving = Players:GetPlayers()
				task.spawn(function()
					if not sendToHub(leaving) then
						leavingUntil = 0
					end
				end)
			else
				enterLobby()
			end
		end
		return
	end

	-- A match is on. Everyone who played it left: back to the lobby (or Waiting if empty).
	if next(participants) == nil then
		if #Players:GetPlayers() > 0 then
			enterLobby()
		else
			setPhase("Waiting")
		end
		return
	end

	if phase == "Prep" then
		if timeUp then
			if wave < #MATCH.waves then
				startWave()
			else
				startFinal()
			end
		end
		return
	end

	-- Combat phases.
	if next(aliveHumanoids()) == nil then
		finish("Defeat")
		return
	end

	if phase == "Wave" then
		spawnFromQueue(dt, MATCH.spawnInterval)
		if #spawnQueue == 0 and queueEmptiedAt == 0 then
			queueEmptiedAt = now
		end
		if #spawnQueue == 0 and HordeService.aliveCount() == 0 then
			MatchService.waveCleared:fire(wave)
			startPrep()
		elseif queueEmptiedAt > 0 and now - queueEmptiedAt > MATCH.waveTimeout then
			HordeService.clear() -- stragglers stuck somewhere: don't block the match
			startPrep()
		end
	else
		-- Final and Extract: an endless mixed horde.
		if #spawnQueue == 0 then
			table.insert(spawnQueue, pickFinalKind())
		end
		spawnFromQueue(dt, MATCH.finalSpawnInterval)

		local b = boss
		if b and not b.dead then
			state:SetAttribute("BossHealth", math.max(0, b.health))
		elseif b then
			state:SetAttribute("BossHealth", 0)
		end

		if phase == "Final" and timeUp then
			setPhase("Extract", EXTRACT_TIME)
			local zone = extractionZone()
			if zone then
				spawnHelicopter(zone)
			end
		elseif phase == "Extract" then
			local zone = extractionZone()
			local aboard: { Player } = {}
			local total = 0
			for player, root in aliveHumanoids() do
				total += 1
				if zone and inZone(zone, root.Position) then
					table.insert(aboard, player)
				end
			end
			-- Everyone still standing aboard: leave now. Timer out: whoever made it wins.
			if total > 0 and #aboard == total then
				finish("Victory", aboard)
			elseif timeUp then
				finish(if #aboard > 0 then "Victory" else "Defeat", aboard)
			end
		end
	end

	state:SetAttribute("Remaining", #spawnQueue + HordeService.aliveCount())
end

-- Players ------------------------------------------------------------------------------------

-- The party a portal sent here, from the first arrival's teleport data.
local function readParty(player: Player)
	if party or not reserved then
		return
	end
	local ok, data = pcall(function()
		return player:GetJoinData().TeleportData
	end)
	local list = ok and typeof(data) == "table" and (data :: any).party
	if typeof(list) == "table" then
		local ids = {}
		for _, id in list do
			if typeof(id) == "number" then
				table.insert(ids, id)
			end
		end
		party = ids
	end
end

local lastReturn: { [Player]: number } = {}
local function onReturnToHub(player: Player)
	local now = os.clock()
	if now - (lastReturn[player] or 0) < 5 then
		return
	end
	lastReturn[player] = now
	-- Mid-match players stay: only the lobby, spectators and the result screen can leave.
	if participants[player] and phase ~= "Lobby" and phase ~= "Result" then
		return
	end
	sendToHub({ player })
end

local function onPlayerAdded(player: Player)
	readParty(player)
	player:SetAttribute("InMatch", false)
	player:SetAttribute("Ready", false)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			-- In the lobby and in Prep you're back quickly; in combat you wait for the next
			-- Prep, and after the result the lobby reloads everyone.
			task.delay(RESPAWN_DELAY, function()
				if not player.Parent or player.Character ~= character then
					return
				end
				if phase == "Lobby" or (phase == "Prep" and participants[player]) then
					player:LoadCharacter()
				end
			end)
		end)
	end)
	-- Joining mid-match: no character, spectate until the next lobby.
	if phase == "Lobby" then
		player:LoadCharacter()
	end
end

local function onSetReady(player: Player, ready: unknown)
	if typeof(ready) == "boolean" and phase == "Lobby" then
		player:SetAttribute("Ready", ready)
	end
end

function MatchService.init()
	Players.CharacterAutoLoads = false
	state = Instance.new("Configuration")
	state.Name = "Match"
	state:SetAttribute("Phase", "Waiting")
	state:SetAttribute("Wave", 0)
	state:SetAttribute("Waves", #MATCH.waves + 1) -- the final wave counts too
	state:SetAttribute("EndsAt", 0)
	state:SetAttribute("Remaining", 0)
	state:SetAttribute("BossHealth", 0)
	state:SetAttribute("BossMaxHealth", 0)
	state:SetAttribute("Outcome", "")
	state:SetAttribute("LobbyCount", 0)
	state:SetAttribute("ReadyCount", 0)
	state.Parent = ReplicatedStorage
	Net.setReady()
	Net.returnToHub()
	notifyRemote = Net.notify()
end

function MatchService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		participants[player] = nil
		lastReturn[player] = nil
	end)
	Net.returnToHub().OnServerEvent:Connect(onReturnToHub)
	TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
		warn(`[Match] teleport of {player.Name} failed: {message}`)
		notifyRemote:FireClient(player, "Falha ao voltar ao acampamento — tente o botão de novo")
	end)
	Net.setReady().OnServerEvent:Connect(onSetReady)
	RunService.Heartbeat:Connect(tick)
end

return MatchService
