--!strict
-- CollectionService tags used by the map. Gameplay systems find map points through these,
-- so the greybox can be swapped for the final art without touching code.

return table.freeze({
	ZombieSpawn = "ZombieSpawn",
	ClimbZone = "ClimbZone",
	Barricade = "Barricade",
	TurretSlot = "TurretSlot",
	ShopBox = "ShopBox",
	AmmoBox = "AmmoBox",
	Extraction = "Extraction",
	-- Blocks movement but not bullets or line of sight (rail fences: you shoot between rails).
	ShootThrough = "ShootThrough",
	-- Lights the client flickers (fires, failing bulbs).
	Flicker = "Flicker",
})
