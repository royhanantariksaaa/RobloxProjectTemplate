--!strict
-- Input
-- Stephen Leitnick
-- October 10, 2021

--[=[
	@class Input

	The Input package provides access to various user input classes.

	- [PreferredInput](/api/PreferredInput)
	- [Mouse](/api/Mouse)
	- [Keyboard](/api/Keyboard)
	- [Touch](/api/Touch)
	- [Gamepad](/api/Gamepad)
	- [Action](/api/Action)
	- [Context](/api/Context)

	Reference the desired input modules via the Input package to get started:

	```lua
	local PreferredInput = require(Packages.Input).PreferredInput
	local Mouse = require(Packages.Input).Mouse
	local Keyboard = require(Packages.Input).Keyboard
	local Touch = require(Packages.Input).Touch
	local Gamepad = require(Packages.Input).Gamepad
	local Action = require(Packages.Input).Action
	local Context = require(Packages.Input).Context
	```
]=]

local InputUtils = require(script.InputUtils)
local PreferredInput = require(script.PreferredInput)
local Mouse = require(script.Mouse)
local Keyboard = require(script.Keyboard)
local Touch = require(script.Touch)
local Gamepad = require(script.Gamepad)
local Action = require(script.Action)
local Context = require(script.Context)

-- Type exports for autocomplete
export type Context = typeof(Context.new(""))
export type Action = typeof(Action.new(Instance.new("InputContext"), "", "Bool"))
export type Mouse = typeof(Mouse.new())
export type Keyboard = typeof(Keyboard.new())
export type Touch = typeof(Touch.new())
export type Gamepad = typeof(Gamepad.new(Enum.UserInputType.Gamepad1))

-- Action definition type for declarative input definition
export type ActionDef = {
	Name: string,
	Type: string | Enum.InputActionType,
	Bind: { Enum.KeyCode | Instance }?,
}

-- Context definition type for declarative input definition
export type ContextDef = {
	Name: string,
	Actions: { ActionDef }?,
	[number]: ActionDef,
}

local Input = {
	-- Input Modules
	PreferredInput = PreferredInput,
	Mouse = Mouse,
	Keyboard = Keyboard,
	Touch = Touch,
	Gamepad = Gamepad,
	Action = Action,
	Context = Context,
	Utils = InputUtils,
	
	-- Helpers
	CreateContext = InputUtils.Context,
	CreateAction = InputUtils.Action,
	IsContextDefinition = InputUtils.IsContextDefinition,
	IsActionDefinition = InputUtils.IsActionDefinition,
}

--[=[
	@function Context
	@within Input
	@param def table -- Context definition
	@return table -- Marked context definition
	
	Helper to define an Input Context in a declarative way.
	
	```lua
	Input.Context {
		Name = "MyContext",
		Input.Action { ... }
	}
	```
]=]
function Input.ContextDef(def: ContextDef)
	return InputUtils.Context(def)
end

--[=[
	@function Action
	@within Input
	@param def table -- Action definition
	@return table -- Marked action definition
	
	Helper to define an Input Action in a declarative way.
	
	```lua
	Input.Action {
		Name = "Jump",
		Type = "Bool",
		Bind = { Enum.KeyCode.Space }
	}
	```
]=]
function Input.ActionDef(def: ActionDef)
	return InputUtils.Action(def)
end

return Input
