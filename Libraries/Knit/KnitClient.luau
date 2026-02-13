--[=[
	@class KnitClient
	@client
	
	Client-side Knit framework for consuming services and controllers.
	
	## Quick Start - Controller
	```lua
	local Knit = require(ReplicatedStorage.Knit.KnitClient)
	local KnitSchema = require(ReplicatedStorage.Knit.Util.Comm.KnitSchema)
	
	local MyController = Knit.CreateController({
		Name = "MyController",
		RenderPriority = Enum.RenderPriority.Camera.Value, -- Optional: for BindToRenderStep
	})
	
	function MyController:KnitInit()
		-- Get service from server
		self.MyService = Knit.GetService("MyService")
	end
	
	function MyController:KnitStart()
		-- Connect to server signals
		self.MyService.OnPlayerAction:Connect(function(data)
			print("Action:", data.action, "at", data.position)
		end)
		
		-- Observe property changes
		self.MyService.Health:Observe(function(newValue)
			print("Health changed to:", newValue)
		end)
		
		-- Call server methods (returns Promise)
		self.MyService:GetStats({ playerId = 123 }):andThen(function(stats)
			print("Kills:", stats.kills, "Deaths:", stats.deaths)
		end)
		
		-- Fire signals to server
		self.MyService.OnPlayerAction:Fire({
			action = "Jump",
			position = Vector3.new(10, 5, 20),
		})
	end
	
	-- RunService lifecycle hooks (auto-connected after KnitStart)
	function MyController:OnHeartbeat(dt) end      -- Every frame, after physics
	function MyController:OnStepped(t, dt) end     -- Every frame, before physics
	function MyController:OnRenderStepped(dt) end  -- Every frame, for rendering (client only)
	```
	
	## Service Consumption
	
	### Signals (Server -> Client or Client -> Server)
	```lua
	local MyService = Knit.GetService("MyService")
	
	-- Listen to server events
	MyService.OnHit:Connect(function(data)
		-- data is auto-deserialized by schema
	end)
	
	-- Fire events to server
	MyService.Shoot:Fire({
		origin = Vector3.new(0, 5, 0),
		direction = Vector3.new(1, 0, 0),
	})
	```
	
	### Properties (Auto-synced State)
	```lua
	-- Get current value
	local health = MyService.Health:Get()
	
	-- Observe changes
	local unsubscribe = MyService.Health:Observe(function(newHealth)
		updateHealthBar(newHealth)
	end)
	
	-- Wait for initial sync
	MyService.Health:OnReady():andThen(function(value)
		print("Initial health:", value)
	end)
	```
	
	### Methods (Request/Response)
	```lua
	-- Returns a Promise
	MyService:GetWeaponStats({ weaponId = "Rifle" })
		:andThen(function(stats)
			print("Damage:", stats.damage)
		end)
		:catch(function(err)
			warn("Request failed:", err)
		end)
	```
	
	## Controller Lifecycle
	1. `KnitInit()` - Initialize controller (can get services)
	2. `KnitStart()` - Start controller (all controllers initialized)
	3. `OnHeartbeat(dt)` - Auto-connected to RunService.Heartbeat
	4. `OnStepped(t, dt)` - Auto-connected to RunService.Stepped
	5. `OnRenderStepped(dt)` - Auto-connected to RunService.RenderStepped
	
	## Trove Cleanup
	```lua
	function MyController:KnitStart()
		-- Automatically cleaned up on KnitDisable
		self:KnitAdd(someEvent:Connect(handler))
		self:KnitAdd(somePart) -- Destroys the part
		self:KnitAdd(function() cleanup() end)
	end
	```
]=]

local Types = require(script.Parent.Types)

export type Middleware = Types.Middleware
export type ClientMiddleware = Types.ClientMiddleware
export type ClientMiddlewareFn = Types.ClientMiddlewareFn
export type ControllerDef<T = {}> = Types.ControllerDef<T>
export type Controller<T = {}> = Types.Controller<T>
export type ClientService = Types.ClientService
export type ClientRemoteSignal = Types.ClientRemoteSignal
export type ClientRemoteProperty<T> = Types.ClientRemoteProperty<T>
export type KnitOptions = Types.KnitClientOptions

