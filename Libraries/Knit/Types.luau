--!strict
--[=[
	@class KnitTypes
	Comprehensive type definitions for Knit services, controllers, and utilities.
	These types enable full autocomplete support throughout the framework.
]=]

-- ============================================================================
-- MIDDLEWARE TYPES
-- ============================================================================

export type ServerMiddlewareFn = (player: Player, args: { any }) -> (boolean, ...any)
export type ServerMiddleware = { ServerMiddlewareFn }

export type ClientMiddlewareFn = (args: { any }) -> (boolean, ...any)
export type ClientMiddleware = { ClientMiddlewareFn }

export type Middleware = {
	Inbound: ServerMiddleware | ClientMiddleware?,
	Outbound: ServerMiddleware | ClientMiddleware?,
}

-- ============================================================================
-- SCHEMA TYPES (BufferNet)
-- ============================================================================

export type Field = {
	name: string,
	type: string,
	options: {
		min: number?,
		max: number?,
		optional: boolean?,
		arrayLength: number?,
		delta: boolean?,
		deltaFrom: string?,
		elementType: string?,
		keyType: string?,
		valueType: string?,
		[string]: any,
	},
}

export type Schema = {
	name: string,
	fields: { Field },
	size: number?,
	isDynamic: boolean,
}

-- ============================================================================
-- OPTIONS TYPES
-- ============================================================================

-- Signal options for creating remote signals
export type SignalOptions = {
	schema: any?,
	unreliable: boolean?,
	inboundMiddleware: ServerMiddleware?,
	outboundMiddleware: ServerMiddleware?,
	deduplication: boolean?, -- Enable automatic data deduplication (default: true)
	RateLimit: number?, -- Anti-exploit: Cooldown in seconds between client requests
}

-- Method options for creating remote functions
export type MethodOptions = {
	inboundSchema: Schema?,
	outboundSchema: Schema?,
	inboundMiddleware: ServerMiddleware?,
	outboundMiddleware: ServerMiddleware?,
	RateLimit: number?, -- Anti-exploit: Cooldown in seconds between client requests
}

-- Property options for creating remote properties
export type PropertyOptions = {
	inboundMiddleware: ServerMiddleware?,
	outboundMiddleware: ServerMiddleware?,
	schema: any?,
	clientToServerDeduplication: boolean?,
	serverToClientDeduplication: boolean?,
}

-- ============================================================================
-- REMOTE COMMUNICATION TYPES
-- ============================================================================

-- Server-side remote signal
export type RemoteSignal = {
	Fire: (self: RemoteSignal, player: Player, ...any) -> (),
	FireAll: (self: RemoteSignal, ...any) -> (),
	FireExcept: (self: RemoteSignal, player: Player, ...any) -> (),
	FireFilter: (self: RemoteSignal, predicate: (player: Player) -> boolean, ...any) -> (),
	Wait: (self: RemoteSignal) -> ...any,
	Connect: (self: RemoteSignal, callback: (player: Player, ...any) -> ()) -> RBXScriptConnection,
	Once: (self: RemoteSignal, callback: (player: Player, ...any) -> ()) -> RBXScriptConnection,
	DisconnectAll: (self: RemoteSignal) -> (),
	Destroy: (self: RemoteSignal) -> (),
}

-- Client-side remote signal
export type ClientRemoteSignal = {
	Fire: (self: ClientRemoteSignal, ...any) -> (),
	Wait: (self: ClientRemoteSignal) -> ...any,
	Connect: (self: ClientRemoteSignal, callback: (...any) -> ()) -> RBXScriptConnection,
	Once: (self: ClientRemoteSignal, callback: (...any) -> ()) -> RBXScriptConnection,
	DisconnectAll: (self: ClientRemoteSignal) -> (),
	Destroy: (self: ClientRemoteSignal) -> (),
}

