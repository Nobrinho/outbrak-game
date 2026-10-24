--!strict
-- Sound and the effects tied to world events. Mixes three groups — SFX, ambience, music:
--   • your shots, reloads, swings and throws in 2D; other players' shots, turrets,
--     explosions, molotov fire and Creeper fuses positioned in the world
--   • one looped growl bed for the whole horde, louder the more zombies are close (§3)
--   • music in layers: a drone during Prep, plus a tension track during waves; a horror
--     sting at every wave and the Brute's roar when he arrives; the helicopter on extraction
--   • a heartbeat when your health is low, clicks on menu buttons, a till on purchases
-- Sound ids live in Art/Sounds.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Sounds = require(Shared.Art.Sounds)
local WeaponController = require(script.Parent.WeaponController)
local ZombieRenderer = require(script.Parent.ZombieRenderer)
local Effects = require(script.Parent.Parent.Effects)

local AudioController = {}

local GUN_SOUNDS: { [string]: string } = {
	Pistol = "GunPistol",
	SMG = "GunSMG",
	Shotgun = "GunShotgun",
	Rifle = "GunRifle",
	AK47 = "GunAK47",
}
local HORDE_RADIUS = 45
local HORDE_FULL = 25 -- this many zombies in range = full growl volume
local FADE = TweenInfo.new(1.5, Enum.EasingStyle.Sine)

local player = Players.LocalPlayer
local groups: { [string]: SoundGroup } = {}
local loops: { [string]: Sound } = {}

local function group(name: string, volume: number): SoundGroup
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = volume
	g.Parent = SoundService
	groups[name] = g
	return g
end

local function makeSound(name: string, parent: Instance, soundGroup: SoundGroup): Sound
	local def = Sounds[name]
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.id
	s.Volume = def.volume
	s.Looped = def.looped == true
	local jitter = def.jitter or 0
	s.PlaybackSpeed = (def.pitch or 1) * (1 + (math.random() * 2 - 1) * jitter)
	s.SoundGroup = soundGroup
	s.Parent = parent
	return s
end

-- One-shot in 2D (your own actions, UI, stingers).
function AudioController.play(name: string, groupName: string?)
	local s = makeSound(name, SoundService, groups[groupName or "SFX"])
	s:Play()
	Debris:AddItem(s, 8)
end

-- One-shot heard from a point in the world.
function AudioController.playAt(name: string, position: Vector3, rollOffMax: number?)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local s = makeSound(name, attachment, groups.SFX)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = rollOffMax or 250
	s:Play()
	Debris:AddItem(attachment, 8)
end

-- Looped sounds live forever and are faded in and out by volume.
local function loop(name: string, groupName: string): Sound
	local s = makeSound(name, SoundService, groups[groupName])
	s.Volume = 0
	s:Play()
	loops[name] = s
	return s
end

local function fadeTo(name: string, volume: number)
	local s = loops[name]
	if s then
		TweenService:Create(s, FADE, { Volume = volume }):Play()
	end
end

-- Music --------------------------------------------------------------------------------------

local function onPhase(match: Instance)
	local phase = match:GetAttribute("Phase")
	local drone, tension = Sounds.MusicDrone.volume, Sounds.MusicTension.volume
	if phase == "Prep" then
		fadeTo("MusicDrone", drone)
		fadeTo("MusicTension", 0)
		fadeTo("Helicopter", 0)
	elseif phase == "Wave" or phase == "Final" then
		AudioController.play("Sting", "Music")
		fadeTo("MusicDrone", drone * 0.5)
		fadeTo("MusicTension", tension)
	elseif phase == "Extract" then
		fadeTo("MusicTension", tension)
		fadeTo("Helicopter", Sounds.Helicopter.volume)
	elseif phase == "Result" then
		AudioController.play("Sting", "Music")
		fadeTo("MusicDrone", 0)
		fadeTo("MusicTension", 0)
		fadeTo("Helicopter", 0)
	end
end

-- Ambient beds ---------------------------------------------------------------------------------

