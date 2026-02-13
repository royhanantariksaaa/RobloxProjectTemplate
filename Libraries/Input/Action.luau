-- Action
-- Wrapper for Roblox InputAction
-- November 23, 2025

local Trove = require(script.Parent.Parent.Trove)
local Signal = require(script.Parent.Parent.Signal)

--[=[
	@class Action
	@client

	The Action class wraps the Roblox `InputAction` instance.
	It provides Signals for input events and methods to bind inputs.

	**Note:** Actions should typically be created via `Context:CreateAction`.
]=]
local Action = {}
Action.__index = Action

--[=[
	@within Action
	@prop Pressed Signal<void>
	@tag Event
	Fired when the input begins (e.g. Key Down). Only works if Type is Bool.
]=]

--[=[
	@within Action
	@prop Released Signal<void>
	@tag Event
	Fired when the input ends (e.g. Key Up). Only works if Type is Bool.
]=]

--[=[
	@within Action
	@prop Changed Signal<Enum.UserInputState, any, InputObject>
	@tag Event
	Fired when the input state changes.
	Arguments: state, value, inputObject
]=]

--[=[
	@return Action
	Constructs a new Action.
	@param contextInstance Instance -- The parent InputContext instance
	@param name string -- The name of the action
	@param actionType string | Enum.InputActionType -- The type of action
]=]
function Action.new(contextInstance: Instance, name: string, actionType: string | any)
	local self = setmetatable({}, Action)
	
	self._trove = Trove.new()
	
	self._instance = self._trove:Construct(Instance.new, "InputAction")
	self._instance.Name = name
	self._instance.Parent = contextInstance
	
	-- Set Type
	if typeof(actionType) == "string" then
		self._instance.Type = Enum.InputActionType[actionType]
	else
		self._instance.Type = actionType
	end
	
	self.Pressed = self._trove:Construct(Signal)
	self.Released = self._trove:Construct(Signal)
	self.Changed = self._trove:Construct(Signal)
	
	-- Connect Instance Events
	self._trove:Connect(self._instance.Pressed, function()
		self.Pressed:Fire()
	end)
	
	self._trove:Connect(self._instance.Released, function()
		self.Released:Fire()
	end)
	
	self._trove:Connect(self._instance.StateChanged, function(state, value, inputObject)
		self.Changed:Fire(state, value, inputObject)
	end)
	
	return self
end

--[=[
	Binds an input to this action.
	@param input Enum.KeyCode | GuiButton -- The key or button to bind
	@return Instance -- The InputBinding instance
]=]
function Action:Bind(input: Enum.KeyCode | Instance)
	-- local binding = Instance.new("InputBinding")
	-- binding.Parent = self._instance
	local binding = self._instance:FindFirstChild(input.Name.."_Binding")
	if not binding then
		binding = Instance.new("InputBinding")
		binding.Name = input.Name .. "_Binding"
		binding.Parent = self._instance
	end
	if typeof(input) == "Instance" then
		if input:IsA("GuiButton") then
			binding.UIButton = input
		elseif input:IsA("InputObject") then
			binding.KeyCode = input.KeyCode
		end
	elseif typeof(input) == "EnumItem" then
		if input.EnumType == Enum.KeyCode then
			binding.KeyCode = input
		elseif input.EnumType == Enum.UserInputType then
			binding.KeyCode = input
		end
	else
		warn("Invalid input type for Action:Bind", input)
	end
	
	return binding
end

--[=[
	Destroys the Action.
]=]
function Action:Destroy()
	self._trove:Destroy()
end

return Action
