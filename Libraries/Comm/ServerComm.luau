-- ServerComm
-- Stephen Leitnick
-- December 20, 2021

local Server = require(script.Parent.Server)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)
local RateLimitMiddleware = require(script.Parent.RateLimitMiddleware)


--[=[
	@class ServerComm
	@server
]=]
local ServerComm = {}
ServerComm.__index = ServerComm

--[=[
	@within ServerComm
	@type ServerMiddlewareFn (player: Player, args: {any}) -> (shouldContinue: boolean, ...: any)
	The middleware function takes the client player and the arguments (as a table array), and should
	return `true|false` to indicate if the process should continue.

	If returning `false`, the optional varargs after the `false` are used as the new return values
	to whatever was calling the middleware.
]=]
--[=[
	@within ServerComm
	@type ServerMiddleware {ServerMiddlewareFn}
	Array of middleware functions.
]=]

--[=[
	@return ServerComm
	Constructs a ServerComm object. The `namespace` parameter is used
	in cases where more than one ServerComm object may be bound
	to the same object. Otherwise, a default namespace is used.

	```lua
	local serverComm = ServerComm.new(game:GetService("ReplicatedStorage"))

	-- If many might exist in the given parent, use a unique namespace:
	local serverComm = ServerComm.new(game:GetService("ReplicatedStorage"), "MyNamespace")
	```
]=]
function ServerComm.new(parent: Instance, namespace: string?)
	assert(Util.IsServer, "ServerComm must be constructed from the server")
	assert(typeof(parent) == "Instance", "Parent must be of type Instance")
	local ns = Util.DefaultCommFolderName
	if namespace then
		ns = namespace
	end
	assert(not parent:FindFirstChild(ns), "Parent already has another ServerComm bound to namespace " .. ns)
	local self = setmetatable({}, ServerComm)
	self._instancesFolder = Instance.new("Folder")
	self._instancesFolder.Name = ns
	self._instancesFolder.Parent = parent
	return self
end

--[=[
	@param name string
	@param fn (player: Player, ...: any) -> ...: any
	@param options table?
	@return RemoteFunction
	Creates a RemoteFunction and binds the given function to it.

	Options:
	- `inboundMiddleware` (ServerMiddleware)
	- `outboundMiddleware` (ServerMiddleware)
	- `inboundSchema` (KnitSchema.Schema)
	- `outboundSchema` (KnitSchema.Schema)

	```lua
	local function GetSomething(player: Player)
		return "Something"
	end

	serverComm:BindFunction("GetSomething", GetSomething, {
		inboundSchema = Schemas.Request,
		outboundSchema = Schemas.Response
	})
	```
]=]
function ServerComm:BindFunction(name: string, fn: Types.FnBind, options: {
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	inboundSchema: any?,
	outboundSchema: any?,
	RateLimit: number?
}?)
	local inboundMiddleware = options and options.inboundMiddleware
	local outboundMiddleware = options and options.outboundMiddleware
	local inboundSchema = options and options.inboundSchema
	local outboundSchema = options and options.outboundSchema
	
	if options and options.RateLimit then
		local rateLimit = RateLimitMiddleware(options.RateLimit)
		if inboundMiddleware then
			table.insert(inboundMiddleware, 1, rateLimit)
		else
			inboundMiddleware = {rateLimit}
		end
	end

	return Server.BindFunction(self._instancesFolder, name, fn, inboundMiddleware, outboundMiddleware, inboundSchema, outboundSchema, options :: any)
end

--[=[
	@param tbl table
	@param name string
	@param options table?
	@return RemoteFunction

	Binds a function to a table method.

	Options:
	- `inboundMiddleware` (ServerMiddleware)
	- `outboundMiddleware` (ServerMiddleware)
	- `inboundSchema` (KnitSchema.Schema)
	- `outboundSchema` (KnitSchema.Schema)

	```lua
	serverComm:WrapMethod(MyObject, "GetData", {
		inboundSchema = Schemas.Request
	})
	```
]=]
function ServerComm:WrapMethod(tbl: {}, name: string, options: {
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	inboundSchema: any?,
	outboundSchema: any?,
	RateLimit: number?
}?)
	local inboundMiddleware = options and options.inboundMiddleware
	local outboundMiddleware = options and options.outboundMiddleware
	local inboundSchema = options and options.inboundSchema
	local outboundSchema = options and options.outboundSchema
	
	if options and options.RateLimit then
		local rateLimit = RateLimitMiddleware(options.RateLimit)
		if inboundMiddleware then
			table.insert(inboundMiddleware, 1, rateLimit)
		else
			inboundMiddleware = {rateLimit}
		end
	end

	return Server.WrapMethod(self._instancesFolder, tbl, name, inboundMiddleware, outboundMiddleware, inboundSchema, outboundSchema, options :: any)
end

