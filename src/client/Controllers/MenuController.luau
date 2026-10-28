--!strict
-- Responsive scrolling settings keep every option reachable in short landscape viewports.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Input = require(script.Parent.InputController)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)
local Settings = require(script.Parent.Parent.UI.ControlSettings)
local Menu = {}
local screen: ScreenGui
local panel: Frame
local openButton: TextButton
local list: ScrollingFrame
local detail: TextLabel
local closeButton: TextButton
local mobileRows: { TextButton } = {}
local labels: { () -> () } = {}
local enlargedFits = true
local function setOpen(open: boolean)
	panel.Visible = open
	Input.setModal("Menu", open)
end
local function button(text: string, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = UDim2.new(1, -12, 0, 48)
	Theme.button(b, "secondary")
	Layout.limitText(b, 14, 21)
	b.Parent = parent
	return b
end
local function option(key: string, values: { any }, describe: () -> string)
	local b = button("", list)
	table.insert(mobileRows, b)
	table.insert(labels, function()
		b.Text = describe()
	end)
	b.Activated:Connect(function()
		local index = table.find(values, Settings.get(key)) or 1
		Settings.set(key, values[index % #values + 1])
	end)
end
local function refresh()
	local touch = Input.isTouch()
	openButton.Visible = not Input.isModalOpen()
	for _, row in mobileRows do
		row.Visible = touch
	end
	for _, apply in labels do
		apply()
	end
	detail.Text = if touch
		then "Segure ATIRAR e arraste para acompanhar o alvo.\nAnalógico e pulo são do Roblox. Ajustes valem nesta sessão.\nA partida online continua com o menu aberto."
		else "WASD: mover · Mouse: tiro / mira\nR: recarga · Q: habilidade · G: granada\nV: corpo a corpo · E: interagir · Espaço: pular"
end
function Menu.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "GameMenu"
	Layout.configure(screen, 40)
	openButton = button("MENU", screen)
	openButton.Name = "MenuButton"
	panel = Instance.new("Frame")
	panel.Name = "Menu"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Active = true
	Theme.panel(panel, 0.05)
	panel.Visible = false
	panel.Parent = screen
	Theme.text(
		panel,
		"display",
		{
			Position = UDim2.fromOffset(16, 8),
			Size = UDim2.new(1, -32, 0, 32),
			Text = "MENU E CONTROLES",
		}
	)
	list = Instance.new("ScrollingFrame")
	list.Name = "Options"
	list.Position = UDim2.fromOffset(16, 48)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = panel
	local flow = Instance.new("UIListLayout")
	flow.Padding = UDim.new(0, 8)
	flow.SortOrder = Enum.SortOrder.LayoutOrder
	flow.Parent = list
	button("PROGRESSÃO E COSMÉTICOS", list).Activated:Connect(function()
		setOpen(false)
		Input.panelRequested:fire("Progression")
	end)
	option("size", { 1, 1.2 }, function()
		return "TAMANHO: "
			.. (
				if Settings.get("size") == 1
					then "PADRÃO"
					elseif enlargedFits then "AMPLIADO"
					else "AUTO — LIMITE DA TELA"
			)
	end)
	option("transparency", { 0.15, 0.35, 0.55 }, function()
		return "OPACIDADE: "
			.. tostring(math.round((1 - Settings.get("transparency")) * 100))
			.. "%"
	end)
	option("sensitivity", { 0.75, 1, 1.25 }, function()
		return "CÂMERA: " .. tostring(Settings.get("sensitivity")) .. "×"
	end)
	option("aimSensitivity", { 0.5, 0.75, 1 }, function()
		return "CÂMERA AO MIRAR: " .. tostring(Settings.get("aimSensitivity")) .. "×"
	end)
	option("aimMode", { "toggle", "hold" }, function()
		return "MIRA: "
			.. (if Settings.get("aimMode") == "toggle" then "TOCAR PARA ALTERNAR" else "SEGURAR")
	end)
	option("autoFire", { true, false }, function()
		return "DISPARO AUTOMÁTICO: "
			.. (if Settings.get("autoFire") then "LIGADO" else "DESLIGADO")
	end)
	local reset = button("RESTAURAR CONTROLES PADRÃO", list)
	table.insert(mobileRows, reset)
	reset.Activated:Connect(Settings.reset)
	detail = Theme.text(
		list,
		"label",
		{ Size = UDim2.new(1, -12, 0, 96), TextWrapped = true, TextSize = 14, TextScaled = false }
	)
	for order, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child.LayoutOrder = order
		end
	end
	closeButton = button("VOLTAR AO JOGO", panel)
	closeButton.Activated:Connect(function()
		setOpen(false)
	end)
	openButton.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)
	Input.registerModal("Menu", function()
		setOpen(false)
	end)
end
function Menu.start()
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Layout.bind(screen, function(m)
		openButton.AnchorPoint = Vector2.new(1, 0)
		openButton.Position = UDim2.new(1, -12, 0, 12)
		openButton.Size = UDim2.fromOffset(88, 44)
		local height = math.min(560, m.size.Y - 24)
		panel.Size = UDim2.fromOffset(math.min(440, m.size.X - 24), height)
		list.Size = UDim2.new(1, -32, 0, math.max(48, height - 116))
		closeButton.Position = UDim2.new(0, 16, 1, -56)
		closeButton.Size = UDim2.new(1, -32, 0, 44)
		enlargedFits = m.mobile.enlargement == m.mobile.requestedEnlargement
		refresh()
	end)
	local match = ReplicatedStorage:FindFirstChild("Match")
	if match then
		match:GetAttributeChangedSignal("Phase"):Connect(function()
			setOpen(false)
		end)
	end
	Input.modalChanged:connect(refresh)
	Settings.changed:connect(refresh)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refresh)
	refresh()
end
return Menu
