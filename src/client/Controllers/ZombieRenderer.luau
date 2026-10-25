--!strict
-- Draws the server's zombie snapshots. Three LOD tiers, all pooled and moved in one
-- workspace:BulkMoveTo per frame (never created/destroyed while playing):
--   near  — up to MAX_ANIMATED closest within NEAR_DISTANCE: the kind's low-poly rig
--           (Art/ZombieRigs) with a procedural walk/attack cycle; pooled per kind. Each part
--           uses the matching Blender mesh from ReplicatedStorage.Assets.Zombies
--           (tools/blender/zombies.py) when the place has it, a plain block otherwise
--   mid   — single block in the zombie's shirt colour, up to FAR_DISTANCE
--   none  — beyond that the corn and fog hide them anyway
-- Positions are interpolated between 10 Hz snapshots, so motion stays smooth at any FPS.
-- Hit zombies flinch; killed ones that were drawn as rigs fall over before returning to the
-- pool (capped at MAX_CORPSES).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local ZombiePacket = require(Shared.ZombiePacket)
local ZombieRigs = require(Shared.Art.ZombieRigs)
local HeroRigs = require(Shared.Art.HeroRigs)
local Signal = require(Shared.Util.Signal)
local Effects = require(script.Parent.Parent.Effects)

local LOD = Config.CLIENT_ZOMBIES
local SNAPSHOT_DT = 1 / Config.HORDE.REPLICATION_HZ
local HIDDEN = CFrame.new(0, -1000, 0)

type Tier = "none" | "mid" | "near"

-- A pooled set of parts for one kind; `specs` says how each part is posed and painted.
type Rig = {
	kind: Types.ZombieKind,
	parts: { BasePart },
	specs: { ZombieRigs.PartSpec },
	pivots: { [ZombieRigs.Role]: Vector3 },
}

local FLINCH_TIME = 0.18
local FLINCH_ANGLE = math.rad(22)
local CORPSE_FALL = 0.35
local CORPSE_LIE = 2.5
local CORPSE_SINK = 0.8
local MAX_CORPSES = 16

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
	variant: ZombieRigs.Variant,
	tier: Tier,
	near: Rig?,
	mid: BasePart?,
}

local ZombieRenderer = {}

-- A Creeper lit its fuse at this position (audio plays the hiss).
ZombieRenderer.fuseLit = Signal.new() :: Signal.Signal<Vector3>

