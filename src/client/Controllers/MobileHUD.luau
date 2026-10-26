--!strict
-- Touch HUD: a right-thumb cluster of big buttons around ATIRAR (the crosshair lives in
-- CombatHUD). The cluster scales with screen height so ATIRAR stays ~100 pt and the others
-- ~60 pt from small phones to tablets, all labelled in full. MIRA toggles instead of needing a
-- held thumb; GRANADA shows how many are left; PODER wears a cyan ring when ready and counts
-- down otherwise. The context button holds whichever ProximityPrompt is showing (shop, ammo,
-- repair), so prompts keep their 0.5 s hold without a precise tap.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputController = require(script.Parent.InputController)
local WeaponController = require(script.Parent.WeaponController)
local Theme = require(script.Parent.Parent.UI.Theme)
local Text = require(game:GetService("ReplicatedStorage").Shared.Util.Text)

type Action = InputController.Action

local MobileHUD = {}

local COLOR_PANEL = Color3.fromRGB(20, 20, 24)
local COLOR_TEXT = Color3.fromRGB(240, 240, 240)
local COLOR_FIRE = Color3.fromRGB(220, 40, 40)
local COLOR_CONTEXT = Color3.fromRGB(255, 204, 0)
local COLOR_READY = Color3.fromRGB(0, 200, 230)

-- Button layout inside the cluster frame (scale units of the cluster, a square anchored
-- bottom-right; pos is the button centre). ATIRAR is biggest and sits where the thumb rests;
-- the rest arc around it without touching.
type ButtonSpec = { action: Action, label: string, pos: Vector2, size: number, color: Color3? }
local BUTTONS: { ButtonSpec } = {
	{
		action = "Fire",
		label = "ATIRAR",
		pos = Vector2.new(0.74, 0.72),
		size = 0.36,
		color = COLOR_FIRE,
	},
	{ action = "Aim", label = "MIRA", pos = Vector2.new(0.42, 0.88), size = 0.2 },
	{ action = "Reload", label = "RECARREGAR", pos = Vector2.new(0.46, 0.58), size = 0.2 },
	{ action = "Grenade", label = "GRANADA", pos = Vector2.new(0.62, 0.36), size = 0.2 },
	{ action = "Melee", label = "FACA", pos = Vector2.new(0.88, 0.4), size = 0.2 },
	{ action = "Ability", label = "PODER", pos = Vector2.new(0.18, 0.68), size = 0.2 },
	-- Kept below the cluster's top band, which the ammo panel covers on wide phones.
	{ action = "Jump", label = "PULAR", pos = Vector2.new(0.12, 0.42), size = 0.16 },
}

local player = Players.LocalPlayer
local screen: ScreenGui
local contextButton: TextButton
local abilityButton: TextButton?
local aimButton: TextButton?
local grenadeBadge: TextLabel?
local aiming = false
local shownPrompt: ProximityPrompt?
local holdingPrompt: ProximityPrompt?

local function corner(parent: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

-- `passThrough` buttons are labels that don't sink the touch, so the default camera still
-- turns when that finger drags (ATIRAR: hold to fire and drag to aim with one thumb).
local function makeButton(spec: ButtonSpec, parent: GuiObject, passThrough: boolean?): TextButton
	local b: any = Instance.new(if passThrough then "TextLabel" else "TextButton")
	b.Name = spec.action
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(spec.pos.X, spec.pos.Y)
	b.Size = UDim2.fromScale(spec.size, spec.size)
	b.BackgroundColor3 = spec.color or COLOR_PANEL
	b.BackgroundTransparency = 0.35
	b.Text = spec.label
	b.TextColor3 = COLOR_TEXT
	b.FontFace = Theme.FONT.heavy
	b.TextScaled = true
	if passThrough then
		b.Active = false
	else
		b.AutoButtonColor = false
	end
	corner(b, UDim.new(0.5, 0))

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.1, 0)
	pad.PaddingRight = UDim.new(0.1, 0)
	pad.PaddingTop = UDim.new(0.3, 0)
	pad.PaddingBottom = UDim.new(0.3, 0)
	pad.Parent = b

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = COLOR_TEXT
	stroke.Transparency = 0.6
	stroke.Thickness = 2
	stroke.Parent = b

	b.Parent = parent
	return b
end

-- Press/release wiring. InputEnded on the button can be missed if the finger slides off, so
-- we also release on the touch's global end. Pass-through buttons never receive input
-- themselves, so their press is a hit test of every touch that starts.
local function bindHold(button: GuiObject, onDown: () -> (), onUp: () -> (), passThrough: boolean?)
	local activeTouch: InputObject? = nil
	local function press(input: InputObject)
		activeTouch = input
		button.BackgroundTransparency = 0.1
		onDown()
	end
	if passThrough then
		UserInputService.TouchStarted:Connect(function(input)
			if activeTouch or not button.Visible then
				return
			end
			local radius = button.AbsoluteSize.X / 2
			local center = button.AbsolutePosition + button.AbsoluteSize / 2
			local point = Vector2.new(input.Position.X, input.Position.Y)
			if (point - center).Magnitude <= radius then
				press(input)
			end
		end)
	else
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch and not activeTouch then
				press(input)
			end
		end)
	end
	UserInputService.TouchEnded:Connect(function(input)
		if input == activeTouch then
			activeTouch = nil
			button.BackgroundTransparency = 0.35
			onUp()
		end
	end)
