--!strict
-- Over-the-shoulder third-person camera. The character always faces where the camera looks
-- (shooter-style), the camera sits offset to the right shoulder, and aiming zooms the FOV.
-- On touch the default drag-to-look camera is kept; on PC the mouse is locked to the center.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local InputController = require(script.Parent.InputController)

local CameraController = {}

local SHOULDER_OFFSET = Vector3.new(2.2, 1.2, 0)
local AIM_OFFSET = Vector3.new(1.6, 1.0, 0)
local FOV_DEFAULT = 70
local FOV_AIM = 50
local ZOOM_DISTANCE = 10
local TURN_SPEED = 18 -- higher = character snaps to camera yaw faster

local player = Players.LocalPlayer
local humanoid: Humanoid?
local root: BasePart?

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid") :: Humanoid
	humanoid = h
	root = character:WaitForChild("HumanoidRootPart") :: BasePart
	h.AutoRotate = false
	h.CameraOffset = SHOULDER_OFFSET
	h.Died:Once(function()
		humanoid = nil
		root = nil
	end)
end

local function setAiming(aiming: boolean)
	local camera = workspace.CurrentCamera
	local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(camera, info, { FieldOfView = if aiming then FOV_AIM else FOV_DEFAULT })
		:Play()
	if humanoid then
		TweenService
			:Create(
				humanoid,
				info,
				{ CameraOffset = if aiming then AIM_OFFSET else SHOULDER_OFFSET }
			)
			:Play()
	end
end

local function step(dt: number)
	if InputController.isModalOpen() then
		-- A menu is open: give the mouse back so its buttons can be clicked.
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	elseif not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end

	local h, r = humanoid, root
	if not (h and r) or h.Sit then
		return
	end

	-- Rotate the character toward the camera's flat look direction.
	local look = workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local target = CFrame.lookAt(r.Position, r.Position + flat)
	r.CFrame = r.CFrame:Lerp(target, math.min(1, dt * TURN_SPEED))
end

function CameraController.init()
	player.CameraMinZoomDistance = ZOOM_DISTANCE
	player.CameraMaxZoomDistance = ZOOM_DISTANCE
end

function CameraController.start()
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	InputController.actionChanged:connect(function(action, isDown)
		if action == "Aim" then
			setAiming(isDown)
		end
	end)

	RunService:BindToRenderStep("SwarmCamera", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
