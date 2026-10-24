--!strict
-- Client side of combat. Shots are raycast from the crosshair against the zombies as they are
-- drawn (ZombieRenderer positions), so hits feel instant; the server re-validates each claim.
-- Ammo is predicted locally and reconciled with server syncs via the shot sequence number:
-- shown mag = server mag − shots the server hasn't processed yet.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Hitscan = require(Shared.Hitscan)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local InputController = require(script.Parent.InputController)
local ZombieRenderer = require(script.Parent.ZombieRenderer)
local Effects = require(script.Parent.Parent.Effects)

local WeaponController = {}

export type View = {
	ready: boolean,
	gun: Config.GunName,
	melee: Config.MeleeName,
	mag: number,
	reserve: number,
	grenades: number,
	reloading: boolean,
}

-- What the HUD shows. Read-only outside this module.
WeaponController.view = {
	ready = false,
	gun = Config.CLASSES[Config.DEFAULT_CLASS].startGun,
	melee = Config.LOADOUT.melee,
	mag = 0,
	reserve = 0,
	grenades = 0,
	reloading = false,
} :: View

WeaponController.changed = Signal.new() :: Signal.Signal<()>
-- Fired on a confirmed-looking local hit; the argument is true for headshots.
WeaponController.hit = Signal.new() :: Signal.Signal<boolean>

local view = WeaponController.view
local player = Players.LocalPlayer
local shotSeq = 0
local nextShot = 0
local nextMelee = 0
local nextGrenade = 0
local reloadWatchdog = 0

local ASSIST_COS = math.cos(math.rad(Config.AIM_ASSIST_DEGREES))
local COLOR_INCENDIARY = Color3.fromRGB(255, 90, 20)
local COLOR_TURRET = Color3.fromRGB(120, 230, 255)

local function incendiaryActive(): boolean
	local untilTime = player:GetAttribute("IncendiaryUntil")
	return typeof(untilTime) == "number" and workspace:GetServerTimeNow() < untilTime
end

type Body = { root: BasePart, head: BasePart }

local function body(): Body?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if
		humanoid
		and humanoid.Health > 0
		and root
		and root:IsA("BasePart")
		and head
		and head:IsA("BasePart")
	then
		return { root = root, head = head }
	end
	return nil
end

local function onSync(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local state = payload :: Types.WeaponState
	local gun = state.gun :: Config.GunName
	local melee = state.melee :: Config.MeleeName
	if not Config.GUNS[gun] or not Config.MELEE[melee] then
		return
	end
	local pending = if Config.DEBUG.infiniteAmmo then 0 else math.max(0, shotSeq - state.shotSeq)
	view.gun = gun
	view.melee = melee
	view.mag = math.max(0, state.mag - pending)
	view.reserve = state.reserve
	view.grenades = state.grenades
	view.reloading = state.reloading
	view.ready = true
	WeaponController.changed:fire()
end

local function centerRay(): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	local size = camera.ViewportSize
	local ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	return ray.Origin, ray.Direction.Unit
end

local function withSpread(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local roll = math.random() * math.pi * 2
	local tilt = math.rad(degrees) * math.sqrt(math.random())
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, roll) * CFrame.Angles(
		tilt,
		0,
		0
	)).LookVector
end

-- Resolves one ray. The camera sits behind the shoulder, so distances are measured from where
-- the ray passes the player's head (`minT`); range and walls count from there.
local function cast(
	origin: Vector3,
	direction: Vector3,
	me: Body,
	range: number,
	assist: boolean
): (Vector3, number?, boolean)
	local minT = math.max(0, (me.head.Position - origin):Dot(direction))
	local wallT = minT + Hitscan.mapDistance(origin + direction * minT, direction, range)

	local bestT, bestId, bestHead = wallT, nil :: number?, false
	ZombieRenderer.forEach(function(id, feet, scale)
		local t, isHead = Hitscan.rayZombie(origin, direction, bestT, feet, scale)
		if t and t >= minT - 2 and t < bestT then
			bestT, bestId, bestHead = t, id, isHead
		end
	end)
	if bestId or not assist then
		return origin + direction * bestT, bestId, bestHead
	end

	-- Touch aim assist: the zombie closest to the crosshair inside the cone, if visible.
	local eye = me.head.Position
	local assistCos, assistId, assistPoint = ASSIST_COS, nil :: number?, nil :: Vector3?
	ZombieRenderer.forEach(function(id, feet, scale)
		local chest = feet + Vector3.new(0, Hitscan.CHEST_HEIGHT * scale, 0)
		local toChest = chest - origin
		local along = toChest:Dot(direction)
		if along > minT and (chest - eye).Magnitude <= range then
			local cos = along / toChest.Magnitude
			if cos >= assistCos then
				assistCos, assistId, assistPoint = cos, id, chest
			end
		end
	end)
	if assistId and assistPoint and Hitscan.clearLine(eye, assistPoint) then
		return assistPoint, assistId, false
	end
	return origin + direction * wallT, nil, false
