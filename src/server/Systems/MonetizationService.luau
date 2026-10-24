--!strict
-- Fair monetization (docs/DEFINICOES.md §6), cosmetics and convenience only:
--   • Gamepass "Pacote do Sobrevivente" — gold weapon skin + a trail ("SurvivorPack" attribute;
--     CombatService paints the gun, this module adds the trail).
--   • Developer Product "Boost 2x XP por 1 h" — extends the profile's boostUntil.
-- Receipts are idempotent: a purchase id is recorded in the profile and only reported as
-- granted once the profile carrying it has been saved, so a crash never loses or doubles it.
-- With ids left at 0 (not created in the Creator Hub yet) everything here stays inactive.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)
local ProfileSchema = require(script.Parent.Parent.Data.ProfileSchema)
local ProgressionService = require(script.Parent.ProgressionService)

local MonetizationService = {}

local M = Config.MONETIZATION
local notifyRemote: RemoteEvent
-- Receipts applied in memory whose profile hasn't been saved yet.
local unsaved: { [string]: boolean } = {}

local function addTrail(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or root:FindFirstChild("SurvivorTrail") then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "SurvivorTrailTop"
	top.Position = Vector3.new(0, 0.8, 0.4)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "SurvivorTrailBottom"
	bottom.Position = Vector3.new(0, -0.9, 0.4)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "SurvivorTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.35
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(0, 200, 230), Color3.fromRGB(255, 204, 0))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = root
end

local function grantPack(player: Player)
	player:SetAttribute("SurvivorPack", true)
	if player.Character then
		task.spawn(addTrail, player.Character)
	end
end

local function checkPass(player: Player)
	if M.survivorPackId == 0 then
		return
	end
	local ok, owns = pcall(
		MarketplaceService.UserOwnsGamePassAsync,
		MarketplaceService,
		player.UserId,
		M.survivorPackId
	)
	if ok and owns then
		grantPack(player)
	end
end

local function hasReceipt(profile: ProfileSchema.Profile, id: string): boolean
	return table.find(profile.receipts, id) ~= nil
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and DataService.get(player)
	if not player or not profile then
		-- Not in this server (or still loading): Roblox retries later, possibly elsewhere.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = tostring(receipt.PurchaseId)
	if hasReceipt(profile, id) and not unsaved[id] then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted and saved
	end

	if not hasReceipt(profile, id) then
		if receipt.ProductId ~= M.xpBoostProductId or M.xpBoostProductId == 0 then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- unknown product: don't eat it
		end
		profile.boostUntil = math.max(profile.boostUntil, os.time()) + M.boostSeconds
		table.insert(profile.receipts, id)
		unsaved[id] = true
		ProgressionService.refresh(player)
	end

	if DataService.saveNow(player) then
		unsaved[id] = nil
		notifyRemote:FireClient(player, "Boost 2x XP ativado!")
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.init()
	notifyRemote = Net.notify()
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == M.survivorPackId and M.survivorPackId ~= 0 then
			grantPack(player)
			notifyRemote:FireClient(player, "Pacote do Sobrevivente ativado!")
		end
	end)

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			if player:GetAttribute("SurvivorPack") == true then
				addTrail(character)
			end
		end)
		checkPass(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MonetizationService
