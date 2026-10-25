--!strict
-- Classes and their abilities (docs/DEFINICOES.md §4). The chosen class lives in the player's
-- "Class" attribute (CombatService reads it for loadout and bonuses). Abilities:
--   Gunslinger   — incendiary rounds: sets "IncendiaryUntil" (server time); CombatService
--                  makes hits burn while it lasts.
--   Exterminator — molotov: a thrown bottle that leaves a fire patch hurting zombies inside.
-- "AbilityReadyAt" (server time) drives the cooldown on the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local HordeService = require(script.Parent.HordeService)

local ClassService = {}

local FIRE_TICK = 0.25
local MOLOTOV_SPEED = 70
local MOLOTOV_LIFT = 25
local MOLOTOV_FLIGHT = 0.8

type FirePatch = {
	position: Vector3,
	radius: number,
	dps: number,
	endsAt: number,
	owner: Player,
	visual: BasePart,
}

local patches: { FirePatch } = {}
local projectiles: Folder

local function phase(): string
	local match = ReplicatedStorage:FindFirstChild("Match")
	local value = match and match:GetAttribute("Phase")
	return if typeof(value) == "string" then value else "Waiting"
end

local function classOf(player: Player): Config.ClassStats
	local id = player:GetAttribute("Class")
	return Config.CLASSES[id :: Types.ClassId] or Config.CLASSES[Config.DEFAULT_CLASS]
end

local function onSelectClass(player: Player, classId: unknown)
	if typeof(classId) ~= "string" or Config.CLASSES[classId :: Types.ClassId] == nil then
		return
	end
	-- Only in the lobby or between waves, so nobody swaps loadouts mid-fight.
	if phase() ~= "Prep" and phase() ~= "Lobby" and phase() ~= "Waiting" then
		return
	end
	if player:GetAttribute("Class") ~= classId then
		player:SetAttribute("Class", classId)
	end
end

local function startFire(owner: Player, position: Vector3, ability: Config.AbilityStats)
	local visual = Instance.new("Part")
	visual.Name = "FirePatch"
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanQuery = false
	visual.CanTouch = false
	visual.Shape = Enum.PartType.Cylinder
	visual.Size = Vector3.new(0.3, ability.radius * 2, ability.radius * 2)
	visual.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	visual.Color = Color3.fromRGB(255, 110, 30)
	visual.Material = Enum.Material.Neon
	visual.Transparency = 0.55
	local fire = Instance.new("Fire")
	fire.Size = ability.radius
	fire.Heat = 8
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(150, 30, 10)
	fire.Parent = visual
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 50)
	light.Range = ability.radius * 2.5
	light.Brightness = 3
	light.Parent = visual
	visual.Parent = projectiles

	table.insert(patches, {
		position = position,
		radius = ability.radius,
		dps = ability.fireDps,
		endsAt = os.clock() + ability.duration,
		owner = owner,
		visual = visual,
	})
end

local function throwMolotov(
	player: Player,
	head: BasePart,
	direction: Vector3,
	ability: Config.AbilityStats
)
	local bottle = Instance.new("Part")
	bottle.Name = "Molotov"
	bottle.Size = Vector3.new(0.5, 1, 0.5)
	bottle.Color = Color3.fromRGB(90, 130, 60)
	bottle.Material = Enum.Material.Glass
	bottle.CanCollide = false
	bottle.CanQuery = false
	bottle.CanTouch = false
	bottle.CFrame = CFrame.new(head.Position + direction * 2.5)
	bottle.AssemblyLinearVelocity = direction * MOLOTOV_SPEED + Vector3.new(0, MOLOTOV_LIFT, 0)
	bottle.Parent = projectiles
	bottle:SetNetworkOwner(nil)

	task.delay(MOLOTOV_FLIGHT, function()
		local position = bottle.Position
		bottle:Destroy()
		-- Settle the fire on whatever is below where the bottle broke.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace:FindFirstChild("Map") or workspace }
		local ground =
			workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
		startFire(
			player,
			if ground then ground.Position else Vector3.new(position.X, 0, position.Z),
			ability
		)
		HordeService.noise(position, 40, 2, nil)
	end)
end

local function onUseAbility(player: Player, aim: unknown)
	local now = workspace:GetServerTimeNow()
	local readyAt = player:GetAttribute("AbilityReadyAt")
	if typeof(readyAt) == "number" and now < readyAt then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
		return
	end

	local class = classOf(player)
	local ability = class.ability
	if ability.fireDps > 0 then
		if typeof(aim) ~= "Vector3" then
			return
		end
		local direction = aim :: Vector3
		local magnitude = direction.Magnitude
		if not (magnitude > 0.9 and magnitude < 1.1) then
			return -- also rejects NaN
		end
		throwMolotov(player, head, direction.Unit, ability)
	else
		player:SetAttribute("IncendiaryUntil", now + ability.duration)
	end
	player:SetAttribute("AbilityReadyAt", now + ability.cooldown)
end

local function tickFire(dt: number)
	local now = os.clock()
	for i = #patches, 1, -1 do
		local patch = patches[i]
		if now >= patch.endsAt then
			patch.visual:Destroy()
			table.remove(patches, i)
		else
			local damage = patch.dps * dt
			local attacker = if patch.owner.Parent then patch.owner else nil
			for _, zombie in HordeService.getZombies() do
				if not zombie.dead then
					local offset = zombie.position - patch.position
					if
						Vector3.new(offset.X, 0, offset.Z).Magnitude <= patch.radius
						and math.abs(offset.Y) < 4
					then
						HordeService.damage(zombie, damage, attacker)
					end
				end
			end
		end
	end
end

-- Removes every fire patch and resets cooldowns (new match). Classes are kept.
function ClassService.reset()
	for _, patch in patches do
		patch.visual:Destroy()
	end
	table.clear(patches)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("AbilityReadyAt", 0)
		player:SetAttribute("IncendiaryUntil", 0)
	end
end

function ClassService.init()
	projectiles = Instance.new("Folder")
	projectiles.Name = "Abilities"
	projectiles.Parent = workspace
end

function ClassService.start()
	Net.selectClass().OnServerEvent:Connect(onSelectClass)
	Net.useAbility().OnServerEvent:Connect(onUseAbility)

	local function setup(player: Player)
		if player:GetAttribute("Class") == nil then
			player:SetAttribute("Class", Config.DEFAULT_CLASS)
		end
		player:SetAttribute("AbilityReadyAt", 0)
		player:SetAttribute("IncendiaryUntil", 0)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= FIRE_TICK then
			tickFire(accumulator)
			accumulator = 0
		end
	end)
end

return ClassService