end

-- Changes state directly: setting Humanoid.Jump is overwritten every frame by the default
-- ControlModule (whose own jump button we hide), so the jump never happened.
local function jump()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

-- Roblox's own jump button overlaps our cluster; ours replaces it.
local function hideDefaultJump()
	local touchGui = player:WaitForChild("PlayerGui"):WaitForChild("TouchGui", 10)
	local frame = touchGui and touchGui:WaitForChild("TouchControlFrame", 10)
	local jumpButton = frame and frame:WaitForChild("JumpButton", 10)
	if jumpButton and jumpButton:IsA("GuiObject") then
		jumpButton.Visible = false
		jumpButton:GetPropertyChangedSignal("Visible"):Connect(function()
			jumpButton.Visible = false
		end)
	end
end

local function buildTouchCluster()
	local cluster = Instance.new("Frame")
	cluster.Name = "ActionCluster"
	cluster.AnchorPoint = Vector2.new(1, 1)
	cluster.Position = UDim2.new(1, -16, 1, -16)
	cluster.Size = UDim2.fromScale(0.8, 0.8)
	cluster.BackgroundTransparency = 1
	cluster.Parent = screen

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = cluster

	for _, spec in BUTTONS do
		local passThrough = spec.action == "Fire"
		local button = makeButton(spec, cluster, passThrough)
		if spec.action == "Ability" then
			abilityButton = button
		elseif spec.action == "Aim" then
			aimButton = button
		elseif spec.action == "Grenade" then
			local badge = Instance.new("TextLabel")
			badge.Name = "Count"
			badge.AnchorPoint = Vector2.new(0.5, 0.5)
			badge.Position = UDim2.fromScale(0.86, 0.14)
			badge.Size = UDim2.fromScale(0.42, 0.42)
			badge.BackgroundColor3 = COLOR_CONTEXT
			badge.TextColor3 = COLOR_PANEL
			badge.FontFace = Theme.FONT.heavy
			badge.TextScaled = true
			corner(badge, UDim.new(0.5, 0))
			badge.Parent = button
			grenadeBadge = badge
		end
		local action = spec.action
		if action == "Aim" then
			-- A toggle on touch: holding a second thumb on MIRA while firing is awkward.
			bindHold(button, function()
				aiming = not aiming
				InputController.setAction("Aim", aiming)
			end, function() end)
			continue
		end
		bindHold(button, function()
			InputController.setAction(action, true)
			if action == "Jump" then
				jump()
			end
		end, function()
			InputController.setAction(action, false)
		end, passThrough)
	end

	-- Context button: only visible while a prompt is on screen; label mirrors the prompt.
	contextButton = makeButton({
		action = "Interact",
		label = "USAR",
		pos = Vector2.new(0.34, 0.32),
		size = 0.2,
		color = COLOR_CONTEXT,
	}, cluster)
	contextButton.TextColor3 = COLOR_PANEL
	contextButton.Visible = false
	bindHold(contextButton, function()
		InputController.setAction("Interact", true)
		if shownPrompt then
			holdingPrompt = shownPrompt
			shownPrompt:InputHoldBegin()
		end
	end, function()
		InputController.setAction("Interact", false)
		if holdingPrompt then
			holdingPrompt:InputHoldEnd()
			holdingPrompt = nil
		end
	end)
end

local function watchPrompts()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		shownPrompt = prompt
		contextButton.Text = Text.upper(prompt.ActionText)
		contextButton.Visible = true
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if prompt == shownPrompt then
			shownPrompt = nil
			contextButton.Visible = false
		end
	end)
end

function MobileHUD.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "SwarmHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
end

function MobileHUD.start()
	-- Always landscape on phones, whichever way the device is held (also set on StarterGui).
	player:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	if UserInputService.TouchEnabled then
		buildTouchCluster()
		watchPrompts()
		-- Our context button replaces the built-in prompt tap target.
		ProximityPromptService.MaxPromptsVisible = 1
		task.spawn(hideDefaultJump)
		-- Live button states: PODER's cooldown/ready ring, MIRA on/off, grenades left.
		RunService.RenderStepped:Connect(function()
			-- A menu or death can release Aim behind our back; keep the toggle in sync.
			if aiming and not InputController.isDown("Aim") then
				aiming = false
			end
			local aim = aimButton
			if aim then
				aim.BackgroundColor3 = if aiming then COLOR_READY else COLOR_PANEL
			end
			local badge = grenadeBadge
			if badge then
				local count = WeaponController.view.grenades
				badge.Text = tostring(count)
				badge.BackgroundColor3 = if count > 0
					then COLOR_CONTEXT
					else Color3.fromRGB(90, 90, 90)
			end
			local button = abilityButton
			if not button then
				return
			end
			local readyAt = player:GetAttribute("AbilityReadyAt")
			local left = if typeof(readyAt) == "number"
				then readyAt - workspace:GetServerTimeNow()
				else 0
			button.Text = if left > 0 then tostring(math.ceil(left)) else "PODER"
			button.TextTransparency = if left > 0 then 0.35 else 0
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if left > 0 then COLOR_TEXT else COLOR_READY
				stroke.Transparency = if left > 0 then 0.7 else 0
				stroke.Thickness = if left > 0 then 2 else 4
			end
		end)
	end

	screen.Parent = player:WaitForChild("PlayerGui")
end

return MobileHUD
