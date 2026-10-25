--!strict
-- Over-the-shoulder third-person camera. The character always faces where the camera looks
-- (shooter-style), the camera sits offset to the right shoulder, and aiming zooms the FOV.
-- On touch the default drag-to-look camera is kept; on PC the mouse is locked to the center.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.Parent.UI.Theme)

local CameraController = {}

local SHOULDER_OFFSET = Vector3.new(2.2, 1.2, 0)
local AIM_OFFSET = Vector3.new(1.6, 1.0, 0)
local FOV_DEFAULT = 70
local FOV_AIM = 50
local ZOOM_DISTANCE = 10
local TURN_SPEED = 18 -- higher = character snaps to camera yaw faster
local SPECTATE_DELAY = 2 -- seconds on your own body before the camera moves to a teammate

local player = Players.LocalPlayer
local humanoid: Humanoid?
local root: BasePart?
local diedAt = 0
local spectating: Humanoid?
local spectateLabel: TextLabel

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid") :: Humanoid
	humanoid = h
	root = character:WaitForChild("HumanoidRootPart") :: BasePart
	h.AutoRotate = false
	h.CameraOffset = SHOULDER_OFFSET
	local camera = workspace.CurrentCamera
	camera.CameraSubject = h
	h.Died:Once(function()
		humanoid = nil
		root = nil
		diedAt = os.clock()
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

-- While down, the camera follows a living teammate (the next one when they fall too) until
-- you respawn. With nobody left alive it stays where it is.
local function isAlive(h: Humanoid?): boolean
	return h ~= nil and h.Health > 0 and h:IsDescendantOf(workspace)
end

local function updateSpectate()
	if humanoid or os.clock() - diedAt < SPECTATE_DELAY then
		spectating = nil
		spectateLabel.Visible = false
		return
	end
	if not isAlive(spectating) then
		spectating = nil
		for _, other in Players:GetPlayers() do
			local h = other ~= player
				and other.Character
				and other.Character:FindFirstChildOfClass("Humanoid")
			if h and isAlive(h) then
				spectating = h
				local camera = workspace.CurrentCamera
				camera.CameraSubject = h
				spectateLabel.Text = "OBSERVANDO: " .. other.DisplayName
				break
			end
		end
	end
	spectateLabel.Visible = spectating ~= nil
end

local function step(dt: number)
	updateSpectate()
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

	local screen = Instance.new("ScreenGui")
	screen.Name = "Spectate"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 3
	spectateLabel = Theme.text(screen, "heavy", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(320, 28),
		Visible = false,
	})
	screen.Parent = player:WaitForChild("PlayerGui")
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
