--!strict
-- Ammo panel (top-right, clear of the touch cluster), the crosshair with its reload notice,
-- and a hitmarker that flashes white on body hits and orange on headshots. The crosshair
-- layer ignores every inset so its center is exactly the camera ray's center.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local WeaponController = require(script.Parent.WeaponController)

local CombatHUD = {}

local COLOR_PANEL = Color3.fromRGB(20, 20, 24)
local COLOR_TEXT = Color3.fromRGB(240, 240, 240)
local COLOR_LOW = Color3.fromRGB(220, 40, 40)
local COLOR_HEAD = Color3.fromRGB(255, 140, 20)

local screen: ScreenGui
local center: ScreenGui
local magLabel: TextLabel
local reserveLabel: TextLabel
local gunLabel: TextLabel
local grenadeLabel: TextLabel
local reloadLabel: TextLabel
local hitmarker: Frame
local hitTicks: { Frame } = {}
local hitTween: Tween? = nil

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = COLOR_TEXT
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function buildAmmoPanel()
	local panel = Instance.new("Frame")
	panel.Name = "Ammo"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 16)
	panel.Size = UDim2.fromScale(0.2, 0.14)
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BackgroundTransparency = 0.35
	panel.Parent = screen

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 2.2
	aspect.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = panel

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
	gunLabel.Text = string.upper(gun.displayName)
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

	buildAmmoPanel()
	buildCenter()
end

function CombatHUD.start()
	refresh()
	WeaponController.changed:connect(refresh)
	WeaponController.hit:connect(flashHit)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	screen.Parent = playerGui
	center.Parent = playerGui
end

return CombatHUD
