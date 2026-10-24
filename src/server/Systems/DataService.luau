--!strict
-- Player profiles: one DataStore key per player, claimed with a session lock so only one
-- server owns a profile at a time (no dupes when rejoining fast). Gameplay reads and writes the
-- in-memory profile only; this module persists it on an autosave timer, when the player
-- leaves and on server shutdown. If a profile can't be loaded the player is kicked rather
-- than handed a blank profile that would overwrite their real data on the next save.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Signal = require(Shared.Util.Signal)
local ProfileSchema = require(script.Parent.Parent.Data.ProfileSchema)
local Stores = require(script.Parent.Parent.Data.Stores)

local DataService = {}

-- Fired once a player's profile is loaded and owned by this server.
DataService.loaded = Signal.new() :: Signal.Signal<Player, ProfileSchema.Profile>

local AUTOSAVE_INTERVAL = 60
local LOCK_STALE = AUTOSAVE_INTERVAL * 2 + 30 -- a lock not refreshed this long is a dead server's
local LOAD_ATTEMPTS = 5
local SHUTDOWN_WAIT = 25

type Session = {
	profile: ProfileSchema.Profile,
	key: string,
	released: boolean,
}

local store: Stores.Store
local sessions: { [Player]: Session } = {}
local jobId = if game.JobId ~= "" then game.JobId else "studio"

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

-- pcall + exponential backoff around one store call.
local function withRetry<T>(attempts: number, fn: () -> T): (boolean, T?)
	local delaySeconds = 1
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[Data] attempt {attempt}/{attempts} failed: {result}`)
		if attempt < attempts then
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, 16)
		end
	end
	return false, nil
end

-- Claims the lock and loads (migrating) in one atomic UpdateAsync.
-- Returns the profile, or nil plus whether it failed because another server holds it.
local function claim(key: string): (ProfileSchema.Profile?, boolean)
	local lockedElsewhere = false
	local loaded: ProfileSchema.Profile? = nil
	local ok = withRetry(3, function()
		lockedElsewhere = false
		return store:UpdateAsync(key, function(stored: any)
			local lock = if typeof(stored) == "table" then stored.lock else nil
			if
				typeof(lock) == "table"
				and lock.jobId ~= jobId
				and typeof(lock.time) == "number"
				and os.time() - lock.time < LOCK_STALE
			then
				lockedElsewhere = true
				return nil -- abort: another server owns this profile
			end
			local profile = ProfileSchema.migrate(stored)
			local out: any = ProfileSchema.serialize(profile)
			out.lock = { jobId = jobId, time = os.time() }
			loaded = profile
			return out
		end)
	end)
	if not ok then
		return nil, false
	end
	return loaded, lockedElsewhere
end

-- Writes the in-memory profile. `release` clears the lock (leaving / shutting down).
-- Refuses to write if another server took the lock meanwhile.
local function save(session: Session, release: boolean): boolean
	local stolen = false
	local ok = withRetry(3, function()
		stolen = false
		return store:UpdateAsync(session.key, function(stored: any)
			local lock = if typeof(stored) == "table" then stored.lock else nil
			if typeof(lock) == "table" and lock.jobId ~= jobId then
				stolen = true
				return nil
			end
			local out: any = ProfileSchema.serialize(session.profile)
			out.lock = if release then nil else { jobId = jobId, time = os.time() }
			return out
		end)
	end)
	if stolen then
		warn(`[Data] lost the session lock for {session.key}; not overwriting`)
		return false
	end
	return ok
end

local function onPlayerAdded(player: Player)
	local key = keyFor(player)
	for attempt = 1, LOAD_ATTEMPTS do
		local profile, lockedElsewhere = claim(key)
		if not player.Parent then
			-- Left while loading: hand the lock straight back.
			if profile then
				save({ profile = profile, key = key, released = false }, true)
			end
			return
		end
		if profile then
			sessions[player] = { profile = profile, key = key, released = false }
			DataService.loaded:fire(player, profile)
			return
		end
		if not lockedElsewhere then
			break -- the store itself failed; retrying the lock won't help
		end
		if attempt < LOAD_ATTEMPTS then
			task.wait(3) -- the previous server may still be saving
		end
	end
	player:Kick("Não foi possível carregar seu progresso. Entre de novo em alguns instantes.")
end

local function release(player: Player)
	local session = sessions[player]
	if not session or session.released then
		return
	end
	session.released = true
	save(session, true)
	sessions[player] = nil
end

-- The loaded profile, or nil while loading / after leaving. Gameplay mutates it directly.
function DataService.get(player: Player): ProfileSchema.Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

-- Saves right away (used after purchases). Returns whether the write succeeded.
function DataService.saveNow(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and not session.released and save(session, false)
end

function DataService.isOffline(): boolean
	return store.offline
end

function DataService.init()
	store = Stores.profiles()
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(release)

	-- Staggered autosave: each player saves at their own offset within the interval.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL / 6)
			local slot = math.floor(os.clock() / (AUTOSAVE_INTERVAL / 6)) % 6
			for player, session in sessions do
				if player.UserId % 6 == slot and not session.released then
					task.spawn(save, session, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				release(player)
				pending -= 1
			end)
		end
		if RunService:IsStudio() then
			return -- don't make every stopped playtest hang
		end
		local deadline = os.clock() + SHUTDOWN_WAIT
		while pending > 0 and os.clock() < deadline do
			task.wait(0.25)
		end
	end)
end

return DataService
