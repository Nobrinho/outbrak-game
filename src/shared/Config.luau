--!strict
-- Tunable gameplay values (see docs/DEFINICOES.md). NOTE: replicated to clients —
-- nothing secret here, and the server never trusts a client-reported value from this file.

local Types = require(script.Parent.Types)

export type ZombieStats = {
	health: number,
	speed: number,
	damage: number,
	attackRange: number,
	attackCooldown: number,
	scale: number, -- visual size multiplier for the client rig
}

local ZOMBIES: { [Types.ZombieKind]: ZombieStats } = {
	Runner = {
		health = 50,
		speed = 22,
		damage = 10,
		attackRange = 3,
		attackCooldown = 1,
		scale = 1,
	},
	Bull = {
		health = 600,
		speed = 14,
		damage = 35,
		attackRange = 4,
		attackCooldown = 1.5,
		scale = 1.5,
	},
	Creeper = {
		health = 80,
		speed = 16,
		damage = 60,
		attackRange = 4,
		attackCooldown = 1,
		scale = 1.2,
	},
	Brute = {
		health = 3000,
		speed = 12,
		damage = 50,
		attackRange = 6,
		attackCooldown = 2,
		scale = 2.4,
	},
}

export type GunName = "Pistol" | "SMG" | "Shotgun" | "Rifle" | "AK47"
export type MeleeName = "Knife" | "Bat"

export type GunStats = {
	displayName: string,
	damage: number, -- per pellet
	fireRate: number, -- shots per second while the trigger is held
	magSize: number,
	reserveMax: number,
	reloadTime: number,
	range: number,
	spread: number, -- degrees, halved while aiming
	pellets: number,
	headMultiplier: number,
}

export type MeleeStats = {
	displayName: string,
	damage: number,
	cooldown: number,
	range: number,
	arc: number, -- degrees in front of the player
	maxTargets: number,
	bleedDps: number,
	bleedTime: number,
}

local GUNS: { [GunName]: GunStats } = {
	Pistol = {
		displayName = "Pistola",
		damage = 20,
		fireRate = 5,
		magSize = 12,
		reserveMax = 72,
		reloadTime = 1.3,
		range = 150,
		spread = 1.2,
		pellets = 1,
		headMultiplier = 2,
	},
	SMG = {
		displayName = "Submetralhadora",
		damage = 14,
		fireRate = 12,
		magSize = 30,
		reserveMax = 180,
		reloadTime = 1.8,
		range = 110,
		spread = 2.5,
		pellets = 1,
		headMultiplier = 1.5,
	},
	Shotgun = {
		displayName = "Escopeta",
		damage = 12,
		fireRate = 1.2,
		magSize = 6,
		reserveMax = 36,
		reloadTime = 2.4,
		range = 45,
		spread = 6,
		pellets = 8,
		headMultiplier = 1.5,
	},
	Rifle = {
		displayName = "Rifle",
		damage = 24,
		fireRate = 9,
		magSize = 30,
		reserveMax = 150,
		reloadTime = 2,
		range = 200,
		spread = 1.5,
		pellets = 1,
		headMultiplier = 2,
	},
	AK47 = {
		displayName = "AK-47",
		damage = 32,
		fireRate = 10,
		magSize = 30,
		reserveMax = 120,
		reloadTime = 2.3,
		range = 200,
		spread = 2.6,
		pellets = 1,
		headMultiplier = 2,
	},
}

local MELEE: { [MeleeName]: MeleeStats } = {
	Knife = {
		displayName = "Faca",
		damage = 35,
		cooldown = 0.45,
		range = 5.5,
		arc = 70,
		maxTargets = 1,
		bleedDps = 0,
		bleedTime = 0,
	},
	Bat = {
		displayName = "Taco com pregos",
		damage = 60,
		cooldown = 0.8,
		range = 6.5,
		arc = 100,
		maxTargets = 3,
		bleedDps = 8,
		bleedTime = 3,
	},
}

return table.freeze({
	AUTOSAVE_INTERVAL = 60,
	MAX_PLAYERS = 4,

	ZOMBIES = table.freeze(ZOMBIES),
	-- Wire ids for ZombieKind (one byte in the replication packet).
	ZOMBIE_KIND_IDS = table.freeze({ Runner = 1, Bull = 2, Creeper = 3, Brute = 4 }) :: { [Types.ZombieKind]: number },
	ZOMBIE_KINDS_BY_ID = table.freeze({ "Runner", "Bull", "Creeper", "Brute" }) :: { Types.ZombieKind },

	GUNS = table.freeze(GUNS),
	MELEE = table.freeze(MELEE),
	GRENADE = table.freeze({
		damage = 150, -- at the center, falling to half at the edge
		radius = 14,
		fuse = 2,
		maxCarry = 2,
		throwSpeed = 90,
		throwLift = 30,
		cooldown = 0.8,
	}),
	-- Starting loadout until the shop (week 7). Change `gun` to test the other guns.
	LOADOUT = table.freeze({
		gun = "Pistol" :: GunName,
		melee = "Knife" :: MeleeName,
	}),
	AMMO_BOX_COOLDOWN = 30,
	-- Prints why shots are accepted/rejected to the server Output. Turn off before release.
	DEBUG_COMBAT = true,
	AIM_ASSIST_DEGREES = 4, -- touch only: near-misses inside this cone count as body hits

	HORDE = table.freeze({
		MAX_ALIVE = 120,
		SIM_HZ = 20,
		REPLICATION_HZ = 10,
		FLOW_RECOMPUTE_INTERVAL = 0.5,
		CELL_SIZE = 4,
		HALF_EXTENT = 240, -- flow field covers [-HALF_EXTENT, HALF_EXTENT] on X and Z
		SEPARATION_RADIUS = 2.2,
		-- Keeps the horde topped up to MAX_ALIVE so the week-3 performance gate can be measured.
		DEBUG_KEEP_FULL = true,
		DEBUG_SPAWN_INTERVAL = 0.2,
	}),

	CLIENT_ZOMBIES = table.freeze({
		MAX_ANIMATED = 40,
		NEAR_DISTANCE = 60, -- full rig with procedural walk
		FAR_DISTANCE = 220, -- beyond this nothing is drawn (hidden in fog/corn)
		LOD_INTERVAL = 0.2,
		STALE_TIMEOUT = 1, -- drop zombies not heard from in this long
	}),
})
