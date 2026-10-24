--!strict
-- Server authority for player weapons. Clients raycast locally for instant feedback and send
-- *claims*; this service owns ammo, fire rate, reloads and damage, and re-checks every claim
-- (zombie exists, in weapon range, visible from the player's head). Melee and grenades are
-- resolved entirely here from server positions.
--
-- Known trust gap (accepted for PvE co-op): the server doesn't verify the shot's aim, so a
-- modified client could pick any visible zombie in range. Damage per second is still capped
-- by fire rate, magazine and reserve, so it can't do more than a perfect-aim player.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Hitscan = require(Shared.Hitscan)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local HordeService = require(script.Parent.HordeService)

local CombatService = {}

-- Slack for network latency: clients see zombies ~100–200 ms in the past.
local RANGE_SLACK = 12
local MELEE_RANGE_SLACK = 2
local MELEE_ARC_SLACK = 15
local FIRE_BURST = 2 -- shots that may arrive bunched together by network jitter
local SYNC_MIN_INTERVAL = 0.25

type PlayerState = {
	gun: Config.GunName,
	melee: Config.MeleeName,
	mag: number,
	reserve: number,
	grenades: number,
	reloadToken: number, -- bumps on every reload start/cancel so stale timers do nothing
	reloading: boolean,
	fireAllowance: number,
	allowanceAt: number,
	nextMelee: number,
	nextGrenade: number,
	ammoBoxReadyAt: number,
	lastSync: number,
	syncQueued: boolean,
}

local states: { [Player]: PlayerState } = {}
local lastDebug: { [Player]: number } = {}
-- Last shot sequence number seen per player. Lives outside PlayerState so it survives
-- respawns: the client's counter never resets.
local shotSeqs: { [Player]: number } = {}
local syncRemote: RemoteEvent
local grenadeFolder: Folder

local function newState(): PlayerState
	local gun = Config.LOADOUT.gun
	local stats = Config.GUNS[gun]
	return {
		gun = gun,
		melee = Config.LOADOUT.melee,
		mag = stats.magSize,
		reserve = stats.reserveMax,
		grenades = Config.GRENADE.maxCarry,
		reloadToken = 0,
		reloading = false,
		fireAllowance = FIRE_BURST,
		allowanceAt = os.clock(),
		nextMelee = 0,
		nextGrenade = 0,
		ammoBoxReadyAt = 0,
		lastSync = 0,
		syncQueued = false,
	}
end

local function sendSync(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local payload: Types.WeaponState = {
		gun = state.gun,
		melee = state.melee,
		mag = state.mag,
		reserve = state.reserve,
		grenades = state.grenades,
		reloading = state.reloading,
		shotSeq = shotSeqs[player] or 0,
	}
	state.lastSync = os.clock()
	syncRemote:FireClient(player, payload)
end

-- Throttled sync for rejection paths, so a misbehaving client can't make us spam it.
local function queueSync(player: Player)
	local state = states[player]
	if not state or state.syncQueued then
		return
	end
	local wait = SYNC_MIN_INTERVAL - (os.clock() - state.lastSync)
	if wait <= 0 then
		sendSync(player)
		return
	end
	state.syncQueued = true
	task.delay(wait, function()
		if states[player] == state then
			state.syncQueued = false
			sendSync(player)
		end
	end)
end

-- Rate-limited diagnostics (Config.DEBUG_COMBAT), at most a few lines per second per player.
local function debugLog(player: Player, message: string)
	if not Config.DEBUG_COMBAT then
		return
	end
	local now = os.clock()
	if now - (lastDebug[player] or 0) < 0.25 then
		return
	end
	lastDebug[player] = now
	print(string.format("[Combat] %s: %s", player.Name, message))
end

local function aliveCharacter(player: Player): (Humanoid?, BasePart?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if
		humanoid
		and humanoid.Health > 0
		and root
		and root:IsA("BasePart")
		and head
		and head:IsA("BasePart")
	then
		return humanoid, root, head
	end
	return nil, nil, nil
end

local function onKill(_zombie: HordeService.Zombie, attacker: Player?)
	if not attacker or not attacker.Parent then
		return
	end
	local leaderstats = attacker:FindFirstChild("leaderstats")
	local kills = leaderstats and leaderstats:FindFirstChild("Abates")
	if kills and kills:IsA("IntValue") then
		kills.Value += 1
	end
end

-- Guns -------------------------------------------------------------------------------------

local function takeFireAllowance(state: PlayerState, fireRate: number): boolean
	local now = os.clock()
	state.fireAllowance =
		math.min(FIRE_BURST, state.fireAllowance + (now - state.allowanceAt) * fireRate)
	state.allowanceAt = now
	if state.fireAllowance < 1 then
		return false
	end
	state.fireAllowance -= 1
	return true
end

local function onFire(player: Player, shotSeq: unknown, hits: unknown)
	local state = states[player]
	if not state or typeof(shotSeq) ~= "number" or typeof(hits) ~= "table" then
		return
	end
	-- Sequence numbers only move forward; an old or repeated one is a replay.
	local seq = shotSeq :: number
	if seq ~= math.floor(seq) or seq <= (shotSeqs[player] or 0) then
		return
	end
	shotSeqs[player] = seq

	local gun = Config.GUNS[state.gun]
	local _, root, head = aliveCharacter(player)
	if not root or not head or state.reloading or state.mag < 1 then
		debugLog(
			player,
			string.format(
				"tiro recusado (vivo=%s recarregando=%s pente=%d)",
				tostring(root ~= nil),
				tostring(state.reloading),
				state.mag
			)
		)
		queueSync(player)
		return
	end
	if not takeFireAllowance(state, gun.fireRate) then
		debugLog(player, "tiro recusado: cadência acima do limite")
		queueSync(player)
		return
	end
	state.mag -= 1

	local hitList = hits :: { unknown }
	local eye = head.Position
	local visible: { [number]: boolean } = {}
	for i = 1, math.min(#hitList, gun.pellets) do
		local hit = hitList[i]
		if typeof(hit) == "table" then
			local entry = hit :: { [string]: unknown }
			local id, isHead = entry.id, entry.head
			if typeof(id) == "number" and typeof(isHead) == "boolean" then
				local zombie = HordeService.get(id)
				if zombie then
					local scale = Config.ZOMBIES[zombie.kindName].scale
					local distance = (zombie.position - root.Position).Magnitude
					local inRange = distance <= gun.range + RANGE_SLACK
					if inRange and visible[id] == nil then
						visible[id] = Hitscan.canSeeZombie(eye, zombie.position, scale)
					end
					if inRange and visible[id] then
						local damage = gun.damage * (if isHead then gun.headMultiplier else 1)
						local killed = HordeService.damage(zombie, damage, player)
						debugLog(
							player,
							string.format(
								"acertou zumbi %d%s: -%.0f, %s",
								id,
								if isHead then " (cabeça)" else "",
								damage,
								if killed
									then "MORTO"
									else string.format("vida %.0f", zombie.health)
							)
						)
					elseif not inRange then
						debugLog(
							player,
							string.format("acerto recusado: fora de alcance (%.0f studs)", distance)
						)
					else
						debugLog(player, "acerto recusado: parede entre jogador e zumbi")
					end
				end
			end
		end
	end
end

local function finishReload(player: Player, state: PlayerState, token: number)
	if states[player] ~= state or state.reloadToken ~= token then
		return
	end
	local gun = Config.GUNS[state.gun]
	local amount = math.min(gun.magSize - state.mag, state.reserve)
	state.mag += amount
	state.reserve -= amount
	state.reloading = false
	sendSync(player)
end

local function onReload(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local gun = Config.GUNS[state.gun]
	local humanoid = aliveCharacter(player)
	if not humanoid or state.reloading or state.mag >= gun.magSize or state.reserve <= 0 then
		queueSync(player)
		return
	end
	state.reloading = true
	state.reloadToken += 1
	local token = state.reloadToken
	sendSync(player)
	task.delay(gun.reloadTime, finishReload, player, state, token)
end

-- Melee ------------------------------------------------------------------------------------

local function onMelee(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local melee = Config.MELEE[state.melee]
	local now = os.clock()
	local _, root = aliveCharacter(player)
	-- Small tolerance so client-timed swings aren't dropped by jitter.
	if not root or now < state.nextMelee - 0.1 then
		return
	end
	state.nextMelee = now + melee.cooldown

	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local cosArc = math.cos(math.rad(melee.arc / 2 + MELEE_ARC_SLACK))
	local reach = melee.range + MELEE_RANGE_SLACK
	local origin = Vector3.new(root.Position.X, 0, root.Position.Z)

	local candidates: { { zombie: HordeService.Zombie, dist: number } } = {}
	for _, zombie in HordeService.getZombies() do
		if not zombie.dead then
			local offset = zombie.position - origin
			local dist = offset.Magnitude
			if dist <= reach and (dist < 1.5 or forward:Dot(offset / dist) >= cosArc) then
				table.insert(candidates, { zombie = zombie, dist = dist })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)
	for i = 1, math.min(#candidates, melee.maxTargets) do
		local zombie = candidates[i].zombie
		if not HordeService.damage(zombie, melee.damage, player) then
			HordeService.bleed(zombie, melee.bleedDps, melee.bleedTime, player)
		end
	end
end

-- Grenades ---------------------------------------------------------------------------------

local function explode(player: Player, position: Vector3)
	local g = Config.GRENADE
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = g.radius
	blast.BlastPressure = 0 -- visual only: no physics push
	blast.DestroyJointRadiusPercent = 0 -- never kills players
	blast.ExplosionType = Enum.ExplosionType.NoCraters
	blast.Parent = workspace

	for _, zombie in HordeService.getZombies() do
		if not zombie.dead then
			local dist = (zombie.position - position).Magnitude
			if dist <= g.radius then
				HordeService.damage(zombie, g.damage * (1 - 0.5 * dist / g.radius), player)
			end
		end
	end
end

local function onThrowGrenade(player: Player, direction: unknown)
	local state = states[player]
	if not state or typeof(direction) ~= "Vector3" then
		return
	end
	local dir = direction :: Vector3
	local magnitude = dir.Magnitude
	-- Rejects NaN (fails every comparison) and non-unit vectors.
	if not (magnitude > 0.9 and magnitude < 1.1) then
		return
	end
	local g = Config.GRENADE
	local now = os.clock()
	local _, _, head = aliveCharacter(player)
	if not head or state.grenades < 1 or now < state.nextGrenade then
		queueSync(player)
		return
	end
	state.grenades -= 1
	state.nextGrenade = now + g.cooldown

	local grenade = Instance.new("Part")
	grenade.Name = "Grenade"
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.new(0.8, 0.8, 0.8)
	grenade.Color = Color3.fromRGB(60, 72, 48)
	grenade.Material = Enum.Material.Metal
	grenade.CanQuery = false
	grenade.CanTouch = false
	grenade.CFrame = CFrame.new(head.Position + dir.Unit * 2.5)
	grenade.AssemblyLinearVelocity = dir.Unit * g.throwSpeed + Vector3.new(0, g.throwLift, 0)
	grenade.Parent = grenadeFolder
	grenade:SetNetworkOwner(nil) -- server simulates it, so the client can't steer the blast

	task.delay(g.fuse, function()
		local position = grenade.Position
		grenade:Destroy()
		explode(player, position)
	end)
end

-- Ammo box ---------------------------------------------------------------------------------

local function onAmmoBox(player: Player)
	local state = states[player]
	local now = os.clock()
	if not state or now < state.ammoBoxReadyAt then
		return
	end
	state.ammoBoxReadyAt = now + Config.AMMO_BOX_COOLDOWN
	state.reserve = Config.GUNS[state.gun].reserveMax
	state.grenades = Config.GRENADE.maxCarry
	sendSync(player)
end

local function watchAmmoBox(box: Instance)
	local prompt = box:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(onAmmoBox)
	end
end

-- Players ----------------------------------------------------------------------------------

-- Greybox gun so other players can see who is armed; replaced by real models in the art pass.
local function attachGun(character: Model)
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local gun = Instance.new("Part")
	gun.Name = "Gun"
	gun.Size = Vector3.new(0.35, 0.6, 2)
	gun.Color = Color3.fromRGB(40, 40, 44)
	gun.Material = Enum.Material.Metal
	gun.Massless = true
	gun.CanCollide = false
	gun.CanQuery = false
	gun.CanTouch = false
	gun.CFrame = hand.CFrame * CFrame.new(0, -0.3, -0.7)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = gun
	weld.Parent = gun
	gun.Parent = character
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local kills = Instance.new("IntValue")
	kills.Name = "Abates"
	kills.Parent = leaderstats
	leaderstats.Parent = player

	local function onCharacter(character: Model)
		states[player] = newState()
		sendSync(player)
		attachGun(character)
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function CombatService.init()
	syncRemote = Net.weaponSync()
	grenadeFolder = Instance.new("Folder")
	grenadeFolder.Name = "Grenades"
	grenadeFolder.Parent = workspace
end

function CombatService.start()
	Net.fireWeapon().OnServerEvent:Connect(onFire)
	Net.reload().OnServerEvent:Connect(onReload)
	Net.melee().OnServerEvent:Connect(onMelee)
	Net.throwGrenade().OnServerEvent:Connect(onThrowGrenade)
	syncRemote.OnServerEvent:Connect(queueSync)

	HordeService.killed:connect(onKill)

	CollectionService:GetInstanceAddedSignal(Tags.AmmoBox):Connect(watchAmmoBox)
	for _, box in CollectionService:GetTagged(Tags.AmmoBox) do
		watchAmmoBox(box)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		shotSeqs[player] = nil
		lastDebug[player] = nil
	end)
end

return CombatService
