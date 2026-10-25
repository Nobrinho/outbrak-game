--!strict
-- The survivors' camp (hub place): where everyone arrives and hangs out between matches.
-- Built at server start like FarmMap, never saved in the place. Sandbag walls, tents, a
-- campfire and floodlights at dusk; along the north edge one helipad per map in
-- Config.MAPS, each with a helicopter, a sign and an invisible zone PortalService watches.
--
-- Layout (studs, y up): camp centred on the origin, spawn just south of the fire, helipads at
-- z = PAD_Z spread along x.

local Lighting = game:GetService("Lighting")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local HubMap = {}

local PAD_Z = -34
local PAD_SPACING = 30
local PAD_RADIUS = 9

local COLOR = {
	ground = Color3.fromRGB(96, 82, 64),
	sand = Color3.fromRGB(150, 132, 96),
	canvas = Color3.fromRGB(86, 96, 66),
	canvasDark = Color3.fromRGB(64, 72, 50),
	wood = Color3.fromRGB(104, 92, 80),
	metal = Color3.fromRGB(70, 74, 72),
	pad = Color3.fromRGB(52, 54, 56),
	marking = Color3.fromRGB(255, 204, 0),
	heli = Color3.fromRGB(70, 80, 60),
	fire = Color3.fromRGB(255, 140, 50),
	player = Color3.fromRGB(0, 200, 230),
}

local root: Folder

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	parent: Instance?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent or root
	return p
end

