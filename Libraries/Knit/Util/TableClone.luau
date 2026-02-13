local function TableClone(t: {any})
    local clone = {}
    for k, v in t do
        if type(v) == "table" then
            clone[k] = TableClone(v)
        else
            clone[k] = v
        end
    end
    return clone
end
return TableClone