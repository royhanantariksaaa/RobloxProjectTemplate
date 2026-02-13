--[[
    KnitSchema - Custom network buffer serialization with schema validation
    Inspired by Blink, optimized for Roblox networking
]]

local KnitSchema = {}
KnitSchema.__index = KnitSchema

-- Type definitions for schemas
export type Schema = {
    name: string,
    fields: {Field},
    size: number?, -- Minimum fixed size
    isDynamic: boolean,
}

--[=[
    @type FieldOptions
    @within KnitSchema
    
    Options for schema field definitions:
    - `min: number?` - Minimum value constraint (for numbers)
    - `max: number?` - Maximum value constraint (for numbers)
    - `optional: boolean?` - Whether the field can be nil
    - `arrayLength: number?` - Fixed array length
    - `delta: boolean?` - Enable automatic delta compression (sends difference from previous value)
    - `deltaFrom: string?` - Advanced: Manually specify field to compute delta from
]=]
export type FieldOptions = {
    min: number?, 
    max: number?, 
    optional: boolean?,
    arrayLength: number?, -- Fixed array length
    delta: boolean?, -- Enable automatic delta compression
    deltaFrom: string?, -- Field name to compute delta from
}

export type Field = {
    name: string,
    type: string,
    options: {
        min: number?, 
        max: number?, 
        optional: boolean?,
        arrayLength: number?, -- Fixed array length
        delta: boolean?, -- Enable automatic delta compression
        deltaFrom: string?, -- Field name to compute delta from
        elementType: string?, -- For lists
        keyType: string?, -- For maps
        valueType: string?, -- For maps
    }
}

-- Supported primitive types and their sizes (0 means dynamic)
local TYPE_SIZES = {
    uint8 = 1, uint16 = 2, uint32 = 4,
    int8 = 1, int16 = 2, int32 = 4,
    float32 = 4, float64 = 8,
    boolean = 1,
    vector2 = 8, vector3 = 12, cframe = 24, -- Pos(12) + Euler(12)
    player = 1, -- Registry ID as u8 (1 byte instead of 8!)
    bitfield = 1, -- Pack up to 8 booleans into 1 byte!
    enum = 1, -- Fixed string set as u8 (1 byte vs 4-10+ bytes!)
    intern = 1, -- Interned string as u8 (1 byte vs 4-20+ bytes!)
    quantized_vec2 = 0, -- Dynamic: 2-8 bytes based on precision/range
    quantized_vec3 = 0, -- Dynamic: 3-12 bytes based on precision/range
    quantized_cframe = 0, -- Dynamic: 6-24 bytes based on precision/range
    string = 0, -- Dynamic: u16 len + bytes
    list = 0,   -- Dynamic: u16 len + elements
    map = 0,    -- Dynamic: u16 len + pairs
    buffer = 0, -- Dynamic: u16 len + bytes
    instance = 2, -- u16 index to side-channel instance table
}

-- Helper: Calculate optimal integer type based on range and precision
local function getOptimalIntType(range: number, precision: number): (string, number)
    local maxValue = range / precision
    
    -- i8: -128 to 127 (can represent up to 128 with offset)
    if maxValue <= 128 then
        return "i8", 1
    -- i16: -32768 to 32767 (can represent up to 32768 with offset)  
    elseif maxValue <= 32768 then
        return "i16", 2
    else
        return "i32", 4
    end
end

-- ============================================================================
-- PLAYER REGISTRY SYSTEM
-- ============================================================================
-- Efficient player serialization: 1 byte (u8 ID) instead of 8 bytes (UserId)
-- Server assigns sequential IDs (0-255) which are reused when players leave
-- IDs are stored as player attributes and synced to clients automatically
-- Supports both real Players and bot Folders tagged with "Bot"

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local IS_SERVER = RunService:IsServer()

local BOT_TAG = "Bot"

KnitSchema.PlayerRegistry = {
    -- Server-side registry
    _idToPlayer = {}, -- [id] = Player or bot Folder
    _freeIds = {}, -- Stack of reusable IDs
    _nextId = 0, -- Next ID to assign (if no free IDs available)
    _botConnections = {}, -- [bot] = connection for cleanup
    
    -- Client-side registry
    _clientIdToPlayer = {}, -- [id] = Player (client-side)
    _pendingData = {}, -- Queue for data received before player registry sync
}

-- Server: Assign ID to player or bot
function KnitSchema.PlayerRegistry:_AssignId(entity: Instance): number
    assert(IS_SERVER, "AssignId can only be called on server")
    
    -- Check if entity already has an ID
    local existingId = entity:GetAttribute("_RegistryID")
    if existingId then return existingId end
    
    -- Reuse free ID or assign new one
    local id = table.remove(self._freeIds) or self._nextId
    if not self._freeIds[1] then
        self._nextId += 1
    end
    
    -- Store in registry and entity attribute
    self._idToPlayer[id] = entity
    entity:SetAttribute("_RegistryID", id)
    
    return id
end

-- Server: Free ID when player/bot leaves
function KnitSchema.PlayerRegistry:_FreeId(entity: Instance)
    assert(IS_SERVER, "FreeId can only be called on server")
    
    local id = entity:GetAttribute("_RegistryID")
    if id then
        self._idToPlayer[id] = nil
        table.insert(self._freeIds, id)
    end
    
    -- Clean up bot connection if exists
    if self._botConnections[entity] then
        self._botConnections[entity]:Disconnect()
        self._botConnections[entity] = nil
    end
end

-- Server: Register a bot folder
function KnitSchema.PlayerRegistry:RegisterBot(botFolder: Folder): number
    assert(IS_SERVER, "RegisterBot can only be called on server")
    
    local id = self:_AssignId(botFolder)
    
    -- Listen for bot removal
    self._botConnections[botFolder] = botFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self:_FreeId(botFolder)
        end
    end)
    
    return id
end

