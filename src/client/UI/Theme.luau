--!strict
-- HUD look (docs/DEFINICOES.md §3): dark translucent panels with a yellow corner tab (the
-- "cut corner"), a condensed military face for numbers and labels (Oswald) and a rough
-- display face for announcements (Bangers). Every HUD builds its panels and text through here.

local Theme = {}
local Tokens = require(script.Parent.Tokens)
local AssetView = require(script.Parent.AssetView)

Theme.TOKENS = Tokens
Theme.COLOR = Tokens.color
Theme.FONT = Tokens.font
Theme.image = AssetView.image
Theme.skinButton = AssetView.button

export type TextStyle = "label" | "heavy" | "display"

-- A TextLabel in the house style; `props` are applied last and can override anything.
function Theme.text(parent: Instance, style: TextStyle, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Theme.COLOR.text
	l.FontFace = Theme.FONT[style]
	l.TextScaled = true
	l.TextStrokeTransparency = Tokens.transparency.textStroke
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

-- Styles a frame as a HUD panel: dark glass, thin light edge and the yellow corner tab.
function Theme.panel(frame: GuiObject, transparency: number?)
	frame.BackgroundColor3 = Theme.COLOR.panel
	frame.BackgroundTransparency = transparency or Tokens.transparency.hud
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	AssetView.slice(
		frame,
		if (transparency or Tokens.transparency.hud) <= 0.15
			then "ui.panels.modal"
			else "ui.panels.hud",
		transparency
	)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Tokens.geometry.radius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.COLOR.text
	stroke.Transparency = Tokens.transparency.edge
	stroke.Thickness = Tokens.geometry.stroke
	stroke.Parent = frame

	-- A square turned 45° and clipped by the panel reads as a cut, highlighted corner.
	local tab = Instance.new("Frame")
	tab.Name = "CornerTab"
	tab.AnchorPoint = Vector2.new(0.5, 0.5)
	tab.Position = UDim2.fromOffset(0, 0)
	tab.Size = UDim2.fromOffset(Tokens.geometry.cornerTab, Tokens.geometry.cornerTab)
	tab.Rotation = 45
	tab.BackgroundColor3 = Theme.COLOR.accent
	tab.BorderSizePixel = 0
	tab.ZIndex = frame.ZIndex + 1
	tab.Parent = frame
end

-- Big action button (shop, class cards): yellow fill, dark heavy text.
function Theme.button(button: TextButton, family: string?)
	button.BackgroundColor3 = if family == "secondary"
		then Theme.COLOR.surface
		else Theme.COLOR.accent
	button.TextColor3 = if family == "secondary" then Theme.COLOR.text else Theme.COLOR.panel
	button.FontFace = Theme.FONT.heavy
	button.TextScaled = true
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Tokens.geometry.radius)
	corner.Parent = button
	AssetView.button(button, family or "primary")
end

return Theme
