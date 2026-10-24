--!strict
-- In-match credits: earned per kill (Config.REWARDS, turret kills go to its owner), spent at
-- the barn shop, reset every match. Shown in the leaderboard as "Créditos".

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local HordeService = require(script.Parent.HordeService)

local EconomyService = {}

local function startCredits(): number
	return if Config.DEBUG.richStart then 5000 else Config.START_CREDITS
end

local function creditsValue(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Créditos")
	return if value and value:IsA("IntValue") then value else nil
end

function EconomyService.get(player: Player): number
	local value = creditsValue(player)
	return if value then value.Value else 0
end

function EconomyService.add(player: Player, amount: number)
	local value = creditsValue(player)
	if value then
		value.Value += amount
	end
end

-- Takes `amount` if the player can afford it.
function EconomyService.spend(player: Player, amount: number): boolean
	local value = creditsValue(player)
	if not value or value.Value < amount then
		return false
	end
	value.Value -= amount
	return true
end

function EconomyService.resetAll()
	for _, player in Players:GetPlayers() do
		local value = creditsValue(player)
		if value then
			value.Value = startCredits()
		end
	end
end

local function onPlayerAdded(player: Player)
	-- CombatService creates leaderstats; credits are added next to the kill count.
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats or leaderstats:FindFirstChild("Créditos") then
		return
	end
	local credits = Instance.new("IntValue")
	credits.Name = "Créditos"
	credits.Value = startCredits()
	credits.Parent = leaderstats
end

function EconomyService.start()
	HordeService.killed:connect(function(zombie, attacker)
		if attacker and attacker.Parent then
			EconomyService.add(attacker, Config.REWARDS[zombie.kindName] or 0)
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return EconomyService
