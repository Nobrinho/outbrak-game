--!strict
-- The DataStore behind player profiles, or — only inside Studio when the place can't reach
-- DataStores (unpublished, or "Studio Access to API Services" off) — an in-memory stand-in with
-- the same UpdateAsync shape, so the game stays playable and nothing pretends to save. A live
-- server never falls back: there a failed call is a failed call.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Stores = {}

export type Store = {
	UpdateAsync: (self: Store, key: string, transform: (any) -> any) -> any,
	offline: boolean,
}

local STORE_NAME = "PlayerProfiles_v1"

local function memoryStore(): Store
	local data: { [string]: any } = {}
	local store = {} :: any
	store.offline = true
	function store.UpdateAsync(_, key: string, transform: (any) -> any): any
		local result = transform(data[key])
		if result ~= nil then
			data[key] = result
		end
		return data[key]
	end
	return store :: Store
end

local function looksLikeNoAccess(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "publish", 1, true) ~= nil
		or string.find(lower, "api services", 1, true) ~= nil
		or string.find(lower, "studio access", 1, true) ~= nil
end

-- Returns the profile store. In Studio, probes it once and falls back to memory if blocked.
function Stores.profiles(): Store
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	if ok and RunService:IsStudio() then
		local probeOk, err = pcall(function()
			return (store :: any):GetAsync("__probe")
		end)
		if not probeOk and looksLikeNoAccess(tostring(err)) then
			warn(
				"[Data] DataStore indisponível no Studio — modo offline: o progresso NÃO é salvo."
			)
			return memoryStore()
		end
	end
	if not ok then
		if RunService:IsStudio() then
			warn(
				"[Data] DataStore indisponível no Studio — modo offline: o progresso NÃO é salvo."
			)
			return memoryStore()
		end
		error(`[Data] cannot open DataStore: {store}`)
	end
	local dataStore = store :: GlobalDataStore
	local wrapper = {} :: any
	wrapper.offline = false
	function wrapper.UpdateAsync(_, key: string, transform: (any) -> any): any
		return dataStore:UpdateAsync(key, transform)
	end
	return wrapper :: Store
end

return Stores
