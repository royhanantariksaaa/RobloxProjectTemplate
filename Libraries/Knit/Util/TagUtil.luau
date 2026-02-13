local CollectionService = game:GetService("CollectionService")

local TagUtil = {}

--[=[
    Observes a tag and calls Add/Remove methods on the target object.
    @param target The object/table to call methods on
    @param tagName The tag to observe
    @param addMethodName The name of the method to call when an instance is added (default: "Add" .. tagName)
    @param removeMethodName The name of the method to call when an instance is removed (default: "Remove" .. tagName)
    @param trove Optional Trove to clean up connections
]=]
function TagUtil.Observe(target: any, tagName: string, addMethodName: string?, removeMethodName: string?, trove: any?)
    local addMethod = addMethodName or ("Add" .. tagName)
    local removeMethod = removeMethodName or ("Remove" .. tagName)
    
    assert(target[addMethod], `Target does not have method {addMethod}`)
    assert(target[removeMethod], `Target does not have method {removeMethod}`)

    local function onAdded(instance)
        target[addMethod](target, instance)
    end
    
    local function onRemoved(instance)
        target[removeMethod](target, instance)
    end
    
    -- Handle initial instances
    for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
        task.spawn(onAdded, instance)
    end
    
    -- Connect signals
    local addedConn = CollectionService:GetInstanceAddedSignal(tagName):Connect(onAdded)
    local removedConn = CollectionService:GetInstanceRemovedSignal(tagName):Connect(onRemoved)
    
    if trove then
        trove:Add(addedConn)
        trove:Add(removedConn)
    end
    
    return function()
        addedConn:Disconnect()
        removedConn:Disconnect()
    end
end

--[=[
    Observes a tag and maintains a simple list of instances.
    @param tagName The tag to observe
    @param list The table to maintain
    @param trove Optional Trove
]=]
function TagUtil.ObserveList(tagName: string, list: {Instance}, trove: any?)
    local function onAdded(instance)
        if not table.find(list, instance) then
            table.insert(list, instance)
        end
    end
    
    local function onRemoved(instance)
        local index = table.find(list, instance)
        if index then
            table.remove(list, index)
        end
    end

    -- Handle initial
    for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
        onAdded(instance)
    end

    local addedConn = CollectionService:GetInstanceAddedSignal(tagName):Connect(onAdded)
    local removedConn = CollectionService:GetInstanceRemovedSignal(tagName):Connect(onRemoved)

    if trove then
        trove:Add(addedConn)
        trove:Add(removedConn)
    end

    return function()
        addedConn:Disconnect()
        removedConn:Disconnect()
    end
end

return TagUtil
