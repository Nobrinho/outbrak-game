--!strict
-- Hit geometry shared by client and server. Zombies have no parts on the server, so both
-- sides test rays against the same analytic shapes: a vertical cylinder for the body and a
-- sphere for the head, scaled per zombie kind. Map line-of-sight ignores barricades and
-- ShootThrough parts (rail fences), which players shoot through.

local CollectionService = game:GetService("CollectionService")

local Tags = require(script.Parent.Tags)

local Hitscan = {}

local BODY_RADIUS = 1
local BODY_TOP = 4
local HEAD_HEIGHT = 4.6
local HEAD_RADIUS = 0.8

Hitscan.CHEST_HEIGHT = 3

local mapParams: RaycastParams? = nil

local function params(): RaycastParams?
	if mapParams then
		return mapParams
	end
	local map = workspace:FindFirstChild("Map")
	if not map then
		return nil
	end
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = { map }
	mapParams = p
	return p
end

-- Distance along a unit ray to the zombie standing at `feet`, or nil. Second value is true
-- when the closest hit is the head.
function Hitscan.rayZombie(
	origin: Vector3,
	direction: Vector3,
	maxDistance: number,
	feet: Vector3,
	scale: number
): (number?, boolean)
	local best: number? = nil
	local head = false

	-- Head sphere.
	local toOrigin = origin - (feet + Vector3.new(0, HEAD_HEIGHT * scale, 0))
	local r = HEAD_RADIUS * scale
	local b = toOrigin:Dot(direction)
	local disc = b * b - (toOrigin:Dot(toOrigin) - r * r)
	if disc >= 0 then
		local s = math.sqrt(disc)
		local t = if -b - s >= 0 then -b - s else -b + s
		if t >= 0 and t <= maxDistance then
			best, head = t, true
		end
	end

	-- Body cylinder (XZ circle, clipped to [feet, BODY_TOP]).
	local ox, oz = origin.X - feet.X, origin.Z - feet.Z
	local dx, dz = direction.X, direction.Z
	local a = dx * dx + dz * dz
	if a > 1e-6 then
		local rb = BODY_RADIUS * scale
		local bb = ox * dx + oz * dz
		local disc2 = bb * bb - a * (ox * ox + oz * oz - rb * rb)
		if disc2 >= 0 then
			local s = math.sqrt(disc2)
			for _, t in { (-bb - s) / a, (-bb + s) / a } do
				if t >= 0 and t <= maxDistance and (best == nil or t < best) then
					local y = origin.Y + direction.Y * t - feet.Y
					if y >= 0 and y <= BODY_TOP * scale then
						best, head = t, false
						break
					end
				end
			end
		end
	end

	return best, head
end

local function shootThrough(instance: Instance): boolean
	return CollectionService:HasTag(instance, Tags.Barricade)
		or CollectionService:HasTag(instance, Tags.ShootThrough)
end

-- Distance along a unit ray to the first solid map surface, capped at max.
function Hitscan.mapDistance(origin: Vector3, direction: Vector3, maxDistance: number): number
	local p = params()
	if not p then
		return maxDistance
	end
	local travelled = 0
	local from = origin
	for _ = 1, 6 do
		local result = workspace:Raycast(from, direction * (maxDistance - travelled), p)
		if not result then
			return maxDistance
		end
		travelled += result.Distance
		if not shootThrough(result.Instance) then
			return travelled
		end
		from = result.Position + direction * 0.05
		travelled += 0.05
		if travelled >= maxDistance then
			return maxDistance
		end
	end
	return travelled
end

function Hitscan.clearLine(from: Vector3, to: Vector3): boolean
	local offset = to - from
	local distance = offset.Magnitude
	if distance < 1e-3 then
		return true
	end
	return Hitscan.mapDistance(from, offset / distance, distance) >= distance - 0.5
end

-- Visible if either the chest or the head can be seen (fences hide legs, not heads).
function Hitscan.canSeeZombie(eye: Vector3, feet: Vector3, scale: number): boolean
	return Hitscan.clearLine(eye, feet + Vector3.new(0, HEAD_HEIGHT * scale, 0))
		or Hitscan.clearLine(eye, feet + Vector3.new(0, Hitscan.CHEST_HEIGHT * scale, 0))
end

return Hitscan
