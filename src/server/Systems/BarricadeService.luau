--!strict
-- Barricade health, breaking and repair. Zombies hit barricades through
-- HordeService.barricadeHit; at 0 health the barricade drops (no collision, see-through) and
-- its flow-field cells open so the horde pours in. Players hold the prompt to repair; a broken
-- barricade can only be rebuilt once no zombie is standing in its gap.
--
-- State lives in attributes (Health, MaxHealth, Broken) so clients can draw health bars
-- without extra remotes.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local FlowField = require(script.Parent.Parent.Horde.FlowField)
local HordeService = require(script.Parent.HordeService)

local BarricadeService = {}

local BARRICADE = Config.BARRICADE
local COLOR_FULL = Color3.fromRGB(255, 204, 0)
local COLOR_LOW = Color3.fromRGB(150, 40, 30)

local lastRepair: { [Player]: number } = {}

local function health(part: BasePart): number
	local h = part:GetAttribute("Health")
	return if typeof(h) == "number" then h else 0
end

local function refresh(part: BasePart)
	local h = health(part)
	local broken = part:GetAttribute("Broken") == true
	part.Color = COLOR_LOW:Lerp(COLOR_FULL, h / BARRICADE.maxHealth)
	part.Transparency = if broken then 0.85 else 0
	part.CanCollide = not broken

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = h < BARRICADE.maxHealth
		prompt.ActionText = if broken then "Reconstruir" else "Reparar"
	end
end

local function setHealth(part: BasePart, value: number)
	part:SetAttribute("Health", math.clamp(value, 0, BARRICADE.maxHealth))
	refresh(part)
end

local function breakBarricade(part: BasePart)
	part:SetAttribute("Broken", true)
	FlowField.setOwnerKind(part, FlowField.FREE)
	refresh(part)
end

local function zombieInGap(part: BasePart): boolean
	for _, zombie in HordeService.getZombies() do
		if not zombie.dead then
			local ix, iz = FlowField.cellAt(zombie.position)
			if FlowField.ownerAt(ix, iz) == part then
				return true
			end
		end
	end
	return false
end

local function onHit(part: BasePart, damage: number)
	if part:GetAttribute("Broken") == true then
		return
	end
	local remaining = health(part) - damage
	setHealth(part, remaining)
	if remaining <= 0 then
		breakBarricade(part)
	end
end

local function onRepair(part: BasePart, player: Player)
	local now = os.clock()
	if now - (lastRepair[player] or 0) < BARRICADE.repairCooldown then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	lastRepair[player] = now

	local amount = BARRICADE.maxHealth * BARRICADE.repairFraction
	if part:GetAttribute("Broken") == true then
		if zombieInGap(part) then
			return
		end
		part:SetAttribute("Broken", false)
		FlowField.setOwnerKind(part, FlowField.BREACH)
		setHealth(part, amount)
	else
		setHealth(part, health(part) + amount)
	end
end

local function setup(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local part = instance
	part:SetAttribute("MaxHealth", BARRICADE.maxHealth)
	part:SetAttribute("Health", BARRICADE.maxHealth)
	part:SetAttribute("Broken", false)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.HoldDuration = BARRICADE.repairHold
		prompt.Triggered:Connect(function(player)
			onRepair(part, player)
		end)
	end
	refresh(part)
end

function BarricadeService.start()
	HordeService.barricadeHit:connect(onHit)
	CollectionService:GetInstanceAddedSignal(Tags.Barricade):Connect(setup)
	for _, part in CollectionService:GetTagged(Tags.Barricade) do
		setup(part)
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRepair[player] = nil
	end)
end

return BarricadeService
