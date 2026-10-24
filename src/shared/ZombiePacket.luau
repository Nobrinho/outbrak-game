--!strict
-- Binary format for zombie replication. 11 bytes per zombie:
--   u16 id | u8 kind | u8 state | i16 x | i16 y | i16 z (decistuds) | u8 yaw (256 steps)
-- Packets are capped so a single UnreliableRemoteEvent payload stays under its ~900 byte limit.

local ZombiePacket = {}

ZombiePacket.RECORD_SIZE = 11
ZombiePacket.MAX_PER_PACKET = 70

export type State = number
ZombiePacket.STATE_WALK = 0
ZombiePacket.STATE_ATTACK = 1
ZombiePacket.STATE_IDLE = 2
ZombiePacket.STATE_CLIMB = 3 -- running up a pile and over a wall
ZombiePacket.STATE_PILE = 4 -- part of a pyramid against a wall
ZombiePacket.STATE_CHARGE = 5 -- Bull mid-charge
ZombiePacket.STATE_FUSE = 6 -- Creeper about to explode
ZombiePacket.STATE_WINDUP = 7 -- Bull scraping before a charge, Brute with a rock raised

export type Record = {
	id: number,
	kind: number,
	state: number,
	position: Vector3,
	yaw: number, -- radians
}

local TAU = math.pi * 2

local function quantize(v: number): number
	return math.clamp(math.round(v * 10), -32768, 32767)
end

function ZombiePacket.encode(records: { Record }, first: number, last: number): buffer
	local b = buffer.create((last - first + 1) * ZombiePacket.RECORD_SIZE)
	local offset = 0
	for i = first, last do
		local r = records[i]
		buffer.writeu16(b, offset, r.id)
		buffer.writeu8(b, offset + 2, r.kind)
		buffer.writeu8(b, offset + 3, r.state)
		buffer.writei16(b, offset + 4, quantize(r.position.X))
		buffer.writei16(b, offset + 6, quantize(r.position.Y))
		buffer.writei16(b, offset + 8, quantize(r.position.Z))
		buffer.writeu8(b, offset + 10, math.round((r.yaw % TAU) / TAU * 256) % 256)
		offset += ZombiePacket.RECORD_SIZE
	end
	return b
end

-- Calls `visit` once per record. Malformed buffers (wrong length) are ignored entirely.
function ZombiePacket.decode(
	b: buffer,
	visit: (
		id: number,
		kind: number,
		state: number,
		position: Vector3,
		yaw: number
	) -> ()
)
	local len = buffer.len(b)
	if len % ZombiePacket.RECORD_SIZE ~= 0 then
		return
	end
	for offset = 0, len - 1, ZombiePacket.RECORD_SIZE do
		visit(
			buffer.readu16(b, offset),
			buffer.readu8(b, offset + 2),
			buffer.readu8(b, offset + 3),
			Vector3.new(
				buffer.readi16(b, offset + 4) / 10,
				buffer.readi16(b, offset + 6) / 10,
				buffer.readi16(b, offset + 8) / 10
			),
			buffer.readu8(b, offset + 10) / 256 * TAU
		)
	end
end

return ZombiePacket
