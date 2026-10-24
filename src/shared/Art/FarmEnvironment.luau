--!strict
-- Visual dressing for the existing farm: no terrain edits, tags, collision or queries.
-- Geometry stays below eye level in the yard; distant silhouettes sit outside combat.
local FarmEnvironment = {}

local MUD = Color3.fromRGB(64, 55, 45)
local WET = Color3.fromRGB(38, 47, 53)
local BARK = Color3.fromRGB(58, 45, 34)
local GRASS = {
	Color3.fromRGB(105, 100, 49),
	Color3.fromRGB(126, 112, 58),
	Color3.fromRGB(77, 83, 43),
	Color3.fromRGB(147, 125, 67),
}
local STONE = {
	Color3.fromRGB(89, 88, 81),
	Color3.fromRGB(103, 99, 85),
	Color3.fromRGB(70, 76, 77),
}

local function piece(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	wedge: boolean?
): BasePart
	local p: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = size.Y > 1.5
	p.Parent = parent
	return p
end

local function branch(parent: Instance, a: Vector3, b: Vector3, thickness: number)
	piece(
		parent,
		"DeadBranch",
		Vector3.new(thickness, thickness * 0.85, (b - a).Magnitude),
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, 0, math.rad(15)),
		BARK,
		Enum.Material.Wood
	)
end

