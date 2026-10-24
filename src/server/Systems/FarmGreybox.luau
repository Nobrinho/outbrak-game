--!strict
-- Greybox of map 1, "Fazenda Abandonada" (docs/DEFINICOES.md §3b). Built from code so the
-- layout lives in git; gameplay systems locate points of interest only through Tags, so the
-- final art can replace this module without code changes.
--
-- Layout (studs, +Z = south): fort is a 120x120 fenced yard centered on the origin with the
-- farmhouse (west) and barn (east); the gate faces south; the west side is the stone corral
-- wall and the silo sits in the NE corner (both ClimbZones). Corn ring fills 80–220 studs out,
-- leaving a cleared lane north to the extraction field.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Tags = require(game:GetService("ReplicatedStorage").Shared.Tags)

local FarmGreybox = {}

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
	onGround("Yard", Vector3.new(FORT_HALF * 2, 0.2, FORT_HALF * 2), 0, 0, {
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

	part("Roof", Vector3.new(w + 4, 1, d + 4), CFrame.new(cx, h + 0.5, cz), {
		color = COLOR.woodDark,
		material = Enum.Material.Slate,
	}, house)

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
	part("Roof", Vector3.new(w + 4, 1, d + 4), CFrame.new(cx, h + 0.5, cz), {
		color = COLOR.woodDark,
		material = Enum.Material.Slate,
	}, barn)

	local shop = onGround("ShopCrate", Vector3.new(6, 4, 4), cx + 8, cz, {
		color = COLOR.interactive,
		material = Enum.Material.WoodPlanks,
	}, barn)
	tag(shop, Tags.ShopBox)
	prompt(shop, "Abrir loja", "Suprimentos")

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

	-- Turret slots: covering the gate, the corral wall and the silo corner.
	for i, pos in { Vector3.new(0, 0, 45), Vector3.new(-45, 0, 30), Vector3.new(40, 0, -40) } do
		local slot = onGround("TurretSlot" .. i, Vector3.new(6, 0.4, 6), pos.X, pos.Z, {
			color = COLOR.player,
			material = Enum.Material.Neon,
			transparency = 0.6,
			canCollide = false,
		}, yard)
		tag(slot, Tags.TurretSlot)
	end

	-- Broken windmill, used as a landmark for orientation.
	onGround(
		"WindmillTower",
		Vector3.new(4, 30, 4),
		-45,
		-45,
		{ color = COLOR.metal, material = Enum.Material.CorrodedMetal },
		yard
	)
	part(
		"WindmillBlades",
		Vector3.new(1, 14, 3),
		CFrame.new(-45, 29, -42.5) * CFrame.Angles(0, 0, math.rad(25)),
		{
			color = COLOR.metal,
			material = Enum.Material.CorrodedMetal,
		},
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

-- Corn ring: big non-colliding blocks that hide the horde (and distant LOD) until close.
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
				local height = 8 + (math.abs(x * 7 + z * 13) % 3)
				onGround("Corn", Vector3.new(cell - 2, height, cell - 2), x, z, {
					color = COLOR.corn,
					material = Enum.Material.Grass,
					canCollide = false,
				}, corn)
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

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.36
	atmosphere.Offset = 0.05
	atmosphere.Color = Color3.fromRGB(160, 105, 90)
	atmosphere.Decay = Color3.fromRGB(80, 55, 60)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Saturation = -0.2
	grade.Contrast = 0.12
	grade.TintColor = Color3.fromRGB(255, 236, 226)
	grade.Parent = Lighting

	-- Gentle glow on lamps and neon; Roblox drops post effects on low graphics levels.
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
end

function FarmGreybox.init()
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"

	buildGround()
	buildPerimeter()
	buildFarmhouse()
	buildBarn()
	buildYardProps()
	buildCornfield()
	buildExtraction()
	buildLights()
	buildLighting()

	mapFolder.Parent = workspace
end

return FarmGreybox
