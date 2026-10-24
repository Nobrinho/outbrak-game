--!strict
-- Shape of the saved player profile, its version and the migrations between versions. Data
-- outlives code: bump VERSION and add a migration step whenever the shape changes, never edit
-- fields in place.

local ProfileSchema = {}

ProfileSchema.VERSION = 1
ProfileSchema.MAX_RECEIPTS = 50 -- recent purchase ids kept to make grants idempotent

export type Profile = {
	version: number,
	xp: number, -- lifetime XP; the level is derived from it
	kills: number,
	matches: number,
	extractions: number,
	boostUntil: number, -- os.time() when the 2x XP boost ends
	receipts: { string }, -- most recent processed developer-product purchase ids
}

local DEFAULT: Profile = {
	version = ProfileSchema.VERSION,
	xp = 0,
	kills = 0,
	matches = 0,
	extractions = 0,
	boostUntil = 0,
	receipts = {},
}

local MIGRATIONS: { [number]: (any) -> any } = {
	-- [1] = function(data) ... return data end, -- v1 → v2 goes here
}

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

function ProfileSchema.new(): Profile
	return deepCopy(DEFAULT)
end

-- Brings stored data up to the current version and fills any missing fields with defaults.
function ProfileSchema.migrate(data: any): Profile
	if typeof(data) ~= "table" then
		return ProfileSchema.new()
	end
	data.version = if typeof(data.version) == "number" then data.version else 1
	while data.version < ProfileSchema.VERSION do
		local step = MIGRATIONS[data.version]
		if not step then
			error(`missing profile migration from v{data.version}`)
		end
		data = step(data)
		data.version += 1
	end
	for key, value in DEFAULT :: any do
		if data[key] == nil then
			data[key] = deepCopy(value)
		end
	end
	return data
end

-- Plain, JSON-safe copy of the in-memory profile for saving.
function ProfileSchema.serialize(profile: Profile): Profile
	local out = deepCopy(profile)
	while #out.receipts > ProfileSchema.MAX_RECEIPTS do
		table.remove(out.receipts, 1)
	end
	return out
end

return ProfileSchema
