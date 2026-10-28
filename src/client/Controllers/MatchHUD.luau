--!strict
-- Match HUD: a top-center banner (phase, wave, timer or zombies left), the Brute's health bar,
-- a big announcement on every phase change, the "you're down" notice, the result screen, the
-- lobby's PRONTO button and the notice for players who joined a match already under way.
-- Everything is read from the attributes MatchService sets on ReplicatedStorage.Match (and the
-- player's own InMatch / Ready attributes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)
local Input = require(script.Parent.InputController)

local MatchHUD = {}

local COLOR_PANEL = Color3.fromRGB(20, 20, 24)
local COLOR_TEXT = Color3.fromRGB(240, 240, 240)
local COLOR_DANGER = Color3.fromRGB(220, 40, 40)
local COLOR_GOOD = Color3.fromRGB(0, 200, 230)
local COLOR_WARN = Color3.fromRGB(255, 204, 0)

local player = Players.LocalPlayer
local state: Instance
local screen: ScreenGui
local titleLabel: TextLabel
local detailLabel: TextLabel
local bossFrame: Frame
local bossFill: Frame
local announce: TextLabel
local downLabel: TextLabel
local result: Frame
local resultTitle: TextLabel
local resultStats: TextLabel
local lobbyScreen: ScreenGui
local readyButton: TextButton
local hubButton: TextButton
local lateLabel: TextLabel

local function attr<T>(name: string, default: T): T
	local value = state:GetAttribute(name)
	return if value ~= nil then value :: any else default
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = COLOR_TEXT
	l.FontFace = Theme.FONT.heavy
	l.TextStrokeTransparency = 0.75
	l.TextScaled = true
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function build()
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 12)
	banner.Size = UDim2.fromScale(0.3, 0.1)
	Theme.panel(banner)
	banner.Parent = screen
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 4
	aspect:Destroy()

	Theme.image(banner, "ui.icons.wave", {
		Position = UDim2.fromScale(0.03, 0.12),
		Size = UDim2.fromScale(0.08, 0.38),
		ImageColor3 = Theme.COLOR.accent,
	})
	titleLabel =
		text(banner, { Position = UDim2.fromScale(0.13, 0.08), Size = UDim2.fromScale(0.82, 0.5) })
	detailLabel = text(banner, {
		Position = UDim2.fromScale(0.05, 0.58),
		Size = UDim2.fromScale(0.9, 0.34),
		TextTransparency = 0.15,
	})

	bossFrame = Instance.new("Frame")
	bossFrame.Name = "Boss"
	bossFrame.AnchorPoint = Vector2.new(0.5, 0)
	bossFrame.Position = UDim2.new(0.5, 0, 0, 12)
	bossFrame.Size = UDim2.fromScale(0.36, 0.03)
	bossFrame.BackgroundColor3 = COLOR_PANEL
	bossFrame.BackgroundTransparency = 0.2
	bossFrame.BorderSizePixel = 0
	bossFrame.Visible = false
	bossFrame.Parent = screen
	bossFill = Instance.new("Frame")
	bossFill.BackgroundColor3 = COLOR_DANGER
	bossFill.BorderSizePixel = 0
	bossFill.Size = UDim2.fromScale(1, 1)
	bossFill.Parent = bossFrame
	text(bossFrame, { Size = UDim2.fromScale(1, 1), Text = "BRUTE", ZIndex = 2 })
	-- Sits right under the banner.
	banner:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		bossFrame.Position = UDim2.new(0.5, 0, 0, 12 + banner.AbsoluteSize.Y + 6)
	end)

	announce = text(screen, {
		FontFace = Theme.FONT.display,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.6, 0.1),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	downLabel = text(screen, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.6, 0.05),
		Text = "VOCÊ CAIU — VOLTA NA PRÓXIMA PREPARAÇÃO",
		TextColor3 = COLOR_DANGER,
		Visible = false,
	})

	lateLabel = text(screen, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.7, 0.05),
		TextColor3 = COLOR_WARN,
		Visible = false,
	})

	-- Its own ScreenGui above the class picker, so PRONTO stays reachable with it open.
	lobbyScreen = Instance.new("ScreenGui")
	lobbyScreen.Name = "LobbyUI"
	Layout.configure(lobbyScreen, 11)
	readyButton = Instance.new("TextButton")
	readyButton.Name = "Ready"
	readyButton.AnchorPoint = Vector2.new(0.5, 1)
	readyButton.Position = UDim2.new(0.5, 0, 1, -16)
	readyButton.Size = UDim2.fromScale(0.22, 0.1)
	readyButton.Visible = false
	Theme.button(readyButton)
	readyButton.Parent = lobbyScreen
	local readyAspect = Instance.new("UIAspectRatioConstraint")
	readyAspect.AspectRatio = 3.2
	readyAspect:Destroy()
	readyButton.Activated:Connect(function()
		Net.setReady():FireServer(player:GetAttribute("Ready") ~= true)
	end)

	-- Back to the camp hub: in the lobby, while spectating, or on the result screen.
	hubButton = Instance.new("TextButton")
	hubButton.Name = "BackToHub"
	hubButton.AnchorPoint = Vector2.new(0.5, 1)
	hubButton.Position = UDim2.new(0.5, 0, 0.88, -24)
	hubButton.Size = UDim2.fromScale(0.24, 0.055)
	hubButton.Text = "VOLTAR AO ACAMPAMENTO"
	hubButton.Visible = false
	Theme.button(hubButton, "secondary")
	hubButton.BackgroundColor3 = COLOR_PANEL
	hubButton.TextColor3 = COLOR_TEXT
	hubButton.Parent = lobbyScreen
	hubButton.Activated:Connect(function()
		Net.returnToHub():FireServer()
	end)

	result = Instance.new("Frame")
	result.Name = "Result"
	result.Size = UDim2.fromScale(1, 1)
	result.BackgroundColor3 = Color3.new(0, 0, 0)
	result.BackgroundTransparency = 0.35
	result.Visible = false
	result.ZIndex = 5
	result.Parent = screen
	Theme.image(result, "ui.icons.trophy", {
		Position = UDim2.fromScale(0.46, 0.17),
		Size = UDim2.fromScale(0.08, 0.12),
		ZIndex = 6,
		ImageColor3 = Theme.COLOR.accent,
	})
	resultTitle = text(result, {
		FontFace = Theme.FONT.display,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.35),
		Size = UDim2.fromScale(0.7, 0.14),
		ZIndex = 6,
	})
	resultStats = text(result, {
		FontFace = Theme.FONT.label,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromScale(0.5, 0.3),
		TextScaled = true,
		TextWrapped = true,
		TextSize = 22,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 6,
	})
