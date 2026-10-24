--!strict
-- Low-poly weapon models held in the player's right hand. Each is a handful of parts in
-- model space with the grip at the origin and the barrel pointing -Z; a "Muzzle" part marks
-- where tracers start. No textures: dark metal, worn wood, a little steel.

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

-- Builds the model for `name` (a gun or melee name). The returned model's pivot is the grip.
function WeaponModels.build(name: string): Model?
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
		built.Color = piece.color
		built.Material = piece.material or Enum.Material.SmoothPlastic
	end
	local muzzle = part("Muzzle", Vector3.new(0.1, 0.1, 0.1), CFrame.new(def.muzzle))
	muzzle.Transparency = 1
	model.WorldPivot = CFrame.new()
	return model
end

return WeaponModels
