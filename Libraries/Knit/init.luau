--[[
	Knit Framework - Simplified Structure
	
	A lightweight framework for building client-server applications in Roblox.
	All utilities are organized in the Util directory with clear categorization.
]]

local RunService = game:GetService("RunService")

-- ============================================================================
-- TYPE IMPORTS FOR AUTOCOMPLETE
-- ============================================================================

-- Core Types
local Types = require(script.Types)
export type Service<T> = Types.Service<T>
export type Controller<T> = Types.Controller<T>
export type ServiceDef<T> = Types.ServiceDef<T>
export type ControllerDef<T> = Types.ControllerDef<T>
export type ViewDef<T> = Types.ViewDef<T>
export type View<T> = Types.View<T>
export type Middleware = Types.Middleware
export type ClientMiddleware = Types.ClientMiddleware
export type ServerMiddleware = Types.ServerMiddleware
export type RemoteSignal = Types.RemoteSignal
export type ClientRemoteSignal = Types.ClientRemoteSignal
export type RemoteProperty<T> = Types.RemoteProperty<T>
export type ClientRemoteProperty<T> = Types.ClientRemoteProperty<T>
export type LocalProperty<T> = Types.LocalProperty<T>
export type ServiceDefinitions = Types.ServiceDefinitions
export type ControllerDefinitions = Types.ControllerDefinitions
export type ViewDefinitions = Types.ViewDefinitions
export type Schema = Types.Schema
export type SignalOptions = Types.SignalOptions
export type MethodOptions = Types.MethodOptions
export type PropertyOptions = Types.PropertyOptions
export type KnitClientOptions = Types.KnitClientOptions
export type KnitServerOptions = Types.KnitServerOptions

-- Utility Module Imports
local Signal = require(script.Parent.Signal)
local Promise = require(script.Parent.Promise)
local Trove = require(script.Parent.Trove)
local Option = require(script.Parent.Option)
local Symbol = require(script.Parent.Symbol)
local TableUtil = require(script.Parent.TableUtil)
local Component = require(script.Util.Component)
local Comm = require(script.Parent.Comm)
local Input = require(script.Parent.Input)
local SafePlayerEvent = require(script.Parent.SafePlayerEvent)
local Timer = require(script.Parent.Timer)
local TagUtil = require(script.Util.TagUtil)
local Trajectory = require(script.Util.Trajectory)
local Tween = require(script.Parent.Tween)

-- Re-export types from Signal
export type Signal<T...> = Signal.Signal<T...>
export type Connection = Signal.Connection

-- Re-export types from Promise
export type Promise<T> = Promise.Promise<T>
export type Status = Promise.Status

-- Re-export types from Option
export type Option<T> = Option.Option<T>

-- ============================================================================
-- KNIT MODULE IMPLEMENTATION
-- ============================================================================

-- Main Knit table
export type KnitServerAPI = {
	CreateService: <T>(serviceDef: ServiceDef<T> & T) -> Service<T> & T,
	GetService: <T>(serviceName: string) -> Service<T> & T,
	AddServices: (parent: Instance) -> { Service<any> },
	AddServicesDeep: (parent: Instance) -> { Service<any> },
	Start: (options: KnitServerOptions?) -> Promise<any>,
	OnStart: () -> Promise<any>,
	CreateSignal: (options: SignalOptions?) -> RemoteSignal,
	CreateProperty: <T>(initialValue: T, options: PropertyOptions?) -> RemoteProperty<T>,
	CreateUnreliableSignal: (options: SignalOptions?) -> RemoteSignal,
	Signal: typeof(Signal),
	Promise: typeof(Promise),
	Trove: typeof(Trove),
	Option: typeof(Option),
	Symbol: typeof(Symbol),
	TableUtil: typeof(TableUtil),
	Component: typeof(Component),
	Comm: typeof(Comm),
	Input: typeof(Input),
	SafePlayerEvent: typeof(SafePlayerEvent),
	Timer: typeof(Timer),
	TagUtil: typeof(TagUtil),
	Trajectory: typeof(Trajectory),
	Tween: typeof(Tween),
}

