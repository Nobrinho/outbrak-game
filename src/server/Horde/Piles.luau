--!strict
-- Zombie pyramids. Zombies that reach a ClimbZone (the corral chain-link fence, the silo)
-- from outside stack into a pile against it, perLayer zombies per layer. Once the pile plus a
-- zombie's reach is as tall as the zone's ClimbHeight, newcomers run up the pile, over the
-- top and drop down on the far side. Like the rest of the horde this is pure server data:
-- the positions written here replicate with everything else.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local ZombiePacket = require(Shared.ZombiePacket)
local FlowField = require(script.Parent.FlowField)

local Piles = {}

local PILE = Config.PILE
local CELL = Config.HORDE.CELL_SIZE
local GRID = 4 -- cells per pile along a wall, so a long wall gets several separate piles
local LANDING_RADIUS = 4
local UP = Vector3.yAxis

-- The fields of a horde zombie this module reads and writes.
export type Member = { position: Vector3, yaw: number, state: number }

type Pile = {
	anchor: Vector3, -- ground point on the zone's outer face
	outward: Vector3, -- flat unit vector from the zone toward the approach side
	lateral: Vector3,
	climbHeight: number,
	landing: Vector3?,
	members: { Member },
	lastActivity: number, -- last join or climb
	lastJoin: number,
	nextRelease: number,
}

type Joined = { pile: Pile, from: Vector3, joinedAt: number }
type Climb = { points: { Vector3 }, startedAt: number, yaws: { number } }

local piles: { [BasePart]: { [number]: Pile } } = {}
local joined: { [Member]: Joined } = {}
local climbing: { [Member]: Climb } = {}

