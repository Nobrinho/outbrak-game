-- Run with the official Luau CLI: luau tests/mobile-controls.luau
local Layout = require("../src/client/UI/ControlLayout")
local Router = require("../src/client/UI/TouchRouter")
local ActionState = require("../src/client/UI/ActionState")
local tested = 0
for width = 568, 1368, 40 do
	for height = 262, 902, 40 do
		if width < height then
			continue
		end
		for _, scale in { 1, 1.2 } do
			local model = Layout.solve(width, height, nil, scale)
			assert(
				model.valid,
				string.format("%sx%s: %s", width, height, table.concat(model.errors, "; "))
			)
			for name, r in model.actions do
				assert(r.w >= 52 and r.h >= 52, name .. " too small")
				assert(
					r.x >= 0 and r.y >= 0 and r.x + r.w <= width and r.y + r.h <= height,
					name .. " clipped"
				)
				assert(not Layout.intersects(r, model.jump), name .. " covers jump")
				assert(not Layout.intersects(r, model.movement), name .. " covers movement")
				for other, b in model.actions do
					assert(name == other or not Layout.intersects(r, b), name .. "/" .. other)
				end
			end
			tested += 1
		end
	end
end
for _, native in
	{
		{ x = 590, y = 190, w = 70, h = 70 },
		{ x = 660, y = 240, w = 100, h = 100 },
		{ x = 820, y = 400, w = 120, h = 120 },
	}
do
	local model = Layout.solve(native.x + native.w + 25, native.y + native.h + 20, native)
	assert(model.valid, table.concat(model.errors, "; "))
end
assert(not Layout.solve(320, 180).valid, "Impossible viewport must be reported")
local model = Layout.solve(685, 280)
assert(model.profile == "compact")
assert(Layout.solve(900, 400).profile == "phone")
assert(Layout.solve(1024, 700).profile == "tablet")
local released = {}
local router = Router.new()
assert(router.claim("left", "Movement", function()
	released.left = true
end))
assert(router.claim("right", "Fire", function()
	released.right = true
end))
assert(not router.claim("right", "Grenade", function()
	error("Finger transferred")
end))
assert(not router.claim("third", "Fire", function()
	error("Second owner")
end))
router.release("left")
assert(released.left and not released.right, "Movement release cancelled fire")
router.release("right")
assert(released.right)
router.release("right") -- Idempotent; duplicate end/cancel cannot fire callbacks twice.
local count = 0
assert(router.claim("a", "Aim", function()
	count += 1
end))
assert(router.claim("b", "Fire", function()
	count += 1
end))
router.cancel()
router.cancel()
assert(count == 2)
local transitions = {}
local state = ActionState.new(function(action, pressed)
	table.insert(transitions, { action, pressed })
end)
state.set("Fire", true, "touch")
state.set("Fire", true, "mouse")
state.set("Fire", false, "touch")
assert(state.isDown("Fire"), "Release stole another source")
assert(#transitions == 1)
state.set("Fire", false, "mouse")
assert(not state.isDown("Fire") and #transitions == 2)
state.set("Aim", true, "toggle")
state.set("Fire", true, "touch")
state.clear()
assert(not state.isDown("Aim") and not state.isDown("Fire"))
print(
	string.format("PASS: %d layout cases + native reservations, ownership and cancellation", tested)
)
