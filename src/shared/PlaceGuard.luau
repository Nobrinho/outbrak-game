--!strict
-- Catches the easy mistake of syncing the wrong Rojo project into a place: the camp (start
-- place) must get hub.project.json (port 34873), every map default.project.json (port 34872).
-- On a mismatch it shouts in the Output and puts a red banner on screen while playtesting, so
-- the wrong code is never published by accident. Local files (PlaceId 0) are not checked.

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Config = require(script.Parent.Config)

local PlaceGuard = {}

-- `project` is what the running code is: "hub" or "map". Call once from the server bootstrap.
function PlaceGuard.check(project: "hub" | "map")
	local placeId = game.PlaceId
	if placeId == 0 then
		return
	end
	local isHubPlace = placeId == Config.PLACES.hub
	local wrong = (project == "hub") ~= isHubPlace
	if not wrong then
		return
	end
	local message = if isHubPlace
		then "PLACE ERRADO: este é o ACAMPAMENTO, mas está rodando o código da FAZENDA. "
			.. "Conecte o Rojo na porta 34873 (hub.project.json)."
		else "PLACE ERRADO: este é um MAPA, mas está rodando o código do ACAMPAMENTO. "
			.. "Conecte o Rojo na porta 34872 (default.project.json)."
	warn("[Swarm] " .. message)
	if not RunService:IsStudio() then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlaceGuard"
	gui.DisplayOrder = 100
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 64)
	label.BackgroundColor3 = Color3.fromRGB(170, 20, 20)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = message
	label.Parent = gui
	gui.Parent = StarterGui
end

return PlaceGuard
