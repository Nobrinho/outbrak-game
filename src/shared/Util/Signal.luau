--!strict
-- Minimal synchronous signal. Handlers run in order; disconnect via the returned function.

export type Signal<T...> = {
	connect: (self: Signal<T...>, handler: (T...) -> ()) -> () -> (),
	fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { (T...) -> () } = {}

	local function connect(_: Signal<T...>, handler: (T...) -> ()): () -> ()
		table.insert(handlers, handler)
		return function()
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end
	end

	local function fire(_: Signal<T...>, ...: T...)
		for _, handler in table.clone(handlers) do
			handler(...)
		end
	end

	return { connect = connect, fire = fire } :: Signal<T...>
end

return Signal
