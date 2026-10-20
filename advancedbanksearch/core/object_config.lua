-- Read the lasting config name RuneQL uses to identify an object

local ObjectConfig = {}

-- Read an object's stable config name, falling back to its printed form
function ObjectConfig.ConfigName(objectID)
    objectID = math.tointeger(tonumber(objectID))
    if objectID == nil or config == nil or config.Obj == nil
        or config.Obj.FromID == nil then return nil end
    local ok, object = pcall(function() return config.Obj.FromID(objectID) end)
    if not ok or object == nil then return nil end
    local nameOK, name = pcall(function() return object.configName end)
    if nameOK and type(name) == "string" and name ~= "" then return name end
    return string.match(tostring(object), "config%.[^.]+%.([^%(]+)%(")
end

return ObjectConfig
