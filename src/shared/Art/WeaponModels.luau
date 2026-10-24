--!strict
-- Low-poly weapon models held in the player's right hand, grip at the origin and barrel
-- pointing -Z; a "Muzzle" part marks where tracers start. No textures: dark metal, worn wood,
-- a little steel.
--
-- Preferred source: Blender meshes (tools/blender/weapons.py) imported into
-- ReplicatedStorage.Assets.Weapons — one MeshPart per colour tone (<Name>_Metal, _Steel,
-- _Wood, _WoodDark) plus <Name>_Grip / <Name>_Muzzle marker cubes (0.1 stud in Blender). The
-- markers fix the importer's unit scale and orientation, so the raw import works as is.
-- Without imported meshes, the part-built models below are used.

local WeaponModels = {}

local METAL = Color3.fromRGB(42, 44, 48)
local STEEL = Color3.fromRGB(150, 154, 160)
local WOOD = Color3.fromRGB(110, 72, 44)
local WOOD_DARK = Color3.fromRGB(80, 52, 34)

type Piece = {
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material?,
	rotation: Vector3?,
}

local function p(
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material?,
	rotation: Vector3?
): Piece
	return { size = size, offset = offset, color = color, material = material, rotation = rotation }
end

-- Barrel tip per model, for the Muzzle marker.
local MODELS: { [string]: { pieces: { Piece }, muzzle: Vector3 } } = {
	Pistol = {
		pieces = {
			p(
				Vector3.new(0.25, 0.6, 0.35),
				Vector3.new(0, -0.2, 0.05),
				METAL,
				nil,
				Vector3.new(-15, 0, 0)
			),
			p(Vector3.new(0.27, 0.3, 1), Vector3.new(0, 0.2, -0.3), METAL, Enum.Material.Metal),
		},
		muzzle = Vector3.new(0, 0.2, -0.85),
	},
	SMG = {
		pieces = {
			p(Vector3.new(0.3, 0.45, 1.3), Vector3.new(0, 0.2, -0.35), METAL, Enum.Material.Metal),
			p(Vector3.new(0.22, 0.75, 0.3), Vector3.new(0, -0.3, -0.45), METAL),
			p(Vector3.new(0.14, 0.14, 0.5), Vector3.new(0, 0.25, -1.2), STEEL, Enum.Material.Metal),
			p(Vector3.new(0.2, 0.35, 0.6), Vector3.new(0, 0.15, 0.55), METAL),
		},
		muzzle = Vector3.new(0, 0.25, -1.5),
	},
	Shotgun = {
		pieces = {
			p(Vector3.new(0.22, 0.22, 2.4), Vector3.new(0, 0.3, -1), STEEL, Enum.Material.Metal),
			p(Vector3.new(0.3, 0.28, 0.7), Vector3.new(0, 0.1, -1), WOOD, Enum.Material.Wood),
			p(Vector3.new(0.3, 0.4, 0.6), Vector3.new(0, 0.2, 0.1), METAL),
			p(
				Vector3.new(0.28, 0.5, 1),
				Vector3.new(0, 0, 0.85),
				WOOD,
				Enum.Material.Wood,
				Vector3.new(-8, 0, 0)
			),
		},
		muzzle = Vector3.new(0, 0.3, -2.25),
	},
	Rifle = {
		pieces = {
			p(Vector3.new(0.3, 0.5, 1.8), Vector3.new(0, 0.2, -0.5), METAL, Enum.Material.Metal),
			p(Vector3.new(0.16, 0.16, 1), Vector3.new(0, 0.3, -1.85), STEEL, Enum.Material.Metal),
			p(Vector3.new(0.22, 0.22, 0.8), Vector3.new(0, 0.62, -0.5), METAL, Enum.Material.Metal),
			p(Vector3.new(0.22, 0.7, 0.32), Vector3.new(0, -0.3, -0.6), METAL),
			p(Vector3.new(0.26, 0.45, 0.9), Vector3.new(0, 0.1, 0.75), METAL),
		},
		muzzle = Vector3.new(0, 0.3, -2.4),
	},
	AK47 = {
		pieces = {
			p(Vector3.new(0.3, 0.42, 1.5), Vector3.new(0, 0.2, -0.4), METAL, Enum.Material.Metal),
			p(Vector3.new(0.32, 0.34, 0.7), Vector3.new(0, 0.18, -1.3), WOOD, Enum.Material.Wood),
			p(Vector3.new(0.14, 0.14, 0.7), Vector3.new(0, 0.3, -1.95), STEEL, Enum.Material.Metal),
			-- The curved magazine is the AK's silhouette.
			p(
				Vector3.new(0.22, 0.8, 0.32),
				Vector3.new(0, -0.35, -0.55),
				METAL,
				nil,
				Vector3.new(18, 0, 0)
			),
			p(
				Vector3.new(0.26, 0.5, 1),
				Vector3.new(0, 0.05, 0.75),
				WOOD,
				Enum.Material.Wood,
				Vector3.new(-10, 0, 0)
			),
		},
		muzzle = Vector3.new(0, 0.3, -2.3),
	},
	Knife = {
		pieces = {
			p(Vector3.new(0.18, 0.22, 0.5), Vector3.new(0, 0, 0.1), WOOD_DARK, Enum.Material.Wood),
			p(Vector3.new(0.06, 0.2, 0.8), Vector3.new(0, 0.02, -0.55), STEEL, Enum.Material.Metal),
		},
		muzzle = Vector3.new(0, 0, -0.95),
	},
	Bat = {
		pieces = {
			p(Vector3.new(0.22, 0.22, 1.2), Vector3.new(0, 0, -0.2), WOOD_DARK, Enum.Material.Wood),
			p(Vector3.new(0.38, 0.38, 1.6), Vector3.new(0, 0, -1.55), WOOD, Enum.Material.Wood),
			-- Nails sticking out of the head.
			p(Vector3.new(0.06, 0.6, 0.06), Vector3.new(0, 0, -1.4), STEEL, Enum.Material.Metal),
			p(Vector3.new(0.6, 0.06, 0.06), Vector3.new(0, 0, -1.8), STEEL, Enum.Material.Metal),
			p(Vector3.new(0.06, 0.6, 0.06), Vector3.new(0, 0, -2.1), STEEL, Enum.Material.Metal),
		},
		muzzle = Vector3.new(0, 0, -2.4),
	},
}

