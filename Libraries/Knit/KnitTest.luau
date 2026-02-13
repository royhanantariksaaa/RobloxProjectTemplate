--[[
    KnitTest - Minimal test utilities for Knit
    
    Provides helpers for integration testing with real services.
    Services are already initialized by init.server before tests run.
    
    Usage:
        local KnitTest = require(ReplicatedStorage.Library.Knit.KnitTest)
        
        local PlacementService = KnitTest.GetService("PlacementService")
        local testPlayer = KnitTest.createTestPlayer({ UserId = -12345 })
        
        -- Load real profile for test player
        local DataService = KnitTest.GetService("DataService")
        DataService:_LoadProfile(testPlayer)
        
        -- Now use services normally
        PlacementService:RequestPlacement(testPlayer, ...)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(script.Parent)

local KnitTest = {}

--[[
    Get an already-initialized service.
    Equivalent to Knit.GetService but makes test intent clear.
]]
function KnitTest.GetService(serviceName: string)
    return Knit.GetService(serviceName)
end

--[[
    Create a mock player object for testing.
    Uses negative UserIds to avoid collision with real player data.
    
    The mock player has the minimal interface needed for most services:
    - Name, UserId, ClassName
    - IsA() method
    - SetAttribute/GetAttribute methods
    
    @param config Optional configuration
    @param config.Name Player name (default: "TestPlayer")
    @param config.UserId Player UserId (default: random negative number)
]]
function KnitTest.createTestPlayer(config: { Name: string?, UserId: number? }?)
    local cfg = config or {}
    local attributes = {}
    
    local player = {
        Name = cfg.Name or "TestPlayer",
        UserId = cfg.UserId or -math.random(100000, 999999),
        ClassName = "Player",
    }
    
    function player:IsA(className: string): boolean
        return className == "Player" or className == "Instance"
    end
    
    function player:SetAttribute(key: string, value: any)
        attributes[key] = value
    end
    
    function player:GetAttribute(key: string): any
        return attributes[key]
    end
    
    function player:IsDescendantOf(_ancestor: Instance): boolean
        return false -- Mock players are never descendants of anything
    end
    
    return player
end

--[[
    Create a test instance with proper parenting.
    Instances are parented to ReplicatedStorage for schema validation.
    
    @param className The class name of the instance to create
    @param name Optional name for the instance
    @param parent Optional parent (defaults to ReplicatedStorage)
]]
function KnitTest.createTestInstance(className: string, name: string?, parent: Instance?): Instance
    local instance = Instance.new(className)
    instance.Name = name or className
    instance.Parent = parent or ReplicatedStorage
    return instance
end

return KnitTest
