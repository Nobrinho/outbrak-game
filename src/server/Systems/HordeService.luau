--!strict
-- Authoritative horde simulation. Zombies are plain data (no Humanoids, no parts on the
-- server): positions advance at SIM_HZ following the shared FlowField, with cheap separation
-- through a spatial hash. Clients receive compact snapshots at REPLICATION_HZ and draw them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local ZombiePacket = require(Shared.ZombiePacket)
local FlowField = require(script.Parent.Parent.Horde.FlowField)
local Piles = require(script.Parent.Parent.Horde.Piles)

local HORDE = Config.HORDE
local SIM_DT = 1 / HORDE.SIM_HZ
local SEPARATION_SQ = HORDE.SEPARATION_RADIUS * HORDE.SEPARATION_RADIUS
local HASH_CELL = HORDE.CELL_SIZE
-- Zombies grab upward: players on crates, hay bales or fence rails are still in reach.
local VERTICAL_REACH = 7

export type Zombie = ZombiePacket.Record & {
	kindName: Types.ZombieKind,
	health: number,
	nextAttack: number,
	dead: boolean,
	bleedUntil: number,
	bleedDps: number,
	lastAttacker: Player?,
}

local HordeService = {}

-- Fired when a zombie strikes a barricade: (barricade, damage). BarricadeService applies it.
HordeService.barricadeHit = Signal.new() :: Signal.Signal<BasePart, number>

-- Fired once per kill, after the zombie is gone from the simulation.
HordeService.killed = Signal.new() :: Signal.Signal<Zombie, Player?>

local zombies: { Zombie } = {}
local byId: { [number]: Zombie } = {}
-- Kills are queued and flushed at the start of the next Heartbeat, so damage can happen
-- mid-iteration (bleeding, remotes) without breaking the zombies array.
local dying: { Zombie } = {}
local nextId = 1
local stateRemote: UnreliableRemoteEvent
local removedRemote: RemoteEvent

type Target = { position: Vector3, humanoid: Humanoid }
local targets: { Target } = {}

local function freeId(): number
	-- u16 on the wire; ids wrap long before 65535 zombies are alive at once.
	local id = nextId
	nextId = nextId % 65535 + 1
	return id
end

function HordeService.spawn(kindName: Types.ZombieKind, position: Vector3): Zombie?
	if #zombies - #dying >= HORDE.MAX_ALIVE then
		return nil
	end
	local stats = Config.ZOMBIES[kindName]
	local zombie: Zombie = {
		id = freeId(),
		kind = Config.ZOMBIE_KIND_IDS[kindName],
		kindName = kindName,
		state = ZombiePacket.STATE_IDLE,
		position = Vector3.new(position.X, 0, position.Z),
		yaw = 0,
		health = stats.health,
		nextAttack = 0,
		dead = false,
		bleedUntil = 0,
		bleedDps = 0,
		lastAttacker = nil,
	}
	table.insert(zombies, zombie)
	byId[zombie.id] = zombie
	return zombie
end

-- Marks the zombie for removal on the next flush (no-op if already dying).
function HordeService.remove(zombie: Zombie)
	if zombie.dead then
		return
	end
	zombie.dead = true
	table.insert(dying, zombie)
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

local function flushDying()
	if #dying == 0 then
		return
	end
	local ids = table.create(#dying) :: { number }
	for _, zombie in dying do
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
	local killed = dying
	dying = {}
	removedRemote:FireAllClients(ids)
	for _, zombie in killed do
		if zombie.health <= 0 then
			HordeService.killed:fire(zombie, zombie.lastAttacker)
		end
	end
end

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

-- Nearest player by ground distance among those within vertical reach.
local function nearestTarget(position: Vector3): (Target?, number)
	local best: Target? = nil
	local bestDist = math.huge
	for _, t in targets do
		local offset = t.position - position
		if math.abs(offset.Y) <= VERTICAL_REACH then
			local d = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if d < bestDist then
				best, bestDist = t, d
			end
		end
	end
	return best, bestDist
end

local function face(z: Zombie, point: Vector3)
	local offset = point - z.position
	if offset.X ~= 0 or offset.Z ~= 0 then
		z.yaw = math.atan2(-offset.X, -offset.Z)
	end
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
	if owner and CollectionService:HasTag(owner, Tags.ClimbZone) then
		if Piles.handleBreach(z, owner, nx, nz, ix, iz, now) then
			return
		end
	end
	z.state = ZombiePacket.STATE_ATTACK
	face(z, FlowField.cellCenter(nx, nz))
	if owner and CollectionService:HasTag(owner, Tags.Barricade) and now >= z.nextAttack then
		z.nextAttack = now + stats.attackCooldown
		HordeService.barricadeHit:fire(
			owner,
			stats.damage * Config.BARRICADE.zombieDamageMultiplier
		)
	end
end

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
	local target, targetDist = nearestTarget(z.position)

	if target and targetDist <= stats.attackRange then
		z.state = ZombiePacket.STATE_ATTACK
		face(z, target.position)
		if now >= z.nextAttack then
			z.nextAttack = now + stats.attackCooldown
			target.humanoid:TakeDamage(stats.damage)
		end
		return
	end

	local ix, iz = FlowField.cellAt(z.position)
	local direction: Vector3
	local nx, nz = FlowField.nextCell(ix, iz)
	if nx and nz then
		if FlowField.kind(nx, nz) == FlowField.BREACH then
			handleBreach(z, stats, ix, iz, nx, nz, now)
			return
		end
		direction = FlowField.cellCenter(nx, nz) - z.position
	elseif target and FlowField.distance(ix, iz) == 0 then
		-- Same cell as a player: close the last few studs directly.
		direction = target.position - z.position
	else
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

local function spawnPoints(): { Vector3 }
	local points = {}
	for _, part in CollectionService:GetTagged(Tags.ZombieSpawn) do
		if part:IsA("BasePart") then
			table.insert(points, part.Position)
		end
	end
	return points
end

function HordeService.init()
	stateRemote = Net.zombieState()
	removedRemote = Net.zombieRemoved()
end

function HordeService.start()
	local map = workspace:WaitForChild("Map")
	local started = os.clock()
	FlowField.build(map)
	print(string.format("[Horde] flow field built in %.0f ms", (os.clock() - started) * 1000))

	local points = spawnPoints()
	local simAccumulator, replicateAccumulator, flowAccumulator, spawnAccumulator =
		0, 0, math.huge, 0

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		flushDying()

		flowAccumulator += dt
		if flowAccumulator >= HORDE.FLOW_RECOMPUTE_INTERVAL then
			flowAccumulator = 0
			refreshTargets()
			recomputeField()
		end

		if HORDE.DEBUG_KEEP_FULL and #points > 0 then
			spawnAccumulator += dt
			if spawnAccumulator >= HORDE.DEBUG_SPAWN_INTERVAL then
				spawnAccumulator = 0
				local base = points[math.random(#points)]
				local jitter = Vector3.new(math.random() * 8 - 4, 0, math.random() * 8 - 4)
				HordeService.spawn("Runner", base + jitter)
			end
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
