--!strict
-- Map 1, "Fazenda Abandonada" (docs/DEFINICOES.md §3b), built from code so the layout lives
-- in git. Gameplay geometry (walls, barricades, fences, climb zones) defines the flow field;
-- the low-poly art pass (roofs, silo, windmill, corn rows, props) sits on top of it and is
-- mostly non-colliding so it never changes how the horde moves. Gameplay systems find points
-- of interest only through Tags.
--
-- Layout (studs, +Z = south): fort is a 120x120 fenced yard centered on the origin with the
-- farmhouse (west) and barn (east); the gate faces south; the west side is the stone corral
-- wall and the silo sits in the NE corner (both ClimbZones). Corn ring fills 80–220 studs out,
-- leaving a cleared lane north to the extraction field.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Tags = require(game:GetService("ReplicatedStorage").Shared.Tags)
local KitModels = require(game:GetService("ReplicatedStorage").Shared.Art.KitModels)
local FarmVisuals = require(game:GetService("ReplicatedStorage").Shared.Art.FarmVisuals)

local FarmMap = {}

-- Art direction palette: desaturated world, saturated gameplay signals.
local COLOR = {
	ground = Color3.fromRGB(122, 108, 84),
	dirt = Color3.fromRGB(96, 82, 64),
	wood = Color3.fromRGB(104, 92, 80),
	woodDark = Color3.fromRGB(74, 64, 58),
	stone = Color3.fromRGB(118, 118, 122),
	metal = Color3.fromRGB(130, 136, 142),
	corn = Color3.fromRGB(156, 138, 82),
	interactive = Color3.fromRGB(255, 204, 0),
	danger = Color3.fromRGB(220, 40, 40),
	player = Color3.fromRGB(0, 200, 230),
}
local ART = {
	roof = Color3.fromRGB(62, 58, 60),
	barnRed = Color3.fromRGB(122, 50, 40),
	trim = Color3.fromRGB(196, 188, 170),
	brick = Color3.fromRGB(120, 66, 52),
	glass = Color3.fromRGB(30, 36, 42),
	rust = Color3.fromRGB(124, 72, 44),
	tire = Color3.fromRGB(28, 28, 30),
	bark = Color3.fromRGB(64, 54, 48),
	rock = Color3.fromRGB(104, 102, 98),
	blood = Color3.fromRGB(60, 12, 12),
	cornShades = {
		Color3.fromRGB(156, 138, 82),
		Color3.fromRGB(140, 124, 70),
		Color3.fromRGB(170, 150, 92),
	},
}
local WARM = Color3.fromRGB(255, 190, 120)
local FIRE = Color3.fromRGB(255, 130, 50)

local FORT_HALF = 60
local FENCE_HEIGHT = 4.5 -- fence posts and gate; rails between them let bullets through
-- Height zombies must pile up to before climbing over the corral fence or onto the silo.
local CLIMB_HEIGHT = 9
local GATE_WIDTH = 16

type PartProps = {
	color: Color3?,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	canCollide: boolean?,
}

local mapFolder: Folder

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	props: PartProps?,
	parent: Instance?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = if props and props.color then props.color else COLOR.wood
	p.Material = if props and props.material then props.material else Enum.Material.SmoothPlastic
	if props and props.shape then
		p.Shape = props.shape
	end
	if props and props.transparency then
		p.Transparency = props.transparency
	end
	if props and props.canCollide ~= nil then
		p.CanCollide = props.canCollide
		-- Decorative non-colliding parts (corn, markers) must not stop bullets or line of sight.
		p.CanQuery = props.canCollide
	end
	p.Parent = parent or mapFolder
	return p
end

-- Places a part resting on the ground (y = 0) at the given XZ.
local function onGround(
	name: string,
	size: Vector3,
	x: number,
	z: number,
	props: PartProps?,
	parent: Instance?
): Part
	return part(name, size, CFrame.new(x, size.Y / 2, z), props, parent)
end

-- Decorative part: never collides, never blocks bullets or the flow-field probe.
local function deco(
	name: string,
	size: Vector3,
	cframe: CFrame,
	props: PartProps?,
	parent: Instance?
): Part
	local p = part(name, size, cframe, props, parent)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- A wedge's slope runs from the top of its +Z face down to the bottom of its -Z face.
local function wedge(
	name: string,
	size: Vector3,
	cframe: CFrame,
	props: PartProps?,
	parent: Instance?
): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.Size = size
	w.CFrame = cframe
	w.Color = if props and props.color then props.color else COLOR.wood
	w.Material = if props and props.material then props.material else Enum.Material.SmoothPlastic
	w.Parent = parent or mapFolder
	return w
end

-- Decorative bar between two points (legs, braces, wires).
local function bar(
	name: string,
	from: Vector3,
	to: Vector3,
	thickness: number,
	props: PartProps?,
	parent: Instance?
): Part
	local length = (to - from).Magnitude
	return deco(
		name,
		Vector3.new(thickness, thickness, length),
		CFrame.lookAt((from + to) / 2, to),
		props,
		parent
	)
end

-- Gable roof over a w (X) by d (Z) box whose walls end at height h; ridge runs along X.
-- Also fills both triangular gable ends with wedges in the wall colour.
local function gableRoof(
	name: string,
	cx: number,
	cz: number,
	w: number,
	d: number,
	h: number,
	rise: number,
	roofProps: PartProps,
	gableProps: PartProps,
	parent: Instance
)
	local overhang = 1.5
	local half = d / 2 + overhang
	local slope = math.atan2(rise, half)
	local length = math.sqrt(half * half + rise * rise)
	for side = -1, 1, 2 do
		deco(
			name .. "Slope" .. (if side < 0 then "N" else "S"),
			Vector3.new(w + overhang * 2, 0.7, length),
			CFrame.new(cx, h + rise / 2, cz + side * half / 2) * CFrame.Angles(side * slope, 0, 0),
			roofProps,
			parent
		)
	end
	deco(
		name .. "Ridge",
		Vector3.new(w + overhang * 2, 0.6, 0.9),
		CFrame.new(cx, h + rise + 0.1, cz),
		roofProps,
		parent
	)
	for _, x in { cx - w / 2, cx + w / 2 } do
		for side = -1, 1, 2 do
			-- High (+Z) face toward the ridge.
			wedge(
				name .. "Gable",
				Vector3.new(0.9, rise, d / 2),
				CFrame.new(x, h + rise / 2, cz + side * d / 4)
					* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
				gableProps,
				parent
			)
		end
	end
