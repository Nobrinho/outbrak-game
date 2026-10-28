--!strict
-- Keyframed clips for PoseController. Poses are not joint angles: PoseController places the
-- gun in chest space and reaches both arms to it (two-bone IK), so a clip moves the gun and
-- says where the left hand goes. A clip is a list of keys over normalized time [0, 1]; each
-- key sets some channels to absolute values, and a channel a key leaves out means "the base
-- pose", so clips start and end on whatever the character is doing. Between two keys every
-- channel eases with smoothstep, per segment.
--
-- Channels:
--   gx, gy, gz        gun grip offset from the hold position (studs, chest space)
--   gp, gyaw, gr      gun pitch (+ muzzle up), yaw (+ muzzle left), roll (radians)
--   lx, ly, lz        where the left hand holds the gun (gun space: -Z barrel, +Y top)
--   lw                0..1 blend of the left hand from the gun to a chest-space point:
--   bx, by, bz        that point (studs, chest space)
--   waist             extra chest yaw (radians)

local Clips = {}

export type Channel =
	"gx"
	| "gy"
	| "gz"
	| "gp"
	| "gyaw"
	| "gr"
	| "lx"
	| "ly"
	| "lz"
	| "lw"
	| "bx"
	| "by"
	| "bz"
	| "waist"
export type Pose = { [Channel]: number }
export type Key = { t: number, pose: Pose }
-- Something held in the left hand ("grenade", "mag", "shell") over [from, to).
export type Prop = { from: number, to: number, kind: string }
export type Clip = {
	keys: { Key },
	props: { Prop }?,
	-- The gun's own magazine is hidden over [from, to) (it's out, or in the left hand).
	magOut: { from: number, to: number }?,
	-- One-shot cues fired as time passes `t` ("dropMag": an empty magazine falls).
	events: { { t: number, name: string } }?,
}

local CHANNELS: { Channel } = {
	"gx",
	"gy",
	"gz",
	"gp",
	"gyaw",
	"gr",
	"lx",
	"ly",
	"lz",
	"lw",
	"bx",
	"by",
	"bz",
	"waist",
}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Writes the clip's pose at normalized time `t` into `base` (which holds the base pose).
function Clips.sample(clip: Clip, t: number, base: Pose)
	local keys = clip.keys
	local i = 1
	while i < #keys - 1 and t >= keys[i + 1].t do
		i += 1
	end
	local a, b = keys[i], keys[i + 1]
	local k = smooth((t - a.t) / math.max(b.t - a.t, 1e-6))
	for _, channel in CHANNELS do
		local from = a.pose[channel]
		local to = b.pose[channel]
		if from or to then
			local held = base[channel]
			local va = from or held
			base[channel] = va + ((to or held) - va) * k
		end
	end
end

-- Merges poses left to right into a new one.
local function mix(...: Pose): Pose
	local out: Pose = {}
	for _, pose in { ... } do
		for channel, value in pose do
			out[channel] = value
		end
	end
	return out
end

local function hand(at: Vector3): Pose
	return { lx = at.X, ly = at.Y, lz = at.Z }
end

local BASE: Pose = {}

Clips.melee = {
	-- Wind the gun up and back, bash it across, recover.
	keys = {
		{ t = 0, pose = BASE },
		{ t = 0.35, pose = { gy = 0.35, gz = 0.35, gp = 0.7, gyaw = 0.5, waist = 0.25 } },
		{ t = 0.7, pose = { gy = -0.1, gz = -0.45, gp = -0.35, gyaw = -0.6, waist = -0.3 } },
		{ t = 1, pose = BASE },
	},
} :: Clip

Clips.throw = {
	-- Overhand: the left hand leaves the gun, goes up and back with the grenade, whips forward.
	keys = {
		{ t = 0, pose = BASE },
		{
			t = 0.4,
			pose = { lw = 1, bx = -0.75, by = 1.3, bz = 0.5, gp = -0.2, gy = -0.1, waist = -0.3 },
		},
		{ t = 0.62, pose = { lw = 1, bx = -0.3, by = 0.7, bz = -1.6, waist = 0.25 } },
		{ t = 1, pose = BASE },
	},
	props = { { from = 0, to = 0.42, kind = "grenade" } },
} :: Clip

-- Magazine reload: the gun comes in and rolls, the left hand strips the empty magazine (it
-- falls), fetches a fresh one from the belt, seats it, then racks the action.
local BELT: Pose = { lw = 1, bx = -0.7, by = -1.0, bz = -0.45 }
local function magReload(well: Vector3, rack: Vector3, pulled: Vector3): Clip
	local tilt: Pose = { gr = 0.55, gp = 0.15, gy = -0.12, gz = 0.2 }
	local seat = hand(well + Vector3.new(0, -0.15, 0))
	return {
		keys = {
			{ t = 0, pose = BASE },
			{ t = 0.12, pose = mix(tilt, hand(well)) },
			{ t = 0.18, pose = mix(tilt, hand(well)) },
			{ t = 0.38, pose = mix(tilt, BELT) },
			{ t = 0.43, pose = mix(tilt, BELT) },
			{ t = 0.6, pose = mix(tilt, seat) },
			{ t = 0.68, pose = mix({ gr = 0.3, gp = 0.05, gy = -0.06, gz = 0.1 }, hand(well)) },
			{ t = 0.8, pose = mix({ gr = 0.15 }, hand(rack)) },
			{ t = 0.87, pose = mix({ gr = 0.15 }, hand(pulled)) },
			{ t = 1, pose = BASE },
		},
		props = { { from = 0.4, to = 0.66, kind = "mag" } },
		magOut = { from = 0.16, to = 0.66 },
		events = { { t = 0.16, name = "dropMag" } },
	}
