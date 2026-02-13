-- ServerProperty
-- Implementation of a server-only property that supports per-player data
-- without any network replication.

local Players = game:GetService("Players")

local Signal = require(script.Parent.Parent.Parent.Signal)
local Util = require(script.Parent.Parent.Parent.Comm.Util)

local None = Util.None

--[=[
	@class ServerProperty
	@server
	
	Created via `KnitServer.CreateServerProperty()`.
	
	Similar to RemoteProperty, but stays entirely on the server.
	Supports per-player value overrides and observation.
]=]
local ServerProperty = {}
ServerProperty.__index = ServerProperty

function ServerProperty.new(initialValue: any)
	local self = setmetatable({}, ServerProperty)
	self._value = initialValue
	self._perPlayer = {}
	self.Changed = Signal.new()
	
	self._playerRemoving = Players.PlayerRemoving:Connect(function(player)
		self._perPlayer[player] = nil
	end)
	
	return self
end

function ServerProperty:Set(value: any)
	local oldValue = self._value
	self._value = value
	table.clear(self._perPlayer)
	if oldValue ~= value then
		self.Changed:Fire(value, oldValue, nil)
	end
end

function ServerProperty:Get(): any
	return self._value
end

function ServerProperty:SetFor(player: Player, value: any)
	local oldValue = self:GetFor(player)
	if player.Parent then
		self._perPlayer[player] = if value == nil then None else value
	end
	if oldValue ~= value then
		self.Changed:Fire(value, oldValue, player)
	end
end

function ServerProperty:GetFor(player: Player): any
	local playerValue = self._perPlayer[player]
	local value = if playerValue == nil then self._value elseif playerValue == None then nil else playerValue
	return value
end

function ServerProperty:ClearFor(player: Player)
	if self._perPlayer[player] == nil then
		return
	end
	local oldValue = self:GetFor(player)
	self._perPlayer[player] = nil
	if oldValue ~= self._value then
		self.Changed:Fire(self._value, oldValue, player)
	end
end

function ServerProperty:ClearAll()
	local hadPerPlayer = next(self._perPlayer) ~= nil
	table.clear(self._perPlayer)
	if hadPerPlayer then
		self.Changed:Fire(self._value, nil, nil)
	end
end

function ServerProperty:ForEach(callback: (Player, any) -> ())
	for _, player in ipairs(Players:GetPlayers()) do
		callback(player, self:GetFor(player))
	end
end

function ServerProperty:Iter()
	local players = Players:GetPlayers()
	local i = 0
	return function()
		i += 1
		local player = players[i]
		if player then
			return player, self:GetFor(player)
		end
		return nil
	end
end

function ServerProperty:Observe(callback: (any, any) -> ())
	task.defer(callback, self._value, nil)
	local connection = self.Changed:Connect(function(value, oldValue, player)
		if player == nil then
			callback(value, oldValue)
		end
	end)
	return function()
		connection:Disconnect()
	end
end

function ServerProperty:ObserveFor(player: Player, callback: (any, any) -> ())
	task.defer(callback, self:GetFor(player), nil)
	
	local lastValue = self:GetFor(player)
	
	local connection = self.Changed:Connect(function(value, oldValue, changedPlayer)
		if changedPlayer == nil or changedPlayer == player then
			local currentValue = self:GetFor(player)
			if currentValue ~= lastValue then
				local prevValue = lastValue
				lastValue = currentValue
				callback(currentValue, prevValue)
			end
		end
	end)
	
	return function()
		connection:Disconnect()
	end
end

function ServerProperty:ObserveForEach(callback: (Player, any) -> ())
	local connections = {}
	
	local function observePlayer(player)
		if connections[player] then return end
		connections[player] = self:ObserveFor(player, function(value)
			callback(player, value)
		end)
	end
	
	local playerAdded = Players.PlayerAdded:Connect(observePlayer)
	local playerRemoving = Players.PlayerRemoving:Connect(function(player)
		if connections[player] then
			connections[player]()
			connections[player] = nil
		end
	end)
	
	for _, player in ipairs(Players:GetPlayers()) do
		observePlayer(player)
	end
	
	return function()
		playerAdded:Disconnect()
		playerRemoving:Disconnect()
		for _, cleanup in pairs(connections) do
			cleanup()
		end
		table.clear(connections)
	end
end

function ServerProperty:Destroy()
	self._playerRemoving:Disconnect()
	self.Changed:Destroy()
end

return ServerProperty
