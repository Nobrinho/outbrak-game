--!strict
-- PC access to the floating screen buttons (PRONTO, CLASSE, MENU…). The over-the-shoulder
-- camera locks the mouse to the center, so on keyboard and mouse each button also answers a
-- key, shown as a keycap in its corner. Holding Alt frees the cursor to click any of them.
-- Touch keeps tapping the buttons as before: keycaps only show for keyboard and mouse.

local UserInputService = game:GetService("UserInputService")
local Theme = require(script.Parent.Theme)

local Hotkeys = {}

local KEYCAP = 22

local keycaps: { TextLabel } = {}

local function showKeycaps()
	local keyboard = UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse
	for _, cap in keycaps do
		cap.Visible = keyboard
	end
end
UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(showKeycaps)

-- Runs `callback` when `key` is pressed, also with a menu open (so a key can close what it
-- opened), but never while typing in chat or a text box. With `button`, its corner shows
-- the key.
function Hotkeys.bind(key: Enum.KeyCode, button: GuiObject?, callback: () -> ())
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == key then
			callback()
		end
	end)
	if not button then
		return
	end
	local cap = Theme.text(button, "heavy", {
		Name = "Keycap",
		-- A badge straddling the top-right corner, clear of the button's label.
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(KEYCAP, KEYCAP),
		BackgroundColor3 = Theme.COLOR.panel,
		BackgroundTransparency = 0,
		TextColor3 = Theme.COLOR.accent,
		Text = UserInputService:GetStringForKeyCode(key),
		ZIndex = button.ZIndex + 2,
	})
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = cap
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.COLOR.accent
	stroke.Parent = cap
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = cap
	table.insert(keycaps, cap)
	showKeycaps()
end

-- Alt held: the camera leaves the mouse free so any screen button can be clicked.
function Hotkeys.cursorReleased(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
end

return Hotkeys