end

-- Rifles/SMGs: charging handle on the receiver's left side.
local RACK, PULLED = Vector3.new(-0.22, 0.28, -0.15), Vector3.new(-0.22, 0.28, 0.15)

-- Shotgun: gun rolled to show the loading port, shells pushed in one by one from the belt,
-- then a pump.
local function shellReload(shells: number): Clip
	local roll: Pose = { gr = -0.6, gp = 0.1, gz = 0.15 }
	local pouch = mix(roll, { lw = 1, bx = -0.7, by = -0.9, bz = -0.5 })
	local port = mix(roll, hand(Vector3.new(0, -0.12, -0.05)))
	local keys: { Key } = { { t = 0, pose = BASE }, { t = 0.08, pose = port } }
	local props: { Prop } = {}
	local start, finish = 0.08, 0.84
	local cycle = (finish - start) / shells
	for i = 0, shells - 1 do
		local t0 = start + i * cycle
		table.insert(keys, { t = t0 + cycle * 0.45, pose = pouch })
		table.insert(keys, { t = t0 + cycle, pose = port })
		table.insert(props, { from = t0 + cycle * 0.45, to = t0 + cycle * 0.95, kind = "shell" })
	end
	table.insert(keys, { t = 0.9, pose = hand(Vector3.new(0, 0, -0.65)) })
	table.insert(keys, { t = 0.95, pose = BASE })
	table.insert(keys, { t = 1, pose = BASE })
	return { keys = keys, props = props }
end

-- Pump after each shotgun shot: hold, rack the fore-end back, slam it forward.
Clips.pump = {
	keys = {
		{ t = 0, pose = BASE },
		{ t = 0.3, pose = BASE },
		{ t = 0.55, pose = hand(Vector3.new(0, 0, -0.65)) },
		{ t = 0.8, pose = BASE },
		{ t = 1, pose = BASE },
	},
} :: Clip

-- Drawing the weapon after a switch: it comes up from the hip, muzzle down, into the hold.
-- (The holster is covered by the model swap: the old weapon simply leaves the hand.)
Clips.equip = {
	keys = {
		{
			t = 0,
			pose = { gx = -0.15, gy = -0.65, gz = 0.35, gp = -1.1, gyaw = 0.6, gr = 0.3, lw = 1 },
		},
		{ t = 0.55, pose = { gy = -0.1, gp = -0.15, lw = 0.3 } },
		{ t = 1, pose = BASE },
	},
} :: Clip

-- Melee weapon swings, replacing the gun bash when a melee weapon is in hand.
local SWINGS: { [string]: Clip } = {
	-- Knife: short wind-up to the right, fast slash across.
	Knife = {
		keys = {
			{ t = 0, pose = BASE },
			{ t = 0.3, pose = { gx = 0.25, gz = 0.3, gyaw = 0.9, waist = 0.3 } },
			{ t = 0.55, pose = { gx = -0.55, gz = -0.5, gyaw = -0.9, waist = -0.35 } },
			{ t = 1, pose = BASE },
		},
	},
	-- Bat: cocked over the shoulder, big horizontal swing through the chest line.
	Bat = {
		keys = {
			{ t = 0, pose = BASE },
			{ t = 0.35, pose = { gy = 0.25, gz = 0.4, gyaw = 0.8, gp = 0.3, waist = 0.4 } },
			{ t = 0.6, pose = { gx = -0.45, gz = -0.6, gyaw = -1.4, gp = -1.2, waist = -0.5 } },
			{ t = 1, pose = BASE },
		},
	},
}

local LONG_RELOAD = magReload(Vector3.new(0, -0.72, -0.5), RACK, PULLED)
local RELOADS: { [string]: Clip } = {
	-- Pistol: magazine out of the grip's base, then the slide is pulled over the top.
	Pistol = magReload(
		Vector3.new(0, -0.62, 0.12),
		Vector3.new(0, 0.32, -0.3),
		Vector3.new(0, 0.32, 0)
	),
	SMG = LONG_RELOAD,
	Rifle = magReload(Vector3.new(0, -0.68, -0.6), RACK, PULLED),
	AK47 = magReload(Vector3.new(0, -0.8, -0.65), RACK, PULLED),
	Shotgun = shellReload(4),
}

-- The clip for an action; reloads and swings depend on the weapon in hand.
function Clips.get(kind: string, gun: string): Clip?
	if kind == "reload" then
		return RELOADS[gun] or LONG_RELOAD
	elseif kind == "melee" and SWINGS[gun] then
		return SWINGS[gun]
	end
	local clip = (Clips :: any)[kind]
	return if type(clip) == "table" then clip else nil
end

return table.freeze(Clips)
