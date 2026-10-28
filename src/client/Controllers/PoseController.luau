--!strict
-- Procedural upper-body poses for every player character, applied after Roblox's default
-- animations each frame (PreSimulation) so legs keep the stock walk cycle:
--   • the gun is placed in chest space (per-gun hold, turned to the aim pitch) and both arms
--     reach it with two-bone IK (Pose/ArmIK): right hand on the grip, left hand on the
--     handguard; Gun.Handle.GripMotor keeps the barrel exactly on the aim line
--   • spring recoil per shot (the gun slides back and climbs, the arms follow), walk sway,
--     breathing, and a lowered gun while running
--   • melee weapons in hand (knife one-handed with the left fist up, bat over the shoulder)
--   • keyframed clips (Pose/Clips): drawing after a weapon switch, per-gun reloads (the magazine leaves the gun, the empty
--     one drops, a fresh one comes from the belt; shotgun shells one by one), the shotgun pump
--     after each shot, the melee swing and the overhand grenade throw
--   • while strafing, the legs turn toward the movement and the chest stays on the aim
-- Arms need Motor6D joints (IK reads their C0/C1); the chest, head and hips also work with
-- AnimationConstraint joints (both expose Transform). The local player
-- poses from the camera; others from the AimPitch attribute and Net.characterFx events.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local InputController = require(script.Parent.InputController)
local WeaponController = require(script.Parent.WeaponController)
local ArmIK = require(script.Parent.Pose.ArmIK)
local Clips = require(script.Parent.Pose.Clips)

local PoseController = {}

local HALF_PI = math.pi / 2
local MAX_PITCH = math.rad(60)
local MAX_TWIST = math.rad(55)
local SPEED_NORMAL, SPEED_AIM, SPEED_RELOAD = 16, 11, 13
local PITCH_SEND_INTERVAL = 0.12
-- Recoil is a damped spring kicked once per shot; the gun slides back and its muzzle climbs.
local KICK_STIFFNESS, KICK_DAMPING, KICK_IMPULSE = 320, 24, 26
-- Running (faster than the aim/reload walk) with no recent shot lowers the gun.
local LOW_READY_SPEED, LOW_READY_AFTER_SHOT = 13.5, 0.8

-- Where each gun sits, in UpperTorso space (studs; -Z forward, +Y up): `grip` is the grip
-- position before aim pitch, `support` the left hand's spot in gun space (-Z barrel, +Y top).
-- Long guns sit close to the chest so the left hand reaches the handguard. Melee weapons can
-- turn in the hand (`turn`, gun space) and leave the left hand free at `free` (chest space).
type Hold = { grip: Vector3, support: Vector3, turn: CFrame?, free: Vector3? }
local HOLDS: { [string]: Hold } = {
	Pistol = { grip = Vector3.new(0.25, 0.45, -1.55), support = Vector3.new(-0.12, -0.28, 0.08) },
	SMG = { grip = Vector3.new(0.35, 0.3, -0.9), support = Vector3.new(0, -0.02, -0.7) },
	Rifle = { grip = Vector3.new(0.35, 0.3, -0.8), support = Vector3.new(0, -0.05, -0.8) },
	AK47 = { grip = Vector3.new(0.35, 0.3, -0.75), support = Vector3.new(0, -0.05, -0.85) },
	Shotgun = { grip = Vector3.new(0.35, 0.3, -0.7), support = Vector3.new(0, -0.02, -0.9) },
	-- Knife low and forward in the right hand, left fist up guarding.
	Knife = {
		grip = Vector3.new(0.5, -0.1, -1.1),
		support = Vector3.zero,
		turn = CFrame.Angles(-0.25, 0, 0),
		free = Vector3.new(-0.45, 0.25, -1.0),
	},
	-- Bat cocked up over the right shoulder, both hands on the handle.
	Bat = {
		grip = Vector3.new(0.45, 0.35, -0.75),
		support = Vector3.new(0, 0, 0.3),
		turn = CFrame.Angles(1.15, 0, -0.35),
	},
}
-- The gun turns with the aim pitch around this point (between the shoulders).
local AIM_PIVOT = Vector3.new(0.3, 0.6, 0.1)
-- Left hand's resting spot when it isn't on the gun (belt, left hip).
local BELT = Vector3.new(-0.7, -1.0, -0.45)
-- Most the gun may float off the hand when a pose is out of the arm's reach.
local MAX_GRIP_SLIP = 0.35