local function tuft(parent: Instance, rng: Random, position: Vector3, height: number)
	for blade = 1, 3 do
		local h = height * rng:NextNumber(0.65, 1)
		piece(
			parent,
			"DryGrass",
			Vector3.new(0.12, h, rng:NextNumber(0.6, 1.1)),
			CFrame.new(
				position + Vector3.new(rng:NextNumber(-0.4, 0.4), h / 2, rng:NextNumber(-0.4, 0.4))
			)
				* CFrame.Angles(
					0,
					math.rad(blade * 115 + rng:NextNumber(-25, 25)),
					math.rad(rng:NextNumber(-15, 15))
				),
			GRASS[rng:NextInteger(1, #GRASS)],
			Enum.Material.SmoothPlastic,
			true
		)
	end
end

local function road(parent: Instance, rng: Random, from: Vector3, to: Vector3, width: number)
	local delta = to - from
	local direction = delta.Unit
	local right = Vector3.new(-direction.Z, 0, direction.X)
	local steps = 14
	for i = 0, steps - 1 do
		local t = (i + 0.5) / steps
		local center = from:Lerp(to, t) + right * math.sin(t * math.pi * 3) * 0.6
		local length = delta.Magnitude / steps + 0.7
		piece(
			parent,
			"WornMud",
			Vector3.new(width + rng:NextNumber(-1, 1.6), 0.045, length),
			CFrame.lookAt(
				center + Vector3.new(0, 0.275, 0),
				center + direction + Vector3.new(0, 0.275, 0)
			),
			MUD:Lerp(Color3.fromRGB(83, 70, 51), rng:NextNumber(0, 0.45)),
			Enum.Material.Mud
		)
		-- Sparse puddles follow the wheel ruts, with jagged mud edges between them.
		if i % 2 == 0 then
			local p = center + right * rng:NextNumber(-width * 0.28, width * 0.28)
			local puddle = piece(
				parent,
				"RainPuddle",
				Vector3.new(rng:NextNumber(1.2, 2.3), 0.035, rng:NextNumber(2.2, 4.1)),
				CFrame.lookAt(p + Vector3.new(0, 0.32, 0), p + direction + Vector3.new(0, 0.32, 0))
					* CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0),
				WET,
				Enum.Material.Glass
			)
			puddle.Transparency = 0.12
			puddle.Reflectance = 0.16
			puddle.CastShadow = false
		end
		for side = -1, 1, 2 do
			local edge = center + right * side * (width / 2 + rng:NextNumber(0.6, 2.5))
			tuft(parent, rng, edge + Vector3.new(0, 0.2, 0), rng:NextNumber(0.75, 1.3))
		end
	end
	for _ = 1, 28 do
		local p = from:Lerp(to, rng:NextNumber(0.03, 0.97))
			+ right * rng:NextNumber(-width * 0.65, width * 0.65)
		local h = rng:NextNumber(0.12, 0.3)
		piece(
			parent,
			"RoadStone",
			Vector3.new(rng:NextNumber(0.6, 1.5), h, rng:NextNumber(0.5, 1.4)),
			CFrame.new(p + Vector3.new(0, 0.33 + h / 2, 0))
				* CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), rng:NextNumber(0, math.pi), 0),
			STONE[rng:NextInteger(1, #STONE)],
			Enum.Material.Slate,
			true
		)
	end
end

local function deadTree(parent: Instance, rng: Random, base: Vector3, height: number)
	local lean = Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
	local lower = base + Vector3.new(0, height * 0.45, 0)
	local upper = base + lean + Vector3.new(0, height * 0.8, 0)
	local top = base + lean * 1.4 + Vector3.new(0, height + 2, 0)
	branch(parent, base, lower, 1.8)
	branch(parent, lower, upper, 1.25)
	branch(parent, upper, top, 0.8)
	for i = 1, 6 do
		local angle = i * 2.35 + rng:NextNumber(-0.3, 0.3)
		local from = base + Vector3.new(0, height * (0.33 + i * 0.075), 0) + lean * 0.4
		local reach = rng:NextNumber(3, 5.5)
		local elbow = from
			+ Vector3.new(math.cos(angle) * reach * 0.7, reach * 0.4, math.sin(angle) * reach * 0.7)
		local tip = elbow
			+ Vector3.new(
				math.cos(angle + 0.35) * reach * 0.5,
				reach * 0.65,
				math.sin(angle + 0.35) * reach * 0.5
			)
		branch(parent, from, elbow, 0.65)
		branch(parent, elbow, tip, 0.32)
	end
end

local function conifer(parent: Instance, base: Vector3, height: number, yaw: number)
	piece(
		parent,
		"PineTrunk",
		Vector3.new(1, height * 0.6, 1),
		CFrame.new(base + Vector3.new(0, height * 0.3, 0)),
		BARK,
		Enum.Material.Wood
	)
	for tier = 1, 3 do
		local width = height * (0.44 - tier * 0.075)
		local h = height * 0.42
		local y = height * (0.16 + tier * 0.2)
		local color = Color3.fromRGB(34 + tier * 4, 48 + tier * 5, 43 + tier * 5)
		for side = -1, 1, 2 do
			piece(
				parent,
				"PineCrown",
				Vector3.new(width, h, width / 2),
				CFrame.new(base + Vector3.new(0, y, 0))
					* CFrame.Angles(0, yaw, 0)
					* CFrame.new(0, 0, side * width / 4)
					* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
				color,
				Enum.Material.SmoothPlastic,
				true
			)
		end
	end
end

local function weedCluster(parent: Instance, rng: Random, base: Vector3)
	-- Wide leaves overlap into one low silhouette instead of isolated tiny flecks.
	local rotation = rng:NextNumber(0, math.pi * 2)
	for leaf = 1, 6 do
		local angle = rotation + leaf * math.pi / 3
		local length = rng:NextNumber(1.9, 2.8)
		local offset = Vector3.new(math.sin(angle), 0, math.cos(angle)) * length * 0.25
		piece(
			parent,
			"BroadleafWeed",
			Vector3.new(rng:NextNumber(0.8, 1.2), 0.35, length),
			CFrame.new(base + offset + Vector3.new(0, 0.45, 0))
				* CFrame.Angles(math.rad(12), angle, math.rad(rng:NextNumber(-8, 8))),
			GRASS[rng:NextInteger(1, #GRASS)],
			Enum.Material.SmoothPlastic,
			true
		)
	end
	for stem = 1, 3 do
		local angle = rotation + stem * 2.1
		tuft(parent, rng, base + Vector3.new(math.sin(angle), 0, math.cos(angle)) * 1.3, 1.15)
	end
end

local function ridge(
	parent: Instance,
	base: Vector3,
	angle: number,
	width: number,
	depth: number,
	height: number,
	color: Color3
)
	-- The triangular end faces the farm: local X follows the radial direction.
	-- Each wedge's high edge meets at local Z=0, producing a pointed peak.
	for side = -1, 1, 2 do
		piece(
			parent,
			"DistantRidge",
			Vector3.new(depth, height, width / 2),
			CFrame.new(base + Vector3.new(0, height / 2 - 3, 0))
				* CFrame.Angles(0, -angle, 0)
				* CFrame.new(0, 0, side * width / 4)
				* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			color,
			Enum.Material.Slate,
			true
		)
	end
end

function FarmEnvironment.build(parent: Instance)
	local rng = Random.new(24102026)
	road(parent, rng, Vector3.new(0, 0, 58), Vector3.new(-26, 0, 12), 6)
	road(parent, rng, Vector3.new(0, 0, 58), Vector3.new(13, 0, 14), 7.5)
	task.wait()

	-- Weeds along existing fences and building foundations, away from the gateways.
	for i = 1, 124 do
		local side = i % 4
		local p: Vector3
		if side == 0 then
			p = Vector3.new(rng:NextNumber(-55, -14), 0.2, rng:NextNumber(52, 58))
		elseif side == 1 then
			p = Vector3.new(rng:NextNumber(18, 55), 0.2, rng:NextNumber(52, 58))
		elseif side == 2 then
			p = Vector3.new(rng:NextNumber(-56, -48), 0.2, rng:NextNumber(-48, 45))
		else
			p = Vector3.new(rng:NextNumber(49, 57), 0.2, rng:NextNumber(-42, 45))
		end
		tuft(parent, rng, p, rng:NextNumber(0.85, 1.3))
	end
	for _, base in
		{
			Vector3.new(-43, 0.2, 7),
			Vector3.new(-48, 0.2, 54),
			Vector3.new(-36, 0.2, 55),
			Vector3.new(-23, 0.2, 54),
			Vector3.new(24, 0.2, 55),
			Vector3.new(38, 0.2, 54),
			Vector3.new(50, 0.2, 54),
			Vector3.new(-55, 0.2, -38),
			Vector3.new(-55, 0.2, 8),
			Vector3.new(-55, 0.2, 38),
			Vector3.new(54, 0.2, -30),
			Vector3.new(54, 0.2, 0),
			Vector3.new(54, 0.2, 25),
			Vector3.new(-40, 0.2, -28),
			Vector3.new(-28, 0.2, -28),
			Vector3.new(-16, 0.2, -28),
			Vector3.new(49, 0.2, -4),
			Vector3.new(49, 0.2, 14),
			Vector3.new(24, 0.2, 36),
			Vector3.new(38, 0.2, 36),
		}
	do
		weedCluster(parent, rng, base)
	end
	task.wait()

	for i, base in
		{
			Vector3.new(70, 0, 25),
			Vector3.new(-72, 0, -30),
			Vector3.new(35, 0, 72),
			Vector3.new(-70, 0, 62),
		}
	do
		deadTree(parent, rng, base, 12 + (i % 3) * 3)
	end
	-- A broken skyline outside the 240-stud navigation grid.
	for i = 0, 31 do
		local angle = i * math.pi * 2 / 32 + 0.06
		local radius = rng:NextNumber(250, 282)
		conifer(
			parent,
			Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius),
			rng:NextNumber(20, 34),
			angle
		)
	end
	task.wait()
	for i = 0, 13 do
		local angle = math.pi * (0.85 + i / 13 * 1.3)
		local radius = rng:NextNumber(275, 288)
		local h = rng:NextNumber(25, 45)
		local w = rng:NextNumber(38, 64)
		local base = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local color = Color3.fromRGB(55 + i % 3 * 8, 67 + i % 3 * 7, 79 + i % 3 * 7)
		ridge(parent, base, angle, w, rng:NextNumber(25, 35), h, color)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local secondaryBase = base
			+ tangent * w * rng:NextNumber(0.35, 0.5)
			+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(3, 8)
		ridge(
			parent,
			secondaryBase,
			angle + 0.08,
			w * 0.65,
			25,
			h * rng:NextNumber(0.55, 0.8),
			color:Lerp(Color3.fromRGB(40, 50, 64), 0.2)
		)
	end
end

return FarmEnvironment
