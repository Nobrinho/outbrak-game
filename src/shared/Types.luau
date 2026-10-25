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
export type WeaponState = {
	gun: string,
	melee: string,
	mag: number,
	reserve: number,
	grenades: number,
	reloading: boolean,
	shotSeq: number, -- last shot the server processed; the client re-applies newer ones
}

-- Match flow (MatchService); replicated as attributes on ReplicatedStorage.Match.
export type MatchPhase = "Waiting" | "Lobby" | "Prep" | "Wave" | "Final" | "Extract" | "Result"

return nil
