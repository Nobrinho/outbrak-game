-- Run in Studio Edit mode after importing pipeline_barrel.fbx.
-- Importer defaults observed: FBX magnified 100x and solid colors omitted.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local model = assert(workspace:FindFirstChild("pipeline_barrel"), "Import pipeline_barrel first")
assert(model:IsA("Model"), "Expected a Model")
local _, beforeSize = model:GetBoundingBox()
local target = Vector3.new(2.26, 3.2, 2.26)
local scaleRatio = target.Y / beforeSize.Y
assert(
	math.abs(beforeSize.X / beforeSize.Y - target.X / target.Y) < 0.001,
	"Unexpected proportions"
)
local colors = {
	Barrel_Body = Color3.fromRGB(153, 104, 72),
	Barrel_Band_00 = Color3.fromRGB(89, 82, 77),
	Barrel_Band_01 = Color3.fromRGB(89, 82, 77),
	Barrel_Band_02 = Color3.fromRGB(89, 82, 77),
	Barrel_Band_03 = Color3.fromRGB(89, 82, 77),
}
local parts = {}
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") then
		assert(part:IsA("MeshPart") and colors[part.Name], "Unexpected mesh: " .. part.Name)
		assert(part.MeshId ~= "", "Expected uploaded mesh")
		table.insert(parts, part)
	end
end
assert(#parts == 5, "Expected exactly five meshes")
ChangeHistoryService:SetWaypoint("Before barrel import normalization")
model:ScaleTo(model:GetScale() * scaleRatio)
for _, part in parts do
	part.Color = colors[part.Name]
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
end
-- Put the imported asset beside the EditableMesh preview, with its base at Y=10.
local box, size = model:GetBoundingBox()
local base = box.Position - Vector3.new(0, size.Y / 2, 0)
local desiredBase = Vector3.new(304, 10, 0)
model:PivotTo(CFrame.new(desiredBase - base) * model:GetPivot())
model:SetAttribute("ImportValidated", true)
model:SetAttribute("ImportScaleCorrection", scaleRatio)
model:SetAttribute("Source", "Blender / pipeline_barrel.fbx")
local _, finalSize = model:GetBoundingBox()
assert((finalSize - target).Magnitude < 0.001, "Normalized size mismatch")
assert((model:GetPivot().Position - desiredBase).Magnitude < 0.001, "Base pivot mismatch")
ChangeHistoryService:SetWaypoint("Validated barrel import")
game:GetService("Selection"):Set({ model })
workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(307, 14, 10), Vector3.new(302, 11.6, 0))
return {
	validated = true,
	meshes = #parts,
	beforeSize = tostring(beforeSize),
	finalSize = tostring(finalSize),
	scaleCorrection = scaleRatio,
	pivot = tostring(model:GetPivot().Position),
}