-- Server-side remote property
export type RemoteProperty<T> = {
	Get: (self: RemoteProperty<T>) -> T,
	Set: (self: RemoteProperty<T>, value: T) -> (),
	SetFor: (self: RemoteProperty<T>, player: Player, value: T) -> (),
	SetFilter: (self: RemoteProperty<T>, predicate: (player: Player) -> boolean, value: T) -> (),
	ForEach: (self: RemoteProperty<T>, callback: (player: Player, value: T) -> ()) -> (),
	Iter: (self: RemoteProperty<T>) -> () -> (Player, T),
	ClearFor: (self: RemoteProperty<T>, player: Player) -> (),
	ClearAll: (self: RemoteProperty<T>) -> (),
	Observe: (self: RemoteProperty<T>, callback: (newValue: T, oldValue: T) -> ()) -> () -> (),
	ObserveFor: (self: RemoteProperty<T>, player: Player, callback: (newValue: T, oldValue: T) -> ()) -> () -> (),
	ObserveForEach: (self: RemoteProperty<T>, callback: (player: Player, value: T) -> ()) -> () -> (),
	Destroy: (self: RemoteProperty<T>) -> (),
}

-- Server-only per-player property (no replication)
export type ServerProperty<T> = {
	Get: (self: ServerProperty<T>) -> T,
	Set: (self: ServerProperty<T>, value: T) -> (),
	SetFor: (self: ServerProperty<T>, player: Player, value: T) -> (),
	GetFor: (self: ServerProperty<T>, player: Player) -> T,
	ClearFor: (self: ServerProperty<T>, player: Player) -> (),
	ClearAll: (self: ServerProperty<T>) -> (),
	ForEach: (self: ServerProperty<T>, callback: (player: Player, value: T) -> ()) -> (),
	Iter: (self: ServerProperty<T>) -> () -> (Player, T),
	Observe: (self: ServerProperty<T>, callback: (newValue: T, oldValue: T) -> ()) -> () -> (),
	ObserveFor: (self: ServerProperty<T>, player: Player, callback: (newValue: T, oldValue: T) -> ()) -> () -> (),
	ObserveForEach: (self: ServerProperty<T>, callback: (player: Player, value: T) -> ()) -> () -> (),
	Destroy: (self: ServerProperty<T>) -> (),
}

-- Client-side remote property
export type ClientRemoteProperty<T> = {
	Get: (self: ClientRemoteProperty<T>) -> T,
	OnReady: (self: ClientRemoteProperty<T>) -> any, -- Returns Promise
	Observe: (self: ClientRemoteProperty<T>, callback: (newValue: T) -> ()) -> () -> (),
	IsReady: (self: ClientRemoteProperty<T>) -> boolean,
	Destroy: (self: ClientRemoteProperty<T>) -> (),
}

-- Shared local property (client-only or server-only)
export type LocalProperty<T> = {
	Get: (self: LocalProperty<T>) -> T,
	Set: (self: LocalProperty<T>, value: T) -> (),
	Observe: (self: LocalProperty<T>, observer: (value: T) -> ()) -> any, -- Signal connection or cleanup function
	Changed: any, -- Signal
	IsReady: (self: LocalProperty<T>) -> boolean,
	OnReady: (self: LocalProperty<T>) -> any, -- Promise
	Destroy: (self: LocalProperty<T>) -> (),
}

-- ============================================================================
-- SERVICE TYPES
-- ============================================================================

-- Service definition (what you pass to CreateService)
export type ServiceDef<T = {}> = T & {
	Name: string,
	Dependencies: {string}?,
	Client: { [any]: any }?,
	Middleware: Middleware?,
	KnitInit: ((self: any) -> ())?,
	KnitStart: ((self: any) -> ())?,
	-- RunService lifecycle hooks
	OnHeartbeat: ((self: any, dt: number) -> ())?,
	OnStepped: ((self: any, t: number, dt: number) -> ())?,
	[any]: any,
}

-- Service client table
export type ServiceClient = {
	Server: any, -- Reference to parent service (breaks circular type reference)
	[any]: any,
}

-- Created service instance
export type Service<T = {}> = T & {
	Name: string,
	Client: ServiceClient,
	KnitComm: any,
	_Trove: any,
	KnitAdd: (self: Service<T>, obj: any, cleanupMethod: string?) -> any,
	KnitInit: ((self: Service<T>) -> ())?,
	KnitStart: ((self: Service<T>) -> ())?,
	-- RunService lifecycle hooks (server only)
	OnHeartbeat: ((self: Service<T>, dt: number) -> ())?,
	OnStepped: ((self: Service<T>, t: number, dt: number) -> ())?,
}

-- ============================================================================
-- CONTROLLER TYPES
-- ============================================================================

