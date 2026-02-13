-- RemoteSignal
-- Stephen Leitnick
-- December 20, 2021

local Players = game:GetService("Players")

local Signal = require(script.Parent.Parent.Signal)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)
local KnitSchema = require(script.Parent.KnitSchema)

--[=[
	@class RemoteSignal
	@server
	Created via `ServerComm:CreateSignal()`.
]=]
local RemoteSignal = {}
RemoteSignal.__index = RemoteSignal

--[=[
	@within RemoteSignal
	@interface Connection
	.Disconnect () -> nil
	.Connected boolean

	Represents a connection.
]=]

function RemoteSignal.new(
	parent: Instance,
	name: string,
	unreliable: boolean?,
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	schema: any?, -- NEW: Optional KnitSchema schema
	clientToServerDeduplication: boolean?, -- NEW: Enable incoming deduplication (default: true)
	serverToClientDeduplication: boolean? -- NEW: Enable outgoing deduplication (default: false)
)
	-- check global flag for testing mock
	if _G.KNIT_TEST_MOCK_COMM then
		local MockRemoteSignal = require(script.Parent.MockRemoteSignal)
		return MockRemoteSignal.new(schema)
	end

	local self = setmetatable({}, RemoteSignal)
	self._re = if unreliable == true then Instance.new("UnreliableRemoteEvent") else Instance.new("RemoteEvent")
	self._re.Name = name
	self._re.Parent = parent
	self._hasOutbound = type(outboundMiddleware) == "table" and #outboundMiddleware > 0
	self._outbound = outboundMiddleware
	self._schema = schema -- Store schema
	self._hasSchema = schema ~= nil and schema.fields ~= nil
	
	-- Deduplication settings
	self._clientToServerDeduplication = if clientToServerDeduplication == nil then true else clientToServerDeduplication
	self._serverToClientDeduplication = if serverToClientDeduplication == nil then false else serverToClientDeduplication
	
	self._previousClientData = {} -- Track previous data FROM client (for incoming deduplication)
	self._previousServerData = {} -- Track previous data TO client (for outgoing deduplication)
	
	if self._hasSchema then
		self._re:SetAttribute("_schema", schema.name)
		
		-- NEW: Expose schema definition to client via StringValue
		local schemaDef = Instance.new("StringValue")
		schemaDef.Name = "SchemaDef"
		schemaDef.Value = game:GetService("HttpService"):JSONEncode(schema)
		schemaDef.Parent = self._re
	end
	
	local hasInbound = type(inboundMiddleware) == "table" and #inboundMiddleware > 0
	local needsSignal = hasInbound or self._hasSchema or self._clientToServerDeduplication
	
	if needsSignal then
		self._directConnect = false
		self._signal = Signal.new()
		self._re.OnServerEvent:Connect(function(player, ...)
			local args = table.pack(...)
			
			-- NEW: Deduplication check (before schema/middleware)
			-- NEW: Deduplication check (before schema/middleware)
			if self._clientToServerDeduplication and self._hasSchema then
				local buf = args[1]
				local instances = args[2]
				
				-- Check if this is a "NO_CHANGE" marker (0-byte buffer)
				if typeof(buf) == "buffer" and buffer.len(buf) == 0 then
					-- Use cached previous data for this player
					local cached = self._previousClientData[player]
					if cached then
						-- Use cached data but CONTINUE to middleware
						args = table.pack(cached)
					else
						warn(`[RemoteSignal] Received NO_CHANGE marker but no cached data for {player.Name}`)
						return
					end
				else
					-- Not a marker, proceed with deserialization
					local success, result = pcall(KnitSchema.deserialize, self._schema, buf, instances)
					if not success then
						warn(`[RemoteSignal] Failed to deserialize {name}: {result}`)
						return
					end
					if not KnitSchema.validate(self._schema, result) then
						warn(`[RemoteSignal] Validation failed for {name}`)
						return
					end
					
					-- Cache the deserialized data for deduplication
					if self._clientToServerDeduplication then
						self._previousClientData[player] = result
					end
					
					args = table.pack(result)
				end
			elseif self._hasSchema then
				-- Schema enabled but deduplication disabled
				local buf = args[1]
				local instances = args[2]
				local success, result = pcall(KnitSchema.deserialize, self._schema, buf, instances)
				if not success then
					warn(`[RemoteSignal] Failed to deserialize {name}: {result}`)
					return
				end
				if not KnitSchema.validate(self._schema, result) then
					warn(`[RemoteSignal] Validation failed for {name}`)
					return
				end
				args = table.pack(result)
			end
			

			
			-- Process middleware if present
			if hasInbound then
				local success = Util.ProcessMiddleware(inboundMiddleware, args)
				if not success then
					return
				end
			end
			
			self._signal:Fire(player, table.unpack(args, 1, args.n))
		end)
		
		-- Clean up cache when player leaves
		if self._clientToServerDeduplication or self._serverToClientDeduplication then
			Players.PlayerRemoving:Connect(function(player)
				self._previousClientData[player] = nil
				self._previousServerData[player] = nil
			end)
		end
	else
		self._directConnect = true
	end
	return self