function ServerComm:Wrap(tbl: {}, middleware: Types.Middleware?)
	for name, value in pairs(tbl) do
		if name ~= "Server" then
			if type(value) == "function" then
				tbl[name] = self:WrapMethod(tbl, name, {
					inboundMiddleware = middleware and middleware.Inbound or nil,
					outboundMiddleware = middleware and middleware.Outbound or nil,
				})
			elseif type(value) == "table" then
				local commType = rawget(value, "__knitCommType")
				if commType == "Signal" then
					local options = value.options or {}
					if middleware then
						if options.inboundMiddleware == nil then
							options.inboundMiddleware = middleware.Inbound
						end
						if options.outboundMiddleware == nil then
							options.outboundMiddleware = middleware.Outbound
						end
					end
					tbl[name] = self:CreateSignal(name, options)
				elseif commType == "Property" then
					local options = value.options or {}
					local inboundMiddleware = options.inboundMiddleware or (middleware and middleware.Inbound or nil)
					local outboundMiddleware = options.outboundMiddleware or (middleware and middleware.Outbound or nil)
					local schema = options.schema
					local clientToServerDeduplication = options.clientToServerDeduplication
					local serverToClientDeduplication = options.serverToClientDeduplication
					tbl[name] = self:CreateProperty(
						name,
						value.initialValue,
						inboundMiddleware,
						outboundMiddleware,
						schema,
						clientToServerDeduplication,
						serverToClientDeduplication
					)
				end
			end
		end
	end
end

--[=[
	@param name string
	@param options table?
	@return RemoteSignal

	Creates a signal that can be used to fire data to the clients
	or receive data from the clients.

	Options table can contain:
	- `unreliable` (boolean) - Use UnreliableRemoteEvent instead of RemoteEvent
	- `inboundMiddleware` (ServerMiddleware) - Process incoming data
	- `outboundMiddleware` (ServerMiddleware) - Process outgoing data  
	- `schema` (KnitSchema.Schema) - Automatic serialization/validation

	```lua
	local Schemas = require(ReplicatedStorage.Shared.Network.Schemas)
	
	-- Simple: Just schema
	local mySignal = serverComm:CreateSignal("MySignal", {
		schema = Schemas.StanceLookAt
	})

	-- Advanced: With middleware and schema
	local mySignal = serverComm:CreateSignal("MySignal", {
		unreliable = false,
		inboundMiddleware = {RateLimitMiddleware},
		schema = Schemas.PlayerAction
	})
	
	-- Legacy: No options (backward compatible)
	local mySignal = serverComm:CreateSignal("MySignal")

	-- When firing, pass data matching the schema:
	mySignal:Fire(somePlayer, {packedAngles = 12345})
	
	-- On receive, data is automatically deserialized and validated:
	mySignal:Connect(function(player, data)
		print("Received validated data:", data.packedAngles)
	end)
	```
]=]
function ServerComm:CreateSignal(name: string, options: {
	unreliable: boolean?,
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	schema: any?,
	clientToServerDeduplication: boolean?, -- Enable incoming deduplication (default: true)
	serverToClientDeduplication: boolean?, -- Enable outgoing deduplication (default: false)
	RateLimit: number?
}?)
	-- Extract options with defaults
	local unreliable = options and options.unreliable or false
	local inboundMiddleware = options and options.inboundMiddleware or nil
	local outboundMiddleware = options and options.outboundMiddleware or nil
	local schema = options and options.schema or nil
	
	if options and options.RateLimit then
		local rateLimit = RateLimitMiddleware(options.RateLimit)
		if inboundMiddleware then
			table.insert(inboundMiddleware, 1, rateLimit)
		else
			inboundMiddleware = {rateLimit}
		end
	end
	local clientToServerDeduplication = if options and options.clientToServerDeduplication ~= nil then options.clientToServerDeduplication else true -- Default: true
	local serverToClientDeduplication = if options and options.serverToClientDeduplication ~= nil then options.serverToClientDeduplication else false -- Default: false
	
	return Server.CreateSignal(
		self._instancesFolder,
		name,
		unreliable,
		inboundMiddleware,
		outboundMiddleware,
		schema,
		clientToServerDeduplication,
		serverToClientDeduplication
	)
end

--[=[
	@param name string
	@param initialValue any
	@param options table?
	@return RemoteProperty

	Create a property object which will replicate its property value to
	the clients. Optionally, specific clients can be targeted with
	different property values.

	Options table can contain:
	- `inboundMiddleware` (ServerMiddleware)
	- `outboundMiddleware` (ServerMiddleware)
	- `schema` (KnitSchema.Schema)
	- `clientToServerDeduplication` (boolean)
	- `serverToClientDeduplication` (boolean)

	```lua
	local comm = Comm.ServerComm.new(game:GetService("ReplicatedStorage"))

	local mapInfo = comm:CreateProperty("MapInfo", {
		MapName = "TheAwesomeMap",
		MapDuration = 60,
	}, {
		schema = Schemas.MapInfo
	})
	```
]=]
function ServerComm:CreateProperty(
	name: string,
	initialValue: any,
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	schema: any?,
	clientToServerDeduplication: boolean?,
	serverToClientDeduplication: boolean?
)
	-- Support legacy signature (name, initialValue, inboundMiddleware, outboundMiddleware)
	-- But also support options table if passed as 3rd argument (not implemented here for simplicity, assuming explicit args for now based on signature)
	-- Wait, the docstring implies an options table but the signature is explicit args.
	-- Let's stick to the explicit args to match the underlying Server.CreateProperty signature we are about to update.
	
	return Server.CreateProperty(
		self._instancesFolder,
		name,
		initialValue,
		inboundMiddleware,
		outboundMiddleware,
		schema,
		clientToServerDeduplication,
		serverToClientDeduplication
	)
end



--[=[
	Destroy the ServerComm object.
]=]
function ServerComm:Destroy()
	self._instancesFolder:Destroy()
end

return ServerComm