local GOLD = Color3.fromRGB(214, 172, 62)

local TONE_COLORS: { [string]: Color3 } = {
	Metal = METAL,
	Steel = STEEL,
	Wood = WOOD,
	WoodDark = WOOD_DARK,
}
local MARKER_SIZE = 0.1
-- Grip → muzzle in studs as authored in Blender (assets/export/weapons.json).
local MESH_MUZZLE: { [string]: Vector3 } = {
	Pistol = Vector3.new(0, 0.24, -0.95),
	SMG = Vector3.new(0, 0.28, -1.48),
	Shotgun = Vector3.new(0, 0.33, -2.25),
	Rifle = Vector3.new(0, 0.26, -2.35),
	AK47 = Vector3.new(0, 0.24, -2.25),
	Knife = Vector3.new(0, 0.03, -1.0),
	Bat = Vector3.new(0, 0, -2.45),
}

local function meshSource(): Instance?
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Weapons")
end

local function findMesh(root: Instance, name: string): BasePart?
	local found = root:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

-- Shortest-arc rotation turning `from` onto `to` (both non-zero).
local function arc(from: Vector3, to: Vector3): CFrame
	local a, b = from.Unit, to.Unit
	local axis = a:Cross(b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-4 then
		return if dot > 0 then CFrame.identity else CFrame.fromAxisAngle(Vector3.yAxis, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Rotation that turns `from` onto `to`, for import axis mismatches. Turns around the vertical
-- first (the Studio importer brings these FBX files in facing +Z, a 180° yaw), then fixes any
-- remaining pitch — a plain shortest arc would roll a reversed gun onto its side.
local function alignRotation(from: Vector3, to: Vector3): CFrame
	local yaw = CFrame.identity
	if
		Vector2.new(from.X, from.Z).Magnitude > 1e-3
		and Vector2.new(to.X, to.Z).Magnitude > 1e-3
	then
		yaw = CFrame.Angles(0, math.atan2(to.X, to.Z) - math.atan2(from.X, from.Z), 0)
	end
	return arc(yaw * from, to) * yaw
end

-- Builds `name` from imported Blender meshes, normalised to studs with the grip at the
-- origin. Nil if the meshes for it aren't in the place.
local function buildFromMeshes(name: string, skin: string?): Model?
	local source = meshSource()
	local grip = source and findMesh(source, name .. "_Grip")
	local tip = source and findMesh(source, name .. "_Muzzle")
	local expected = MESH_MUZZLE[name]
	if not source or not grip or not tip or not expected then
		return nil
	end
	local scale = MARKER_SIZE / math.max(grip.Size.X, 1e-6)
	local gripFrame = grip.CFrame
	local rawMuzzle = gripFrame:PointToObjectSpace(tip.Position) * scale
	if rawMuzzle.Magnitude < 1e-3 then
		return nil
	end
	-- Whatever axes the importer used, turn the grip→muzzle line onto the authored one.
	local fix = alignRotation(rawMuzzle, expected)

	local model = Instance.new("Model")
	model.Name = name
	for tone, color in TONE_COLORS do
		local mesh = findMesh(source, name .. "_" .. tone)
		if mesh then
			local piece = mesh:Clone()
			for _, child in piece:GetChildren() do
				child:Destroy() -- drop importer leftovers (welds, attachments)
			end
			local relative = gripFrame:ToObjectSpace(mesh.CFrame)
			piece.Size = mesh.Size * scale
			piece.CFrame = fix * (CFrame.new(relative.Position * scale) * relative.Rotation)
			local metal = tone == "Metal" or tone == "Steel"
			piece.Color = if skin == "gold" and metal then GOLD else color
			piece.Material = if skin == "gold" and metal
				then Enum.Material.Foil
				elseif metal then Enum.Material.Metal
				else Enum.Material.Wood
			piece.Anchored = false
			piece.Massless = true
			piece.CanCollide = false
			piece.CanQuery = false
			piece.CanTouch = false
			piece.CastShadow = false
			piece.Parent = model
		end
	end
	local muzzle = Instance.new("Part")
	muzzle.Name = "Muzzle"
	muzzle.Size = Vector3.new(0.1, 0.1, 0.1)
	muzzle.Transparency = 1
	muzzle.Anchored = false
	muzzle.Massless = true
	muzzle.CanCollide = false
	muzzle.CanQuery = false
	muzzle.CanTouch = false
	muzzle.CFrame = CFrame.new(expected)
	muzzle.Parent = model
	model.WorldPivot = CFrame.new()
	return model
end

-- Builds the model for `name` (a gun or melee name). The returned model's pivot is the grip.
-- `skin` "gold" (Pacote do Sobrevivente) turns the metal parts gold; wood stays wood.
function WeaponModels.build(name: string, skin: string?): Model?
	local fromMeshes = buildFromMeshes(name, skin)
	if fromMeshes then
		return fromMeshes
	end
	local def = MODELS[name]
	if not def then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	local function part(partName: string, size: Vector3, cframe: CFrame): Part
		local piece = Instance.new("Part")
		piece.Name = partName
		piece.Size = size
		piece.CFrame = cframe
		piece.Anchored = false
		piece.Massless = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		piece.Parent = model
		return piece
	end
	for i, piece in def.pieces do
		local rotation = piece.rotation or Vector3.zero
		local built = part(
			"Piece" .. i,
			piece.size,
			CFrame.new(piece.offset)
				* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
		)
		local metal = piece.color == METAL or piece.color == STEEL
		if skin == "gold" and metal then
			built.Color = GOLD
			built.Material = Enum.Material.Foil
		else
			built.Color = piece.color
			built.Material = piece.material or Enum.Material.SmoothPlastic
		end
	end
	local muzzle = part("Muzzle", Vector3.new(0.1, 0.1, 0.1), CFrame.new(def.muzzle))
	muzzle.Transparency = 1
	model.WorldPivot = CFrame.new()
	return model
end

return WeaponModels
