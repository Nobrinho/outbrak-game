--!strict
-- Grid flow field shared by the whole horde. One BFS from every player's cell gives each cell
-- its distance to the nearest player; a zombie only looks at its 8 neighbours to pick a step.
-- Cost is O(cells) per recompute no matter how many zombies there are.
--
-- Cells are FREE, SOLID (walls, props) or BREACH (barricades and climb zones). BREACH cells
-- carry distance like FREE ones so the field leads into the fort, but zombies never step onto
-- them: reaching one is where they stop and attack (and, from week 5, pile up and climb).

local CollectionService = game:GetService("CollectionService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Tags = require(game:GetService("ReplicatedStorage").Shared.Tags)

local FlowField = {}

FlowField.FREE = 0
FlowField.SOLID = 1
FlowField.BREACH = 2

local CELL = Config.HORDE.CELL_SIZE
local HALF = Config.HORDE.HALF_EXTENT
local N = math.floor(HALF * 2 / CELL)
local UNREACHABLE = 65535

FlowField.UNREACHABLE = UNREACHABLE

local kinds = buffer.create(N * N) -- u8 per cell
local distance = buffer.create(N * N * 2) -- u16 per cell
-- Same goals, but climb zones count as walls: for zombies that can't build pyramids (Bull,
-- Creeper, Brute), so they head for a barricade instead of waiting at a fence forever.
local walkerDistance = buffer.create(N * N * 2)
local climbCells = buffer.create(N * N) -- u8: 1 where a ClimbZone owns the cell
local queue = table.create(N * N) :: { number }
-- The barricade / climb zone part behind each BREACH cell, and the reverse index, so a
-- broken barricade can open exactly its own cells.
local owners: { [number]: BasePart } = {}
local ownerCells: { [BasePart]: { number } } = {}

local NEIGHBOURS = {
	{ 1, 0 },
	{ -1, 0 },
	{ 0, 1 },
	{ 0, -1 },
	{ 1, 1 },
	{ 1, -1 },
	{ -1, 1 },
	{ -1, -1 },
}

-- Cell index is 0-based: ix + iz * N.
function FlowField.cellAt(position: Vector3): (number, number)
	local ix = math.floor((position.X + HALF) / CELL)
	local iz = math.floor((position.Z + HALF) / CELL)
	return ix, iz
end

function FlowField.inBounds(ix: number, iz: number): boolean
	return ix >= 0 and iz >= 0 and ix < N and iz < N
end

function FlowField.cellCenter(ix: number, iz: number): Vector3
	return Vector3.new(ix * CELL - HALF + CELL / 2, 0, iz * CELL - HALF + CELL / 2)
end

function FlowField.kind(ix: number, iz: number): number
	if not FlowField.inBounds(ix, iz) then
		return FlowField.SOLID
	end
	return buffer.readu8(kinds, ix + iz * N)
end

-- A distance field (u16 per cell). The main field leads to the players; noise sources get
-- their own small fields (see Noise.luau).
function FlowField.newField(): buffer
	local field = buffer.create(N * N * 2)
	buffer.fill(field, 0, 255)
	return field
end

function FlowField.distance(ix: number, iz: number, field: buffer?): number
	if not FlowField.inBounds(ix, iz) then
		return UNREACHABLE
	end
	return buffer.readu16(field or distance, (ix + iz * N) * 2)
end

function FlowField.ownerAt(ix: number, iz: number): BasePart?
	if not FlowField.inBounds(ix, iz) then
		return nil
	end
	return owners[ix + iz * N]
end

-- Switches every cell owned by `owner` (e.g. BREACH → FREE when a barricade breaks).
function FlowField.setOwnerKind(owner: BasePart, kind: number)
	local cells = ownerCells[owner]
	if cells then
		for _, index in cells do
			buffer.writeu8(kinds, index, kind)
		end
	end
end

