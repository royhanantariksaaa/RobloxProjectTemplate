local FilterUtil = {}

function FilterUtil.Add(filter: {Instance}, instance: Instance, trove)
    if not instance or table.find(filter, instance) then return end
    
    table.insert(filter, instance)
    
    local connection
    connection = instance.Destroying:Connect(function()
        FilterUtil.Remove(filter, instance)
        if connection then
            connection:Disconnect()
        end
    end)
    
    if trove then
        trove:Add(connection)
    end
    
    return connection
end

function FilterUtil.Remove(filter: {Instance}, instance: Instance)
    local index = table.find(filter, instance)
    if index then
        table.remove(filter, index)
    end
end

return FilterUtil