end

local function folder(name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = mapFolder
	return f
end

local function tag(instance: Instance, tagName: string)
	CollectionService:AddTag(instance, tagName)
end

local function prompt(parent: BasePart, actionText: string, objectText: string)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = 0.5 -- hold to avoid accidental taps on mobile
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = parent
end

local function buildGround()
	onGround("Ground", Vector3.new(600, 1, 600), 0, 0, {
		color = COLOR.ground,
		material = Enum.Material.Grass,
	}).Position =
		Vector3.new(0, -0.5, 0)
	onGround("YardGround", Vector3.new(FORT_HALF * 2, 0.2, FORT_HALF * 2), 0, 0, {
		color = COLOR.dirt,
		material = Enum.Material.Ground,
	})
	onGround("NorthLane", Vector3.new(24, 0.2, 140), 0, -FORT_HALF - 70, {
		color = COLOR.dirt,
		material = Enum.Material.Ground,
	})
end

-- Wooden fence on N/E/S with a gate gap on the south side; west side is the stone corral wall.
-- Rail fence between two ground points: posts plus two thick rails. Rails are 1 stud thick
-- so the flow field's per-cell probe always catches them; they're tagged ShootThrough so
-- bullets and line of sight pass between them while zombies are still blocked.
local function fenceRun(name: string, from: Vector3, to: Vector3, parent: Instance)
	local fence: PartProps = { color = COLOR.wood, material = Enum.Material.WoodPlanks }
	local offset = to - from
	local length = offset.Magnitude
	local direction = offset / length
	local center = from + offset / 2

	for i, height in { 1.4, 3.6 } do
		local rail = part(
			name .. "Rail" .. i,
			Vector3.new(1, 0.6, length),
			CFrame.lookAt(
				center + Vector3.new(0, height, 0),
				center + Vector3.new(0, height, 0) + direction
			),
			fence,
			parent
		)
		tag(rail, Tags.ShootThrough)
	end

	local posts = math.max(1, math.floor(length / 8))
	for i = 0, posts do
		local p = from + direction * (length * i / posts)
		local post = onGround(name .. "Post" .. i, Vector3.new(1.2, FENCE_HEIGHT, 1.2), p.X, p.Z, {
			color = COLOR.woodDark,
			material = Enum.Material.Wood,
		}, parent)
		tag(post, Tags.ShootThrough)
	end
end

-- Rail fence on N/E/S with a gate gap on the south side; west side is the stone corral wall.
local function buildPerimeter()
	local perimeter = folder("Perimeter")
	local h = FORT_HALF
	local gate = GATE_WIDTH / 2

	fenceRun("FenceNorth", Vector3.new(-h, 0, -h), Vector3.new(h, 0, -h), perimeter)
	fenceRun("FenceEast", Vector3.new(h, 0, -h), Vector3.new(h, 0, h), perimeter)
	fenceRun("FenceSouthW", Vector3.new(-h, 0, h), Vector3.new(-gate, 0, h), perimeter)
	fenceRun("FenceSouthE", Vector3.new(gate, 0, h), Vector3.new(h, 0, h), perimeter)

	local length = FORT_HALF * 2
	-- Corral: tall chain-link fence. Zombies can't walk through it but pile up and climb it;
	-- players see and shoot through the mesh, so the pyramid is a target as it grows.
	local mesh = onGround("CorralFence", Vector3.new(1, CLIMB_HEIGHT, length), -FORT_HALF, 0, {
		color = COLOR.metal,
		material = Enum.Material.Metal,
		transparency = 0.55,
	}, perimeter)
	mesh:SetAttribute("ClimbHeight", CLIMB_HEIGHT)
	mesh:SetAttribute("Inside", Vector3.zero)
	tag(mesh, Tags.ClimbZone)
	tag(mesh, Tags.ShootThrough)
	for i = 0, 12 do
		local post = onGround(
			"CorralPost" .. i,
			Vector3.new(0.6, CLIMB_HEIGHT + 0.5, 0.6),
			-FORT_HALF,
			-FORT_HALF + i * 10,
			{ color = COLOR.woodDark, material = Enum.Material.Metal },
			perimeter
		)
		tag(post, Tags.ShootThrough)
	end

	local silo = part(
		"Silo",
		Vector3.new(30, 14, 14),
		CFrame.new(FORT_HALF - 4, 15, -FORT_HALF + 4) * CFrame.Angles(0, 0, math.rad(90)),
		{
			color = COLOR.metal,
			material = Enum.Material.CorrodedMetal,
			shape = Enum.PartType.Cylinder,
		},
		perimeter
	)
	-- Zombies pile against the silo up to the catwalk ring, then drop into the yard.
	silo:SetAttribute("ClimbHeight", CLIMB_HEIGHT)
	silo:SetAttribute("Inside", Vector3.zero)
	tag(silo, Tags.ClimbZone)
	part(
		"SiloCatwalk",
		Vector3.new(0.6, 19, 19),
		CFrame.new(FORT_HALF - 4, CLIMB_HEIGHT, -FORT_HALF + 4) * CFrame.Angles(0, 0, math.rad(90)),
		{
			color = COLOR.woodDark,
			material = Enum.Material.DiamondPlate,
			shape = Enum.PartType.Cylinder,
			canCollide = false,
		},
		perimeter
	)
	-- Dome cap, rusted hoops and a ladder on the yard side.
	local siloBase = Vector3.new(FORT_HALF - 4, 0, -FORT_HALF + 4)
	deco("SiloDome", Vector3.new(14.2, 14.2, 14.2), CFrame.new(siloBase + Vector3.new(0, 30, 0)), {
		color = ART.roof,
		material = Enum.Material.CorrodedMetal,
		shape = Enum.PartType.Ball,
	}, perimeter)
	for _, y in { 5, 13, 21, 28 } do
		deco(
			"SiloHoop",
			Vector3.new(0.6, 14.6, 14.6),
			CFrame.new(siloBase + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			{
				color = ART.rust,
				material = Enum.Material.CorrodedMetal,
				shape = Enum.PartType.Cylinder,
			},
			perimeter
		)
	end
	local ladderDir = Vector3.new(-1, 0, 1).Unit -- faces the yard
	local ladderRight = Vector3.new(ladderDir.Z, 0, -ladderDir.X)
	local ladderBase = siloBase + ladderDir * 7.4
	for side = -1, 1, 2 do
		bar(
			"LadderRail",
			ladderBase + ladderRight * side * 0.8,
			ladderBase + ladderRight * side * 0.8 + Vector3.new(0, 29, 0),
			0.25,
			{ color = ART.rust, material = Enum.Material.Metal },
			perimeter
		)
	end
	for y = 1, 28, 2 do
		bar(
			"LadderRung",
			ladderBase - ladderRight * 0.8 + Vector3.new(0, y, 0),
			ladderBase + ladderRight * 0.8 + Vector3.new(0, y, 0),
			0.2,
			{ color = ART.rust, material = Enum.Material.Metal },
			perimeter
		)
	end
end

local function barricade(name: string, size: Vector3, cframe: CFrame, parent: Instance)
	local b = part(name, size, cframe, {
		color = COLOR.interactive,
		material = Enum.Material.WoodPlanks,
	}, parent)
	tag(b, Tags.Barricade) -- health and repair: BarricadeService
	prompt(b, "Reparar", "Barricada")
end

-- Farmhouse: hollow box with a south door and two east-facing windows.
local function buildFarmhouse()
	local house = folder("Farmhouse")
	local cx, cz = -28, -10
	local w, h, d = 34, 14, 28
	local t = 1
	local wall: PartProps = { color = COLOR.woodDark, material = Enum.Material.WoodPlanks }

	onGround("WallNorth", Vector3.new(w, h, t), cx, cz - d / 2, wall, house)
	onGround("WallWest", Vector3.new(t, h, d), cx - w / 2, cz, wall, house)

	-- East wall with two window openings (3 solid pieces + sills/lintels).
	local ex = cx + w / 2
	local winW, winH, sill = 6, 5, 4
	onGround("WallEastN", Vector3.new(t, h, 5), ex, cz - d / 2 + 2.5, wall, house)
	onGround("WallEastMid", Vector3.new(t, h, d - 10 - winW * 2), ex, cz, wall, house)
	onGround("WallEastS", Vector3.new(t, h, 5), ex, cz + d / 2 - 2.5, wall, house)
	for i, wz in { cz - d / 2 + 5 + winW / 2, cz + d / 2 - 5 - winW / 2 } do
		onGround("Sill" .. i, Vector3.new(t, sill, winW), ex, wz, wall, house)
		part(
			"Lintel" .. i,
			Vector3.new(t, h - sill - winH, winW),
			CFrame.new(ex, sill + winH + (h - sill - winH) / 2, wz),
			wall,
			house
		)
		barricade(
			"WindowBarricade" .. i,
			Vector3.new(0.6, winH, winW),
			CFrame.new(ex + 0.8, sill + winH / 2, wz),
			house
		)
	end

	-- South wall with a door opening.
	local doorW, doorH = 6, 9
	local sideW = (w - doorW) / 2
	local sz = cz + d / 2
	onGround("WallSouthW", Vector3.new(sideW, h, t), cx - doorW / 2 - sideW / 2, sz, wall, house)
	onGround("WallSouthE", Vector3.new(sideW, h, t), cx + doorW / 2 + sideW / 2, sz, wall, house)
	part(
		"DoorLintel",
		Vector3.new(doorW, h - doorH, t),
		CFrame.new(cx, doorH + (h - doorH) / 2, sz),
		wall,
		house
	)
	barricade(
		"DoorBarricade",
		Vector3.new(doorW, doorH, 0.6),
		CFrame.new(cx, doorH / 2, sz + 0.8),
		house
	)

	-- Ceiling keeps the inside dark under the roof; the gable roof is decoration on top.
	part("Ceiling", Vector3.new(w, 0.6, d), CFrame.new(cx, h + 0.3, cz), wall, house)
	gableRoof(
		"Roof",
		cx,
		cz,
		w,
		d,
		h + 0.6,
		7,
		{ color = ART.roof, material = Enum.Material.Slate },
		wall,
		house
	)
	deco("Chimney", Vector3.new(2.6, 9, 2.6), CFrame.new(cx + 9, h + 6, cz - 4), {
		color = ART.brick,
		material = Enum.Material.Brick,
	}, house)

	-- Porch: a lean-to roof on posts over the door.
	local porchZ = sz + 3.5
	deco(
		"PorchRoof",
		Vector3.new(18, 0.5, 7.5),
		CFrame.new(cx, 9.8, porchZ) * CFrame.Angles(math.rad(-10), 0, 0),
		{
			color = ART.roof,
			material = Enum.Material.Slate,
		},
		house
	)
	deco("PorchFloor", Vector3.new(18, 0.4, 7), CFrame.new(cx, 0.2, porchZ), {
		color = COLOR.wood,
		material = Enum.Material.WoodPlanks,
	}, house)
	for _, px in { cx - 8.5, cx + 8.5 } do
		deco("PorchPost", Vector3.new(0.6, 9.4, 0.6), CFrame.new(px, 4.7, sz + 6.8), {
			color = ART.trim,
		}, house)
	end

	-- Dark windows on the outer walls and pale trim around every opening.
	local glass: PartProps = { color = ART.glass, material = Enum.Material.Glass }
	local trim: PartProps = { color = ART.trim }
	for i, wx in { cx - 9, cx + 9 } do
		deco(
			"WindowN" .. i,
			Vector3.new(5, 4.5, 0.2),
			CFrame.new(wx, 7, cz - d / 2 - 0.6),
			glass,
			house
		)
		deco(
			"WindowNTrim" .. i,
			Vector3.new(5.8, 0.4, 0.3),
			CFrame.new(wx, 4.6, cz - d / 2 - 0.65),
			trim,
			house
		)
	end
	for i, wz in { cz - 6, cz + 6 } do
		deco(
			"WindowW" .. i,
			Vector3.new(0.2, 4.5, 5),
			CFrame.new(cx - w / 2 - 0.6, 7, wz),
			glass,
			house
		)
	end
	deco(
		"DoorTrim",
		Vector3.new(doorW + 1, 0.5, 0.3),
		CFrame.new(cx, doorH + 0.25, sz + 0.65),
		trim,
		house
	)
	for i, wz in { cz - d / 2 + 5 + winW / 2, cz + d / 2 - 5 - winW / 2 } do
		deco(
			"WindowTrimTop" .. i,
			Vector3.new(0.3, 0.4, winW + 0.8),
			CFrame.new(ex + 0.65, sill + winH + 0.2, wz),
			trim,
			house
		)
		deco(
			"WindowTrimSill" .. i,
			Vector3.new(0.5, 0.3, winW + 0.8),
			CFrame.new(ex + 0.7, sill - 0.15, wz),
			trim,
			house
		)
	end

	-- Ammo on the porch (south of the door).
	local ammo = onGround("AmmoBox", Vector3.new(4, 2, 2.5), cx + 8, sz + 5, {
		color = COLOR.interactive,
	}, house)
	tag(ammo, Tags.AmmoBox)
	prompt(ammo, "Pegar munição", "Munição")
end

-- Barn: open-front shell (west-facing) holding the shop crate.
local function buildBarn()
	local barn = folder("Barn")
	local cx, cz = 30, 12
	local w, h, d = 30, 20, 40
	local t = 1
	local wall: PartProps =
		{ color = Color3.fromRGB(112, 58, 48), material = Enum.Material.WoodPlanks }

	onGround("WallNorth", Vector3.new(w, h, t), cx, cz - d / 2, wall, barn)
	onGround("WallSouth", Vector3.new(w, h, t), cx, cz + d / 2, wall, barn)
	onGround("WallEast", Vector3.new(t, h, d), cx + w / 2, cz, wall, barn)
	-- West face: two short stubs leave a wide doorway toward the yard.
	onGround("WallWestN", Vector3.new(t, h, 8), cx - w / 2, cz - d / 2 + 4, wall, barn)
	onGround("WallWestS", Vector3.new(t, h, 8), cx - w / 2, cz + d / 2 - 4, wall, barn)
	part("Ceiling", Vector3.new(w, 0.6, d), CFrame.new(cx, h + 0.3, cz), wall, barn)
	-- Ridge along X, so the open west face is the gable end, like a classic barn front.
	gableRoof(
		"Roof",
		cx,
		cz,
		w,
		d,
		h + 0.6,
		12,
		{ color = ART.roof, material = Enum.Material.CorrodedMetal },
		wall,
		barn
	)
	-- White trim: corner boards and a frame around the big doorway, hayloft door above it.
	local trim: PartProps = { color = ART.trim }
	for _, corner in
		{ Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(1, 1) }
	do
		deco(
			"CornerTrim",
			Vector3.new(1.2, h, 1.2),
			CFrame.new(cx + corner.X * w / 2, h / 2, cz + corner.Y * d / 2),
			trim,
			barn
		)
	end
	local doorX = cx - w / 2 - 0.6
	deco("DoorHeader", Vector3.new(0.5, 1, d - 16), CFrame.new(doorX, h - 2, cz), trim, barn)
	deco(
		"Hayloft",
		Vector3.new(0.4, 5, 6),
		CFrame.new(doorX, h + 3.5, cz),
		{ color = ART.barnRed },
		barn
	)
	bar(
		"HayloftX1",
		Vector3.new(doorX - 0.3, h + 1.2, cz - 2.8),
		Vector3.new(doorX - 0.3, h + 5.8, cz + 2.8),
		0.4,
		trim,
		barn
	)
	bar(
		"HayloftX2",
		Vector3.new(doorX - 0.3, h + 1.2, cz + 2.8),
		Vector3.new(doorX - 0.3, h + 5.8, cz - 2.8),
		0.4,
		trim,
		barn
	)

	local shop = onGround("ShopCrate", Vector3.new(6, 4, 4), cx + 8, cz, {
		color = COLOR.interactive,
		material = Enum.Material.WoodPlanks,
	}, barn)
	tag(shop, Tags.ShopBox)
	prompt(shop, "Abrir loja", "Suprimentos")
	-- Visual-only supply display: prompt and original shop collision stay authoritative.
	KitModels.clone("Medkit", shop.CFrame * CFrame.new(-1.5, shop.Size.Y / 2, 0), barn)
	KitModels.clone("Grenade", shop.CFrame * CFrame.new(1.5, shop.Size.Y / 2, 0), barn)

	-- Hay bales as cover inside.
	for i, offset in { Vector2.new(-4, -12), Vector2.new(2, 12), Vector2.new(-6, 8) } do
		onGround("Hay" .. i, Vector3.new(5, 3, 3), cx + offset.X, cz + offset.Y, {
			color = COLOR.corn,
			material = Enum.Material.Fabric,
		}, barn)
	end
end

local function buildYardProps()
	local yard = folder("Yard")

	-- Gate barricade spanning the south gap.
	barricade(
		"GateBarricade",
		Vector3.new(GATE_WIDTH, FENCE_HEIGHT, 1),
		CFrame.new(0, FENCE_HEIGHT / 2, FORT_HALF),
		yard
	)

	-- Turret slots: covering the gate, the corral fence (from the corridor beside the house,
	-- in reach of piles along its whole north half) and the silo corner.
	for i, pos in { Vector3.new(0, 0, 45), Vector3.new(-52, 0, -10), Vector3.new(40, 0, -40) } do
		local slot = onGround("TurretSlot" .. i, Vector3.new(6, 0.4, 6), pos.X, pos.Z, {
			color = COLOR.player,
			material = Enum.Material.Neon,
			transparency = 0.6,
			canCollide = false,
		}, yard)
		tag(slot, Tags.TurretSlot)
	end

	-- Broken windmill, a landmark for orientation: lattice tower, platform, a wheel with
	-- missing blades and a bent tail vane. Decorative only.
	local millBase = Vector3.new(-45, 0, -45)
	local metal: PartProps = { color = COLOR.metal, material = Enum.Material.CorrodedMetal }
	local top = 28
	local corners =
		{ Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) }
	local function legAt(corner: Vector2, y: number): Vector3
		local spread = 2.6 - (2.6 - 0.7) * y / top
		return millBase + Vector3.new(corner.X * spread, y, corner.Y * spread)
	end
	for i, corner in corners do
		bar("MillLeg" .. i, legAt(corner, 0), legAt(corner, top), 0.4, metal, yard)
		for _, y in { 7, 14, 21 } do
			local nextCorner = corners[i % 4 + 1]
			bar("MillBrace", legAt(corner, y), legAt(nextCorner, y), 0.25, metal, yard)
			bar("MillCross", legAt(corner, y - 7), legAt(nextCorner, y), 0.2, metal, yard)
		end
	end
	deco(
		"MillPlatform",
		Vector3.new(3, 0.4, 3),
		CFrame.new(millBase + Vector3.new(0, top, 0)),
		metal,
		yard
	)
	local hub = millBase + Vector3.new(0, top + 1.5, -1.6)
	deco("MillHub", Vector3.new(1.2, 1.2, 1.2), CFrame.new(hub), metal, yard)
	for blade = 0, 7 do
		if blade ~= 2 and blade ~= 5 then -- two blades long gone
			local angle = math.rad(blade * 45 + 10)
			local tip = hub + Vector3.new(math.cos(angle) * 6, math.sin(angle) * 6, 0)
			bar(
				"MillBlade",
				hub,
				tip,
				0.5,
				{ color = ART.trim, material = Enum.Material.Metal },
				yard
			)
		end
	end
	bar("MillTailBoom", hub, hub + Vector3.new(0.6, -0.4, 5), 0.3, metal, yard)
	deco(
		"MillVane",
		Vector3.new(0.2, 2.5, 3),
		CFrame.new(hub + Vector3.new(0.6, -0.2, 5.5))
			* CFrame.Angles(0, math.rad(15), math.rad(-12)),
		metal,
		yard
	)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, 0.5, 20)
	spawn.Color = COLOR.player
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 3 -- brief spawn protection (ForceField)
	spawn.Parent = yard
