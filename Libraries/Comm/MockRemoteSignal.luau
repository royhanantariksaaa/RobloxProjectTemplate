-- MockRemoteSignal
-- Designed to simulate RemoteSignal behavior in tests with full Schema validation
-- but without strict Roblox networking constraints (e.g. valid Player instances).

local Signal = require(script.Parent.Parent.Signal)
local KnitSchema = require(script.Parent.KnitSchema)

local MockRemoteSignal = {}
MockRemoteSignal.__index = MockRemoteSignal

function MockRemoteSignal.new(schema)
	local self = setmetatable({}, MockRemoteSignal)
	
	self._schema = schema
	self._signal = Signal.new() -- For incoming client events
	self._outboundSignal = Signal.new() -- For outbound server events (to inspect in tests)
	
	return self
end

-- Simulate Client -> Server firing
function MockRemoteSignal:SimulateIncoming(player, data)
	-- 1. Validate incoming data against schema
	if self._schema then
		-- Simulate network serialization trip
		local buf, instances = KnitSchema.serialize(self._schema, data)
		local success, result = pcall(KnitSchema.deserialize, self._schema, buf, instances)
		
		if not success then
			error(string.format("[MockRemoteSignal] Deserialization failed: %s", tostring(result)))
		end
		
		if not KnitSchema.validate(self._schema, result) then
			error(string.format("[MockRemoteSignal] Incoming validation failed for schema %s", self._schema.name))
		end
		
		data = result
	end
	
	self._signal:Fire(player, data)
end

-- Server -> Client firing (what the Service calls)
function MockRemoteSignal:Fire(player, data)
	-- 1. Validate outbound data against schema
	if self._schema then
		if not KnitSchema.validate(self._schema, data) then
			error(string.format("[MockRemoteSignal] Outbound validation failed for schema %s", self._schema.name))
		end

		-- Simulate network serialization trip
		local buf, instances = KnitSchema.serialize(self._schema, data)
		local _, result = pcall(KnitSchema.deserialize, self._schema, buf, instances)
		data = result
	end
	
	-- Fire outbound signal so tests can assert this happened
	self._outboundSignal:Fire(player, data)
end

function MockRemoteSignal:FireAll(data)
	-- We can't really simulate "All" without a list of players, 
	-- but for testing we usually just want to validata data.
	self:Fire(nil, data)
end

function MockRemoteSignal:FireExcept(ignorePlayer, data)
	self:Fire(nil, data)
end

function MockRemoteSignal:Connect(fn)
	return self._signal:Connect(fn)
end

function MockRemoteSignal:Destroy()
	self._signal:Destroy()
	self._outboundSignal:Destroy()
end

return MockRemoteSignal
