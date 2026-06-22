WD = WD or {}
WD.Resource = GetCurrentResourceName()

function WD.Debug(message, data)
    if not Config or not Config.Debug then return end

    if data ~= nil then
        print(('[%s] DEBUG: %s %s'):format(WD.Resource, message, json.encode(data)))
    else
        print(('[%s] DEBUG: %s'):format(WD.Resource, message))
    end
end

function WD.Locale(key, vars)
    local value = Locales and Locales[Config.Locale or 'en'] and Locales[Config.Locale or 'en'][key] or key

    if vars then
        for name, replacement in pairs(vars) do
            value = value:gsub(('%%{%s}'):format(name), tostring(replacement))
        end
    end

    return value
end

function WD.Distance(a, b)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
end