local entries: { [number]: Entry } = {}
-- Ids removed recently. Snapshots are unreliable and removals reliable, so a snapshot can
-- arrive after the removal; without this the dead zombie would pop back for a second.
local removedAt: { [number]: number } = {}
local container: Folder
local nearPools: { [Types.ZombieKind]: { Rig } } = {}
local midPool: { BasePart } = {}
-- `root` is on the ground; zombies killed up on a pile drop from `height` as they fall.
type Corpse = { rig: Rig, root: CFrame, height: number, kind: number, diedAt: number }
local corpses: { Corpse } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function newPart(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material
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

-- Blender meshes by name ("Zombie_Torso"…); left/right and lettered parts share one mesh.
local meshTemplates: { [string]: MeshPart } = {}
local MESH_ALIASES: { [string]: string } = {
	LegL = "Leg",
	LegR = "Leg",
	ArmL = "Arm",
	ArmR = "Arm",
	SleeveL = "Sleeve",
	SleeveR = "Sleeve",
	PlateL = "Plate",
	PlateR = "Plate",
	FistL = "Fist",
	FistR = "Fist",
	TrapL = "Trap",
	TrapR = "Trap",
	PustuleA = "Pustule",
	PustuleB = "Pustule",
	PustuleC = "Pustule",
}

-- Hero meshes (tools/blender/zombie_heroes.py), imported into Assets.Heroes. A kind uses its
-- hero rig only when every part's mesh is present; otherwise the block/part rig above.
local heroTemplates: { [string]: MeshPart } = {}
local heroKinds: { [Types.ZombieKind]: boolean } = {}

local function loadMeshTemplates()
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Zombies")
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("MeshPart") then
				meshTemplates[d.Name] = d
			end
		end
	end
	local heroes = assets and assets:FindFirstChild("Heroes")
	if heroes then
		for _, d in heroes:GetDescendants() do
			if d:IsA("MeshPart") then
				heroTemplates[d.Name] = d
			end
		end
	end
	for kind, rig in HeroRigs.RIGS do
		local complete = true
		for _, spec in rig.parts do
			if not heroTemplates[spec.mesh :: string] then
				complete = false
				break
			end
		end
		heroKinds[kind] = complete
	end
end

-- A pooled rig part: the Blender mesh for this spec if imported, else a block/ball.
local function rigPart(spec: ZombieRigs.PartSpec): BasePart
	local template = if spec.mesh
		then heroTemplates[spec.mesh]
		else meshTemplates["Zombie_" .. (MESH_ALIASES[spec.name] or spec.name)]
	if not template then
		return newPart(
			spec.name,
			spec.size,
			Color3.new(),
			ZombieRigs.material(spec.tone),
			spec.shape
		)
	end
	local p = template:Clone()
	for _, child in p:GetChildren() do
		child:Destroy()
	end
	p.Name = spec.name
	p.Size = spec.size
	p.Material = spec.material or ZombieRigs.material(spec.tone)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.CFrame = HIDDEN
	p.Parent = container
	return p
end

local function kindName(kind: number): Types.ZombieKind
	return Config.ZOMBIE_KINDS_BY_ID[kind] or "Runner"
end

local function acquireNear(kind: Types.ZombieKind): Rig
	local pool = nearPools[kind]
	local rig = pool and table.remove(pool)
	if rig then
		return rig
	end
	local hero = if heroKinds[kind] then HeroRigs.RIGS[kind] else nil
	local specs = if hero then hero.parts else ZombieRigs.RIGS[kind]
	local parts = table.create(#specs) :: { BasePart }
	for _, spec in specs do
		table.insert(parts, rigPart(spec))
	end
	return {
		kind = kind,
		parts = parts,
		specs = specs,
		pivots = if hero then hero.pivots else ZombieRigs.PIVOTS,
	}
end

local function releaseRig(rig: Rig)
	for _, p in rig.parts do
		table.insert(moveParts, p)
		table.insert(moveCFrames, HIDDEN)
	end
	local pool = nearPools[rig.kind]
	if pool then
		table.insert(pool, rig)
	else
		nearPools[rig.kind] = { rig }
	end
end

-- Rigs are reused between zombies of a kind, so each is repainted with its new owner's outfit.
local function paintRig(rig: Rig, variant: ZombieRigs.Variant)
	for i, spec in rig.specs do
		rig.parts[i].Color = ZombieRigs.partColor(spec, variant, rig.kind)
	end
end

local function acquireMid(): BasePart
	local part = table.remove(midPool)
	if part then
		return part
	end
	-- No lights or extra parts here: at 100+ instances even a SurfaceLight each is too costly.
	return newPart("ZombieMid", Vector3.new(1.8, 5, 1), Color3.new(), Enum.Material.SmoothPlastic)
end

local function release(entry: Entry)
	local near = entry.near
	if near then
		releaseRig(near)
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
		local rig = acquireNear(kindName(entry.kind))
		paintRig(rig, entry.variant)
		entry.near = rig
	elseif tier == "mid" then
		local mid = acquireMid()
		mid.Color = entry.variant.shirt
		entry.mid = mid
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
			if state == ZombiePacket.STATE_FUSE and entry.state ~= state then
				ZombieRenderer.fuseLit:fire(position)
			end
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
				variant = ZombieRigs.variant(kindName(kind), id),
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
		if item.dist <= LOD.NEAR_DISTANCE and animated < budget then
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

-- How many zombies are within `radius` studs of `point` (drives the horde ambience).
function ZombieRenderer.countNear(point: Vector3, radius: number): number
	local count = 0
	local radiusSq = radius * radius
	for _, entry in entries do
		local offset = entry.to - point
		if offset:Dot(offset) <= radiusSq then
			count += 1
		end
	end
	return count
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
					root = CFrame.new(position.X, 0, position.Z)
						* CFrame.Angles(0, currentYaw(entry), 0),
					height = position.Y,
					kind = entry.kind,
					diedAt = now,
				})
			end
		end
		removedAt[id] = now
		removeEntry(id)
	end
end

-- Places every rig part relative to `base` (the feet, facing -Z): legs swing around the
-- hips, arms around the shoulders, body and head bob.
local function poseRig(
	rig: Rig,
	base: CFrame,
	scale: number,
	legSwing: number,
	armSwing: number,
	armRaise: number, -- both arms up together (climbing, grabbing the wall)
	bob: number,
	rightRaise: number? -- extra lift on the right arm only (Brute holding a rock up)
)
	local lift = CFrame.new(0, bob, 0)
	for i, spec in rig.specs do
		local part = rig.parts[i]
		local role = spec.role
		local offset = spec.offset * scale
		local cf: CFrame
		if role == "Body" or role == "Head" then
			cf = base * lift * CFrame.new(offset)
		else
			local pivot = rig.pivots[role] * scale
			local angle: number
			if role == "LegL" then
				angle = legSwing
			elseif role == "LegR" then
				angle = -legSwing
			elseif role == "ArmL" then
				angle = armRaise + armSwing
			else
				angle = armRaise - armSwing + (rightRaise or 0)
			end
			-- Arms ride the body's bob; legs stay planted.
			local origin = if role == "ArmL" or role == "ArmR" then base * lift else base
			cf = origin
				* CFrame.new(pivot)
				* CFrame.Angles(angle, 0, 0)
				* CFrame.new(offset - pivot)
		end
		local size = spec.size * scale
		if part.Size ~= size then
			part.Size = size
		end
		table.insert(moveParts, part)
		table.insert(moveCFrames, cf)
	end