end

local function flashAnnouncement(message: string, color: Color3)
	announce.Text = message
	announce.TextColor3 = color
	announce.TextTransparency = 0
	announce.TextStrokeTransparency = 0.4
	local fade = TweenService:Create(
		announce,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	fade:Play()
end

local function killsTable(): string
	local rows = {}
	local players = Players:GetPlayers()
	local function kills(p: Player): number
		local leaderstats = p:FindFirstChild("leaderstats")
		local value = leaderstats and leaderstats:FindFirstChild("Abates")
		return if value and value:IsA("IntValue") then value.Value else 0
	end
	table.sort(players, function(a, b)
		return kills(a) > kills(b)
	end)
	for _, p in players do
		table.insert(rows, string.format("%s — %d abates", p.DisplayName, kills(p)))
	end
	return table.concat(rows, "\n")
end

local function onPhaseChanged()
	local phase = attr("Phase", "Waiting")
	local wave = attr("Wave", 0)
	if phase == "Prep" then
		flashAnnouncement("PREPARAÇÃO", COLOR_WARN)
	elseif phase == "Wave" then
		flashAnnouncement("ONDA " .. wave, COLOR_DANGER)
	elseif phase == "Final" then
		flashAnnouncement("ONDA FINAL", COLOR_DANGER)
	elseif phase == "Extract" then
		flashAnnouncement("CORRA PARA O HELICÓPTERO!", COLOR_GOOD)
	end

	result.Visible = phase == "Result"
	if phase == "Result" then
		local victory = attr("Outcome", "") == "Victory"
		resultTitle.Text = if victory then "EXTRAÍDOS!" else "A HORDA VENCEU"
		resultTitle.TextColor3 = if victory then COLOR_GOOD else COLOR_DANGER
		-- XP is awarded as the match ends; give the attribute a moment to arrive.
		task.delay(0.5, function()
			local xp = player:GetAttribute("MatchXP")
			local level = player:GetAttribute("Level")
			local summary = if typeof(xp) == "number"
				then string.format("+%d XP  ·  Nível %s\n\n", xp, tostring(level or 1))
				else ""
			resultStats.Text = summary .. killsTable()
		end)
	end
end

-- Shown by Roblox while the teleport back to the camp loads.
local function teleportScreen(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "TeleportScreen"
	gui.IgnoreGuiInset = true
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(14, 12, 12)
	back.Parent = gui
	text(back, {
		FontFace = Theme.FONT.display,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.1),
		Text = "VOLTANDO AO ACAMPAMENTO…",
		TextColor3 = COLOR_WARN,
	})
	return gui
end

local function timeLeft(): number
	local endsAt = attr("EndsAt", 0)
	if endsAt <= 0 then
		return 0
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

local function clock(seconds: number): string
	local s = math.ceil(seconds)
	return string.format("%d:%02d", s // 60, s % 60)
end

local function update()
	screen.Enabled = not Input.isModalOpen()
	lobbyScreen.Enabled = not Input.isModalOpen()
	local phase = attr("Phase", "Waiting")
	local wave = attr("Wave", 0)
	local waves = attr("Waves", 10)
	local left = timeLeft()

	if phase == "Lobby" then
		titleLabel.Text = "LOBBY"
		detailLabel.Text = string.format(
			"Começa em %s — %d/%d prontos",
			clock(left),
			attr("ReadyCount", 0),
			attr("LobbyCount", 0)
		)
	elseif phase == "Prep" then
		titleLabel.Text = "PREPARAÇÃO"
		detailLabel.Text = "Repare barricadas e reabasteça — " .. clock(left)
	elseif phase == "Wave" then
		titleLabel.Text = string.format("ONDA %d / %d", wave, waves)
		detailLabel.Text = string.format("%d zumbis restantes", attr("Remaining", 0))
	elseif phase == "Final" then
		titleLabel.Text = string.format("ONDA FINAL %d / %d", waves, waves)
		detailLabel.Text = "Helicóptero em " .. clock(left)
	elseif phase == "Extract" then
		titleLabel.Text = "EXTRAÇÃO"
		detailLabel.Text = "Chegue ao helicóptero ao norte — " .. clock(left)
	elseif phase == "Result" then
		titleLabel.Text = "FIM DE PARTIDA"
		detailLabel.Text = "Nova partida em " .. clock(left)
	else
		titleLabel.Text = "AGUARDANDO"
		detailLabel.Text = ""
	end

	local bossMax = attr("BossMaxHealth", 0)
	local bossHealth = attr("BossHealth", 0)
	bossFrame.Visible = bossMax > 0 and bossHealth > 0
	if bossMax > 0 then
		bossFill.Size = UDim2.fromScale(math.clamp(bossHealth / bossMax, 0, 1), 1)
	end

	local ready = player:GetAttribute("Ready") == true
	readyButton.Visible = phase == "Lobby"
		and player:GetAttribute("ClassConfirmed") == true
		and not Input.isModalOpen()
	readyButton.Text = if ready then "PRONTO ✓" else "PRONTO"
	readyButton.BackgroundColor3 = if ready then COLOR_GOOD else COLOR_WARN

	local inMatch = player:GetAttribute("InMatch") == true
	local underWay = phase ~= "Lobby" and phase ~= "Waiting" and phase ~= "Result"
	hubButton.Visible = Config.PLACES.hub > 0
		and Config.PLACES.hub ~= game.PlaceId
		and (phase == "Lobby" or phase == "Result" or (underWay and not inMatch))
	lateLabel.Visible = underWay and not inMatch
	if lateLabel.Visible then
		lateLabel.Text = string.format(
			"PARTIDA EM ANDAMENTO (ONDA %d/%d) — VOCÊ ENTRA NA PRÓXIMA",
			math.max(wave, 1),
			waves
		)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local inCombat = phase == "Wave" or phase == "Final" or phase == "Extract"
	downLabel.Visible = inMatch and inCombat and (not humanoid or humanoid.Health <= 0)
end

function MatchHUD.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "MatchHUD"
	Layout.configure(screen, 10)
	build()
end

function MatchHUD.start()
	state = ReplicatedStorage:WaitForChild("Match")
	state:GetAttributeChangedSignal("Phase"):Connect(onPhaseChanged)
	onPhaseChanged()
	-- Timers tick every frame; cheap (a few text writes).
	RunService.RenderStepped:Connect(update)
	screen.Parent = player:WaitForChild("PlayerGui")
	lobbyScreen.Parent = screen.Parent
	Layout.bind(screen, function(m)
		local banner = screen:FindFirstChild("Banner") :: Frame
		if m.touch then
			Layout.place(banner, m.mobile.banner)
			Layout.place(bossFrame, m.mobile.boss)
		else
			banner.AnchorPoint = Vector2.new(0.5, 0)
			banner.Position = UDim2.new(0.5, 0, 0, 12)
			banner.Size = UDim2.fromOffset(math.min(300, m.size.X * 0.42), 52)
			bossFrame.AnchorPoint = Vector2.new(0.5, 0)
			bossFrame.Position = UDim2.new(0.5, 0, 0, 70)
			bossFrame.Size = UDim2.fromOffset(math.min(300, m.size.X * 0.38), 20)
		end
		readyButton.Size = UDim2.fromOffset(math.min(220, m.size.X * 0.32), 48)
		hubButton.Position = UDim2.new(0.5, 0, 1, -76)
		hubButton.Size = UDim2.fromOffset(math.min(260, m.size.X * 0.4), 44)
	end)
	TeleportService:SetTeleportGui(teleportScreen())
end

return MatchHUD