-- Server: Get ID from player or bot (reads attribute)
function KnitSchema.PlayerRegistry:GetId(entity: Instance): number?
    if IS_SERVER then
        -- On server, read from attribute or assign new
        local id = entity:GetAttribute("_RegistryID") :: number?
        if not id then
            id = self:_AssignId(entity)
        end
        return id
    else
        -- On client, read from attribute (replicated automatically)
        return entity:GetAttribute("_RegistryID") :: number?
    end
end

-- Get player or bot from ID
function KnitSchema.PlayerRegistry:GetPlayer(id: number): Instance?
    if IS_SERVER then
        return self._idToPlayer[id]
    else
        -- On client, first check real players
        for _, player in Players:GetPlayers() do
            if player:GetAttribute("_RegistryID") == id then
                return player
            end
        end
        -- Then check tagged bots
        for _, bot in CollectionService:GetTagged(BOT_TAG) do
            if bot:GetAttribute("_RegistryID") == id then
                return bot
            end
        end
        return nil
    end
end

-- Initialize registry on server
if IS_SERVER then
    -- Assign IDs to existing players
    for _, player in Players:GetPlayers() do
        KnitSchema.PlayerRegistry:_AssignId(player)
    end
    
    -- Also assign IDs to existing bots (tagged with "Bot")
    for _, bot in CollectionService:GetTagged(BOT_TAG) do
        KnitSchema.PlayerRegistry:RegisterBot(bot)
    end
    
    -- Handle new players
    Players.PlayerAdded:Connect(function(player)
        KnitSchema.PlayerRegistry:_AssignId(player)
    end)
    
    -- Free IDs when players leave
    Players.PlayerRemoving:Connect(function(player)
        KnitSchema.PlayerRegistry:_FreeId(player)
    end)
    
    -- Handle bots tagged with "Bot"
    CollectionService:GetInstanceAddedSignal(BOT_TAG):Connect(function(bot)
        KnitSchema.PlayerRegistry:RegisterBot(bot)
    end)
    
    CollectionService:GetInstanceRemovedSignal(BOT_TAG):Connect(function(bot)
        KnitSchema.PlayerRegistry:_FreeId(bot)
    end)
end

-- ============================================================================
-- STRING REGISTRY SYSTEM (Interning)
-- ============================================================================
-- Like PlayerRegistry but for common strings (weapon names, item IDs, etc.)
-- Reduces string overhead from 4-20+ bytes to 1 byte per occurrence

KnitSchema.StringRegistry = {
    _registries = {}, -- Named registries for different purposes
}

-- Get or create a named registry
function KnitSchema.StringRegistry:GetRegistry(name: string)
    if not self._registries[name] then
        self._registries[name] = {
            idToString = {},
            stringToId = {},
            nextId = 0,
        }
    end
    return self._registries[name]
end

-- Server: Register a string and get its ID
function KnitSchema.StringRegistry:Register(registryName: string, str: string): number
    local registry = self:GetRegistry(registryName)
    
    -- Check if already registered
    if registry.stringToId[str] then
        return registry.stringToId[str]
    end
    
    -- Assign new ID
    local id = registry.nextId
    registry.nextId += 1
    registry.idToString[id] = str
    registry.stringToId[str] = id
    
    return id
end

-- Get string from ID
function KnitSchema.StringRegistry:GetString(registryName: string, id: number): string?
    local registry = self:GetRegistry(registryName)
    return registry.idToString[id]
end

-- Get ID from string (or register if new)
function KnitSchema.StringRegistry:GetId(registryName: string, str: string): number
    local registry = self:GetRegistry(registryName)
    return registry.stringToId[str] or self:Register(registryName, str)
end

-- Schema builder
function KnitSchema.schema(name: string): Schema
    return {
        name = name,
        fields = {},
        size = 0,
        isDynamic = false,
    }
end

-- Add field to schema
function KnitSchema.field(schema: Schema, name: string, type: string, options: any?): Schema
    local fieldDef: Field = {
        name = name,
        type = type,
        options = options or {}
    }
    
    table.insert(schema.fields, fieldDef)
    
    -- Calculate size
    local typeSize = TYPE_SIZES[type]
    if typeSize == nil then error(`Unsupported type: {type}`) end

    if typeSize == 0 or fieldDef.options.optional then
        schema.isDynamic = true
        schema.size = (schema.size or 0) + (typeSize or 0) -- Add min size (0 for dynamic)
    else
        if fieldDef.options.arrayLength then
            schema.size = (schema.size or 0) + (typeSize * fieldDef.options.arrayLength)
        else
            schema.size = (schema.size or 0) + typeSize
        end
    end
    
    return schema
end