-- Samples the map once. Anything collidable between knee and head height blocks a cell;
-- a hit on a Barricade or ClimbZone part makes it a breach point instead.
function FlowField.build(map: Instance)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	params.RespectCanCollide = true

	local boxSize = Vector3.new(CELL - 0.5, 5, CELL - 0.5)
	for iz = 0, N - 1 do
		for ix = 0, N - 1 do
			local center = FlowField.cellCenter(ix, iz)
			local hits =
				workspace:GetPartBoundsInBox(CFrame.new(center.X, 4, center.Z), boxSize, params)
			local kind = FlowField.FREE
			local index = ix + iz * N
			for _, hit in hits do
				if
					CollectionService:HasTag(hit, Tags.Barricade)
					or CollectionService:HasTag(hit, Tags.ClimbZone)
				then
					kind = FlowField.BREACH
					owners[index] = hit
					if CollectionService:HasTag(hit, Tags.ClimbZone) then
						buffer.writeu8(climbCells, index, 1)
					end
					local list = ownerCells[hit]
					if list then
						table.insert(list, index)
					else
						ownerCells[hit] = { index }
					end
					break
				end
				kind = FlowField.SOLID
			end
			buffer.writeu8(kinds, index, kind)
		end
	end
end

-- Breadth-first from all goal positions at once, stopping `limit` cells out. A goal on top of
-- something solid (a crate, hay bale) seeds the open cells around it instead.
local function bfs(field: buffer, goals: { Vector3 }, limit: number, blockClimb: boolean)
	buffer.fill(field, 0, 255)

	local function blocked(index: number): boolean
		return buffer.readu8(kinds, index) == FlowField.SOLID
			or (blockClimb and buffer.readu8(climbCells, index) == 1)
	end

	local head, tail = 1, 0
	local function seed(ix: number, iz: number)
		local index = ix + iz * N
		if
			FlowField.inBounds(ix, iz)
			and not blocked(index)
			and buffer.readu16(field, index * 2) ~= 0
		then
			buffer.writeu16(field, index * 2, 0)
			tail += 1
			queue[tail] = index
		end
	end
	for _, goal in goals do
		local ix, iz = FlowField.cellAt(goal)
		if FlowField.inBounds(ix, iz) and not blocked(ix + iz * N) then
			seed(ix, iz)
		else
			for _, offset in NEIGHBOURS do
				seed(ix + offset[1], iz + offset[2])
			end
		end
	end

	while head <= tail do
		local index = queue[head]
		head += 1
		local ix, iz = index % N, index // N
		local nextDistance = buffer.readu16(field, index * 2) + 1
		if nextDistance > limit then
			continue
		end
		for i = 1, 4 do
			local nx, nz = ix + NEIGHBOURS[i][1], iz + NEIGHBOURS[i][2]
			if FlowField.inBounds(nx, nz) then
				local nIndex = nx + nz * N
				if not blocked(nIndex) and buffer.readu16(field, nIndex * 2) > nextDistance then
					buffer.writeu16(field, nIndex * 2, nextDistance)
					tail += 1
					queue[tail] = nIndex
				end
			end
		end
	end
end

function FlowField.compute(goals: { Vector3 })
	bfs(distance, goals, UNREACHABLE - 1, false)
	bfs(walkerDistance, goals, UNREACHABLE - 1, true)
end

-- The field for zombies that can't climb (see walkerDistance).
function FlowField.walkerField(): buffer
	return walkerDistance
end

-- Fills `field` with distances to `goals`, only up to `limitCells` away.
function FlowField.computeField(field: buffer, goals: { Vector3 }, limitCells: number)
	bfs(field, goals, limitCells, false)
end

function FlowField.cellsFor(studs: number): number
	return math.ceil(studs / CELL)
end

-- Best neighbour to step toward. Diagonals are only allowed when both orthogonal cells are
-- open, so zombies never cut wall corners. Returns nil when already at a goal or stranded.
function FlowField.nextCell(ix: number, iz: number, field: buffer?): (number?, number?)
	local best = FlowField.distance(ix, iz, field)
	if best == 0 or best == UNREACHABLE then
		return nil, nil
	end
	local bx, bz = nil, nil
	for i, offset in NEIGHBOURS do
		local nx, nz = ix + offset[1], iz + offset[2]
		local d = FlowField.distance(nx, nz, field)
		if d < best and FlowField.kind(nx, nz) ~= FlowField.SOLID then
			local diagonalOk = i <= 4
				or (
					FlowField.kind(ix + offset[1], iz) ~= FlowField.SOLID
					and FlowField.kind(ix, iz + offset[2]) ~= FlowField.SOLID
				)
			if diagonalOk then
				best, bx, bz = d, nx, nz
			end
		end
	end
	return bx, bz
end

return FlowField
