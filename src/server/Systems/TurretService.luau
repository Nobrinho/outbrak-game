--!strict
-- Automatic turrets. A turret kit bought at the shop ("TurretKits" player attribute) is
-- installed by holding the prompt on one of the map's TurretSlot markers. The turret shoots
-- the nearest visible zombie in range, credits kills to its owner, makes noise, and powers
-- down (freeing the slot) when its ammo runs out.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Hitscan = require(Shared.Hitscan)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local HordeService = require(script.Parent.HordeService)

local TurretService = {}

local TURRET = Config.TURRET
local RETARGET_INTERVAL = 0.3
local MAX_SIGHT_CHECKS = 4 -- line-of-sight raycasts per retarget
local HEAD_HEIGHT = 2.8

type Turret = {
	slot: BasePart,
	owner: Player,
	ammo: number,
	model: Model,
	head: BasePart,
	target: HordeService.Zombie?,
	nextShot: number,
	nextRetarget: number,
}

local turrets: { [BasePart]: Turret } = {}
local shotRemote: UnreliableRemoteEvent
local notifyRemote: RemoteEvent

local function notify(player: Player, message: string)
	if player.Parent then
		notifyRemote:FireClient(player, message)
	end
end

local function kits(player: Player): number
	local value = player:GetAttribute("TurretKits")
	return if typeof(value) == "number" then value else 0
end

function TurretService.addKit(player: Player): boolean
	if kits(player) >= TURRET.maxKits then
		return false
	end
	player:SetAttribute("TurretKits", kits(player) + 1)
	return true
end

local function slotPrompt(slot: BasePart): ProximityPrompt?
	return slot:FindFirstChildOfClass("ProximityPrompt")
end

local function buildModel(slot: BasePart): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Turret"
	local function piece(
		name: string,
		size: Vector3,
		cframe: CFrame,
		color: Color3,
		material: Enum.Material
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material
		p.CanQuery = false -- bullets pass the turret, it isn't cover
		p.Parent = model
		return p
	end
	local base = slot.Position
	piece(
		"Base",
		Vector3.new(3, 2, 3),
		CFrame.new(base + Vector3.new(0, 1, 0)),
		Color3.fromRGB(60, 62, 66),
		Enum.Material.DiamondPlate
	)
	local head = piece(
		"Head",
		Vector3.new(1.8, 1.2, 2.6),
		CFrame.new(base + Vector3.new(0, HEAD_HEIGHT, 0)),
		Color3.fromRGB(40, 44, 48),
		Enum.Material.Metal
	)
	local lamp = piece(
		"Lamp",
		Vector3.new(0.4, 0.2, 0.4),
		head.CFrame * CFrame.new(0, 0.7, 0.6),
		Color3.fromRGB(0, 200, 230),
		Enum.Material.Neon
	)
	lamp.CanCollide = false
	local barrel = piece(
		"Barrel",
		Vector3.new(0.35, 0.35, 2),
		head.CFrame * CFrame.new(0, 0, -2.2),
		Color3.fromRGB(30, 30, 30),
		Enum.Material.Metal
	)
	barrel.CanCollide = false
	-- Lamp and barrel follow the head when it turns.
	for _, attached in { lamp, barrel } do
		attached.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = attached
		weld.Parent = attached
	end
	model.PrimaryPart = head
	model.Parent = workspace
	return model, head
end

local function removeTurret(turret: Turret)
	turret.model:Destroy()
	turrets[turret.slot] = nil
	local prompt = slotPrompt(turret.slot)
	if prompt then
		prompt.Enabled = true
	end
end

local function install(slot: BasePart, player: Player)
	if turrets[slot] then
		return
	end
	if kits(player) < 1 then
		notify(player, "Compre uma torreta na loja do celeiro")
		return
	end
	player:SetAttribute("TurretKits", kits(player) - 1)
	local model, head = buildModel(slot)
	turrets[slot] = {
		slot = slot,
		owner = player,
		ammo = TURRET.ammo,
		model = model,
		head = head,
		target = nil,
		nextShot = 0,
		nextRetarget = 0,
	}
	local prompt = slotPrompt(slot)
	if prompt then
		prompt.Enabled = false
	end
	notify(player, "Torreta instalada")
end

local function chest(zombie: HordeService.Zombie): Vector3
	return zombie.position
		+ Vector3.new(0, Hitscan.CHEST_HEIGHT * Config.ZOMBIES[zombie.kindName].scale, 0)
end

-- Nearest zombie in range that the turret can actually see.
local function findTarget(turret: Turret): HordeService.Zombie?
	local origin = turret.head.Position
	local candidates: { { zombie: HordeService.Zombie, dist: number } } = {}
	for _, zombie in HordeService.getZombies() do
		if not zombie.dead then
			local dist = (chest(zombie) - origin).Magnitude
			if dist <= TURRET.range then
				table.insert(candidates, { zombie = zombie, dist = dist })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)
	for i = 1, math.min(#candidates, MAX_SIGHT_CHECKS) do
		local zombie = candidates[i].zombie
		if Hitscan.clearLine(origin, chest(zombie)) then
			return zombie
		end
	end
	return nil
end

local function stepTurret(turret: Turret, now: number)
	if now >= turret.nextRetarget then
		turret.nextRetarget = now + RETARGET_INTERVAL
		turret.target = findTarget(turret)
	end
	local target = turret.target
	if not target or target.dead or now < turret.nextShot then
		return
	end
	local aim = chest(target)
	local origin = turret.head.Position
	if (aim - origin).Magnitude > TURRET.range then
		turret.target = nil
		return
	end
	turret.nextShot = now + 1 / TURRET.fireRate

	turret.head.CFrame = CFrame.lookAt(origin, Vector3.new(aim.X, origin.Y, aim.Z))
	local muzzle = origin + turret.head.CFrame.LookVector * 3.2
	local owner = if turret.owner.Parent then turret.owner else nil
	HordeService.damage(target, TURRET.damage, owner)
	shotRemote:FireAllClients(muzzle, aim)
	HordeService.noise(turret.slot.Position, TURRET.noise, 1.5, turret)

	turret.ammo -= 1
	if turret.ammo <= 0 then
		removeTurret(turret)
		if owner then
			notify(owner, "Sua torreta ficou sem munição")
		end
	end
end

local function setupSlot(instance: Instance)
	if not instance:IsA("BasePart") or slotPrompt(instance) then
		return
	end
	local slot = instance
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Instalar torreta"
	prompt.ObjectText = "Ponto de torreta"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = slot
	prompt.Triggered:Connect(function(player)
		install(slot, player)
	end)
end

-- Removes every turret and kit (new match).
function TurretService.clear()
	for _, turret in turrets do
		removeTurret(turret)
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute("TurretKits", 0)
	end
end

function TurretService.init()
	shotRemote = Net.turretShot()
	notifyRemote = Net.notify()
end

function TurretService.start()
	CollectionService:GetInstanceAddedSignal(Tags.TurretSlot):Connect(setupSlot)
	for _, slot in CollectionService:GetTagged(Tags.TurretSlot) do
		setupSlot(slot)
	end
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, turret in turrets do
			stepTurret(turret, now)
		end
	end)
end

return TurretService
