--!strict
-- Class picker and ability trigger. The picker opens on its own in the lobby before every
-- match (the current class is highlighted) and can be reopened with the CLASSE button there
-- and, for players in the match, while any Prep lasts. The ability key/button sends the camera direction (the molotov uses it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Text = require(Shared.Util.Text)
local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.Parent.UI.Theme)

local ClassController = {}

local COLOR_PANEL = Color3.fromRGB(20, 20, 24)
local COLOR_TEXT = Color3.fromRGB(240, 240, 240)
local COLOR_ACCENT = Color3.fromRGB(255, 204, 0)
local CLASS_ORDER: { Types.ClassId } = { "Gunslinger", "Exterminator" }

local player = Players.LocalPlayer
local screen: ScreenGui
local picker: Frame
local reopenButton: TextButton
local cards: { [Types.ClassId]: UIStroke } = {}

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = COLOR_TEXT
	l.FontFace = Theme.FONT.heavy
	l.TextScaled = true
	l.TextWrapped = true
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function setOpen(open: boolean)
	picker.Visible = open
	InputController.setModal("ClassPicker", open)
end

local function highlight()
	local current = player:GetAttribute("Class")
	for id, stroke in cards do
		stroke.Color = if id == current then COLOR_ACCENT else COLOR_TEXT
		stroke.Thickness = if id == current then 4 else 1
	end
end

local function buildPicker()
	picker = Instance.new("Frame")
	picker.Name = "ClassPicker"
	picker.AnchorPoint = Vector2.new(0.5, 0.5)
	picker.Position = UDim2.fromScale(0.5, 0.5)
	picker.Size = UDim2.fromScale(0.7, 0.7)
	picker.ZIndex = 10
	Theme.panel(picker, 0.12)
	picker.Visible = false
	picker.Parent = screen

	label(picker, {
		Position = UDim2.fromScale(0.05, 0.03),
		Size = UDim2.fromScale(0.9, 0.12),
		Text = "ESCOLHA SUA CLASSE",
		FontFace = Theme.FONT.display,
		ZIndex = 11,
	})

	for i, id in CLASS_ORDER do
		local class = Config.CLASSES[id]
		local card = Instance.new("TextButton")
		card.Name = id
		card.AutoButtonColor = true
		card.Text = ""
		card.Position = UDim2.fromScale(0.04 + (i - 1) * 0.49, 0.2)
		card.Size = UDim2.fromScale(0.43, 0.74)
		card.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
		card.ZIndex = 11
		card.Parent = picker
		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0.05, 0)
		cardCorner.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
		cards[id] = stroke

		label(card, {
			Position = UDim2.fromScale(0.06, 0.04),
			Size = UDim2.fromScale(0.88, 0.16),
			Text = Text.upper(class.displayName),
			TextColor3 = COLOR_ACCENT,
			ZIndex = 12,
		})
		label(card, {
			Position = UDim2.fromScale(0.06, 0.24),
			Size = UDim2.fromScale(0.88, 0.1),
			Text = "Arma inicial: " .. Config.GUNS[class.startGun].displayName,
			FontFace = Theme.FONT.label,
			ZIndex = 12,
		})
		label(card, {
			Position = UDim2.fromScale(0.06, 0.38),
			Size = UDim2.fromScale(0.88, 0.24),
			Text = class.description,
			FontFace = Theme.FONT.label,
			ZIndex = 12,
		})
		label(card, {
			Position = UDim2.fromScale(0.06, 0.66),
			Size = UDim2.fromScale(0.88, 0.28),
			Text = "Habilidade — " .. class.ability.name .. ": " .. class.ability.description,
			FontFace = Theme.FONT.heavy,
			TextColor3 = Color3.fromRGB(255, 160, 80),
			ZIndex = 12,
		})

		card.Activated:Connect(function()
			Net.selectClass():FireServer(id)
			setOpen(false)
		end)
	end
	highlight()
	player:GetAttributeChangedSignal("Class"):Connect(highlight)

	reopenButton = Instance.new("TextButton")
	reopenButton.Name = "ClassButton"
	reopenButton.AnchorPoint = Vector2.new(0, 0)
	reopenButton.Position = UDim2.new(0, 16, 0, 116) -- under CombatHUD's health and credits
	reopenButton.Size = UDim2.fromOffset(110, 36)
	reopenButton.BackgroundColor3 = COLOR_PANEL
	reopenButton.BackgroundTransparency = 0.3
	reopenButton.TextColor3 = COLOR_TEXT
	reopenButton.FontFace = Theme.FONT.heavy
	reopenButton.TextScaled = true
	reopenButton.Text = "CLASSE"
	reopenButton.Visible = false
	reopenButton.Parent = screen
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0.2, 0)
	buttonCorner.Parent = reopenButton
	reopenButton.Activated:Connect(function()
		setOpen(not picker.Visible)
	end)
end

-- The picker opens in the lobby (pick or confirm a class before PRONTO) and can be reopened
-- there or, for players in the match, during any Prep.
local function canPick(phase: unknown): boolean
	return phase == "Lobby" or (phase == "Prep" and player:GetAttribute("InMatch") == true)
end

local function onPhaseChanged(match: Instance)
	local phase = match:GetAttribute("Phase")
	reopenButton.Visible = canPick(phase)
	if phase == "Lobby" then
		setOpen(true)
	elseif picker.Visible then
		setOpen(false) -- the match started (or left Prep): CLASSE reopens it while allowed
	end
end

function ClassController.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "ClassUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screen.DisplayOrder = 5
	buildPicker()
end

function ClassController.start()
	screen.Parent = player:WaitForChild("PlayerGui")

	local match = ReplicatedStorage:WaitForChild("Match")
	match:GetAttributeChangedSignal("Phase"):Connect(function()
		onPhaseChanged(match)
	end)
	player:GetAttributeChangedSignal("InMatch"):Connect(function()
		reopenButton.Visible = canPick(match:GetAttribute("Phase"))
	end)
	onPhaseChanged(match)

	InputController.actionChanged:connect(function(action, isDown)
		if action == "Ability" and isDown and not InputController.isModalOpen() then
			local readyAt = player:GetAttribute("AbilityReadyAt")
			if typeof(readyAt) == "number" and workspace:GetServerTimeNow() < readyAt then
				return
			end
			Net.useAbility():FireServer(workspace.CurrentCamera.CFrame.LookVector)
		end
	end)
end

return ClassController
