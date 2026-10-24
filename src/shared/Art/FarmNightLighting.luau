--!strict
-- Moonlit blue ambience with warm practical lights supplied by the map.
-- Called after FarmMap's original lighting setup; this adjusts those effects in place.
local Lighting = game:GetService("Lighting")

local FarmNightLighting = {}

function FarmNightLighting.apply()
	Lighting.ClockTime = 0.5
	Lighting.GeographicLatitude = 32
	Lighting.Brightness = 1.7
	Lighting.ExposureCompensation = 0.15
	-- Keep outdoor silhouettes readable on mobile, including when post effects are disabled.
	Lighting.Ambient = Color3.fromRGB(52, 58, 74)
	Lighting.OutdoorAmbient = Color3.fromRGB(74, 88, 111)
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.55

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.29
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(133, 164, 193)
	atmosphere.Decay = Color3.fromRGB(39, 57, 83)
	atmosphere.Glare = 0.08
	atmosphere.Haze = 1.5

	local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Parent = Lighting
	end
	grade.Enabled = true
	grade.Brightness = 0
	grade.Contrast = 0.08
	grade.Saturation = -0.12
	-- A restrained tint leaves the lamps orange instead of washing the whole scene blue.
	grade.TintColor = Color3.fromRGB(235, 242, 255)

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Parent = Lighting
	end
	bloom.Enabled = true
	bloom.Intensity = 0.22
	bloom.Size = 24
	bloom.Threshold = 1.8

	-- Use Studio's built-in Sky defaults, including its moon; no external asset dependency.
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Name = "FarmMoonSky"
		sky.Parent = Lighting
	end
	sky.CelestialBodiesShown = true
	sky.MoonAngularSize = 12
	sky.SunAngularSize = 8
	sky.StarCount = 450

	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Name = "FarmMoonClouds"
		clouds.Parent = workspace.Terrain
	end
	clouds.Enabled = true
	clouds.Cover = 0.65
	clouds.Density = 0.72
	clouds.Color = Color3.fromRGB(79, 95, 118)
end

return FarmNightLighting
