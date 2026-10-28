--!strict
-- Decorative models from the catalog. Authoring origin is ground center, Roblox -Z forward.
-- All pieces remain non-interactive; gameplay uses the original simple colliders/prompts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KitModels = {}

function KitModels.clone(name: string, at: CFrame, parent: Instance, scale: number?): Model?
	local kit = ReplicatedStorage:FindFirstChild("OutbreakKit")
	local source = kit and kit:FindFirstChild(name)
	if not source or not source:IsA("Model") then
		return nil
	end
	local model = source:Clone()
	model.Name = name .. "Art"
	model.WorldPivot = CFrame.identity
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(at)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
		end
	end
	model.Parent = parent
	return model
end

-- Attach an appearance to an existing physics projectile; server keeps the same mass/shape.
function KitModels.attach(name: string, anchor: BasePart, offset: CFrame?, scale: number?): Model?
	local model = KitModels.clone(name, anchor.CFrame * (offset or CFrame.identity), anchor, scale)
	if not model then
		return nil
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Massless = true
			p.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchor
			weld.Part1 = p
			weld.Parent = p
		end
	end
	anchor.Transparency = 1
	return model
end

return KitModels
