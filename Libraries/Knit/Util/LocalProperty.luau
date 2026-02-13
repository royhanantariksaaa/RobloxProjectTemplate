--[[
	LocalProperty
	A client-only observable property for local state management.
	
	Created via `KnitClient.CreateProperty()`.
	
	This provides the same API as ClientRemoteProperty but without
	any network replication. Perfect for local UI state, controller
	state, or any client-only reactive values.
	
	Example:
	```lua
	local MyController = Knit.CreateController({
		Name = "MyController",
	})
	
	function MyController:KnitInit()
		-- Create a local property (client-only, no networking)
		self.Score = Knit.CreateProperty(0)
		self.IsMenuOpen = Knit.CreateProperty(false)
	end
	
	function MyController:KnitStart()
		-- Observe changes
		self.Score:Observe(function(score)
			print("Score:", score)
		end)
		
		-- Set value
		self.Score:Set(100)
		
		-- Get value
		print(self.Score:Get()) --> 100
	end
	```
]]

local Signal = require(script.Parent.Parent.Parent.Signal)

--[=[
	@class LocalProperty
	@client
	
	A client-side only property for local state management.
	
	Unlike RemoteProperty/ClientRemoteProperty, this does NOT
	replicate to the server. It's purely local to the client.
	
	API:
	- `Get()` - Get the current value
	- `Set(value)` - Set a new value (fires Changed signal)
	- `Observe(callback)` - Observe value changes (calls immediately with current value)
	- `.Changed` - Signal that fires on value change
	- `Destroy()` - Cleanup resources
]=]
local LocalProperty = {}
LocalProperty.__index = LocalProperty

export type LocalProperty<T> = {
	Get: (self: LocalProperty<T>) -> T,
	Set: (self: LocalProperty<T>, value: T) -> (),
	Observe: (self: LocalProperty<T>, observer: (value: T) -> ()) -> RBXScriptConnection,
	Changed: any, -- Signal
	Destroy: (self: LocalProperty<T>) -> (),
}

--[=[
	Creates a new LocalProperty with an initial value.
	
	@param initialValue any -- The initial value of the property
	@return LocalProperty
]=]
function LocalProperty.new<T>(initialValue: T): LocalProperty<T>
	local self = setmetatable({}, LocalProperty)
	self._value = initialValue
	self.Changed = Signal.new()
	return self
end

--[=[
	Gets the current value of the property.
	
	```lua
	local value = property:Get()
	```
]=]
function LocalProperty:Get(): any
	return self._value
end

--[=[
	Sets the value of the property. If the value has changed,
	fires the Changed signal.
	
	```lua
	property:Set(100)
	property:Set({ key = "value" })
	```
]=]
function LocalProperty:Set(value: any)
	local oldValue = self._value
	self._value = value
	if oldValue ~= value then
		self.Changed:Fire(value, oldValue)
	end
end

--[=[
	Observes the value of the property. The observer callback
	will be called immediately with the current value, and
	every time the value changes.
	
	Returns a connection that can be disconnected to stop observing.
	
	```lua
	local connection = property:Observe(function(value)
		print("Value:", value)
	end)
	
	-- Later, to stop observing:
	connection:Disconnect()
	```
]=]
function LocalProperty:Observe(observer: (any) -> ()): RBXScriptConnection
	-- Call observer immediately with current value
	task.defer(observer, self._value)
	-- Connect to future changes
	return self.Changed:Connect(observer)
end

--[=[
	Returns true (LocalProperty is always immediately ready, unlike ClientRemoteProperty).
	Provided for API compatibility with ClientRemoteProperty.
]=]
function LocalProperty:IsReady(): boolean
	return true
end

--[=[
	Returns a resolved Promise with the current value.
	Provided for API compatibility with ClientRemoteProperty.
]=]
function LocalProperty:OnReady()
	local Promise = require(script.Parent.Parent.Parent.Promise)
	return Promise.resolve(self._value)
end

--[=[
	Destroys the LocalProperty and cleans up resources.
]=]
function LocalProperty:Destroy()
	self.Changed:Destroy()
end

return LocalProperty
