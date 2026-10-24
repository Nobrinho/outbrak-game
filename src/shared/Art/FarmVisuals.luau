--!strict
-- Art-only integration. Original map parts, prompts and gameplay tags stay in place.
local Structures = require(script.Parent.FarmStructures)
local Environment = require(script.Parent.FarmEnvironment)
local NightLighting = require(script.Parent.FarmNightLighting)
local Props = require(script.Parent.FarmProps)

local FarmVisuals = {}

function FarmVisuals.apply(map: Instance)
	if map:FindFirstChild("VisualUpgrade") then
		return
	end
	local root = Instance.new("Folder")
	root.Name = "VisualUpgrade"
	Structures.build(map, root, Props.apply(map, root))
	Environment.build(root)
	-- Keep every surface out of movement, hitscan and overlap queries.
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	root.Parent = map
	NightLighting.apply()
end

return FarmVisuals
