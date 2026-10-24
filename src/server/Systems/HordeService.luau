--!strict
-- Authoritative horde simulation. Zombies are plain data (no Humanoids, no parts on the
-- server): positions advance at SIM_HZ following the shared FlowField, with cheap separation
-- through a spatial hash. Clients receive compact snapshots at REPLICATION_HZ and draw them.
--
-- Kinds (docs/DEFINICOES.md §4): Runners hear noise and build pyramids; Bulls telegraph and
-- charge; Creepers light a fuse next to players or barricades and explode (also when shot);
-- the Brute punches and throws rocks. Spawning is driven by MatchService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Hitscan = require(Shared.Hitscan)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local ZombiePacket = require(Shared.ZombiePacket)
local FlowField = require(script.Parent.Parent.Horde.FlowField)
local Noise = require(script.Parent.Parent.Horde.Noise)
local Piles = require(script.Parent.Parent.Horde.Piles)

local HORDE = Config.HORDE
local SIM_DT = 1 / HORDE.SIM_HZ
local SEPARATION_SQ = HORDE.SEPARATION_RADIUS * HORDE.SEPARATION_RADIUS
local HASH_CELL = HORDE.CELL_SIZE
-- Zombies grab upward: players on crates, hay bales or fence rails are still in reach.
local VERTICAL_REACH = 7
local UP = Vector3.yAxis

export type Zombie = ZombiePacket.Record & {
	kindName: Types.ZombieKind,
	health: number,
	maxHealth: number,
	nextAttack: number,
	dead: boolean,
	bleedUntil: number,
	bleedDps: number,
	lastAttacker: Player?,
	noise: Noise.Source?, -- set while following a noise instead of the players
	special: number, -- end time of a windup or fuse; 0 when none
	nextSpecial: number, -- cooldown for charges / rock throws
	chargeUntil: number,
	chargeDir: Vector3,
	throwAt: Vector3?,
	pendingBlast: boolean, -- explodes when removed (Creeper)
}

export type Blast = {
	radius: number,
	playerDamage: number, -- at the center; falls off to 40% at the edge
	zombieDamage: number, -- at the center; falls off to 50% at the edge
	barricadeDamage: number,
	noise: number,
	attacker: Player?,
}

local HordeService = {}

-- Fired when something strikes a barricade: (barricade, damage). BarricadeService applies it.
HordeService.barricadeHit = Signal.new() :: Signal.Signal<BasePart, number>

-- Fired once per kill, after the zombie is gone from the simulation.
HordeService.killed = Signal.new() :: Signal.Signal<Zombie, Player?>

local zombies: { Zombie } = {}
local byId: { [number]: Zombie } = {}
-- Kills are queued and flushed at the start of the next Heartbeat, so damage can happen
-- mid-iteration (bleeding, explosions, remotes) without breaking the zombies array.
local dying: { Zombie } = {}
local nextId = 1
local stateRemote: UnreliableRemoteEvent
local removedRemote: RemoteEvent
local spawnPositions: { Vector3 } = {}
local projectiles: Folder

type Target = { position: Vector3, humanoid: Humanoid }
local targets: { Target } = {}

local function freeId(): number
	-- u16 on the wire; ids wrap long before 65535 zombies are alive at once.
	local id = nextId
	nextId = nextId % 65535 + 1
	return id
end

-- Lifecycle ----------------------------------------------------------------------------------

function HordeService.spawn(kindName: Types.ZombieKind, position: Vector3, health: number?): Zombie?
	if #zombies - #dying >= HORDE.MAX_ALIVE then
		return nil
	end
	local stats = Config.ZOMBIES[kindName]
	local hp = health or stats.health
	local zombie: Zombie = {
		id = freeId(),
		kind = Config.ZOMBIE_KIND_IDS[kindName],
		kindName = kindName,
		state = ZombiePacket.STATE_IDLE,
		position = Vector3.new(position.X, 0, position.Z),
		yaw = 0,
		health = hp,
		maxHealth = hp,
		nextAttack = 0,
		dead = false,
		bleedUntil = 0,
		bleedDps = 0,
		lastAttacker = nil,
		noise = nil,
		special = 0,
		nextSpecial = os.clock() + 2,
		chargeUntil = 0,
		chargeDir = Vector3.zAxis,
		throwAt = nil,
		pendingBlast = false,
	}
	table.insert(zombies, zombie)
	byId[zombie.id] = zombie
	return zombie
