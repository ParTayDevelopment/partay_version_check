Server = Server or {}
Server.Preview = Server.Preview or {}

local states = {}
local ownerStates = {}
local previewDistance = 25.0
local clearAfterSeconds = 30

local function stationKey(storeId, stationId)
    return ('%s:%s'):format(storeId, stationId)
end

local function findStation(storeId, stationId)
    local store = Server.GetStore(storeId)
    if not store then return nil, nil end

    for _, station in ipairs(store.orderStations or {}) do
        if station.id == stationId then
            return store, station
        end
    end
end

local function isAllowedModel(modelName)
    if not modelName or modelName == '' then return true end

    for _, weapon in ipairs(Config.Weapons) do
        if weapon.enabled ~= false and (weapon.previewModel == modelName or weapon.item == modelName) then
            return true
        end
    end

    if Config.Melee and Config.Melee.Enabled ~= false then
        for _, item in ipairs(Config.Melee.Items or {}) do
            if item.item == modelName or item.previewModel == modelName then
                return true
            end
        end
    end

    return false
end

local function clearState(key, notify)
    local state = states[key]
    if not state then return end

    states[key] = nil
    if state.owner then
        ownerStates[state.owner] = nil
    end

    if notify then
        TriggerClientEvent('qbx_weapondealer:client:setPreviewWeapon', -1, state.store, state.station, nil, state.preview, previewDistance)
    end
end

local function clearOwnerPreview(owner, exceptKey)
    local key = ownerStates[owner]
    if key and key ~= exceptKey then
        clearState(key, true)
    end
end

local function clearOwnedStation(owner, key)
    local state = states[key]
    if state and state.owner == owner then
        clearState(key, false)
        return true
    end

    return false
end

RegisterNetEvent('qbx_weapondealer:server:setPreviewWeapon', function(storeId, stationId, modelName)
    local source = source
    local store, station = findStation(storeId, stationId)
    local key = stationKey(storeId, stationId)
    local existing = states[key]

    if not store or not station then
        Server.Logs.Blocked(source, 'preview_weapon', 'invalid_order_station', { store = storeId, station = stationId })
        return
    end

    local canControl = Server.IsNear(source, station.coords) or (existing and existing.owner == source)
    if not canControl then
        Server.Logs.Blocked(source, 'preview_weapon', 'not_at_order_station', { store = storeId, station = stationId })
        return
    end

    if not isAllowedModel(modelName) then
        Server.Logs.Blocked(source, 'preview_weapon', 'invalid_preview_model', { model = modelName })
        return
    end

    if not modelName or modelName == '' then
        clearOwnedStation(source, key)
        TriggerClientEvent('qbx_weapondealer:client:setPreviewWeapon', -1, storeId, stationId, nil, station.preview, previewDistance)
        return
    end

    clearOwnerPreview(source, key)

    states[key] = {
        store = storeId,
        station = stationId,
        model = modelName,
        preview = station.preview,
        owner = source,
        expires = os.time() + clearAfterSeconds
    }
    ownerStates[source] = key

    TriggerClientEvent('qbx_weapondealer:client:setPreviewWeapon', -1, storeId, stationId, modelName, station.preview, previewDistance)
end)

CreateThread(function()
    while true do
        local now = os.time()

        for key, state in pairs(states) do
            if state.expires <= now then
                clearState(key, true)
            end
        end

        Wait(5000)
    end
end)

AddEventHandler('playerDropped', function()
    local key = ownerStates[source]
    if key then
        clearState(key, true)
    end
end)
