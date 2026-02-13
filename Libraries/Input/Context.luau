-- Context
-- Wrapper for Roblox InputContext
-- November 23, 2025

local Players = game:GetService("Players")

local Trove = require(script.Parent.Parent.Trove)
local Action = require(script.Parent.Action)

--[=[
	@class Context
	@client

	The Context class wraps the Roblox `InputContext` instance.
	It allows grouping related actions and enabling/disabling them together.

	```lua
	local Context = require(Packages.Input).Context
	
	local gameplayContext = Context.new("Gameplay")
	local jumpAction = gameplayContext:CreateAction("Jump", "Bool")
	
	gameplayContext:Enable()
	```
]=]
local Context = {}
Context.__index = Context

--[=[
	@return Context
	Constructs a new Context.
	@param name string -- The name of the context
	@param parent Instance? -- Optional parent (defaults to PlayerGui)
]=]
function Context.new(name: string, parent: Instance?)
	local self = setmetatable({}, Context)
	
	self._trove = Trove.new()
	
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	
	self._instance = self._trove:Construct(Instance.new, "InputContext")
	self._instance.Name = name
	self._instance.Parent = parent or playerGui
	
	return self
end

--[=[
	Creates a new Action within this context.
	@param name string -- The name of the action
	@param actionType string | Enum.InputActionType -- The type of action (e.g., "Bool", "Direction1D")
	@return Action
]=]
function Context:CreateAction(name: string, actionType: string | any)
	local action = self._trove:Construct(Action, self._instance, name, actionType)
	return action
end

--[=[
	Enables the context.
]=]
function Context:Enable()
	self._instance.Enabled = true
end

--[=[
	Disables the context.
]=]
function Context:Disable()
	self._instance.Enabled = false
end

--[=[
	Checks if the context is enabled.
	@return boolean
]=]
function Context:IsEnabled()
	return self._instance.Enabled
end

--[=[
	Destroys the Context and all its actions.
]=]
function Context:Destroy()
	self._trove:Destroy()
end

return Context
