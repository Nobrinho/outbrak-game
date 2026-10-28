--!strict
-- Touch combat controls reserve the native movement/jump zones. Aim toggles, firing
-- permits drag-to-look, and every held action is released on a modal, death or focus loss.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputController = require(script.Parent.InputController)
local WeaponController = require(script.Parent.WeaponController)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)
local AssetView = require(script.Parent.Parent.UI.AssetView)
local Settings = require(script.Parent.Parent.UI.ControlSettings)
local TouchRouter = require(script.Parent.Parent.UI.TouchRouter)
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
		pos = Vector2.new(0.82, 0.79),
		size = 76 / 210,
		color = COLOR_FIRE,
	},
	{ action = "Aim", label = "MIRA", pos = Vector2.new(0.13, 0.60), size = 52 / 210 },
	{ action = "Reload", label = "RECARGA", pos = Vector2.new(0.43, 0.86), size = 52 / 210 },
	{ action = "Grenade", label = "GRANADA", pos = Vector2.new(0.13, 0.15), size = 52 / 210 },
	{ action = "Ability", label = "PODER", pos = Vector2.new(0.43, 0.15), size = 52 / 210 },
}

local ACTION_ICON = {
	Fire = "aim",
	Aim = "aim",
	Reload = "reload",
	Grenade = "grenade",
	Melee = "melee",
	Ability = "fire",
	Jump = "jump",
	Interact = "interact",
}

local player = Players.LocalPlayer
local screen: ScreenGui
local contextButton: TextButton
local abilityButton: TextButton?
local aimButton: TextButton?
local grenadeBadge: TextLabel?
local actionButtons: { [Action]: TextButton } = {}
local aiming = false
local router = TouchRouter.new()
local hitTargets: { [GuiObject]: GuiObject } = {}
local function idleTransparency(): number
	return Settings.get("transparency")
end
local function cancelTouches()
	router.cancel()
	aiming = false
	InputController.setAction("Aim", false, "touch.Aim")
end
local contextFill: Frame?
local holdStarted = 0
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
	local target: any = Instance.new(if passThrough then "Frame" else "TextButton")
	target.Name = spec.action
	target.BackgroundTransparency = 1
	target.BorderSizePixel = 0
	target.Active = not passThrough
	if not passThrough then
		target.Text = ""
		target.AutoButtonColor = false
	end
	target:SetAttribute("TouchTarget", true)
	target.Parent = parent
	local b: any = Instance.new("TextLabel")
	hitTargets[b] = target
	b.Name = spec.action
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(0.5, 0.5)
	b.Size = UDim2.new(1, -6, 1, -6)
	b.BackgroundColor3 = spec.color or COLOR_PANEL
	b.BackgroundTransparency = idleTransparency()
	b.Text = spec.label
	b.TextColor3 = COLOR_TEXT
	b.FontFace = Theme.FONT.heavy
	b.TextScaled = true
	b.Active = false
	corner(b, UDim.new(0.5, 0))
	local surface = AssetView.slice(b, "ui.buttons.touch-normal", b.BackgroundTransparency)
	if surface then
		corner(surface, UDim.new(0.5, 0))
		b:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
			surface.ImageTransparency = b.BackgroundTransparency
			surface.Image = AssetView.resolve(
				if b.BackgroundTransparency < 0.2
					then "ui.buttons.touch-pressed"
					else "ui.buttons.touch-normal"
			) or surface.Image
		end)
	end

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

	local icon = Theme.image(b, "ui.icons." .. (ACTION_ICON[spec.action] or "interact"), {
		Position = UDim2.fromScale(0.28, 0.06),
		Size = UDim2.fromScale(0.44, 0.44),
		ImageColor3 = COLOR_TEXT,
	})
	if icon then
		pad:Destroy()
		local caption = Theme.text(b, "heavy", {
			Position = UDim2.fromScale(0.06, 0.57),
			Size = UDim2.fromScale(0.88, 0.3),
			Text = b.Text,
			TextColor3 = b.TextColor3,
		})
		b.TextTransparency = 1
		b:GetPropertyChangedSignal("Text"):Connect(function()
			caption.Text = b.Text
		end)
		b:GetPropertyChangedSignal("TextColor3"):Connect(function()
			caption.TextColor3 = b.TextColor3
			icon.ImageColor3 = b.TextColor3
		end)
		local mirroring = false
		b:GetPropertyChangedSignal("TextTransparency"):Connect(function()
			if mirroring or b.TextTransparency == 1 then
				return
			end
			caption.TextTransparency = b.TextTransparency
			mirroring = true
			b.TextTransparency = 1
			mirroring = false
		end)
	end
	b.Parent = target
	return b
