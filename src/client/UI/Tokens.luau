--!strict
-- Outbreak UI v0.1. Specification: docs/design/DESIGN-SYSTEM.md.
-- Shared by both places through their existing Client/UI Rojo mapping.
return table.freeze({
	color = table.freeze({
		panel = Color3.fromRGB(16, 16, 20),
		surface = Color3.fromRGB(36, 36, 42),
		text = Color3.fromRGB(236, 232, 222),
		muted = Color3.fromRGB(160, 156, 148),
		accent = Color3.fromRGB(255, 204, 0),
		danger = Color3.fromRGB(220, 40, 40),
		player = Color3.fromRGB(0, 200, 230),
		fire = Color3.fromRGB(255, 140, 20),
		disabled = Color3.fromRGB(90, 90, 96),
	}),
	font = table.freeze({
		label = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Medium),
		heavy = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
		display = Font.new("rbxasset://fonts/families/Bangers.json"),
	}),
	textSize = table.freeze({
		caption = 14,
		label = 18,
		body = 20,
		title = 28,
		stat = 36,
		announcement = 48,
	}),
	space = table.freeze({
		micro = 4,
		small = 8,
		medium = 12,
		large = 16,
		section = 24,
		major = 32,
	}),
	geometry = table.freeze({ radius = 4, stroke = 1, cornerTab = 16 }),
	transparency = table.freeze({ hud = 0.3, modal = 0.1, edge = 0.85, textStroke = 0.75 }),
	touch = table.freeze({ minimum = 48, secondary = 60, fire = 88, gap = 12 }),
	motion = table.freeze({ feedback = 0.12, transition = 0.2, notice = 3 }),
	layer = table.freeze({ hud = 10, contextual = 20, announcement = 30, modal = 40, toast = 50 }),
})
