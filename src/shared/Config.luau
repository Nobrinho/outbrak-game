--!strict
-- Tunable gameplay values (see docs/DEFINICOES.md). NOTE: replicated to clients —
-- nothing secret here, and the server never trusts a client-reported value from this file.

local Types = require(script.Parent.Types)

export type ZombieStats = {
	displayName: string,
	health: number,
	speed: number,
	damage: number,
	attackRange: number,
	attackCooldown: number,
	barricadeDamage: number, -- per hit on a barricade
	backMultiplier: number, -- damage taken from behind (weak spot)
	canPile: boolean, -- joins pyramids and climbs walls
	hearsNoise: boolean, -- pulled toward gunfire and explosions
	scale: number, -- visual size multiplier for the client rig
}

local ZOMBIES: { [Types.ZombieKind]: ZombieStats } = {
	Runner = {
		displayName = "Corredor",
		health = 50,
		speed = 22,
		damage = 10,
		attackRange = 3,
		attackCooldown = 1,
		barricadeDamage = 3,
		backMultiplier = 1,
		canPile = true,
		hearsNoise = true,
		scale = 1,
	},
	Bull = {
		displayName = "Bull",
		health = 600,
		speed = 14,
		damage = 35,
		attackRange = 4,
		attackCooldown = 1.5,
		barricadeDamage = 60,
		backMultiplier = 2,
		canPile = false,
		hearsNoise = false,
		scale = 1.5,
	},
	Creeper = {
		displayName = "Creeper",
		health = 80,
		speed = 16,
		damage = 60, -- explosion at the center
		attackRange = 4, -- starts its fuse this close
		attackCooldown = 1,
		barricadeDamage = 150, -- explosion vs barricades
		backMultiplier = 1,
		canPile = false,
		hearsNoise = true,
		scale = 1.2,
	},
	Brute = {
		displayName = "Brute",
		health = 2000, -- plus BRUTE.healthPerPlayer for each player
		speed = 12,
		damage = 50,
		attackRange = 6,
		attackCooldown = 2,
		barricadeDamage = 120,
		backMultiplier = 3,
		canPile = false,
		hearsNoise = false,
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
	noise: number, -- studs within which Runners hear it
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

export type AbilityStats = {
	name: string,
	description: string,
	cooldown: number,
	duration: number,
	-- Incendiary rounds (Gunslinger): each hit sets the zombie burning.
	burnDps: number,
	burnTime: number,
	-- Molotov (Exterminator): a fire patch where it lands.
	radius: number,
	fireDps: number,
}

export type ClassStats = {
	displayName: string,
	description: string,
	startGun: GunName,
	damageBonus: { [string]: number }, -- per gun name
	reserveBonus: number, -- multiplies every gun's reserve
	grenades: number, -- carry limit
	ability: AbilityStats,
}

export type ShopItem = {
	id: string,
	kind: "gun" | "melee" | "grenade" | "turret",
	displayName: string,
	price: number,
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
		noise = 40,
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
		noise = 45,
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
		noise = 60,
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
		noise = 60,
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
		noise = 70,
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
		noise = 100, -- heard from the moment it lands: a decoy
	}),
	CLASSES = table.freeze({
		Gunslinger = table.freeze({
			displayName = "Gunslinger",
			description = "Precisão: +25% de dano com rifles e SMG, +30% de munição.",
			startGun = "SMG",
			damageBonus = table.freeze({ SMG = 1.25, Rifle = 1.25, AK47 = 1.25 }),
			reserveBonus = 1.3,
			grenades = 2,
			ability = table.freeze({
				name = "Munição incendiária",
				description = "10 s de tiros que incendeiam os zumbis.",
				cooldown = 45,
				duration = 10,
				burnDps = 12,
				burnTime = 3,
				radius = 0,
				fireDps = 0,
			}),
		}),
		Exterminator = table.freeze({
			displayName = "Exterminador",
			description = "Controle de multidão: +20% de dano com escopeta, +1 granada.",
			startGun = "Shotgun",
			damageBonus = table.freeze({ Shotgun = 1.2 }),
			reserveBonus = 1,
			grenades = 3,
			ability = table.freeze({
				name = "Coquetel molotov",
				description = "Área de fogo por 6 s onde cair.",
				cooldown = 45,
				duration = 6,
				burnDps = 0,
				burnTime = 0,
				radius = 9,
				fireDps = 35,
			}),
		}),
	}) :: { [Types.ClassId]: ClassStats },
	DEFAULT_CLASS = "Gunslinger" :: Types.ClassId,

	-- Credits per kill, spent at the barn shop. Reset every match.
	REWARDS = table.freeze({ Runner = 5, Creeper = 15, Bull = 50, Brute = 300 }) :: { [Types.ZombieKind]: number },
	START_CREDITS = 0,
	SHOP = table.freeze({
		table.freeze({ id = "SMG", kind = "gun", displayName = "Submetralhadora", price = 400 }),
		table.freeze({ id = "Shotgun", kind = "gun", displayName = "Escopeta", price = 500 }),
		table.freeze({ id = "Rifle", kind = "gun", displayName = "Rifle", price = 700 }),
		table.freeze({ id = "AK47", kind = "gun", displayName = "AK-47", price = 900 }),
		table.freeze({ id = "Bat", kind = "melee", displayName = "Taco com pregos", price = 350 }),
		table.freeze({
			id = "Grenade",
			kind = "grenade",
			displayName = "Granada (+1)",
			price = 150,
		}),
		table.freeze({
			id = "Turret",
			kind = "turret",
			displayName = "Torreta automática",
			price = 750,
		}),
	}) :: { ShopItem },
	SHOP_RANGE = 14, -- studs from a shop crate to buy
	TURRET = table.freeze({
		range = 65,
		fireRate = 6,
		damage = 12,
		ammo = 400, -- shots before it powers down and frees its slot
		noise = 50,
		maxKits = 3,
	}),

	BULL = table.freeze({
		chargeRange = 30, -- starts a charge at players closer than this (and visible)
		chargeMinRange = 8,
		windup = 0.6, -- scrapes the ground before charging (telegraph)
		chargeSpeed = 42,
		chargeTime = 1.2,
		chargeDamage = 35,
		chargeBarricadeDamage = 250,
		cooldown = 6,
	}),
	CREEPER = table.freeze({
		fuse = 1,
		radius = 12,
		zombieDamage = 80, -- hurts the horde too: shoot it next to a pile
		noise = 60,
	}),
	BRUTE = table.freeze({
		healthPerPlayer = 1000,
		throwMinRange = 14,
		throwMaxRange = 90,
		windup = 1, -- arm raised before the rock leaves
		cooldown = 7,
		rockDamage = 30,
		rockBarricadeDamage = 80,
		rockRadius = 7,
	}),
	MATCH = table.freeze({
		prepTimes = table.freeze({ 45, 35, 35 }), -- before wave 1, wave 2 and the final wave
		waves = table.freeze({
			table.freeze({ Runner = 50, Creeper = 2 }),
			table.freeze({ Runner = 70, Creeper = 3, Bull = 1 }),
		}),
		spawnInterval = 0.2,
		extraPlayerScale = 0.35, -- each player beyond the first adds 35% to wave sizes
		waveTimeout = 150, -- after everything spawned, leftovers are despawned
		finalDuration = 90, -- survive this long, then reach the helicopter
		finalSpawnInterval = 0.3,
		finalMix = table.freeze({ Runner = 0.85, Creeper = 0.1, Bull = 0.05 }),
		resultTime = 12,
	}),
	-- Melee everyone starts with; the starting gun comes from the class (CLASSES.startGun).
	LOADOUT = table.freeze({
		melee = "Knife" :: MeleeName,
	}),
	AMMO_BOX_COOLDOWN = 30,
	BARRICADE = table.freeze({
		maxHealth = 1500,
		repairFraction = 0.25, -- of max health per completed hold
		repairHold = 1.2,
		repairCooldown = 0.3,
		zombieDamageMultiplier = 0.5, -- zombies hit barricades for half their player damage
	}),
	PILE = table.freeze({
		perLayer = 3,
		layerHeight = 1.6,
		reach = 4, -- a zombie on top of the pile can grab a ledge this far above it
		joinTime = 0.4,
		climbTimes = table.freeze({ 0.55, 0.35, 0.45 }), -- up the pile, over the top, drop down
		stallTime = 5, -- no newcomers for this long: the pile climbs over anyway, top first
		releaseInterval = 0.6, -- one zombie leaves the top of a flowing pile this often
		disbandAfter = 15, -- a pile with nowhere to land falls apart after this long idle
	}),
	-- Account progression (persisted). XP comes from kills, cleared waves, finishing matches
	-- and extractions; shop items unlock by account level.
	PROGRESSION = table.freeze({
		xpPerKill = table.freeze({ Runner = 2, Creeper = 5, Bull = 15, Brute = 100 }) :: { [Types.ZombieKind]: number },
		xpWaveCleared = 50,
		xpMatchPlayed = 25,
		xpExtraction = 200,
		-- Level n needs this much XP to advance to n + 1.
		levelBase = 100,
		levelExponent = 1.5,
		unlocks = table.freeze({ Bat = 2, Rifle = 3, Turret = 4, AK47 = 5 }) :: { [string]: number },
	}),
	-- Monetization (docs/DEFINICOES.md §6): cosmetic pass + XP boost only, never power. Ids come
	-- from the Creator Hub after publishing; 0 means "not set up yet" (the offer is hidden).
	MONETIZATION = table.freeze({
		survivorPackId = 0, -- Gamepass "Pacote do Sobrevivente": gold weapon skin + trail
		xpBoostProductId = 0, -- Developer Product "Boost 2x XP por 1 h"
		boostSeconds = 3600,
		boostMultiplier = 2,
	}),

	-- Shown on the HUD so testers can say which build they played.
	BUILD = "0.11.0-teste",
	-- Test switches. ALL must be false before publishing.
	DEBUG = table.freeze({
		combatLog = false, -- prints why shots are accepted/rejected to the server Output
		godMode = false, -- players take no damage (invisible ForceField)
		infiniteAmmo = false, -- magazine and grenades never run out
		richStart = false, -- start every match with 5000 credits to try the shop
	}),
	AIM_ASSIST_DEGREES = 4, -- touch only: near-misses inside this cone count as body hits

	HORDE = table.freeze({
		MAX_ALIVE = 120,
		SIM_HZ = 20,
		REPLICATION_HZ = 10,
		FLOW_RECOMPUTE_INTERVAL = 0.5,
		CELL_SIZE = 4,
		HALF_EXTENT = 240, -- flow field covers [-HALF_EXTENT, HALF_EXTENT] on X and Z
		SEPARATION_RADIUS = 2.2,
	}),

	CLIENT_ZOMBIES = table.freeze({
		MAX_ANIMATED = 40,
		NEAR_DISTANCE = 60, -- full rig with procedural walk
		FAR_DISTANCE = 220, -- beyond this nothing is drawn (hidden in fog/corn)
		LOD_INTERVAL = 0.2,
		STALE_TIMEOUT = 1, -- drop zombies not heard from in this long
	}),
})
