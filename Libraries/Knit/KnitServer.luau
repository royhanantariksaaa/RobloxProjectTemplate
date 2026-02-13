--[=[
	@class KnitServer
	@server
	
	Server-side Knit framework for creating services and exposing API to clients.
	
	## Quick Start - Service
	```lua
	local Knit = require(ReplicatedStorage.Knit.KnitServer)
	local KnitSchema = require(ReplicatedStorage.Knit.Util.Comm.KnitSchema)
	
	local MyService = Knit.CreateService({
		Name = "MyService",
		Client = {
			-- Expose signals to client
			OnPlayerAction = Knit.CreateSignal(),
			
			-- Expose properties to client
			Health = Knit.CreateProperty(100),
		},
	})
	
	-- Expose methods to client (RemoteFunctions)
	function MyService.Client:GetStats(player)
		return { kills = 10, deaths = 5 }
	end
	
	function MyService:KnitInit()
		print("MyService Initialized")
	end
	
	function MyService:KnitStart()
		print("MyService Started")
		
		-- Connect to RunService events
		self:OnHeartbeat(function(dt)
			-- ...
		end)
	end
	
	return MyService
	```
]=]

local Types = require(script.Parent.Types)

export type Middleware = Types.Middleware
export type ServiceDef<T = {}> = Types.ServiceDef<T>
export type Service<T = {}> = Types.Service<T>
export type KnitOptions = Types.KnitServerOptions

local defaultOptions: KnitOptions = {
	Middleware = nil,
	PerServiceMiddleware = {},
}

local selectedOptions = nil

local KnitServer = {}
KnitServer.Util = script.Parent.Util

local Promise = require(script.Parent.Parent.Promise)
local Comm = require(script.Parent.Parent.Comm)
local ServerComm = Comm.ServerComm
local Trove = require(script.Parent.Parent.Trove)
local RunService = game:GetService("RunService")

local services: { [string]: Service } = {}
KnitServer.Services = services :: Types.ServiceDefinitions

local started = false
local startedComplete = false
local onStartedComplete = Instance.new("BindableEvent")

local function DoesServiceExist(serviceName: string): boolean
	return services[serviceName] ~= nil
end

