--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (remote payloads, profile schema) live here so both sides agree.

export type ZombieKind = "Runner" | "Bull" | "Creeper" | "Brute"
export type ClassId = "Gunslinger" | "Exterminator"

export type PlayerProfile = {
	version: number,
	xp: number,
	coins: number,
	unlockedWeapons: { string },
}

-- Server → client weapon snapshot (Net.weaponSync).
-- Slots: 1 primary gun, 2 sidearm, 3 melee.
export type Slot = number
export type WeaponState = {
	gun: string, -- the gun in hand (slot 1/2); the primary while the melee is out
	melee: string,
	mag: number, -- of `gun`
	reserve: number, -- of `gun`
	grenades: number,
	reloading: boolean,
	shotSeq: number, -- last shot the server processed; the client re-applies newer ones
	slot: Slot,
	primary: string,
	sidearm: string,
	primaryMag: number,
	primaryReserve: number,
	sidearmMag: number,
	sidearmReserve: number,
}

-- Match flow (MatchService); replicated as attributes on ReplicatedStorage.Match.
export type MatchPhase = "Waiting" | "Lobby" | "Prep" | "Wave" | "Final" | "Extract" | "Result"

return nil
