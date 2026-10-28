--!strict
-- Local session preferences. No server data or combat balance is changed.
local Signal = require(game:GetService("ReplicatedStorage").Shared.Util.Signal)
local Settings = {}
Settings.changed = Signal.new() :: Signal.Signal<string>
local defaults: { [string]: any } = {
	size = 1,
	transparency = 0.35,
	sensitivity = 1,
	aimSensitivity = 0.75,
	aimMode = "toggle",
	autoFire = true,
}
local values = table.clone(defaults)
function Settings.get(key: string): any
	return values[key]
end
function Settings.set(key: string, value: any)
	if defaults[key] == nil or values[key] == value then
		return
	end
	values[key] = value
	Settings.changed:fire(key)
end
function Settings.reset()
	for key, value in defaults do
		Settings.set(key, value)
	end
end
return Settings
