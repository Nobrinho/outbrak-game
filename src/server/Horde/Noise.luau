--!strict
-- Noise sources that pull nearby Runners (gunfire, explosions, a grenade used as a decoy).
-- Each source gets its own small distance field, flood-filled only out to its radius, so
-- attracted zombies path around walls (and pile up at the fort) exactly like they do toward
-- players. Repeated noise from the same source (a player holding the trigger) refreshes the
-- existing field instead of computing a new one per shot.

local FlowField = require(script.Parent.FlowField)

local Noise = {}

local MAX_ACTIVE = 6
local MERGE_DISTANCE = 10

export type Source = {
	position: Vector3,
	radius: number,
	radiusCells: number,
	expiresAt: number,
	key: any,
	field: buffer,
}

local active: { Source } = {}
local spareFields: { buffer } = {}

local function release(source: Source)
	table.insert(spareFields, source.field)
end

-- Creates (or refreshes) a noise source. `key` identifies who makes it, for merging; nil
-- never merges. Returns the source when a new field was computed, so the caller can attract
-- zombies to it, or nil when an existing source was only refreshed.
function Noise.emit(
	position: Vector3,
	radius: number,
	duration: number,
	key: any,
	now: number
): Source?
	if key ~= nil then
		for _, source in active do
			if
				source.key == key
				and (source.position - position).Magnitude < MERGE_DISTANCE
				and source.radius >= radius
			then
				source.expiresAt = math.max(source.expiresAt, now + duration)
				return nil
			end
		end
	end

	if #active >= MAX_ACTIVE then
		-- Drop the one closest to expiring.
		local oldest = 1
		for i, source in active do
			if source.expiresAt < active[oldest].expiresAt then
				oldest = i
			end
		end
		release(table.remove(active, oldest) :: Source)
	end

	local radiusCells = FlowField.cellsFor(radius)
	local field = table.remove(spareFields) or FlowField.newField()
	FlowField.computeField(field, { position }, radiusCells)
	local source: Source = {
		position = position,
		radius = radius,
		radiusCells = radiusCells,
		expiresAt = now + duration,
		key = key,
		field = field,
	}
	table.insert(active, source)
	return source
end

-- True if a zombie standing at `position` can hear `source` (within its walking radius).
function Noise.hears(source: Source, position: Vector3): boolean
	local ix, iz = FlowField.cellAt(position)
	return FlowField.distance(ix, iz, source.field) <= source.radiusCells
end

function Noise.isActive(source: Source, now: number): boolean
	return source.expiresAt > now and table.find(active, source) ~= nil
end

function Noise.step(now: number)
	for i = #active, 1, -1 do
		local source = active[i]
		if source.expiresAt <= now then
			table.remove(active, i)
			release(source)
		end
	end
end

function Noise.clear()
	for _, source in active do
		release(source)
	end
	table.clear(active)
end

return Noise