-- Helper: Measure size of dynamic data
local function measureValue(type: string, value: any, options: any): number
    if value == nil then return 0 end
    
    if type == "string" then
        return 2 + #value -- u16 length + string bytes
    elseif type == "list" then
        local len = 2 -- u16 length
        local elemType = options.elementType
        
        -- Handle struct elements
        if elemType == "struct" and options.elementSchema then
            local schema = options.elementSchema
            for _, v in ipairs(value) do
                -- Measure each struct element
                for _, field in ipairs(schema.fields) do
                    local fieldValue = v[field.name]
                    if fieldValue ~= nil then
                        len += measureValue(field.type, fieldValue, field.options)
                    end
                end
            end
            return len
        end
        
        local elemSize = TYPE_SIZES[elemType]
        
        if elemSize and elemSize > 0 then
            return len + (#value * elemSize)
        else
            -- Dynamic elements (e.g. list of strings)
            for _, v in ipairs(value) do
                len += measureValue(elemType, v, options)
            end
            return len
        end
    elseif type == "map" then
        local len = 2 -- u16 length
        local keyType = options.keyType
        local valType = options.valueType
        local keySize = TYPE_SIZES[keyType]
        local valSize = TYPE_SIZES[valType]
        
        for k, v in pairs(value) do
            len += (keySize > 0 and keySize or measureValue(keyType, k, options))
            len += (valSize > 0 and valSize or measureValue(valType, v, options))
        end
        return len
    elseif type == "quantized_vec2" then
        local precision = options.precision or 0.01
        local range = options.range or 327.68
        local _, bytesPerComp = getOptimalIntType(range, precision)
        return bytesPerComp * 2
    elseif type == "quantized_vec3" then
        local precision = options.precision or 0.01
        local range = options.range or 327.68
        local _, bytesPerComp = getOptimalIntType(range, precision)
        return bytesPerComp * 3
    elseif type == "quantized_cframe" then
        local precision = options.precision or 0.01
        local range = options.range or 327.68
        local _, bytesPerComp = getOptimalIntType(range, precision)
        return bytesPerComp * 6
    elseif type == "buffer" then
        return 2 + buffer.len(value) -- u16 len + bytes
    else
        return TYPE_SIZES[type] or 0
    end
end

-- Helper: Write value to buffer
local function writeValue(buf: buffer, offset: number, type: string, value: any, options: any, instances: {Instance}?): number
    local _startOffset = offset
    
    if type == "uint8" then buffer.writeu8(buf, offset, value); offset += 1
    elseif type == "uint16" then buffer.writeu16(buf, offset, value); offset += 2
    elseif type == "uint32" then buffer.writeu32(buf, offset, value); offset += 4
    elseif type == "int8" then buffer.writei8(buf, offset, value); offset += 1
    elseif type == "int16" then buffer.writei16(buf, offset, value); offset += 2
    elseif type == "int32" then buffer.writei32(buf, offset, value); offset += 4
    elseif type == "float32" then buffer.writef32(buf, offset, value); offset += 4
    elseif type == "float64" then buffer.writef64(buf, offset, value); offset += 8
    elseif type == "boolean" then buffer.writeu8(buf, offset, value and 1 or 0); offset += 1
    
    elseif type == "player" then
        -- Serialize Player as Registry ID (u8 - 1 byte!)
        local id
        if typeof(value) == "Instance" then
            -- Handle Player instances or any Instance with _RegistryID (e.g., bot Characters)
            id = KnitSchema.PlayerRegistry:GetId(value)
        else
            id = value -- Assume it's already an ID
        end
        buffer.writeu8(buf, offset, id)
        offset += 1
    
    elseif type == "bitfield" then
        -- Pack up to 8 booleans into 1 byte
        local bits = 0
        local flags = options.flags or {}
        for flagName, bitIndex in pairs(flags) do
            if value[flagName] then
                bits = bit32.bor(bits, bit32.lshift(1, bitIndex))
            end
        end
        buffer.writeu8(buf, offset, bits)
        offset += 1
    
    elseif type == "enum" then
        -- Serialize string as enum index (u8)
        local values = options.values or {}
        local index = 0
        for i, enumValue in ipairs(values) do
            if enumValue == value then
                index = i - 1 -- 0-indexed
                break
            end
        end
        buffer.writeu8(buf, offset, index)
        offset += 1
    
    elseif type == "intern" then
        -- Serialize interned string as registry ID
        local registryName = options.registry or "default"
        local id = KnitSchema.StringRegistry:GetId(registryName, value)
        buffer.writeu8(buf, offset, id)
        offset += 1
    
    elseif type == "quantized_vec2" then
        -- Adaptive quantization: choose i8/i16/i32 based on range
        local precision = options.precision or 0.01
        local range = options.range or 327.68
        local intType, bytesPerComp = getOptimalIntType(range, precision)
        
        local x = math.round(value.X / precision)
        local y = math.round(value.Y / precision)
        
        if intType == "i8" then
            buffer.writei8(buf, offset, math.clamp(x, -128, 127))
            buffer.writei8(buf, offset + 1, math.clamp(y, -128, 127))
        elseif intType == "i16" then
            buffer.writei16(buf, offset, math.clamp(x, -32768, 32767))
            buffer.writei16(buf, offset + 2, math.clamp(y, -32768, 32767))
        else -- i32
            buffer.writei32(buf, offset, x)
            buffer.writei32(buf, offset + 4, y)
        end
        offset += bytesPerComp * 2
        
    elseif type == "quantized_vec3" then
        -- Adaptive quantization
        local precision = options.precision or 0.01
        local range = options.range or 327.68
        local intType, bytesPerComp = getOptimalIntType(range, precision)
        
        local x = math.round(value.X / precision)
        local y = math.round(value.Y / precision)
        local z = math.round(value.Z / precision)
        
        if intType == "i8" then
            buffer.writei8(buf, offset, math.clamp(x, -128, 127))
            buffer.writei8(buf, offset + 1, math.clamp(y, -128, 127))
            buffer.writei8(buf, offset + 2, math.clamp(z, -128, 127))
        elseif intType == "i16" then
            buffer.writei16(buf, offset, math.clamp(x, -32768, 32767))
            buffer.writei16(buf, offset + 2, math.clamp(y, -32768, 32767))
            buffer.writei16(buf, offset + 4, math.clamp(z, -32768, 32767))
        else -- i32
            buffer.writei32(buf, offset, x)
            buffer.writei32(buf, offset + 4, y)
            buffer.writei32(buf, offset + 8, z)
        end
        offset += bytesPerComp * 3
        
    elseif type == "quantized_cframe" then
        -- Adaptive quantization for CFrame
        local precision = options.precision or 0.01
        local range = options.range or 327.68
        local intType, bytesPerComp = getOptimalIntType(range, precision)
        
        local x, y, z = value.X, value.Y, value.Z
        local rx, ry, rz = value:ToEulerAnglesYXZ()
        
        local function writeComp(val: number, off: number)
            local scaled = math.round(val / precision)
            if intType == "i8" then
                buffer.writei8(buf, off, math.clamp(scaled, -128, 127))
            elseif intType == "i16" then
                buffer.writei16(buf, off, math.clamp(scaled, -32768, 32767))
            else
                buffer.writei32(buf, off, scaled)
            end
        end
        
        writeComp(x, offset)
        writeComp(y, offset + bytesPerComp)
        writeComp(z, offset + bytesPerComp * 2)
        writeComp(rx, offset + bytesPerComp * 3)
        writeComp(ry, offset + bytesPerComp * 4)
        writeComp(rz, offset + bytesPerComp * 5)
        offset += bytesPerComp * 6
    
    elseif type == "vector2" then
        buffer.writef32(buf, offset, value.X)
        buffer.writef32(buf, offset + 4, value.Y)
        offset += 8
        
    elseif type == "vector3" then
        buffer.writef32(buf, offset, value.X)
        buffer.writef32(buf, offset + 4, value.Y)
        buffer.writef32(buf, offset + 8, value.Z)
        offset += 12
        
    elseif type == "cframe" then
        -- Pos (12) + Euler (12)
        local x, y, z = value.X, value.Y, value.Z
        local rx, ry, rz = value:ToEulerAnglesYXZ()
        buffer.writef32(buf, offset, x)
        buffer.writef32(buf, offset + 4, y)
        buffer.writef32(buf, offset + 8, z)
        buffer.writef32(buf, offset + 12, rx)
        buffer.writef32(buf, offset + 16, ry)
        buffer.writef32(buf, offset + 20, rz)
        offset += 24
        
    elseif type == "string" then
        local len = #value
        buffer.writeu16(buf, offset, len)
        buffer.writestring(buf, offset + 2, value, len)
        offset += 2 + len
        
    elseif type == "list" then
        local len = #value
        buffer.writeu16(buf, offset, len)
        offset += 2
        local elemType = options.elementType
        
        -- Handle struct elements
        if elemType == "struct" and options.elementSchema then
            local schema = options.elementSchema
            for i = 1, len do
                local elem = value[i]
                for _, field in ipairs(schema.fields) do
                    local fieldValue = elem[field.name]
                    if fieldValue ~= nil or not field.options.optional then
                        offset = writeValue(buf, offset, field.type, fieldValue, field.options, instances)
                    end
                end
            end
        else
            for i = 1, len do
                offset = writeValue(buf, offset, elemType, value[i], options, instances)
            end
        end
        
    elseif type == "map" then
        -- Count keys first
        local count = 0
        for _ in pairs(value) do count += 1 end
        buffer.writeu16(buf, offset, count)
        offset += 2
        
        local keyType = options.keyType
        local valType = options.valueType
        for k, v in pairs(value) do
            offset = writeValue(buf, offset, keyType, k, options, instances)
            offset = writeValue(buf, offset, valType, v, options, instances)
        end
        
    elseif type == "buffer" then
        local len = buffer.len(value)
        buffer.writeu16(buf, offset, len)
        buffer.copy(buf, offset + 2, value, 0, len)
        offset += 2 + len
        
    elseif type == "instance" then
        if instances then
            table.insert(instances, value)
            buffer.writeu16(buf, offset, #instances)
        else
            buffer.writeu16(buf, offset, 0) -- Should not happen if used correctly
        end
        offset += 2
    end
    
    return offset
end

-- Helper: Read value from buffer
local function readValue(buf: buffer, offset: number, type: string, options: any, instances: {Instance}?): (any, number)
    if type == "uint8" then return buffer.readu8(buf, offset), 1
    elseif type == "uint16" then return buffer.readu16(buf, offset), 2
    elseif type == "uint32" then return buffer.readu32(buf, offset), 4
    elseif type == "int8" then return buffer.readi8(buf, offset), 1
    elseif type == "int16" then return buffer.readi16(buf, offset), 2
    elseif type == "int32" then return buffer.readi32(buf, offset), 4
    elseif type == "float32" then return buffer.readf32(buf, offset), 4
    elseif type == "float64" then return buffer.readf64(buf, offset), 8
    elseif type == "boolean" then return buffer.readu8(buf, offset) == 1, 1
    
    elseif type == "player" then
        -- Deserialize Registry ID to Player
        local id = buffer.readu8(buf, offset)
        return KnitSchema.PlayerRegistry:GetPlayer(id), 1
    
    elseif type == "bitfield" then
        -- Unpack 8 booleans from 1 byte
        local bits = buffer.readu8(buf, offset)
        local flags = options.flags or {}
        local result = {}
        for flagName, bitIndex in pairs(flags) do
            result[flagName] = bit32.band(bits, bit32.lshift(1, bitIndex)) ~= 0
        end
        return result, 1
    
    elseif type == "enum" then
        -- Deserialize enum index to string
        local index = buffer.readu8(buf, offset)
        local values = options.values or {}
        return values[index + 1], 1 -- 0-indexed to 1-indexed
    
    elseif type == "intern" then
        -- Deserialize interned string from registry ID
        local id = buffer.readu8(buf, offset)
        local registryName = options.registry or "default"
        return KnitSchema.StringRegistry:GetString(registryName, id), 1
    
    elseif type == "quantized_vec2" then
        -- Adaptive dequantization
        local precision = options.precision or 0.01
        local range = options.range or 327.68
        local intType, bytesPerComp = getOptimalIntType(range, precision)
        
        local x, y
        if intType == "i8" then
            x = buffer.readi8(buf, offset) * precision
            y = buffer.readi8(buf, offset + 1) * precision
        elseif intType == "i16" then
            x = buffer.readi16(buf, offset) * precision
            y = buffer.readi16(buf, offset + 2) * precision
        else -- i32
            x = buffer.readi32(buf, offset) * precision
            y = buffer.readi32(buf, offset + 4) * precision
        end
        return Vector2.new(x, y), bytesPerComp * 2
        
    elseif type == "quantized_vec3" then
        -- Adaptive dequantization
        local precision = options.precision or 0.01
        local range = options.range or 327.68
        local intType, bytesPerComp = getOptimalIntType(range, precision)
        
        local x, y, z
        if intType == "i8" then
            x = buffer.readi8(buf, offset) * precision
            y = buffer.readi8(buf, offset + 1) * precision
            z = buffer.readi8(buf, offset + 2) * precision
        elseif intType == "i16" then
            x = buffer.readi16(buf, offset) * precision
            y = buffer.readi16(buf, offset + 2) * precision
            z = buffer.readi16(buf, offset + 4) * precision
        else -- i32
            x = buffer.readi32(buf, offset) * precision
            y = buffer.readi32(buf, offset + 4) * precision
            z = buffer.readi32(buf, offset + 8) * precision
        end
        return Vector3.new(x, y, z), bytesPerComp * 3
        
    elseif type == "quantized_cframe" then
        -- Adaptive dequantization for CFrame
        local precision = options.precision or 0.01
        local range = options.range or 327.68
        local intType, bytesPerComp = getOptimalIntType(range, precision)
        
        local function readComp(off: number): number
            if intType == "i8" then
                return buffer.readi8(buf, off) * precision
            elseif intType == "i16" then
                return buffer.readi16(buf, off) * precision
            else
                return buffer.readi32(buf, off) * precision
            end
        end
        
        local x = readComp(offset)
        local y = readComp(offset + bytesPerComp)
        local z = readComp(offset + bytesPerComp * 2)
        local rx = readComp(offset + bytesPerComp * 3)
        local ry = readComp(offset + bytesPerComp * 4)
        local rz = readComp(offset + bytesPerComp * 5)
        return CFrame.new(x, y, z) * CFrame.fromEulerAnglesYXZ(rx, ry, rz), bytesPerComp * 6
    
    elseif type == "vector2" then
        local x = buffer.readf32(buf, offset)
        local y = buffer.readf32(buf, offset + 4)
        return Vector2.new(x, y), 8
        
    elseif type == "vector3" then
        local x = buffer.readf32(buf, offset)
        local y = buffer.readf32(buf, offset + 4)
        local z = buffer.readf32(buf, offset + 8)
        return Vector3.new(x, y, z), 12
        
    elseif type == "cframe" then
        local x = buffer.readf32(buf, offset)
        local y = buffer.readf32(buf, offset + 4)
        local z = buffer.readf32(buf, offset + 8)
        local rx = buffer.readf32(buf, offset + 12)
        local ry = buffer.readf32(buf, offset + 16)
        local rz = buffer.readf32(buf, offset + 20)
        return CFrame.new(x, y, z) * CFrame.fromEulerAnglesYXZ(rx, ry, rz), 24
        
    elseif type == "string" then
        local len = buffer.readu16(buf, offset)
        return buffer.readstring(buf, offset + 2, len), 2 + len
        
    elseif type == "list" then
        local len = buffer.readu16(buf, offset)
        local list = table.create(len)
        local currentOffset = offset + 2
        local elemType = options.elementType
        
        -- Handle struct elements
        if elemType == "struct" and options.elementSchema then
            local schema = options.elementSchema
            for i = 1, len do
                local elem = {}
                for _, field in ipairs(schema.fields) do
                    local val, bytes = readValue(buf, currentOffset, field.type, field.options, instances)
                    elem[field.name] = val
                    currentOffset += bytes
                end
                list[i] = elem
            end
        else
            for i = 1, len do
                local val, bytes = readValue(buf, currentOffset, elemType, options, instances)
                list[i] = val
                currentOffset += bytes
            end
        end
        return list, currentOffset - offset
        
    elseif type == "map" then
        local count = buffer.readu16(buf, offset)
        local map = {}
        local currentOffset = offset + 2
        local keyType = options.keyType
        local valType = options.valueType
        
        for i = 1, count do
            local key, kBytes = readValue(buf, currentOffset, keyType, options, instances)
            currentOffset += kBytes
            local val, vBytes = readValue(buf, currentOffset, valType, options, instances)
            currentOffset += vBytes
            map[key] = val
        end
        return map, currentOffset - offset
        
    elseif type == "buffer" then
        local len = buffer.readu16(buf, offset)
        local b = buffer.create(len)
        buffer.copy(b, 0, buf, offset + 2, len)
        return b, 2 + len
        
    elseif type == "instance" then
        local index = buffer.readu16(buf, offset)
        if instances and index > 0 and index <= #instances then
            return instances[index], 2
        else
            return nil, 2
        end
    end
    
    return nil, 0
end


-- Serialize data according to schema
function KnitSchema.serialize(schema: Schema, data: any, previousData: {[string]: any}?): (buffer, {Instance})
    -- Special Case: Handle raw field type (no fields array)
    if not schema.fields or #schema.fields == 0 then
        -- Map single value to mock schema
        local rawType = (schema :: any).type
        local rawOptions = (schema :: any).options or {}
        if rawType then
            if not schema.name then
                schema.name = "Raw_" .. rawType
            end
            local value = data
            -- For single values, we ignore delta compression for now as it needs state
            local measuredSize = measureValue(rawType, value, rawOptions)
            local rawBuf = buffer.create(measuredSize or 0)
            local rawInstances = {}
            writeValue(rawBuf, 0, rawType, value, rawOptions, rawInstances)
            return rawBuf, rawInstances
        end
    end

    -- Count optional fields for presence bits
    local optionalFields = {}
    local optionalCount = 0
    for i, field in ipairs(schema.fields) do
        if field.options.optional then
            optionalFields[i] = optionalCount
            optionalCount += 1
        end
    end
    
    -- Auto-enable presence bits if ANY optional fields (fix for missing optional fields)
    local usePresenceBits = optionalCount > 0
    local presenceBytes = if usePresenceBits then math.ceil(optionalCount / 8) else 0
    
    local totalSize = presenceBytes
    
    -- Pass 1: Measure size (only for present fields)
    if schema.isDynamic then
        for _, field in ipairs(schema.fields) do
            local value = data[field.name]
            if value ~= nil then
                if field.options.arrayLength then
                    totalSize += (TYPE_SIZES[field.type] * field.options.arrayLength)
                else
                    totalSize += measureValue(field.type, value, field.options)
                end
            end
        end
    else
        totalSize += schema.size or 0
    end
    
    local buf = buffer.create(totalSize)
    local offset = 0
    local instances = {}
    
    -- Write presence bits if enabled
    if usePresenceBits then
        local presenceBits = table.create(presenceBytes, 0)
        for i, field in ipairs(schema.fields) do
            if field.options.optional and data[field.name] ~= nil then
                local bitIndex = optionalFields[i]
                local byteIndex = math.floor(bitIndex / 8)
                local bitPos = bitIndex % 8
                presenceBits[byteIndex + 1] = bit32.bor(presenceBits[byteIndex + 1] or 0, bit32.lshift(1, bitPos))
            end
        end
        for i = 1, presenceBytes do
            buffer.writeu8(buf, offset, presenceBits[i])
            offset += 1
        end
    end
    
    -- Pass 2: Write data (only present fields)
    for _, field in ipairs(schema.fields) do
        local value = data[field.name]
        
        if value == nil and not field.options.optional then
            error(`Missing required field: {field.name}`)
        end
        
        if value ~= nil then
            if field.options.deltaFrom and previousData and previousData[field.options.deltaFrom] then
                value = value - previousData[field.options.deltaFrom]
            end
            
            if field.options.arrayLength then
                for i = 1, field.options.arrayLength do
                    offset = writeValue(buf, offset, field.type, value[i], field.options, instances)
                end
            else
                offset = writeValue(buf, offset, field.type, value, field.options, instances)
            end
        end
    end
    
    return buf, instances
end

-- Deserialize buffer according to schema
function KnitSchema.deserialize(schema: Schema, buf: buffer, instances: {Instance}?, previousData: {[string]: any}?): {[string]: any}
    local data = {}
    local offset = 0
    
    -- Count optional fields and check for presence bits
    local optionalFields = {}
    local optionalCount = 0
    for i, field in ipairs(schema.fields) do
        if field.options.optional then
            optionalFields[i] = optionalCount
            optionalCount += 1
        end
    end
    
    local usePresenceBits = optionalCount > 0
    local presenceBytes = if usePresenceBits then math.ceil(optionalCount / 8) else 0
    
    -- Read presence bits if enabled
    local presenceBits = {}
    
    -- Special Case: Handle raw field type (no fields array)
    if not schema.fields or #schema.fields == 0 then
        local rawType = (schema :: any).type
        local rawOptions = (schema :: any).options or {}
        if rawType then
            local value, _ = readValue(buf, 0, rawType, rawOptions, instances)
            return value
        end
    end

    if usePresenceBits then
        for i = 1, presenceBytes do
            presenceBits[i] = buffer.readu8(buf, offset)
            offset += 1
        end
    end
    
    -- Helper: Check if optional field is present
    local function isPresent(fieldIndex: number): boolean
        if not usePresenceBits then return true end
        local field = schema.fields[fieldIndex]
        if not field.options.optional then return true end
        
        local bitIndex = optionalFields[fieldIndex]
        local byteIndex = math.floor(bitIndex / 8)
        local bitPos = bitIndex % 8
        return bit32.band(presenceBits[byteIndex + 1] or 0, bit32.lshift(1, bitPos)) ~= 0
    end
    
    -- Read fields
    for i, field in ipairs(schema.fields) do
        if isPresent(i) then
            if field.options.arrayLength then
                local arr = table.create(field.options.arrayLength)
                for j = 1, field.options.arrayLength do
                    local value, bytesRead = readValue(buf, offset, field.type, field.options, instances)
                    arr[j] = value
                    offset += bytesRead
                end
                data[field.name] = arr
            else
                local value, bytesRead = readValue(buf, offset, field.type, field.options, instances)
                offset += bytesRead
                
                if value and field.options.deltaFrom and previousData and previousData[field.options.deltaFrom] then
                    value = value + previousData[field.options.deltaFrom]
                end
                
                data[field.name] = value
            end
        else
            -- Optional field not present, set to nil
            data[field.name] = nil
        end
    end
    
    return data
end

-- Helper: Validate single value
local function validateValue(value: any, type: string, options: any): (boolean, string?)
    if value == nil then
        if options.optional then return true end
        return false, "Value is nil but not optional"
    end

    if type == "uint8" or type == "uint16" or type == "uint32" or 
       type == "int8" or type == "int16" or type == "int32" or 
       type == "float32" or type == "float64" then
        if typeof(value) ~= "number" then return false, "Expected number, got " .. typeof(value) end
        if options.min and value < options.min then return false, "Value below min" end
        if options.max and value > options.max then return false, "Value above max" end
        return true
    elseif type == "boolean" then
        if typeof(value) ~= "boolean" then return false, "Expected boolean, got " .. typeof(value) end
        return true
    elseif type == "vector2" then
        if typeof(value) ~= "Vector2" then return false, "Expected Vector2, got " .. typeof(value) end
        return true
    elseif type == "vector3" then
        if typeof(value) ~= "Vector3" then return false, "Expected Vector3, got " .. typeof(value) end
        return true
    elseif type == "cframe" then
        if typeof(value) ~= "CFrame" then return false, "Expected CFrame, got " .. typeof(value) end
        return true
    elseif type == "player" then
        if typeof(value) == "Instance" then
            -- Allow Player or any Instance with _RegistryID (e.g., bot folders)
            if value:IsA("Player") then return true end
            if value:GetAttribute("_RegistryID") ~= nil then return true end
        end
        if typeof(value) == "number" then return true end -- Allow UserId/RegistryID
        return false, "Expected Player, registered Instance, or ID, got " .. typeof(value)
    elseif type == "bitfield" then
        if typeof(value) ~= "table" then return false, "Expected table (bitfield), got " .. typeof(value) end
        -- Validate all flags are boolean
        for k, v in pairs(value) do
            if typeof(v) ~= "boolean" then return false, "Bitfield value must be boolean, got " .. typeof(v) end
        end
        return true
    elseif type == "enum" then
        if typeof(value) ~= "string" then return false, "Expected string (enum), got " .. typeof(value) end
        local values = options.values or {}
        for _, enumValue in ipairs(values) do
            if enumValue == value then return true end
        end
        return false, "Enum value '" .. value .. "' not in allowed values"
    elseif type == "intern" then
        if typeof(value) ~= "string" then return false, "Expected string (intern), got " .. typeof(value) end
        return true
    elseif type == "quantized_vec2" then
        if typeof(value) ~= "Vector2" then return false, "Expected Vector2, got " .. typeof(value) end
        return true
    elseif type == "quantized_vec3" then
        if typeof(value) ~= "Vector3" then return false, "Expected Vector3, got " .. typeof(value) end
        return true
    elseif type == "quantized_cframe" then
        if typeof(value) ~= "CFrame" then return false, "Expected CFrame, got " .. typeof(value) end
        return true
    elseif type == "instance" then
        -- Instance validation: must be a valid Instance that exists
        -- If optional and nil, we already returned true earlier in this function
        if value == nil then
            -- Not optional (we'd have returned earlier), so nil is invalid
            return false, "Instance is nil (destroyed or doesn't exist)"
        end
        if typeof(value) ~= "Instance" then 
            return false, "Expected Instance, got " .. typeof(value) 
        end
        -- Validate the instance still exists (not destroyed)
        if value.Parent == nil then
            -- Check if it's a service (services have no parent but are valid)
            local success = pcall(function() return value.Name end)
            if not success then
                return false, "Instance was destroyed"
            end
        end
        return true
    elseif type == "string" then
        if typeof(value) ~= "string" then return false, "Expected string, got " .. typeof(value) end
        return true
    elseif type == "list" then
        if typeof(value) ~= "table" then return false, "Expected table (list), got " .. typeof(value) end
        local elemType = options.elementType
        
        -- Handle struct elements
        if elemType == "struct" and options.elementSchema then
            local schema = options.elementSchema
            for i, v in ipairs(value) do
                if typeof(v) ~= "table" then 
                    return false, "List element " .. i .. ": Expected table (struct), got " .. typeof(v) 
                end
                -- Validate each field in the struct
                for _, field in ipairs(schema.fields) do
                    local fieldValue = v[field.name]
                    if fieldValue == nil and not field.options.optional then
                        return false, "List element " .. i .. ": Missing required field '" .. field.name .. "'"
                    end
                    if fieldValue ~= nil then
                        local valid, err = validateValue(fieldValue, field.type, field.options)
                        if not valid then 
                            return false, "List element " .. i .. "." .. field.name .. ": " .. (err or "Invalid") 
                        end
                    end
                end
            end
            return true
        end
        
        for i, v in ipairs(value) do
            local valid, err = validateValue(v, elemType, options)
            if not valid then return false, "List element " .. i .. ": " .. (err or "Invalid") end
        end
        return true
    elseif type == "map" then
        if typeof(value) ~= "table" then return false, "Expected table (map), got " .. typeof(value) end
        local keyType = options.keyType
        local valType = options.valueType
        for k, v in pairs(value) do
            local validKey, errKey = validateValue(k, keyType, options)
            if not validKey then return false, "Map key: " .. (errKey or "Invalid") end
            local validVal, errVal = validateValue(v, valType, options)
            if not validVal then return false, "Map value for key " .. tostring(k) .. ": " .. (errVal or "Invalid") end
        end
        return true
    end
    
    return true
end

-- Validate data
function KnitSchema.validate(schema: Schema, data: any): (boolean, string?)
    -- Special Case: Handle raw field type (no fields array)
    if not schema.fields or #schema.fields == 0 then
        local rawType = (schema :: any).type
        local rawOptions = (schema :: any).options or {}
        if rawType then
            return validateValue(data, rawType, rawOptions)
        end
    end
    
    for _, field in ipairs(schema.fields or {}) do
        local value = data[field.name]
        
        if field.options.arrayLength then
            if typeof(value) ~= "table" then return false, "Field " .. field.name .. ": Expected array, got " .. typeof(value) end
            if #value ~= field.options.arrayLength then return false, "Field " .. field.name .. ": Expected length " .. field.options.arrayLength .. ", got " .. #value end
            for i = 1, field.options.arrayLength do
                local valid, err = validateValue(value[i], field.type, field.options)
                if not valid then return false, "Field " .. field.name .. "[" .. i .. "]: " .. (err or "Invalid") end
            end
        else
            local valid, err = validateValue(value, field.type, field.options)
            if not valid then return false, "Field " .. field.name .. ": " .. (err or "Invalid") end
        end
    end
    return true
end

-- Shorthand constructors
local function createType(typeName: string)
    return function(options: FieldOptions?)
        return { type = typeName, options = options or {} }
    end
end

KnitSchema.u8 = createType("uint8")
KnitSchema.u16 = createType("uint16")
KnitSchema.u32 = createType("uint32")
KnitSchema.i8 = createType("int8")
KnitSchema.i16 = createType("int16")
KnitSchema.i32 = createType("int32")
KnitSchema.f32 = createType("float32")
KnitSchema.f64 = createType("float64")
KnitSchema.bool = createType("boolean")
KnitSchema.vec2 = createType("vector2")
KnitSchema.vec3 = createType("vector3")
KnitSchema.cframe = createType("cframe")
KnitSchema.player = createType("player")
KnitSchema.string = createType("string")
KnitSchema.buffer = createType("buffer")
KnitSchema.instance = createType("instance")

-- Delta compression helpers
KnitSchema.delta = {}
local function createDeltaType(typeName: string)
    return function(options: FieldOptions?)
        local opts = options or {}
        opts.delta = true
        return { type = typeName, options = opts }
    end
end

KnitSchema.delta.u8 = createDeltaType("uint8")
KnitSchema.delta.u16 = createDeltaType("uint16")
KnitSchema.delta.u32 = createDeltaType("uint32")
KnitSchema.delta.i8 = createDeltaType("int8")
KnitSchema.delta.i16 = createDeltaType("int16")
KnitSchema.delta.i32 = createDeltaType("int32")
KnitSchema.delta.f32 = createDeltaType("float32")
KnitSchema.delta.f64 = createDeltaType("float64")
KnitSchema.delta.vec2 = createDeltaType("vector2")
KnitSchema.delta.vec3 = createDeltaType("vector3")
-- Note: Delta not supported for player (doesn't make sense to delta UserId)

-- Dynamic Array: KnitSchema.array(KnitSchema.u8) or KnitSchema.array(MyStructSchema)
function KnitSchema.array(elementType: any)
    -- If elementType is a function (e.g., KnitSchema.u8), call it to get the type table
    local typeObj = type(elementType) == "function" and elementType() or elementType
    
    -- Check if elementType is a full schema (struct) - has 'fields' property
    if typeObj.fields then
        return {
            type = "list",
            options = { 
                elementType = "struct",
                elementSchema = typeObj -- Store the full schema for nested structs
            }
        }
    end
    
    local typeName = typeObj.type or "uint8"
    return {
        type = "list",
        options = { elementType = typeName }
    }
end

-- Dynamic Map: KnitSchema.map(KnitSchema.string, KnitSchema.u32)
function KnitSchema.map(keyType: any, valueType: any)
    -- Handle function constructors
    local keyObj = type(keyType) == "function" and keyType() or keyType
    local valObj = type(valueType) == "function" and valueType() or valueType
    return {
        type = "map",
        options = { 
            keyType = keyObj.type or "string",
            valueType = valObj.type or "uint32"
        }
    }
end

-- Dynamic Set: KnitSchema.set(KnitSchema.u32) -> Equivalent to Array but implies uniqueness
-- (For serialization purposes, it's identical to an array)
function KnitSchema.set(elementType: any)
    return KnitSchema.array(elementType)
end

-- Bitfield: Pack up to 8 booleans into 1 byte!
-- Usage: KnitSchema.bitfield({ isCrouching = 0, isSprinting = 1, isAiming = 2 })
function KnitSchema.bitfield(flags: {[string]: number})
    return {
        type = "bitfield",
        options = { flags = flags }
    }
end

--[=[
    Enum: Fixed set of string values serialized as u8 index
    @param values Array of possible string values (max 256)
    
    Example:
    status = KnitSchema.enum({ "Idle", "Running", "Jumping", "Falling" })
    -- "Running" serializes as 1 (1 byte) instead of 7 bytes!
]=]
function KnitSchema.enum(values: {string})
    return {
        type = "enum",
        options = { values = values }
    }
end

--[=[
    String Interning: Common strings stored as u8 IDs
    @param options { registry: string? } - Optional registry name
    
    Example:
    weaponName = KnitSchema.intern.string({ registry = "weapons" })
    -- "Pistol" first time = registered + 1 byte
    -- "Pistol" again = 1 byte (vs 6 bytes for full string!)
]=]
KnitSchema.intern = {}
function KnitSchema.intern.string(options: {registry: string?}?)
    return {
        type = "intern",
        options = { registry = (options and options.registry) or "default" }
    }
end

-- Quantized types: Compress vectors using scaled integers (adaptive i8/i16/i32)
KnitSchema.quantized = {}

--[=[
    Quantize Vector2 with adaptive precision
    @param options { precision: number?, range: number? }
    - precision: Value resolution (default 0.01 = 1cm)
    - range: Max absolute value (default 327.68 for i16)
    
    Examples:
    - { precision = 0.1, range = 12.7 } → i8 (2 bytes total!)
    - { precision = 0.01, range = 327.68 } → i16 (4 bytes, default)
    - { precision = 0.001, range = 2147.483 } → i32 (8 bytes)
]=]
function KnitSchema.quantized.vec2(options: FieldOptions?)
    local opts = options or {}
    opts.precision = opts.precision or 0.01
    opts.range = opts.range or 327.68 -- Default: i16 range
    return { type = "quantized_vec2", options = opts }
end

function KnitSchema.quantized.vec3(options: FieldOptions?)
    local opts = options or {}
    opts.precision = opts.precision or 0.01
    opts.range = opts.range or 327.68
    return { type = "quantized_vec3", options = opts }
end

function KnitSchema.quantized.cframe(options: FieldOptions?)
    local opts = options or {}
    opts.precision = opts.precision or 0.01
    opts.range = opts.range or 327.68
    return { type = "quantized_cframe", options = opts }
end

-- Schema Registry
KnitSchema.Defs = {}

-- Modern schema definition
function KnitSchema.define(name: string, fields: {[string]: any}): Schema
    local schema = KnitSchema.schema(name)
    local fieldNames = {}
    for name in pairs(fields) do table.insert(fieldNames, name) end
    table.sort(fieldNames)
    
    for _, fieldName in ipairs(fieldNames) do
        local fieldDef = fields[fieldName]
        if type(fieldDef) == "function" then fieldDef = fieldDef({}) end
        KnitSchema.field(schema, fieldName, fieldDef.type, fieldDef.options)
    end
    
    -- Register schema
    KnitSchema.Defs[name] = schema
    
    return schema
end

-- Helper for optional fields
function KnitSchema.optional(fieldDef: any)
    -- Handle function constructors
    if type(fieldDef) == "function" then fieldDef = fieldDef() end
    
    -- Clone options to avoid mutating original
    local options = table.clone(fieldDef.options or {})
    options.optional = true
    
    return {
        type = fieldDef.type,
        options = options
    }
end

-- Alias for table (generic map)
-- Usage: KnitSchema.table() -> map<string, any> (not fully supported by map logic which needs specific types)
-- For now, let's treat it as a map<string, string> fallback or just map<string, u16> if generic?
-- Actually, let's map it to `map(string, string)` as a safe default for generic data tables if specialized types aren't known, 
-- or better, provide a `any` type if supported? No `any` type.
-- Let's make `table` an alias for `map(string, string)` for now to satisfy the call.
function KnitSchema.table()
    return KnitSchema.map(KnitSchema.string, KnitSchema.string) -- Fallback
end

return KnitSchema
