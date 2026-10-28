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
local Layout = require(script.Parent.Parent.UI.Layout)

local ShopUI = {}

local COLOR_PANEL = Theme.COLOR.panel
local COLOR_ROW = Theme.COLOR.surface
local COLOR_TEXT = Theme.COLOR.text
local COLOR_ACCENT = Theme.COLOR.accent
local COLOR_DISABLED = Theme.COLOR.disabled

local player = Players.LocalPlayer
local screen: ScreenGui
local menu: Frame
local toasts: Frame
local buyButtons: { [string]: TextButton } = {}
local pending: { [string]: number } = {}

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
	local levelValue = player:GetAttribute("Level")
	local level = if typeof(levelValue) == "number" then levelValue else 1
	for _, item in Config.SHOP do
		local button = buyButtons[item.id]
		if button then
			-- Items above the account level show what unlocks them instead of a price.
			local required = Config.PROGRESSION.unlocks[item.id]
			local locked = required ~= nil and level < required
			local affordable = not locked and have >= item.price
			local waiting = (pending[item.id] or 0) > os.clock()
			button.Text = if waiting
				then "AGUARDE"
				elseif locked then `NÍVEL {required}`
				elseif not affordable then "SEM CR"
				else "COMPRAR"
			button:SetAttribute("AssetDisabled", not affordable or waiting)
			button.BackgroundColor3 = if affordable and not waiting
				then COLOR_ACCENT
				else COLOR_DISABLED
			button.TextColor3 = if affordable and not waiting then COLOR_PANEL else COLOR_TEXT
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
	menu.Size = UDim2.fromScale(0.88, 0.86)
	Theme.panel(menu, 0.1)
	menu.Visible = false
	menu.Parent = screen
	local limits = Instance.new("UISizeConstraint")
	limits.MaxSize = Vector2.new(620, 700)
	limits.Parent = menu

	label(menu, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -100, 0, 40),
		Text = "SUPRIMENTOS",
		FontFace = Theme.FONT.display,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_ACCENT,
	})
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 8)
	close.Size = UDim2.fromOffset(48, 48)
	close.BackgroundColor3 = COLOR_ROW
	close.Text = "X"
	close.TextColor3 = COLOR_TEXT
	close.FontFace = Theme.FONT.heavy
	close.TextScaled = true
	Theme.skinButton(close, "secondary")
	close.Parent = menu
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Items"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Position = UDim2.fromOffset(12, 64)
	rows.Size = UDim2.new(1, -24, 1, -76)
	rows.CanvasSize = UDim2.fromOffset(0, #Config.SHOP * 80)
	rows.ScrollBarThickness = 6
	rows.ScrollingDirection = Enum.ScrollingDirection.Y
	rows.Parent = menu
	local previews = { Heal = "Medkit", Turret = "Turret", Grenade = "Grenade" }
	for i, item in Config.SHOP do
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(0, (i - 1) * 80)
		row.Size = UDim2.new(1, -10, 0, 72)
		row.BackgroundColor3 = COLOR_ROW
		row.Parent = rows
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0.15, 0)
		rowCorner.Parent = row
		Theme.image(row, "weapons." .. (previews[item.id] or item.id), {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(80, 64),
		})

		label(row, {
			Position = UDim2.fromOffset(90, 8),
			Size = UDim2.new(1, -214, 0, 32),
			Text = item.displayName,
			TextScaled = false,
			TextSize = 20,
			TextWrapped = true,
			FontFace = Theme.FONT.label,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		label(row, {
			Position = UDim2.fromOffset(90, 44),
			Size = UDim2.new(1, -214, 0, 20),
			Text = "CR " .. item.price,
			TextScaled = false,
			TextSize = 18,
			TextColor3 = COLOR_ACCENT,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local buy = Instance.new("TextButton")
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, -8, 0.5, 0)
		buy.Size = UDim2.fromOffset(110, 48)
		buy.Text = "$ " .. item.price
		Theme.button(buy)
		buy.Parent = row
		local buyCorner = Instance.new("UICorner")
		buyCorner.CornerRadius = UDim.new(0.2, 0)
		buyCorner.Parent = buy
		buy.Activated:Connect(function()
			if buy:GetAttribute("AssetDisabled") then
				return
			end
			pending[item.id] = os.clock() + 2
			refreshPrices()
			Net.purchase():FireServer(item.id)
			task.delay(2, refreshPrices)
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
	Layout.configure(screen, 40)
	buildMenu()
	InputController.registerModal("Shop", function()
		setOpen(false)
	end)

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
	local match = ReplicatedStorage:WaitForChild("Match")
	match:GetAttributeChangedSignal("Phase"):Connect(function()
		if menu.Visible then
			setOpen(false)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local crate = prompt.Parent
		if crate and CollectionService:HasTag(crate, Tags.ShopBox) then
			setOpen(true)
		end
	end)
	Net.notify().OnClientEvent:Connect(function(message: unknown)
		if typeof(message) == "string" then
			table.clear(pending)
			refreshPrices()
			toast(message)
		end
	end)

	-- Prices dim/brighten as credits change; walking away closes the menu.
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats")
		local value = leaderstats:WaitForChild("Créditos")
		if value:IsA("IntValue") then
			value.Changed:Connect(refreshPrices)
			player:GetAttributeChangedSignal("Level"):Connect(refreshPrices)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if menu.Visible and not nearShop() then
			setOpen(false)
		end
	end)
end

return ShopUI
