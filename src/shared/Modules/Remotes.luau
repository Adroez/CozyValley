--!strict
-- Lightweight wrapper around the ReplicatedStorage.CozyRemotes folder.
-- Server calls Remotes.init(serverReplicator); clients call Remotes.init(nil)
-- which waits for the folder to replicate. After init(), everything is
-- plain GetRemote* lookups with a typed name table -- no event bus, no
-- extra abstraction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(script.Parent.Parent.Config.GameConstants)

export type RemoteSpec = {
	name: string,
	class: "Event" | "Function",
}

-- Single registry of every remote the game uses. Add new entries here.
local SPECS: {RemoteSpec} = {
	{ name = "Ping", class = "Event" }, -- bootstrap smoke test
}

local Remotes = {}

local initialized = false
local remoteCache: { [string]: RemoteObject } = {}

local function waitForFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(GameConstants.RemoteFolderName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	return ReplicatedStorage:WaitForChild(GameConstants.RemoteFolderName, 60) :: Folder
end

function Remotes.init(serverStorageProvider: Instance?)
	if initialized then
		return
	end

	local storage = serverStorageProvider or waitForFolder()

	for _, spec in SPECS do
		local object: RemoteObject
		if spec.class == "Event" then
			object = storage:FindFirstChild(spec.name) or Instance.new("RemoteEvent")
			object.Name = spec.name
			object.Parent = storage
		else
			object = storage:FindFirstChild(spec.name) or Instance.new("RemoteFunction")
			object.Name = spec.name
			object.Parent = storage
		end
		remoteCache[spec.name] = object
	end

	initialized = true
end

function Remotes.get(name: string): RemoteObject
	local cached = remoteCache[name]
	if cached then
		return cached
	end

	if not initialized then
		Remotes.init(nil)
		cached = remoteCache[name]
		if cached then
			return cached
		end
	end

	local folder = waitForFolder()
	local object = folder:WaitForChild(name, 30)
	assert(object, ("Remote '%s' not found under %s"):format(name, GameConstants.RemoteFolderName))
	return object :: RemoteObject
end

function Remotes.event(name: string): RemoteEvent
	local object = Remotes.get(name)
	assert(object:IsA("RemoteEvent"), ("Remote '%s' is not a RemoteEvent"):format(name))
	return object :: RemoteEvent
end

function Remotes.function(name: string): RemoteFunction
	local object = Remotes.get(name)
	assert(object:IsA("RemoteFunction"), ("Remote '%s' is not a RemoteFunction"):format(name))
	return object :: RemoteFunction
end

return Remotes