-- Controller definition (what you pass to CreateController)
export type ControllerDef<T = {}> = T & {
	Name: string,
	RenderPriority: number?, -- For BindToRenderStep priority control
	KnitInit: ((self: any) -> ())?,
	KnitStart: ((self: any) -> ())?,
	OnEnable: ((self: any) -> ())?,
	OnDisable: ((self: any) -> ())?,
	-- RunService lifecycle hooks
	OnHeartbeat: ((self: any, dt: number) -> ())?,
	OnStepped: ((self: any, t: number, dt: number) -> ())?,
	OnRenderStepped: ((self: any, dt: number) -> ())?,
	[any]: any,
}

-- Created controller instance
export type Controller<T = {}> = T & {
	Name: string,
	RenderPriority: number?, -- For BindToRenderStep priority control
	_Trove: any,
	_InputContext: any?,
	_KnitEnabled: boolean,
	KnitAdd: (self: Controller<T>, obj: any, cleanupMethod: string?) -> any,
	KnitEnable: (self: Controller<T>) -> (),
	KnitDisable: (self: Controller<T>) -> (),
	KnitInit: ((self: Controller<T>) -> ())?,
	KnitStart: ((self: Controller<T>) -> ())?,
	OnEnable: ((self: Controller<T>) -> ())?,
	OnDisable: ((self: Controller<T>) -> ())?,
	-- RunService lifecycle hooks
	OnHeartbeat: ((self: Controller<T>, dt: number) -> ())?,
	OnStepped: ((self: Controller<T>, t: number, dt: number) -> ())?,
	OnRenderStepped: ((self: Controller<T>, dt: number) -> ())?,
}

-- ============================================================================
-- VIEW TYPES
-- ============================================================================

-- View definition (what you pass to CreateView)
export type ViewDef<T = {}> = T & {
	Name: string,
	Tag: string?,
	RenderPriority: number?, -- For BindToRenderStep priority control
	KnitInit: ((self: any) -> ())?,
	KnitStart: ((self: any) -> ())?,
	KnitEnable: ((self: any) -> ())?,
	KnitDisable: ((self: any) -> ())?,
	-- RunService lifecycle hooks
	OnHeartbeat: ((self: any, dt: number) -> ())?,
	OnStepped: ((self: any, t: number, dt: number) -> ())?,
	OnRenderStepped: ((self: any, dt: number) -> ())?,
	[any]: any,
}

-- Created view instance
export type View<T = {}> = T & {
	Name: string,
	Tag: string?,
	RenderPriority: number?, -- For BindToRenderStep priority control
	Instance: Instance?,
	_Trove: any,
	KnitAdd: (self: View<T>, obj: any, cleanupMethod: string?) -> any,
	KnitInit: ((self: View<T>) -> ())?,
	KnitStart: ((self: View<T>) -> ())?,
	KnitEnable: ((self: View<T>) -> ())?,
	KnitDisable: ((self: View<T>) -> ())?,
	-- RunService lifecycle hooks
	OnHeartbeat: ((self: View<T>, dt: number) -> ())?,
	OnStepped: ((self: View<T>, t: number, dt: number) -> ())?,
	OnRenderStepped: ((self: View<T>, dt: number) -> ())?,
}

-- ============================================================================
-- DEFINITION REGISTRY TYPES
-- ============================================================================

--[=[
	@interface ServiceDefinitions
	@within KnitTypes
	Table used to register Service types for autocompletion.
	User should add their services to this table definition in their own types file or here.
]=]
export type ServiceDefinitions = {
	[string]: Service<any>,
}

--[=[
	@interface ControllerDefinitions
	@within KnitTypes
	Table used to register Controller types for autocompletion.
	User should add their controllers to this table definition in their own types file or here.
]=]
export type ControllerDefinitions = {
	[string]: Controller<any>,
}

--[=[
	@interface ViewDefinitions
	@within KnitTypes
	Table used to register View types for autocompletion.
	User should add their views to this table definition in their own types file or here.
]=]
export type ViewDefinitions = {
	[string]: View<any>,
}

-- ============================================================================
-- KNIT OPTIONS TYPES
-- ============================================================================

-- Options for KnitClient.Start()
export type KnitClientOptions = {
	ServicePromises: boolean?,
	Middleware: Middleware?,
	PerServiceMiddleware: { [string]: Middleware }?,
}

-- Options for KnitServer.Start()
export type KnitServerOptions = {
	Middleware: Middleware?,
}

-- ============================================================================
-- CLIENT SERVICE PROXY TYPE
-- ============================================================================

-- Proxy type for accessing services from client
export type ClientService = {
	[string]: any,
}

return {}
