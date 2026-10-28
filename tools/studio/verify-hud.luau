-- Run in the Studio MCP Client datamodel during a playtest. Read-only geometry checks.
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local report = { overlaps = {}, insets = {}, nativeJumpVisible = false }
local widgets = {}
local function add(instance)
	if not instance or not instance:IsA("GuiObject") or not instance.Visible then
		return
	end
	local parent = instance.Parent
	while parent do
		if parent:IsA("GuiObject") and not parent.Visible then
			return
		end
		if parent:IsA("ScreenGui") and not parent.Enabled then
			return
		end
		parent = parent.Parent
	end
	table.insert(widgets, instance)
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
local combat = gui:FindFirstChild("CombatHUD")
if combat then
	add(combat:FindFirstChild("Vitals"))
	add(combat:FindFirstChild("Ammo"))
end
local menu = gui:FindFirstChild("GameMenu")
if menu then
	add(menu:FindFirstChild("MenuButton"))
end
local match = gui:FindFirstChild("MatchHUD")
if match then
	add(match:FindFirstChild("Banner"))
end
local touch = gui:FindFirstChild("SwarmHUD")
if touch then
	local cluster = touch:FindFirstChild("ActionCluster")
	if cluster then
		for _, button in cluster:GetChildren() do
			add(button)
		end
	end
	add(touch:FindFirstChild("MeleeQuickSlot"))
	add(touch:FindFirstChild("Interact"))
end
local native = gui:FindFirstChild("TouchGui")
local jump = native and native:FindFirstChild("JumpButton", true)
if jump then
	add(jump)
	report.nativeJumpVisible = jump.Visible
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
return game:GetService("HttpService"):JSONEncode(report)
