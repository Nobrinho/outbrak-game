--!strict
-- Single source of truth for player actions. Keyboard/mouse, gamepad and the touch HUD all
-- feed setAction(); gameplay code only reads isDown() / actionChanged and never cares which
-- device produced the input.

local UserInputService = game:GetService("UserInputService")

local GuiService = game:GetService("GuiService")
local ActionState = require(script.Parent.Parent.UI.ActionState)
local Settings = require(script.Parent.Parent.UI.ControlSettings)
local Signal = require(game:GetService("ReplicatedStorage").Shared.Util.Signal)

export type Action =
	"Fire"
	| "Aim"
	| "Reload"
	| "Ability"
	| "Interact"
	| "Grenade"
	| "Melee"
	| "Jump"
	-- Weapon slots: pick one directly, or step through them (mouse wheel, D-pad, HUD tap).
	| "Slot1"
	| "Slot2"
	| "Slot3"
	| "NextSlot"
	| "PrevSlot"

local InputController = {}

InputController.modalChanged = Signal.new() :: Signal.Signal<boolean>
InputController.panelRequested = Signal.new() :: Signal.Signal<string>
InputController.actionChanged = Signal.new() :: Signal.Signal<Action, boolean>

-- Auto-fire (fire when the crosshair is over a zombie) defaults on for touch; the targeting
-- check itself lands with the weapon system in week 4.
InputController.autoFire = false

InputController.cancelled = Signal.new() :: Signal.Signal<string>
local state = ActionState.new(function(action, pressed)
	InputController.actionChanged:fire(action :: Action, pressed)
end)
function InputController.cancelAll(reason: string)
	state.clear()
	InputController.cancelled:fire(reason)
end
local modals: { [string]: boolean } = {}
local closers: { [string]: () -> () } = {}

function InputController.registerModal(name: string, close: () -> ())
	closers[name] = close
end

function InputController.isTouch(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Touch
end

local KEY_BINDINGS: { [Enum.KeyCode | Enum.UserInputType]: Action } = {
	[Enum.UserInputType.MouseButton1] = "Fire",
	[Enum.UserInputType.MouseButton2] = "Aim",
	[Enum.KeyCode.R] = "Reload",
	[Enum.KeyCode.Q] = "Ability",
	[Enum.KeyCode.E] = "Interact",
	[Enum.KeyCode.G] = "Grenade",
	[Enum.KeyCode.V] = "Melee",
	[Enum.KeyCode.One] = "Slot1",
	[Enum.KeyCode.Two] = "Slot2",
	[Enum.KeyCode.Three] = "Slot3",
	[Enum.KeyCode.ButtonR2] = "Fire",
	[Enum.KeyCode.ButtonL2] = "Aim",
	[Enum.KeyCode.ButtonX] = "Reload",
	[Enum.KeyCode.ButtonY] = "Ability",
	[Enum.KeyCode.ButtonB] = "Melee",
	[Enum.KeyCode.ButtonR1] = "Grenade",
	[Enum.KeyCode.DPadUp] = "Interact",
	[Enum.KeyCode.DPadRight] = "NextSlot",
	[Enum.KeyCode.DPadLeft] = "PrevSlot",
}

-- Menus (shop, class picker) register while open: the mouse is freed and weapons hold fire.
function InputController.setModal(name: string, open: boolean)
	if open then
		for other in table.clone(modals) do
			if other ~= name and closers[other] then
				closers[other]()
			end
		end
	end
	modals[name] = if open then true else nil
	if open then
		InputController.cancelAll("modal")
	end
	InputController.modalChanged:fire(InputController.isModalOpen())
end

function InputController.isModalOpen(): boolean
	return next(modals) ~= nil
end

function InputController.isDown(action: Action): boolean
	return state.isDown(action)
end

function InputController.setAction(action: Action, pressed: boolean, source: any?)
	if pressed and InputController.isModalOpen() then
		return
	end
	state.set(action, pressed, source or "legacy")
end

local function bindingFor(input: InputObject): Action?
	return KEY_BINDINGS[input.KeyCode] or KEY_BINDINGS[input.UserInputType]
end

function InputController.init()
	InputController.autoFire = Settings.get("autoFire")
	Settings.changed:connect(function(key)
		if key == "autoFire" then
			InputController.autoFire = Settings.get(key)
		end
	end)
end

function InputController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or InputController.isModalOpen() then
			return
		end
		local action = bindingFor(input)
		if action then
			InputController.setAction(action, true, input)
		end
	end)

	-- The mouse wheel has no press/release: each notch is a tap of Next/PrevSlot.
	UserInputService.InputChanged:Connect(function(input, processed)
		if
			processed
			or InputController.isModalOpen()
			or input.UserInputType ~= Enum.UserInputType.MouseWheel
			or input.Position.Z == 0
		then
			return
		end
		local action: Action = if input.Position.Z < 0 then "NextSlot" else "PrevSlot"
		InputController.setAction(action, true, "wheel")
		InputController.setAction(action, false, "wheel")
	end)

	-- Releases are never filtered by `processed`, otherwise an action could stay stuck down.
	UserInputService.InputEnded:Connect(function(input)
		local action = bindingFor(input)
		if action then
			InputController.setAction(action, false, input)
		end
	end)

	UserInputService.WindowFocusReleased:Connect(function()
		InputController.cancelAll("focus")
	end)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		InputController.cancelAll("input-device")
	end)
	GuiService.MenuOpened:Connect(function()
		InputController.setModal("Roblox", true)
	end)
	GuiService.MenuClosed:Connect(function()
		InputController.setModal("Roblox", false)
	end)
	game:GetService("Players").LocalPlayer.CharacterRemoving:Connect(function()
		InputController.cancelAll("character")
	end)
end

return InputController
