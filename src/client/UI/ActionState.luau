--!strict
-- Multiple input sources may hold an action; releasing one must not release another.
local ActionState = {}
function ActionState.new(changed: (string, boolean) -> ())
	local sources: { [string]: { [any]: boolean } } = {}
	local state = {}
	function state.isDown(action: string): boolean
		return sources[action] ~= nil and next(sources[action]) ~= nil
	end
	function state.set(action: string, pressed: boolean, source: any)
		local before = state.isDown(action)
		local held = sources[action] or {}
		sources[action] = held
		held[source] = if pressed then true else nil
		local after = state.isDown(action)
		if before ~= after then
			changed(action, after)
		end
	end
	function state.clear()
		local old = sources
		sources = {}
		for action, held in old do
			if next(held) then
				changed(action, false)
			end
		end
	end
	return state
end
return ActionState
