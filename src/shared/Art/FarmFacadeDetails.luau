--!strict
-- Supplemental architecture and weathering; only decorative descendants are created.
local Details = {}

function Details.build(parent: Instance)
	local root = Instance.new("Folder")
	root.Name = "FacadeDetails"
	root.Parent = parent
	local rng = Random.new(251026)
	local wood = Color3.fromRGB(105, 90, 72)
	local edge = Color3.fromRGB(132, 115, 88)
	local dark = Color3.fromRGB(44, 39, 33)
	local slate = Color3.fromRGB(43, 53, 61)
	local function part(
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		wedge: boolean?
	): BasePart
		local p: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Parent = root
		return p
	end
	local function beam(name: string, a: Vector3, b: Vector3, width: number, color: Color3)
		part(
			name,
			Vector3.new(width, width, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b),
			color
		)
	end
	-- Front dormer above the porch: a visual attic, above the existing ceiling collider.
	local cx, front = -34, 0.8
	part("DormerFront", Vector3.new(6, 4.8, 0.3), CFrame.new(cx, 20.4, front), wood)
	for _, side in { -1, 1 } do
		part("DormerSide", Vector3.new(0.3, 4.8, 6.5), CFrame.new(cx + side * 3, 20.4, -2.3), wood)
		part(
			"DormerGable",
			Vector3.new(0.35, 2.6, 3),
			CFrame.new(cx + side * 1.5, 24.1, front) * CFrame.Angles(0, -side * math.pi / 2, 0),
			wood,
			true
		)
		part(
			"DormerRoof",
			Vector3.new(4.5, 0.23, 7.1),
			CFrame.new(cx + side * 1.75, 24.1, -2.3)
				* CFrame.Angles(0, 0, -side * math.atan2(2.6, 3.5)),
			slate
		)
		beam(
			"DormerRoofTrim",
			Vector3.new(cx, 25.4, 1.35),
			Vector3.new(cx + side * 3.6, 22.75, 1.35),
			0.3,
			edge
		)
	end
	for row = 0, 4 do
		part("DormerClapboard", Vector3.new(6, 0.13, 0.2), CFrame.new(cx, 18.4 + row, 1), dark)
	end
	part("DormerWindowRecess", Vector3.new(3.2, 3.6, 0.15), CFrame.new(cx, 20.9, 1.05), dark)
	local pane = part(
		"DormerWarmGlass",
		Vector3.new(2.7, 3.1, 0.1),
		CFrame.new(cx, 20.9, 1.15),
		Color3.fromRGB(193, 86, 31)
	)
	pane.Material = Enum.Material.Neon
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 159, 76)
	glow.Brightness = 0.45
	glow.Range = 11
	glow.Shadows = false
	glow.Parent = pane
	for _, x in { -1.5, 0, 1.5 } do
		part("DormerWindowFrame", Vector3.new(0.2, 3.7, 0.25), CFrame.new(cx + x, 20.9, 1.25), edge)
	end
	for _, y in { 19.1, 20.9, 22.7 } do
		part("DormerWindowFrame", Vector3.new(3.2, 0.2, 0.25), CFrame.new(cx, y, 1.25), edge)
	end
	-- Shutters flank only the south decorative windows; the east barricades are untouched.
	for _, wx in { -38, -18 } do
		for _, side in { -1, 1 } do
			local cf = CFrame.new(wx + side * 3, 7, 4.95)
				* CFrame.Angles(0, side * 0.11, side * 0.035)
			for slat = 0, 6 do
				if not (side == 1 and slat == 2) then
					part(
						"BrokenShutter",
						Vector3.new(1, 0.62, 0.18),
						cf * CFrame.new(0, -2.1 + slat * 0.7, 0),
						wood:Lerp(dark, rng:NextNumber(0.1, 0.4))
					)
				end
			end
			part(
				"ShutterRail",
				Vector3.new(0.15, 5.2, 0.2),
				cf * CFrame.new(side * 0.35, 0, -0.05),
				dark
			)
		end
	end
	-- Thin broken boards and nail marks on existing, already-solid wall surfaces.
	for i = 1, 24 do
		local x = if i % 2 == 0 then rng:NextNumber(-44, -32) else rng:NextNumber(-24, -12)
		local y = rng:NextNumber(0.8, 13)
		if y < 4 or y > 10 then
			part(
				"SplitClapboard",
				Vector3.new(rng:NextNumber(0.8, 2.2), 0.06, 0.06),
				CFrame.new(x, y, 4.77) * CFrame.Angles(0, 0, rng:NextNumber(-0.025, 0.025)),
				dark
			)
		end
	end
	-- Small leaf clusters climb the solid outer surfaces, never entrances or windows.
	for _, vine in
		{
			{ cf = CFrame.new(-44, 0, 4.9), height = 12 },
			{ cf = CFrame.new(-13, 0, 4.9), height = 6 },
			{ cf = CFrame.new(44, 0, 32.9), height = 16 },
			{ cf = CFrame.new(17, 0, 32.9), height = 10 },
			{ cf = CFrame.new(59, 0, -49.4), height = 22 },
		}
	do
		for step = 1, math.floor(vine.height / 0.85) do
			local x = math.sin(step * 0.65) * 0.7
			local cf = vine.cf * CFrame.new(x, step * 0.85, 0.04)
			part(
				"IvyStem",
				Vector3.new(0.09, 1, 0.12),
				cf * CFrame.Angles(0, 0, 0.2 * math.cos(step)),
				dark
			)
			for _, side in { -1, 1 } do
				local color = Color3.fromRGB(
					65 + rng:NextInteger(0, 27),
					74 + rng:NextInteger(0, 20),
					37 + rng:NextInteger(0, 12)
				)
				part(
					"IvyLeaf",
					Vector3.new(0.7, 0.8, 0.12),
					cf
						* CFrame.new(side * 0.4, 0.2, 0.13)
						* CFrame.Angles(0, side * 0.25, side * 0.65),
					color,
					true
				)
			end
		end
	end
	-- Dark ties make the original hay cover read as bundled straw without touching it.
	for _, bale in
		{
			{ cf = CFrame.new(9, 1.25, 28), size = Vector3.new(4, 2.5, 2.5) },
			{
				cf = CFrame.new(9.5, 3.75, 28.3) * CFrame.Angles(0, math.rad(8), 0),
				size = Vector3.new(4, 2.5, 2.5),
			},
		}
	do
		for _, x in { -1.1, 1.1 } do
			for _, z in { -1, 1 } do
				part(
					"HayBinding",
					Vector3.new(0.08, bale.size.Y + 0.03, 0.08),
					bale.cf * CFrame.new(x, 0, z * (bale.size.Z / 2 + 0.03)),
					dark
				)
			end
			part(
				"HayBinding",
				Vector3.new(0.08, 0.08, bale.size.Z),
				bale.cf * CFrame.new(x, bale.size.Y / 2 + 0.03, 0),
				dark
			)
		end
	end
end

return Details
