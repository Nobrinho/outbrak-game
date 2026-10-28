--!strict
-- Hub HUD: the camp's title, the group panel while standing on a helipad (map, players,
-- countdown, how to cancel), toasts from the server (level-ups, purchases, portal errors)
-- and the loading screen shown while the teleport to a map runs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)
local Input = require(script.Parent.InputController)

local PortalHUD = {}

local player = Players.LocalPlayer
local screen: ScreenGui
local panel: Frame
local mapLabel: TextLabel
local groupLabel: TextLabel
local toastLabel: TextLabel
local toastToken = 0
local campTitle: TextLabel
local campHint: TextLabel
local teleportOverlay: ScreenGui?

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function build()
	campTitle = Theme.text(screen, "display", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromScale(0.4, 0.07),
		Text = "ACAMPAMENTO",
		TextColor3 = Theme.COLOR.accent,
	})
	campHint = Theme.text(screen, "label", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.07, 18),
		Size = UDim2.fromScale(0.5, 0.035),
		Text = "Suba num heliponto com seu grupo para ir a um mapa",
		TextColor3 = Theme.COLOR.muted,
	})

	panel = Instance.new("Frame")
	panel.Name = "Group"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -24)
	panel.Size = UDim2.fromScale(0.42, 0.16)
	panel.Visible = false
	Theme.panel(panel, 0.15)
	panel.Parent = screen
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 4.2
	aspect:Destroy()
	Theme.image(panel, "ui.icons.helicopter", {
		Position = UDim2.fromScale(0.03, 0.1),
		Size = UDim2.fromScale(0.09, 0.38),
		ImageColor3 = Theme.COLOR.accent,
	})
	mapLabel = Theme.text(panel, "heavy", {
		Position = UDim2.fromScale(0.14, 0.08),
		Size = UDim2.fromScale(0.82, 0.4),
		TextColor3 = Theme.COLOR.accent,
	})
	groupLabel = Theme.text(panel, "heavy", {
		Position = UDim2.fromScale(0.05, 0.5),
		Size = UDim2.fromScale(0.9, 0.24),
	})
	Theme.text(panel, "label", {
		Position = UDim2.fromScale(0.05, 0.76),
		Size = UDim2.fromScale(0.9, 0.18),
		Text = "Saia do heliponto para cancelar",
		TextColor3 = Theme.COLOR.muted,
	})

	toastLabel = Theme.text(screen, "heavy", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.6, 0.05),
		TextTransparency = 1,
	})
end

local function toast(message: string)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = message
	toastLabel.TextTransparency = 0
	task.delay(3, function()
		if token == toastToken then
			TweenService:Create(toastLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
	end)
end

-- Shown by Roblox on this client while the teleport to the map loads.
local function loadingScreen(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "TeleportScreen"
	gui.IgnoreGuiInset = true
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(14, 12, 12)
	back.Parent = gui
	Theme.image(
		back,
		"backgrounds.hub-loading-v1",
		{ Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop }
	)
	local shade = Instance.new("Frame")
	shade.Name = "Readability"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Theme.COLOR.panel
	shade.BackgroundTransparency = 0.3
	shade.BorderSizePixel = 0
	shade.Parent = back
	Theme.text(back, "display", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.6, 0.1),
		Text = "DECOLANDO…",
		TextColor3 = Theme.COLOR.accent,
	})
	Theme.text(back, "label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.6, 0.04),
		Text = "Segure firme. A horda está esperando.",
		TextColor3 = Theme.COLOR.muted,
	})
	return gui
end

local function update()
	local map = player:GetAttribute("PortalMap")
	local queued = typeof(map) == "string"
	local visible = not Input.isModalOpen()
	panel.Visible = queued and visible
	campTitle.Visible = not queued and visible
	campHint.Visible = campTitle.Visible
	if not panel.Visible then
		return
	end
	mapLabel.Text = map :: string
	local count = player:GetAttribute("PortalCount")
	local max = player:GetAttribute("PortalMax")
	local endsAt = player:GetAttribute("PortalEndsAt")
	local left = if typeof(endsAt) == "number" and endsAt > 0
		then endsAt - workspace:GetServerTimeNow()
		else 0
	groupLabel.Text = string.format(
		"GRUPO %s/%s — DECOLA EM %s",
		tostring(count or 1),
		tostring(max or 4),
		clock(left)
	)
end

function PortalHUD.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "PortalHUD"
	Layout.configure(screen, 10)
	build()
end

function PortalHUD.start()
	screen.Parent = player:WaitForChild("PlayerGui")
	Layout.bind(screen, function(m)
		campTitle.Position = UDim2.new(0.5, 0, 0, 12)
		campTitle.Size = UDim2.fromOffset(math.min(320, m.size.X * 0.5), 36)
		campHint.Position = UDim2.new(0.5, 0, 0, 52)
		campHint.Size = UDim2.fromOffset(math.min(440, m.size.X * 0.7), 26)
		panel.Size = UDim2.fromOffset(math.min(440, m.size.X * 0.48), 88)
		panel.Position = UDim2.new(0.5, 0, 1, if not m.touch and m.size.X < 900 then -88 else -16)
	end)
	TeleportService:SetTeleportGui(loadingScreen())
	player.OnTeleport:Connect(function(state)
		if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
			if not teleportOverlay then
				teleportOverlay = loadingScreen()
				teleportOverlay.DisplayOrder = 80
				teleportOverlay.Parent = player:WaitForChild("PlayerGui")
			end
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(failedPlayer)
		if failedPlayer == player and teleportOverlay then
			teleportOverlay:Destroy()
			teleportOverlay = nil
		end
	end)
	Net.notify().OnClientEvent:Connect(function(message: unknown)
		if typeof(message) == "string" then
			toast(message)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return PortalHUD
