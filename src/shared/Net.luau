--!strict
-- Remote registry. The server creates every remote on first access; clients wait for them.
-- Names are listed once here so both sides can't drift.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local function folder(): Instance
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		return existing
	end
	if not IS_SERVER then
		return ReplicatedStorage:WaitForChild("Remotes")
	end
	local f = Instance.new("Folder")
	f.Name = "Remotes"
	f.Parent = ReplicatedStorage
	return f
end

local function get(name: string, className: string): Instance
	local parent = folder()
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	if not IS_SERVER then
		return parent:WaitForChild(name)
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local Net = {}

-- Server → clients, 10 Hz, buffer from ZombiePacket. Unreliable: a lost packet is replaced
-- by the next one 100 ms later.
function Net.zombieState(): UnreliableRemoteEvent
	return get("ZombieState", "UnreliableRemoteEvent") :: UnreliableRemoteEvent
end

-- Server → clients, reliable: { number } ids of zombies that died/despawned.
function Net.zombieRemoved(): RemoteEvent
	return get("ZombieRemoved", "RemoteEvent") :: RemoteEvent
end

-- Client → server: (shotSeq: number, hits: { { id: number, head: boolean } }). One per shot,
-- misses included, so the server's ammo count follows the client's.
function Net.fireWeapon(): RemoteEvent
	return get("FireWeapon", "RemoteEvent") :: RemoteEvent
end

-- Client → server, no payload.
function Net.reload(): RemoteEvent
	return get("Reload", "RemoteEvent") :: RemoteEvent
end

-- Client → server, no payload. The server finds the targets itself.
function Net.melee(): RemoteEvent
	return get("Melee", "RemoteEvent") :: RemoteEvent
end

-- Client → server: (direction: Vector3, unit).
function Net.throwGrenade(): RemoteEvent
	return get("ThrowGrenade", "RemoteEvent") :: RemoteEvent
end

-- Server → client: authoritative WeaponState. Client → server (no payload): request one.
function Net.weaponSync(): RemoteEvent
	return get("WeaponSync", "RemoteEvent") :: RemoteEvent
end

-- Client → server: (classId: string). Only during a Prep phase.
function Net.selectClass(): RemoteEvent
	return get("SelectClass", "RemoteEvent") :: RemoteEvent
end

-- Client → server: (aim: Vector3, unit camera direction for thrown abilities).
function Net.useAbility(): RemoteEvent
	return get("UseAbility", "RemoteEvent") :: RemoteEvent
end

-- Client → server: (itemId: string), from Config.SHOP.
function Net.purchase(): RemoteEvent
	return get("Purchase", "RemoteEvent") :: RemoteEvent
end

-- Server → client: (message: string) shown as a short toast.
function Net.notify(): RemoteEvent
	return get("Notify", "RemoteEvent") :: RemoteEvent
end

-- Server → clients, unreliable: (from: Vector3, to: Vector3) tracer for a turret shot.
function Net.turretShot(): UnreliableRemoteEvent
	return get("TurretShot", "UnreliableRemoteEvent") :: UnreliableRemoteEvent
end

-- Server → clients, unreliable: (shooter: Player, gun: string) so others hear a shot.
function Net.shotFx(): UnreliableRemoteEvent
	return get("ShotFx", "UnreliableRemoteEvent") :: UnreliableRemoteEvent
end

return Net