local function yawFacing(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

local function layersOf(pile: Pile): number
	return math.ceil(#pile.members / PILE.perLayer)
end

local function climbable(pile: Pile): boolean
	return pile.landing ~= nil
		and layersOf(pile) * PILE.layerHeight + PILE.reach >= pile.climbHeight
end

-- Is the approaching zombie on the fort side of the zone? (Zones carry an `Inside` point.)
local function fromInside(zone: BasePart, from: Vector3): boolean
	local inside = zone:GetAttribute("Inside")
	if typeof(inside) ~= "Vector3" then
		return false
	end
	local center = Vector3.new(zone.Position.X, 0, zone.Position.Z)
	local toInside = Vector3.new(inside.X, 0, inside.Z) - center
	return (from - center):Dot(toInside) > 0
end

-- Nearest open cell on the far side of the zone, where climbers land.
local function findLanding(anchor: Vector3, outward: Vector3, bx: number, bz: number): Vector3?
	local best: Vector3? = nil
	local bestDist = math.huge
	for dx = -LANDING_RADIUS, LANDING_RADIUS do
		for dz = -LANDING_RADIUS, LANDING_RADIUS do
			local cx, cz = bx + dx, bz + dz
			if FlowField.kind(cx, cz) == FlowField.FREE then
				local center = FlowField.cellCenter(cx, cz)
				local offset = center - anchor
				if offset:Dot(outward) < -1.5 and offset.Magnitude < bestDist then
					best, bestDist = center, offset.Magnitude
				end
			end
		end
	end
	return best
end

local function newPile(
	zone: BasePart,
	outward: Vector3,
	bx: number,
	bz: number,
	from: Vector3
): Pile
	-- Find the zone's actual surface by casting from the approach cell back toward it.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { zone }
	local origin = Vector3.new(from.X, 2, from.Z)
	local hit = workspace:Raycast(origin, -outward * CELL * 3, params)
	local anchor = if hit
		then Vector3.new(hit.Position.X, 0, hit.Position.Z)
		else FlowField.cellCenter(bx, bz) + outward * CELL / 2

	local height = zone:GetAttribute("ClimbHeight")
	return {
		anchor = anchor,
		outward = outward,
		lateral = Vector3.new(-outward.Z, 0, outward.X),
		climbHeight = if typeof(height) == "number" then height else zone.Size.Y,
		landing = findLanding(anchor, outward, bx, bz),
		members = {},
		lastActivity = os.clock(),
		lastJoin = os.clock(),
		nextRelease = 0,
	}
end

local function startClimb(z: Member, pile: Pile, now: number)
	local top = pile.anchor + pile.outward * 0.9 + UP * (layersOf(pile) * PILE.layerHeight + 0.3)
	local over = pile.anchor - pile.outward * 0.4 + UP * (pile.climbHeight + 0.4)
	local landing = pile.landing :: Vector3
	local inward = yawFacing(-pile.outward)
	climbing[z] = {
		points = { z.position, top, over, landing },
		yaws = { inward, inward, yawFacing(landing - over) },
		startedAt = now,
	}
	z.state = ZombiePacket.STATE_CLIMB
	pile.lastActivity = now
end

function Piles.isBusy(z: Member): boolean
	return joined[z] ~= nil or climbing[z] ~= nil
end

-- Called when a walking zombie's next cell is part of `zone`. Returns true if the zombie is
-- now piling or climbing (the caller stops moving it); false means "hold here".
function Piles.handleBreach(
	z: Member,
	zone: BasePart,
	bx: number,
	bz: number,
	fx: number,
	fz: number,
	now: number
): boolean
	if Piles.isBusy(z) then
		return true
	end
	local from = FlowField.cellCenter(fx, fz)
	if fromInside(zone, from) then
		return false
	end

	local dx, dz = fx - bx, fz - bz
	local outward: Vector3, dirCode: number
	if math.abs(dx) >= math.abs(dz) then
		outward, dirCode = Vector3.new(math.sign(dx), 0, 0), if dx > 0 then 0 else 1
	else
		outward, dirCode = Vector3.new(0, 0, math.sign(dz)), if dz > 0 then 2 else 3
	end
	local key = ((bx // GRID) * 1000 + (bz // GRID)) * 4 + dirCode

	local byKey = piles[zone]
	if not byKey then
		byKey = {}
		piles[zone] = byKey
	end
	local pile = byKey[key]
	if not pile then
		pile = newPile(zone, outward, bx, bz, from)
		byKey[key] = pile
	end

	if climbable(pile) then
		startClimb(z, pile, now)
		return true
	end
	if pile.landing == nil then
		-- Nowhere to land: cap the pile at the height that would have been enough.
		local maxLayers = math.ceil((pile.climbHeight - PILE.reach) / PILE.layerHeight)
		if layersOf(pile) >= maxLayers then
			return false
		end
	end

	table.insert(pile.members, z)
	joined[z] = { pile = pile, from = z.position, joinedAt = now }
	z.state = ZombiePacket.STATE_PILE
	pile.lastActivity = now
	pile.lastJoin = now
	return true
end

function Piles.forget(z: Member)
	local j = joined[z]
	if j then
		local index = table.find(j.pile.members, z)
		if index then
			-- table.remove keeps order, so everyone above settles one slot down.
			table.remove(j.pile.members, index)
		end
		joined[z] = nil
	end
	climbing[z] = nil
end

local function disband(pile: Pile)
	for _, m in pile.members do
		joined[m] = nil
		m.position = Vector3.new(m.position.X, 0, m.position.Z)
		m.state = ZombiePacket.STATE_IDLE
	end
	table.clear(pile.members)
end

local function layoutPile(pile: Pile, now: number)
	local count = #pile.members
	local topLayer = (count - 1) // PILE.perLayer
	local yaw = yawFacing(-pile.outward)
	for i, m in pile.members do
		local layer = (i - 1) // PILE.perLayer
		local column = (i - 1) % PILE.perLayer - (PILE.perLayer - 1) / 2
		-- Lower layers sit further out, so the pile reads as a ramp up the wall.
		local slot = pile.anchor
			+ pile.outward * (0.9 + (topLayer - layer) * 0.8)
			+ pile.lateral * (column * 1.5 + (layer % 2) * 0.6)
			+ UP * (layer * PILE.layerHeight)
		local j = joined[m]
		local alpha = if j then math.min(1, (now - j.joinedAt) / PILE.joinTime) else 1
		m.position = if j then j.from:Lerp(slot, alpha) else slot
		m.yaw = yaw
		m.state = ZombiePacket.STATE_PILE
	end
end

local function stepClimb(z: Member, c: Climb, now: number): boolean
	local elapsed = now - c.startedAt
	for i, duration in PILE.climbTimes do
		if elapsed < duration then
			z.position = c.points[i]:Lerp(c.points[i + 1], elapsed / duration)
			z.yaw = c.yaws[i]
			return false
		end
		elapsed -= duration
	end
	z.position = c.points[#c.points]
	z.yaw = c.yaws[#c.yaws]
	z.state = ZombiePacket.STATE_WALK
	return true
end

-- Positions every piled and climbing zombie. Call once per simulation step.
function Piles.step(now: number)
	for _, byKey in piles do
		for key, pile in byKey do
			if #pile.members > 0 and pile.landing then
				-- The pile flows over the top: once it's tall enough, or once nobody new has
				-- joined for a while (the end of a wave), the top zombie climbs every
				-- releaseInterval. Without this the zombies forming the pile never leave and a
				-- wave can't finish.
				local stalled = now - pile.lastJoin > PILE.stallTime
				if (climbable(pile) or stalled) and now >= pile.nextRelease then
					pile.nextRelease = now + PILE.releaseInterval
					local top = table.remove(pile.members) :: Member
					joined[top] = nil
					startClimb(top, pile, now)
				end
			elseif #pile.members > 0 and now - pile.lastActivity > PILE.disbandAfter then
				disband(pile) -- nowhere to land: it can never get over
			end
			if #pile.members == 0 and now - pile.lastActivity > PILE.disbandAfter then
				byKey[key] = nil
			else
				layoutPile(pile, now)
			end
		end
	end
	for z, c in climbing do
		if stepClimb(z, c, now) then
			climbing[z] = nil
		end
	end
end

return Piles
