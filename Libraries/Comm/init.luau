--!strict
-- Comm
-- Stephen Leitnick
-- August 05, 2021

--[=[
	@class Comm
	Remote communication library.

	This exposes the raw functions that are used by the `ServerComm` and `ClientComm` classes.
	Those two classes should be preferred over accessing the functions directly through this
	Comm library.

	```lua
	-- Server
	local ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm
	local serverComm = ServerComm.new(somewhere, "MyComm")
	serverComm:BindFunction("Hello", function(player: Player)
		return "Hi"
	end)
	
	-- Client
	local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
	local clientComm = ClientComm.new(somewhere, false, "MyComm")
	local comm = clientComm:BuildObject()
	print(comm:Hello()) --> Hi
	```
]=]

-- Load core Server and Client modules first (these don't have circular dependencies)
local Server = require(script.Server)
local Client = require(script.Client)
local ServerComm = require(script.ServerComm)
local ClientComm = require(script.ClientComm)
local KnitSchema = require(script.KnitSchema)

-- Type exports for autocomplete
export type ServerComm = typeof(ServerComm.new(Instance.new("Folder"), ""))
export type ClientComm = typeof(ClientComm.new(Instance.new("Folder"), false, ""))
export type BufferNet = typeof(KnitSchema)

-- Create the Comm table with core functions
local Comm = {
	-- Export Server and Client modules directly
	Server = Server,
	Client = Client,
	
	-- Lazy-loaded comm classes
	ServerComm = ServerComm,
	ClientComm = ClientComm,
	
	-- BufferNet schema system
	KnitSchema = KnitSchema,
	BufferNet = KnitSchema, -- Alias for convenience
}

-- Export all Server functions
for key, value in pairs(Server) do
	if Comm[key] == nil then
		Comm[key] = value
	end
end

-- Export all Client functions
for key, value in pairs(Client) do
	if Comm[key] == nil then
		Comm[key] = value
	end
end

return Comm
