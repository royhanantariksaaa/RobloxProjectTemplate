local Util = require(script.Parent.Util)
local HttpService = game:GetService("HttpService")
local Types = require(script.Parent.Types)
local Promise = require(script.Parent.Parent.Promise)
local ClientRemoteSignal = require(script.Parent.ClientRemoteSignal)
local ClientRemoteProperty = require(script.Parent.ClientRemoteProperty)

local Client = {}

local KnitSchema = require(script.Parent.KnitSchema)
local ClientPredicted = require(script.Parent.ClientPredicted) :: any

function Client.GetFunction(
	parent: Instance,
	name: string,
	usePromise: boolean,
	inboundMiddleware: Types.ClientMiddleware?,
	outboundMiddleware: Types.ClientMiddleware?,
	inboundSchema: any?,
	outboundSchema: any?
)
	assert(not Util.IsServer, "GetFunction must be called from the client")
	local folder = Util.GetCommSubFolder(parent, "RF"):Expect("Failed to get Comm RF folder")
	local rf = folder:WaitForChild(name, Util.WaitForChildTimeout)
	assert(rf ~= nil, "Failed to find RemoteFunction: " .. name)
	
	if rf:IsA("Folder") then
		return ClientPredicted.new(rf)
	end
	
	-- Auto-resolve schemas from attributes if not provided
	-- Note: Server's "inbound" (Request) is Client's "outbound"
	--       Server's "outbound" (Response) is Client's "inbound"
	if not outboundSchema then
		local schemaName = rf:GetAttribute("_inSchema")
		if schemaName then
			outboundSchema = KnitSchema.Defs[schemaName]
		end
	end
	if not inboundSchema then
		local schemaName = rf:GetAttribute("_outSchema")
		if schemaName then
			inboundSchema = KnitSchema.Defs[schemaName]
		end
	end
	
	local hasInbound = type(inboundMiddleware) == "table" and #inboundMiddleware > 0
	local hasOutbound = type(outboundMiddleware) == "table" and #outboundMiddleware > 0
	
	local function InvokeWithMiddleware(...)
		local args = table.pack(...)
		
		-- Detect and strip service proxy from arguments (when colon syntax is used)
		-- When calling `service:Method()`, Lua passes the service proxy as arg[1]
		if args.n >= 1 and type(args[1]) == "table" then
			local firstArg = args[1]
			local isServiceProxy = false
			
			-- Check for explicit marker (most reliable)
			if rawget(firstArg, "__isKnitServiceProxy") then
				isServiceProxy = true
			else
				-- Fallback: check for signal/event objects (for backwards compatibility)
				for _, v in pairs(firstArg) do
					if type(v) == "table" and (rawget(v, "_signal") or rawget(v, "_re")) then
						isServiceProxy = true
						break
					end
				end
			end
			
			if isServiceProxy then
				-- Shift all arguments left by 1 to remove the proxy
				local newArgs = { n = args.n - 1 }
				for i = 2, args.n do
					newArgs[i - 1] = args[i]
				end
				args = newArgs
			end
		end
		
		if hasOutbound then
			local success, result = Util.ProcessMiddleware(outboundMiddleware, args)
			if not success then
				return false, result
			end
		end

		-- Serialize arguments if outboundSchema is present
		if outboundSchema then
			local buf = KnitSchema.serialize(outboundSchema, args[1])
			args = table.pack(buf)
		end
		
		local success, res = pcall(function()
			return table.pack(rf:InvokeServer(table.unpack(args, 1, args.n)))
		end)
		
		if not success then
			return false, res
		end

		-- Deserialize result if inboundSchema is present
		if inboundSchema and res.n > 0 and typeof(res[1]) == "buffer" then
			local buf = res[1]
			local decoded = KnitSchema.deserialize(inboundSchema, buf)
			res = table.pack(decoded)
		end
		
		if hasInbound then
			local middlewareSuccess, result = Util.ProcessMiddleware(inboundMiddleware, res)
			if not middlewareSuccess then
				return true, result
			end
		end
		
		return true, table.unpack(res, 1, res.n)
	end
	
	if usePromise then
		return function(...)
			local args = table.pack(...)
			return Promise.new(function(resolve, reject)
				local results = table.pack(InvokeWithMiddleware(table.unpack(args, 1, args.n)))
				if results[1] then
					resolve(results[2])
				else
					reject(results[2])
				end
			end)
		end
	else
		return function(...)
			local results = table.pack(InvokeWithMiddleware(...))
			if results[1] then
				return table.unpack(results, 2, results.n)
			else
				error(results[2])
			end
		end
	end
end

function Client.GetSignal(
	parent: Instance,
	name: string,
	inboundMiddleware: Types.ClientMiddleware?,
	outboundMiddleware: Types.ClientMiddleware?,
	schema: any?, -- NEW: Optional KnitSchema schema
	deduplication: boolean? -- NEW: Enable deduplication (default: true)
)
	assert(not Util.IsServer, "GetSignal must be called from the client")
	local folder = Util.GetCommSubFolder(parent, "RE"):Expect("Failed to get Comm RE folder")
	local re = folder:WaitForChild(name, Util.WaitForChildTimeout)
	assert(re ~= nil, "Failed to find RemoteEvent: " .. name)
	
	-- Auto-resolve schema from attribute if not provided
	if not schema then
		local schemaDef = re:FindFirstChild("SchemaDef")
		if schemaDef and schemaDef:IsA("StringValue") then
			-- Decode schema from JSON
			local success, decoded = pcall(function()
				return HttpService:JSONDecode(schemaDef.Value)
			end)
			if success then
				schema = decoded
			else
				warn("Failed to decode SchemaDef for signal: " .. name)
			end
		else
			local schemaName = re:GetAttribute("_schema")
			if schemaName then
				schema = KnitSchema.Defs[schemaName]
			end
		end
	end
	
	return ClientRemoteSignal.new(re, inboundMiddleware, outboundMiddleware, schema, deduplication)
end

function Client.GetProperty(
	parent: Instance,
	name: string,
	inboundMiddleware: Types.ClientMiddleware?,
	outboundMiddleware: Types.ClientMiddleware?,
	schema: any?, -- NEW: Optional KnitSchema schema
	deduplication: boolean? -- NEW: Enable deduplication
)
	assert(not Util.IsServer, "GetProperty must be called from the client")
	local folder = Util.GetCommSubFolder(parent, "RP"):Expect("Failed to get Comm RP folder")
	local re = folder:WaitForChild(name, Util.WaitForChildTimeout)
	assert(re ~= nil, "Failed to find RemoteEvent for RemoteProperty: " .. name)
	
	-- Auto-resolve schema from attribute if not provided
	if not schema then
		local schemaDef = re:FindFirstChild("SchemaDef")
		if schemaDef and schemaDef:IsA("StringValue") then
			-- Decode schema from JSON
			local success, decoded = pcall(function()
				return HttpService:JSONDecode(schemaDef.Value)
			end)
			if success then
				schema = decoded
			else
				warn("Failed to decode SchemaDef for property: " .. name)
			end
		else
			local schemaName = re:GetAttribute("_schema")
			if schemaName then
				schema = KnitSchema.Defs[schemaName]
			end
		end
	end
	
	return ClientRemoteProperty.new(re, inboundMiddleware, outboundMiddleware, schema, deduplication)
end

return Client
