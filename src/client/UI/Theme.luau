--!strict
-- HUD look (docs/DEFINICOES.md §3): dark translucent panels with a yellow corner tab (the
-- "cut corner"), a condensed military face for numbers and labels (Oswald) and a rough
-- display face for announcements (Bangers). Every HUD builds its panels and text through here.

local Theme = {}

Theme.COLOR = table.freeze({
	panel = Color3.fromRGB(16, 16, 20),
	text = Color3.fromRGB(236, 232, 222),
	muted = Color3.fromRGB(160, 156, 148),
	accent = Color3.fromRGB(255, 204, 0), -- interactive / economy
	danger = Color3.fromRGB(220, 40, 40),
	player = Color3.fromRGB(0, 200, 230),
	fire = Color3.fromRGB(255, 140, 20),
})

Theme.FONT = table.freeze({
	label = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Medium),
	heavy = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	display = Font.new("rbxasset://fonts/families/Bangers.json"),
})

export type TextStyle = "label" | "heavy" | "display"

-- A TextLabel in the house style; `props` are applied last and can override anything.
function Theme.text(parent: Instance, style: TextStyle, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Theme.COLOR.text
	l.FontFace = Theme.FONT[style]
	l.TextScaled = true
	l.TextStrokeTransparency = 0.75
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

-- Styles a frame as a HUD panel: dark glass, thin light edge and the yellow corner tab.
function Theme.panel(frame: GuiObject, transparency: number?)
	frame.BackgroundColor3 = Theme.COLOR.panel
	frame.BackgroundTransparency = transparency or 0.3
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.COLOR.text
	stroke.Transparency = 0.85
	stroke.Thickness = 1
	stroke.Parent = frame

	-- A square turned 45° and clipped by the panel reads as a cut, highlighted corner.
	local tab = Instance.new("Frame")
	tab.Name = "CornerTab"
	tab.AnchorPoint = Vector2.new(0.5, 0.5)
	tab.Position = UDim2.fromOffset(0, 0)
	tab.Size = UDim2.fromOffset(16, 16)
	tab.Rotation = 45
	tab.BackgroundColor3 = Theme.COLOR.accent
	tab.BorderSizePixel = 0
	tab.ZIndex = frame.ZIndex + 1
	tab.Parent = frame
end

-- Big action button (shop, class cards): yellow fill, dark heavy text.
function Theme.button(button: TextButton)
	button.BackgroundColor3 = Theme.COLOR.accent
	button.TextColor3 = Theme.COLOR.panel
	button.FontFace = Theme.FONT.heavy
	button.TextScaled = true
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = button
end

return Theme
