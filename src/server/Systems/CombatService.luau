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
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Hitscan = require(Shared.Hitscan)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local KitModels = require(Shared.Art.KitModels)
local Types = require(Shared.Types)
local HordeService = require(script.Parent.HordeService)
local WeaponModels = require(Shared.Art.WeaponModels)

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
local shotFxRemote: UnreliableRemoteEvent
local characterFxRemote: UnreliableRemoteEvent
local grenadeFolder: Folder

local function classOf(player: Player): Config.ClassStats
	local id = player:GetAttribute("Class")
	return Config.CLASSES[id :: Types.ClassId] or Config.CLASSES[Config.DEFAULT_CLASS]
end

local function reserveFor(player: Player, gun: Config.GunName): number
	return math.floor(Config.GUNS[gun].reserveMax * classOf(player).reserveBonus)
end

local function newState(player: Player): PlayerState
	local class = classOf(player)
	local gun = class.startGun
	return {
		gun = gun,
		melee = Config.LOADOUT.melee,
		mag = Config.GUNS[gun].magSize,
		reserve = reserveFor(player, gun),
		grenades = class.grenades,
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

-- Rate-limited diagnostics (Config.DEBUG.combatLog), at most a few lines per second per player.
local function debugLog(player: Player, message: string)
	if not Config.DEBUG.combatLog then
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

-- Bulls and the Brute take extra damage from behind (their weak spot).
local function backMultiplier(zombie: HordeService.Zombie, from: Vector3): number
	local multiplier = Config.ZOMBIES[zombie.kindName].backMultiplier
	if multiplier == 1 then
		return 1
	end
	local toAttacker = Vector3.new(from.X - zombie.position.X, 0, from.Z - zombie.position.Z)
	if toAttacker.Magnitude < 1e-3 then
		return 1
	end
	local forward = Vector3.new(-math.sin(zombie.yaw), 0, -math.cos(zombie.yaw))
	return if forward:Dot(toAttacker.Unit) < -0.35 then multiplier else 1
end

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
	if not Config.DEBUG.infiniteAmmo then
		state.mag -= 1
	end
	HordeService.noise(root.Position, gun.noise, 2.5, player)
	shotFxRemote:FireAllClients(player, state.gun)
	characterFxRemote:FireAllClients(player, "shot", state.gun)

	local hitList = hits :: { unknown }
	local eye = head.Position
	-- Gunslinger ability: hits set zombies burning (reuses the bleed damage-over-time).
	local ability = classOf(player).ability
	local incendiaryUntil = player:GetAttribute("IncendiaryUntil")
	local incendiary = typeof(incendiaryUntil) == "number"
		and workspace:GetServerTimeNow() < incendiaryUntil
		and ability.burnDps > 0
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
						local damage = gun.damage
							* (if isHead then gun.headMultiplier else 1)
							* backMultiplier(zombie, eye)
							* (classOf(player).damageBonus[state.gun] or 1)
						local killed = HordeService.damage(zombie, damage, player)
						if not killed and incendiary then
							HordeService.bleed(zombie, ability.burnDps, ability.burnTime, player)
						end
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
	characterFxRemote:FireAllClients(player, "reload", state.gun)
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
	characterFxRemote:FireAllClients(player, "melee", state.gun)

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
		local damage = melee.damage * backMultiplier(zombie, root.Position)
		if not HordeService.damage(zombie, damage, player) then
			HordeService.bleed(zombie, melee.bleedDps, melee.bleedTime, player)
		end
	end
end

-- Grenades ---------------------------------------------------------------------------------

-- Zombie body for grenade contact, per unit of kind scale: the body cylinder plus the
-- grenade's own radius.
local GRENADE_HIT_RADIUS = 1.4
local GRENADE_HIT_TOP = 5.2

local function explode(player: Player, position: Vector3)
	local g = Config.GRENADE
	HordeService.explode(position, {
		radius = g.radius,
		playerDamage = 0, -- no friendly fire
		zombieDamage = g.damage,
		barricadeDamage = 0,
		noise = g.noise,
		attacker = player,
	})
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
	if not Config.DEBUG.infiniteAmmo then
		state.grenades -= 1
	end
	state.nextGrenade = now + g.cooldown
	characterFxRemote:FireAllClients(player, "throw", state.gun)

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
	KitModels.attach("Grenade", grenade, CFrame.new(0, -0.45, 0), 0.8)
	grenade:SetNetworkOwner(nil) -- server simulates it, so the client can't steer the blast

	-- Once it has (roughly) landed it starts pulling Runners in: the decoy.
	task.delay(0.4, function()
		if grenade.Parent then
			HordeService.noise(grenade.Position, g.noise, g.fuse, nil)
		end
	end)
	-- Blows on whichever comes first: touching a zombie (zombies are data, not parts, so a
	-- per-frame check against their bodies stands in for Touched) or the fuse running out.
	local done = false
	local watch: RBXScriptConnection
	local function detonate()
		if done then
			return
		end
		done = true
		watch:Disconnect()
		local position = grenade.Position
		grenade:Destroy()
		explode(player, position)
	end
	watch = RunService.Heartbeat:Connect(function()
		if not grenade.Parent then
			detonate()
			return
		end
		local at = grenade.Position
		for _, zombie in HordeService.getZombies() do
			local scale = Config.ZOMBIES[zombie.kindName].scale
			local feet = zombie.position
			local height = at.Y - feet.Y
			local flat = Vector2.new(at.X - feet.X, at.Z - feet.Z).Magnitude
			if
				not zombie.dead
				and height >= 0
				and height <= GRENADE_HIT_TOP * scale
				and flat <= GRENADE_HIT_RADIUS * scale
			then
				detonate()
				return
			end
		end
	end)
	task.delay(g.fuse, detonate)
end

-- Ammo box ---------------------------------------------------------------------------------

local function onAmmoBox(player: Player)
	local state = states[player]
	local now = os.clock()
	if not state or now < state.ammoBoxReadyAt then
		return
	end
	state.ammoBoxReadyAt = now + Config.AMMO_BOX_COOLDOWN
	state.reserve = reserveFor(player, state.gun)
	state.grenades = classOf(player).grenades
	sendSync(player)
end

local function watchAmmoBox(box: Instance)
	local prompt = box:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(onAmmoBox)
	end
end

-- Puts the current gun's low-poly model (Art/WeaponModels) in the right hand, replacing
-- the previous one. Other players see it; the client also uses its Muzzle for tracers.
local function attachWeapon(character: Model, gun: string)
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local old = character:FindFirstChild("Gun")
	if old then
		old:Destroy()
	end
	local owner = Players:GetPlayerFromCharacter(character)
	local skin = if owner and owner:GetAttribute("SurvivorPack") == true then "gold" else nil
	local model = WeaponModels.build(gun, skin)
	if not model then
		return
	end
	model.Name = "Gun"
	-- Barrel along the hand's -Y (down the forearm) and the gun's top facing the back of the
	-- hand, matching the aiming pose the client puts the arms in (PoseController).
	model:PivotTo(hand.CFrame * CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	for _, piece in model:GetChildren() do
		if piece:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = piece
			weld.Parent = piece
		end
	end
	model.Parent = character
end

-- Shop API ---------------------------------------------------------------------------------

-- Swaps the gun for `gun` with a full magazine and reserve. False if already equipped.
function CombatService.equipGun(player: Player, gun: Config.GunName): boolean
	local state = states[player]
	if not state or state.gun == gun then
		return false
	end
	state.gun = gun
	state.mag = Config.GUNS[gun].magSize
	state.reserve = reserveFor(player, gun)
	state.reloading = false
	state.reloadToken += 1 -- cancels a reload in progress on the old gun
	if player.Character then
		attachWeapon(player.Character, gun)
	end
	sendSync(player)
	return true
end

function CombatService.equipMelee(player: Player, melee: Config.MeleeName): boolean
	local state = states[player]
	if not state or state.melee == melee then
		return false
	end
	state.melee = melee
	sendSync(player)
	return true
end

function CombatService.addGrenade(player: Player): boolean
	local state = states[player]
	if not state or state.grenades >= classOf(player).grenades then
		return false
	end
	state.grenades += 1
	sendSync(player)
	return true
end

-- Players ----------------------------------------------------------------------------------

-- Greybox gun so other players can see who is armed; replaced by real models in the art pass.

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local kills = Instance.new("IntValue")
	kills.Name = "Abates"
	kills.Parent = leaderstats
	leaderstats.Parent = player

	local function onCharacter(character: Model)
		states[player] = newState(player)
		if Config.DEBUG.godMode then
			-- Humanoid:TakeDamage (every zombie and explosion hit) is ignored under a ForceField.
			local shield = Instance.new("ForceField")
			shield.Name = "DebugGodMode"
			shield.Visible = false
			shield.Parent = character
		end
		sendSync(player)
		-- The avatar's body parts are swapped when its appearance finishes loading, which would
		-- drop a gun welded to the old hand; attach it only after that.
		task.spawn(function()
			if not player:HasAppearanceLoaded() then
				player.CharacterAppearanceLoaded:Wait()
			end
			local state = states[player]
			if state and player.Character == character then
				attachWeapon(character, state.gun)
			end
		end)
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	-- Buying the Survivor Pack mid-match repaints the gun right away.
	player:GetAttributeChangedSignal("SurvivorPack"):Connect(function()
		local state = states[player]
		if state and player.Character then
			attachWeapon(player.Character, state.gun)
		end
	end)
	-- Picking a class re-issues the loadout (only allowed during Prep, see ClassService).
	player:GetAttributeChangedSignal("Class"):Connect(function()
		if states[player] and aliveCharacter(player) then
			local state = newState(player)
			states[player] = state
			if player.Character then
				attachWeapon(player.Character, state.gun)
			end
			sendSync(player)
		end
	end)
end

function CombatService.init()
	syncRemote = Net.weaponSync()
	shotFxRemote = Net.shotFx()
	characterFxRemote = Net.characterFx()
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
	-- Aim pitch for everyone's poses: a finite number in range, copied to the character.
	local lastPitch: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		lastPitch[player] = nil
	end)
	Net.aimPitch().OnServerEvent:Connect(function(player, pitch: unknown)
		local now = os.clock()
		if now - (lastPitch[player] or 0) < 0.08 then
			return -- the client sends ~8/s at most; ignore floods
		end
		lastPitch[player] = now
		local character = player.Character
		if character and typeof(pitch) == "number" and pitch == pitch then
			character:SetAttribute("AimPitch", math.clamp(pitch :: number, -1.1, 1.1))
		end
	end)

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
