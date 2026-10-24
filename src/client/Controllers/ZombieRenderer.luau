--!strict
-- Draws the server's zombie snapshots. Three LOD tiers, all pooled and moved in one
-- workspace:BulkMoveTo per frame (never created/destroyed while playing):
--   near  — up to MAX_ANIMATED closest within NEAR_DISTANCE: 7-part greybox rig with a
--           procedural walk/attack cycle
--   mid   — single block with glowing eyes, up to FAR_DISTANCE
--   none  — beyond that the corn and fog hide them anyway
-- Positions are interpolated between 10 Hz snapshots, so motion stays smooth at any FPS.
-- Hit zombies flinch; killed ones that were drawn as rigs fall over before returning to the
-- pool (capped at MAX_CORPSES).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local ZombiePacket = require(Shared.ZombiePacket)
local Effects = require(script.Parent.Parent.Effects)

local LOD = Config.CLIENT_ZOMBIES
local SNAPSHOT_DT = 1 / Config.HORDE.REPLICATION_HZ
local HIDDEN = CFrame.new(0, -1000, 0)

local COLOR_SKIN = Color3.fromRGB(122, 132, 110)
local COLOR_CLOTHES = Color3.fromRGB(84, 92, 62)
local COLOR_EYES = Color3.fromRGB(255, 120, 20)

type Tier = "none" | "mid" | "near"

-- Near rig part order; offsets are relative to the zombie's feet, facing -Z.
local RIG = {
	{
		name = "Torso",
		size = Vector3.new(1.8, 2, 1),
		offset = Vector3.new(0, 3, 0),
		color = COLOR_CLOTHES,
	},
	{
		name = "Head",
		size = Vector3.new(1.2, 1.2, 1.2),
		offset = Vector3.new(0, 4.6, -0.2),
		color = COLOR_SKIN,
	},
	{
		name = "Eyes",
		size = Vector3.new(0.9, 0.22, 0.1),
		offset = Vector3.new(0, 4.75, -0.82),
		color = COLOR_EYES,
	},
	{
		name = "ArmL",
		size = Vector3.new(0.5, 0.5, 2),
		offset = Vector3.new(-1.15, 3.7, -0.9),
		color = COLOR_SKIN,
	},
	{
		name = "ArmR",
		size = Vector3.new(0.5, 0.5, 2),
		offset = Vector3.new(1.15, 3.7, -0.9),
		color = COLOR_SKIN,
	},
	{
		name = "LegL",
		size = Vector3.new(0.7, 2, 0.7),
		offset = Vector3.new(-0.45, 1, 0),
		color = COLOR_CLOTHES,
	},
	{
		name = "LegR",
		size = Vector3.new(0.7, 2, 0.7),
		offset = Vector3.new(0.45, 1, 0),
		color = COLOR_CLOTHES,
	},
}
local HIP_Y = 2
local FLINCH_TIME = 0.18
local FLINCH_ANGLE = math.rad(22)
local CORPSE_FALL = 0.35
local CORPSE_LIE = 2.5
local CORPSE_SINK = 0.8
local MAX_CORPSES = 16
local SHOULDER = Vector3.new(0, 3.7, 0)

type Entry = {
	id: number,
	kind: number,
	state: number,
	from: Vector3,
	to: Vector3,
	fromYaw: number,
	toYaw: number,
	alpha: number,
	lastSeen: number,
	phase: number, -- walk-cycle offset so the horde doesn't march in lockstep
	hitAt: number,
	tier: Tier,
	near: { BasePart }?,
	mid: BasePart?,
}

local ZombieRenderer = {}

local entries: { [number]: Entry } = {}
-- Ids removed recently. Snapshots are unreliable and removals reliable, so a snapshot can
-- arrive after the removal; without this the dead zombie would pop back for a second.
local removedAt: { [number]: number } = {}
local container: Folder
local nearPool: { { BasePart } } = {}
local midPool: { BasePart } = {}
type Corpse = { rig: { BasePart }, root: CFrame, kind: number, diedAt: number }
local corpses: { Corpse } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function newPart(name: string, size: Vector3, color: Color3, neon: boolean): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = HIDDEN
	p.Parent = container
	return p
end

local function acquireNear(): { BasePart }
	local rig = table.remove(nearPool)
	if rig then
		return rig
	end
	local parts = {}
	for _, spec in RIG do
		table.insert(parts, newPart(spec.name, spec.size, spec.color, spec.name == "Eyes"))
	end
	return parts
end

local function acquireMid(): BasePart
	local part = table.remove(midPool)
	if part then
		return part
	end
	-- No lights or extra parts here: at 100+ instances even a SurfaceLight each is too costly.
	local body = newPart("ZombieMid", Vector3.new(1.8, 5, 1), COLOR_CLOTHES, false)
	return body
end

