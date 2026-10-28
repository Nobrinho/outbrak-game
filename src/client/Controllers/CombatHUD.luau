--!strict
-- Combat HUD, one job per corner so it reads at a glance on a phone:
--   lower-left — health and credits (above the native stick on touch);
--   lower-right on PC / quick slots on touch — weapon and ammunition;
--   centre    — a ring crosshair, a reload bar under it and a hitmarker that flashes white on
--               body hits and orange on headshots.
-- On touch the grenade count and the ability cooldown live on their buttons (MobileHUD). The
-- crosshair layer ignores every inset so its center is exactly the camera ray's center.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Text = require(Shared.Util.Text)
local WeaponController = require(script.Parent.WeaponController)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)
local Input = require(script.Parent.InputController)

local AssetView = require(script.Parent.Parent.UI.AssetView)

local CombatHUD = {}

local COLOR_TEXT = Color3.fromRGB(240, 240, 240)
local COLOR_LOW = Color3.fromRGB(220, 40, 40)
local COLOR_HEAD = Color3.fromRGB(255, 140, 20)

local ammoPanel: Frame
local vitalsPanel: Frame
local screen: ScreenGui
local center: ScreenGui
local magLabel: TextLabel
local reserveLabel: TextLabel
local gunLabel: TextLabel
local gunImage: ImageLabel?
local grenadeLabel: TextLabel
local creditsLabel: TextLabel
local healthFill: Frame
local healthBack: Frame
local healthTitle: TextLabel
local creditIcon: ImageLabel?
local healthIcon: ImageLabel?
local healthLabel: TextLabel
local vignette: { Frame } = {}
local damageFlash = 0 -- 0..1, decays every frame
local abilityLabel: TextLabel
local reloadBar: Frame
local reloadFill: Frame
local reloadStartedAt = 0
local hitmarker: Frame
local hitTicks: { Frame } = {}
local hitTween: Tween? = nil

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = COLOR_TEXT
	l.FontFace = Theme.FONT.heavy
	l.TextStrokeTransparency = 0.75
	l.TextScaled = true
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function buildAmmoPanel()
	local panel = Instance.new("Frame")
	ammoPanel = panel
	panel.Name = "Ammo"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 16)
	panel.Size = UDim2.fromScale(0.24, 0.2)
	Theme.panel(panel)
	panel.Parent = screen
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 2.1
	aspect:Destroy()

	magLabel = label(panel, {
		Position = UDim2.fromScale(0.05, 0.02),
		Size = UDim2.fromScale(0.5, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	reserveLabel = label(panel, {
		Position = UDim2.fromScale(0.57, 0.18),
		Size = UDim2.fromScale(0.4, 0.28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.3,
	})
	gunLabel = label(panel, {
		Position = UDim2.fromScale(0.3, 0.52),
		Size = UDim2.fromScale(0.65, 0.2),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTransparency = 0.15,
	})
	gunImage = Theme.image(
		panel,
		"weapons.Pistol",
		{ Position = UDim2.fromScale(0.03, 0.46), Size = UDim2.fromScale(0.25, 0.28) }
	)
	-- Keyboards only: on touch these live on the grenade and ability buttons.
	local keyboard = not Layout.isTouch()
	grenadeLabel = label(panel, {
		Position = UDim2.fromScale(0.05, 0.74),
		Size = UDim2.fromScale(0.9, 0.2),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.COLOR.muted,
		Visible = keyboard,
	})
	abilityLabel = label(screen, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(260, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = keyboard,
	})
end

-- Health bar with its number and, under it, the credits: the two things you check most.
local function buildVitals()
	local vitals = Instance.new("Frame")
	vitalsPanel = vitals
	vitals.Name = "Vitals"
	vitals.Position = UDim2.fromOffset(16, 16)
	vitals.Size = UDim2.fromScale(0.3, 0.1)
	Theme.panel(vitals)
	vitals.Parent = screen
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = vitals
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 4.2
	aspect:Destroy()
	-- Thumb-readable on small phones, not oversized on monitors; the CLASSE/level/VIP column
	-- starts below the max height (ClassController, ProgressionHUD).
	local limits = Instance.new("UISizeConstraint")
	limits.MinSize = Vector2.new(220, 52)
	limits.MaxSize = Vector2.new(380, 90)
	limits:Destroy()

	healthTitle = label(vitals, {
		Position = UDim2.fromScale(0.1, 0),
		Size = UDim2.fromScale(0.14, 0.48),
		Text = "VIDA",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local back = Instance.new("Frame")
	healthBack = back
	back.Position = UDim2.fromScale(0.26, 0.06)
	back.Size = UDim2.fromScale(0.54, 0.36)
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BackgroundTransparency = 0.35
	back.BorderSizePixel = 0
	back.Parent = vitals
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 4)
	backCorner.Parent = back
	healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Theme.COLOR.player
	healthFill.BorderSizePixel = 0
	healthFill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = healthFill
	healthLabel = label(vitals, {
		Position = UDim2.fromScale(0.82, 0),
		Size = UDim2.fromScale(0.18, 0.48),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	healthIcon = Theme.image(vitals, "ui.icons.health", {
		Position = UDim2.fromScale(0, 0.04),
		Size = UDim2.fromScale(0.08, 0.4),
		ImageColor3 = Theme.COLOR.player,
	})
	creditIcon = Theme.image(vitals, "ui.icons.credits", {
		Position = UDim2.fromScale(0, 0.56),
		Size = UDim2.fromScale(0.08, 0.36),
		ImageColor3 = Theme.COLOR.accent,
	})
	creditsLabel = label(vitals, {
		Position = UDim2.fromScale(0.1, 0.54),
		Size = UDim2.fromScale(0.6, 0.46),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLOR.accent,
	})
end

-- Red edges that flash on damage and pulse when health is low. Four gradient strips in the
-- inset-free layer, so they hug the real screen edges.
local function buildVignette()
	for i, spec in
		{
			{ anchor = Vector2.new(0, 0), size = UDim2.fromScale(1, 0.18), rotation = 90 },
			{ anchor = Vector2.new(0, 1), size = UDim2.fromScale(1, 0.18), rotation = -90 },
			{ anchor = Vector2.new(0, 0), size = UDim2.fromScale(0.12, 1), rotation = 0 },
			{ anchor = Vector2.new(1, 0), size = UDim2.fromScale(0.12, 1), rotation = 180 },
		}
	do
		local edge = Instance.new("Frame")
		edge.Name = "Vignette" .. i
		edge.AnchorPoint = spec.anchor
		edge.Position = UDim2.fromScale(spec.anchor.X, spec.anchor.Y)
		edge.Size = spec.size
		edge.BackgroundColor3 = Theme.COLOR.danger
		edge.BackgroundTransparency = 1
		edge.BorderSizePixel = 0
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec.rotation
		gradient.Transparency = NumberSequence.new(0, 1) -- solid at the edge, clear inward
		gradient.Parent = edge
		edge.Parent = center
		table.insert(vignette, edge)
	end
end

local function humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function updateHealth(dt: number)
	local h = humanoid()
	local ratio = if h and h.MaxHealth > 0 then math.clamp(h.Health / h.MaxHealth, 0, 1) else 0
	healthFill.Size = UDim2.fromScale(ratio, 1)
	healthFill.BackgroundColor3 = if ratio < 0.35 then Theme.COLOR.danger else Theme.COLOR.player
	healthLabel.Text = if h then tostring(math.ceil(h.Health)) else ""

	damageFlash = math.max(0, damageFlash - dt * 1.8)
	local lowPulse = if h
			and h.Health > 0
			and ratio < 0.35
		then 0.25 + 0.15 * math.sin(os.clock() * 5)
		else 0
	local strength = math.max(damageFlash, lowPulse)
	for _, edge in vignette do
		edge.BackgroundTransparency = 1 - strength
	end
end

local function watchDamage(character: Model)
	local h = character:WaitForChild("Humanoid", 10)
	if not h or not h:IsA("Humanoid") then
		return
	end
	local last = h.Health
	h.HealthChanged:Connect(function(health)
		if health < last then
			damageFlash = math.min(0.7, damageFlash + (last - health) / h.MaxHealth * 3 + 0.2)
		end
		last = health
	end)
end

-- "+N" that rises from the credits line whenever credits go up.
local function creditPopup(amount: number)
	if not creditsLabel.Visible then
		return
	end
	local popup = label(vitalsPanel, {
		Position = UDim2.fromOffset(
			creditsLabel.AbsolutePosition.X
				- vitalsPanel.AbsolutePosition.X
				+ creditsLabel.TextBounds.X
				+ 10,
			creditsLabel.AbsolutePosition.Y - vitalsPanel.AbsolutePosition.Y
		),
		Size = UDim2.fromOffset(90, creditsLabel.AbsoluteSize.Y),
		Text = "+" .. amount,
		TextColor3 = Theme.COLOR.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, info, {
		Position = popup.Position - UDim2.fromOffset(0, 30),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1, popup.Destroy, popup)
end

local function refreshStatus()
	local player = Players.LocalPlayer
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Créditos")
	creditsLabel.Text = "$ " .. (if value and value:IsA("IntValue") then value.Value else 0)

	local class = Config.CLASSES[player:GetAttribute("Class") :: Types.ClassId]
		or Config.CLASSES[Config.DEFAULT_CLASS]
	local readyAt = player:GetAttribute("AbilityReadyAt")
	local left = if typeof(readyAt) == "number" then readyAt - workspace:GetServerTimeNow() else 0
	abilityLabel.Text = "[Q] "
		.. Text.upper(class.ability.name)
		.. (if left > 0 then string.format(" — %ds", math.ceil(left)) else " — PRONTA")
	abilityLabel.TextColor3 = if left > 0 then Theme.COLOR.muted else Theme.COLOR.player

	local view = WeaponController.view
	reloadBar.Visible = view.reloading
	if view.reloading then
		local duration = Config.GUNS[view.gun].reloadTime
		reloadFill.Size = UDim2.fromScale(
			math.clamp((os.clock() - reloadStartedAt) / math.max(duration, 0.05), 0, 1),
			1
		)
	end
end

local function buildCenter()
	-- A thin ring reads better than a dot on a busy, dark screen and leaves the target visible.
	local ring = Instance.new("Frame")
	ring.Name = "Crosshair"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(20, 20)
	ring.BackgroundTransparency = 1
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_TEXT
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.Parent = ring
	ring.Parent = center
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(3, 3)
	dot.BackgroundColor3 = COLOR_TEXT
	dot.BorderSizePixel = 0
	dot.Parent = center

	-- Reload progress: a short bar under the crosshair that fills over the reload time.
	reloadBar = Instance.new("Frame")
	reloadBar.Name = "Reload"
	reloadBar.AnchorPoint = Vector2.new(0.5, 0)
	reloadBar.Position = UDim2.new(0.5, 0, 0.5, 22)
	reloadBar.Size = UDim2.fromOffset(70, 6)
	reloadBar.BackgroundColor3 = Color3.new(0, 0, 0)
	reloadBar.BackgroundTransparency = 0.35
	reloadBar.BorderSizePixel = 0
	reloadBar.Visible = false
	reloadBar.Parent = center
	reloadFill = Instance.new("Frame")
	reloadFill.BackgroundColor3 = Theme.COLOR.accent
	reloadFill.BorderSizePixel = 0
	reloadFill.Size = UDim2.fromScale(0, 1)
	reloadFill.Parent = reloadBar

	-- Four short diagonal ticks around the crosshair.
	hitmarker = Instance.new("Frame")
	hitmarker.Name = "Hitmarker"
	hitmarker.AnchorPoint = Vector2.new(0.5, 0.5)
	hitmarker.Position = UDim2.fromScale(0.5, 0.5)
	hitmarker.Size = UDim2.fromOffset(28, 28)
	hitmarker.BackgroundTransparency = 1
	hitmarker.Parent = center
	for _, corner in
		{ Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) }
	do
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new(0.5, corner.X * 9, 0.5, corner.Y * 9)
		tick.Size = UDim2.fromOffset(9, 2)
		tick.Rotation = if corner.X == corner.Y then 45 else -45
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = COLOR_TEXT
		tick.BackgroundTransparency = 1
		tick.Parent = hitmarker
		table.insert(hitTicks, tick)
	end
end

local function refresh()
	local view = WeaponController.view
	local gun = Config.GUNS[view.gun]
	gunLabel.Text = Text.upper(gun.displayName)
	if gunImage then
		local uri = AssetView.resolve("weapons." .. view.gun)
		gunImage.Visible = uri ~= nil and not Layout.isTouch()
		if uri then
			gunImage.Image = uri
		end
	end
	magLabel.Text = tostring(view.mag)
	magLabel.TextColor3 = if view.mag <= gun.magSize * 0.25 then COLOR_LOW else COLOR_TEXT
	reserveLabel.Text = if Config.DEBUG.infiniteAmmo then "/ ∞" else "/ " .. view.reserve
	grenadeLabel.Text = "GRANADAS: " .. view.grenades
end

local function flashHit(head: boolean)
	if hitTween then
		hitTween:Cancel()
	end
	local color = if head then COLOR_HEAD else COLOR_TEXT
	for _, tick in hitTicks do
		tick.BackgroundColor3 = color
		tick.BackgroundTransparency = 0
	end
	hitmarker.Size = UDim2.fromOffset(34, 34)
	local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	hitTween = TweenService:Create(hitmarker, info, { Size = UDim2.fromOffset(28, 28) })
	local tween = hitTween :: Tween
	tween:Play()
	for _, tick in hitTicks do
		TweenService:Create(tick, info, { BackgroundTransparency = 1 }):Play()
	end
end

function CombatHUD.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "CombatHUD"
	Layout.configure(screen, 10)

	center = Instance.new("ScreenGui")
	center.Name = "Crosshair"
	center.ResetOnSpawn = false
	center.ScreenInsets = Enum.ScreenInsets.None

	buildAmmoPanel()
	buildVitals()
	buildCenter()
	buildVignette()
end

function CombatHUD.start()
	refresh()
	WeaponController.changed:connect(refresh)
	WeaponController.hit:connect(flashHit)
	WeaponController.reloadStarted:connect(function()
		reloadStartedAt = os.clock()
	end)
	-- Credits, cooldown and health change constantly; a few writes per frame are cheap.
	RunService.RenderStepped:Connect(function(dt)
		local match = game:GetService("ReplicatedStorage"):FindFirstChild("Match")
		local phase = match and match:GetAttribute("Phase")
		local playing = Players.LocalPlayer:GetAttribute("InMatch") == true
			and phase ~= "Lobby"
			and phase ~= "Result"
			and phase ~= "Waiting"
		screen.Enabled = playing and not Input.isModalOpen()
		local h = humanoid()
		center.Enabled = screen.Enabled and h ~= nil and h.Health > 0
		refreshStatus()
		updateHealth(dt)
	end)

	local player = Players.LocalPlayer
	if player.Character then
		task.spawn(watchDamage, player.Character)
	end
	player.CharacterAdded:Connect(watchDamage)
	task.spawn(function()
		local credits = player:WaitForChild("leaderstats"):WaitForChild("Créditos")
		if credits:IsA("IntValue") then
			local last = credits.Value
			credits.Changed:Connect(function(value)
				-- Kill rewards only; a new match resetting credits isn't a reward.
				if value > last and value - last <= 500 then
					creditPopup(value - last)
				end
				last = value
			end)
		end
	end)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	screen.Parent = playerGui
	center.Parent = playerGui
	Layout.bind(screen, function(m)
		if m.touch then
			Layout.place(vitalsPanel, m.mobile.vitals)
			Layout.place(ammoPanel, m.mobile.ammo)
		else
			vitalsPanel.AnchorPoint = Vector2.new(0, 1)
			vitalsPanel.Position = UDim2.new(0, 12, 1, -16)
			vitalsPanel.Size = UDim2.fromOffset(280, 72)
			ammoPanel.AnchorPoint = Vector2.new(1, 1)
			ammoPanel.Position = UDim2.new(1, -16, 1, -16)
			ammoPanel.Size = UDim2.fromOffset(240, 100)
		end
		creditsLabel.Visible = not m.touch
		if creditIcon then
			creditIcon.Visible = not m.touch
		end
		healthTitle.Visible = not m.touch
		healthBack.Position = if m.touch
			then UDim2.fromScale(0.14, 0.2)
			else UDim2.fromScale(0.26, 0.06)
		healthBack.Size = if m.touch then UDim2.fromScale(0.6, 0.6) else UDim2.fromScale(0.54, 0.36)
		healthLabel.Position = UDim2.fromScale(if m.touch then 0.78 else 0.82, 0)
		healthLabel.Size =
			UDim2.fromScale(if m.touch then 0.22 else 0.18, if m.touch then 1 else 0.48)
		if healthIcon then
			healthIcon.Position = UDim2.fromScale(0, if m.touch then 0.2 else 0.04)
			healthIcon.Size = UDim2.fromScale(0.1, if m.touch then 0.6 else 0.4)
		end
		magLabel.Position = UDim2.fromScale(0.05, if m.touch then 0.06 else 0.02)
		magLabel.Size = UDim2.fromScale(0.5, if m.touch then 0.62 else 0.5)
		reserveLabel.Position = UDim2.fromScale(0.57, if m.touch then 0.2 else 0.18)
		reserveLabel.Size = UDim2.fromScale(0.4, if m.touch then 0.42 else 0.28)
		gunLabel.Position = UDim2.fromScale(0.05, if m.touch then 0.68 else 0.52)
		gunLabel.Size = UDim2.fromScale(0.9, if m.touch then 0.27 else 0.2)
		if gunImage then
			gunImage.Visible = not m.touch
		end
		grenadeLabel.Visible = not m.touch
		abilityLabel.Visible = not m.touch
		abilityLabel.AnchorPoint = Vector2.new(1, 1)
		abilityLabel.Position = UDim2.new(1, -16, 1, -124)
		abilityLabel.Size = UDim2.fromOffset(math.min(320, m.size.X * 0.4), 24)
	end)
end

return CombatHUD