-- LocalProperty type for client-only properties
export type LocalProperty<T> = {
	Get: (self: any) -> T,
	Set: (self: any, value: T) -> (),
	Observe: (self: any, observer: (value: T) -> ()) -> RBXScriptConnection,
	Changed: any, -- Signal
	IsReady: (self: any) -> boolean,
	OnReady: (self: any) -> any, -- Promise
	Destroy: (self: any) -> (),
}



type Service = ClientService

local defaultOptions: KnitOptions = {
	ServicePromises = true,
	Middleware = nil,
	PerServiceMiddleware = {},
}

local selectedOptions = nil

local KnitClient = {}
KnitClient.Player = game:GetService("Players").LocalPlayer
KnitClient.Util = script.Parent.Util

local Promise = require(script.Parent.Parent.Promise)
local Comm = require(script.Parent.Parent.Comm)
local ClientComm = Comm.ClientComm
local BufferNet = Comm.BufferNet
local Trove = require(script.Parent.Parent.Trove)
local Input = require(script.Parent.Parent.Input)
local RunService = game:GetService("RunService")


local controllers: { [string]: Controller } = {}
KnitClient.Controllers = controllers :: Types.ControllerDefinitions
KnitClient.BufferNet = BufferNet

local services: { [string]: Service } = {}
local servicesFolder = nil

local started = false
local startedComplete = false
local onStartedComplete = Instance.new("BindableEvent")

local function DoesControllerExist(controllerName: string): boolean
	return controllers[controllerName] ~= nil
end

local function GetServicesFolder()
	if not servicesFolder then
		servicesFolder = script.Parent:WaitForChild("Services")
	end
	return servicesFolder
end

