--!strict
-- Procedural upper-body poses for every player character, applied after Roblox's default
-- animations each frame (PreSimulation) so legs keep the stock walk cycle:
--   • holding the gun two-handed (pistol: both hands forward), arms and head following the
--     aim pitch; the wrist keeps the barrel exactly on the aim line
--   • recoil kick per shot, reload (left hand to the magazine, gun tilted), melee swing with
--     the gun, overhand grenade throw with a grenade in the left hand
--   • while strafing, the legs turn toward the movement and the chest stays on the aim
-- Works with Motor6D and AnimationConstraint joints (both expose Transform). The local player
-- poses from the camera; others from the AimPitch attribute and Net.characterFx events.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local InputController = require(script.Parent.InputController)
local WeaponController = require(script.Parent.WeaponController)

local PoseController = {}

local HALF_PI = math.pi / 2
local MAX_PITCH = math.rad(60)
local MAX_TWIST = math.rad(55)
local SPEED_NORMAL, SPEED_AIM, SPEED_RELOAD = 16, 11, 13
local PITCH_SEND_INTERVAL = 0.12

type Joint = { Transform: CFrame }
type Action = { kind: string, start: number, duration: number }
type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	leftHand: BasePart,
	joints: { [string]: Joint },
	twist: number,
	recoil: number,
	action: Action?,
	prop: BasePart?,
	-- What we wrote to the Root joint last frame and the animation value under it, so a frame
	-- where the animator didn't touch Root doesn't stack the hip turn again.
	lastRoot: CFrame?,
	rootBase: CFrame,
}

local player = Players.LocalPlayer
local rigs: { [Model]: Rig } = {}
local lastPitchSent = 0
local lastPitchTime = 0

local JOINT_PARTS = {
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	Waist = "UpperTorso",
	Neck = "Head",
	Root = "LowerTorso",
}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 0→1→0 envelope over [0, 1] with `edge` long ramps, for actions that leave and return.
local function envelope(t: number, edge: number): number
	if t < edge then
		return smooth(t / edge)
	elseif t > 1 - edge then
		return smooth((1 - t) / edge)
	end
	return 1
end

local function arm(pitch: number, yaw: number): CFrame
	-- Raise the arm forward by `pitch` (0 = hanging), then swing it sideways by `yaw`.
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

local function track(character: Model)
	if rigs[character] then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local leftHand = character:WaitForChild("LeftHand", 10)
	if
		not humanoid
		or not humanoid:IsA("Humanoid")
		or humanoid.RigType ~= Enum.HumanoidRigType.R15
	then
		return
	end
	if not root or not root:IsA("BasePart") or not leftHand or not leftHand:IsA("BasePart") then
		return
	end
	local joints: { [string]: Joint } = {}
	for name, partName in JOINT_PARTS do
		local part = character:WaitForChild(partName, 10)
		local joint = part and part:FindFirstChild(name)
		if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			joints[name] = joint :: any
		end
	end
	rigs[character] = {
		character = character,
		humanoid = humanoid,
		root = root,
		leftHand = leftHand,
		joints = joints,
		twist = 0,
		recoil = 0,
		action = nil,
		prop = nil,
		lastRoot = nil,
		rootBase = CFrame.identity,
	}
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			local rig = rigs[character]
			if rig and rig.prop then
				rig.prop:Destroy()
			end
			rigs[character] = nil
		end
	end)
end

local function startAction(character: Model?, kind: string, duration: number)
	local rig = character and rigs[character]
	if rig then
		rig.action = { kind = kind, start = os.clock(), duration = duration }
	end
end

local function grenadeProp(rig: Rig, show: boolean)
	if show and not rig.prop then
		local ball = Instance.new("Part")
		ball.Name = "GrenadeInHand"
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(0.7, 0.7, 0.7)
		ball.Color = Color3.fromRGB(60, 72, 48)
		ball.Material = Enum.Material.Metal
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CastShadow = false
		ball.Parent = workspace
		rig.prop = ball
	elseif not show and rig.prop then
		rig.prop:Destroy()
		rig.prop = nil
	end
	if rig.prop then
		rig.prop.CFrame = rig.leftHand.CFrame * CFrame.new(0, -0.4, 0)
	end
end