local function release(entry: Entry)
	local near = entry.near
	if near then
		for _, p in near do
			table.insert(moveParts, p)
			table.insert(moveCFrames, HIDDEN)
		end
		table.insert(nearPool, near)
		entry.near = nil
	end
	local mid = entry.mid
	if mid then
		table.insert(moveParts, mid)
		table.insert(moveCFrames, HIDDEN)
		table.insert(midPool, mid)
		entry.mid = nil
	end
	entry.tier = "none"
end

local function setTier(entry: Entry, tier: Tier)
	if entry.tier == tier then
		return
	end
	release(entry)
	entry.tier = tier
	if tier == "near" then
		entry.near = acquireNear()
	elseif tier == "mid" then
		entry.mid = acquireMid()
	end
end

local function removeEntry(id: number)
	local entry = entries[id]
	if entry then
		release(entry)
		entries[id] = nil
	end
end

local function lerpAngle(a: number, b: number, t: number): number
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + diff * t
end

local function currentPosition(entry: Entry): Vector3
	return entry.from:Lerp(entry.to, entry.alpha)
end

local function currentYaw(entry: Entry): number
	return lerpAngle(entry.fromYaw, entry.toYaw, entry.alpha)
end

local function onSnapshot(b: buffer)
	if typeof(b) ~= "buffer" then
		return
	end
	local now = os.clock()
	ZombiePacket.decode(b, function(id, kind, state, position, yaw)
		local removed = removedAt[id]
		if removed then
			if now - removed < LOD.STALE_TIMEOUT * 2 then
				return
			end
			removedAt[id] = nil -- old enough: the id has been reused by a new zombie
		end
		local entry = entries[id]
		if entry then
			entry.from = currentPosition(entry)
			entry.fromYaw = currentYaw(entry)
			entry.to = position
			entry.toYaw = yaw
			entry.alpha = 0
			entry.state = state
			entry.kind = kind
			entry.lastSeen = now
		else
			entries[id] = {
				id = id,
				kind = kind,
				state = state,
				from = position,
				to = position,
				fromYaw = yaw,
				toYaw = yaw,
				alpha = 1,
				lastSeen = now,
				phase = math.random() * math.pi * 2,
				hitAt = -math.huge,
				tier = "none",
			}
		end
	end)
end

local function viewerPosition(): Vector3
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return workspace.CurrentCamera.CFrame.Position
end

-- Picks tiers: nearest MAX_ANIMATED inside NEAR_DISTANCE get rigs, the rest within
-- FAR_DISTANCE get blocks. Also drops entries the server stopped sending.
local function assignLods()
	local now = os.clock()
	local viewer = viewerPosition()
	local sorted: { { entry: Entry, dist: number } } = {}
	for id, entry in entries do
		if now - entry.lastSeen > LOD.STALE_TIMEOUT then
			removeEntry(id)
		else
			table.insert(
				sorted,
				{ entry = entry, dist = (currentPosition(entry) - viewer).Magnitude }
			)
		end
	end
	for id, removed in removedAt do
		if now - removed >= LOD.STALE_TIMEOUT * 2 then
			removedAt[id] = nil
		end
	end
	table.sort(sorted, function(a, b)
		return a.dist < b.dist
	end)

	local animated = 0
	for _, item in sorted do
		local tier: Tier = "none"
		if item.dist <= LOD.NEAR_DISTANCE and animated < LOD.MAX_ANIMATED then
			tier = "near"
			animated += 1
		elseif item.dist <= LOD.FAR_DISTANCE then
			tier = "mid"
		end
		setTier(item.entry, tier)
	end
end

local function kindScale(kind: number): number
	local name = Config.ZOMBIE_KINDS_BY_ID[kind]
	return if name then Config.ZOMBIES[name].scale else 1
end

-- Local hit feedback; the server still decides the damage.
function ZombieRenderer.flinch(id: number)
	local entry = entries[id]
	if entry then
		entry.hitAt = os.clock()
	end
end

-- Visits every zombie at its rendered (interpolated) position. Weapons hit-test against this,
-- so what the player sees is what they hit.
function ZombieRenderer.forEach(visit: (id: number, feet: Vector3, scale: number) -> ())
	for id, entry in entries do
		visit(id, currentPosition(entry), kindScale(entry.kind))
	end
end

local function onRemoved(ids: { number })
	local now = os.clock()
	for _, id in ids do
		local entry = entries[id]
		if entry then
			local position = currentPosition(entry)
			Effects.blood(position + Vector3.new(0, 3 * kindScale(entry.kind), 0), 14)
			-- Hand the drawn rig to a corpse instead of the pool; far zombies just vanish.
			local rig = entry.near
			if rig and #corpses < MAX_CORPSES then
				entry.near = nil
				table.insert(corpses, {
					rig = rig,
					root = CFrame.new(position) * CFrame.Angles(0, currentYaw(entry), 0),
					kind = entry.kind,
					diedAt = now,
				})
			end
		end
		removedAt[id] = now
		removeEntry(id)
	end
end

