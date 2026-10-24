--!strict
-- Barn shop menu and toast notifications. The menu opens when the shop crate's prompt is
-- completed (keyboard hold or the touch context button) and closes when the player walks
-- away. Buttons only ask; the server validates and answers with a toast (Net.notify).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.Parent.UI.Theme)

local ShopUI = {}

local COLOR_PANEL = Color3.fromRGB(20, 20, 24)
local COLOR_ROW = Color3.fromRGB(36, 36, 42)
local COLOR_TEXT = Color3.fromRGB(240, 240, 240)
local COLOR_ACCENT = Color3.fromRGB(255, 204, 0)
local COLOR_DISABLED = Color3.fromRGB(90, 90, 96)

local player = Players.LocalPlayer
local screen: ScreenGui
local menu: Frame
local toasts: Frame
local buyButtons: { [string]: TextButton } = {}

local function credits(): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Créditos")
	return if value and value:IsA("IntValue") then value.Value else 0
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = COLOR_TEXT
	l.FontFace = Theme.FONT.heavy
	l.TextScaled = true
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function refreshPrices()
	local have = credits()
	for _, item in Config.SHOP do
		local button = buyButtons[item.id]
		if button then
			local affordable = have >= item.price
			button.BackgroundColor3 = if affordable then COLOR_ACCENT else COLOR_DISABLED
			button.TextColor3 = if affordable then COLOR_PANEL else COLOR_TEXT
		end
	end
end

local function setOpen(open: boolean)
	menu.Visible = open
	InputController.setModal("Shop", open)
	if open then
		refreshPrices()
	end
end

local function buildMenu()
	menu = Instance.new("Frame")
	menu.Name = "Shop"
	menu.AnchorPoint = Vector2.new(0.5, 0.5)
	menu.Position = UDim2.fromScale(0.5, 0.5)
	menu.Size = UDim2.fromScale(0.5, 0.8)
	Theme.panel(menu, 0.1)
	menu.Visible = false
	menu.Parent = screen
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.9
	aspect.Parent = menu

	label(menu, {
		Position = UDim2.fromScale(0.05, 0.02),
		Size = UDim2.fromScale(0.7, 0.08),
		Text = "SUPRIMENTOS",
		FontFace = Theme.FONT.display,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_ACCENT,
	})
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(0.96, 0.02)
	close.Size = UDim2.fromScale(0.1, 0.08)
	close.BackgroundColor3 = COLOR_ROW
	close.Text = "X"
	close.TextColor3 = COLOR_TEXT
	close.FontFace = Theme.FONT.heavy
	close.TextScaled = true
	close.Parent = menu
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local rowHeight = 0.86 / #Config.SHOP
	for i, item in Config.SHOP do
		local row = Instance.new("Frame")
		row.Position = UDim2.fromScale(0.04, 0.12 + (i - 1) * rowHeight)
		row.Size = UDim2.fromScale(0.92, rowHeight * 0.88)
		row.BackgroundColor3 = COLOR_ROW
		row.Parent = menu
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0.15, 0)
		rowCorner.Parent = row

		label(row, {
			Position = UDim2.fromScale(0.04, 0.15),
			Size = UDim2.fromScale(0.6, 0.7),
			Text = item.displayName,
			FontFace = Theme.FONT.label,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local buy = Instance.new("TextButton")
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.fromScale(0.97, 0.5)
		buy.Size = UDim2.fromScale(0.3, 0.75)
		buy.Text = "$ " .. item.price
		Theme.button(buy)
		buy.Parent = row
		local buyCorner = Instance.new("UICorner")
		buyCorner.CornerRadius = UDim.new(0.2, 0)
		buyCorner.Parent = buy
		buy.Activated:Connect(function()
			Net.purchase():FireServer(item.id)
		end)
		buyButtons[item.id] = buy
	end
end

local function toast(message: string)
	local l = label(toasts, {
		Size = UDim2.new(1, 0, 0, 30),
		Text = message,
		BackgroundColor3 = COLOR_PANEL,
		BackgroundTransparency = 0.3,
	})
	l.TextScaled = false
	l.TextSize = 20
	TweenService:Create(
		l,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2),
		{ TextTransparency = 1, BackgroundTransparency = 1 }
	):Play()
	Debris:AddItem(l, 3)
end

local function nearShop(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	for _, crate in CollectionService:GetTagged(Tags.ShopBox) do
		if
			crate:IsA("BasePart")
			and (crate.Position - root.Position).Magnitude <= Config.SHOP_RANGE
		then
			return true
		end
	end
	return false
end

function ShopUI.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "ShopUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screen.DisplayOrder = 6
	buildMenu()

	toasts = Instance.new("Frame")
	toasts.Name = "Toasts"
	toasts.AnchorPoint = Vector2.new(0.5, 0)
	toasts.Position = UDim2.fromScale(0.5, 0.68)
	toasts.Size = UDim2.fromScale(0.5, 0.2)
	toasts.BackgroundTransparency = 1
	toasts.Parent = screen
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.Parent = toasts
end

function ShopUI.start()
	screen.Parent = player:WaitForChild("PlayerGui")

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local crate = prompt.Parent
		if crate and CollectionService:HasTag(crate, Tags.ShopBox) then
			setOpen(true)
		end
	end)
	Net.notify().OnClientEvent:Connect(function(message: unknown)
		if typeof(message) == "string" then
			toast(message)
		end
	end)

	-- Prices dim/brighten as credits change; walking away closes the menu.
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats")
		local value = leaderstats:WaitForChild("Créditos")
		if value:IsA("IntValue") then
			value.Changed:Connect(refreshPrices)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if menu.Visible and not nearShop() then
			setOpen(false)
		end
	end)
end

return ShopUI
