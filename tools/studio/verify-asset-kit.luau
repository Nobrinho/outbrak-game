-- Read-only smoke check. Execute in Edit, Server or Client after Rojo sync.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local kit = assert(ReplicatedStorage:FindFirstChild("OutbreakKit"), "Kit is missing")
local ids = require(ReplicatedStorage.Shared.Art.AssetIds)
local report = { models = 0, meshes = 0, images = 0, portals = 0, captions = 0 }
for _, id in ids do
	assert(typeof(id) == "number" and id > 0 and id % 1 == 0, "Invalid image ID")
	report.images += 1
end
for _, model in kit:GetChildren() do
	assert(model:IsA("Model"), "Expected a catalog model")
	report.models += 1
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			assert(
				p:IsA("MeshPart") and p.MeshId:match("^rbxassetid://%d+$"),
				"Missing real mesh ID"
			)
			assert(
				p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch,
				p:GetFullName()
			)
			report.meshes += 1
		end
	end
end
assert(report.models == 10 and report.meshes == 107 and report.images == 69, "Catalog count drift")
local hub = workspace:FindFirstChild("Hub")
local portals = hub and hub:FindFirstChild("Portals")
if portals then
	for _, pad in portals:GetChildren() do
		local zone = pad:FindFirstChild("Zone")
		assert(
			zone and zone:IsA("BasePart") and zone.Size == Vector3.new(18, 8, 18),
			"Portal hitbox changed"
		)
		assert(zone:GetAttribute("MapId") == pad.Name, "Portal identity changed")
		report.portals += 1
	end
end
local player = game:GetService("Players").LocalPlayer
local gui = player and player:FindFirstChildOfClass("PlayerGui")
if gui then
	for _, caption in gui:GetDescendants() do
		if caption.Name == "AssetCaption" and caption:IsA("TextLabel") then
			local button = caption.Parent
			assert(button and button:IsA("TextButton"), "Caption has no button")
			assert(
				caption.Visible and caption.Text == button.Text and button.TextTransparency == 1,
				"Button caption mismatch"
			)
			report.captions += 1
		end
	end
end
return report
