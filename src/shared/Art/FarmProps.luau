--!strict
-- Blender meshes for the farm props (tools/blender/props.py): the rusted tractor, the pickup
-- and the crates. FarmMap still builds the original parts, which keep giving collisions, cover
-- and flow-field walls; when the meshes are imported into ReplicatedStorage.Assets.Props, those
-- parts turn invisible and the meshes are laid over them. Each prop is authored around the
-- centre of its body part, where a <Prop>_Origin marker cube gives the importer's unit scale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FarmProps = {}

local MARKER_SIZE = 0.1

type Look = { color: Color3, material: Enum.Material }
type PropDef = {
	anchor: string, -- body part the prop is drawn around
	parts: string, -- pattern for every original part of the prop (hidden when meshed)
	tones: { [string]: Look },
}

local function look(r: number, g: number, b: number, material: Enum.Material): Look
	return { color = Color3.fromRGB(r, g, b), material = material }
end

local TIRE = look(28, 28, 30, Enum.Material.Rubber)
local DARK = look(43, 38, 34, Enum.Material.Metal)

local PROPS: { [string]: PropDef } = {
	Tractor = {
		anchor = "TractorBody",
		parts = "^Tractor",
		tones = {
			Paint = look(124, 72, 44, Enum.Material.CorrodedMetal),
			Dark = DARK,
			Tire = TIRE,
			Rim = look(176, 146, 74, Enum.Material.CorrodedMetal),
		},
	},
	Truck = {
		anchor = "TruckBody",
		parts = "^Truck",
		tones = {
			Paint = look(113, 44, 31, Enum.Material.CorrodedMetal),
			Glass = look(30, 36, 42, Enum.Material.Glass),
			Tire = TIRE,
			Chrome = look(82, 86, 86, Enum.Material.Metal),
			Dark = DARK,
			Lamp = look(174, 161, 119, Enum.Material.Glass),
			Tail = look(120, 32, 26, Enum.Material.Glass),
		},
	},
	Crate = {
		anchor = "Crate",
		parts = "^Crate$",
		tones = {
			Wood = look(108, 94, 77, Enum.Material.WoodPlanks),
			Frame = look(72, 60, 48, Enum.Material.Wood),
		},
	},
}

-- Lays the meshes over map.Props and returns the props it drew, so FarmStructures skips its
-- part-built details for them. Without imported meshes nothing changes.
function FarmProps.apply(map: Instance, parent: Instance): { [string]: boolean }
	local meshed: { [string]: boolean } = {}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild("Props")
	local props = map:FindFirstChild("Props")
	if not source or not props then
		return meshed
	end
	local meshes: { [string]: MeshPart } = {}
	for _, d in source:GetDescendants() do
		if d:IsA("MeshPart") then
			meshes[d.Name] = d
		end
	end

	for name, def in PROPS do
		local origin = meshes[name .. "_Origin"]
		if not origin then
			continue
		end
		local scale = MARKER_SIZE / math.max(origin.Size.X, 1e-6)
		local folder = Instance.new("Folder")
		folder.Name = name .. "Meshes"
		for _, anchor in props:GetChildren() do
			if not anchor:IsA("BasePart") or anchor.Name ~= def.anchor then
				continue
			end
			for tone, toneLook in def.tones do
				local mesh = meshes[name .. "_" .. tone]
				if not mesh then
					continue
				end
				local piece = mesh:Clone()
				for _, child in piece:GetChildren() do
					child:Destroy() -- importer leftovers (welds, attachments)
				end
				local relative = origin.CFrame:ToObjectSpace(mesh.CFrame)
				piece.Name = name .. tone
				piece.Size = mesh.Size * scale
				piece.CFrame = anchor.CFrame
					* CFrame.new(relative.Position * scale)
					* relative.Rotation
				piece.Color = toneLook.color
				piece.Material = toneLook.material
				piece.Parent = folder
			end
		end
		for _, p in props:GetChildren() do
			if p:IsA("BasePart") and p.Name:match(def.parts) then
				p.Transparency = 1
			end
		end
		folder.Parent = parent
		meshed[name] = true
	end
	return meshed
end

return FarmProps