end

local function poseNear(entry: Entry, rig: Rig, root: CFrame, t: number)
	local state = entry.state
	local cycle = t * 9 + entry.phase
	local legSwing, armSwing, armRaise, bob, lean = 0, math.sin(cycle) * 0.12, 0, 0, 0
	local rightRaise = 0
	local shake = Vector3.zero
	if state == ZombiePacket.STATE_WALK then
		legSwing = math.sin(cycle) * 0.7
		bob = math.abs(math.sin(cycle)) * 0.25
	elseif state == ZombiePacket.STATE_ATTACK then
		armSwing = math.sin(t * 12 + entry.phase) * 0.6
	elseif state == ZombiePacket.STATE_PILE then
		-- Clawing at the wall: leaning in, arms up, legs scrabbling.
		legSwing = math.sin(t * 3 + entry.phase) * 0.15
		armSwing = math.sin(t * 6 + entry.phase) * 0.3
		armRaise, lean = 1.4, -0.35
	elseif state == ZombiePacket.STATE_CLIMB then
		legSwing = math.sin(t * 16 + entry.phase) * 0.9
		armSwing = math.sin(t * 16 + entry.phase) * 0.5
		armRaise, lean = 1.2, -0.2
	elseif state == ZombiePacket.STATE_CHARGE then
		-- Head down, arms back, legs pumping.
		legSwing = math.sin(t * 18 + entry.phase) * 0.9
		armRaise, lean = -0.6, -0.45
	elseif state == ZombiePacket.STATE_WINDUP then
		if rig.kind == "Brute" then
			rightRaise, lean = 2.6, 0.12 -- rock held high: the throw telegraph
		else
			-- Bull scraping the ground before a charge.
			legSwing = math.max(0, math.sin(t * 10)) * 0.6
			lean = -0.3
		end
	elseif state == ZombiePacket.STATE_FUSE then
		-- Creeper about to blow: trembling, belly and pustules flashing red.
		local s = 0.08 * kindScale(entry.kind)
		shake = Vector3.new((math.random() - 0.5) * s, 0, (math.random() - 0.5) * s)
		armRaise = 0.4
		local flash = math.sin(t * 30) > 0
		for i, spec in rig.specs do
			if spec.tone == "glow" or spec.glow or spec.name == "Belly" then
				rig.parts[i].Color = if flash
					then ZombieRigs.FUSE_COLOR
					else ZombieRigs.partColor(spec, entry.variant, rig.kind)
			end
		end
	end
	-- Hit reaction: snap back from the feet and recover.
	local flinch = math.max(0, 1 - (t - entry.hitAt) / FLINCH_TIME)
	local base = root * CFrame.new(shake) * CFrame.Angles(lean + flinch * FLINCH_ANGLE, 0, 0)
	poseRig(rig, base, kindScale(entry.kind), legSwing, armSwing, armRaise, bob, rightRaise)
end

-- Dead rigs fall on their back, lie still, then sink into the ground and go back to the pool.
local function poseCorpses(t: number)
	for i = #corpses, 1, -1 do
		local corpse = corpses[i]
		local age = t - corpse.diedAt
		if age >= CORPSE_FALL + CORPSE_LIE + CORPSE_SINK then
			releaseRig(corpse.rig)
			corpses[i] = corpses[#corpses]
			corpses[#corpses] = nil
		else
			local scale = kindScale(corpse.kind)
			local fall = math.min(1, age / CORPSE_FALL)
			fall *= fall -- accelerate like gravity
			local sink = math.max(0, age - CORPSE_FALL - CORPSE_LIE) / CORPSE_SINK * 2 * scale
			-- Lifting by half the torso depth keeps the back on the ground once flat.
			local base = corpse.root
				* CFrame.new(0, corpse.height * (1 - fall) + fall * 0.5 * scale - sink, 0)
				* CFrame.Angles(fall * math.rad(88), 0, 0)
			poseRig(corpse.rig, base, scale, fall * 0.2, fall * 0.4, 0, 0)
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
	loadMeshTemplates()
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