end

-- Spawns at a random ZombieSpawn point in the corn (nil when the horde is at its cap).
function HordeService.spawnRandom(kindName: Types.ZombieKind, health: number?): Zombie?
	if #spawnPositions == 0 then
		return nil
	end
	local base = spawnPositions[math.random(#spawnPositions)]
	local jitter = Vector3.new(math.random() * 8 - 4, 0, math.random() * 8 - 4)
	return HordeService.spawn(kindName, base + jitter, health)
end

function HordeService.aliveCount(): number
	return #zombies - #dying
end

-- Marks the zombie for removal on the next flush (no-op if already dying).
function HordeService.remove(zombie: Zombie)
	if zombie.dead then
		return
	end
	zombie.dead = true
	table.insert(dying, zombie)
end

-- Removes every zombie without kill credit (match reset).
function HordeService.clear()
	for _, zombie in zombies do
		zombie.pendingBlast = false
		HordeService.remove(zombie)
	end
	Noise.clear()
end

-- Returns true if this hit killed the zombie.
function HordeService.damage(zombie: Zombie, amount: number, attacker: Player?): boolean
	if zombie.dead then
		return false
	end
	zombie.health -= amount
	if attacker then
		zombie.lastAttacker = attacker
	end
	if zombie.health <= 0 then
		-- Shooting a Creeper sets it off where it stands.
		zombie.pendingBlast = zombie.kindName == "Creeper"
		HordeService.remove(zombie)
		return true
	end
	return false
end

function HordeService.bleed(zombie: Zombie, dps: number, duration: number, attacker: Player?)
	if dps <= 0 or zombie.dead then
		return
	end
	zombie.bleedDps = math.max(zombie.bleedDps, dps)
	zombie.bleedUntil = math.max(zombie.bleedUntil, os.clock() + duration)
	zombie.lastAttacker = attacker or zombie.lastAttacker
end

function HordeService.get(id: number): Zombie?
	local zombie = byId[id]
	if zombie and not zombie.dead then
		return zombie
	end
	return nil
end

function HordeService.getZombies(): { Zombie }
	return zombies
end

-- Noise and explosions ---------------------------------------------------------------------

-- Pulls zombies that hear noise toward `position` for `duration` seconds. `key` merges
-- repeated noise from one source (e.g. a player firing) into a single field.
function HordeService.noise(position: Vector3, radius: number, duration: number, key: any)
	local source = Noise.emit(position, radius, duration, key, os.clock())
	if not source then
		return
	end
	for _, z in zombies do
		if
			not z.dead
			and Config.ZOMBIES[z.kindName].hearsNoise
			and not Piles.isBusy(z)
			and Noise.hears(source, z.position)
		then
			z.noise = source
		end
	end
end

function HordeService.explode(position: Vector3, blast: Blast)
	local visual = Instance.new("Explosion")
	visual.Position = position
	visual.BlastRadius = blast.radius
	visual.BlastPressure = 0 -- visual only: no physics push
	visual.DestroyJointRadiusPercent = 0 -- damage is applied below, never by joints
	visual.ExplosionType = Enum.ExplosionType.NoCraters
	visual.Parent = workspace

	if blast.playerDamage > 0 then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				local dist = (root.Position - position).Magnitude
				if dist <= blast.radius then
					humanoid:TakeDamage(blast.playerDamage * (1 - 0.6 * dist / blast.radius))
				end
			end
		end
	end

	if blast.zombieDamage > 0 then
		for _, z in zombies do
			if not z.dead then
				local dist = (z.position - position).Magnitude
				if dist <= blast.radius then
					HordeService.damage(
						z,
						blast.zombieDamage * (1 - 0.5 * dist / blast.radius),
						blast.attacker
					)
				end
			end
		end
	end

	if blast.barricadeDamage > 0 then
		for _, part in CollectionService:GetTagged(Tags.Barricade) do
			if part:IsA("BasePart") and part:GetAttribute("Broken") ~= true then
				local reach = blast.radius + math.max(part.Size.X, part.Size.Z) / 2
				if (part.Position - position).Magnitude <= reach then
					HordeService.barricadeHit:fire(part, blast.barricadeDamage)
				end
			end
		end
	end

	if blast.noise > 0 then
		HordeService.noise(position, blast.noise, 3, nil)
	end
end

local function creeperBlast(z: Zombie)
	local creeper = Config.CREEPER
	local stats = Config.ZOMBIES.Creeper
	HordeService.explode(z.position + UP * 2, {
		radius = creeper.radius,
		playerDamage = stats.damage,
		zombieDamage = creeper.zombieDamage,
		barricadeDamage = stats.barricadeDamage,
		noise = creeper.noise,
		attacker = z.lastAttacker, -- shot by a player: they get the chain kills
	})
end

local function flushDying()
	if #dying == 0 then
		return
	end
	local batch = dying
	dying = {}
	local ids = table.create(#batch) :: { number }
	for _, zombie in batch do
		local index = table.find(zombies, zombie)
		if index then
			-- Swap-remove: order doesn't matter and this keeps removal O(1).
			zombies[index] = zombies[#zombies]
			zombies[#zombies] = nil
		end
		if byId[zombie.id] == zombie then
			byId[zombie.id] = nil
		end
		Piles.forget(zombie)
		table.insert(ids, zombie.id)
	end
	removedRemote:FireAllClients(ids)
	for _, zombie in batch do
		if zombie.health <= 0 then
			HordeService.killed:fire(zombie, zombie.lastAttacker)
		end
		-- May queue more deaths (chain reactions); they flush next Heartbeat.
		if zombie.pendingBlast then
			creeperBlast(zombie)
		end
	end
end

-- Targets and the field --------------------------------------------------------------------

local function refreshTargets()
	table.clear(targets)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			table.insert(targets, { position = root.Position, humanoid = humanoid })
		end
	end
end

local function recomputeField()
	local goals = table.create(#targets) :: { Vector3 }
	for _, t in targets do
		table.insert(goals, t.position)
	end
	FlowField.compute(goals)
end

-- Nearest player by ground distance. Unless `anyHeight`, only those within vertical reach.
local function nearestTarget(position: Vector3, anyHeight: boolean?): (Target?, number)
	local best: Target? = nil
	local bestDist = math.huge
	for _, t in targets do
		local offset = t.position - position
		if anyHeight or math.abs(offset.Y) <= VERTICAL_REACH then
			local d = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if d < bestDist then
				best, bestDist = t, d
			end
		end
	end
	return best, bestDist
end

-- Movement -----------------------------------------------------------------------------------

local function hashKey(position: Vector3): number
	return math.floor(position.X / HASH_CELL) * 65536 + math.floor(position.Z / HASH_CELL)
end

local function buildHash(): { [number]: { Zombie } }
	local hash: { [number]: { Zombie } } = {}
	for _, z in zombies do
		local key = hashKey(z.position)
		local bucket = hash[key]
		if bucket then
			table.insert(bucket, z)
		else
			hash[key] = { z }
		end
	end
	return hash
end

local function separation(z: Zombie, hash: { [number]: { Zombie } }): Vector3
	local push = Vector3.zero
	local cx = math.floor(z.position.X / HASH_CELL)
	local cz = math.floor(z.position.Z / HASH_CELL)
	for dx = -1, 1 do
		for dz = -1, 1 do
			local bucket = hash[(cx + dx) * 65536 + (cz + dz)]
			if bucket then
				for _, other in bucket do
					if other ~= z then
						local offset = z.position - other.position
						local distSq = offset.X * offset.X + offset.Z * offset.Z
						if distSq < SEPARATION_SQ and distSq > 1e-4 then
							push += offset.Unit * (1 - math.sqrt(distSq) / HORDE.SEPARATION_RADIUS)
						end
					end
				end
			end
		end
	end
	return push
end

local function isWalkable(position: Vector3): boolean
	local ix, iz = FlowField.cellAt(position)
	return FlowField.kind(ix, iz) == FlowField.FREE
end

-- Moves with wall sliding: try the full step, then each axis alone. A zombie already standing
-- on a blocked cell (dropped from a pile, or a barricade rebuilt around it) moves freely
-- until it is out.
local function moveTo(z: Zombie, step: Vector3)
	local p = z.position
	if not isWalkable(p) then
		z.position = p + step
		return
	end
	local candidates = { p + step, p + Vector3.new(step.X, 0, 0), p + Vector3.new(0, 0, step.Z) }
	for _, candidate in candidates do
		if isWalkable(candidate) then
			z.position = candidate
			return
		end
	end
end

local function face(z: Zombie, point: Vector3)
	local offset = point - z.position
	if offset.X ~= 0 or offset.Z ~= 0 then
		z.yaw = math.atan2(-offset.X, -offset.Z)
	end
end

local function lightFuse(z: Zombie, now: number)
	z.special = now + Config.CREEPER.fuse
	z.state = ZombiePacket.STATE_FUSE
end

-- The next cell is a barricade or climb zone: join/climb a pile, or stand and hit it.
local function handleBreach(
	z: Zombie,
	stats: Config.ZombieStats,
	ix: number,
	iz: number,
	nx: number,
	nz: number,
	now: number
)
	local owner = FlowField.ownerAt(nx, nz)
	local isBarricade = owner ~= nil and CollectionService:HasTag(owner, Tags.Barricade)
	if owner and stats.canPile and CollectionService:HasTag(owner, Tags.ClimbZone) then
		if Piles.handleBreach(z, owner, nx, nz, ix, iz, now) then
			return
		end
	end
	if isBarricade and z.kindName == "Creeper" then
		lightFuse(z, now)
		return
	end
	z.state = ZombiePacket.STATE_ATTACK
	face(z, FlowField.cellCenter(nx, nz))
	if owner and isBarricade and now >= z.nextAttack then
		z.nextAttack = now + stats.attackCooldown
		HordeService.barricadeHit:fire(owner, stats.barricadeDamage)
	end
end

-- Specials -----------------------------------------------------------------------------------

-- Bull: scrapes the ground (windup), then charges in a straight line. Hitting a barricade
-- deals heavy damage; hitting a player hurts; any wall ends the charge.
local function stepBull(z: Zombie, now: number): boolean
	local bull = Config.BULL
	if z.chargeUntil > now then
		z.state = ZombiePacket.STATE_CHARGE
		local nextPosition = z.position + z.chargeDir * bull.chargeSpeed * SIM_DT
		local ix, iz = FlowField.cellAt(nextPosition)
		local kind = FlowField.kind(ix, iz)
		if kind ~= FlowField.FREE then
			local owner = FlowField.ownerAt(ix, iz)
			if
				kind == FlowField.BREACH
				and owner
				and CollectionService:HasTag(owner, Tags.Barricade)
			then
				HordeService.barricadeHit:fire(owner, bull.chargeBarricadeDamage)
			end
			z.chargeUntil = 0
			return true
		end
		z.position = nextPosition
		for _, t in targets do
			local offset = t.position - z.position
			if
				Vector3.new(offset.X, 0, offset.Z).Magnitude <= 3.5
				and math.abs(offset.Y) <= VERTICAL_REACH
			then
				t.humanoid:TakeDamage(bull.chargeDamage)
				z.chargeUntil = 0
				break
			end
		end
		return true
	end

	if z.special > 0 then
		z.state = ZombiePacket.STATE_WINDUP
		if now >= z.special then
			z.special = 0
			z.chargeUntil = now + bull.chargeTime
		end
		return true
	end

	if now >= z.nextSpecial then
		local target, dist = nearestTarget(z.position)
		if
			target
			and dist >= bull.chargeMinRange
			and dist <= bull.chargeRange
			and Hitscan.clearLine(z.position + UP * 3, target.position)
		then
			local offset = target.position - z.position
			z.chargeDir = Vector3.new(offset.X, 0, offset.Z).Unit
			z.special = now + bull.windup
			z.nextSpecial = now + bull.cooldown
			z.state = ZombiePacket.STATE_WINDUP
			face(z, target.position)
			return true
		end
	end
	return false
end

local function throwRock(z: Zombie, aim: Vector3)
	local brute = Config.BRUTE
	local scale = Config.ZOMBIES.Brute.scale
	local forward = Vector3.new(-math.sin(z.yaw), 0, -math.cos(z.yaw))
	local start = z.position + UP * (5.5 * scale) + forward * 2
	local flightTime = math.clamp((aim - start).Magnitude / 55, 0.7, 1.6)
	local gravity = workspace.Gravity

	local rock = Instance.new("Part")
	rock.Name = "Rock"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(2.4, 2.4, 2.4)
	rock.Color = Color3.fromRGB(110, 104, 96)
	rock.Material = Enum.Material.Slate
	rock.CanCollide = false -- follows its arc to the target; walls don't stop a thrown boulder
	rock.CanQuery = false
	rock.CanTouch = false
	rock.CFrame = CFrame.new(start)
	-- Ballistic solve: reaches `aim` after exactly `flightTime`.
	rock.AssemblyLinearVelocity = (aim - start) / flightTime + UP * (0.5 * gravity * flightTime)
	rock.Parent = projectiles
	rock:SetNetworkOwner(nil)

	task.delay(flightTime, function()
		local position = rock.Position
		rock:Destroy()
		HordeService.explode(position, {
			radius = brute.rockRadius,
			playerDamage = brute.rockDamage,
			zombieDamage = 0,
			barricadeDamage = brute.rockBarricadeDamage,
			noise = 0,
			attacker = nil,
		})
	end)
end

-- Brute: winds up (arm raised for `windup` seconds) and throws a rock at a visible player in
-- range; otherwise walks and punches like any zombie.
local function stepBrute(z: Zombie, now: number): boolean
	local brute = Config.BRUTE
	if z.special > 0 then
		z.state = ZombiePacket.STATE_WINDUP
		local aim = z.throwAt
		if aim then
			face(z, aim)
		end
		if now >= z.special then
			z.special = 0
			-- Aim at where the target is now, not where it was at the windup.
			local target = nearestTarget(z.position, true)
			local aimAt = if target then target.position else aim
			if aimAt then
				throwRock(z, aimAt)
			end
		end
		return true
	end

	if now >= z.nextSpecial then
		local target, dist = nearestTarget(z.position, true)
		local head = z.position + UP * (5 * Config.ZOMBIES.Brute.scale)
		if
			target
			and dist >= brute.throwMinRange
			and dist <= brute.throwMaxRange
			and Hitscan.clearLine(head, target.position)
		then
			z.special = now + brute.windup
			z.nextSpecial = now + brute.cooldown
			z.throwAt = target.position
			z.state = ZombiePacket.STATE_WINDUP
			face(z, target.position)
			return true
		end
	end
	return false
end

-- Main step ----------------------------------------------------------------------------------

local function stepZombie(z: Zombie, hash: { [number]: { Zombie } }, now: number)
	if z.dead then
		return
	end
	if z.bleedUntil > now then
		if HordeService.damage(z, z.bleedDps * SIM_DT, nil) then
			return
		end
	end
	if Piles.isBusy(z) then
		return -- position is driven by Piles.step
	end
	local stats = Config.ZOMBIES[z.kindName]

	if z.kindName == "Creeper" and z.special > 0 then
		z.state = ZombiePacket.STATE_FUSE
		if now >= z.special then
			z.pendingBlast = true
			HordeService.remove(z)
		end
		return
	elseif z.kindName == "Bull" and stepBull(z, now) then
		return
	elseif z.kindName == "Brute" and stepBrute(z, now) then
		return
	end

	local target, targetDist = nearestTarget(z.position)
	if target and targetDist <= stats.attackRange then
		if z.kindName == "Creeper" then
			lightFuse(z, now)
			return
		end
		z.state = ZombiePacket.STATE_ATTACK
		face(z, target.position)
		if now >= z.nextAttack then
			z.nextAttack = now + stats.attackCooldown
			target.humanoid:TakeDamage(stats.damage)
		end
		return
	end

	-- Follow a noise while it lasts, otherwise the players' field (the no-climbing version
	-- for kinds that can't build pyramids).
	local noiseField: buffer? = nil
	local source = z.noise
	if source then
		if Noise.isActive(source, now) then
			noiseField = source.field
		else
			z.noise = nil
		end
	end
	local field = noiseField or (if stats.canPile then nil else FlowField.walkerField())

	local ix, iz = FlowField.cellAt(z.position)
	local direction: Vector3
	local nx, nz = FlowField.nextCell(ix, iz, field)
	if nx and nz then
		if FlowField.kind(nx, nz) == FlowField.BREACH then
			handleBreach(z, stats, ix, iz, nx, nz, now)
			return
		end
		direction = FlowField.cellCenter(nx, nz) - z.position
	elseif not noiseField and target and FlowField.distance(ix, iz, field) == 0 then
		-- Same cell as a player: close the last few studs directly.
		direction = target.position - z.position
	else
		-- At a noise (milling around until it fades) or nowhere to go.
		z.state = ZombiePacket.STATE_IDLE
		return
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local heading = flat.Unit + separation(z, hash) * 1.5
	if heading.Magnitude < 1e-3 then
		return
	end
	heading = heading.Unit
	moveTo(z, heading * stats.speed * SIM_DT)
	z.yaw = math.atan2(-heading.X, -heading.Z)
	z.state = ZombiePacket.STATE_WALK
end

local function simulate(now: number)
	local hash = buildHash()
	for _, z in zombies do
		stepZombie(z, hash, now)
	end
	Piles.step(now)
end

local function replicate()
	-- Zombies killed since this Heartbeat's flush are left out so they don't flicker back.
	local alive = table.create(#zombies) :: { Zombie }
	for _, z in zombies do
		if not z.dead then
			table.insert(alive, z)
		end
	end
	local count = #alive
	for first = 1, count, ZombiePacket.MAX_PER_PACKET do
		local last = math.min(first + ZombiePacket.MAX_PER_PACKET - 1, count)
		stateRemote:FireAllClients(ZombiePacket.encode(alive, first, last))
	end
end

function HordeService.init()
	stateRemote = Net.zombieState()
	removedRemote = Net.zombieRemoved()
	projectiles = Instance.new("Folder")
	projectiles.Name = "Projectiles"
	projectiles.Parent = workspace
end

function HordeService.start()
	local map = workspace:WaitForChild("Map")
	local started = os.clock()
	FlowField.build(map)
	print(string.format("[Horde] flow field built in %.0f ms", (os.clock() - started) * 1000))

	for _, part in CollectionService:GetTagged(Tags.ZombieSpawn) do
		if part:IsA("BasePart") then
			table.insert(spawnPositions, part.Position)
		end
	end

	local simAccumulator, replicateAccumulator, flowAccumulator = 0, 0, math.huge

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		flushDying()
		refreshTargets()
		Noise.step(now)

		flowAccumulator += dt
		if flowAccumulator >= HORDE.FLOW_RECOMPUTE_INTERVAL then
			flowAccumulator = 0
			recomputeField()
		end

		-- Fixed-step simulation, capped so a server hitch can't snowball.
		simAccumulator = math.min(simAccumulator + dt, SIM_DT * 3)
		while simAccumulator >= SIM_DT do
			simAccumulator -= SIM_DT
			simulate(now)
		end

		replicateAccumulator += dt
		if replicateAccumulator >= 1 / HORDE.REPLICATION_HZ then
			replicateAccumulator = 0
			replicate()
		end
	end)
end

return HordeService