-- Places the 7 rig parts relative to `base` (the feet, facing -Z).
local function poseRig(
	rig: { BasePart },
	base: CFrame,
	scale: number,
	legSwing: number,
	armSwing: number,
	bob: number
)
	for i, spec in RIG do
		local part = rig[i]
		local offset = spec.offset * scale
		local cf: CFrame
		if spec.name == "LegL" or spec.name == "LegR" then
			local sign = if spec.name == "LegL" then 1 else -1
			local hip = Vector3.new(offset.X, HIP_Y * scale, 0)
			cf = base
				* CFrame.new(hip)
				* CFrame.Angles(legSwing * sign, 0, 0)
				* CFrame.new(0, -HIP_Y * scale / 2, 0)
		elseif spec.name == "ArmL" or spec.name == "ArmR" then
			local sign = if spec.name == "ArmL" then 1 else -1
			local shoulder = Vector3.new(offset.X, SHOULDER.Y * scale + bob, 0)
			cf = base
				* CFrame.new(shoulder)
				* CFrame.Angles(armSwing * sign, 0, 0)
				* CFrame.new(0, 0, offset.Z)
		else
			cf = base * CFrame.new(offset + Vector3.new(0, bob, 0))
		end
		if part.Size ~= spec.size * scale then
			part.Size = spec.size * scale
		end
		table.insert(moveParts, part)
		table.insert(moveCFrames, cf)
	end
end

local function poseNear(entry: Entry, rig: { BasePart }, root: CFrame, t: number)
	local walking = entry.state == ZombiePacket.STATE_WALK
	local attacking = entry.state == ZombiePacket.STATE_ATTACK
	local cycle = t * 9 + entry.phase
	local legSwing = if walking then math.sin(cycle) * 0.7 else 0
	local armSwing = if attacking
		then math.sin(t * 12 + entry.phase) * 0.6
		else math.sin(cycle) * 0.12
	local bob = if walking then math.abs(math.sin(cycle)) * 0.25 else 0
	-- Hit reaction: snap back from the feet and recover.
	local flinch = math.max(0, 1 - (t - entry.hitAt) / FLINCH_TIME)
	local base = root * CFrame.Angles(flinch * FLINCH_ANGLE, 0, 0)
	poseRig(rig, base, kindScale(entry.kind), legSwing, armSwing, bob)
end

-- Dead rigs fall on their back, lie still, then sink into the ground and go back to the pool.
local function poseCorpses(t: number)
	for i = #corpses, 1, -1 do
		local corpse = corpses[i]
		local age = t - corpse.diedAt
		if age >= CORPSE_FALL + CORPSE_LIE + CORPSE_SINK then
			for _, part in corpse.rig do
				table.insert(moveParts, part)
				table.insert(moveCFrames, HIDDEN)
			end
			table.insert(nearPool, corpse.rig)
			corpses[i] = corpses[#corpses]
			corpses[#corpses] = nil
		else
			local scale = kindScale(corpse.kind)
			local fall = math.min(1, age / CORPSE_FALL)
			fall *= fall -- accelerate like gravity
			local sink = math.max(0, age - CORPSE_FALL - CORPSE_LIE) / CORPSE_SINK * 2 * scale
			-- Lifting by half the torso depth keeps the back on the ground once flat.
			local base = corpse.root
				* CFrame.new(0, fall * 0.5 * scale - sink, 0)
				* CFrame.Angles(fall * math.rad(88), 0, 0)
			poseRig(corpse.rig, base, scale, fall * 0.2, fall * 0.4, 0)
		end
	end
end

local function render(dt: number)
	local t = os.clock()
	for _, entry in entries do
		entry.alpha = math.min(1, entry.alpha + dt / SNAPSHOT_DT)
		if entry.tier ~= "none" then
			local root = CFrame.new(currentPosition(entry)) * CFrame.Angles(0, currentYaw(entry), 0)
			local near, mid = entry.near, entry.mid
			if near then
				poseNear(entry, near, root, t)
			elseif mid then
				local scale = kindScale(entry.kind)
				table.insert(moveParts, mid)
				table.insert(moveCFrames, root * CFrame.new(0, 2.5 * scale, 0))
			end
		end
	end

	poseCorpses(t)

	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(moveParts)
		table.clear(moveCFrames)
	end
end

function ZombieRenderer.init()
	container = Instance.new("Folder")
	container.Name = "ZombiesClient"
	container.Parent = workspace
end

function ZombieRenderer.start()
	Net.zombieState().OnClientEvent:Connect(onSnapshot)
	Net.zombieRemoved().OnClientEvent:Connect(function(ids: { number })
		if typeof(ids) == "table" then
			onRemoved(ids)
		end
	end)

	local lodAccumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		lodAccumulator += dt
		if lodAccumulator >= LOD.LOD_INTERVAL then
			lodAccumulator = 0
			assignLods()
		end
		render(dt)
	end)
end

return ZombieRenderer
