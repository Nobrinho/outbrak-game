--!strict
-- Optional catalog art with native UI fallback while an image is unavailable/moderating.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = require(script.Parent.Assets)
local Ids = require(ReplicatedStorage.Shared.Art.AssetIds)

local AssetView = {}

function AssetView.resolve(key: string): string?
	return Assets.resolve(key, Ids)
end

function AssetView.image(parent: Instance, key: string, props: { [string]: any }?): ImageLabel?
	local uri = AssetView.resolve(key)
	if not uri then
		return nil
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Asset_" .. key
	image.BackgroundTransparency = 1
	image.Active = false
	image.Image = uri
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.fromOffset(24, 24)
	for name, value in props or {} do
		(image :: any)[name] = value
	end
	image.Parent = parent
	return image
end

function AssetView.slice(parent: GuiObject, key: string, transparency: number?): ImageLabel?
	return AssetView.image(parent, key, {
		Name = "AssetSurface",
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(12, 12, 52, 52),
		ImageTransparency = transparency or 0,
	})
end

-- Keep the caption a separate GUI element: localized labels/prices remain readable even
-- when the texture changes. Native button remains the input target (including gamepad).
function AssetView.button(button: TextButton, family: string)
	if
		button:GetAttribute("AssetSkinned")
		or not AssetView.resolve("ui.buttons." .. family .. "-normal")
	then
		return
	end
	button:SetAttribute("AssetSkinned", true)
	button.AutoButtonColor = false
	local image = AssetView.slice(button, "ui.buttons." .. family .. "-normal")
	if not image then
		return
	end
	local caption = Instance.new("TextLabel")
	caption.Name = "AssetCaption"
	caption.BackgroundTransparency = 1
	caption.Size = UDim2.fromScale(1, 1)
	caption.ZIndex = button.ZIndex + 1
	caption.Active = false
	caption.Parent = button
	local hover, pressed, focused = false, false, false
	local function sync()
		local disabled = button:GetAttribute("AssetDisabled") == true
		local state = if disabled
			then "disabled"
			elseif pressed then "pressed"
			elseif focused then "focused"
			elseif hover then "hover"
			else "normal"
		image.Image = AssetView.resolve("ui.buttons." .. family .. "-" .. state) or image.Image
		image.ZIndex = button.ZIndex
		caption.ZIndex = button.ZIndex + 1
		caption.Text = button.Text
		caption.TextColor3 = button.TextColor3
		caption.FontFace = button.FontFace
		caption.TextScaled = button.TextScaled
		caption.TextSize = button.TextSize
		caption.TextWrapped = button.TextWrapped
		caption.TextXAlignment = button.TextXAlignment
		caption.TextYAlignment = button.TextYAlignment
		caption.TextStrokeTransparency = button.TextStrokeTransparency
		-- The separate caption remains visible even if a texture is still loading or rejected.
		caption.Visible = true
		button.TextTransparency = 1
	end
	for _, property in
		{
			"Text",
			"TextColor3",
			"FontFace",
			"TextScaled",
			"TextSize",
			"TextWrapped",
			"TextXAlignment",
			"TextYAlignment",
			"ZIndex",
		}
	do
		button:GetPropertyChangedSignal(property):Connect(sync)
	end
	button:GetAttributeChangedSignal("AssetDisabled"):Connect(sync)
	image:GetPropertyChangedSignal("IsLoaded"):Connect(sync)
	button.MouseEnter:Connect(function()
		hover = true
		sync()
	end)
	button.MouseLeave:Connect(function()
		hover = false
		pressed = false
		sync()
	end)
	button.SelectionGained:Connect(function()
		focused = true
		sync()
	end)
	button.SelectionLost:Connect(function()
		focused = false
		pressed = false
		sync()
	end)
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			pressed = true
			sync()
		end
	end)
	-- Global release handles a pointer/finger leaving the button while pressed.
	local release = game:GetService("UserInputService").InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			pressed = false
			sync()
		end
	end)
	button.Destroying:Connect(function()
		release:Disconnect()
	end)
	sync()
end

return AssetView