end

-- Corn ring: rows of non-colliding blocks that hide the horde (and distant LOD) until close.
local function buildCornfield()
	local corn = folder("Cornfield")
	local inner, outer = 80, 220
	local cell = 28
	local laneHalf = 18 -- cleared lane north to extraction

	for x = -outer, outer, cell do
		for z = -outer, outer, cell do
			local dist = math.max(math.abs(x), math.abs(z))
			local inLane = math.abs(x) < laneHalf + cell / 2 and z < 0
			if dist >= inner and dist <= outer and not inLane then
				-- Four thick rows per cell: reads as planted corn, still hides the horde.
				for row = 0, 3 do
					local seed = math.abs(x * 7 + z * 13 + row * 5)
					local height = 7.5 + (seed % 7) * 0.4
					local rz = z - cell / 2 + 3.5 + row * 7
					onGround("Corn", Vector3.new(cell - 1, height, 3.8), x, rz, {
						color = ART.cornShades[seed % #ART.cornShades + 1],
						material = Enum.Material.Grass,
						canCollide = false,
					}, corn)
				end
			end
		end
	end

	-- Spawn points sit inside the corn, all around except the north lane.
	local spawns = folder("ZombieSpawns")
	for i = 1, 8 do
		local angle = math.rad(45 * i + 22.5)
		local p = onGround(
			"ZombieSpawn" .. i,
			Vector3.new(4, 1, 4),
			math.sin(angle) * 150,
			math.cos(angle) * 150,
			{
				color = COLOR.danger,
				transparency = 1,
				canCollide = false,
			},
			spawns
		)
		tag(p, Tags.ZombieSpawn)
	end
end

-- Props: tell the story of the farm and give cover. Pieces players can hide behind collide
-- (they become blocked cells in the flow field, like any wall); the rest is decoration.
local function buildDressing()
	local props = folder("Props")
	local solid = function(name: string, size: Vector3, cframe: CFrame, p: PartProps)
		return part(name, size, cframe, p, props)
	end

	-- Rusted tractor north of the barn.
	local tractor = CFrame.new(18, 0, -38) * CFrame.Angles(0, math.rad(20), 0)
	local rust: PartProps = { color = ART.rust, material = Enum.Material.CorrodedMetal }
	local tire: PartProps =
		{ color = ART.tire, material = Enum.Material.Rubber, shape = Enum.PartType.Cylinder }
	solid("TractorBody", Vector3.new(3.4, 2.6, 7), tractor * CFrame.new(0, 2.6, 0), rust)
	deco("TractorHood", Vector3.new(2.8, 1.6, 3.4), tractor * CFrame.new(0, 4.6, -1.8), rust, props)
	deco(
		"TractorStack",
		Vector3.new(0.4, 2.4, 0.4),
		tractor * CFrame.new(0.8, 6.4, -2.4),
		rust,
		props
	)
	deco("TractorSeat", Vector3.new(1.4, 0.8, 1.2), tractor * CFrame.new(0, 4.3, 2), rust, props)
	for _, side in { -1, 1 } do
		solid(
			"TractorWheelBig",
			Vector3.new(1.4, 5, 5),
			tractor * CFrame.new(side * 2.4, 2.5, 2),
			tire
		)
		deco(
			"TractorWheelSmall",
			Vector3.new(1, 2.6, 2.6),
			tractor * CFrame.new(side * 2, 1.3, -2.6),
			tire,
			props
		)
	end

	-- Abandoned pickup outside the gate, nose in the dirt.
	local truck = CFrame.new(-28, 0, 70) * CFrame.Angles(0, math.rad(-35), math.rad(4))
	local paint: PartProps =
		{ color = Color3.fromRGB(70, 88, 96), material = Enum.Material.CorrodedMetal }
	solid("TruckBody", Vector3.new(5, 2.4, 12), truck * CFrame.new(0, 2.2, 0), paint)
	deco("TruckCab", Vector3.new(4.8, 2.4, 4), truck * CFrame.new(0, 4.6, -1), paint, props)
	deco("TruckWindshield", Vector3.new(4.4, 1.8, 0.2), truck * CFrame.new(0, 4.8, -3.05), {
		color = ART.glass,
		material = Enum.Material.Glass,
	}, props)
	for _, wheel in
		{
			Vector2.new(-2.5, -3.6),
			Vector2.new(2.5, -3.6),
			Vector2.new(-2.5, 3.6),
			Vector2.new(2.5, 3.6),
		}
	do
		deco(
			"TruckWheel",
			Vector3.new(0.9, 2.4, 2.4),
			truck * CFrame.new(wheel.X, 1.1, wheel.Y),
			tire,
			props
		)
	end

	-- Crate stacks (cover) by the barn and near the gate.
	local crate: PartProps = { color = COLOR.wood, material = Enum.Material.WoodPlanks }
	for _, c in
		{
			CFrame.new(25, 1.5, -12),
			CFrame.new(28.5, 1.5, -12.5) * CFrame.Angles(0, math.rad(12), 0),
			CFrame.new(26.5, 4.5, -12.2) * CFrame.Angles(0, math.rad(-8), 0),
			CFrame.new(-20, 1.5, 50),
			CFrame.new(-16.5, 1.5, 51) * CFrame.Angles(0, math.rad(25), 0),
		}
	do
		solid("Crate", Vector3.new(3, 3, 3), c, crate)
	end

	-- Oil drums behind the barn, one knocked over.
	local drum: PartProps = {
		color = Color3.fromRGB(70, 84, 64),
		material = Enum.Material.CorrodedMetal,
		shape = Enum.PartType.Cylinder,
	}
	for i, c in
		{
			CFrame.new(39, 1.6, 38) * CFrame.Angles(0, 0, math.rad(90)),
			CFrame.new(41.5, 1.6, 37) * CFrame.Angles(0, 0, math.rad(90)),
			CFrame.new(40, 1.1, 41) * CFrame.Angles(0, math.rad(30), 0),
		}
	do
		solid("Drum" .. i, Vector3.new(3.2, 2.2, 2.2), c, drum)
	end

	-- Hay bales by the barn door, a water trough along the corral fence, a wheelbarrow.
	local hay: PartProps = { color = COLOR.corn, material = Enum.Material.Fabric }
	solid("HayBale", Vector3.new(4, 2.5, 2.5), CFrame.new(9, 1.25, 28), hay)
	solid(
		"HayBale",
		Vector3.new(4, 2.5, 2.5),
		CFrame.new(9.5, 3.75, 28.3) * CFrame.Angles(0, math.rad(8), 0),
		hay
	)
	solid(
		"Trough",
		Vector3.new(2.4, 2, 7),
		CFrame.new(-54, 1, 30),
		{ color = COLOR.wood, material = Enum.Material.WoodPlanks }
	)
	deco("TroughWater", Vector3.new(1.8, 0.2, 6.4), CFrame.new(-54, 1.9, 30), {
		color = Color3.fromRGB(46, 58, 50),
		material = Enum.Material.Glass,
	}, props)
	local barrow = CFrame.new(-8, 0, -30) * CFrame.Angles(0, math.rad(40), 0)
	deco("BarrowTub", Vector3.new(2.4, 1.2, 3), barrow * CFrame.new(0, 1.6, 0), rust, props)
	deco("BarrowWheel", Vector3.new(0.4, 1.4, 1.4), barrow * CFrame.new(0, 0.7, -1.9), tire, props)
	bar(
		"BarrowHandleL",
		barrow * Vector3.new(-0.9, 1.6, 1.2),
		barrow * Vector3.new(-1.1, 1.2, 3.2),
		0.2,
		crate,
		props
	)
	bar(
		"BarrowHandleR",
		barrow * Vector3.new(0.9, 1.6, 1.2),
		barrow * Vector3.new(1.1, 1.2, 3.2),
		0.2,
		crate,
		props
	)

	-- Dead trees between the fence and the corn.
	local barkProps: PartProps = { color = ART.bark, material = Enum.Material.Wood }
	for i, base in
		{
			Vector3.new(70, 0, 25),
			Vector3.new(-72, 0, -30),
			Vector3.new(35, 0, 72),
			Vector3.new(-70, 0, 62),
		}
	do
		local height = 12 + (i % 3) * 3
		solid(
			"TreeTrunk",
			Vector3.new(1.4, height, 1.4),
			CFrame.new(base + Vector3.new(0, height / 2, 0)),
			barkProps
		)
		for b = 1, 4 do
			local angle = math.rad(b * 97 + i * 31)
			local from = base + Vector3.new(0, height * (0.45 + b * 0.12), 0)
			local to = from + Vector3.new(math.cos(angle) * 4, 2.5 + b * 0.4, math.sin(angle) * 4)
			bar("TreeBranch", from, to, 0.5, barkProps, props)
			bar(
				"TreeTwig",
				to,
				to + Vector3.new(math.cos(angle + 0.8) * 1.6, 1.4, math.sin(angle + 0.8) * 1.6),
				0.25,
				barkProps,
				props
			)
		end
	end

	-- Scarecrow at the edge of the corn, watching the road.
	local crow = Vector3.new(36, 0, 82)
	bar("ScarecrowPole", crow, crow + Vector3.new(0, 8, 0), 0.4, barkProps, props)
	bar(
		"ScarecrowArms",
		crow + Vector3.new(-2.5, 5.8, 0),
		crow + Vector3.new(2.5, 5.8, 0),
		0.3,
		barkProps,
		props
	)
	deco("ScarecrowCoat", Vector3.new(2.2, 2.6, 1), CFrame.new(crow + Vector3.new(0, 5, 0)), {
		color = Color3.fromRGB(70, 60, 84),
		material = Enum.Material.Fabric,
	}, props)
	deco("ScarecrowHead", Vector3.new(1.3, 1.3, 1.3), CFrame.new(crow + Vector3.new(0, 7, 0)), {
		color = Color3.fromRGB(180, 160, 110),
		material = Enum.Material.Fabric,
		shape = Enum.PartType.Ball,
	}, props)
	deco(
		"ScarecrowHat",
		Vector3.new(2.2, 0.3, 2.2),
		CFrame.new(crow + Vector3.new(0, 7.7, 0)),
		barkProps,
		props
	)

	-- Gate arch with the farm's name.
	for _, x in { -9.8, 9.8 } do
		deco(
			"ArchPost",
			Vector3.new(0.9, 11.5, 0.9),
			CFrame.new(x, 5.75, FORT_HALF + 1.5),
			barkProps,
			props
		)
	end
	local board =
		deco("ArchSign", Vector3.new(16, 2.2, 0.4), CFrame.new(0, 10.2, FORT_HALF + 1.5), {
			color = COLOR.wood,
			material = Enum.Material.WoodPlanks,
		}, props)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "FAZENDA SANTA LUZIA"
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = ART.trim
		label.Parent = gui
		gui.Parent = board
	end

	-- Worn dirt paths from the gate to the porch and the barn, and old bloodstains.
	local dirt: PartProps = { color = Color3.fromRGB(84, 70, 54), material = Enum.Material.Ground }
	bar("PathToPorch", Vector3.new(0, 0.22, 58), Vector3.new(-26, 0.22, 12), 5, dirt, props).Size =
		Vector3.new(5, 0.05, 55)
	bar("PathToBarn", Vector3.new(0, 0.22, 58), Vector3.new(13, 0.22, 14), 5, dirt, props).Size =
		Vector3.new(5, 0.05, 46)
	local bloodProps: PartProps = {
		color = ART.blood,
		material = Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
	}
	for _, spot in
		{
			Vector3.new(3, 0, 52),
			Vector3.new(-24, 0, 9),
			Vector3.new(-50, 0, 12),
			Vector3.new(22, 0, 40),
		}
	do
		deco(
			"Bloodstain",
			Vector3.new(0.1, 3.5, 2.6),
			CFrame.new(spot + Vector3.new(0, 0.23, 0))
				* CFrame.Angles(0, math.rad(spot.X * 13), math.rad(90)),
			bloodProps,
			props
		)
	end

	-- Rock clusters out in the field.
	local rockProps: PartProps = { color = ART.rock, material = Enum.Material.Slate }
	for i, base in
		{
			Vector3.new(75, 0, -5),
			Vector3.new(-66, 0, -72),
			Vector3.new(68, 0, 68),
			Vector3.new(-40, 0, 72),
		}
	do
		for r = 0, 2 do
			local size = 2.5 - r * 0.6
			solid(
				"Rock",
				Vector3.new(size * 1.4, size, size * 1.2),
				CFrame.new(base + Vector3.new(r * 1.8, size / 2 - 0.2, (r % 2) * 1.5))
					* CFrame.Angles(math.rad(i * 9 + r * 20), math.rad(i * 33 + r * 50), 0),
				rockProps
			)
		end
	end

	-- Power poles down the north lane, wires sagging between them.
	local poles = {}
	for i, z in { -78, -112, -146 } do
		local foot = Vector3.new(15, 0, z)
		bar("Pole" .. i, foot, foot + Vector3.new(0, 16, 0), 0.7, barkProps, props)
		bar(
			"PoleArm" .. i,
			foot + Vector3.new(-2.5, 15, 0),
			foot + Vector3.new(2.5, 15, 0),
			0.4,
			barkProps,
			props
		)
		table.insert(poles, foot + Vector3.new(0, 15.3, 0))
	end
	for i = 1, #poles - 1 do
		for _, dx in { -2.2, 2.2 } do
			local a, b = poles[i] + Vector3.new(dx, 0, 0), poles[i + 1] + Vector3.new(dx, 0, 0)
			local sag = (a + b) / 2 - Vector3.new(0, 1.6, 0)
			bar("Wire", a, sag, 0.08, { color = ART.tire }, props)
			bar("Wire", sag, b, 0.08, { color = ART.tire }, props)
		end
	end
end

local function buildExtraction()
	local zone = onGround("ExtractionZone", Vector3.new(50, 0.4, 50), 0, -FORT_HALF - 120, {
		color = COLOR.player,
		material = Enum.Material.Neon,
		transparency = 0.7,
		canCollide = false,
	})
	tag(zone, Tags.Extraction)
end

-- Light sources: warm practical lights the players defend around, a red beacon on the silo
-- and a flare at the extraction field. Shadows stay off on every light (mobile budget).
type LightMode = "steady" | "fire" | "blink"

local function lamp(
	name: string,
	position: Vector3,
	color: Color3,
	range: number,
	brightness: number,
	mode: LightMode,
	parent: Instance
): Part
	local bulb = part(name, Vector3.new(0.8, 0.8, 0.8), CFrame.new(position), {
		color = color,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		canCollide = false,
	}, parent)
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = bulb
	if mode ~= "steady" then
		-- The client animates these (AmbienceController); the server only sets the baseline.
		bulb:SetAttribute("LightMode", mode)
		bulb:SetAttribute("BaseBrightness", brightness)
		tag(bulb, Tags.Flicker)
	end
	return bulb
end

local function lampPost(name: string, x: number, z: number, parent: Instance)
	local height = 10
	onGround(name, Vector3.new(0.6, height, 0.6), x, z, {
		color = COLOR.woodDark,
		material = Enum.Material.Wood,
	}, parent)
	part(name .. "Arm", Vector3.new(0.4, 0.4, 2), CFrame.new(x, height - 0.2, z - 0.8), {
		color = COLOR.woodDark,
		material = Enum.Material.Wood,
	}, parent)
	lamp(name .. "Bulb", Vector3.new(x, height - 0.9, z - 1.6), WARM, 26, 1.6, "steady", parent)
end

local function fireBarrel(name: string, x: number, z: number, parent: Instance)
	local barrel = onGround(name, Vector3.new(2.4, 3, 2.4), x, z, {
		color = COLOR.metal,
		material = Enum.Material.CorrodedMetal,
	}, parent)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(120, 30, 10)
	fire.Parent = barrel
	lamp(name .. "Glow", Vector3.new(x, 4.5, z), FIRE, 22, 2.4, "fire", parent).Transparency = 1
end

local function buildLights()
	local lights = folder("Lights")

	-- Porch lamp over the farmhouse door (south wall, door at x = -28, wall at z = 4).
	lamp("PorchLamp", Vector3.new(-28, 10.5, 5), WARM, 22, 1.8, "fire", lights)
	-- Barn: lantern over the shop crate and one at the open west doorway.
	lamp("BarnLantern", Vector3.new(38, 12, 12), WARM, 24, 2, "steady", lights)
	lamp("BarnDoorLamp", Vector3.new(14, 12, -4), WARM, 20, 1.5, "steady", lights)

	lampPost("GateLampW", -12, 54, lights)
	lampPost("GateLampE", 12, 54, lights)
	lampPost("NorthLamp", 0, -50, lights)
	lampPost("WestLamp", -50, 45, lights)

	fireBarrel("FireBarrelYard", 12, 38, lights)
	fireBarrel("FireBarrelNorth", -30, -40, lights)

	lamp(
		"SiloBeacon",
		Vector3.new(FORT_HALF - 4, 31, -FORT_HALF + 4),
		COLOR.danger,
		30,
		3,
		"blink",
		lights
	)
	lamp(
		"ExtractionFlare",
		Vector3.new(0, 1, -FORT_HALF - 120),
		COLOR.danger,
		40,
		4,
		"fire",
		lights
	)
end

-- One effect of each class: reuses whatever the place file already holds (a saved place can
-- carry copies from earlier sessions) and removes the extras, so effects never stack.
local function lightingEffect(className: string): Instance
	local found: Instance? = nil
	for _, child in Lighting:GetChildren() do
		if child.ClassName == className then
			if found then
				child:Destroy()
			else
				found = child
			end
		end
	end
	if found then
		return found
	end
	local created = Instance.new(className)
	created.Parent = Lighting
	return created
end

-- Apocalyptic dusk: the sun is just down, so the practical lights read clearly; red-grey haze
-- hides the far corn. No rain (particles cost).
local function buildLighting()
	Lighting.ClockTime = 18.4
	Lighting.Brightness = 1.1
	Lighting.ExposureCompensation = 0.15
	Lighting.Ambient = Color3.fromRGB(78, 66, 66)
	Lighting.OutdoorAmbient = Color3.fromRGB(105, 88, 88)
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.2

	local atmosphere = lightingEffect("Atmosphere") :: Atmosphere
	atmosphere.Density = 0.36
	atmosphere.Offset = 0.05
	atmosphere.Color = Color3.fromRGB(160, 105, 90)
	atmosphere.Decay = Color3.fromRGB(80, 55, 60)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.6

	local grade = lightingEffect("ColorCorrectionEffect") :: ColorCorrectionEffect
	grade.Saturation = -0.2
	grade.Contrast = 0.12
	grade.TintColor = Color3.fromRGB(255, 236, 226)

	-- Gentle glow on lamps and neon; Roblox drops post effects on low graphics levels.
	local bloom = lightingEffect("BloomEffect") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6
end

function FarmMap.init()
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"

	buildGround()
	buildPerimeter()
	buildFarmhouse()
	buildBarn()
	buildYardProps()
	buildCornfield()
	buildDressing()
	buildExtraction()
	buildLights()
	buildLighting()
	FarmVisuals.apply(mapFolder)

	mapFolder.Parent = workspace
end

return FarmMap
