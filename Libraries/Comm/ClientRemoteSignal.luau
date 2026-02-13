-- ClientRemoteSignal
-- Stephen Leitnick
-- December 20, 2021

local Signal = require(script.Parent.Parent.Signal)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)
local KnitSchema = require(script.Parent.KnitSchema)

--[=[
	@class ClientRemoteSignal
	@client
	Created via `ClientComm:GetSignal()`.
]=]
local ClientRemoteSignal = {}
ClientRemoteSignal.__index = ClientRemoteSignal

--[=[
	@within ClientRemoteSignal
	@interface Connection
	.Disconnect () -> ()

	Represents a connection.
]=]

function ClientRemoteSignal.new(
	re: RemoteEvent | UnreliableRemoteEvent,
	inboundMiddleware: Types.ClientMiddleware?,
	outboudMiddleware: Types.ClientMiddleware?,
	schema: any?, -- NEW: Optional KnitSchema schema
	deduplication: boolean? -- NEW: Enable deduplication (default: true)
)
	local self = setmetatable({}, ClientRemoteSignal)
	self._re = re
	self._hasOutbound = type(outboudMiddleware) == "table" and #outboudMiddleware > 0
	self._outbound = outboudMiddleware
	self._schema = schema -- Store schema
	self._hasSchema = schema ~= nil and schema.fields ~= nil
	self._deduplication = if deduplication == nil then true else deduplication -- Default: enabled
	self._previousBuffer = nil -- Track previous buffer for deduplication (after quantization!)
	self._previousServerData = nil -- Track previous data FROM server (for incoming deduplication)
	
	local hasInbound = type(inboundMiddleware) == "table" and #inboundMiddleware > 0
	local needsSignal = hasInbound or self._hasSchema
	
	if needsSignal then
		self._directConnect = false
		self._signal = Signal.new()
		self._reConn = self._re.OnClientEvent:Connect(function(...)
			local args = table.pack(...)
			
			-- NEW: Deduplication check (Server -> Client)
			local isNoChange = false
			if self._hasSchema then
				local buf = args[1]
				
				-- Check if this is a "NO_CHANGE" marker (0-byte buffer)
				if typeof(buf) == "buffer" and buffer.len(buf) == 0 then
					-- Use cached previous data
					if self._previousServerData then
						-- Use cached data but CONTINUE to middleware
						args = table.pack(self._previousServerData)
						isNoChange = true
					else
						warn(`[ClientRemoteSignal] Received NO_CHANGE marker but no cached data from server`)
						return
					end
				end
			end
			
			-- NEW: KnitSchema deserialization
			if self._hasSchema and not isNoChange then
				local buf = args[1]
				local instances = args[2]
				-- print(`[KnitSchema Debug] ClientRemoteSignal Recv Buffer: {buf} ({buffer.len(buf)} bytes)`)
				local success, result = pcall(KnitSchema.deserialize, self._schema, buf, instances)
				if not success then
					warn(`[ClientRemoteSignal] Failed to deserialize: {result}`)
					return
				end
				if not KnitSchema.validate(self._schema, result) then
					warn(`[ClientRemoteSignal] Validation failed`)
					return
				end
				-- print(`[KnitSchema Debug] ClientRemoteSignal Recv Data:`, result)
				
				-- Cache result for future deduplication
				self._previousServerData = result
				
				args = table.pack(result)
			end
			
			-- Process middleware if present
			if hasInbound then
				local success = Util.ProcessMiddleware(inboundMiddleware, args)
				if not success then
					return
				end
			end
			
			self._signal:Fire(table.unpack(args, 1, args.n))
		end)
	else
		self._directConnect = true
	end
	return self
end



function ClientRemoteSignal:_processOutboundMiddleware(...: any)
	local args = table.pack(...)
	
	-- NEW: KnitSchema serialization with deduplication
	if self._hasSchema then
		local data = args[1] or {} -- Default to empty table if nil
		-- print(`[KnitSchema Debug] ClientRemoteSignal Send Data:`, data)
		
		-- Validate and serialize FIRST (this applies schema quantization)
		if not KnitSchema.validate(self._schema, data) then
			error(`[ClientRemoteSignal] Invalid data for schema {self._schema.name}`)
		end
		local buf, instances = KnitSchema.serialize(self._schema, data)
		-- print(`[KnitSchema Debug] ClientRemoteSignal Send Buffer: {buf} ({buffer.len(buf)} bytes)`)
		
		-- Deduplication: Compare serialized buffers (after quantization!)
		if self._deduplication and self._previousBuffer then
			-- Compare buffer contents byte-by-byte
			if buffer.len(buf) == buffer.len(self._previousBuffer) then
				local identical = true
				for i = 0, buffer.len(buf) - 1 do
					if buffer.readu8(buf, i) ~= buffer.readu8(self._previousBuffer, i) then
						identical = false
						break
					end
				end
				
				if identical then
					-- Send NO_CHANGE marker (0-byte buffer)
					local marker = buffer.create(0)
					-- print(`[Deduplication] Sending NO_CHANGE marker (saved {buffer.len(buf)} bytes)`)
					return marker
				end
			end
		end
		
		-- Cache buffer for next comparison
		if self._deduplication then
			self._previousBuffer = buf
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
	@param fn (...: any) -> ()
	@return Connection
	Connects a function to the remote signal. The function will be
	called anytime the equivalent server-side RemoteSignal is
	fired at this specific client that created this client signal.
]=]
function ClientRemoteSignal:Connect(fn: (...any) -> ())
	if self._directConnect then
		return self._re.OnClientEvent:Connect(fn)
	else
		return self._signal:Connect(fn)
	end
end

--[=[
	Fires the equivalent server-side signal with the given arguments.

	:::note Outbound Middleware
	All arguments pass through any outbound middleware before being
	sent to the server.
	:::
]=]
function ClientRemoteSignal:Fire(...: any)
	if self._hasOutbound or self._hasSchema then
		self._re:FireServer(self:_processOutboundMiddleware(...))
	else
		self._re:FireServer(...)
	end
end

--[=[
	Destroys the ClientRemoteSignal object.
]=]
function ClientRemoteSignal:Destroy()
	if self._signal then
		self._signal:Destroy()
	end
end

return ClientRemoteSignal