--[=[
	Creates a new service with automatic type inference.
	
	@param serviceDef ServiceDef -- The service definition table
	@return Service -- The created service
]=]
function KnitServer.CreateService<T>(serviceDef: ServiceDef & T): Service & T
	assert(type(serviceDef) == "table", `Service must be a table; got {type(serviceDef)}`)
	assert(type(serviceDef.Name) == "string", `Service.Name must be a string; got {type(serviceDef.Name)}`)
	assert(#serviceDef.Name > 0, "Service.Name must be a non-empty string")
	assert(not DoesServiceExist(serviceDef.Name), `Service {serviceDef.Name} already exists`)
	assert(not started, `Services cannot be created after calling "Knit.Start()"`)
	
	local service = serviceDef :: any
	
	service._Trove = Trove.new()
	service._KnitEnabled = false
	
	if not service.Client then
		service.Client = { Server = service }
	else
		service.Client.Server = service
	end
	
	function service:KnitEnable()
		if self._KnitEnabled then return end
		self._KnitEnabled = true
		if self.OnEnable then
			self:OnEnable()
		end
	end
	
	function service:KnitDisable()
		if not self._KnitEnabled then return end
		self._KnitEnabled = false
		self._Trove:Clean()
		if self.OnDisable then
			self:OnDisable()
		end
	end
	
	function service:KnitAdd(obj, cleanupMethod)
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
	
	services[service.Name] = service
	return service
end

function KnitServer.AddServices(parent: Instance): { Service }
	assert(not started, `Services cannot be added after calling "Knit.Start()"`)
	local addedServices = {}
	for _, v in parent:GetChildren() do
		if v:IsA("ModuleScript") and v.Name:find("Service") then
			table.insert(addedServices, require(v))
		end
	end
	return addedServices
end

function KnitServer.AddServicesDeep(parent: Instance): { Service }
	assert(not started, `Services cannot be added after calling "Knit.Start()"`)
	local addedServices = {}
	for _, v in parent:GetDescendants() do
		if v:IsA("ModuleScript") and v.Name:find("Service") then
			table.insert(addedServices, require(v))
		end
	end
	return addedServices
end

--[=[
	Gets a service by name.
	
	@param serviceName string -- The name of the service
	@return Service -- The service instance
]=]
function KnitServer.GetService<T>(serviceName: string): Service & T
	local service = services[serviceName]
	if service then
		return service :: any
	end
	assert(started, "Cannot call GetService until Knit has been started")
	assert(type(serviceName) == "string", `ServiceName must be a string; got {type(serviceName)}`)
	error(`Could not find service "{serviceName}". Check to verify a service with this name exists.`, 2)
end

function KnitServer.GetServices(): { [string]: Service }
	assert(started, "Cannot call GetServices until Knit has been started")
	return services
end

function KnitServer.Start(options: KnitOptions?)
	if started then
		return Promise.reject("Knit already started")
	end
	started = true
	if not _G.KNIT_TEST_NO_FREEZE then
		table.freeze(services)
	end
	
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
		-- Create services folder
		local servicesFolder = script.Parent:FindFirstChild("Services")
		if not servicesFolder then
			servicesFolder = Instance.new("Folder")
			servicesFolder.Name = "Services"
			servicesFolder.Parent = script.Parent
		end
		
		-- Initialize services
		local promisesInitServices = {}
		for _, service in services do
			if type(service.KnitInit) == "function" then
				table.insert(promisesInitServices, Promise.new(function(r)
					debug.setmemorycategory(service.Name)
					service:KnitInit()
					r()
				end))
			end
		end
		
		resolve(Promise.all(promisesInitServices))
	end):andThen(function()
		-- Setup networking
		for _, service in services do
			local middleware = selectedOptions.Middleware
			local serviceMiddleware = selectedOptions.PerServiceMiddleware[service.Name]
			if serviceMiddleware then
				middleware = middleware or {}
				local inbound = {}
				local outbound = {}
				if middleware.Inbound then table.move(middleware.Inbound, 1, #middleware.Inbound, 1, inbound) end
				if serviceMiddleware.Inbound then table.move(serviceMiddleware.Inbound, 1, #serviceMiddleware.Inbound, #inbound + 1, inbound) end
				if middleware.Outbound then table.move(middleware.Outbound, 1, #middleware.Outbound, 1, outbound) end
				if serviceMiddleware.Outbound then table.move(serviceMiddleware.Outbound, 1, #serviceMiddleware.Outbound, #outbound + 1, outbound) end
				middleware = {Inbound = inbound, Outbound = outbound}
			end
			local serverComm = ServerComm.new(script.Parent.Services, service.Name)
			if type(service.Client) == "table" then
				service.Client.Server = nil
				serverComm:Wrap(service.Client, middleware)
				service.Client.Server = service
			end
		end
		
		-- Start services and connect lifecycle hooks
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
		end

		for _, service in services do
			if type(service.KnitStart) == "function" then
				task.spawn(function()
					debug.setmemorycategory(service.Name)
					service:KnitStart()
					ConnectLifecycleHooks(service)
				end)
			else
				task.spawn(function()
					debug.setmemorycategory(service.Name)
					ConnectLifecycleHooks(service)
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

function KnitServer.OnStart()
	if startedComplete then
		return Promise.resolve(nil)
	else
		return Promise.fromEvent(onStartedComplete.Event)
	end
end

--[=[
	Creates a Signal for communication between the server and client.
	
	@return RemoteSignal
]=]
function KnitServer.CreateSignal(options)
	return {
		__knitCommType = "Signal",
		options = options,
	}
end

--[=[
	Creates a Property for communication between the server and client.
	
	@param initialValue any -- The initial value
	@return RemoteProperty
]=]
function KnitServer.CreateProperty(initialValue, options)
	return {
		__knitCommType = "Property",
		initialValue = initialValue,
		options = options,
	}
end

--[=[
	Creates a UnreliableSignal for fire-and-forget communication.
	
	@return RemoteSignal
]=]
function KnitServer.CreateUnreliableSignal(options)
	local mergedOptions = options or {}
	mergedOptions.unreliable = true
	return {
		__knitCommType = "Signal",
		options = mergedOptions,
	}
end

return KnitServer