local function updateBeds()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local center = if root and root:IsA("BasePart")
		then root.Position
		else workspace.CurrentCamera.CFrame.Position

	local near = ZombieRenderer.countNear(center, HORDE_RADIUS)
	local horde = loops.Horde
	if horde then
		horde.Volume = Sounds.Horde.volume * math.clamp(near / HORDE_FULL, 0, 1)
	end

	local heart = loops.Heartbeat
	if heart then
		local low = humanoid and humanoid.Health > 0 and humanoid.Health / humanoid.MaxHealth < 0.35
		heart.Volume = if low then Sounds.Heartbeat.volume else 0
	end
end

-- World events -------------------------------------------------------------------------------

local function onWorldDescendant(instance: Instance)
	if instance:IsA("Explosion") then
		AudioController.playAt("Explosion", instance.Position, 400)
		Effects.explosion(instance.Position, instance.BlastRadius)
	elseif instance.Name == "FirePatch" and instance:IsA("BasePart") then
		-- Molotov fire: crackles where it burns, removed with the patch.
		local s = makeSound("Fire", instance, groups.SFX)
		s.RollOffMaxDistance = 80
		s:Play()
	end
end

local function hookButtons(gui: Instance)
	-- Menu buttons click; the touch action cluster (SwarmHUD) stays silent, it fires constantly.
	local function hook(descendant: Instance)
		local screen = descendant:FindFirstAncestorOfClass("ScreenGui")
		if descendant:IsA("GuiButton") and screen and screen.Name ~= "SwarmHUD" then
			descendant.Activated:Connect(function()
				AudioController.play("Click", "UI")
			end)
		end
	end
	gui.DescendantAdded:Connect(hook)
	for _, d in gui:GetDescendants() do
		hook(d)
	end
end

function AudioController.init()
	group("SFX", 0.9)
	group("Ambience", 0.8)
	group("Music", 0.6)
	group("UI", 0.7)
end

function AudioController.start()
	loop("MusicDrone", "Music")
	loop("MusicTension", "Music")
	loop("Horde", "Ambience")
	loop("Heartbeat", "SFX")
	loop("Helicopter", "Ambience")

	-- Your own weapon.
	WeaponController.fired:connect(function(gun, muzzle, direction)
		AudioController.play(GUN_SOUNDS[gun] or "GunPistol")
		Effects.muzzleFlash(muzzle, direction)
	end)
	WeaponController.reloadStarted:connect(function()
		AudioController.play("Reload")
	end)
	WeaponController.swung:connect(function()
		AudioController.play("Swing")
	end)
	WeaponController.thrown:connect(function()
		AudioController.play("Throw")
	end)
	WeaponController.hit:connect(function()
		AudioController.play("HitTick", "UI")
	end)

	-- Other players and turrets.
	Net.shotFx().OnClientEvent:Connect(function(shooter: unknown, gun: unknown)
		if typeof(shooter) ~= "Instance" or shooter == player or typeof(gun) ~= "string" then
			return
		end
		local character = (shooter :: Player).Character
		local muzzle = character and character:FindFirstChild("Muzzle", true)
		if muzzle and muzzle:IsA("BasePart") then
			AudioController.playAt(GUN_SOUNDS[gun] or "GunPistol", muzzle.Position)
		end
	end)
	Net.turretShot().OnClientEvent:Connect(function(from: Vector3)
		if typeof(from) == "Vector3" then
			AudioController.playAt("Turret", from, 150)
		end
	end)
	ZombieRenderer.fuseLit:connect(function(position)
		AudioController.playAt("CreeperHiss", position, 120)
	end)

	workspace.DescendantAdded:Connect(onWorldDescendant)

	Net.notify().OnClientEvent:Connect(function(message: unknown)
		if
			typeof(message) == "string"
			and (message:find("^Comprou") or message:find("^Torreta comprada"))
		then
			AudioController.play("Purchase", "UI")
		end
	end)
	hookButtons(player:WaitForChild("PlayerGui"))

	local match = ReplicatedStorage:WaitForChild("Match")
	match:GetAttributeChangedSignal("Phase"):Connect(function()
		onPhase(match)
	end)
	onPhase(match)
	-- The Brute announces himself.
	local bossWasUp = false
	match:GetAttributeChangedSignal("BossMaxHealth"):Connect(function()
		local up = (match:GetAttribute("BossMaxHealth") or 0) > 0
		if up and not bossWasUp then
			AudioController.play("BruteRoar", "Music")
			Effects.shake(0.4)
		end
		bossWasUp = up
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			updateBeds()
		end
	end)
end

return AudioController
