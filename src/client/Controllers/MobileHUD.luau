--!strict
-- Touch HUD: a right-thumb cluster of big buttons around the Fire button (the crosshair lives
-- in CombatHUD). Sizes scale with screen height so they stay thumb-sized from small phones
-- to tablets. The context button holds whichever ProximityPrompt is showing
-- (shop, ammo, repair), so prompts keep their 0.5 s hold without a precise tap.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.Parent.UI.Theme)
local Text = require(game:GetService("ReplicatedStorage").Shared.Util.Text)

type Action = InputController.Action

local MobileHUD = {}

local COLOR_PANEL = Color3.fromRGB(20, 20, 24)
local COLOR_TEXT = Color3.fromRGB(240, 240, 240)
local COLOR_FIRE = Color3.fromRGB(220, 40, 40)
local COLOR_CONTEXT = Color3.fromRGB(255, 204, 0)

-- Button layout inside the cluster frame (scale units of the cluster, which is a square
-- anchored bottom-right). Fire is biggest and sits where the thumb rests.
type ButtonSpec = { action: Action, label: string, pos: Vector2, size: number, color: Color3? }
local BUTTONS: { ButtonSpec } = {
	{
		action = "Fire",
		label = "ATIRAR",
		pos = Vector2.new(0.62, 0.62),
		size = 0.34,
		color = COLOR_FIRE,
	},
	{ action = "Jump", label = "PULAR", pos = Vector2.new(0.90, 0.30), size = 0.17 },
	{ action = "Aim", label = "MIRA", pos = Vector2.new(0.30, 0.78), size = 0.2 },
	{ action = "Reload", label = "RECAR", pos = Vector2.new(0.36, 0.46), size = 0.17 },
	{ action = "Melee", label = "FACA", pos = Vector2.new(0.62, 0.26), size = 0.17 },
	{ action = "Grenade", label = "GRAN", pos = Vector2.new(0.10, 0.56), size = 0.15 },
	{ action = "Ability", label = "HABIL", pos = Vector2.new(0.36, 0.14), size = 0.2 },
}

local player = Players.LocalPlayer
local screen: ScreenGui
local contextButton: TextButton
local abilityButton: TextButton?
local shownPrompt: ProximityPrompt?
local holdingPrompt: ProximityPrompt?

local function corner(parent: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function makeButton(spec: ButtonSpec, parent: GuiObject): TextButton
	local b = Instance.new("TextButton")
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
	b.AutoButtonColor = false
	corner(b, UDim.new(0.5, 0))

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.18, 0)
	pad.PaddingRight = UDim.new(0.18, 0)
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
-- we also release on the touch's global end.
local function bindHold(button: GuiButton, onDown: () -> (), onUp: () -> ())
	local activeTouch: InputObject? = nil
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not activeTouch then
			activeTouch = input
			button.BackgroundTransparency = 0.1
			onDown()
		end
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if input == activeTouch then
			activeTouch = nil
			button.BackgroundTransparency = 0.35
			onUp()
		end
	end)
end

local function jump()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Jump = true
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
	cluster.Size = UDim2.fromScale(0.55, 0.55)
	cluster.BackgroundTransparency = 1
	cluster.Parent = screen

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = cluster

	for _, spec in BUTTONS do
		local button = makeButton(spec, cluster)
		if spec.action == "Ability" then
			abilityButton = button
		end
		local action = spec.action
		bindHold(button, function()
			InputController.setAction(action, true)
			if action == "Jump" then
				jump()
			end
		end, function()
			InputController.setAction(action, false)
		end)
	end

	-- Context button: only visible while a prompt is on screen; label mirrors the prompt.
	contextButton = makeButton({
		action = "Interact",
		label = "USAR",
		pos = Vector2.new(0.08, 0.2),
		size = 0.22,
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
	if UserInputService.TouchEnabled then
		buildTouchCluster()
		watchPrompts()
		-- Our context button replaces the built-in prompt tap target.
		ProximityPromptService.MaxPromptsVisible = 1
		task.spawn(hideDefaultJump)
		-- Ability button shows its cooldown in seconds and dims until ready.
		RunService.RenderStepped:Connect(function()
			local button = abilityButton
			if not button then
				return
			end
			local readyAt = player:GetAttribute("AbilityReadyAt")
			local left = if typeof(readyAt) == "number"
				then readyAt - workspace:GetServerTimeNow()
				else 0
			button.Text = if left > 0 then tostring(math.ceil(left)) else "HABIL"
			button.TextTransparency = if left > 0 then 0.4 else 0
		end)
	end

	screen.Parent = player:WaitForChild("PlayerGui")
end

return MobileHUD
