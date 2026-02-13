-- RemoteProperty
-- Stephen Leitnick
-- December 20, 2021

local Players = game:GetService("Players")

local Signal = require(script.Parent.Parent.Signal)
local RemoteSignal = require(script.Parent.RemoteSignal)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)

local None = Util.None

--[=[
	@class RemoteProperty
	@server
	Created via `ServerComm:CreateProperty()`.

	Values set can be anything that can pass through a
	[RemoteEvent](https://developer.roblox.com/en-us/articles/Remote-Functions-and-Events#parameter-limitations).

	Here is a cheat-sheet for the below methods:
	- Setting data
		- `Set`: Set "top" value for all current and future players. Overrides any custom-set data per player.
		- `SetTop`: Set the "top" value for all players, but does _not_ override any custom-set data per player.
		- `SetFor`: Set custom data for the given player. Overrides the "top" value. (_Can be nil_)
		- `SetForList`: Same as `SetFor`, but accepts a list of players.
		- `SetFilter`: Accepts a predicate function which checks for which players to set.
	- Clearing data
		- `ClearFor`: Clears the custom data set for a given player. Player will start using the "top" level value instead.
		- `ClearForList`: Same as `ClearFor`, but accepts a list of players.
		- `ClearFilter`: Accepts a predicate function which checks for which players to clear.
	- Getting data
		- `Get`: Retrieves the "top" value
		- `GetFor`: Gets the current value for the given player. If cleared, returns the top value.

	:::caution Network
	Calling any of the data setter methods (e.g. `Set()`) will
	fire the underlying RemoteEvent to replicate data to the
	clients. Therefore, setting data should only occur when it
	is necessary to change the data that the clients receive.
	:::

	:::caution Tables
	Tables _can_ be used with RemoteProperties. However, the
	RemoteProperty object will _not_ watch for changes within
	the table. Therefore, anytime changes are made to the table,
	the data must be set again using one of the setter methods.
	:::
]=]
local RemoteProperty = {}
RemoteProperty.__index = RemoteProperty

function RemoteProperty.new(
	parent: Instance,
	name: string,
	initialValue: any,
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	schema: any?, -- NEW: Optional KnitSchema schema
	clientToServerDeduplication: boolean?, -- NEW: Enable incoming deduplication
	serverToClientDeduplication: boolean? -- NEW: Enable outgoing deduplication
)
	-- check global flag for testing mock
	if _G.KNIT_TEST_MOCK_COMM then
		local MockRemoteProperty = require(script.Parent.MockRemoteProperty)
		return MockRemoteProperty.new(initialValue, schema)
	end

	local self = setmetatable({}, RemoteProperty)
	self._rs = RemoteSignal.new(parent, name, false, inboundMiddleware, outboundMiddleware, schema, clientToServerDeduplication, serverToClientDeduplication)
	self._value = initialValue
	self._perPlayer = {}
	self.Changed = Signal.new()
	self._playerRemoving = Players.PlayerRemoving:Connect(function(player)
		self._perPlayer[player] = nil
	end)
	self._rs:Connect(function(player)
		local playerValue = self._perPlayer[player]
		local value = if playerValue == nil then self._value elseif playerValue == None then nil else playerValue
		self._rs:Fire(player, value)
	end)
	return self
end

--[=[
	Sets the top-level value of all clients to the same value.
	
	:::note Override Per-Player Data
	This will override any per-player data that was set using
	`SetFor` or `SetFilter`. To avoid overriding this data,
	`SetTop` can be used instead.
	:::

	```lua
	-- Examples
	remoteProperty:Set(10)
	remoteProperty:Set({SomeData = 32})
	remoteProperty:Set("HelloWorld")
	```
]=]
function RemoteProperty:Set(value: any)
	local oldValue = self._value
	self._value = value
	table.clear(self._perPlayer)
	self._rs:FireAll(value)
	if oldValue ~= value then
		self.Changed:Fire(value, oldValue, nil)
	end
end

--[=[
	Set the top-level value of the property, but does not override
	any per-player data (e.g. set with `SetFor` or `SetFilter`).
	Any player without custom-set data will receive this new data.

	This is useful if certain players have specific values that
	should not be changed, but all other players should receive
	the same new value.

	```lua
	-- Using just 'Set' overrides per-player data:
	remoteProperty:SetFor(somePlayer, "CustomData")
	remoteProperty:Set("Data")
	print(remoteProperty:GetFor(somePlayer)) --> "Data"

	-- Using 'SetTop' does not override:
	remoteProperty:SetFor(somePlayer, "CustomData")
	remoteProperty:SetTop("Data")
	print(remoteProperty:GetFor(somePlayer)) --> "CustomData"
	```
]=]
function RemoteProperty:SetTop(value: any)
	local oldValue = self._value
	self._value = value
	for _, player in ipairs(Players:GetPlayers()) do
		if self._perPlayer[player] == nil then
			self._rs:Fire(player, value)
		end
	end
	if oldValue ~= value then
		self.Changed:Fire(value, oldValue, nil)
	end
end

--[=[
	@param value any -- Value to set for the clients (and to the predicate)
	Sets the value for specific clients that pass the `predicate`
	function test. This can be used to finely set the values
	based on more control logic (e.g. setting certain values
	per team).

	```lua
	-- Set the value of "NewValue" to players with a name longer than 10 characters:
	remoteProperty:SetFilter(function(player)
		return #player.Name > 10
	end, "NewValue")
	```
]=]
function RemoteProperty:SetFilter(predicate: (Player, any) -> boolean, value: any)
	for _, player in ipairs(Players:GetPlayers()) do
		if predicate(player, value) then
			self:SetFor(player, value)
		end
	end
end

--[=[
	Set the value of the property for a specific player. This
	will override the value used by `Set` (and the initial value
	set for the property when created).

	This value _can_ be `nil`. In order to reset the value for a
	given player and let the player use the top-level value held
	by this property, either use `Set` to set all players' data,
	or use `ClearFor`.

	```lua
	remoteProperty:SetFor(somePlayer, "CustomData")
	```
]=]
function RemoteProperty:SetFor(player: Player, value: any)
	local oldValue = self:GetFor(player)
	if player.Parent then
		self._perPlayer[player] = if value == nil then None else value
	end
	self._rs:Fire(player, value)
	if oldValue ~= value then
		self.Changed:Fire(value, oldValue, player)
	end
end

--[=[
	Set the value of the property for specific players. This just
	loops through the players given and calls `SetFor`.

	```lua
	local players = {player1, player2, player3}
	remoteProperty:SetForList(players, "CustomData")
	```
]=]
function RemoteProperty:SetForList(players: { Player }, value: any)
	for _, player in ipairs(players) do
		self:SetFor(player, value)
	end
end

--[=[
	Clears the custom property value for the given player. When
	this occurs, the player will reset to use the top-level
	value held by this property (either the value set when the
	property was created, or the last value set by `Set`).

	```lua
	remoteProperty:Set("DATA")

	remoteProperty:SetFor(somePlayer, "CUSTOM_DATA")
	print(remoteProperty:GetFor(somePlayer)) --> "CUSTOM_DATA"

	-- DOES NOT CLEAR, JUST SETS CUSTOM DATA TO NIL:
	remoteProperty:SetFor(somePlayer, nil)
	print(remoteProperty:GetFor(somePlayer)) --> nil

	-- CLEAR:
	remoteProperty:ClearFor(somePlayer)
	print(remoteProperty:GetFor(somePlayer)) --> "DATA"
	```
]=]
function RemoteProperty:ClearFor(player: Player)
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

--[=[
	Clears the custom value for the given players. This
	just loops through the list of players and calls
	the `ClearFor` method for each player.
]=]
function RemoteProperty:ClearForList(players: { Player })
	for _, player in ipairs(players) do
		self:ClearFor(player)
	end
end

--[=[
	The same as `SetFiler`, except clears the custom value
	for any player that passes the predicate.
]=]
function RemoteProperty:ClearFilter(predicate: (Player) -> boolean)
	for _, player in ipairs(Players:GetPlayers()) do
		if predicate(player) then
			self:ClearFor(player)
		end
	end
end

--[=[
	Clears the custom property value for all players. When
	this occurs, all players will reset to use the top-level
	value held by this property.
]=]
function RemoteProperty:ClearAll()
	local hadPerPlayer = next(self._perPlayer) ~= nil
	table.clear(self._perPlayer)
	self._rs:FireAll(self._value)
	if hadPerPlayer then
		self.Changed:Fire(self._value, nil, nil) -- player nil indicates top-level/global change
	end
end

--[=[
	Returns the top-level value held by the property. This will
	either be the initial value set, or the last value set
	with `Set()`.

	```lua
	remoteProperty:Set("Data")
	print(remoteProperty:Get()) --> "Data"
	```
]=]
function RemoteProperty:Get(): any
	return self._value
end

--[=[
	Returns the current value for the given player. This value
	will depend on if `SetFor` or `SetFilter` has affected the
	custom value for the player. If so, that custom value will
	be returned. Otherwise, the top-level value will be used
	(e.g. value from `Set`).

	```lua
	-- Set top level data:
	remoteProperty:Set("Data")
	print(remoteProperty:GetFor(somePlayer)) --> "Data"

	-- Set custom data:
	remoteProperty:SetFor(somePlayer, "CustomData")
	print(remoteProperty:GetFor(somePlayer)) --> "CustomData"

	-- Set top level again, overriding custom data:
	remoteProperty:Set("NewData")
	print(remoteProperty:GetFor(somePlayer)) --> "NewData"

	-- Set custom data again, and set top level without overriding:
	remoteProperty:SetFor(somePlayer, "CustomData")
	remoteProperty:SetTop("Data")
	print(remoteProperty:GetFor(somePlayer)) --> "CustomData"

	-- Clear custom data to use top level data:
	remoteProperty:ClearFor(somePlayer)
	print(remoteProperty:GetFor(somePlayer)) --> "Data"
	```
]=]
function RemoteProperty:GetFor(player: Player): any
	local playerValue = self._perPlayer[player]
	local value = if playerValue == nil then self._value elseif playerValue == None then nil else playerValue
	return value
end

--[=[
	Iterates through all current players and calls the `callback`
	with the player and their current value.
	
	```lua
	remoteProperty:ForEach(function(player, value)
		print(player.Name, value)
	end)
	```
]=]
function RemoteProperty:ForEach(callback: (Player, any) -> ())
	for _, player in ipairs(Players:GetPlayers()) do
		callback(player, self:GetFor(player))
	end
end

--[=[
	Returns an iterator for all current players and their current values.
	
	```lua
	for player, value in remoteProperty:Iter() do
		print(player.Name, value)
	end
	```
]=]
function RemoteProperty:Iter()
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

--[=[
	Observes the property for changes. The callback will be
	called immediately with the current top-level value, and
	every time the top-level value changes.
	
	Returns a cleanup function to stop observing.
]=]
function RemoteProperty:Observe(callback: (any, any) -> ())
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

--[=[
	Observes the property for a specific player. The callback
	will be called immediately with the player's current value,
	and every time their value changes (whether via SetFor, 
	Set, or Clear).
	
	Returns a cleanup function to stop observing.
]=]
function RemoteProperty:ObserveFor(player: Player, callback: (any, any) -> ())
	task.defer(callback, self:GetFor(player), nil)
	
	local lastValue = self:GetFor(player)
	
	local connection = self.Changed:Connect(function(value, oldValue, changedPlayer)
		-- If it's a global change (changedPlayer == nil) OR it's specifically for this player
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

--[=[
	Observes the property for all current and future players.
	The callback will be called for each player with their current
	value, and every time their value changes.
	
	Returns a cleanup function to stop observing all players.
]=]
function RemoteProperty:ObserveForEach(callback: (Player, any) -> ())
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
			connections[player]() -- cleanup ObserveFor
			connections[player] = nil
		end
	end)
	
	for _, player in ipairs(Players:GetPlayers()) do
		observePlayer(player)
	end
	
	return function()
		playerAdded:Disconnect()
		playerRemoving:Disconnect()
		for player, cleanup in pairs(connections) do
			cleanup()
		end
		table.clear(connections)
	end
end

--[=[
	Destroys the RemoteProperty object.
]=]
function RemoteProperty:Destroy()
	self._rs:Destroy()
	self._playerRemoving:Disconnect()
	self.Changed:Destroy()
end

return RemoteProperty
