local FilterList = {}
FilterList.__index = FilterList

function FilterList.new(objects: {Instance})
    local self = setmetatable({}, FilterList)
    for _, object in objects do
        self:AddObject(object)
    end

    return self
end

function FilterList:GetObject(object)
    if not self._Objects then return end
    return table.find(self._Objects, object)
end

function FilterList:AddObject(object: Instance)
    if not self._Objects then
        self._Objects = {}
    end
    if not self:GetObject(object) then
        table.insert(self._Objects, object)

    local connection 
        connection = object.Destroying:Connect(function()
            self:RemoveObject(object)
            if connection then
                connection:Disconnect()
            end
        end)
    end
end

function FilterList:RemoveObject(object: Object)
    if not self._Objects then return end
    table.remove(self._Objects, table.find(self._Objects, object))
end

return FilterList