local function aimPitch(rig: Rig): number
	if rig.character == player.Character then
		return math.clamp(
			math.asin(workspace.CurrentCamera.CFrame.LookVector.Y),
			-MAX_PITCH,
			MAX_PITCH
		)
	end
	local pitch = rig.character:GetAttribute("AimPitch")
	return if typeof(pitch) == "number" then math.clamp(pitch, -MAX_PITCH, MAX_PITCH) else 0
end

local function gunName(rig: Rig): string
	local gun = rig.character:FindFirstChild("Gun")
	if gun then
		for _, child in gun:GetChildren() do
			local base = string.match(child.Name, "^(%w+)_")
			if base and Config.GUNS[base :: Config.GunName] then
				return base
			end
		end
	end
	if rig.character == player.Character then
		return WeaponController.view.gun
	end
	return "SMG"
end

local function pose(rig: Rig, dt: number)
	local joints = rig.joints
	local pitch = aimPitch(rig)
	local pistol = gunName(rig) == "Pistol"

	-- Base hold: right hand on the grip, left hand supporting the barrel.
	local rShoulder, rYaw, rElbow = 1.45 + pitch * 0.8, 0, 0.25
	local lShoulder, lYaw, lElbow = 1.35 + pitch * 0.8, -0.6, 0.55
	if pistol then
		rShoulder, rElbow = 1.5 + pitch * 0.9, 0.12
		lShoulder, lYaw, lElbow = 1.45 + pitch * 0.9, -0.42, 0.3
	end
	local wristRoll = 0
	local waistExtra = 0

	rig.recoil = math.max(0, rig.recoil - dt * 9)
	local kick = rig.recoil * 0.18
	rShoulder += kick
	lShoulder += kick

	local action = rig.action
	if action then
		local t = (os.clock() - action.start) / action.duration
		if t >= 1 then
			rig.action = nil
		elseif action.kind == "melee" then
			-- Wind up high and out, then bash across the body, then recover.
			if t < 0.35 then
				local k = smooth(t / 0.35)
				rShoulder += (2.4 - rShoulder) * k
				rYaw += 0.6 * k
				waistExtra = 0.25 * k
			elseif t < 0.7 then
				local k = smooth((t - 0.35) / 0.35)
				rShoulder = 2.4 + (0.6 - 2.4) * k
				rYaw = 0.6 + (-0.5 - 0.6) * k
				waistExtra = 0.25 - 0.55 * k
			else
				local k = smooth((t - 0.7) / 0.3)
				rShoulder = 0.6 + (rShoulder - 0.6) * k
				rYaw = -0.5 * (1 - k)
				waistExtra = -0.3 * (1 - k)
			end
		elseif action.kind == "throw" then
			-- Overhand: left arm up and back with the grenade, whip forward, recover.
			if t < 0.4 then
				local k = smooth(t / 0.4)
				lShoulder += (2.9 - lShoulder) * k
				lYaw += (0.45 - lYaw) * k
				lElbow += (1.3 - lElbow) * k
				waistExtra = -0.3 * k
			elseif t < 0.62 then
				local k = smooth((t - 0.4) / 0.22)
				lShoulder = 2.9 + (1.1 - 2.9) * k
				lYaw = 0.45 + (-0.3 - 0.45) * k
				lElbow = 1.3 + (0.05 - 1.3) * k
				waistExtra = -0.3 + 0.55 * k
			else
				local k = smooth((t - 0.62) / 0.38)
				lShoulder = 1.1 + (lShoulder - 1.1) * k
				lYaw = -0.3 + (lYaw + 0.3) * k
				lElbow = 0.05 + (lElbow - 0.05) * k
				waistExtra = 0.25 * (1 - k)
			end
			grenadeProp(rig, t < 0.42)
		elseif action.kind == "reload" then
			-- Left hand drops to the magazine and back; the gun tilts while it's out.
			local k = envelope(t, 0.2)
			lShoulder += (0.75 - lShoulder) * k
			lYaw += (-0.35 - lYaw) * k
			lElbow += (1.15 - lElbow) * k
			wristRoll = 0.45 * k
		end
	end
	if not (action and action.kind == "throw") and rig.prop then
		grenadeProp(rig, false)
	end

	-- Strafing: legs face the movement, chest stays on the aim.
	local velocity = rig.root.CFrame:VectorToObjectSpace(rig.root.AssemblyLinearVelocity)
	local flat = Vector2.new(velocity.X, velocity.Z)
	local targetTwist = 0
	if flat.Magnitude > 2 then
		local angle = math.atan2(-velocity.X, -velocity.Z) -- 0 = forward, + = left
		if math.abs(angle) > HALF_PI then
			-- Backpedalling: keep the hips square rather than turning them around.
			angle = (if angle > 0 then angle - math.pi else angle + math.pi) * 0.5
		end
		targetTwist = math.clamp(angle, -MAX_TWIST, MAX_TWIST)
	end
	rig.twist += (targetTwist - rig.twist) * math.min(1, dt * 10)

	-- The wrist keeps the barrel on the aim line whatever the arm is doing.
	local wrist = HALF_PI + pitch - rShoulder - rElbow

	local function set(name: string, value: CFrame)
		local joint = joints[name]
		if joint then
			joint.Transform = value
		end
	end
	set("RightShoulder", arm(rShoulder, rYaw))
	set("RightElbow", CFrame.Angles(rElbow, 0, 0))
	set("RightWrist", CFrame.Angles(wrist, 0, wristRoll))
	set("LeftShoulder", arm(lShoulder, lYaw))
	set("LeftElbow", CFrame.Angles(lElbow, 0, 0))
	set("Waist", CFrame.Angles(0, -rig.twist + waistExtra, 0) * CFrame.Angles(pitch * 0.25, 0, 0))
	set("Neck", CFrame.Angles(pitch * 0.45, 0, 0))
	local root = joints.Root
	if root then
		-- Keep the walk cycle's bob from the default animation, add the hip turn.
		local current = root.Transform
		local base = if rig.lastRoot and current == rig.lastRoot then rig.rootBase else current
		rig.rootBase = base
		local out = CFrame.Angles(0, rig.twist, 0) * base
		root.Transform = out
		rig.lastRoot = out
	end
