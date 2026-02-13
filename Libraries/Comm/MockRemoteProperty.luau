-- MockRemoteProperty
-- Designed to simulate RemoteProperty behavior in tests with full Schema validation
-- but without strict Roblox networking constraints.

local Signal = require(script.Parent.Parent.Signal)
local MockRemoteSignal = require(script.Parent.MockRemoteSignal)

local MockRemoteProperty = {}
MockRemoteProperty.__index = MockRemoteProperty

function MockRemoteProperty.new(initialValue, schema)
	local self = setmetatable({}, MockRemoteProperty)
	
	self._value = initialValue
	self._perPlayer = {}
	self.Changed = Signal.new()
	self._rs = MockRemoteSignal.new(schema)
	
	-- Mock internal player tracking since we don't have real connection events in pure unit tests
	-- unless we simulate them.
	
	return self
end

function MockRemoteProperty:Set(value)
	local oldValue = self._value
	self._value = value
	table.clear(self._perPlayer)
	self._rs:FireAll(value)
	if oldValue ~= value then
		self.Changed:Fire(value, oldValue, nil)
	end
end

function MockRemoteProperty:SetTop(value)
	local oldValue = self._value
	self._value = value
	-- In real implementation this iterates players. Here we just update value.
	if oldValue ~= value then
		self.Changed:Fire(value, oldValue, nil)
	end
end

function MockRemoteProperty:SetFor(player, value)
	local oldValue = self:GetFor(player)
	self._perPlayer[player] = value
	self._rs:Fire(player, value)
	if oldValue ~= value then
		self.Changed:Fire(value, oldValue, player)
	end
end

function MockRemoteProperty:SetForList(players, value)
	for _, player in ipairs(players) do
		self:SetFor(player, value)
	end
end

function MockRemoteProperty:ClearFor(player)
	if self._perPlayer[player] == nil then
		return
	end
	local oldValue = self:GetFor(player)
	self._perPlayer[player] = nil
	self._rs:Fire(player, self._value)
	if oldValue ~= self._value then
		self.Changed:Fire(self._value, oldValue, player)
	end
end

function MockRemoteProperty:ClearForList(players)
	for _, player in ipairs(players) do
		self:ClearFor(player)
	end
end

function MockRemoteProperty:ClearAll()
	local hadPerPlayer = next(self._perPlayer) ~= nil
	table.clear(self._perPlayer)
	self._rs:FireAll(self._value)
	if hadPerPlayer then
		self.Changed:Fire(self._value, nil, nil)
	end
end

function MockRemoteProperty:Get()
	return self._value
end

function MockRemoteProperty:GetFor(player)
	local val = self._perPlayer[player]
	if val ~= nil then return val end
	return self._value
end

function MockRemoteProperty:ForEach(callback)
	-- Mock implementation: only iterate players who have custom values or whom we know about?
	-- RemoteProperty iterates Players:GetPlayers(). In a mock env, that might be empty.
	-- We'll iterate the known custom overrides instead for now/
	for player, value in pairs(self._perPlayer) do
		callback(player, value)
	end
end

function MockRemoteProperty:Iter()
	return pairs(self._perPlayer)
end

function MockRemoteProperty:Observe(callback)
	task.defer(callback, self._value, nil)
	return self.Changed:Connect(function(val, old, plr)
		if plr == nil then callback(val, old) end
	end)
end

function MockRemoteProperty:Destroy()
	self.Changed:Destroy()
	self._rs:Destroy()
end

return MockRemoteProperty
