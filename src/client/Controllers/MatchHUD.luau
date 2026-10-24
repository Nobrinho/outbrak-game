--!strict
-- Match HUD: a top-center banner (phase, wave, timer or zombies left), the Brute's health bar,
-- a big announcement on every phase change, the "you're down" notice and the result screen.
-- Everything is read from the attributes MatchService sets on ReplicatedStorage.Match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.UI.Theme)

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
	aspect.Parent = banner

	titleLabel =
		text(banner, { Position = UDim2.fromScale(0.05, 0.08), Size = UDim2.fromScale(0.9, 0.5) })
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

	result = Instance.new("Frame")
	result.Name = "Result"
	result.Size = UDim2.fromScale(1, 1)
	result.BackgroundColor3 = Color3.new(0, 0, 0)
	result.BackgroundTransparency = 0.35
	result.Visible = false
	result.ZIndex = 5
	result.Parent = screen
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
		TextScaled = false,
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
		resultStats.Text = killsTable()
	end
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
	local phase = attr("Phase", "Waiting")
	local wave = attr("Wave", 0)
	local waves = attr("Waves", 2)
	local left = timeLeft()

	if phase == "Prep" then
		titleLabel.Text = "PREPARAÇÃO"
		detailLabel.Text = "Repare barricadas e reabasteça — " .. clock(left)
	elseif phase == "Wave" then
		titleLabel.Text = string.format("ONDA %d / %d", wave, waves)
		detailLabel.Text = string.format("%d zumbis restantes", attr("Remaining", 0))
	elseif phase == "Final" then
		titleLabel.Text = "ONDA FINAL"
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

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local inCombat = phase == "Wave" or phase == "Final" or phase == "Extract"
	downLabel.Visible = inCombat and (not humanoid or humanoid.Health <= 0)
end

function MatchHUD.init()
	screen = Instance.new("ScreenGui")
	screen.Name = "MatchHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	build()
end

function MatchHUD.start()
	state = ReplicatedStorage:WaitForChild("Match")
	state:GetAttributeChangedSignal("Phase"):Connect(onPhaseChanged)
	onPhaseChanged()
	-- Timers tick every frame; cheap (a few text writes).
	RunService.RenderStepped:Connect(update)
	screen.Parent = player:WaitForChild("PlayerGui")
end

return MatchHUD
