--!strict
-- Map-side XP sources (Config.PROGRESSION): kills, cleared waves, finished matches and
-- extractions. Only the match roster earns wave and match XP; spectators who joined late
-- don't. Lives with the map's systems so ProgressionService stays usable in the hub.

local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local DataService = require(script.Parent.DataService)
local HordeService = require(script.Parent.HordeService)
local MatchService = require(script.Parent.MatchService)
local ProgressionService = require(script.Parent.ProgressionService)

local MatchRewards = {}

local P = Config.PROGRESSION

function MatchRewards.start()
	HordeService.killed:connect(function(zombie, attacker)
		if attacker and attacker.Parent then
			local profile = DataService.get(attacker)
			if profile then
				profile.kills += 1
			end
			ProgressionService.award(attacker, P.xpPerKill[zombie.kindName] or 0)
		end
	end)

	MatchService.started:connect(function()
		for _, player in Players:GetPlayers() do
			player:SetAttribute("MatchXP", 0)
		end
	end)
	MatchService.waveCleared:connect(function()
		for _, player in Players:GetPlayers() do
			if MatchService.isParticipant(player) then
				ProgressionService.award(player, P.xpWaveCleared)
			end
		end
	end)
	MatchService.finished:connect(function(_outcome, extracted)
		for _, player in Players:GetPlayers() do
			if not MatchService.isParticipant(player) then
				continue
			end
			local profile = DataService.get(player)
			if profile then
				profile.matches += 1
			end
			ProgressionService.award(player, P.xpMatchPlayed)
		end
		for _, player in extracted do
			local profile = DataService.get(player)
			if profile then
				profile.extractions += 1
			end
			ProgressionService.award(player, P.xpExtraction)
		end
	end)
end

return MatchRewards
