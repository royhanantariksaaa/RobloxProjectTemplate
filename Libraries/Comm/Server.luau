local RemoteProperty = require(script.Parent.RemoteProperty)
local RemoteSignal = require(script.Parent.RemoteSignal)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)
local KnitSchema = require(script.Parent.KnitSchema)
local ClientPredicted = require(script.Parent.ClientPredicted) :: any

local Server = {}

--[=[
	@within Comm
	@prop ServerComm ServerComm
]=]
--[=[
	@within Comm
	@prop ClientComm ClientComm
]=]

--[=[
	@within Comm
	@private
	@interface Server
	.BindFunction (parent: Instance, name: string, fn: FnBind, inboundMiddleware: ServerMiddleware?, outboundMiddleware: ServerMiddleware?): RemoteFunction
	.WrapMethod (parent: Instance, tbl: table, name: string, inboundMiddleware: ServerMiddleware?, outboundMiddleware: ServerMiddleware?): RemoteFunction
	.CreateSignal (parent: Instance, name: string, inboundMiddleware: ServerMiddleware?, outboundMiddleware: ServerMiddleware?): RemoteSignal
	.CreateProperty (parent: Instance, name: string, value: any, inboundMiddleware: ServerMiddleware?, outboundMiddleware: ServerMiddleware?): RemoteProperty
	Server Comm
]=]
--[=[
	@within Comm
	@private
	@interface Client
	.GetFunction (parent: Instance, name: string, usePromise: boolean, inboundMiddleware: ClientMiddleware?, outboundMiddleware: ClientMiddleware?): (...: any) -> any
	.GetSignal (parent: Instance, name: string, inboundMiddleware: ClientMiddleware?, outboundMiddleware: ClientMiddleware?): ClientRemoteSignal
	.GetProperty (parent: Instance, name: string, inboundMiddleware: ClientMiddleware?, outboundMiddleware: ClientMiddleware?): ClientRemoteProperty
	Client Comm
]=]

function Server.BindFunction(
	parent: Instance,
	name: string,
	func: Types.FnBind,
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	inboundSchema: any?, -- NEW: Schema for request
	outboundSchema: any?, -- NEW: Schema for response
	options: { ClientPrediction: boolean? }?
): RemoteFunction | any
	assert(Util.IsServer, "BindFunction must be called from the server")
	local folder = Util.GetCommSubFolder(parent, "RF"):Expect("Failed to get Comm RF folder")
	
	if options and options.ClientPrediction then
		local container = Instance.new("Folder")
		container.Name = name
		container.Parent = folder
		
		local cp = ClientPredicted.new(func)
		cp:Construct(container)
		return cp
	end

	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	
	local hasInbound = type(inboundMiddleware) == "table" and #inboundMiddleware > 0
	local hasOutbound = type(outboundMiddleware) == "table" and #outboundMiddleware > 0
	local hasInboundSchema = inboundSchema ~= nil and inboundSchema.fields ~= nil
	local hasOutboundSchema = outboundSchema ~= nil and outboundSchema.fields ~= nil
	
	if not hasInbound and not hasOutbound and not hasInboundSchema and not hasOutboundSchema then
		rf.OnServerInvoke = func
	else
		rf.OnServerInvoke = function(player, ...)
			local args = table.pack(...)
			
			-- NEW: KnitSchema deserialization for request
			if hasInboundSchema then
				local buf = args[1]
				-- Only deserialize if we actually received a buffer
				if typeof(buf) == "buffer" then
					local success, result = pcall(KnitSchema.deserialize, inboundSchema, buf)
					if not success then
						warn(`[RemoteFunction] Failed to deserialize {name} request: {result}`)
						return nil
					end
					if not KnitSchema.validate(inboundSchema, result) then
						warn(`[RemoteFunction] Validation failed for {name} request`)
						return nil
					end
					args = table.pack(result)
				end
				-- If not a buffer, args stays as-is (for backwards compatibility or when client doesn't have schema)
			end
			
			-- Process inbound middleware
			if hasInbound then
				local success, result = Util.ProcessMiddleware(inboundMiddleware, args)
				if not success then
					return result
				end
			end
			
			-- Call the function
			local results = table.pack(func(player, table.unpack(args, 1, args.n)))
			
			-- Process outbound middleware
			if hasOutbound then
				local success, result = Util.ProcessMiddleware(outboundMiddleware, results)
				if not success then
					return result
				end
			end
			
			-- NEW: KnitSchema serialization for response
			if hasOutboundSchema then
				local data = results[1]
				if not KnitSchema.validate(outboundSchema, data) then
					error(`[RemoteFunction] Invalid response data for {name}`)
				end
				local buf = KnitSchema.serialize(outboundSchema, data)
				return buf
			end
			
			return table.unpack(results, 1, results.n)
		end
	end
	
	if hasInboundSchema then
		rf:SetAttribute("_inSchema", inboundSchema.name)
	end
	if hasOutboundSchema then
		rf:SetAttribute("_outSchema", outboundSchema.name)
	end
	
	rf.Parent = folder
	return rf
end

function Server.WrapMethod(
	parent: Instance,
	tbl: {},
	name: string,
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	inboundSchema: any?,
	outboundSchema: any?,
	options: { ClientPrediction: boolean? }?
): RemoteFunction | any
	assert(Util.IsServer, "WrapMethod must be called from the server")
	local fn = tbl[name]
	assert(type(fn) == "function", "Value at index " .. name .. " must be a function; got " .. type(fn))
	return Server.BindFunction(parent, name, function(...)
		return fn(tbl, ...)
	end, inboundMiddleware, outboundMiddleware, inboundSchema, outboundSchema, options)
end

function Server.CreateSignal(
	parent: Instance,
	name: string,
	reliable: boolean?,
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	schema: any?, -- NEW: Optional KnitSchema schema
	clientToServerDeduplication: boolean?, -- NEW: Enable incoming deduplication
	serverToClientDeduplication: boolean? -- NEW: Enable outgoing deduplication
)
	assert(Util.IsServer, "CreateSignal must be called from the server")
	local folder = Util.GetCommSubFolder(parent, "RE"):Expect("Failed to get Comm RE folder")
	local rs = RemoteSignal.new(folder, name, reliable, inboundMiddleware, outboundMiddleware, schema, clientToServerDeduplication, serverToClientDeduplication)
	return rs
end

function Server.CreateProperty(
	parent: Instance,
	name: string,
	initialValue: any,
	inboundMiddleware: Types.ServerMiddleware?,
	outboundMiddleware: Types.ServerMiddleware?,
	schema: any?, -- NEW: Optional KnitSchema schema
	clientToServerDeduplication: boolean?, -- NEW: Enable incoming deduplication
	serverToClientDeduplication: boolean? -- NEW: Enable outgoing deduplication
)
	assert(Util.IsServer, "CreateProperty must be called from the server")
	local folder = Util.GetCommSubFolder(parent, "RP"):Expect("Failed to get Comm RP folder")
	local rp = RemoteProperty.new(folder, name, initialValue, inboundMiddleware, outboundMiddleware, schema, clientToServerDeduplication, serverToClientDeduplication)
	return rp
end

return Server
