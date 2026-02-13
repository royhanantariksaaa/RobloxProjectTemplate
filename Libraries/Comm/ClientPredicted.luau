local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local ClientPredicted = {} :: any
ClientPredicted.__index = ClientPredicted

local function DeepCompare(t1, t2)
	if type(t1) ~= type(t2) then return false end
	if type(t1) ~= "table" then return t1 == t2 end
	
	for k, v in pairs(t1) do
		if not DeepCompare(v, t2[k]) then return false end
	end
	for k, v in pairs(t2) do
		if not DeepCompare(v, t1[k]) then return false end
	end
	return true
end

if RunService:IsServer() then
	function ClientPredicted.new(fn)
		local self = setmetatable({}, ClientPredicted)
		self._fn = fn
		return self
	end

	function ClientPredicted:Construct(parent: Instance)
		self._request = Instance.new("RemoteEvent")
		self._request.Name = "Request"
		self._request.Parent = parent
		
		self._response = Instance.new("RemoteEvent")
		self._response.Name = "Response"
		self._response.Parent = parent

		self._request.OnServerEvent:Connect(function(player, pack)
			if type(pack) ~= "table" then return end
			local uuid = pack.UUID
			local args = pack.Args or {}

			-- Run Logic
			local results = table.pack(self._fn(player, table.unpack(args, 1, args.n)))

			-- Send Result back
			self._response:FireClient(player, {
				UUID = uuid,
				Results = results
			})
		end)

		return self
	end
elseif RunService:IsClient() then
	local Signal = require(script.Parent.Parent.Signal)

	ClientPredicted.__call = function(t, ...)
		return t:Fire(...)
	end

	function ClientPredicted.new(parent: Instance)
		local self = setmetatable({}, ClientPredicted)
		
		self._request = parent:WaitForChild("Request")
		self._response = parent:WaitForChild("Response")
		self._pending = {}
		self._predictor = nil
		self.OnReconciliation = Signal.new()

		self._response.OnClientEvent:Connect(function(pack)
			if type(pack) ~= "table" then return end
			local uuid = pack.UUID
			local serverResults = pack.Results

			local pending = self._pending[uuid]
			if pending then
				self._pending[uuid] = nil
				
				-- Compare
				local clientResults = pending.Results
				if not DeepCompare(clientResults, serverResults) then
					-- Mismatch! Fire Reconciliation
					if self.OnReconciliation:GetConnectionCount() == 0 then
						warn(`[Knit] Client Prediction mismatch for {self._request.Parent.Name}, but no Reconciliation handler connected! Server Result:`, serverResults)
					end
					self.OnReconciliation:Fire(table.unpack(serverResults, 1, serverResults.n))
				end
			end
		end)
		
		-- Cleanup Loop
		self._cleanupConnection = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			for uuid, data in pairs(self._pending) do
				if now - data.Time > 10 then
					self._pending[uuid] = nil
				end
			end
		end)

		return self
	end
	
	function ClientPredicted:SetPredictor(predictor)
		self._predictor = predictor
	end

	function ClientPredicted:Fire(...)
		local args = table.pack(...)
		local uuid = HttpService:GenerateGUID(false)
		
		-- 1. Run Predictor
		local results = {n=0}
		if self._predictor then
			results = table.pack(self._predictor(...))
		end

		-- 2. Store for verification
		self._pending[uuid] = {
			Results = results,
			Time = os.clock()
		}

		-- 3. Send to Server
		self._request:FireServer({
			UUID = uuid,
			Args = args
		})
		
		return table.unpack(results, 1, results.n)
	end
	
	function ClientPredicted:AsFunction()
		return function(...)
			return self:Fire(...)
		end
	end
	
	function ClientPredicted:Destroy()
		self.OnReconciliation:Destroy()
		if self._cleanupConnection then
			self._cleanupConnection:Disconnect()
		end
	end
end

return ClientPredicted