end

--[=[
	@return boolean
	Returns `true` if the underlying RemoteSignal is bound to an
	UnreliableRemoteEvent object.
]=]
function RemoteSignal:IsUnreliable(): boolean
	return self._re:IsA("UnreliableRemoteEvent")
end

--[=[
	@param fn (player: Player, ...: any) -> nil -- The function to connect
	@return Connection
	Connect a function to the signal. Anytime a matching ClientRemoteSignal
	on a client fires, the connected function will be invoked with the
	arguments passed by the client.
]=]
function RemoteSignal:Connect(fn)
	if self._directConnect then
		return self._re.OnServerEvent:Connect(fn)
	else
		return self._signal:Connect(fn)
	end
end

function RemoteSignal:_processOutboundMiddleware(player: Player?, ...: any)
	local args = table.pack(...)
	
	-- NEW: KnitSchema serialization
	if self._hasSchema then
		local data = args[1]
		-- print(`[KnitSchema Debug] RemoteSignal Send Data:`, data)
		if not KnitSchema.validate(self._schema, data) then
			error(`[RemoteSignal]Invalid data for schema {self._schema.name}`)
		end
		local buf, instances = KnitSchema.serialize(self._schema, data)
		-- print(`[KnitSchema Debug] RemoteSignal Send Buffer: {buf} ({buffer.len(buf)} bytes)`)
		
		-- Deduplication Logic (Server -> Client)
		if self._serverToClientDeduplication and player then
			local previousBuf = self._previousServerData[player]
			
			if previousBuf and buffer.len(buf) == buffer.len(previousBuf) then
				local identical = true
				for i = 0, buffer.len(buf) - 1 do
					if buffer.readu8(buf, i) ~= buffer.readu8(previousBuf, i) then
						identical = false
						break
					end
				end
				
				if identical then
					-- Send NO_CHANGE marker (0-byte buffer)
					local marker = buffer.create(0)
					-- print(`[Deduplication] Sending NO_CHANGE marker to {player.Name}`)
					return marker
				end
			end
			
			-- Cache for next time
			self._previousServerData[player] = buf
		end
		
		args = table.pack(buf, instances)
	end
	
	-- Process middleware if present
	if self._hasOutbound then
		local success, result = Util.ProcessMiddleware(self._outbound, args)
		if not success then
			return result
		end
	end
	
	return table.unpack(args, 1, args.n)
end

--[=[
	@param player Player -- The target client
	@param ... any -- Arguments passed to the client
	Fires the signal at the specified client with any arguments.

	:::note Outbound Middleware
	All arguments pass through any outbound middleware (if any)
	before being sent to the clients.
	:::
]=]
function RemoteSignal:Fire(player: Player, ...: any)
	local args = table.pack(self:_processOutboundMiddleware(player, ...))
	
	-- Mock mode: Validate but don't send over network.
	if _G.KNIT_TEST_MOCK_COMM then
		-- Optional: Log or fire some internal debug event if needed for assertion
		return
	end

	self._re:FireClient(player, table.unpack(args, 1, args.n))