export type KnitClientAPI = {
	CreateController: <T>(controllerDef: ControllerDef<T> & T) -> Controller<T> & T,
	GetService: <T>(serviceName: string) -> ClientService & T,
	GetController: <T>(controllerName: string) -> Controller<T> & T,
	AddControllers: (parent: Instance) -> { Controller<any> },
	AddControllersDeep: (parent: Instance) -> { Controller<any> },
	Start: (options: KnitClientOptions?) -> Promise<any>,
	OnStart: () -> Promise<any>,
	CreateProperty: <T>(initialValue: T) -> LocalProperty<T>,
	Signal: typeof(Signal),
	Promise: typeof(Promise),
	Trove: typeof(Trove),
	Option: typeof(Option),
	Symbol: typeof(Symbol),
	TableUtil: typeof(TableUtil),
	Component: typeof(Component),
	Comm: typeof(Comm),
	Input: typeof(Input),
	SafePlayerEvent: typeof(SafePlayerEvent),
	Timer: typeof(Timer),
	TagUtil: typeof(TagUtil),
	Trajectory: typeof(Trajectory),
	Tween: typeof(Tween),
}

local Knit: KnitServerAPI | KnitClientAPI = {}

-- Load KnitClient or KnitServer based on execution context
if RunService:IsServer() then
	-- On server, load KnitServer as the base
	for key, value in pairs(require(script.KnitServer)) do
		Knit[key] = value
	end
else
	-- On client, clean up KnitServer if it exists and load KnitClient
	local KnitServer = script:FindFirstChild("KnitServer")
	if KnitServer and RunService:IsRunning() then
		KnitServer:Destroy()
	end
	for key, value in pairs(require(script.KnitClient)) do
		Knit[key] = value
	end
end

-- ============================================================================
-- UTILITY EXPORTS
-- ============================================================================
-- All utilities are organized by category for easy discovery and understanding

-- ----------------------------------------------------------------------------
-- Core Utilities
-- ----------------------------------------------------------------------------
-- Fundamental building blocks used throughout the framework

-- Signal: Type-safe event system for creating custom events
Knit.Signal = Signal

-- Promise: Asynchronous operation handling with chainable methods
Knit.Promise = Promise

-- Trove: Lifecycle management for cleaning up objects and connections
Knit.Trove = Trove

-- Option: Safe handling of optional/nullable values
Knit.Option = Option

-- Symbol: Unique identifiers for internal use
Knit.Symbol = Symbol

-- ----------------------------------------------------------------------------
-- Data Utilities
-- ----------------------------------------------------------------------------
-- Helper modules for working with data structures

-- TableUtil: Utility functions for table manipulation and operations
Knit.TableUtil = TableUtil

-- ----------------------------------------------------------------------------
-- Component System
-- ----------------------------------------------------------------------------
-- Entity-component system for attaching behavior to instances

-- Component: Base class for creating reusable components
Knit.Component = Component

-- ----------------------------------------------------------------------------
-- Communication
-- ----------------------------------------------------------------------------
-- Client-server networking with type-safe remote communication

-- Comm: Simplified client-server communication system
Knit.Comm = Comm

-- ----------------------------------------------------------------------------
-- Input System
-- ----------------------------------------------------------------------------
-- Unified input handling across multiple device types

-- Input: Cross-platform input management (Keyboard, Mouse, Gamepad, Touch)
Knit.Input = Input

-- SafePlayerEvent: Utility for managing player and character lifecycle events efficiently
Knit.SafePlayerEvent = SafePlayerEvent

-- Timer: Periodic execution management with drift control
Knit.Timer = Timer

-- ----------------------------------------------------------------------------
-- UI System
-- ----------------------------------------------------------------------------
-- Reactive UI utilities for building user interfaces

-- Tween: Animation and tweening utilities
Knit.Tween = Tween

-- TagUtil: Lightweight tag observation (alternative to Components)
Knit.TagUtil = TagUtil

-- Trajectory: Physics trajectory calculations
Knit.Trajectory = Trajectory

-- ============================================================================

return Knit