local function GetMiddlewareForService(serviceName: string)
	local knitMiddleware = if selectedOptions.Middleware ~= nil then selectedOptions.Middleware else {}
	local serviceMiddleware = selectedOptions.PerServiceMiddleware[serviceName]
	
	if serviceMiddleware then
		local inbound = {}
		local outbound = {}
		
		if knitMiddleware.Inbound then table.move(knitMiddleware.Inbound, 1, #knitMiddleware.Inbound, 1, inbound) end
		if serviceMiddleware.Inbound then table.move(serviceMiddleware.Inbound, 1, #serviceMiddleware.Inbound, #inbound + 1, inbound) end
		
		if knitMiddleware.Outbound then table.move(knitMiddleware.Outbound, 1, #knitMiddleware.Outbound, 1, outbound) end
		if serviceMiddleware.Outbound then table.move(serviceMiddleware.Outbound, 1, #serviceMiddleware.Outbound, #outbound + 1, outbound) end
		
		return {Inbound = inbound, Outbound = outbound}
	end
	
	return knitMiddleware
end

local function BuildService(serviceName: string)
	local folder = GetServicesFolder()
	local middleware = GetMiddlewareForService(serviceName)
	local clientComm = ClientComm.new(folder, selectedOptions.ServicePromises, serviceName)
	local service = clientComm:BuildObject(middleware.Inbound, middleware.Outbound)
	services[serviceName] = service
	return service
end

--[=[
	Creates a new controller with automatic type inference.
	
	@param controllerDef ControllerDef -- The controller definition table
	@return Controller -- The created controller with full type information
	
	Example:
	```lua
	type MyControllerDef = {
		value: number,
		DoSomething: (self: MyControllerDef) -> (),
	}
	
	local MyController = Knit.CreateController({
		Name = "MyController",
		value = 0,
	}) :: Knit.Controller<MyControllerDef>
	
	function MyController:DoSomething()
		self.value += 1 -- Full autocomplete!
	end
	```
]=]
function KnitClient.CreateController<T>(controllerDef: ControllerDef & T): Controller & T
	assert(type(controllerDef) == "table", `Controller must be a table; got {type(controllerDef)}`)
	assert(type(controllerDef.Name) == "string", `Controller.Name must be a string; got {type(controllerDef.Name)}`)
	assert(#controllerDef.Name > 0, "Controller.Name must be a non-empty string")
	assert(not DoesControllerExist(controllerDef.Name), `Controller {controllerDef.Name} already exists`)
	assert(not started, `Controllers cannot be created after calling "Knit.Start()"`)
	local controller = controllerDef :: any
	
	-- Input System & Lifecycle Injection
	controller._Trove = Trove.new()
	controller._KnitEnabled = false
	
	if controller.Input and Input.IsContextDefinition(controller.Input) then
		controller._InputContext = Input.Utils.CreateContextFromSchema(controller, controller.Input)
		controller.Input = controller._InputContext
		controller._InputContext:Disable()
	end
	
	function controller:KnitEnable()
		if self._KnitEnabled then return end
		self._KnitEnabled = true
		
		if self._InputContext then
			self._InputContext:Enable()
		end
		
		if self.OnEnable then
			self:OnEnable()
		end
	end
	
	function controller:KnitDisable()
		if not self._KnitEnabled then return end
		self._KnitEnabled = false
		
		if self._InputContext then
			self._InputContext:Disable()
		end
		
		self._Trove:Clean()
		
		if self.OnDisable then
			self:OnDisable()
		end
	end
	
	function controller:KnitAdd(obj, cleanupMethod)
		if type(obj) == "table" and not cleanupMethod and not (obj.Destroy or obj.Disconnect or obj.destroy or obj.disconnect) then
			local isArray = false
			for k in pairs(obj) do
				if type(k) == "number" then
					isArray = true
					break
				end
			end
			if isArray then
				for _, item in ipairs(obj) do
					self._Trove:Add(item)
				end
				return obj
			end
		end
		return self._Trove:Add(obj, cleanupMethod)
	end

	controllers[controller.Name] = controller
	return controller
end

function KnitClient.AddControllers(parent: Instance): { Controller }
	assert(not started, `Controllers cannot be added after calling "Knit.Start()"`)
	local addedControllers = {}
	for _, v in parent:GetChildren() do
		if v:IsA("ModuleScript") and v.Name:find("Controller") then
			table.insert(addedControllers, require(v))
		end
	end
	return addedControllers
end

function KnitClient.AddControllersDeep(parent: Instance): { Controller }
	assert(not started, `Controllers cannot be added after calling "Knit.Start()"`)
	local addedControllers = {}
	for _, v in parent:GetDescendants() do
		if v:IsA("ModuleScript") and v.Name:find("Controller") then
			table.insert(addedControllers, require(v))
		end
	end
	return addedControllers
end

--[=[
	Gets a service proxy from the server with type inference support.
	
	@param serviceName string -- The name of the service
	@return ClientService -- The service proxy
	
	Example:
	```lua
	local MyService = Knit.GetService("MyService") :: MyServiceClientType
	MyService:GetCounter():andThen(function(count)
		print(count)
	end)
	```
]=]
function KnitClient.GetService<T>(serviceName: string): Service & T
	local service = services[serviceName]
	if service then
		return service :: any
	end
	assert(started, "Cannot call GetService until Knit has been started")
	assert(type(serviceName) == "string", `ServiceName must be a string; got {type(serviceName)}`)
	return BuildService(serviceName) :: any
end


--[=[
	Gets a controller by name with type inference support.
	
	@param controllerName string -- The name of the controller
	@return Controller -- The controller instance
	
	Example:
	```lua
	local MyController = Knit.GetController("MyController") :: MyControllerType
	MyController:DoSomething() -- Full autocomplete!
	```
]=]
function KnitClient.GetController<T>(controllerName: string): Controller & T
	local controller = controllers[controllerName]
	if controller then
		return controller :: any
	end
	assert(started, "Cannot call GetController until Knit has been started")
	assert(type(controllerName) == "string", `ControllerName must be a string; got {type(controllerName)}`)
	error(`Could not find controller "{controllerName}". Check to verify a controller with this name exists.`, 2)
end

function KnitClient.GetControllers(): { [string]: Controller }
	assert(started, "Cannot call GetControllers until Knit has been started")
	return controllers
end

function KnitClient.Start(options: KnitOptions?)
	if started then
		return Promise.reject("Knit already started")
	end
	started = true
	table.freeze(controllers)
	if options == nil then
		selectedOptions = defaultOptions
	else
		assert(typeof(options) == "table", `KnitOptions should be a table or nil; got {typeof(options)}`)
		selectedOptions = options
		for k, v in defaultOptions do
			if selectedOptions[k] == nil then
				selectedOptions[k] = v
			end
		end
	end
	if type(selectedOptions.PerServiceMiddleware) ~= "table" then
		selectedOptions.PerServiceMiddleware = {}
	end
	return Promise.new(function(resolve)
		local promisesStartControllers = {}
		for _, controller in controllers do
			if type(controller.KnitInit) == "function" then
				table.insert(
					promisesStartControllers,
					Promise.new(function(r)
						debug.setmemorycategory(controller.Name)
						controller:KnitInit()
						r()
					end)
				)
			end
		end
		resolve(Promise.all(promisesStartControllers))
	end):andThen(function()
		-- Helper to connect RunService lifecycle hooks
		local function ConnectLifecycleHooks(module)
			-- OnHeartbeat
			if type(module.OnHeartbeat) == "function" then
				module:KnitAdd(RunService.Heartbeat:Connect(function(dt)
					module:OnHeartbeat(dt)
				end))
			end
			
			-- OnStepped
			if type(module.OnStepped) == "function" then
				module:KnitAdd(RunService.Stepped:Connect(function(t, dt)
					module:OnStepped(t, dt)
				end))
			end
			
			-- OnRenderStepped (client only, but we're already in KnitClient)
			if type(module.OnRenderStepped) == "function" then
				if module.RenderPriority then
					-- Use BindToRenderStep for priority control
					local renderName = module.Name .. "_RenderStep"
					RunService:BindToRenderStep(renderName, module.RenderPriority, function(dt)
						module:OnRenderStepped(dt)
					end)
					module:KnitAdd(function()
						RunService:UnbindFromRenderStep(renderName)
					end)
				else
					module:KnitAdd(RunService.RenderStepped:Connect(function(dt)
						module:OnRenderStepped(dt)
					end))
				end
			end
		end
		
		for _, controller in controllers do
			if type(controller.KnitStart) == "function" then
				task.spawn(function()
					debug.setmemorycategory(controller.Name)
					controller:KnitStart()
					ConnectLifecycleHooks(controller)
				end)
			else
				-- Still connect lifecycle hooks even without KnitStart
				task.spawn(function()
					debug.setmemorycategory(controller.Name)
					ConnectLifecycleHooks(controller)
				end)
			end
		end
		startedComplete = true
		onStartedComplete:Fire()
		task.defer(function()
			onStartedComplete:Destroy()
		end)
	end)
end

function KnitClient.OnStart()
	if startedComplete then
		return Promise.resolve()
	else
		return Promise.fromEvent(onStartedComplete.Event)
	end
end

--[=[
	Creates a client-only property (LocalProperty) that does NOT replicate to the server.
	
	This is useful for local state management in controllers, such as UI state,
	cached values, or any client-side reactive state.
	
	@param initialValue any -- The initial value of the property
	@return LocalProperty -- The created property
	
	Example:
	```lua
	local MyController = Knit.CreateController({
		Name = "MyController",
	})
	
	function MyController:KnitInit()
		-- Create client-only properties
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
]=]
local LocalProperty = require(script.Parent.Util.LocalProperty)

function KnitClient.CreateProperty<T>(initialValue: T)
	return LocalProperty.new(initialValue)
end

function KnitClient.Property<T>(initialValue: T)
	return KnitClient.CreateProperty(initialValue)
end

return KnitClient
