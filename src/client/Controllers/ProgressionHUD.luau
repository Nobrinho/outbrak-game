--!strict
-- Account level badge with an XP bar (top-left, under the CLASSE button), the active XP boost
-- countdown, and the VIP panel with the two Robux offers. Purchases are prompted here; the
-- server grants them (MonetizationService). Offers whose ids aren't configured yet show as
-- unavailable instead of failing.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)

local ProgressionHUD = {}

local M = Config.MONETIZATION

local player = Players.LocalPlayer
local screen: ScreenGui
local badge: Frame
local vipButton: TextButton
local levelLabel: TextLabel
local xpFill: Frame
local boostLabel: TextLabel
local vipPanel: Frame
local packButton: TextButton
local boostButton: TextButton
local progressSummary: TextLabel

local function number(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

local function buildBadge()
	badge = Instance.new("Frame")
	badge.Name = "Level"
	badge.Position = UDim2.fromOffset(16, 160)
	badge.Size = UDim2.fromOffset(210, 40)
	Theme.panel(badge)
	badge.Parent = screen

	Theme.image(badge, "ui.icons.xp", {
		Position = UDim2.fromOffset(8, 5),
		Size = UDim2.fromOffset(16, 16),
		ImageColor3 = Theme.COLOR.accent,
	})
	levelLabel = Theme.text(badge, "heavy", {
		Position = UDim2.fromOffset(30, 3),
		Size = UDim2.new(1, -38, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local back = Instance.new("Frame")
	back.Position = UDim2.new(0, 12, 0, 26)
	back.Size = UDim2.new(1, -24, 0, 7)
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BackgroundTransparency = 0.4
	back.BorderSizePixel = 0
	back.Parent = badge
	xpFill = Instance.new("Frame")
	xpFill.BackgroundColor3 = Theme.COLOR.accent
	xpFill.BorderSizePixel = 0
	xpFill.Parent = back

	boostLabel = Theme.text(screen, "heavy", {
		Position = UDim2.fromOffset(16, 204),
		Size = UDim2.fromOffset(170, 18),
		TextColor3 = Theme.COLOR.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	})
end

local function setVipOpen(open: boolean)
	vipPanel.Visible = open
	InputController.setModal("VIP", open)
end

local function offerRow(parent: Frame, y: number, title: string, description: string): TextButton
	Theme.text(parent, "heavy", {
		Position = UDim2.fromScale(0.06, y),
		Size = UDim2.fromScale(0.6, 0.1),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Theme.text(parent, "label", {
		Position = UDim2.fromScale(0.06, y + 0.1),
		Size = UDim2.fromScale(0.6, 0.12),
		Text = description,
		TextColor3 = Theme.COLOR.muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.fromScale(0.94, y + 0.02)
	button.Size = UDim2.fromScale(0.26, 0.16)
	Theme.button(button)
	button.Parent = parent
	return button
end

local function buildVip()
	local open = Instance.new("TextButton")
	vipButton = open
	open.Name = "VipButton"
	open.Position = UDim2.fromOffset(16, 228)
	open.Size = UDim2.fromOffset(110, 32)
	open.Text = "★ VIP"
	Theme.button(open)
	open.Parent = screen
	open.Activated:Connect(function()
		setVipOpen(not vipPanel.Visible)
	end)

	vipPanel = Instance.new("Frame")
	vipPanel.Name = "VipPanel"
	vipPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	vipPanel.Position = UDim2.fromScale(0.5, 0.5)
	vipPanel.Size = UDim2.fromScale(0.5, 0.5)
	Theme.panel(vipPanel, 0.1)
	vipPanel.Visible = false
	vipPanel.Parent = screen
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.5
	aspect:Destroy()

	Theme.text(vipPanel, "display", {
		Position = UDim2.fromScale(0.06, 0.04),
		Size = UDim2.fromScale(0.7, 0.14),
		Text = "PROGRESSÃO",
		TextColor3 = Theme.COLOR.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(0.95, 0.05)
	close.Size = UDim2.fromScale(0.1, 0.14)
	close.Text = "X"
	Theme.button(close)
	close.Parent = vipPanel
	close.Activated:Connect(function()
		setVipOpen(false)
	end)

	progressSummary = Theme.text(vipPanel, "heavy", {
		Position = UDim2.fromScale(0.06, 0.19),
		Size = UDim2.fromScale(0.88, 0.07),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	packButton = offerRow(
		vipPanel,
		0.30,
		"PACOTE DO SOBREVIVENTE",
		"Armas douradas e um rastro. Só visual — nada de vantagem."
	)
	boostButton = offerRow(
		vipPanel,
		0.60,
		"BOOST 2x XP — 1 HORA",
		"Dobra o XP de conta. Acumula se comprar de novo."
	)
	Theme.text(vipPanel, "label", {
		Position = UDim2.fromScale(0.06, 0.9),
		Size = UDim2.fromScale(0.88, 0.06),
		Text = "Nada à venda aumenta dano, vida ou dá armas exclusivas.",
		TextColor3 = Theme.COLOR.muted,
	})

	packButton.Activated:Connect(function()
		if M.survivorPackId ~= 0 and player:GetAttribute("SurvivorPack") ~= true then
			MarketplaceService:PromptGamePassPurchase(player, M.survivorPackId)
		end
	end)
	boostButton.Activated:Connect(function()
		if M.xpBoostProductId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, M.xpBoostProductId)
		end
	end)
end

local function clock(seconds: number): string
	local m = math.ceil(seconds / 60)
	return if m >= 60 then string.format("%dh%02d", m // 60, m % 60) else `{m} min`
end

-- Level and VIP are for the lobby, the camp and the breaks between waves; in combat they're
-- clutter next to health and ammo. Without a Match (the hub) they always show.
local function outOfCombat(): boolean
	local match = ReplicatedStorage:FindFirstChild("Match")
	local phase = match and match:GetAttribute("Phase")
	return phase ~= "Wave" and phase ~= "Final" and phase ~= "Extract"
end

local function update()
	local calm = outOfCombat()
	badge.Visible = calm
		and not ReplicatedStorage:FindFirstChild("Match")
		and not InputController.isModalOpen()
	vipButton.Visible = false
	local level = number("Level", 1)
	local progress = number("LevelXP", 0)
	local needed = math.max(1, number("LevelXPNeeded", 100))
	levelLabel.Text = `NÍVEL {level}   {math.floor(progress)} / {needed} XP`
	progressSummary.Text = levelLabel.Text
	xpFill.Size = UDim2.fromScale(math.clamp(progress / needed, 0, 1), 1)

	-- BoostUntil is os.time() on the server; server time on the client is the same clock.
	local boostLeft = number("BoostUntil", 0) - workspace:GetServerTimeNow()
	boostLabel.Visible = badge.Visible and boostLeft > 0
	if boostLeft > 0 then
		boostLabel.Text = "2x XP — " .. clock(boostLeft)
	end

	local owned = player:GetAttribute("SurvivorPack") == true
	packButton.Text = if M.survivorPackId == 0
		then "EM BREVE"
		elseif owned then "ATIVO"
		else "COMPRAR"
	packButton.AutoButtonColor = false
	packButton:SetAttribute("AssetDisabled", M.survivorPackId == 0 or owned)
	packButton.TextColor3 = if M.survivorPackId == 0 or owned
		then Theme.COLOR.text
		else Theme.COLOR.panel
	boostButton.Text = if M.xpBoostProductId == 0 then "EM BREVE" else "COMPRAR"
	boostButton.AutoButtonColor = false
	boostButton:SetAttribute("AssetDisabled", M.xpBoostProductId == 0)
	boostButton.TextColor3 = if M.xpBoostProductId == 0 then Theme.COLOR.text else Theme.COLOR.panel
end

function ProgressionHUD.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "ProgressionHUD"
	Layout.configure(screen, 40)
	buildBadge()
	buildVip()
	InputController.registerModal("VIP", function()
		setVipOpen(false)
	end)
	InputController.panelRequested:connect(function(name)
		if name == "Progression" then
			setVipOpen(true)
		end
	end)
end

function ProgressionHUD.start()
	screen.Parent = player:WaitForChild("PlayerGui")
	Layout.bind(screen, function(m)
		badge.AnchorPoint = Vector2.new(0, 1)
		badge.Position = UDim2.new(0, 12, 1, if m.touch then -m.vitalsBottom else -16)
		badge.Size = UDim2.fromOffset(if m.touch then 190 else 240, 48)
		boostLabel.AnchorPoint = Vector2.new(0, 1)
		boostLabel.Position = UDim2.new(0, 12, 1, if m.touch then -m.vitalsBottom - 52 else -70)
		vipPanel.Size = UDim2.fromOffset(math.min(620, m.size.X - 24), math.min(440, m.size.Y - 20))
	end)
	local match = ReplicatedStorage:FindFirstChild("Match")
	if match then
		match:GetAttributeChangedSignal("Phase"):Connect(function()
			setVipOpen(false)
		end)
	end
	RunService.RenderStepped:Connect(update)
end

return ProgressionHUD
