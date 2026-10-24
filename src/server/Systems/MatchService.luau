--!strict
-- Match flow (docs/DEFINICOES.md §4): Prep → Wave 1 → Prep → Wave 2 → Prep → Final wave with
-- the Brute (survive finalDuration) → Extract (reach the helicopter) → Result → new match.
--
-- State is published as attributes on ReplicatedStorage.Match (Phase, Wave, EndsAt in server
-- time, Remaining, BossHealth/BossMaxHealth, Outcome) so the HUD needs no remotes. Players who
-- die during combat stay down until the next Prep; if everyone is down, the match is lost.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local BarricadeService = require(script.Parent.BarricadeService)
local ClassService = require(script.Parent.ClassService)
local EconomyService = require(script.Parent.EconomyService)
local HordeService = require(script.Parent.HordeService)
local TurretService = require(script.Parent.TurretService)

local MatchService = {}

local MATCH = Config.MATCH
local EXTRACT_TIME = 25
local RESPAWN_DELAY = 3 -- outside combat

local state: Configuration
local phase: Types.MatchPhase = "Waiting"
local phaseEndsAt = 0 -- os.clock() deadline, 0 = no timer
local wave = 0
local spawnQueue: { Types.ZombieKind } = {}
local spawnAccumulator = 0
local queueEmptiedAt = 0
local boss: HordeService.Zombie? = nil
local helicopter: Model? = nil

local function inCombat(): boolean
	return phase == "Wave" or phase == "Final" or phase == "Extract"
end

local function setPhase(newPhase: Types.MatchPhase, duration: number?)
	phase = newPhase
	local now = os.clock()
	phaseEndsAt = if duration then now + duration else 0
	-- Phase last: clients react to its change and read the others.
	state:SetAttribute("Wave", wave)
	state:SetAttribute("EndsAt", if duration then workspace:GetServerTimeNow() + duration else 0)
	state:SetAttribute("Phase", newPhase)
end

local function aliveHumanoids(): { [Player]: BasePart }
	local alive = {}
	for _, player in Players:GetPlayers() do
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
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			task.spawn(player.LoadCharacter, player)
		end
	end
end

local function playerScale(): number
	return 1 + MATCH.extraPlayerScale * math.max(0, #Players:GetPlayers() - 1)
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

local function finish(outcome: "Victory" | "Defeat")
	state:SetAttribute("Outcome", outcome)
	state:SetAttribute("BossMaxHealth", 0)
	boss = nil
	-- The horde leaves with the match, so nobody respawns into it during the result screen.
	spawnQueue = {}
	HordeService.clear()
	setPhase("Result", MATCH.resultTime)
end

local function resetMatch()
	HordeService.clear()
	BarricadeService.resetAll()
	TurretService.clear()
	ClassService.reset()
	EconomyService.resetAll()
	if helicopter then
		helicopter:Destroy()
		helicopter = nil
	end
	for _, player in Players:GetPlayers() do
		local leaderstats = player:FindFirstChild("leaderstats")
		local kills = leaderstats and leaderstats:FindFirstChild("Abates")
		if kills and kills:IsA("IntValue") then
			kills.Value = 0
		end
	end
	wave = 0
	state:SetAttribute("Outcome", "")
	state:SetAttribute("BossHealth", 0)
	state:SetAttribute("BossMaxHealth", 0)
	-- Fresh characters: full health and a reset loadout (CombatService resets on spawn).
	for _, player in Players:GetPlayers() do
		task.spawn(player.LoadCharacter, player)
	end
	setPhase("Prep", MATCH.prepTimes[1])
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
		if #Players:GetPlayers() > 0 then
			resetMatch()
		end
		return
	elseif phase == "Result" then
		if timeUp then
			if #Players:GetPlayers() > 0 then
				resetMatch()
			else
				setPhase("Waiting")
			end
		end
		return
	elseif phase == "Prep" then
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
			local alive = aliveHumanoids()
			local inside, total = 0, 0
			for _, root in alive do
				total += 1
				if zone and inZone(zone, root.Position) then
					inside += 1
				end
			end
			-- Everyone still standing aboard: leave now. Timer out: whoever made it wins.
			if total > 0 and inside == total then
				finish("Victory")
			elseif timeUp then
				finish(if inside > 0 then "Victory" else "Defeat")
			end
		end
	end

	state:SetAttribute("Remaining", #spawnQueue + HordeService.aliveCount())
end

-- Players ------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			-- During Prep you're back quickly; in combat you wait for the next Prep, and after
			-- the result the new match reloads everyone.
			task.delay(RESPAWN_DELAY, function()
				if player.Parent and phase == "Prep" and player.Character == character then
					player:LoadCharacter()
				end
			end)
		end)
	end)
	if not inCombat() and phase ~= "Waiting" then
		player:LoadCharacter()
	end
end

function MatchService.init()
	Players.CharacterAutoLoads = false
	state = Instance.new("Configuration")
	state.Name = "Match"
	state:SetAttribute("Phase", "Waiting")
	state:SetAttribute("Wave", 0)
	state:SetAttribute("Waves", #MATCH.waves)
	state:SetAttribute("EndsAt", 0)
	state:SetAttribute("Remaining", 0)
	state:SetAttribute("BossHealth", 0)
	state:SetAttribute("BossMaxHealth", 0)
	state:SetAttribute("Outcome", "")
	state.Parent = ReplicatedStorage
end

function MatchService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	RunService.Heartbeat:Connect(tick)
end

return MatchService
