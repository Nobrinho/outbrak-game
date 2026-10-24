--!strict
-- Sound library. Effects come from Roblox's licensed libraries (ProSoundEffects, APM), free to
-- use in any experience; the explosion ships with the Roblox client itself. Several guns
-- share one recording at different pitches. Volumes are relative; AudioController mixes them
-- into SFX / ambience / music groups.

export type SoundDef = {
	id: string,
	volume: number,
	pitch: number?,
	jitter: number?, -- random ± pitch per play, so repeats don't sound mechanical
	looped: boolean?,
}

local PISTOL = "rbxassetid://9117399029" -- Pistol Single Shots 1 (ProSoundEffects)
local RIFLE = "rbxassetid://9118173988" -- Rifle Single Shots 3 (ProSoundEffects)
local SWOOSH = "rbxassetid://12222200"

local Sounds: { [string]: SoundDef } = {
	GunPistol = { id = PISTOL, volume = 0.5, jitter = 0.06 },
	GunSMG = { id = RIFLE, volume = 0.4, pitch = 1.3, jitter = 0.05 },
	GunShotgun = { id = RIFLE, volume = 0.8, pitch = 0.62, jitter = 0.04 },
	GunRifle = { id = RIFLE, volume = 0.5, jitter = 0.04 },
	GunAK47 = { id = RIFLE, volume = 0.6, pitch = 0.86, jitter = 0.04 },
	Turret = { id = RIFLE, volume = 0.3, pitch = 1.5, jitter = 0.05 },
	Reload = { id = "rbxassetid://9113104176", volume = 0.6 }, -- Ammo Magazine 1
	Swing = { id = SWOOSH, volume = 0.6, jitter = 0.1 },
	Throw = { id = SWOOSH, volume = 0.5, pitch = 0.7 },
	HitTick = { id = "rbxassetid://9119717523", volume = 0.25, pitch = 1.6, jitter = 0.05 },
	Explosion = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.9, jitter = 0.08 },
	Fire = { id = "rbxassetid://9120193895", volume = 0.5, looped = true }, -- Torch O Fire 1
	CreeperHiss = { id = "rbxassetid://9125475729", volume = 0.8, pitch = 1.2 },
	BruteRoar = { id = "rbxassetid://9113980319", volume = 1, pitch = 0.8 },
	-- One looped growl bed for the whole horde, louder the more zombies are close (§3 Áudio).
	Horde = { id = "rbxassetid://9113985466", volume = 0.7, pitch = 0.85, looped = true },
	Helicopter = { id = "rbxassetid://9113417082", volume = 0.8, looped = true },
	Heartbeat = { id = "rbxassetid://9043365842", volume = 0.7, looped = true },
	Purchase = { id = "rbxassetid://9113728042", volume = 0.5 }, -- Cash Register 1
	Click = { id = "rbxassetid://9119717523", volume = 0.4 },
	Sting = { id = "rbxassetid://1841714843", volume = 0.6 }, -- Modern Horror sting (APM)
	MusicDrone = { id = "rbxassetid://1843995698", volume = 0.35, looped = true }, -- Moving Drone 29
	MusicTension = { id = "rbxassetid://1840640599", volume = 0.4, looped = true }, -- Body Of Evidence
}

return table.freeze(Sounds)
