--!strict
-- Account XP and levels (Config.PROGRESSION), shared by every place (the camp hub and the
-- maps). XP is awarded through award() — MatchRewards does it for kills, waves, matches and
-- extractions — doubled while an XP boost is active. The level is derived from lifetime XP;
-- levels unlock shop items (ShopService enforces it).
--
-- Mirrored to the client as player attributes: Level, LevelXP (progress inside the level),
-- LevelXPNeeded, MatchXP (earned this match) and BoostUntil (os.time()).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)

local ProgressionService = {}

local P = Config.PROGRESSION

local notifyRemote: RemoteEvent

-- XP needed to go from `level` to `level + 1`.
function ProgressionService.xpForLevel(level: number): number
	return math.floor(P.levelBase * level ^ P.levelExponent)
end

-- Level and progress inside it for a lifetime XP total.
function ProgressionService.levelFromXp(xp: number): (number, number, number)
	local level = 1
	local remaining = xp
	while remaining >= ProgressionService.xpForLevel(level) do
		remaining -= ProgressionService.xpForLevel(level)
		level += 1
	end
	return level, remaining, ProgressionService.xpForLevel(level)
end

function ProgressionService.level(player: Player): number
	local value = player:GetAttribute("Level")
	return if typeof(value) == "number" then value else 1
end

local function boosted(player: Player): boolean
	local profile = DataService.get(player)
	return profile ~= nil and profile.boostUntil > os.time()
end

local function mirror(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local level, progress, needed = ProgressionService.levelFromXp(profile.xp)
	player:SetAttribute("Level", level)
	player:SetAttribute("LevelXP", progress)
	player:SetAttribute("LevelXPNeeded", needed)
	player:SetAttribute("BoostUntil", profile.boostUntil)
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Nível")
	if value and value:IsA("IntValue") then
		value.Value = level
	end
end

local function unlocksAt(level: number): { string }
	local names = {}
	for item, required in P.unlocks do
		if required == level then
			local gun = Config.GUNS[item :: Config.GunName]
			local melee = Config.MELEE[item :: Config.MeleeName]
			table.insert(
				names,
				if gun then gun.displayName elseif melee then melee.displayName else "Torreta"
			)
		end
	end
	return names
end

-- Adds XP (boost applied) and announces level-ups with what they unlock.
function ProgressionService.award(player: Player, amount: number)
	local profile = DataService.get(player)
	if not profile or amount <= 0 then
		return
	end
	local gained = amount * (if boosted(player) then Config.MONETIZATION.boostMultiplier else 1)
	local before = ProgressionService.levelFromXp(profile.xp)
	profile.xp += gained
	local after = ProgressionService.levelFromXp(profile.xp)
	local matchXp = player:GetAttribute("MatchXP")
	player:SetAttribute("MatchXP", (if typeof(matchXp) == "number" then matchXp else 0) + gained)
	mirror(player)
	for level = before + 1, after do
		local unlocked = unlocksAt(level)
		notifyRemote:FireClient(
			player,
			`Nível {level}!`
				.. (if #unlocked > 0 then " Desbloqueado: " .. table.concat(unlocked, ", ") else "")
		)
	end
end

function ProgressionService.init()
	notifyRemote = Net.notify()
end

function ProgressionService.start()
	local function onLoaded(player: Player)
		player:SetAttribute("MatchXP", 0)
		-- Maps get leaderstats from EconomyService; the hub has none, so make our own.
		local leaderstats = player:WaitForChild("leaderstats", 5)
		if not leaderstats and player.Parent then
			leaderstats = Instance.new("Folder")
			leaderstats.Name = "leaderstats"
			leaderstats.Parent = player
		end
		if leaderstats and not leaderstats:FindFirstChild("Nível") then
			local level = Instance.new("IntValue")
			level.Name = "Nível"
			level.Parent = leaderstats
		end
		mirror(player)
	end
	DataService.loaded:connect(function(player)
		task.spawn(onLoaded, player)
	end)
	-- Profiles that finished loading before this service started (systems start in any order).
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			task.spawn(onLoaded, player)
		end
	end
end

-- Re-publishes attributes after something outside changed the profile (e.g. a boost).
ProgressionService.refresh = mirror

return ProgressionService
