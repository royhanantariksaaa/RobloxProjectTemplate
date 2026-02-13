--[[
    @class SafePlayerEvent
    @desc SafePlayerEvent is a utility class that provides safe ways to handle player events.
    Automatically handles connection cleanup, existing instances, and proper lifecycle management.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Trove = require(script.Parent.Trove)

local SafePlayerEvent = {}
SafePlayerEvent.__index = SafePlayerEvent

local IS_CLIENT = RunService:IsClient()

export type Config = {
    isLocal: boolean?,
    
    -- Player Events
    playerAddedCallback: ((Player) -> ())?,
    playerRemovingCallback: ((Player) -> ())?,
    
    -- Character Events
    characterAddedCallback: ((Player, Model) -> ())?,
    characterRemovingCallback: ((Player, Model) -> ())?,
    characterDiedCallback: ((Player, Model, Humanoid) -> ())?,
    characterChildAddedCallback: ((Player, Model, Instance) -> ())?,
    characterChildRemovingCallback: ((Player, Model, Instance) -> ())?,
    characterEquippedCallback: ((Player, Model, Tool) -> ())?,
    characterUnequippedCallback: ((Player, Model, Tool) -> ())?,
    
    -- Humanoid Events
    humanoidRunningCallback: ((Player, Model, Humanoid, number) -> ())?,
    humanoidJumpingCallback: ((Player, Model, Humanoid) -> ())?,
    humanoidClimbingCallback: ((Player, Model, Humanoid, number) -> ())?,
    humanoidSwimmingCallback: ((Player, Model, Humanoid, number) -> ())?,
    humanoidFreeFallingCallback: ((Player, Model, Humanoid, boolean) -> ())?,
    humanoidSeatedCallback: ((Player, Model, Humanoid, boolean, BasePart?) -> ())?,
    humanoidStateChangedCallback: ((Player, Model, Humanoid, Enum.HumanoidStateType, Enum.HumanoidStateType) -> ())?,
    humanoidHealthChangedCallback: ((Player, Model, Humanoid, number) -> ())?,
    
    -- Backpack Events
    backpackAddedCallback: ((Player, Backpack) -> ())?,
    backpackRemovingCallback: ((Player, Backpack) -> ())?,
    backpackChildAddedCallback: ((Player, Backpack, Instance) -> ())?,
    backpackChildRemovingCallback: ((Player, Backpack, Instance) -> ())?,
    
    -- PlayerGui Events (Client Only)
    playerGuiAddedCallback: ((Player, PlayerGui) -> ())?,
    playerGuiChildAddedCallback: ((Player, PlayerGui, Instance) -> ())?,
    playerGuiChildRemovingCallback: ((Player, PlayerGui, Instance) -> ())?,
    
    -- Chat Events
    chattedCallback: ((Player, string, Player?) -> ())?,
    
    -- Leaderstats Events
    leaderstatsAddedCallback: ((Player, Folder) -> ())?,
    leaderstatsChildAddedCallback: ((Player, Folder, Instance) -> ())?,
    leaderstatsValueChangedCallback: ((Player, Folder, Instance, any) -> ())?,
    
    -- Attribute Events
    playerAttributeChangedCallback: ((Player, string) -> ())?,
    characterAttributeChangedCallback: ((Player, Model, string) -> ())?,
    
    -- Team Events
    teamChangedCallback: ((Player, Team?) -> ())?,
}

function SafePlayerEvent.new(config: Config)
    local self = setmetatable({}, SafePlayerEvent)
    self._trove = Trove.new()
    self._config = config
    
    self:_init()
    
    return self
end

function SafePlayerEvent:Destroy()
    self._trove:Destroy()
end

function SafePlayerEvent:_init()
    local config = self._config
    local isLocal = config.isLocal
    
    local function onPlayer(player: Player)
        if config.playerAddedCallback then
            task.spawn(config.playerAddedCallback, player)
        end
        
        self:_setupCharacterListeners(player)
        self:_setupBackpackListeners(player)
        self:_setupPlayerGuiListeners(player)
        self:_setupChatListeners(player)
        self:_setupLeaderstatsListeners(player)
        self:_setupPlayerAttributeListeners(player)
        self:_setupTeamListeners(player)
    end
    
    if isLocal then
        local player = Players.LocalPlayer
        if player then
            onPlayer(player)
        end
    else
        self._trove:Connect(Players.PlayerAdded, onPlayer)
        for _, player in Players:GetPlayers() do
            task.spawn(onPlayer, player)
        end
        
        if config.playerRemovingCallback then
            self._trove:Connect(Players.PlayerRemoving, function(player)
                config.playerRemovingCallback(player)
            end)
        end
    end
end

function SafePlayerEvent:_setupCharacterListeners(player: Player)
    local config = self._config
    
    -- Check if any character listeners are needed
    local needsCharacterListeners = config.characterAddedCallback or config.characterRemovingCallback or 
        config.characterDiedCallback or config.characterEquippedCallback or 
        config.characterUnequippedCallback or config.characterChildAddedCallback or 
        config.characterChildRemovingCallback or config.characterAttributeChangedCallback or
        config.humanoidRunningCallback or config.humanoidJumpingCallback or
        config.humanoidClimbingCallback or config.humanoidSwimmingCallback or
        config.humanoidFreeFallingCallback or config.humanoidSeatedCallback or
        config.humanoidStateChangedCallback or config.humanoidHealthChangedCallback
    
    if not needsCharacterListeners then
        return
    end

    local function onCharacter(character: Model)
        local charTrove = self._trove:Extend()
        
        -- Cleanup charTrove when character is removed
        local removingConn
        removingConn = player.CharacterRemoving:Connect(function(removedChar)
            if removedChar == character then
                if config.characterRemovingCallback then
                    task.spawn(config.characterRemovingCallback, player, character)
                end
                charTrove:Destroy()
                if removingConn then removingConn:Disconnect() end
            end
        end)
        self._trove:Add(removingConn)

        if config.characterAddedCallback then
            task.spawn(config.characterAddedCallback, player, character)
        end
        
        -- Setup Humanoid listeners
        self:_setupHumanoidListeners(player, character, charTrove)
        
        -- Character Attribute Changed
        if config.characterAttributeChangedCallback then
            charTrove:Connect(character.AttributeChanged, function(attributeName)
                config.characterAttributeChangedCallback(player, character, attributeName)
            end)
        end
        
        -- Combined ChildAdded Listener
        if config.characterEquippedCallback or config.characterChildAddedCallback then
            local function handleChild(child)
                if config.characterEquippedCallback and child:IsA("Tool") then
                    config.characterEquippedCallback(player, character, child)
                end
                if config.characterChildAddedCallback then
                    config.characterChildAddedCallback(player, character, child)
                end
            end

            charTrove:Connect(character.ChildAdded, handleChild)
            for _, child in character:GetChildren() do
                task.spawn(handleChild, child)
            end
        end

        -- Combined ChildRemoved Listener
        if config.characterUnequippedCallback or config.characterChildRemovingCallback then
            charTrove:Connect(character.ChildRemoved, function(child)
                if config.characterUnequippedCallback and child:IsA("Tool") then
                    config.characterUnequippedCallback(player, character, child)
                end
                if config.characterChildRemovingCallback then
                    config.characterChildRemovingCallback(player, character, child)
                end
            end)
        end
    end
    
    self._trove:Connect(player.CharacterAdded, onCharacter)
    if player.Character then
        task.spawn(onCharacter, player.Character)
    end
end

function SafePlayerEvent:_setupHumanoidListeners(player: Player, character: Model, charTrove)
    local config = self._config
    
    local needsHumanoidListeners = config.characterDiedCallback or
        config.humanoidRunningCallback or config.humanoidJumpingCallback or
        config.humanoidClimbingCallback or config.humanoidSwimmingCallback or
        config.humanoidFreeFallingCallback or config.humanoidSeatedCallback or
        config.humanoidStateChangedCallback or config.humanoidHealthChangedCallback
    
    if not needsHumanoidListeners then
        return
    end
    
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then return end
    
    if config.characterDiedCallback then
        charTrove:Connect(humanoid.Died, function()
            config.characterDiedCallback(player, character, humanoid)
        end)
    end
    
    if config.humanoidRunningCallback then
        charTrove:Connect(humanoid.Running, function(speed)
            config.humanoidRunningCallback(player, character, humanoid, speed)
        end)
    end
    
    if config.humanoidJumpingCallback then
        charTrove:Connect(humanoid.Jumping, function()
            config.humanoidJumpingCallback(player, character, humanoid)
        end)
    end
    
    if config.humanoidClimbingCallback then
        charTrove:Connect(humanoid.Climbing, function(speed)
            config.humanoidClimbingCallback(player, character, humanoid, speed)
        end)
    end
    
    if config.humanoidSwimmingCallback then
        charTrove:Connect(humanoid.Swimming, function(speed)
            config.humanoidSwimmingCallback(player, character, humanoid, speed)
        end)
    end
    
    if config.humanoidFreeFallingCallback then
        charTrove:Connect(humanoid.FreeFalling, function(active)
            config.humanoidFreeFallingCallback(player, character, humanoid, active)
        end)
    end
    
    if config.humanoidSeatedCallback then
        charTrove:Connect(humanoid.Seated, function(isSeated, seat)
            config.humanoidSeatedCallback(player, character, humanoid, isSeated, seat)
        end)
    end
    
    if config.humanoidStateChangedCallback then
        charTrove:Connect(humanoid.StateChanged, function(oldState, newState)
            config.humanoidStateChangedCallback(player, character, humanoid, oldState, newState)
        end)
    end
    
    if config.humanoidHealthChangedCallback then
        charTrove:Connect(humanoid.HealthChanged, function(health)
            config.humanoidHealthChangedCallback(player, character, humanoid, health)
        end)
    end
end

function SafePlayerEvent:_setupBackpackListeners(player: Player)
    local config = self._config
    
    if not (config.backpackAddedCallback or config.backpackRemovingCallback or 
            config.backpackChildAddedCallback or config.backpackChildRemovingCallback) then
        return
    end
    
    local function onBackpack(backpack: Backpack)
        local backpackTrove = self._trove:Extend()
        
        local removingConn
        removingConn = backpack.AncestryChanged:Connect(function(_, parent)
            if not parent then
                if config.backpackRemovingCallback then
                    task.spawn(config.backpackRemovingCallback, player, backpack)
                end
                backpackTrove:Destroy()
                if removingConn then removingConn:Disconnect() end
            end
        end)
        self._trove:Add(removingConn)
        
        if config.backpackAddedCallback then
            task.spawn(config.backpackAddedCallback, player, backpack)
        end
        
        if config.backpackChildAddedCallback then
            local function handleBackpackChild(child)
                config.backpackChildAddedCallback(player, backpack, child)
            end
            backpackTrove:Connect(backpack.ChildAdded, handleBackpackChild)
            for _, child in backpack:GetChildren() do
                task.spawn(handleBackpackChild, child)
            end
        end
        
        if config.backpackChildRemovingCallback then
            backpackTrove:Connect(backpack.ChildRemoved, function(child)
                config.backpackChildRemovingCallback(player, backpack, child)
            end)
        end
    end
    
    self._trove:Connect(player.ChildAdded, function(child)
        if child:IsA("Backpack") then
            onBackpack(child)
        end
    end)
    
    local existingBackpack = player:FindFirstChild("Backpack")
    if existingBackpack then
        task.spawn(onBackpack, existingBackpack)
    end
end

function SafePlayerEvent:_setupPlayerGuiListeners(player: Player)
    local config = self._config
    
    if not IS_CLIENT then return end
    if not (config.playerGuiAddedCallback or config.playerGuiChildAddedCallback or 
            config.playerGuiChildRemovingCallback) then
        return
    end
    
    local function onPlayerGui(playerGui: PlayerGui)
        local guiTrove = self._trove:Extend()
        
        if config.playerGuiAddedCallback then
            task.spawn(config.playerGuiAddedCallback, player, playerGui)
        end
        
        if config.playerGuiChildAddedCallback then
            local function handleGuiChild(child)
                config.playerGuiChildAddedCallback(player, playerGui, child)
            end
            guiTrove:Connect(playerGui.ChildAdded, handleGuiChild)
            for _, child in playerGui:GetChildren() do
                task.spawn(handleGuiChild, child)
            end
        end
        
        if config.playerGuiChildRemovingCallback then
            guiTrove:Connect(playerGui.ChildRemoved, function(child)
                config.playerGuiChildRemovingCallback(player, playerGui, child)
            end)
        end
    end
    
    local existingPlayerGui = player:FindFirstChild("PlayerGui")
    if existingPlayerGui then
        task.spawn(onPlayerGui, existingPlayerGui)
    else
        local conn
        conn = player.ChildAdded:Connect(function(child)
            if child:IsA("PlayerGui") then
                conn:Disconnect()
                onPlayerGui(child)
            end
        end)
        self._trove:Add(conn)
    end
end

function SafePlayerEvent:_setupChatListeners(player: Player)
    local config = self._config
    
    if not config.chattedCallback then return end
    
    self._trove:Connect(player.Chatted, function(message, recipient)
        config.chattedCallback(player, message, recipient)
    end)
end

function SafePlayerEvent:_setupLeaderstatsListeners(player: Player)
    local config = self._config
    
    if not (config.leaderstatsAddedCallback or config.leaderstatsChildAddedCallback or 
            config.leaderstatsValueChangedCallback) then
        return
    end
    
    local function onLeaderstats(leaderstats: Folder)
        local statsTrove = self._trove:Extend()
        
        if config.leaderstatsAddedCallback then
            task.spawn(config.leaderstatsAddedCallback, player, leaderstats)
        end
        
        local function setupValueListener(stat)
            if stat:IsA("ValueBase") then
                statsTrove:Connect(stat.Changed, function(newValue)
                    if config.leaderstatsValueChangedCallback then
                        config.leaderstatsValueChangedCallback(player, leaderstats, stat, newValue)
                    end
                end)
            end
        end
        
        if config.leaderstatsChildAddedCallback or config.leaderstatsValueChangedCallback then
            local function handleStatChild(child)
                if config.leaderstatsChildAddedCallback then
                    config.leaderstatsChildAddedCallback(player, leaderstats, child)
                end
                if config.leaderstatsValueChangedCallback then
                    setupValueListener(child)
                end
            end
            statsTrove:Connect(leaderstats.ChildAdded, handleStatChild)
            for _, child in leaderstats:GetChildren() do
                task.spawn(handleStatChild, child)
            end
        end
    end
    
    local existingLeaderstats = player:FindFirstChild("leaderstats")
    if existingLeaderstats and existingLeaderstats:IsA("Folder") then
        task.spawn(onLeaderstats, existingLeaderstats)
    else
        local conn
        conn = player.ChildAdded:Connect(function(child)
            if child.Name == "leaderstats" and child:IsA("Folder") then
                conn:Disconnect()
                onLeaderstats(child)
            end
        end)
        self._trove:Add(conn)
    end
end

function SafePlayerEvent:_setupPlayerAttributeListeners(player: Player)
    local config = self._config
    
    if not config.playerAttributeChangedCallback then return end
    
    self._trove:Connect(player.AttributeChanged, function(attributeName)
        config.playerAttributeChangedCallback(player, attributeName)
    end)
end

function SafePlayerEvent:_setupTeamListeners(player: Player)
    local config = self._config
    
    if not config.teamChangedCallback then return end
    
    self._trove:Connect(player:GetPropertyChangedSignal("Team"), function()
        config.teamChangedCallback(player, player.Team)
    end)
    
    -- Fire initial team if exists
    if player.Team then
        task.spawn(config.teamChangedCallback, player, player.Team)
    end
end


-- ============================================
-- Static Compatibility Methods (Quick Helpers)
-- ============================================

function SafePlayerEvent.PlayerAdded(callback)
    local event = SafePlayerEvent.new({
        isLocal = false,
        playerAddedCallback = callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.PlayerLeft(callback)
    local event = SafePlayerEvent.new({
        isLocal = false,
        playerRemovingCallback = callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.CharacterAdded(data: { isLocal: boolean, callback: (Player, Model) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        characterAddedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.CharacterRemoving(data: { isLocal: boolean, callback: (Player, Model) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        characterRemovingCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.CharacterDied(data: { isLocal: boolean, callback: (Player, Model, Humanoid) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        characterDiedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.CharacterEquipped(data: { isLocal: boolean, callback: (Player, Model, Tool) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        characterEquippedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.CharacterUnequipped(data: { isLocal: boolean, callback: (Player, Model, Tool) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        characterUnequippedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.Chatted(data: { isLocal: boolean, callback: (Player, string, Player?) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        chattedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.TeamChanged(data: { isLocal: boolean, callback: (Player, Team?) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        teamChangedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.HumanoidStateChanged(data: { isLocal: boolean, callback: (Player, Model, Humanoid, Enum.HumanoidStateType, Enum.HumanoidStateType) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        humanoidStateChangedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.HumanoidHealthChanged(data: { isLocal: boolean, callback: (Player, Model, Humanoid, number) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        humanoidHealthChangedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.BackpackChildAdded(data: { isLocal: boolean, callback: (Player, Backpack, Instance) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        backpackChildAddedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.BackpackChildRemoving(data: { isLocal: boolean, callback: (Player, Backpack, Instance) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        backpackChildRemovingCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.LeaderstatsValueChanged(data: { isLocal: boolean, callback: (Player, Folder, Instance, any) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        leaderstatsValueChangedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.PlayerAttributeChanged(data: { isLocal: boolean, callback: (Player, string) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        playerAttributeChangedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

function SafePlayerEvent.CharacterAttributeChanged(data: { isLocal: boolean, callback: (Player, Model, string) -> () })
    local event = SafePlayerEvent.new({
        isLocal = data.isLocal,
        characterAttributeChangedCallback = data.callback
    })
    return {
        Disconnect = function() event:Destroy() end
    }
end

return SafePlayerEvent
