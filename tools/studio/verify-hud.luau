-- Read-only runtime verification. Run in the Client datamodel with the combat HUD visible.
local player = game:GetService("Players").LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local metrics = gui:FindFirstChild("HUDSafeArea")
local area = metrics and metrics:FindFirstChild("SafeAreaMetrics")
assert(area, "HUD safe-area observer missing")
local origin, safeSize = area.AbsolutePosition, area.AbsoluteSize
local report = {
	overlaps = {},
	bounds = {},
	smallTargets = {},
	widgets = {},
	insets = {},
	nativeJumpVisible = false,
	viewport = tostring(workspace.CurrentCamera.ViewportSize),
	safeArea = { x = origin.X, y = origin.Y, w = safeSize.X, h = safeSize.Y },
	preferredInput = game:GetService("UserInputService").PreferredInput.Name,
}
local widgets = {}
local function visible(instance)
	local parent = instance
	while parent do
		if parent:IsA("GuiObject") and not parent.Visible then
			return false
		end
		if parent:IsA("ScreenGui") and not parent.Enabled then
			return false
		end
		parent = parent.Parent
	end
	return true
end
local function add(instance, native)
	if not instance or not instance:IsA("GuiObject") or not visible(instance) then
		return
	end
	table.insert(widgets, instance)
	local p, s = instance.AbsolutePosition - origin, instance.AbsoluteSize
	table.insert(report.widgets, { name = instance.Name, x = p.X, y = p.Y, w = s.X, h = s.Y })
	if
		not native
		and (p.X < -1 or p.Y < -1 or p.X + s.X > safeSize.X + 1 or p.Y + s.Y > safeSize.Y + 1)
	then
		table.insert(report.bounds, instance.Name)
	end
	if instance:GetAttribute("TouchTarget") and (s.X < 52 or s.Y < 52) then
		table.insert(report.smallTargets, instance.Name)
	end
end
for _, name in
	{ "CombatHUD", "ClassUI", "GameMenu", "MatchHUD", "ProgressionHUD", "PortalHUD", "SwarmHUD" }
do
	local screen = gui:FindFirstChild(name)
	if screen then
		report.insets[name] = screen.ScreenInsets.Name
		assert(
			screen.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets,
			name .. " must respect Roblox UI"
		)
	end
end
for _, spec in
	{
		{ "CombatHUD", "Vitals" },
		{ "CombatHUD", "Ammo" },
		{ "GameMenu", "MenuButton" },
		{ "MatchHUD", "Banner" },
		{ "MatchHUD", "Boss" },
		{ "ClassUI", "ClassButton" },
	}
do
	local screen = gui:FindFirstChild(spec[1])
	if screen then
		add(screen:FindFirstChild(spec[2]))
	end
end
local touch = gui:FindFirstChild("SwarmHUD")
if touch then
	add(touch:FindFirstChild("ContextHint"))
	report.combatControlsVisible = touch.Enabled
	report.profile = touch:GetAttribute("LayoutProfile")
	report.solverValid = touch:GetAttribute("LayoutValid")
	report.solverErrors = touch:GetAttribute("LayoutErrors")
	for _, target in touch:GetDescendants() do
		if target:GetAttribute("TouchTarget") then
			add(target)
		end
	end
end
local native = gui:FindFirstChild("TouchGui")
local jump = native and native:FindFirstChild("JumpButton", true)
if jump then
	add(jump, true)
	report.nativeJumpVisible = visible(jump)
end
for i, a in widgets do
	for j = i + 1, #widgets do
		local b = widgets[j]
		local p, size = a.AbsolutePosition, a.AbsoluteSize
		local q, other = b.AbsolutePosition, b.AbsoluteSize
		if
			p.X < q.X + other.X
			and p.X + size.X > q.X
			and p.Y < q.Y + other.Y
			and p.Y + size.Y > q.Y
		then
			table.insert(report.overlaps, a.Name .. " / " .. b.Name)
		end
	end
end
report.widgetCount = #widgets
report.geometryPassed = #report.overlaps == 0 and #report.bounds == 0 and #report.smallTargets == 0
return game:GetService("HttpService"):JSONEncode(report)
