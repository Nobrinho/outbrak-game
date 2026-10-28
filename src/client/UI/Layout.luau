--!strict
-- One shared safe-area observer. Native joystick graphics never drive HUD positions.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Solver = require(script.Parent.ControlLayout)
local Settings = require(script.Parent.ControlSettings)
local Layout = {}
local metricsArea: Frame?
local current: any = nil
local subscribers: { [ScreenGui]: (any) -> () } = {}
local queued = false
local jump: GuiObject?
local jumpConnections: { RBXScriptConnection } = {}

function Layout.isTouch(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Touch
end
function Layout.configure(screen: ScreenGui, order: number?)
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = order or 10
end
local function update()
	queued = false
	local area = metricsArea
	if not area or area.AbsoluteSize.X < 1 or area.AbsoluteSize.Y < 1 then
		return
	end
	local size, origin = area.AbsoluteSize, area.AbsolutePosition
	local native = nil
	if jump and jump.Parent and jump.AbsoluteSize.Y > 0 then
		local p, s = jump.AbsolutePosition - origin, jump.AbsoluteSize
		native = { x = p.X, y = p.Y, w = s.X, h = s.Y }
	end
	local mobile = Solver.solve(size.X, size.Y, native, Settings.get("size"))
	current = {
		size = size,
		origin = origin,
		touch = Layout.isTouch(),
		scale = math.clamp(math.min(size.X / 760, size.Y / 380), 0.85, 1.15),
		margin = 12,
		mobile = mobile,
		touchBottom = size.Y - mobile.jump.y + 10,
		vitalsBottom = size.Y - mobile.movement.y + 10,
	}
	for screen, apply in subscribers do
		if screen.Parent then
			apply(current)
		end
	end
end
local function schedule()
	if queued then
		return
	end
	queued = true
	task.defer(update)
end
local function watchJump(control: Instance)
	if control.Name ~= "JumpButton" or not control:IsA("GuiObject") or control == jump then
		return
	end
	for _, connection in jumpConnections do
		connection:Disconnect()
	end
	table.clear(jumpConnections)
	jump = control
	for _, property in { "AbsolutePosition", "AbsoluteSize" } do
		table.insert(jumpConnections, control:GetPropertyChangedSignal(property):Connect(schedule))
	end
	table.insert(
		jumpConnections,
		control.Destroying:Connect(function()
			jump = nil
			for _, connection in jumpConnections do
				connection:Disconnect()
			end
			table.clear(jumpConnections)
			schedule()
		end)
	)
	schedule()
end
local function initialize()
	if metricsArea then
		return
	end
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "HUDSafeArea"
	Layout.configure(screen, 0)
	local area = Instance.new("Frame")
	area.Name = "SafeAreaMetrics"
	area.BackgroundTransparency = 1
	area.Size = UDim2.fromScale(1, 1)
	area.Active = false
	area.Parent = screen
	metricsArea = area
	screen.Parent = gui
	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule)
	area:GetPropertyChangedSignal("AbsolutePosition"):Connect(schedule)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(schedule)
	Settings.changed:connect(function(key)
		if key == "size" then
			schedule()
		end
	end)
	local native = gui:FindFirstChild("TouchGui")
	if native then
		for _, control in native:GetDescendants() do
			watchJump(control)
		end
	end
	gui.DescendantAdded:Connect(function(control)
		if control:FindFirstAncestor("TouchGui") then
			watchJump(control)
		end
	end)
	schedule()
end
function Layout.bind(screen: ScreenGui, apply: (any) -> ())
	initialize()
	subscribers[screen] = apply
	screen.Destroying:Once(function()
		subscribers[screen] = nil
	end)
	if current then
		apply(current)
	else
		schedule()
	end
	return metricsArea
end
function Layout.place(widget: GuiObject, r: Solver.Rect)
	widget.AnchorPoint = Vector2.zero
	widget.Position = UDim2.fromOffset(r.x, r.y)
	widget.Size = UDim2.fromOffset(r.w, r.h)
end
function Layout.limitText(label: TextLabel | TextButton, min: number?, max: number?)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = min or 12
	limit.MaxTextSize = max or 24
	limit.Parent = label
end
return Layout
