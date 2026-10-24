--!strict
-- Low-poly zombie rigs (docs/DEFINICOES.md §3): a shared base body plus a few parts per kind
-- for a readable silhouette — Runner lean and ragged, Bull in riot plates, Creeper bloated
-- with glowing pustules, Brute hunched with huge fists. No textures; colour and shape only.
-- Every part belongs to an animation role; the renderer rotates arms and legs around their
-- role's pivot and bobs the body and head.
--
-- Offsets are relative to the feet with the zombie facing -Z, before the kind's scale.

local Types = require(script.Parent.Parent.Types)

local ZombieRigs = {}

export type Role = "Body" | "Head" | "ArmL" | "ArmR" | "LegL" | "LegR"
export type Tone = "skin" | "shirt" | "pants" | "eyes" | "dark" | "accent" | "glow"

export type PartSpec = {
	name: string,
	role: Role,
	tone: Tone,
	size: Vector3,
	offset: Vector3,
	shape: Enum.PartType?,
}

export type Variant = { skin: Color3, shirt: Color3, pants: Color3 }

-- Rotation pivots: hips for legs, shoulders for arms; body and head only bob.
ZombieRigs.PIVOTS = table.freeze({
	Body = Vector3.zero,
	Head = Vector3.zero,
	ArmL = Vector3.new(-1.12, 3.75, 0),
	ArmR = Vector3.new(1.12, 3.75, 0),
	LegL = Vector3.new(-0.45, 2, 0),
	LegR = Vector3.new(0.45, 2, 0),
}) :: { [Role]: Vector3 }

local EYES = Color3.fromRGB(255, 120, 20)
local GLOW = Color3.fromRGB(170, 255, 60)
local DARK = Color3.fromRGB(40, 25, 25)
ZombieRigs.FUSE_COLOR = Color3.fromRGB(230, 30, 30)

local function spec(
	name: string,
	role: Role,
	tone: Tone,
	size: Vector3,
	offset: Vector3,
	shape: Enum.PartType?
): PartSpec
	return { name = name, role = role, tone = tone, size = size, offset = offset, shape = shape }
end

local function base(): { PartSpec }
	return {
		spec("LegL", "LegL", "pants", Vector3.new(0.7, 2, 0.7), Vector3.new(-0.45, 1, 0)),
		spec("LegR", "LegR", "pants", Vector3.new(0.7, 2, 0.7), Vector3.new(0.45, 1, 0)),
		spec("Hips", "Body", "pants", Vector3.new(1.7, 0.6, 0.95), Vector3.new(0, 2.15, 0)),
		-- Slight forward hunch: the chest sits a little ahead of the hips.
		spec("Torso", "Body", "shirt", Vector3.new(1.8, 1.7, 1), Vector3.new(0, 3.25, -0.1)),
		spec("Head", "Head", "skin", Vector3.new(1.15, 1.15, 1.15), Vector3.new(0, 4.6, -0.3)),
		spec("Jaw", "Head", "dark", Vector3.new(0.8, 0.28, 0.5), Vector3.new(0, 4.08, -0.65)),
		spec("Eyes", "Head", "eyes", Vector3.new(0.85, 0.2, 0.1), Vector3.new(0, 4.75, -0.88)),
		spec("ArmL", "ArmL", "skin", Vector3.new(0.45, 0.45, 2), Vector3.new(-1.12, 3.75, -0.85)),
		spec("ArmR", "ArmR", "skin", Vector3.new(0.45, 0.45, 2), Vector3.new(1.12, 3.75, -0.85)),
		spec(
			"SleeveL",
			"ArmL",
			"shirt",
			Vector3.new(0.58, 0.58, 0.6),
			Vector3.new(-1.12, 3.75, -0.1)
		),
		spec(
			"SleeveR",
			"ArmR",
			"shirt",
			Vector3.new(0.58, 0.58, 0.6),
			Vector3.new(1.12, 3.75, -0.1)
		),
	}
end

local function withExtras(extras: { PartSpec }): { PartSpec }
	local parts = base()
	for _, extra in extras do
		table.insert(parts, extra)
	end
	return table.freeze(parts)
end