end

--[=[
	@param ... any
	Fires the signal at _all_ clients with any arguments.

	:::note Outbound Middleware
	All arguments pass through any outbound middleware (if any)
	before being sent to the clients.
	:::
]=]
function RemoteSignal:FireAll(...: any)
	if self._serverToClientDeduplication then
		-- Must fire individually to handle per-player deduplication state
		for _, player in Players:GetPlayers() do
			self:Fire(player, ...)
		end
	else
		local args = table.pack(self:_processOutboundMiddleware(nil, ...))
		
		if _G.KNIT_TEST_MOCK_COMM then
			return
		end
		
		self._re:FireAllClients(table.unpack(args, 1, args.n))
	end
end

--[=[
	Simulate an incoming event from a client (Mock Mode).
	Required when detecting _G.KNIT_TEST_MOCK_COMM after instantiation.
]=]
function RemoteSignal:SimulateIncoming(player, data)
	if not self._signal then
		error("[RemoteSignal] Cannot simulate incoming on direct-connected signal (no schema/middleware/dedup).")
	end

	if self._hasSchema then
		-- Simulate network serialization trip
		local buf, instances = KnitSchema.serialize(self._schema, data)
		local success, result = pcall(KnitSchema.deserialize, self._schema, buf, instances)
		
		if not success then
			error(string.format("[RemoteSignal] Deserialization failed: %s", tostring(result)))
		end
		
		if not KnitSchema.validate(self._schema, result) then
			error(string.format("[RemoteSignal] Incoming validation failed for schema %s", self._schema.name))
		end
		
		data = result
	end

	-- Fire internal signal (as if received from RemoteEvent)
	self._signal:Fire(player, data)
end

--[=[
	@param ignorePlayer Player -- The client to ignore
	@param ... any -- Arguments passed to the other clients
	Fires the signal to all clients _except_ the specified
	client.

	:::note Outbound Middleware
	All arguments pass through any outbound middleware (if any)
	before being sent to the clients.
	:::
]=]
function RemoteSignal:FireExcept(ignorePlayer: Player, ...: any)
	self:FireFilter(function(plr)
		return plr ~= ignorePlayer
	end, ...)
end

--[=[
	@param predicate (player: Player, argsFromFire: ...) -> boolean
	@param ... any -- Arguments to pass to the clients (and to the predicate)
	Fires the signal at any clients that pass the `predicate`
	function test. This can be used to fire signals with much
	more control logic.

	:::note Outbound Middleware
	All arguments pass through any outbound middleware (if any)
	before being sent to the clients.
	:::

	:::caution Predicate Before Middleware
	The arguments sent to the predicate are sent _before_ getting
	transformed by any middleware.
	:::

	```lua
	-- Fire signal to players of the same team:
	remoteSignal:FireFilter(function(player)
		return player.Team.Name == "Best Team"
	end)
	```
]=]
function RemoteSignal:FireFilter(predicate: (Player, ...any) -> boolean, ...: any)
	for _, player in Players:GetPlayers() do
		if predicate(player, ...) then
			-- Fire individually to support deduplication
			self:Fire(player, ...)
		end
	end
end

--[=[
	Fires a signal at the clients within the `players` table. This is
	useful when signals need to fire for a specific set of players.

	For more complex firing, see `FireFilter`.

	:::note Outbound Middleware
	All arguments pass through any outbound middleware (if any)
	before being sent to the clients.
	:::

	```lua
	local players = {somePlayer1, somePlayer2, somePlayer3}
	remoteSignal:FireFor(players, "Hello, players!")
	```
]=]
function RemoteSignal:FireFor(players: { Player }, ...: any)
	for _, player in players do
		self:Fire(player, ...)
	end
end

--[=[
	Destroys the RemoteSignal object.
]=]
function RemoteSignal:Destroy()
	self._re:Destroy()
	if self._signal then
		self._signal:Destroy()
	end
end

return RemoteSignal

