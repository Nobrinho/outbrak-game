--!strict
-- Studio-only invariant check. Capture the SAME map before and after its art pass.
-- New descendants of the direct child Map.VisualUpgrade are deliberately ignored.
-- This helper does not mutate the map, services, attributes, or physics settings.

type Record = {
	path: string,
	className: string,
	parent: Instance?,
	properties: { [string]: any },
	attributes: { [string]: any },
	tags: { string },
}

export type Snapshot = {
	root: Instance,
	records: { [Instance]: Record },
	count: number,
	baseParts: number,
	prompts: number,
}

local Verifier = {}
local EPSILON = 1e-5

local function value(raw: any): any
	local kind = typeof(raw)
	if kind == "CFrame" then
		return { kind = kind, components = { raw:GetComponents() } }
	elseif kind == "Vector3" then
		return { kind = kind, components = { raw.X, raw.Y, raw.Z } }
	elseif kind == "Vector2" then
		return { kind = kind, components = { raw.X, raw.Y } }
	elseif kind == "Color3" then
		return { kind = kind, components = { raw.R, raw.G, raw.B } }
	elseif kind == "PhysicalProperties" then
		return {
			kind = kind,
			components = {
				raw.Density,
				raw.Friction,
				raw.Elasticity,
				raw.FrictionWeight,
				raw.ElasticityWeight,
			},
		}
	elseif kind == "number" or kind == "string" or kind == "boolean" or kind == "nil" then
		return raw
	end
	return { kind = kind, description = tostring(raw) }
end

local function equivalent(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) == "number" then
		return a == b or math.abs(a - b) <= EPSILON
	end
	if type(a) ~= "table" then
		return a == b
	end
	for key, item in a do
		if not equivalent(item, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function Verifier.capture(root: Instance): Snapshot
	local snapshot: Snapshot = { root = root, records = {}, count = 0, baseParts = 0, prompts = 0 }
	local function visit(instance: Instance)
		if instance.Parent == root and instance.Name == "VisualUpgrade" then
			return
		end
		local tags = instance:GetTags()
		table.sort(tags)
		local attributes: { [string]: any } = {}
		for key, raw in instance:GetAttributes() do
			attributes[key] = value(raw)
		end
		local properties: { [string]: any } = { Name = instance.Name }
		if instance:IsA("BasePart") then
			snapshot.baseParts += 1
			properties.CFrame = value(instance.CFrame)
			properties.Size = value(instance.Size)
			properties.Anchored = instance.Anchored
			properties.CanCollide = instance.CanCollide
			properties.CanQuery = instance.CanQuery
			properties.CanTouch = instance.CanTouch
			properties.CollisionGroup = instance.CollisionGroup
			properties.Massless = instance.Massless
			properties.Material = value(instance.Material)
			properties.MaterialVariant = instance.MaterialVariant
			-- Explicit marker also catches transitions between nil and custom physics.
			properties.CustomPhysicalProperties = value(instance.CustomPhysicalProperties)
				or "default"
			properties.CurrentPhysicalProperties = value(instance.CurrentPhysicalProperties)
			if instance:IsA("Part") then
				properties.Shape = value(instance.Shape)
			elseif instance:IsA("MeshPart") then
				properties.MeshId = instance.MeshId
				properties.CollisionFidelity = value(instance.CollisionFidelity)
			end
			if #tags > 0 then
				-- Gameplay signals, including flickering light anchors, stay intact.
				properties.Color = value(instance.Color)
				properties.Transparency = instance.Transparency
				properties.CastShadow = instance.CastShadow
			end
		end
		if instance:IsA("SpawnLocation") then
			properties.Enabled = instance.Enabled
			properties.Neutral = instance.Neutral
			properties.Duration = instance.Duration
			properties.TeamColor = value(instance.TeamColor)
			properties.AllowTeamChangeOnTouch = instance.AllowTeamChangeOnTouch
		end
		if instance:IsA("ProximityPrompt") then
			snapshot.prompts += 1
			properties.Enabled = instance.Enabled
			properties.HoldDuration = instance.HoldDuration
			properties.MaxActivationDistance = instance.MaxActivationDistance
			properties.RequiresLineOfSight = instance.RequiresLineOfSight
			properties.KeyboardKeyCode = value(instance.KeyboardKeyCode)
			properties.GamepadKeyCode = value(instance.GamepadKeyCode)
			properties.ClickablePrompt = instance.ClickablePrompt
			properties.Exclusivity = value(instance.Exclusivity)
			properties.ActionText = instance.ActionText
			properties.ObjectText = instance.ObjectText
		end
		snapshot.records[instance] = {
			path = instance:GetFullName(),
			className = instance.ClassName,
			parent = instance.Parent,
			properties = properties,
			attributes = attributes,
			tags = tags,
		}
		snapshot.count += 1
		for _, child in instance:GetChildren() do
			visit(child)
		end
	end
	visit(root)
	return snapshot
end

function Verifier.compare(before: Snapshot, after: Snapshot)
	local changes: { string } = {}
	local function changed(path: string, detail: string)
		table.insert(changes, path .. ": " .. detail)
	end
	if before.root ~= after.root then
		changed("Map", "root instance replaced; capture and compare the same map")
	end
	for instance, previous in before.records do
		local current = after.records[instance]
		if not current then
			changed(
				previous.path,
				"original instance removed, replaced or moved into VisualUpgrade"
			)
			continue
		end
		if previous.parent ~= current.parent then
			changed(previous.path, "parent changed")
		end
		if previous.className ~= current.className then
			changed(previous.path, "class changed")
		end
		for property, expected in previous.properties do
			if not equivalent(expected, current.properties[property]) then
				changed(previous.path, "property " .. property .. " changed")
			end
		end
		for property in current.properties do
			if previous.properties[property] == nil then
				changed(previous.path, "property " .. property .. " added")
			end
		end
		if not equivalent(previous.attributes, current.attributes) then
			changed(previous.path, "attributes changed")
		end
		if not equivalent(previous.tags, current.tags) then
			changed(previous.path, "tags changed")
		end
	end
	for instance, current in after.records do
		if not before.records[instance] then
			changed(current.path, "new instance outside VisualUpgrade")
		end
	end
	table.sort(changes)
	return {
		ok = #changes == 0,
		originalCount = before.count,
		currentCount = after.count,
		originalBaseParts = before.baseParts,
		currentBaseParts = after.baseParts,
		originalPrompts = before.prompts,
		currentPrompts = after.prompts,
		changedCount = #changes,
		changes = changes,
	}
end

return Verifier