end

-- A gesture can only acquire a control at its starting point. Crossing another target
-- never transfers ownership. Fire is deliberately transparent to Roblox's camera.
local function bindHold(button: GuiObject, onDown: () -> (), onUp: () -> (), passThrough: boolean?)
	local target = hitTargets[button]
	local function press(input: InputObject)
		if not screen.Enabled or not target.Visible or InputController.isModalOpen() then
			return
		end
		local claimed = router.claim(input, target.Name, function()
			button.BackgroundTransparency = idleTransparency()
			target:SetAttribute("Pressed", false)
			onUp()
		end)
		if not claimed then
			return
		end
		button.BackgroundTransparency = 0.08
		target:SetAttribute("Pressed", true)
		onDown()
	end
	if passThrough then
		UserInputService.TouchStarted:Connect(function(input, processed)
			if processed or not screen.Enabled or InputController.isModalOpen() then
				return
			end
			local point = Vector2.new(input.Position.X, input.Position.Y)
			local p, size = target.AbsolutePosition, target.AbsoluteSize
			if
				point.X < p.X
				or point.Y < p.Y
				or point.X >= p.X + size.X
				or point.Y >= p.Y + size.Y
			then
				return
			end
			-- An unrelated active overlay must not leak a press through to a weapon.
			for _, object in player.PlayerGui:GetGuiObjectsAtPosition(point.X, point.Y) do
				if object.Active and object ~= target and not object:IsDescendantOf(target) then
					return
				end
			end
			press(input)
		end)
	else
		target.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				press(input)
			end
		end)
	end
end

local function buildTouchCluster()
	local cluster = Instance.new("Frame")
	cluster.Name = "ActionCluster"
	cluster.Size = UDim2.fromScale(1, 1)
	cluster.BackgroundTransparency = 1
	cluster.Active = false
	cluster.Parent = screen

	for _, spec in BUTTONS do
		local passThrough = spec.action == "Fire"
		local button = makeButton(spec, cluster, passThrough)
		actionButtons[spec.action] = button
		if spec.action == "Ability" then
			abilityButton = button
		elseif spec.action == "Aim" then
			aimButton = button
		elseif spec.action == "Grenade" then
			local badge = Instance.new("TextLabel")
			badge.Name = "Count"
			badge.AnchorPoint = Vector2.new(0.5, 0.5)
			badge.Position = UDim2.fromScale(0.79, 0.21)
			badge.Size = UDim2.fromScale(0.32, 0.32)
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
				aiming = if Settings.get("aimMode") == "hold" then true else not aiming
				InputController.setAction("Aim", aiming, "touch.Aim")
			end, function()
				if Settings.get("aimMode") == "hold" then
					aiming = false
					InputController.setAction("Aim", false, "touch.Aim")
				end
			end)
			continue
		end
		bindHold(button, function()
			InputController.setAction(action, true, "touch." .. action)
		end, function()
			InputController.setAction(action, false, "touch." .. action)
		end, passThrough)
	end

	-- Context button: only visible while a prompt is on screen; label mirrors the prompt.
	contextButton = makeButton({
		action = "Interact",
		label = "USAR",
		pos = Vector2.new(0.34, 0.32),
		size = 0.2,
		color = COLOR_CONTEXT,
	}, screen)
	contextButton.TextColor3 = COLOR_PANEL
	contextButton.Visible = true
	hitTargets[contextButton].Visible = false
	bindHold(contextButton, function()
		InputController.setAction("Interact", true, "touch.Interact")
		if shownPrompt then
			holdingPrompt = shownPrompt
			holdStarted = os.clock()
			shownPrompt:InputHoldBegin()
		end
	end, function()
		InputController.setAction("Interact", false, "touch.Interact")
		if holdingPrompt then
			holdingPrompt:InputHoldEnd()
			holdingPrompt = nil
		end
	end)
	local fill = Instance.new("Frame")
	fill.Name = "HoldProgress"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(0, 0.06)
	fill.BackgroundColor3 = COLOR_PANEL
	fill.BorderSizePixel = 0
	fill.Parent = contextButton
	contextFill = fill
	local knife =
		makeButton({ action = "Melee", label = "FACA", pos = Vector2.zero, size = 1 }, screen)
	knife.Name = "MeleeQuickSlot"
	hitTargets[knife].Name = "MeleeQuickSlot"
	bindHold(knife, function()
		InputController.setAction("Melee", true, "touch.Melee")
	end, function()
		InputController.setAction("Melee", false, "touch.Melee")
	end)
	local geometryKey = ""
	Layout.bind(screen, function(m)
		local model = m.mobile
		local key = string.format(
			"%s:%s:%s:%s:%s:%s",
			m.size.X,
			m.size.Y,
			m.origin.X,
			m.origin.Y,
			model.profile,
			model.enlargement
		)
		-- Also cancel on native jump relocation; never move an active target under a finger.
		key ..= string.format(":%s:%s", model.jump.x, model.jump.y)
		if key ~= geometryKey then
			cancelTouches()
			geometryKey = key
		end
		for action, button in actionButtons do
			Layout.place(hitTargets[button], model.actions[action])
		end
		Layout.place(hitTargets[knife], model.actions.Melee)
		Layout.place(hitTargets[contextButton], model.actions.Interact)
		screen:SetAttribute("LayoutProfile", model.profile)
		screen:SetAttribute("LayoutValid", model.valid)
		screen:SetAttribute("ControlsEnlarged", model.enlargement > 1)
		screen:SetAttribute("LayoutErrors", table.concat(model.errors, "; "))
		if not model.valid then
			warn("[HUD] Unsupported safe area: " .. table.concat(model.errors, "; "))
		end
	end)
	Settings.changed:connect(function(key)
		if key == "aimMode" then
			cancelTouches()
		end
		if key == "transparency" then
			for visual, target in hitTargets do
				if not target:GetAttribute("Pressed") then
					visual.BackgroundTransparency = idleTransparency()
				end
			end
		end
	end)
