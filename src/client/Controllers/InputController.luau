--!strict
-- Single source of truth for player actions. Keyboard/mouse, gamepad and the touch HUD all
-- feed setAction(); gameplay code only reads isDown() / actionChanged and never cares which
-- device produced the input.

local UserInputService = game:GetService("UserInputService")

local Signal = require(game:GetService("ReplicatedStorage").Shared.Util.Signal)

export type Action = "Fire" | "Aim" | "Reload" | "Ability" | "Interact" | "Grenade" | "Melee" | "Jump"

local InputController = {}

InputController.actionChanged = Signal.new() :: Signal.Signal<Action, boolean>

-- Auto-fire (fire when the crosshair is over a zombie) defaults on for touch; the targeting
-- check itself lands with the weapon system in week 4.
InputController.autoFire = false

local down: { [Action]: boolean } = {}

local KEY_BINDINGS: { [Enum.KeyCode | Enum.UserInputType]: Action } = {
	[Enum.UserInputType.MouseButton1] = "Fire",
	[Enum.UserInputType.MouseButton2] = "Aim",
	[Enum.KeyCode.R] = "Reload",
	[Enum.KeyCode.Q] = "Ability",
	[Enum.KeyCode.E] = "Interact",
	[Enum.KeyCode.G] = "Grenade",
	[Enum.KeyCode.V] = "Melee",
	[Enum.KeyCode.ButtonR2] = "Fire",
	[Enum.KeyCode.ButtonL2] = "Aim",
	[Enum.KeyCode.ButtonX] = "Reload",
	[Enum.KeyCode.ButtonY] = "Ability",
	[Enum.KeyCode.ButtonB] = "Melee",
	[Enum.KeyCode.ButtonR1] = "Grenade",
	[Enum.KeyCode.DPadUp] = "Interact",
}

function InputController.isDown(action: Action): boolean
	return down[action] == true
end

function InputController.setAction(action: Action, isDown: boolean)
	if (down[action] == true) == isDown then
		return
	end
	down[action] = isDown
	InputController.actionChanged:fire(action, isDown)
end

local function bindingFor(input: InputObject): Action?
	return KEY_BINDINGS[input.KeyCode] or KEY_BINDINGS[input.UserInputType]
end

function InputController.init()
	InputController.autoFire = UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled
end

function InputController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local action = bindingFor(input)
		if action then
			InputController.setAction(action, true)
		end
	end)

	-- Releases are never filtered by `processed`, otherwise an action could stay stuck down.
	UserInputService.InputEnded:Connect(function(input)
		local action = bindingFor(input)
		if action then
			InputController.setAction(action, false)
		end
	end)

	-- Losing focus (alt-tab, app backgrounded on mobile) releases everything.
	UserInputService.WindowFocusReleased:Connect(function()
		for action in down do
			InputController.setAction(action, false)
		end
	end)
end

return InputController
