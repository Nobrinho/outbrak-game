--!strict
-- Ammo panel (top-right, clear of the touch cluster), the crosshair with its reload notice,
-- and a hitmarker that flashes white on body hits and orange on headshots. The crosshair
-- layer ignores every inset so its center is exactly the camera ray's center.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Text = require(Shared.Util.Text)
local WeaponController = require(script.Parent.WeaponController)
local Theme = require(script.Parent.Parent.UI.Theme)

local CombatHUD = {}

local COLOR_TEXT = Color3.fromRGB(240, 240, 240)
local COLOR_LOW = Color3.fromRGB(220, 40, 40)
local COLOR_HEAD = Color3.fromRGB(255, 140, 20)

local screen: ScreenGui
local center: ScreenGui
local magLabel: TextLabel
local reserveLabel: TextLabel
local gunLabel: TextLabel
local grenadeLabel: TextLabel
local creditsLabel: TextLabel
local statusPanel: Frame
local healthFill: Frame
local healthLabel: TextLabel
local vignette: { Frame } = {}
local damageFlash = 0 -- 0..1, decays every frame
local abilityLabel: TextLabel
local reloadLabel: TextLabel
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

local function buildAmmoPanel(): Frame
	local panel = Instance.new("Frame")
	panel.Name = "Ammo"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 16)
	panel.Size = UDim2.fromScale(0.2, 0.14)
	Theme.panel(panel)
	panel.Parent = screen

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 2.2
	aspect.Parent = panel

	gunLabel = label(panel, {
		Position = UDim2.fromScale(0.06, 0.06),
		Size = UDim2.fromScale(0.88, 0.22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.2,
	})
	magLabel = label(panel, {
		Position = UDim2.fromScale(0.06, 0.3),
		Size = UDim2.fromScale(0.42, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	reserveLabel = label(panel, {
		Position = UDim2.fromScale(0.52, 0.42),
		Size = UDim2.fromScale(0.42, 0.3),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.3,
	})
	grenadeLabel = label(panel, {
		Position = UDim2.fromScale(0.06, 0.8),
		Size = UDim2.fromScale(0.88, 0.16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.2,
	})
	return panel
end

-- Credits and ability cooldown, in a strip right under the ammo panel.
local function buildStatusPanel(ammo: Frame)
	local panel = Instance.new("Frame")
	panel.Name = "Status"
	panel.AnchorPoint = Vector2.new(1, 0)
	Theme.panel(panel)
	panel.Parent = screen
	local function place()
		local size = ammo.AbsoluteSize
		panel.Size = UDim2.fromOffset(size.X, size.Y * 0.62)
		panel.Position = UDim2.new(1, -16, 0, 16 + size.Y + 6)
	end
	ammo:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()

	statusPanel = panel
	creditsLabel = label(panel, {
		Position = UDim2.fromScale(0.06, 0.06),
		Size = UDim2.fromScale(0.88, 0.3),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.COLOR.accent,
	})
	abilityLabel = label(panel, {
		Position = UDim2.fromScale(0.06, 0.38),
		Size = UDim2.fromScale(0.88, 0.26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.15,
	})
	-- Health bar along the bottom of the strip.
	local back = Instance.new("Frame")
	back.Position = UDim2.fromScale(0.06, 0.7)
	back.Size = UDim2.fromScale(0.88, 0.22)
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BackgroundTransparency = 0.4
	back.BorderSizePixel = 0
	back.Parent = panel
	healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Theme.COLOR.player
	healthFill.BorderSizePixel = 0
	healthFill.Parent = back
	healthLabel = label(back, {
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.FONT.heavy,
		ZIndex = 3,
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
	local popup = label(screen, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(
			statusPanel.AbsolutePosition.X - 8,
			statusPanel.AbsolutePosition.Y
		),
		Size = UDim2.fromOffset(90, 26),
		Text = "+" .. amount,
		TextColor3 = Theme.COLOR.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
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
	abilityLabel.Text = Text.upper(class.ability.name)
		.. (if left > 0 then string.format(" — %ds", math.ceil(left)) else " — PRONTA")
end

local function buildCenter()
	local dot = Instance.new("Frame")
	dot.Name = "Crosshair"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = COLOR_TEXT
	dot.BorderSizePixel = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = dot
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1
	stroke.Parent = dot
	dot.Parent = center

	reloadLabel = label(center, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 28),
		Size = UDim2.fromOffset(220, 22),
		Text = "RECARREGANDO...",
		Visible = false,
	})

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
	magLabel.Text = tostring(view.mag)
	magLabel.TextColor3 = if view.mag <= gun.magSize * 0.25 then COLOR_LOW else COLOR_TEXT
	reserveLabel.Text = if Config.DEBUG.infiniteAmmo then "/ ∞" else "/ " .. view.reserve
	grenadeLabel.Text = "GRANADAS x" .. view.grenades
	reloadLabel.Visible = view.reloading
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
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	center = Instance.new("ScreenGui")
	center.Name = "Crosshair"
	center.ResetOnSpawn = false
	center.ScreenInsets = Enum.ScreenInsets.None

	buildStatusPanel(buildAmmoPanel())
	buildCenter()
	buildVignette()
end

function CombatHUD.start()
	refresh()
	WeaponController.changed:connect(refresh)
	WeaponController.hit:connect(flashHit)
	-- Credits, cooldown and health change constantly; a few writes per frame are cheap.
	RunService.RenderStepped:Connect(function(dt)
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
end

return CombatHUD
