--!strict
-- Pure ownership state. Used by both GUI input and the fire/camera pass-through.
local TouchRouter = {}
function TouchRouter.new()
	local touches: { [any]: any } = {}
	local controls: { [string]: any } = {}
	local router = {}
	function router.claim(touch: any, name: string, release: () -> ()): boolean
		if touches[touch] or controls[name] then
			return false
		end
		touches[touch] = { name = name, release = release }
		controls[name] = touch
		return true
	end
	function router.release(touch: any)
		local held = touches[touch]
		if not held then
			return
		end
		touches[touch] = nil
		controls[held.name] = nil
		held.release()
	end
	function router.cancel()
		for touch in table.clone(touches) do
			router.release(touch)
		end
	end
	return router
end
return TouchRouter
