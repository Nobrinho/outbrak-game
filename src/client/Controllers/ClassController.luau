--!strict
-- Stage a class selection, confirm it, then let the separate PRONTO action join the match.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Text = require(ReplicatedStorage.Shared.Util.Text)
local Input = require(script.Parent.InputController)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)
local ClassController = {}
local player = Players.LocalPlayer
local screen: ScreenGui
local overlay: Frame
local picker: Frame
local reopen: TextButton
local confirm: TextButton
local back: TextButton
local selected: Types.ClassId = Config.DEFAULT_CLASS
local cards: { [Types.ClassId]: TextButton } = {}
local strokes: { [Types.ClassId]: UIStroke } = {}
local classOrder: { Types.ClassId } = { "Gunslinger", "Exterminator" }

local function canPick(): boolean
	local match = ReplicatedStorage:FindFirstChild("Match")
	local phase = match and match:GetAttribute("Phase")
	return phase == "Lobby" or (phase == "Prep" and player:GetAttribute("InMatch") == true)
end
local function highlight()
	for id, stroke in strokes do
		stroke.Color = if id == selected then Theme.COLOR.accent else Theme.COLOR.muted
		stroke.Thickness = if id == selected then 3 else 1
	end
end
local function setOpen(open: boolean)
	if open and not canPick() then
		return
	end
	if open then
		local current = player:GetAttribute("Class")
		selected = if typeof(current) == "string" and Config.CLASSES[current :: Types.ClassId]
			then current :: Types.ClassId
			else Config.DEFAULT_CLASS
		highlight()
	end
	overlay.Visible = open
	Input.setModal("ClassPicker", open)
end
local function text(
	parent: Instance,
	y: number,
	height: number,
	value: string,
	style: Theme.TextStyle
): TextLabel
	local label = Theme.text(parent, style, {
		Position = UDim2.new(0.06, 0, y, 0),
		Size = UDim2.new(0.88, 0, height, 0),
		Text = value,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Layout.limitText(label, 12, if style == "heavy" then 24 else 19)
	return label
end
function ClassController.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "ClassUI"
	Layout.configure(screen, 40)
	overlay = Instance.new("Frame")
	overlay.Name = "ClassOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Theme.COLOR.panel
	overlay.BackgroundTransparency = 0.08
	overlay.Active = true
	overlay.Visible = false
	overlay.Parent = screen
	picker = Instance.new("Frame")
	picker.Name = "ClassPicker"
	picker.AnchorPoint = Vector2.new(0.5, 0.5)
	picker.Position = UDim2.fromScale(0.5, 0.5)
	Theme.panel(picker, 0.04)
	picker.Parent = overlay
	local title = Theme.text(picker, "display", {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 36),
		Text = "ESCOLHA SUA CLASSE",
	})
	Layout.limitText(title, 18, 32)
	for _, id in classOrder do
		local class = Config.CLASSES[id]
		local card = Instance.new("TextButton")
		card.Name = id
		card.Text = ""
		card.BackgroundColor3 = Theme.COLOR.surface
		card.AutoButtonColor = true
		card.Parent = picker
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
		cards[id], strokes[id] = card, stroke
		local name = text(card, 0.03, 0.15, Text.upper(class.displayName), "heavy")
		name.TextColor3 = Theme.COLOR.accent
		text(card, 0.21, 0.11, "Arma: " .. Config.GUNS[class.startGun].displayName, "label")
		text(card, 0.36, 0.26, class.description, "label")
		local ability =
			text(card, 0.65, 0.31, class.ability.name .. ": " .. class.ability.description, "label")
		ability.TextColor3 = Theme.COLOR.fire
		card.Activated:Connect(function()
			selected = id
			highlight()
		end)
	end
	back = Instance.new("TextButton")
	back.Name = "BackToHub"
	back.Text = if Config.PLACES.hub > 0 and Config.PLACES.hub ~= game.PlaceId
		then "VOLTAR AO ACAMPAMENTO"
		else "VOLTAR"
	Theme.button(back, "secondary")
	Layout.limitText(back, 12, 20)
	back.Parent = picker
	back.Activated:Connect(function()
		setOpen(false)
		if Config.PLACES.hub > 0 and Config.PLACES.hub ~= game.PlaceId then
			Net.returnToHub():FireServer()
		end
	end)
	confirm = Instance.new("TextButton")
	confirm.Name = "ConfirmClass"
	confirm.Text = "CONFIRMAR CLASSE"
	Theme.button(confirm)
	Layout.limitText(confirm, 14, 22)
	confirm.Parent = picker
	confirm.Activated:Connect(function()
		if not canPick() then
			return
		end
		Net.selectClass():FireServer(selected)
		player:SetAttribute("ClassConfirmed", true)
		setOpen(false)
	end)
	reopen = Instance.new("TextButton")
	reopen.Name = "ClassButton"
	reopen.Text = "CLASSE"
	Theme.button(reopen, "secondary")
	Layout.limitText(reopen, 14, 22)
	reopen.Parent = screen
	reopen.Activated:Connect(function()
		setOpen(true)
	end)
	Input.registerModal("ClassPicker", function()
		setOpen(false)
	end)
end
function ClassController.start()
	screen.Parent = player:WaitForChild("PlayerGui")
	Layout.bind(screen, function(m)
		local width = math.min(800, m.size.X - 24)
		local height = math.min(460, m.size.Y - 20)
		picker.Size = UDim2.fromOffset(width, height)
		for index, id in classOrder do
			cards[id].Position = UDim2.new(0.025 + (index - 1) * 0.49, 0, 0, 52)
			cards[id].Size = UDim2.new(0.46, 0, 1, -124)
		end
		back.AnchorPoint = Vector2.new(0, 1)
		back.Position = UDim2.new(0.025, 0, 1, -12)
		back.Size = UDim2.new(0.4, 0, 0, 48)
		confirm.AnchorPoint = Vector2.new(1, 1)
		confirm.Position = UDim2.new(0.975, 0, 1, -12)
		confirm.Size = UDim2.new(0.53, 0, 0, 48)
		reopen.Position = UDim2.fromOffset(12, 12)
		reopen.Size = UDim2.fromOffset(96, 44)
	end)
	local match = ReplicatedStorage:WaitForChild("Match")
	local function phaseChanged()
		if match:GetAttribute("Phase") == "Lobby" then
			player:SetAttribute("ClassConfirmed", false)
			setOpen(true)
		else
			setOpen(false)
		end
	end
	match:GetAttributeChangedSignal("Phase"):Connect(phaseChanged)
	phaseChanged()
	RunService.RenderStepped:Connect(function()
		reopen.Visible = canPick() and not Input.isModalOpen()
	end)
	Input.actionChanged:connect(function(action, isDown)
		if action == "Ability" and isDown and not Input.isModalOpen() then
			local readyAt = player:GetAttribute("AbilityReadyAt")
			if typeof(readyAt) == "number" and workspace:GetServerTimeNow() < readyAt then
				return
			end
			Net.useAbility():FireServer(workspace.CurrentCamera.CFrame.LookVector)
		end
	end)
end
return ClassController