end

local function localUpdate()
	local rig = player.Character and rigs[player.Character]
	if not rig then
		return
	end
	-- Aiming and reloading slow you down.
	local speed = SPEED_NORMAL
	if WeaponController.view.reloading then
		speed = SPEED_RELOAD
	end
	if InputController.isDown("Aim") then
		speed = SPEED_AIM
	end
	if rig.humanoid.WalkSpeed ~= speed then
		rig.humanoid.WalkSpeed = speed
	end
	-- Share the aim pitch so others see where you point (throttled, only on change).
	local pitch = aimPitch(rig)
	local now = os.clock()
	if math.abs(pitch - lastPitchSent) > 0.03 and now - lastPitchTime > PITCH_SEND_INTERVAL then
		lastPitchSent, lastPitchTime = pitch, now
		Net.aimPitch():FireServer(pitch)
	end
end

function PoseController.start()
	local function watch(p: Player)
		if p.Character then
			task.spawn(track, p.Character)
		end
		p.CharacterAdded:Connect(track)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end

	-- Your own actions start instantly; others' arrive through the server relay.
	WeaponController.fired:connect(function()
		local rig = player.Character and rigs[player.Character]
		if rig then
			rig.recoil = 1
		end
	end)
	WeaponController.swung:connect(function()
		startAction(player.Character, "melee", 0.4)
	end)
	WeaponController.thrown:connect(function()
		startAction(player.Character, "throw", 0.6)
	end)
	WeaponController.reloadStarted:connect(function()
		startAction(player.Character, "reload", Config.GUNS[WeaponController.view.gun].reloadTime)
	end)
	Net.characterFx().OnClientEvent:Connect(function(who: unknown, kind: unknown, gun: unknown)
		if typeof(who) ~= "Instance" or who == player or typeof(kind) ~= "string" then
			return
		end
		local character = (who :: Player).Character
		if kind == "shot" then
			local rig = character and rigs[character]
			if rig then
				rig.recoil = 1
			end
		elseif kind == "reload" then
			local stats = typeof(gun) == "string" and Config.GUNS[gun :: Config.GunName]
			startAction(character, kind, if stats then stats.reloadTime else 1.5)
		elseif kind == "melee" then
			startAction(character, kind, 0.4)
		elseif kind == "throw" then
			startAction(character, kind, 0.6)
		end
	end)

	RunService.PreSimulation:Connect(function(dt)
		localUpdate()
		for _, rig in rigs do
			if rig.humanoid.Health > 0 then
				pose(rig, dt)
			end
		end
	end)
end

return PoseController
