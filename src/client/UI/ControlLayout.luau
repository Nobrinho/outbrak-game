--!strict
-- Pure geometry: all coordinates are relative to the CoreUISafeInsets content rectangle.
local ControlLayout = {}
export type Rect = { x: number, y: number, w: number, h: number }
local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = math.round(x), y = math.round(y), w = math.round(w), h = math.round(h) }
end
function ControlLayout.intersects(a: Rect, b: Rect, gap: number?): boolean
	local g = gap or 0
	return a.x < b.x + b.w + g
		and a.x + a.w + g > b.x
		and a.y < b.y + b.h + g
		and a.y + a.h + g > b.y
end
function ControlLayout.contains(r: Rect, x: number, y: number): boolean
	return x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end

function ControlLayout.solve(width: number, height: number, nativeJump: Rect?, enlargement: number?)
	local margin, gap = 12, 10
	local jump = nativeJump or rect(width - 95, height - 90, 70, 70)
	-- Reserve a stable envelope, never the thumbstick's moving graphics.
	local movement = rect(
		0,
		height - math.min(156, height * 0.48),
		math.min(190, width * 0.28),
		math.min(156, height * 0.48)
	)
	local profiles = {
		{ name = "tablet", button = 64, fire = 96, eligible = width >= 900 and height >= 540 },
		{ name = "phone", button = 58, fire = 84, eligible = width >= 640 and height >= 330 },
		{ name = "compact", button = 52, fire = 76, eligible = true },
	}
	local requested = math.clamp(enlargement or 1, 1, 1.2)
	local last: any = nil
	-- Prefer the requested target size; fall back to the regular size only if it cannot fit.
	for _, multiplier in { requested, 1 } do
		for _, profile in profiles do
			if not profile.eligible then
				continue
			end
			local size = math.round(profile.button * multiplier)
			local fireSize = math.round(profile.fire * multiplier)
			for _, placement in { "above", "beside" } do
				local fireX = width - margin - fireSize
				local fireY = math.min(height - margin - fireSize, jump.y - gap - fireSize)
				if placement == "beside" then
					fireX = math.min(width - margin - fireSize, jump.x - gap - fireSize)
					fireY = height - margin - fireSize
				end
				local gridRight = math.min(fireX, jump.x) - gap
				local gridX = gridRight - (size * 2 + gap)
				local gridY = height - margin - (size * 3 + gap * 2)
				local actions =
					{ Fire = rect(fireX, fireY, fireSize, fireSize) } :: { [string]: Rect }
				for i, name in { "Grenade", "Ability", "Aim", "Reload", "Melee", "Interact" } do
					actions[name] = rect(
						gridX + ((i - 1) % 2) * (size + gap),
						gridY + math.floor((i - 1) / 2) * (size + gap),
						size,
						size
					)
				end
				local ammoLeft, ammoRight = movement.w + margin, gridX - margin
				local ammoWidth = math.min(160, ammoRight - ammoLeft)
				local ammo = rect(
					ammoLeft + (ammoRight - ammoLeft - ammoWidth) / 2,
					height - 56,
					ammoWidth,
					44
				)
				local contextHint = rect(ammo.x, ammo.y - 52, ammo.w, 44)
				local vitals =
					rect(margin, movement.y - 50, math.min(180, movement.w - margin * 2), 40)
				local bannerWidth = math.min(280, width - 240)
				local banner = rect((width - bannerWidth) / 2, 12, bannerWidth, 40)
				local boss = rect(banner.x, 56, banner.w, 14)
				local errors = {}
				local widgets = {
					Vitals = vitals,
					Ammo = ammo,
					ContextHint = contextHint,
					Banner = banner,
					Boss = boss,
					Menu = rect(width - 100, 12, 88, 44),
					Class = rect(12, 12, 108, 44),
				} :: { [string]: Rect }
				for name, r in actions do
					widgets[name] = r
				end
				for name, r in widgets do
					if
						r.x < margin
						or r.y < margin
						or r.x + r.w > width - margin
						or r.y + r.h > height - margin
						or r.w <= 0
					then
						table.insert(errors, name .. ": bounds")
					end
					if
						name ~= "Class"
						and (
							ControlLayout.intersects(r, jump, 4)
							or ControlLayout.intersects(r, movement, 4)
						)
					then
						table.insert(errors, name .. ": native reservation")
					end
					for other, b in widgets do
						if name < other and ControlLayout.intersects(r, b, 4) then
							table.insert(errors, name .. "/" .. other)
						end
					end
				end
				if ammo.w < 92 then
					table.insert(errors, "Ammo: readable width")
				end
				last = {
					profile = profile.name,
					actions = actions,
					ammo = ammo,
					contextHint = contextHint,
					vitals = vitals,
					banner = banner,
					boss = boss,
					jump = jump,
					movement = movement,
					errors = errors,
					valid = #errors == 0,
					enlargement = multiplier,
					requestedEnlargement = requested,
					placement = placement,
				}
				if last.valid then
					return last
				end
			end
		end
	end
	return last
end
return ControlLayout
