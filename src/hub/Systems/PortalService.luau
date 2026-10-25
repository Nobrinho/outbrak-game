--!strict
-- Hub portals (one helipad per map, built by HubMap). Players standing on a pad form that
-- map's group, up to its maxPlayers, in arrival order; stepping off leaves it. The group
-- leaves PORTAL.countdown seconds after the first one stepped on (fullCountdown once full):
-- the server reserves a private server of the map's place and teleports the whole group
-- there, with the party in the teleport data so the map knows who to wait for.
--
-- Mirrored for the HUD as player attributes: PortalMap (map name, nil when off a pad),
-- PortalCount, PortalMax, PortalEndsAt (server time). The pad's sign is updated here too.
-- Teleports can't run in Studio: there the launch is a dry run that just notifies.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)

local PortalService = {}

local PORTAL = Config.PORTAL
local RETRY_DELAY = 5 -- after a failed launch, try again this long later
local TELEPORT_GRACE = 20 -- still here this long after a launch: the teleport failed

type Portal = {
	info: Config.MapInfo,
	zone: BasePart,
	title: TextLabel?,
	status: TextLabel?,
	queue: { Player },
	endsAt: number, -- os.clock(); 0 = no countdown
	launching: boolean,
}

local portals: { Portal } = {}
local notifyRemote: RemoteEvent
local teleportingSince: { [Player]: number } = {}

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function inside(zone: BasePart, position: Vector3): boolean
	local offset = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(offset.X) <= half.X
		and math.abs(offset.Y) <= half.Y
		and math.abs(offset.Z) <= half.Z
end

local function standingOn(player: Player, zone: BasePart): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil
		and humanoid.Health > 0
		and root ~= nil
		and root:IsA("BasePart")
		and inside(zone, root.Position)
end

local function setHud(player: Player, portal: Portal?)
	if portal then
		player:SetAttribute("PortalMap", portal.info.name)
		player:SetAttribute("PortalCount", #portal.queue)
		player:SetAttribute("PortalMax", portal.info.maxPlayers)
		local left = portal.endsAt - os.clock()
		player:SetAttribute(
			"PortalEndsAt",
			if portal.endsAt > 0 then workspace:GetServerTimeNow() + left else 0
		)
	else
		player:SetAttribute("PortalMap", nil)
		player:SetAttribute("PortalCount", nil)
		player:SetAttribute("PortalMax", nil)
		player:SetAttribute("PortalEndsAt", nil)
	end
end

local function updateSign(portal: Portal, now: number)
	local status = portal.status
	if not status then
		return
	end
	local info = portal.info
	if info.placeId < 0 then
		status.Text = "Novo mapa a caminho"
	elseif info.placeId == 0 and not RunService:IsStudio() then
		status.Text = "INDISPONÍVEL"
	elseif portal.launching then
		status.Text = "Decolando…"
	elseif #portal.queue == 0 then
		status.Text = "Pise no heliponto para entrar"
	else
		status.Text = string.format(
			"%d/%d — decola em %s",
			#portal.queue,
			info.maxPlayers,
			clock(portal.endsAt - now)
		)
	end
end

local function notifyGroup(group: { Player }, message: string)
	for _, player in group do
		if player.Parent then
			notifyRemote:FireClient(player, message)
		end
	end
end

local function reserve(placeId: number): string?
	for attempt = 1, 3 do
		local ok, code = pcall(TeleportService.ReserveServer, TeleportService, placeId)
		if ok and typeof(code) == "string" then
			return code
		end
		warn(`[Portal] ReserveServer failed ({attempt}/3): {code}`)
		task.wait(attempt)
	end
	return nil
end

-- Sends the group to a fresh reserved server of the map. Runs in its own thread.
local function launch(portal: Portal, group: { Player })
	local info = portal.info
	if RunService:IsStudio() then
		notifyGroup(group, `(Studio) teleporte simulado para {info.name}`)
		portal.launching = false
		return
	end
	for _, player in group do
		teleportingSince[player] = os.clock()
		DataService.saveNow(player)
	end
	local code = reserve(info.placeId)
	local ok, err = false, "no reserved server"
	if code then
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		local party = {}
		for _, player in group do
			table.insert(party, player.UserId)
		end
		options:SetTeleportData({ map = info.id, party = party })
		local present = {}
		for _, player in group do
			if player.Parent then
				table.insert(present, player)
			end
		end
		ok, err =
			pcall(TeleportService.TeleportAsync, TeleportService, info.placeId, present, options)
	end
	if not ok then
		warn(`[Portal] teleport to {info.id} failed: {err}`)
		notifyGroup(group, "Falha ao decolar — tentando de novo")
		for _, player in group do
			teleportingSince[player] = nil
		end
		portal.endsAt = os.clock() + RETRY_DELAY
	end
	portal.launching = false
end

local function step()
	local now = os.clock()
	local onPad: { [Player]: Portal } = {}
	for _, portal in portals do
		local info = portal.info
		-- Keep arrival order: drop who left or stepped off, then append newcomers.
		local queue = {}
		for _, player in portal.queue do
			if
				player.Parent
				and not teleportingSince[player]
				and standingOn(player, portal.zone)
			then
				table.insert(queue, player)
			end
		end
		if info.placeId > 0 or (info.placeId == 0 and RunService:IsStudio()) then
			for _, player in Players:GetPlayers() do
				if
					#queue < info.maxPlayers
					and not table.find(queue, player)
					and not onPad[player]
					and not teleportingSince[player]
					and standingOn(player, portal.zone)
				then
					table.insert(queue, player)
				end
			end
		end
		portal.queue = queue

		if #queue == 0 then
			portal.endsAt = 0
		elseif portal.endsAt == 0 then
			portal.endsAt = now + PORTAL.countdown
		end
		if #queue >= info.maxPlayers then
			portal.endsAt = math.min(portal.endsAt, now + PORTAL.fullCountdown)
		end
		if #queue > 0 and not portal.launching and now >= portal.endsAt then
			portal.launching = true
			portal.endsAt = 0
			task.spawn(launch, portal, table.clone(queue))
		end

		for _, player in queue do
			onPad[player] = portal
		end
		updateSign(portal, now)
	end

	for _, player in Players:GetPlayers() do
		setHud(player, onPad[player])
		local since = teleportingSince[player]
		if since and now - since > TELEPORT_GRACE then
			teleportingSince[player] = nil
		end
	end
end

function PortalService.init()
	notifyRemote = Net.notify()
end

function PortalService.start()
	local hub = workspace:WaitForChild("Hub")
	local folder = hub:WaitForChild("Portals")
	for _, info in Config.MAPS do
		local pad = folder:WaitForChild(info.id)
		local zone = pad:WaitForChild("Zone") :: BasePart
		local sign = pad:FindFirstChild("Sign")
		local board = sign and sign:FindFirstChild("Board")
		table.insert(portals, {
			info = info,
			zone = zone,
			title = board and board:FindFirstChild("Title") :: TextLabel?,
			status = board and board:FindFirstChild("Status") :: TextLabel?,
			queue = {},
			endsAt = 0,
			launching = false,
		})
	end

	TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
		teleportingSince[player] = nil
		warn(`[Portal] TeleportInitFailed for {player.Name}: {message}`)
		notifyRemote:FireClient(player, "Falha ao decolar — pise no heliponto de novo")
	end)
	Players.PlayerRemoving:Connect(function(player)
		teleportingSince[player] = nil
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= PORTAL.scanInterval then
			accumulator = 0
			step()
		end
	end)
end

return PortalService