type Joint = { Transform: CFrame }
-- `cue` is the index of the clip's next one-shot event.
type Action = { kind: string, start: number, duration: number, cue: number }
type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	upperTorso: BasePart,
	leftHand: BasePart,
	joints: { [string]: Joint },
	twist: number,
	kick: number,
	kickVelocity: number,
	lastShot: number,
	lowReady: number,
	swayPhase: number,
	action: Action?,
	prop: BasePart?,
	propKind: string?,
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
	LeftWrist = "LeftHand",
	Waist = "UpperTorso",
	Neck = "Head",
	Root = "LowerTorso",
}

local function track(character: Model)
	if rigs[character] then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local leftHand = character:WaitForChild("LeftHand", 10)
	local upperTorso = character:WaitForChild("UpperTorso", 10)
	if
		not humanoid
		or not humanoid:IsA("Humanoid")
		or humanoid.RigType ~= Enum.HumanoidRigType.R15
	then
		return
	end
	if
		not root
		or not root:IsA("BasePart")
		or not leftHand
		or not leftHand:IsA("BasePart")
		or not upperTorso
		or not upperTorso:IsA("BasePart")
	then
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
		upperTorso = upperTorso,
		leftHand = leftHand,
		joints = joints,
		twist = 0,
		kick = 0,
		kickVelocity = 0,
		lastShot = 0,
		lowReady = 0,
		swayPhase = 0,
		action = nil,
		prop = nil,
		propKind = nil,
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
		rig.action = { kind = kind, start = os.clock(), duration = duration, cue = 1 }
	end
end

-- The gun's magazine piece ("<Gun>_Mag", see Art/WeaponModels), if it has one.
local function gunMag(rig: Rig): BasePart?
	local gun = rig.character:FindFirstChild("Gun")
	if gun then
		for _, child in gun:GetChildren() do
			if child:IsA("BasePart") and string.sub(child.Name, -4) == "_Mag" then
				return child
			end
		end
	end
	return nil
end

local function looseCopy(part: BasePart): BasePart
	local copy = part:Clone()
	for _, child in copy:GetChildren() do
		child:Destroy() -- welds to the gun
	end
	copy.LocalTransparencyModifier = 0
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	return copy
end

local function newProp(rig: Rig, kind: string): BasePart
	local mag = kind == "mag" and gunMag(rig)
	if mag then
		return looseCopy(mag)
	end
	local part = Instance.new("Part")
	part.Name = "InHand"
	if kind == "grenade" then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(0.7, 0.7, 0.7)
		part.Color = Color3.fromRGB(60, 72, 48)
		part.Material = Enum.Material.Metal
	elseif kind == "shell" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.4, 0.18, 0.18)
		part.Color = Color3.fromRGB(170, 40, 34)
	else
		part.Size = Vector3.new(0.2, 0.7, 0.28)
		part.Color = Color3.fromRGB(42, 44, 48)
		part.Material = Enum.Material.Metal
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Shows `kind` in the left hand (nil: nothing), replacing whatever was there.
local function handProp(rig: Rig, kind: string?)
	if kind ~= rig.propKind then
		if rig.prop then
			rig.prop:Destroy()
		end
		rig.prop = if kind then newProp(rig, kind) else nil
		rig.propKind = kind
		if rig.prop then
			rig.prop.Parent = workspace
		end
	end
	if rig.prop then
		local offset = if rig.propKind == "mag"
			then CFrame.new(0, -0.45, -0.1)
			else CFrame.new(0, -0.4, 0)
		rig.prop.CFrame = rig.leftHand.CFrame * offset
	end
end

-- The empty magazine falls out of the gun and lies on the floor for a moment.
local function dropMag(rig: Rig)
	local mag = gunMag(rig)
	local camera = workspace.CurrentCamera
	if not mag or (mag.Position - camera.CFrame.Position).Magnitude > 120 then
		return
	end
	local copy = looseCopy(mag)
	copy.Anchored = false
	copy.Massless = false
	copy.CanCollide = true
	copy.Parent = workspace
	copy.AssemblyLinearVelocity = rig.root.AssemblyLinearVelocity + Vector3.new(0, -4, 0)
	copy.AssemblyAngularVelocity = rig.root.CFrame.RightVector * 6
	Debris:AddItem(copy, 3)
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
			if
				base
				and (Config.GUNS[base :: Config.GunName] or Config.MELEE[base :: Config.MeleeName])
			then
				return base
			end
		end
	end
	if rig.character == player.Character then
		return WeaponController.view.gun
	end
	return "SMG"
end

local function shot(rig: Rig)
	local gun = gunName(rig)
	local stats = Config.GUNS[gun :: Config.GunName]
	rig.kickVelocity += KICK_IMPULSE * (if stats then stats.recoil else 1)
	rig.lastShot = os.clock()
	rig.lowReady = 0
	if gun == "Shotgun" and not rig.action then
		startAction(rig.character, "pump", 0.6)
	end
