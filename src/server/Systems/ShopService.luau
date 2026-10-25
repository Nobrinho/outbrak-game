--!strict
-- Barn shop (Config.SHOP). The client opens the menu from the shop crate's prompt; purchases
-- arrive here and are checked for everything that matters: the item exists, the player is
-- alive and standing at a shop crate, has the account level that unlocks it, can afford it,
-- and the item actually applies (not already equipped, grenades not full, kit limit). Credits
-- are only taken if it applied.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local CombatService = require(script.Parent.CombatService)
local EconomyService = require(script.Parent.EconomyService)
local ProgressionService = require(script.Parent.ProgressionService)
local TurretService = require(script.Parent.TurretService)

local ShopService = {}

local PURCHASE_COOLDOWN = 0.3

local notifyRemote: RemoteEvent
local lastPurchase: { [Player]: number } = {}

local itemsById: { [string]: Config.ShopItem } = {}
for _, item in Config.SHOP do
	itemsById[item.id] = item
end

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function atShop(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	for _, crate in CollectionService:GetTagged(Tags.ShopBox) do
		if
			crate:IsA("BasePart")
			and (crate.Position - root.Position).Magnitude <= Config.SHOP_RANGE
		then
			return true
		end
	end
	return false
end

-- Applies the item; returns nil on success or the reason it couldn't.
local function apply(player: Player, item: Config.ShopItem): string?
	if item.kind == "gun" then
		return if CombatService.equipGun(player, item.id :: Config.GunName)
			then nil
			else "Você já está com essa arma"
	elseif item.kind == "melee" then
		return if CombatService.equipMelee(player, item.id :: Config.MeleeName)
			then nil
			else "Você já está com essa arma"
	elseif item.kind == "grenade" then
		return if CombatService.addGrenade(player) then nil else "Granadas no máximo"
	elseif item.kind == "heal" then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return "Item indisponível"
		end
		if humanoid.Health >= humanoid.MaxHealth then
			return "Sua vida já está cheia"
		end
		humanoid.Health = humanoid.MaxHealth
		return nil
	elseif item.kind == "turret" then
		return if TurretService.addKit(player) then nil else "Limite de torretas atingido"
	end
	return "Item indisponível"
end

local function onPurchase(player: Player, itemId: unknown)
	if typeof(itemId) ~= "string" then
		return
	end
	local item = itemsById[itemId]
	local now = os.clock()
	if not item or now - (lastPurchase[player] or 0) < PURCHASE_COOLDOWN then
		return
	end
	lastPurchase[player] = now

	-- Credits and loadouts belong to a match: nothing to buy in the lobby.
	if player:GetAttribute("InMatch") ~= true then
		notify(player, "A loja abre quando a partida começa")
		return
	end
	if not atShop(player) then
		notify(player, "Chegue mais perto da loja")
		return
	end
	local required = Config.PROGRESSION.unlocks[item.id]
	if required and ProgressionService.level(player) < required then
		notify(player, `Desbloqueia no nível {required}`)
		return
	end
	if EconomyService.get(player) < item.price then
		notify(player, "Créditos insuficientes")
		return
	end
	local failure = apply(player, item)
	if failure then
		notify(player, failure)
		return
	end
	EconomyService.spend(player, item.price) -- can't fail: checked above, same frame
	notify(
		player,
		if item.kind == "turret"
			then "Torreta comprada: instale numa marca azul do quintal"
			else "Comprou: " .. item.displayName
	)
end

function ShopService.init()
	notifyRemote = Net.notify()
end

function ShopService.start()
	Net.purchase().OnServerEvent:Connect(onPurchase)
	Players.PlayerRemoving:Connect(function(player)
		lastPurchase[player] = nil
	end)
end

return ShopService
