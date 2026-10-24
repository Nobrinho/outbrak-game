--!strict
-- Animates map lights tagged Flicker on the client, so no property changes cross the network.
-- LightMode "fire" wavers with noise; "blink" pulses on and off (silo beacon).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Tags = require(game:GetService("ReplicatedStorage").Shared.Tags)
local Effects = require(script.Parent.Parent.Effects)

local AmbienceController = {}

type Flicker = {
	bulb: BasePart,
	light: PointLight,
	base: number,
	blink: boolean,
	seed: number,
	bulbTransparency: number,
}

local flickers: { [Instance]: Flicker } = {}

local function track(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local light = instance:FindFirstChildOfClass("PointLight")
		or instance:WaitForChild("PointLight", 5)
	if not light or not light:IsA("PointLight") then
		return
	end
	local base = instance:GetAttribute("BaseBrightness")
	flickers[instance] = {
		bulb = instance,
		light = light,
		base = if typeof(base) == "number" then base else light.Brightness,
		blink = instance:GetAttribute("LightMode") == "blink",
		seed = math.random() * 100,
		bulbTransparency = instance.Transparency,
	}
end

local function step()
	local t = os.clock()
	for _, f in flickers do
		if f.blink then
			local on = math.sin(t * 4 + f.seed) > 0
			f.light.Brightness = if on then f.base else 0
			f.bulb.Transparency = if on then f.bulbTransparency else 0.8
		else
			-- math.noise is roughly [-0.5, 0.5]; two octaves read as a live flame.
			local n = math.noise(t * 5, f.seed) + 0.5 * math.noise(t * 13, f.seed + 10)
			f.light.Brightness = f.base * (0.85 + 0.45 * n)
		end
	end
end

function AmbienceController.start()
	Effects.start() -- camera shake and automatic effect quality
	CollectionService:GetInstanceAddedSignal(Tags.Flicker):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.Flicker):Connect(function(instance)
		flickers[instance] = nil
	end)
	for _, instance in CollectionService:GetTagged(Tags.Flicker) do
		task.spawn(track, instance)
	end
	RunService.RenderStepped:Connect(step)
end

return AmbienceController
