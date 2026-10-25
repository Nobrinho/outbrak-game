--!strict
-- Hub (camp) server entry point, same two-phase bootstrap as the maps (src/server/init.server.luau).

local Folder = script:FindFirstChild("Systems")

local loaded: { [string]: any } = {}
if Folder then
	for _, child in Folder:GetChildren() do
		if child:IsA("ModuleScript") then
			loaded[child.Name] = require(child) :: any
		end
	end
end

for _, mod in loaded do
	if typeof(mod.init) == "function" then
		mod.init()
	end
end

for _, mod in loaded do
	if typeof(mod.start) == "function" then
		task.spawn(mod.start)
	end
end

print("[Swarm] hub server started")