end

local function requestReload()
	local gun = Config.GUNS[view.gun]
	if not view.ready or view.reloading or view.mag >= gun.magSize or view.reserve <= 0 then
		return
	end
	view.reloading = true
	reloadWatchdog = os.clock() + gun.reloadTime + 1.5
	Net.reload():FireServer()
	WeaponController.changed:fire()
end

local function fire(me: Body)
	local gun = Config.GUNS[view.gun]
	local now = os.clock()
	nextShot = now + 1 / gun.fireRate
	shotSeq += 1
	if not Config.DEBUG.infiniteAmmo then
		view.mag -= 1
	end

	local aiming = InputController.isDown("Aim")
	local spread = gun.spread * (if aiming then 0.5 else 1)
	local assist = InputController.autoFire and gun.pellets == 1
	local origin, center = centerRay()
	local gunPart = me.root.Parent and me.root.Parent:FindFirstChild("Gun")
	local muzzle = if gunPart and gunPart:IsA("BasePart")
		then gunPart.Position
		else me.head.Position

	local hits = {}
	local anyHit, anyHead = false, false
	local tracerColor = if incendiaryActive() then COLOR_INCENDIARY else nil
	for _ = 1, gun.pellets do
		local endPoint, id, isHead = cast(origin, withSpread(center, spread), me, gun.range, assist)
		Effects.tracer(muzzle, endPoint, tracerColor)
		if id then
			table.insert(hits, { id = id, head = isHead })
			Effects.blood(endPoint, 4)
			ZombieRenderer.flinch(id)
			anyHit = true
			anyHead = anyHead or isHead
		end
	end

	Net.fireWeapon():FireServer(shotSeq, hits)
	if anyHit then
		WeaponController.hit:fire(anyHead)
	end
	WeaponController.changed:fire()
	if view.mag <= 0 then
		requestReload()
	end
end

-- Auto-fire trigger: something hittable is under (or, with assist, near) the crosshair.
local function hasTarget(me: Body): boolean
	local gun = Config.GUNS[view.gun]
	local origin, center = centerRay()
	local _, id = cast(origin, center, me, gun.range, true)
	return id ~= nil
end

local function swing()
	local now = os.clock()
	local me = body()
	if not view.ready or not me or now < nextMelee then
		return
	end
	local melee = Config.MELEE[view.melee]
	nextMelee = now + melee.cooldown
	Net.melee():FireServer()
	Effects.swipe(me.root.CFrame, melee.range)

	-- Local hit check only drives feedback; the server decides the real targets.
	local look = me.root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local origin = Vector3.new(me.root.Position.X, 0, me.root.Position.Z)
	local cosArc = math.cos(math.rad(melee.arc / 2))
	local hit = false
	ZombieRenderer.forEach(function(id, feet, scale)
		local offset = Vector3.new(feet.X, 0, feet.Z) - origin
		local dist = offset.Magnitude
		if dist <= melee.range and (dist < 1.5 or forward:Dot(offset / dist) >= cosArc) then
			Effects.blood(feet + Vector3.new(0, 3 * scale, 0), 6)
			ZombieRenderer.flinch(id)
			hit = true
		end
	end)
	if hit then
		WeaponController.hit:fire(false)
	end
end

local function throwGrenade()
	local now = os.clock()
	if not view.ready or not body() or view.grenades < 1 or now < nextGrenade then
		return
	end
	nextGrenade = now + Config.GRENADE.cooldown
	if not Config.DEBUG.infiniteAmmo then
		view.grenades -= 1
	end
	Net.throwGrenade():FireServer(workspace.CurrentCamera.CFrame.LookVector)
	WeaponController.changed:fire()
end

local function step()
	if not view.ready then
		return
	end
	local now = os.clock()
	if view.reloading and now > reloadWatchdog then
		-- Lost the server's answer somehow; ask for the truth instead of staying stuck.
		view.reloading = false
		Net.weaponSync():FireServer()
		WeaponController.changed:fire()
	end
	if view.reloading or now < nextShot or InputController.isModalOpen() then
		return
	end
	local me = body()
	if not me then
		return
	end

	local wantsFire = InputController.isDown("Fire")
		or (InputController.autoFire and view.mag > 0 and hasTarget(me))
	if not wantsFire then
		return
	end
	if view.mag > 0 then
		fire(me)
	else
		requestReload()
	end
end

function WeaponController.start()
	Net.weaponSync().OnClientEvent:Connect(onSync)
	Net.turretShot().OnClientEvent:Connect(function(from: Vector3, to: Vector3)
		if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
			Effects.tracer(from, to, COLOR_TURRET)
		end
	end)
	Net.weaponSync():FireServer()

	InputController.actionChanged:connect(function(action, isDown)
		if not isDown or InputController.isModalOpen() then
			return
		end
		if action == "Reload" then
			requestReload()
		elseif action == "Melee" then
			swing()
		elseif action == "Grenade" then
			throwGrenade()
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return WeaponController
