--!strict
-- Health bar over each barricade, driven by the Health/MaxHealth/Broken attributes the server
-- sets. Hidden at full health so a calm fort stays clean; shows "QUEBRADA" when down.

local CollectionService = game:GetService("CollectionService")

local Tags = require(game:GetService("ReplicatedStorage").Shared.Tags)

local BarricadeHUD = {}

local COLOR_FULL = Color3.fromRGB(255, 204, 0)
local COLOR_LOW = Color3.fromRGB(220, 40, 40)

local function number(part: Instance, name: string, default: number): number
	local value = part:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or instance:FindFirstChild("BarricadeHealth") then
		return
	end
	local part = instance

	local gui = Instance.new("BillboardGui")
	gui.Name = "BarricadeHealth"
	gui.Size = UDim2.fromScale(4, 0.5)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.2, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Adornee = part

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Parent = back

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "QUEBRADA"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = back

	local function refresh()
		local maxHealth = number(part, "MaxHealth", 1)
		local ratio = math.clamp(number(part, "Health", maxHealth) / maxHealth, 0, 1)
		local broken = part:GetAttribute("Broken") == true
		gui.Enabled = broken or ratio < 1
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = COLOR_LOW:Lerp(COLOR_FULL, ratio)
		label.Visible = broken
	end

	part:GetAttributeChangedSignal("Health"):Connect(refresh)
	part:GetAttributeChangedSignal("Broken"):Connect(refresh)
	refresh()
	gui.Parent = part
end

function BarricadeHUD.start()
	CollectionService:GetInstanceAddedSignal(Tags.Barricade):Connect(track)
	for _, part in CollectionService:GetTagged(Tags.Barricade) do
		track(part)
	end
end

return BarricadeHUD