end

local function gripMotor(rig: Rig): Motor6D?
	local gun = rig.character:FindFirstChild("Gun")
	local handle = gun and gun:FindFirstChild("Handle")
	local motor = handle and handle:FindFirstChild("GripMotor")
	return if motor and motor:IsA("Motor6D") then motor else nil
end

local function chain(rig: Rig, side: string): ArmIK.Chain?
	local joints = rig.joints :: { [string]: any }
	local shoulder = ArmIK.frames(joints[side .. "Shoulder"])
	local elbow = ArmIK.frames(joints[side .. "Elbow"])
	local wrist = ArmIK.frames(joints[side .. "Wrist"])
	if shoulder and elbow and wrist then
		return { shoulder = shoulder, elbow = elbow, wrist = wrist }
	end
	return nil
end

local function pose(rig: Rig, dt: number)
	local joints = rig.joints
	local pitch = aimPitch(rig)
	local gun = gunName(rig)
	local hold = HOLDS[gun] or HOLDS.SMG
	local now = os.clock()

	-- Base pose for the clips: gun at its hold, left hand on its support spot.
	local p: Clips.Pose = {
		gx = 0,
		gy = 0,
		gz = 0,
		gp = 0,
		gyaw = 0,
		gr = 0,
		lx = hold.support.X,
		ly = hold.support.Y,
		lz = hold.support.Z,
		lw = if hold.free then 1 else 0,
		bx = if hold.free then hold.free.X else BELT.X,
		by = if hold.free then hold.free.Y else BELT.Y,
		bz = if hold.free then hold.free.Z else BELT.Z,
		waist = 0,
	}

	local action = rig.action
	local propKind: string? = nil
	local magOut = false
	if action then
		local t = (now - action.start) / action.duration
		local clip = Clips.get(action.kind, gun)
		if t >= 1 or not clip then
			rig.action = nil
		else
			Clips.sample(clip, t, p)
			for _, prop in clip.props or {} do
				if t >= prop.from and t < prop.to then
					propKind = prop.kind
				end
			end
			local out = clip.magOut
			magOut = out ~= nil and t >= out.from and t < out.to
			local events = clip.events
			while events and events[action.cue] and t >= events[action.cue].t do
				if events[action.cue].name == "dropMag" then
					dropMag(rig)
				end
				action.cue += 1
			end
		end
	end
	if propKind or rig.prop then
		handProp(rig, propKind)
	end
	local mag = gunMag(rig)
	if mag then
		mag.LocalTransparencyModifier = if magOut then 1 else 0
	end

	-- Recoil spring (semi-implicit Euler; dt is clamped so a hitch can't blow it up).
	local step = math.min(dt, 1 / 30)
	rig.kickVelocity += (-KICK_STIFFNESS * rig.kick - KICK_DAMPING * rig.kickVelocity) * step
	rig.kick = math.clamp(rig.kick + rig.kickVelocity * step, -0.5, 2.5)
	local kick = rig.kick
	p.gz += kick * 0.22
	p.gp += kick * 0.12

	local velocity = rig.root.CFrame:VectorToObjectSpace(rig.root.AssemblyLinearVelocity)
	local speed = Vector2.new(velocity.X, velocity.Z).Magnitude

	-- Walk sway (figure-eight on the gun) and a slow breathing bob when standing.
	local moving = math.min(1, speed / SPEED_NORMAL)
	rig.swayPhase += dt * speed * 0.55
	local bob = math.sin(rig.swayPhase * 2) * 0.05 * moving + math.sin(now * 1.6) * 0.012
	local sway = math.sin(rig.swayPhase) * 0.05 * moving
	p.gy += bob
	p.gx += sway
	p.gyaw += sway * 0.6

	-- Low-ready while running: gun drops across the body, muzzle down. Aiming or reloading
	-- walks slower than the threshold, so it also works for other players with no extra data.
	local lowTarget = if speed > LOW_READY_SPEED
			and now - rig.lastShot > LOW_READY_AFTER_SHOT
			and not rig.action
		then 1
		else 0
	local rate = if lowTarget > rig.lowReady then 5 else 14
	rig.lowReady += (lowTarget - rig.lowReady) * math.min(1, dt * rate)
	local low = rig.lowReady
	p.gp -= 0.8 * low
	p.gy -= 0.35 * low
	p.gz += 0.25 * low
	p.gx -= 0.2 * low
	p.gyaw += 0.45 * low

	-- Strafing: legs face the movement, chest stays on the aim.
	local targetTwist = 0
	if speed > 2 then
		local angle = math.atan2(-velocity.X, -velocity.Z) -- 0 = forward, + = left
		if math.abs(angle) > HALF_PI then
			-- Backpedalling: keep the hips square rather than turning them around.
			angle = (if angle > 0 then angle - math.pi else angle + math.pi) * 0.5
		end
		targetTwist = math.clamp(angle, -MAX_TWIST, MAX_TWIST)
	end
	rig.twist += (targetTwist - rig.twist) * math.min(1, dt * 10)

	local function set(name: string, value: CFrame)
		local joint = joints[name]
		if joint then
			joint.Transform = value
		end
	end
	-- The chest takes a quarter of the aim pitch. The gun points along the real aim (body
	-- facing + pitch) measured against the chest's last frame, so whatever the animations did
	-- to the torso, the barrel stays on target; its grip swings around AIM_PIVOT with it.
	set(
		"Waist",
		CFrame.Angles(0, -rig.twist + p.waist, 0) * CFrame.Angles(pitch * 0.25 + kick * 0.04, 0, 0)
	)
	set("Neck", CFrame.Angles(pitch * 0.45 + kick * 0.03, 0, 0))
	local aimTurn = (rig.upperTorso.CFrame:Inverse() * rig.root.CFrame).Rotation
		* CFrame.Angles(pitch, 0, 0)
	local aim = CFrame.new(AIM_PIVOT) * aimTurn * CFrame.new(-AIM_PIVOT)
	local gunFrame = aim
		* CFrame.new(hold.grip + Vector3.new(p.gx, p.gy, p.gz))
		* CFrame.Angles(0, p.gyaw, 0)
		* CFrame.Angles(p.gp, 0, 0)
		* CFrame.Angles(0, 0, p.gr)
		* (hold.turn or CFrame.identity)

	local grip = gripMotor(rig)
	local right = chain(rig, "Right")
	if grip and right then
		-- Right hand to the grip, turned to the gun; the GripMotor absorbs what's left.
		local hand = gunFrame * grip.C0:Inverse()
		local shoulder, bend = ArmIK.solve(right, ArmIK.pivotFor(right, hand))
		local lowerArm = ArmIK.lowerArm(right, shoulder, bend)
		local wrist = ArmIK.wrist(right, lowerArm, hand)
		set("RightShoulder", shoulder)
		set("RightElbow", CFrame.Angles(bend, 0, 0))
		set("RightWrist", wrist)
		local actual = lowerArm * right.wrist.C0 * wrist * right.wrist.C1:Inverse()
		local slip = grip.C0:Inverse() * actual:Inverse() * gunFrame
		local offset = slip.Position
		if offset.Magnitude > MAX_GRIP_SLIP then
			offset = offset.Unit * MAX_GRIP_SLIP
		end
		grip.Transform = CFrame.new(offset) * slip.Rotation
	end
	local left = chain(rig, "Left")
	if grip and left then
		local onGun = gunFrame * Vector3.new(p.lx, p.ly, p.lz)
		local target = onGun:Lerp(Vector3.new(p.bx, p.by, p.bz), math.clamp(p.lw, 0, 1))
		-- The left wrist stays straight, so the hand extends past the pivot along the arm:
		-- stop the pivot one hand-length short so the palm lands on the spot.
		local from = left.shoulder.C0.Position
		local handLength = left.wrist.C1.Position.Magnitude
		if (target - from).Magnitude > handLength then
			target -= (target - from).Unit * handLength
		end
		local shoulder, bend = ArmIK.solve(left, target)
		set("LeftShoulder", shoulder)
		set("LeftElbow", CFrame.Angles(bend, 0, 0))
		set("LeftWrist", CFrame.identity)
	end

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
			shot(rig)
		end
	end)
	WeaponController.swung:connect(function()
		startAction(player.Character, "melee", 0.4)
	end)
	WeaponController.thrown:connect(function()
		startAction(player.Character, "throw", 0.6)
	end)
	WeaponController.switched:connect(function()
		startAction(player.Character, "equip", Config.LOADOUT.switchTime + 0.1)
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
				shot(rig)
			end
		elseif kind == "reload" then
			local stats = typeof(gun) == "string" and Config.GUNS[gun :: Config.GunName]
			startAction(character, kind, if stats then stats.reloadTime else 1.5)
		elseif kind == "melee" then
			startAction(character, kind, 0.4)
		elseif kind == "throw" then
			startAction(character, kind, 0.6)
		elseif kind == "equip" then
			startAction(character, kind, Config.LOADOUT.switchTime + 0.1)
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
