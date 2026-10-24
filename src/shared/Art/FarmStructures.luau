--!strict
-- Visual skins over the original farm. Every new part is excluded from physics and raycasts.
local Structures = {}
local WOOD = Color3.fromRGB(108, 94, 77)
local TRIM = Color3.fromRGB(147, 133, 106)
local DARK = Color3.fromRGB(43, 38, 34)
local ROOF = Color3.fromRGB(43, 53, 61)
local RED = Color3.fromRGB(113, 44, 31)
local RUST = Color3.fromRGB(106, 55, 32)
local WARM = Color3.fromRGB(255, 151, 60)

-- `meshed` names the props FarmProps already drew from Blender meshes; their part-built
-- details are skipped.
function Structures.build(map: Instance, parent: Instance, meshed: { [string]: boolean }?)
	local meshedProps = meshed or {}
	local rng = Random.new(241026)
	local count = 0
	local function group(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
		return f
	end
	local function tint(c: Color3, amount: number): Color3
		local n = rng:NextNumber(-amount, amount)
		return Color3.new(
			math.clamp(c.R + n, 0, 1),
			math.clamp(c.G + n, 0, 1),
			math.clamp(c.B + n, 0, 1)
		)
	end
	local function piece(
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		folder: Instance,
		class: string?
	): BasePart
		local p = Instance.new(class or "Part") :: BasePart
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = folder
		count += 1
		return p
	end
	local function beam(
		name: string,
		a: Vector3,
		b: Vector3,
		width: number,
		color: Color3,
		folder: Instance
	)
		return piece(
			name,
			Vector3.new(width, width, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b),
			color,
			folder
		)
	end
	local function hideDecor(folder: Instance, prefixes: { string })
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") and not p.CanCollide and not p.CanQuery and #p:GetTags() == 0 then
				for _, prefix in prefixes do
					if string.sub(p.Name, 1, #prefix) == prefix then
						p.Transparency = 1
						p.CastShadow = false
						break
					end
				end
			end
		end
	end
	local function light(holder: BasePart, range: number, brightness: number)
		local l = Instance.new("PointLight")
		l.Color = WARM
		l.Range = range
		l.Brightness = brightness
		l.Shadows = false
		l.Parent = holder
	end
	-- A shallow window on an already solid wall, never across a gameplay opening.
	local function window(cf: CFrame, width: number, height: number, folder: Instance)
		piece("WindowRecess", Vector3.new(width + 0.6, height + 0.6, 0.18), cf, DARK, folder)
		local glass = piece(
			"WarmWindow",
			Vector3.new(width, height, 0.12),
			cf * CFrame.new(0, 0, 0.12),
			WARM,
			folder
		)
		glass.Material = Enum.Material.Neon
		light(glass, 14, 0.65)
		for _, x in { -width / 2, 0, width / 2 } do
			piece(
				"WindowMullion",
				Vector3.new(0.24, height + 0.4, 0.32),
				cf * CFrame.new(x, 0, 0.25),
				DARK,
				folder
			)
		end
		for _, y in { -height / 2, 0, height / 2 } do
			piece(
				"WindowRail",
				Vector3.new(width + 0.4, 0.24, 0.32),
				cf * CFrame.new(0, y, 0.25),
				TRIM,
				folder
			)
		end
		piece(
			"WindowSill",
			Vector3.new(width + 1, 0.35, 0.8),
			cf * CFrame.new(0, -height / 2 - 0.2, 0.1),
			WOOD,
			folder
		)
	end
	local function siding(original: Instance, center: Vector3, barn: boolean, dest: Instance)
		for _, wall in original:GetChildren() do
			if
				wall:IsA("BasePart")
				and (
					wall.Name:match("^Wall")
					or wall.Name:match("^Sill")
					or wall.Name:match("^Lintel")
					or wall.Name == "DoorLintel"
				)
			then
				local alongX = wall.Size.X > wall.Size.Z
				local length = if alongX then wall.Size.X else wall.Size.Z
				local axis = if alongX then Vector3.xAxis else Vector3.zAxis
				local normal = if alongX
					then Vector3.new(0, 0, if wall.Position.Z > center.Z then 1 else -1)
					else Vector3.new(if wall.Position.X > center.X then 1 else -1, 0, 0)
				local origin = wall.Position + normal * 0.63
				if barn then
					local columns = math.ceil(length / 1.55)
					for i = 1, columns do
						local width = length / columns - 0.09
						local pos = origin + axis * (-length / 2 + (i - 0.5) * length / columns)
						local size = if alongX
							then Vector3.new(width, wall.Size.Y - 0.1, 0.2)
							else Vector3.new(0.2, wall.Size.Y - 0.1, width)
						piece("BarnBoard", size, CFrame.new(pos), tint(RED, 0.055), dest)
					end
				else
					local rows = math.ceil(wall.Size.Y / 1.05)
					local cols = math.max(1, math.ceil(length / 8))
					for row = 1, rows do
						for col = 1, cols do
							local pos = origin
								+ axis * (-length / 2 + (col - 0.5) * length / cols)
								+ Vector3.new(
									0,
									-wall.Size.Y / 2 + (row - 0.5) * wall.Size.Y / rows,
									0
								)
							local size = if alongX
								then Vector3.new(
									length / cols - 0.07,
									wall.Size.Y / rows - 0.07,
									0.22
								)
								else Vector3.new(
									0.22,
									wall.Size.Y / rows - 0.07,
									length / cols - 0.07
								)
							piece(
								"WeatheredClapboard",
								size,
								CFrame.new(pos),
								tint(WOOD, 0.065),
								dest
							)
						end
					end
				end
			end
		end
	end
	local function roof(
		cx: number,
		cz: number,
		width: number,
		depth: number,
		height: number,
		rise: number,
		wallColor: Color3,
		dest: Instance
	)
		local half = depth / 2 + 1.7
		local angle = math.atan2(rise, half)
		local slopeLength = math.sqrt(half * half + rise * rise)
		local cols = math.ceil((width + 3.4) / 2.7)
		local rows = math.ceil(slopeLength / 3.0)
		for _, side in { -1, 1 } do
			for row = 1, rows do
				for col = 1, cols do
					-- Broken shingles expose battens, with intact silhouette at the ridge.
					if row == 1 or rng:NextNumber() > 0.16 then
						local t = (row - 0.5) * slopeLength / rows
						local pos = Vector3.new(
							cx - (width + 3.4) / 2 + (col - 0.5) * (width + 3.4) / cols,
							height + rise - t * math.sin(angle),
							cz + side * t * math.cos(angle)
						)
						piece(
							"BrokenShingle",
							Vector3.new(
								(width + 3.4) / cols - 0.07,
								0.21,
								slopeLength / rows + 0.16
							),
							CFrame.new(pos)
								* CFrame.Angles(side * angle, 0, rng:NextNumber(-0.022, 0.022)),
							tint(ROOF, 0.04),
							dest
						)
					end
				end
			end
			for x = cx - width / 2, cx + width / 2, 4.2 do
				beam(
					"RoofRafter",
					Vector3.new(x, height + rise - 0.2, cz),
					Vector3.new(x, height - 0.2, cz + side * half),
					0.3,
					WOOD,
					dest
				)
			end
			for row = 1, 3 do
				local t = slopeLength * row / 4
				piece(
					"RoofBatten",
					Vector3.new(width + 2, 0.2, 0.2),
					CFrame.new(
						cx,
						height + rise - t * math.sin(angle) - 0.2,
						cz + side * t * math.cos(angle)
					),
					DARK,
					dest
				)
			end
		end
		piece(
			"RidgeCap",
			Vector3.new(width + 3.8, 0.45, 0.65),
			CFrame.new(cx, height + rise + 0.05, cz),
			ROOF,
			dest
		)
		for _, x in { cx - width / 2, cx + width / 2 } do
			for _, side in { -1, 1 } do
				piece(
					"GableEnd",
					Vector3.new(0.3, rise, depth / 2),
					CFrame.new(x, height + rise / 2, cz + side * depth / 4)
						* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
					wallColor,
					dest,
					"WedgePart"
				)
				beam(
					"GableFascia",
					Vector3.new(x, height + rise + 0.2, cz),
					Vector3.new(x, height - 0.05, cz + side * half),
					0.55,
					TRIM,
					dest
				)
			end
			for z = -depth / 2 + 1, depth / 2 - 1, 1.8 do
				local h = rise * (1 - math.abs(z) / (depth / 2))
				piece(
					"GableBoard",
					Vector3.new(0.42, math.max(0.2, h), 1.68),
					CFrame.new(x, height + h / 2, cz + z),
					tint(wallColor, 0.04),
					dest
				)
			end
		end
	end
	local house = map:FindFirstChild("Farmhouse")
	local barn = map:FindFirstChild("Barn")
	assert(house and barn, "Existing farm buildings missing")
	local hf = group("FarmhouseSkin")
	hideDecor(house, { "Roof", "Chimney", "Porch", "WindowN", "WindowW" })
	siding(house, Vector3.new(-28, 0, -10), false, hf)
	roof(-28, -10, 34, 28, 14.6, 9, WOOD, hf)
	-- Two warm south windows sit on solid facade segments outside the door opening.
	window(CFrame.new(-38, 7, 4.72), 4.5, 5.4, hf)
	window(CFrame.new(-18, 7, 4.72), 4.5, 5.4, hf)
	window(CFrame.new(-10.65, 18.3, -10) * CFrame.Angles(0, math.pi / 2, 0), 3.5, 4, hf)
	window(CFrame.new(-45.67, 7, -10) * CFrame.Angles(0, -math.pi / 2, 0), 4.5, 5, hf)
	-- Broad porch with a clear central doorway and ammunition access on its east side.
	for x = -40, -16, 2 do
		piece(
			"PorchDeck",
			Vector3.new(1.9, 0.16, 7.2),
			CFrame.new(x, 0.16, 7.5),
			tint(WOOD, 0.06),
			hf
		)
	end
	for _, x in { -40, -34, -22, -16 } do
		piece("PorchPillar", Vector3.new(0.55, 9.3, 0.55), CFrame.new(x, 4.8, 10.8), TRIM, hf)
		beam(
			"PorchKneeBrace",
			Vector3.new(x, 7.5, 10.8),
			Vector3.new(x + 1.5, 9.2, 10.8),
			0.3,
			WOOD,
			hf
		)
	end
	for i = 0, 17 do
		piece(
			"PorchRoofBoard",
			Vector3.new(1.55, 0.22, 8.5),
			CFrame.new(-41 + i * 1.55, 10.1, 7.5) * CFrame.Angles(math.rad(9), 0, 0),
			tint(ROOF, 0.035),
			hf
		)
	end
	for _, span in { { -40, -32 }, { -24, -16 } } do
		piece(
			"PorchRail",
			Vector3.new(span[2] - span[1], 0.25, 0.3),
			CFrame.new((span[1] + span[2]) / 2, 3.5, 10.8),
			TRIM,
			hf
		)
		for x = span[1], span[2], 1.3 do
			piece(
				"PorchBaluster",
				Vector3.new(0.2, 2.7, 0.2),
				CFrame.new(x, 1.95, 10.8),
				tint(WOOD, 0.04),
				hf
			)
		end
	end
	-- Brickwork rather than a single plain chimney.
	for row = 0, 9 do
		for col = 0, 1 do
			piece(
				"ChimneyBrick",
				Vector3.new(1.32, 0.62, 2.6),
				CFrame.new(-20.7 + col * 1.4 + (row % 2) * 0.12, 20 + row * 0.67, -14),
				tint(RUST, 0.05),
				hf
			)
		end
	end
	piece("ChimneyCrown", Vector3.new(3.3, 0.6, 3.2), CFrame.new(-20, 26.8, -14), DARK, hf)
	local bf = group("BarnSkin")
	hideDecor(barn, { "Roof", "CornerTrim", "DoorHeader", "Hayloft" })
	siding(barn, Vector3.new(30, 0, 12), true, bf)
	roof(30, 12, 30, 40, 20.6, 12, RED, bf)
	for _, x in { 14.5, 45.5 } do
		for _, z in { -8.6, 32.6 } do
			piece("BarnCornerPost", Vector3.new(0.8, 20, 0.8), CFrame.new(x, 10, z), WOOD, bf)
		end
	end
	-- Frames hug the existing west opening; no decoration spans the walkable opening.
	for _, z in { -0.5, 24.5 } do
		piece("BarnDoorJamb", Vector3.new(0.65, 19, 0.7), CFrame.new(14.1, 9.5, z), TRIM, bf)
	end
	piece("BarnDoorHeader", Vector3.new(0.8, 0.8, 26), CFrame.new(14.1, 19.2, 12), TRIM, bf)
	window(CFrame.new(14.55, 24.4, 12) * CFrame.Angles(0, -math.pi / 2, 0), 5.8, 4.6, bf)
	window(CFrame.new(30, 10, 32.72), 4, 4.8, bf)
	for _, z in { -8.75, 32.75 } do
		for y = 3, 18, 7.2 do
			piece(
				"BarnHorizontalBeam",
				Vector3.new(30.8, 0.36, 0.4),
				CFrame.new(30, y, z),
				WOOD,
				bf
			)
		end
		beam("BarnDiagonalBrace", Vector3.new(16, 3, z), Vector3.new(24, 17, z), 0.45, WOOD, bf)
		beam("BarnDiagonalBrace", Vector3.new(44, 3, z), Vector3.new(36, 17, z), 0.45, WOOD, bf)
	end
	-- Warm recessed interior lighting keeps the original shop visibly accessible.
	local glow = piece("BarnWarmFill", Vector3.new(0.3, 0.3, 0.3), CFrame.new(25, 9, 12), WARM, bf)
	glow.Transparency = 1
	light(glow, 27, 1.2)
	local yard = map:FindFirstChild("Yard")
	assert(yard, "Existing yard missing")
	hideDecor(yard, { "Mill" })
	local mf = group("WindmillSkin")
	local base = Vector3.new(-45, 0, -45)
	local top = 38
	local corners =
		{ Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) }
	local function leg(c: Vector2, y: number): Vector3
		local spread = 3.4 - 2.5 * y / top
		return base + Vector3.new(c.X * spread, y, c.Y * spread)
	end
	for i, c in corners do
		beam("TowerLeg", leg(c, 0), leg(c, top), 0.55, RUST, mf)
		local nextCorner = corners[i % 4 + 1]
		for y = 0, 28, 7 do
			beam("TowerCross", leg(c, y), leg(nextCorner, y + 7), 0.24, WOOD, mf)
			beam("TowerRail", leg(c, y + 7), leg(nextCorner, y + 7), 0.28, RUST, mf)
		end
	end
	piece("MillServicePlatform", Vector3.new(4.2, 0.4, 4.2), CFrame.new(-45, 36, -45), WOOD, mf)
	local hub = base + Vector3.new(0, 40, -1.8)
	for i = 0, 15 do
		local angle = i * math.pi / 8
		local outward = Vector3.new(math.sin(angle), math.cos(angle), 0)
		local tangent = Vector3.new(math.cos(angle), -math.sin(angle), 0)
		beam("RotorSpoke", hub, hub + outward * 8.7, 0.12, DARK, mf)
		if i ~= 3 and i ~= 10 then
			piece(
				"RotorSail",
				Vector3.new(2.3, 3.5, 0.18),
				CFrame.fromMatrix(hub + outward * 7, tangent, outward, Vector3.zAxis),
				tint(ROOF, 0.035),
				mf
			)
		end
		local nextDirection =
			Vector3.new(math.sin(angle + math.pi / 8), math.cos(angle + math.pi / 8), 0)
		beam("RotorRim", hub + outward * 5.2, hub + nextDirection * 5.2, 0.14, RUST, mf)
	end
	local hubPart = piece(
		"RotorHub",
		Vector3.new(0.9, 1.8, 1.8),
		CFrame.new(hub) * CFrame.Angles(0, math.pi / 2, 0),
		RUST,
		mf
	) :: Part
	hubPart.Shape = Enum.PartType.Cylinder
	beam("VaneArm", hub + Vector3.new(0, 0, 1), hub + Vector3.new(10, -0.5, 3), 0.3, RUST, mf)
	piece(
		"TailVane",
		Vector3.new(5, 3, 0.2),
		CFrame.new(hub + Vector3.new(10, -0.5, 3)) * CFrame.Angles(0, -0.2, 0.08),
		ROOF,
		mf
	)
	local perimeter = map:FindFirstChild("Perimeter")
	assert(perimeter, "Existing perimeter missing")
	hideDecor(perimeter, { "SiloDome", "SiloHoop", "Ladder" })
	local sf = group("SiloSkin")
	local siloCenter = Vector3.new(56, 0, -56)
	-- Panel seams and segmented cap retain the original cylindrical climb collider.
	for panel = 0, 15 do
		local a = panel * math.pi / 8
		local cf = CFrame.new(siloCenter) * CFrame.Angles(0, a, 0)
		for row = 0, 4 do
			piece(
				"SiloSheet",
				Vector3.new(2.7, 5.86, 0.16),
				cf * CFrame.new(0, 3 + row * 6, 7.06),
				tint(Color3.fromRGB(116, 121, 119), 0.045),
				sf
			)
		end
		for _, y in { 1, 6, 12, 18, 24, 29.5 } do
			piece(
				"SiloRingSegment",
				Vector3.new(2.85, 0.22, 0.22),
				cf * CFrame.new(0, y, 7.2),
				RUST,
				sf
			)
		end
		local domeA = siloCenter + Vector3.new(math.sin(a) * 7.2, 30, math.cos(a) * 7.2)
		local domeB = siloCenter + Vector3.new(math.sin(a) * 4.2, 34, math.cos(a) * 4.2)
		beam("DomeRib", domeA, domeB, 0.24, DARK, sf)
		beam("DomeRib", domeB, siloCenter + Vector3.new(0, 36, 0), 0.2, DARK, sf)
		piece(
			"DomeLowerPanel",
			Vector3.new(2.7, 0.22, 5),
			cf * CFrame.new(0, 32, 5.7) * CFrame.Angles(math.rad(53), 0, 0),
			tint(ROOF, 0.025),
			sf
		)
		piece(
			"DomeUpperPanel",
			Vector3.new(1.55, 0.22, 4.7),
			cf * CFrame.new(0, 35, 2.1) * CFrame.Angles(math.rad(26), 0, 0),
			tint(ROOF, 0.025),
			sf
		)
	end
	for _, x in { 54.9, 57.1 } do
		piece("SiloLadderRail", Vector3.new(0.2, 30, 0.2), CFrame.new(x, 15, -48.5), DARK, sf)
	end
	for y = 1, 29, 1.5 do
		piece("SiloLadderRung", Vector3.new(2.3, 0.17, 0.2), CFrame.new(56, y, -48.5), RUST, sf)
	end
	-- Detail existing cover props without changing their extents or physical materials.
	local props = map:FindFirstChild("Props")
	assert(props, "Existing props missing")
	local pf = group("PropDetails")
	for _, p in props:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name == "Crate" and not meshedProps.Crate then
				for _, side in { -1, 1 } do
					for _, y in { -1.2, 1.2 } do
						piece(
							"CrateFrame",
							Vector3.new(3.1, 0.28, 0.2),
							p.CFrame * CFrame.new(0, y, side * 1.57),
							DARK,
							pf
						)
					end
					piece(
						"CrateDiagonal",
						Vector3.new(0.32, 3.7, 0.2),
						p.CFrame * CFrame.new(0, 0, side * 1.6) * CFrame.Angles(0, 0, math.rad(40)),
						WOOD,
						pf
					)
				end
			elseif p.Name:match("^Drum") then
				for _, x in { -1.25, 1.25 } do
					local hoop = piece(
						"BarrelHoop",
						Vector3.new(0.16, 2.28, 2.28),
						p.CFrame * CFrame.new(x, 0, 0),
						DARK,
						pf
					) :: Part
					hoop.Shape = Enum.PartType.Cylinder
				end
			elseif p.Name:match("^Truck") then
				if p.Name == "TruckBody" or p.Name == "TruckCab" then
					p.Color = RED
				end
			end
		end
	end
	if not meshedProps.Truck then
		local truck = CFrame.new(-28, 0, 70) * CFrame.Angles(0, math.rad(-35), math.rad(4))
		piece("TruckGrille", Vector3.new(4.5, 1.2, 0.18), truck * CFrame.new(0, 2, -6.15), DARK, pf)
		piece(
			"TruckBumper",
			Vector3.new(5.2, 0.45, 0.6),
			truck * CFrame.new(0, 1.1, -6.25),
			Color3.fromRGB(82, 86, 86),
			pf
		)
		for _, x in { -1.7, 1.7 } do
			local headlight = piece(
				"TruckHeadlight",
				Vector3.new(0.15, 0.7, 0.7),
				truck * CFrame.new(x, 2.2, -6.3) * CFrame.Angles(0, math.pi / 2, 0),
				Color3.fromRGB(174, 161, 119),
				pf
			) :: Part
			headlight.Shape = Enum.PartType.Cylinder
		end
		for i = 0, 5 do
			piece(
				"TruckGrilleSlat",
				Vector3.new(0.1, 1, 0.1),
				truck * CFrame.new(-1.1 + i * 0.44, 2, -6.28),
				TRIM,
				pf
			)
		end
		for _, side in { -1, 1 } do
			piece(
				"TruckBedSide",
				Vector3.new(0.22, 1.25, 4),
				truck * CFrame.new(side * 2.45, 3.9, 3.7),
				RED,
				pf
			)
			piece(
				"TruckDoorHandle",
				Vector3.new(0.15, 0.13, 0.6),
				truck * CFrame.new(side * 2.5, 3.6, -0.3),
				DARK,
				pf
			)
		end
	end
	return count
end

return Structures
