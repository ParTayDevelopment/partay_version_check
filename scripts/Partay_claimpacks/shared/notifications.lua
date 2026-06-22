local position = Config.Notify and Config.Notify.Position or 'top'
local defaultDuration = 5000
local defaultIcon = 'fa-solid fa-gift'

local function cloneTable(source)
    if type(source) ~= 'table' then return {} end
    local copy = {}
    for key, value in pairs(source) do
        if type(value) == 'table' then
            copy[key] = cloneTable(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function formatPayload(message, overrides)
    if type(message) == 'table' then
        local payload = cloneTable(message)
        if overrides then
            for key, value in pairs(overrides) do
                payload[key] = value
            end
        end
        payload.position = payload.position or position
        payload.duration = payload.duration or defaultDuration
        payload.icon = payload.icon or defaultIcon
        return payload
    end

    local payload = overrides and cloneTable(overrides) or {}
    payload.description = payload.description or tostring(message)
    payload.position = payload.position or position
    payload.duration = payload.duration or defaultDuration
    payload.icon = payload.icon or defaultIcon
    return payload
end

if IsDuplicityVersion() then
    local Notifications = {}

    local function send(source, payload)
        if not source or source <= 0 then return end
        if type(payload) ~= 'table' then return end
        payload.position = payload.position or position
        TriggerClientEvent('Partay_claimpacks:notify', source, payload)
    end

    function Notifications.Notify(source, payload)
        send(source, formatPayload(payload))
    end

    function Notifications.Success(source, message, overrides)
        local payload = formatPayload(message, overrides)
        payload.type = 'success'
        send(source, payload)
    end

    function Notifications.Error(source, message, overrides)
        local payload = formatPayload(message, overrides)
        payload.type = 'error'
        send(source, payload)
    end

    function Notifications.Warning(source, message, overrides)
        local payload = formatPayload(message, overrides)
        payload.type = 'warning'
        send(source, payload)
    end

    exports('Notify', function(source, payload) Notifications.Notify(source, payload) end)
    exports('Success', function(source, message, overrides) Notifications.Success(source, message, overrides) end)
    exports('Error', function(source, message, overrides) Notifications.Error(source, message, overrides) end)
    exports('Warning', function(source, message, overrides) Notifications.Warning(source, message, overrides) end)

    PartayClaimpacksNotify = Notifications
    return
end

local function show(payload)
    if type(payload) ~= 'table' then return end
    payload.position = payload.position or position
    payload.duration = payload.duration or defaultDuration
    payload.icon = payload.icon or defaultIcon
    payload.type = payload.type or 'inform'

    if lib and lib.notify then
        lib.notify(payload)
    else
        print(('Partay_claimpacks notification [%s]: %s'):format(payload.type, payload.description or payload.title or ''))
    end
end

RegisterNetEvent('Partay_claimpacks:notify', function(payload)
    show(payload)
end)

PartayClaimpacksNotify = {
    Notify = function(payload)
        show(formatPayload(payload))
    end,
    Success = function(message, overrides)
        local payload = formatPayload(message, overrides)
        payload.type = 'success'
        show(payload)
    end,
    Error = function(message, overrides)
        local payload = formatPayload(message, overrides)
        payload.type = 'error'
        show(payload)
    end,
    Warning = function(message, overrides)
        local payload = formatPayload(message, overrides)
        payload.type = 'warning'
        show(payload)
    end
}




