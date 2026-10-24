--!strict
-- Roblox Swarm: Outbreak client entry point. Two-phase bootstrap: init() all, then start() all.

local Folder = script:FindFirstChild("Controllers")

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

print("[Swarm] client started")
