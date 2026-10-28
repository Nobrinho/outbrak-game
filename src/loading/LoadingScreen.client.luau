--!strict
-- Covers the first seconds of a place: the map is built at runtime and the engine lights it
-- progressively after the parts arrive, so the world only shows once it is lit. Runs from
-- ReplicatedFirst, before the rest of the game replicates; Tokens and AssetIds are mapped as
-- children by both Rojo projects, and the attributes on this script say which place it is.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Tokens = require(script:WaitForChild("Tokens"))
local AssetIds = require(script:WaitForChild("AssetIds"))

-- The engine exposes no "lighting ready" signal to game scripts (its quality stats need
-- plugin access). Lighting converges over rendered frames, not seconds: measured in Studio,
-- the final look arrived 225–310 frames after the map. Count frames past that, with margin.
local LIGHT_FRAMES = 360
-- Never trap a player behind the screen, whatever fails to replicate or however slow the GPU.
local TIMEOUT = 45

local COLOR = Tokens.color
local SPACE = Tokens.space

local title = script:GetAttribute("Title") or "CARREGANDO"
local worldName = script:GetAttribute("World") or "Map"
local background = script:GetAttribute("Background")

ReplicatedFirst:RemoveDefaultLoadingScreen()

-- Two layers: the art bleeds under notches and rounded corners, the panel stays in the safe area.
local function layer(
	name: string,
	insets: Enum.ScreenInsets,
	order: number
): (ScreenGui, CanvasGroup)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = insets
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local group = Instance.new("CanvasGroup")
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Parent = gui
	return gui, group
end

local backdropGui, root = layer("LoadingScreen", Enum.ScreenInsets.None, 100)
root.BackgroundColor3 = COLOR.panel
root.BackgroundTransparency = 0
local contentGui, content = layer("LoadingScreenContent", Enum.ScreenInsets.DeviceSafeInsets, 101)

local artId = if typeof(background) == "string" then AssetIds[background] else nil
if artId then
	local art = Instance.new("ImageLabel")
	art.Name = "Background"
	art.Size = UDim2.fromScale(1, 1)
	art.BackgroundTransparency = 1
	art.Image = "rbxassetid://" .. artId
	art.ScaleType = Enum.ScaleType.Crop
	art.Parent = root
end

-- Darkens the lower part of the art so the panel and its text stay readable on any crop.
local shade = Instance.new("Frame")
shade.Name = "Shade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = COLOR.panel
shade.BorderSizePixel = 0
shade.ZIndex = 2
shade.Parent = root
local fade = Instance.new("UIGradient")
fade.Rotation = 90
fade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.85),
	NumberSequenceKeypoint.new(0.5, 0.6),
	NumberSequenceKeypoint.new(1, 0.1),
})
fade.Parent = shade

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, SPACE.major, 1, -SPACE.major)
panel.Size = UDim2.new(0.6, 0, 0, 148)
panel.BackgroundColor3 = COLOR.panel
panel.BackgroundTransparency = Tokens.transparency.modal
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.ZIndex = 3
panel.Parent = content
local maxWidth = Instance.new("UISizeConstraint")
maxWidth.MaxSize = Vector2.new(360, 148)
maxWidth.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, Tokens.geometry.radius)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = COLOR.text
stroke.Transparency = Tokens.transparency.edge
stroke.Thickness = Tokens.geometry.stroke
stroke.Parent = panel
-- Same signature corner as Theme.panel: a square turned 45° and clipped by the panel.
local tab = Instance.new("Frame")
tab.Name = "CornerTab"
tab.AnchorPoint = Vector2.new(0.5, 0.5)
tab.Size = UDim2.fromOffset(Tokens.geometry.cornerTab, Tokens.geometry.cornerTab)
tab.Rotation = 45
tab.BackgroundColor3 = COLOR.accent
tab.BorderSizePixel = 0
tab.ZIndex = 4
tab.Parent = panel

local function label(name: string, font: Font, size: number, color: Color3, y: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(SPACE.large, y)
	l.Size = UDim2.new(1, -SPACE.large * 2, 0, size + SPACE.micro)
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.ZIndex = 4
	l.Parent = panel
	return l
end

label("Kicker", Tokens.font.label, Tokens.textSize.caption, COLOR.muted, SPACE.large).Text =
	"ENTRANDO EM"
label("Title", Tokens.font.display, Tokens.textSize.announcement, COLOR.text, SPACE.large + 16).Text =
	title
local status = label("Status", Tokens.font.label, Tokens.textSize.caption, COLOR.text, 96)

local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0, 1)
track.Position = UDim2.new(0, SPACE.large, 1, -SPACE.large)
track.Size = UDim2.new(1, -SPACE.large * 2, 0, SPACE.micro)
track.BackgroundColor3 = COLOR.surface
track.BorderSizePixel = 0
track.ZIndex = 4
track.Parent = panel
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = COLOR.accent
fill.BorderSizePixel = 0
fill.ZIndex = 5
fill.Parent = track

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
backdropGui.Parent = playerGui
contentGui.Parent = playerGui

local deadline = os.clock() + TIMEOUT

local function step(text: string, progress: number)
	status.Text = text
	TweenService:Create(
		fill,
		TweenInfo.new(Tokens.motion.transition, Enum.EasingStyle.Quad),
		{ Size = UDim2.fromScale(progress, 1) }
	):Play()
end

-- Waits for `ready` without passing the shared deadline.
local function waitUntil(ready: () -> boolean)
	while not ready() and os.clock() < deadline do
		task.wait(0.1)
	end
end

step("CARREGANDO ARQUIVOS", 0.15)
waitUntil(function()
	return game:IsLoaded()
end)
step("MONTANDO O MAPA", 0.45)
waitUntil(function()
	return workspace:FindFirstChild(worldName) ~= nil
end)
step("PREPARANDO O SOBREVIVENTE", 0.7)
waitUntil(function()
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
end)
-- The camera is already on the character behind the screen, so these frames light the view.
step("AJUSTANDO A ILUMINAÇÃO", 0.75)
local frames = 0
local counter = RunService.RenderStepped:Connect(function()
	frames += 1
	fill.Size = UDim2.fromScale(0.75 + 0.25 * math.min(frames / LIGHT_FRAMES, 1), 1)
end)
waitUntil(function()
	return frames >= LIGHT_FRAMES
end)
counter:Disconnect()

local info = TweenInfo.new(Tokens.motion.transition * 2, Enum.EasingStyle.Quad)
TweenService:Create(content, info, { GroupTransparency = 1 }):Play()
local reveal = TweenService:Create(root, info, { GroupTransparency = 1 })
reveal.Completed:Connect(function()
	backdropGui:Destroy()
	contentGui:Destroy()
end)
reveal:Play()