local function deco(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function folder(name: string, parent: Instance?): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or root
	return f
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function buildGround()
	part(
		"Ground",
		Vector3.new(260, 2, 260),
		CFrame.new(0, -1, 0),
		COLOR.ground,
		Enum.Material.Ground
	)
	-- Packed sand where people walk: around the fire and the path to the helipads.
	deco(
		part(
			"Yard",
			Vector3.new(70, 0.1, 60),
			CFrame.new(0, 0.05, -8),
			COLOR.sand,
			Enum.Material.Sand
		)
	)
end

-- A low wall of stacked sandbags from `a` to `b`, waist high, with a gap left by the caller.
local function sandbagWall(a: Vector3, b: Vector3, parent: Instance)
	local offset = b - a
	local length = offset.Magnitude
	local count = math.max(1, math.floor(length / 2.2))
	local step = offset / count
	local cf = CFrame.lookAt(a, b)
	for i = 0, count - 1 do
		for row = 0, 1 do
			local at = a + step * (i + 0.5 + row * 0.5)
			part(
				"Sandbag",
				Vector3.new(1.4, 0.9, 2.2),
				CFrame.new(at.X, 0.45 + row * 0.85, at.Z) * cf.Rotation,
				COLOR.sand,
				Enum.Material.Fabric,
				parent
			)
		end
	end
end

local function buildWalls()
	local walls = folder("Walls")
	local half = 48
	-- South, east and west sides closed; the north side opens onto the helipads.
	sandbagWall(Vector3.new(-half, 0, half), Vector3.new(half, 0, half), walls)
	sandbagWall(Vector3.new(-half, 0, -half), Vector3.new(-half, 0, half), walls)
	sandbagWall(Vector3.new(half, 0, -half), Vector3.new(half, 0, half), walls)
	sandbagWall(Vector3.new(-half, 0, -14), Vector3.new(-22, 0, -14), walls)
	sandbagWall(Vector3.new(22, 0, -14), Vector3.new(half, 0, -14), walls)
	-- Chain-link fence behind the helipads, the edge of the camp.
	for x = -half, half, 8 do
		part(
			"FencePost",
			Vector3.new(0.4, 7, 0.4),
			CFrame.new(x, 3.5, -half - 14),
			COLOR.metal,
			Enum.Material.Metal,
			walls
		)
	end
	local mesh = part(
		"Fence",
		Vector3.new(half * 2, 6, 0.1),
		CFrame.new(0, 3.5, -half - 14),
		COLOR.metal,
		Enum.Material.DiamondPlate,
		walls
	)
	mesh.Transparency = 0.55
end

local function tent(x: number, z: number, yaw: number, parent: Instance)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
	for _, side in { -1, 1 } do
		local panel = part(
			"TentPanel",
			Vector3.new(0.2, 4.8, 8),
			base * CFrame.new(side * 1.7, 2, 0) * CFrame.Angles(0, 0, math.rad(side * 35)),
			COLOR.canvas,
			Enum.Material.Fabric,
			parent
		)
		panel.CastShadow = true
	end
	part(
		"TentBack",
		Vector3.new(5.4, 3.8, 0.2),
		base * CFrame.new(0, 1.9, 3.9),
		COLOR.canvasDark,
		Enum.Material.Fabric,
		parent
	)
	part(
		"TentRidge",
		Vector3.new(0.3, 0.3, 8.4),
		base * CFrame.new(0, 4.05, 0),
		COLOR.wood,
		Enum.Material.Wood,
		parent
	)
end

local function buildCamp()
	local camp = folder("Camp")
	for i, spot in
		{
			{ -30, 4, 90 },
			{ -30, 18, 90 },
			{ 30, 4, -90 },
			{ 30, 18, -90 },
			{ -14, 34, 0 },
			{ 14, 34, 0 },
		}
	do
		tent(spot[1], spot[2], spot[3], camp)
		if i % 2 == 0 then
			part(
				"Crate",
				Vector3.new(3, 3, 3),
				CFrame.new(spot[1] + 5, 1.5, spot[2] + 3),
				COLOR.wood,
				Enum.Material.WoodPlanks,
				camp
			)
		end
	end

	-- Campfire in the middle: stones, logs, flames and a warm flickering light.
	local fire = folder("Campfire", camp)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		part(
			"FireStone",
			Vector3.new(1, 0.7, 1),
			CFrame.new(math.cos(a) * 2.2, 0.35, 8 + math.sin(a) * 2.2),
			Color3.fromRGB(104, 102, 98),
			Enum.Material.Slate,
			fire
		)
	end
	for _, yaw in { 0, 60, 120 } do
		part(
			"Log",
			Vector3.new(0.6, 0.6, 3.2),
			CFrame.new(0, 0.5, 8) * CFrame.Angles(0, math.rad(yaw), 0),
			COLOR.wood,
			Enum.Material.Wood,
			fire
		)
	end
	local flame = deco(
		part(
			"Flame",
			Vector3.new(1.2, 1.6, 1.2),
			CFrame.new(0, 1.4, 8),
			COLOR.fire,
			Enum.Material.Neon,
			fire
		)
	)
	flame.Shape = Enum.PartType.Ball
	flame.Transparency = 0.25
	light(flame, COLOR.fire, 30, 3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(COLOR.fire, Color3.fromRGB(80, 30, 20))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(1.4, 0)
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Rate = 18
	emitter.Speed = NumberRange.new(3, 5)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Parent = flame
	for _, spot in { { -5, 8, 90 }, { 5, 8, 90 }, { 0, 13, 0 } } do
		part(
			"Bench",
			Vector3.new(4, 0.8, 1.2),
			CFrame.new(spot[1], 0.4, spot[2]) * CFrame.Angles(0, math.rad(spot[3]), 0),
			COLOR.wood,
			Enum.Material.Wood,
			fire
		)
	end

	-- Floodlights on poles at the corners of the yard.
	for _, spot in { { -40, 40 }, { 40, 40 }, { -40, -10 }, { 40, -10 } } do
		local x, z = spot[1], spot[2]
		part(
			"LightPole",
			Vector3.new(0.6, 12, 0.6),
			CFrame.new(x, 6, z),
			COLOR.metal,
			Enum.Material.Metal,
			camp
		)
		local head = deco(
			part(
				"Floodlight",
				Vector3.new(2, 1.2, 1),
				CFrame.lookAt(Vector3.new(x, 12, z), Vector3.new(0, 0, 0)),
				Color3.fromRGB(255, 240, 200),
				Enum.Material.Neon,
				camp
			)
		)
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Angle = 70
		beam.Range = 45
		beam.Brightness = 2
		beam.Color = Color3.fromRGB(255, 236, 200)
		beam.Parent = head
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, 0.5, 22)
	spawn.Color = COLOR.player
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = camp
end

-- Greybox helicopter parked behind a pad (same proportions as the extraction helicopter).
local function helicopter(at: CFrame, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Helicopter"
	local body = part(
		"Body",
		Vector3.new(8, 6, 18),
		at * CFrame.new(0, 4, 0),
		COLOR.heli,
		Enum.Material.Metal,
		model
	)
	part(
		"Cockpit",
		Vector3.new(6.5, 3.5, 5),
		at * CFrame.new(0, 4.6, 8.4),
		Color3.fromRGB(30, 36, 42),
		Enum.Material.Glass,
		model
	)
	part(
		"Rotor",
		Vector3.new(30, 0.3, 1.5),
		at * CFrame.new(0, 7.5, 0),
		Color3.fromRGB(30, 30, 30),
		Enum.Material.Metal,
		model
	)
	part(
		"Rotor2",
		Vector3.new(1.5, 0.3, 30),
		at * CFrame.new(0, 7.5, 0),
		Color3.fromRGB(30, 30, 30),
		Enum.Material.Metal,
		model
	)
	part(
		"Tail",
		Vector3.new(1.5, 1.5, 12),
		at * CFrame.new(0, 5, -14),
		COLOR.heli,
		Enum.Material.Metal,
		model
	)
	for _, side in { -1, 1 } do
		part(
			"Skid",
			Vector3.new(0.4, 0.4, 16),
			at * CFrame.new(side * 3.5, 0.6, 0),
			COLOR.metal,
			Enum.Material.Metal,
			model
		)
	end
	model.PrimaryPart = body
	model.Parent = parent
end

-- A helipad with its zone, sign and helicopter. Attributes on the zone tell PortalService
-- which map it leads to.
local function helipad(info: Config.MapInfo, x: number, parent: Instance)
	local pad = folder(info.id, parent)
	local center = CFrame.new(x, 0, PAD_Z)
	local disc = part(
		"Pad",
		Vector3.new(0.4, PAD_RADIUS * 2, PAD_RADIUS * 2),
		center * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		COLOR.pad,
		Enum.Material.Concrete,
		pad
	)
	disc.Shape = Enum.PartType.Cylinder
	local active = info.placeId >= 0
	local mark = if active then COLOR.marking else Color3.fromRGB(110, 110, 110)
	-- The "H" marking.
	for _, side in { -1, 1 } do
		deco(
			part(
				"H",
				Vector3.new(1, 0.05, 7),
				center * CFrame.new(side * 2.2, 0.42, 0),
				mark,
				Enum.Material.SmoothPlastic,
				pad
			)
		)
	end
	deco(
		part(
			"H",
			Vector3.new(4.4, 0.05, 1),
			center * CFrame.new(0, 0.42, 0),
			mark,
			Enum.Material.SmoothPlastic,
			pad
		)
	)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		deco(
			part(
				"Ring",
				Vector3.new(1.2, 0.05, 2.6),
				center * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0.42, PAD_RADIUS - 0.9),
				mark,
				Enum.Material.SmoothPlastic,
				pad
			)
		)
	end

	helicopter(center * CFrame.new(0, 0, -PAD_RADIUS - 8) * CFrame.Angles(0, math.rad(90), 0), pad)

	-- What PortalService watches: standing inside this box queues you for the map.
	local zone = deco(
		part(
			"Zone",
			Vector3.new(PAD_RADIUS * 2, 8, PAD_RADIUS * 2),
			center * CFrame.new(0, 4, 0),
			COLOR.marking,
			nil,
			pad
		)
	)
	zone.Transparency = 1
	zone:SetAttribute("MapId", info.id)

	-- Billboard on two posts at the back of the pad, above the helicopter, facing the camp:
	-- readable from the fire, never in the way up close. A lamp under it lights the pad.
	for _, side in { -1, 1 } do
		part(
			"SignPost",
			Vector3.new(0.5, 15, 0.5),
			center * CFrame.new(side * 7.5, 7.5, -PAD_RADIUS - 1.5),
			COLOR.metal,
			Enum.Material.Metal,
			pad
		)
	end
	local board = part(
		"Sign",
		Vector3.new(17, 4.6, 0.3),
		center * CFrame.new(0, 13, -PAD_RADIUS - 1.5),
		Color3.fromRGB(28, 30, 32),
		Enum.Material.Metal,
		pad
	)
	local lamp = deco(
		part(
			"PadLamp",
			Vector3.new(6, 0.3, 0.6),
			center * CFrame.new(0, 10.4, -PAD_RADIUS - 1.2),
			Color3.fromRGB(255, 240, 210),
			Enum.Material.Neon,
			pad
		)
	)
	light(lamp, Color3.fromRGB(255, 236, 210), 28, 2.5)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Back -- +Z: towards the camp
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = board
	local function label(name: string, y: number, h: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.04, y)
		l.Size = UDim2.fromScale(0.92, h)
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = color
		l.Parent = gui
		return l
	end
	label("Title", 0.08, 0.46, if active then COLOR.marking else Color3.fromRGB(180, 180, 180)).Text =
		info.name
	label("Status", 0.58, 0.32, Color3.fromRGB(240, 240, 240)).Text = ""
end

local function buildHelipads()
	local portals = folder("Portals")
	local count = #Config.MAPS
	for i, info in Config.MAPS do
		helipad(info, (i - (count + 1) / 2) * PAD_SPACING, portals)
	end
end

-- One lighting effect of each class (a saved place may carry copies), dusk like the farm.
local function effect(className: string): Instance
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

local function buildLighting()
	Lighting.ClockTime = 17.3
	Lighting.Brightness = 1.2
	Lighting.ExposureCompensation = 0.2
	Lighting.Ambient = Color3.fromRGB(96, 84, 82)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 120, 112)
	local atmosphere = effect("Atmosphere") :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.05
	atmosphere.Color = Color3.fromRGB(160, 105, 90)
	atmosphere.Decay = Color3.fromRGB(80, 55, 60)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.4
	local grade = effect("ColorCorrectionEffect") :: ColorCorrectionEffect
	grade.Saturation = -0.15
	grade.Contrast = 0.1
	grade.TintColor = Color3.fromRGB(255, 236, 226)
	local bloom = effect("BloomEffect") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6
end

function HubMap.init()
	root = Instance.new("Folder")
	root.Name = "Hub"
	buildGround()
	buildWalls()
	buildCamp()
	buildHelipads()
	buildLighting()
	root.Parent = workspace
end

return HubMap