end

local function watchPrompts()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if holdingPrompt and holdingPrompt ~= prompt then
			router.cancel()
		end
		shownPrompt = prompt
		contextButton.Text = Text.upper(prompt.ActionText)
		hitTargets[contextButton].Visible = screen.Enabled
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if prompt == shownPrompt then
			if holdingPrompt then
				holdingPrompt:InputHoldEnd()
				holdingPrompt = nil
			end
			InputController.setAction("Interact", false, "touch.Interact")
			shownPrompt = nil
			hitTargets[contextButton].Visible = false
		end
	end)
end

function MobileHUD.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "SwarmHUD"
	screen.Enabled = false
	Layout.configure(screen, 20)
end

function MobileHUD.start()
	-- Always landscape on phones, whichever way the device is held (also set on StarterGui).
	player:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	if UserInputService.TouchEnabled then
		buildTouchCluster()
		watchPrompts()
		-- Our context button replaces the built-in prompt tap target.
		ProximityPromptService.MaxPromptsVisible = 1
		-- Live button states: PODER's cooldown/ready ring, MIRA on/off, grenades left.
		RunService.RenderStepped:Connect(function()
			local match = ReplicatedStorage:FindFirstChild("Match")
			local phase = match and match:GetAttribute("Phase")
			local character = player.Character
			local human = character and character:FindFirstChildOfClass("Humanoid")
			local enabled = Layout.isTouch()
				and not InputController.isModalOpen()
				and player:GetAttribute("InMatch") == true
				and human ~= nil
				and human.Health > 0
				and (phase == "Prep" or phase == "Wave" or phase == "Final" or phase == "Extract")
			if screen.Enabled and not enabled then
				cancelTouches()
			end
			screen.Enabled = enabled
			hitTargets[contextButton].Visible = shownPrompt ~= nil and enabled
			if contextFill then
				contextFill.Size = UDim2.fromScale(
					if holdingPrompt
						then math.clamp(
							(os.clock() - holdStarted) / math.max(holdingPrompt.HoldDuration, 0.01),
							0,
							1
						)
						else 0,
					0.06
				)
			end
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

	InputController.cancelled:connect(function()
		cancelTouches()
	end)
	UserInputService.TouchEnded:Connect(function(input)
		router.release(input)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputState == Enum.UserInputState.Cancel then
			router.release(input)
		end
	end)
	screen.Parent = player:WaitForChild("PlayerGui")
end

return MobileHUD
