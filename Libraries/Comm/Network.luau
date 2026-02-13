local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[
    Network.luau
    
    Abstracts the creation and fetching of signals using Knit's Comm library.
    Handles the underlying ServerComm/ClientComm instantiation and folder management.
]]

-- Setup Root Folder
local RootFolder
if RunService:IsServer() then
    RootFolder = ReplicatedStorage:FindFirstChild("Networking")
    if not RootFolder then
        RootFolder = Instance.new("Folder")
        RootFolder.Name = "Networking"
        RootFolder.Parent = ReplicatedStorage
    end
else
    RootFolder = ReplicatedStorage:WaitForChild("Networking", 60)
    if not RootFolder then
        error("Networking folder failed to replicate within 60 seconds.")
    end
end

-- Setup Comm
local Comm
if RunService:IsServer() then
    local ServerComm = require(script.Parent.ServerComm)
    Comm = ServerComm.new(RootFolder, "Networking")
else
    local ClientComm = require(script.Parent.ClientComm)
    Comm = ClientComm.new(RootFolder, false, "Networking")
end

local Network = {}

function Network.Signal(options)
    local name = options.name
    assert(name, "Signal options must include a 'name' field")
    
    local signal
    if RunService:IsServer() then
        signal = Comm:CreateSignal(name, options)
    else
        -- Client: GetSignal waits for the RemoteEvent
        signal = Comm:GetSignal(name, nil, nil, options.schema)
    end
    
    -- Expose schema on the signal object for testing convenience
    signal._schema = options.schema
    
    return signal
end

function Network.CreateSignal(options)
    return Network.Signal(options)
end

return Network
