--!strict
-- Over-the-shoulder third-person camera. The character always faces where the camera looks
-- (shooter-style), the camera sits offset to the right shoulder, and aiming zooms the FOV.
-- On touch the default drag-to-look camera is kept; on PC the mouse is locked to the center
-- (except while Alt is held, so the screen buttons can be clicked).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local InputController = require(script.Parent.InputController)
local Settings = require(script.Parent.Parent.UI.ControlSettings)
local Hotkeys = require(script.Parent.Parent.UI.Hotkeys)
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
local frozenForModal = false
local spectateLabel: TextLabel
local beforeNativeRotation = CFrame.identity
local cameraTouchMoved = false
local collision = RaycastParams.new()
collision.FilterType = Enum.RaycastFilterType.Exclude
collision.RespectCanCollide = true
local function tuneTouchRotation()
	if not cameraTouchMoved or not InputController.isTouch() or InputController.isModalOpen() then
		cameraTouchMoved = false
		return
	end
	cameraTouchMoved = false
	local camera = workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Custom or not humanoid then
		return
	end
	local factor =
		Settings.get(if InputController.isDown("Aim") then "aimSensitivity" else "sensitivity")
	if factor == 1 then
		return
	end
	-- Scale the rotation already produced by the native camera once. Do not apply a
	-- second TouchMoved delta or replace Roblox movement, orbit and camera ownership.
	local native = camera.CFrame
	local rotation = beforeNativeRotation:Lerp(native.Rotation, factor)
	local focus = camera.Focus.Position
	local localFocus = native:PointToObjectSpace(focus)
	local adjusted = CFrame.new(focus) * rotation * CFrame.new(-localFocus)
	collision.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local ray = workspace:Raycast(focus, adjusted.Position - focus, collision)
	if ray then
		adjusted = CFrame.new(ray.Position + ray.Normal * 0.25) * rotation
	end
	camera.CFrame = adjusted
end

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
	tuneTouchRotation()
	updateSpectate()
	local camera = workspace.CurrentCamera
	if InputController.isModalOpen() then
		frozenForModal = true
		camera.CameraType = Enum.CameraType.Scriptable
	elseif frozenForModal then
		-- Always back to Custom: a modal that opens before the character spawns (class picker)
		-- would otherwise save the engine's pre-spawn Fixed camera and restore a frozen one.
		frozenForModal = false
		camera.CameraType = Enum.CameraType.Custom
	end
	UserInputService.MouseBehavior = if InputController.isModalOpen()
			or InputController.isTouch()
			or Hotkeys.cursorReleased()
		then Enum.MouseBehavior.Default
		else Enum.MouseBehavior.LockCenter

	local h, r = humanoid, root
	if not (h and r) or h.Sit or InputController.isModalOpen() then
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
	UserInputService.TouchMoved:Connect(function(_, processed)
		if not processed then
			cameraTouchMoved = true
		end
	end)
	InputController.cancelled:connect(function()
		cameraTouchMoved = false
	end)
	RunService:BindToRenderStep(
		"SwarmCameraBefore",
		Enum.RenderPriority.Camera.Value - 1,
		function()
			beforeNativeRotation = workspace.CurrentCamera.CFrame.Rotation
		end
	)
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