ZombieRigs.RIGS = table.freeze({
	Runner = withExtras({}),
	-- Riot gear: shoulder plates, chest plate, helmet.
	Bull = withExtras({
		spec("PlateL", "Body", "accent", Vector3.new(1, 0.5, 1.2), Vector3.new(-1.1, 4.15, 0)),
		spec("PlateR", "Body", "accent", Vector3.new(1, 0.5, 1.2), Vector3.new(1.1, 4.15, 0)),
		spec("Chest", "Body", "accent", Vector3.new(1.9, 1.3, 0.3), Vector3.new(0, 3.3, -0.65)),
		spec("Helmet", "Head", "accent", Vector3.new(1.3, 0.6, 1.3), Vector3.new(0, 5.05, -0.3)),
	}),
	-- Swollen belly and pustules that glow (and flash red on the fuse).
	Creeper = withExtras({
		spec(
			"Belly",
			"Body",
			"skin",
			Vector3.new(1.9, 1.9, 1.9),
			Vector3.new(0, 2.95, -0.4),
			Enum.PartType.Ball
		),
		spec(
			"PustuleA",
			"Body",
			"glow",
			Vector3.new(0.5, 0.5, 0.5),
			Vector3.new(0.6, 3.4, -1.25),
			Enum.PartType.Ball
		),
		spec(
			"PustuleB",
			"Body",
			"glow",
			Vector3.new(0.4, 0.4, 0.4),
			Vector3.new(-0.5, 2.6, -1.3),
			Enum.PartType.Ball
		),
		spec(
			"PustuleC",
			"Head",
			"glow",
			Vector3.new(0.35, 0.35, 0.35),
			Vector3.new(0.4, 5, -0.6),
			Enum.PartType.Ball
		),
	}),
	-- Hunched back, heavy trapezius, fists like boulders.
	Brute = withExtras({
		spec("FistL", "ArmL", "skin", Vector3.new(0.95, 0.95, 0.95), Vector3.new(-1.12, 3.75, -2)),
		spec("FistR", "ArmR", "skin", Vector3.new(0.95, 0.95, 0.95), Vector3.new(1.12, 3.75, -2)),
		spec("Hunch", "Body", "shirt", Vector3.new(1.6, 1, 1), Vector3.new(0, 4.15, 0.5)),
		spec("TrapL", "Body", "skin", Vector3.new(0.7, 0.6, 0.9), Vector3.new(-0.7, 4.15, 0)),
		spec("TrapR", "Body", "skin", Vector3.new(0.7, 0.6, 0.9), Vector3.new(0.7, 4.15, 0)),
	}),
}) :: { [Types.ZombieKind]: { PartSpec } }

-- Desaturated clothing, so the crowd varies without stealing attention from the eyes.
local RUNNER_SHIRTS = {
	Color3.fromRGB(150, 145, 130),
	Color3.fromRGB(80, 90, 105),
	Color3.fromRGB(110, 52, 46),
	Color3.fromRGB(84, 92, 62),
	Color3.fromRGB(95, 75, 55),
	Color3.fromRGB(70, 70, 74),
}
local RUNNER_PANTS = {
	Color3.fromRGB(55, 60, 72),
	Color3.fromRGB(72, 62, 50),
	Color3.fromRGB(42, 46, 52),
	Color3.fromRGB(88, 82, 64),
}
local RUNNER_SKINS = {
	Color3.fromRGB(122, 132, 110),
	Color3.fromRGB(132, 128, 112),
	Color3.fromRGB(108, 118, 104),
}

local FIXED: { [Types.ZombieKind]: Variant } = {
	Bull = {
		skin = Color3.fromRGB(110, 104, 96),
		shirt = Color3.fromRGB(58, 62, 72),
		pants = Color3.fromRGB(45, 48, 55),
	},
	Creeper = {
		skin = Color3.fromRGB(160, 176, 70),
		shirt = Color3.fromRGB(104, 118, 40),
		pants = Color3.fromRGB(60, 64, 40),
	},
	Brute = {
		skin = Color3.fromRGB(104, 92, 84),
		shirt = Color3.fromRGB(58, 44, 38),
		pants = Color3.fromRGB(45, 38, 34),
	},
}

-- Colours for one zombie; `seed` (its id) keeps a Runner's outfit stable between LOD swaps.
function ZombieRigs.variant(kind: Types.ZombieKind, seed: number): Variant
	local fixed = FIXED[kind]
	if fixed then
		return fixed
	end
	return {
		skin = RUNNER_SKINS[seed % #RUNNER_SKINS + 1],
		shirt = RUNNER_SHIRTS[(seed // 3) % #RUNNER_SHIRTS + 1],
		pants = RUNNER_PANTS[(seed // 7) % #RUNNER_PANTS + 1],
	}
end

function ZombieRigs.color(tone: Tone, variant: Variant, kind: Types.ZombieKind): Color3
	if tone == "skin" then
		return variant.skin
	elseif tone == "shirt" then
		return variant.shirt
	elseif tone == "pants" then
		return variant.pants
	elseif tone == "eyes" then
		return EYES
	elseif tone == "glow" then
		return GLOW
	elseif tone == "accent" then
		return if kind == "Bull" then Color3.fromRGB(70, 74, 80) else Color3.fromRGB(60, 50, 45)
	end
	return DARK
end

function ZombieRigs.material(tone: Tone): Enum.Material
	if tone == "eyes" or tone == "glow" then
		return Enum.Material.Neon
	elseif tone == "accent" then
		return Enum.Material.Metal
	end
	return Enum.Material.SmoothPlastic
end

return ZombieRigs
