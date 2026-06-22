Client = Client or {}
Client.Preview = Client.Preview or {}

local activeStoreId = nil
local activeStationId = nil
local previews = {}

local function key(storeId, stationId)
    return ('%s:%s'):format(storeId, stationId)
end

local function deletePreview(previewKey)
    local state = previews[previewKey]
    if state and state.object and DoesEntityExist(state.object) then
        SetEntityAsMissionEntity(state.object, true, true)
        DeleteEntity(state.object)
    end

    if state then
        state.object = nil
        state.currentModel = nil
    end
end

local function previewCoords(preview)
    local base = preview and preview.coords or Config.Preview.Coords
    local offset = preview and preview.offset or Config.Preview.Offset or vec3(0.0, 0.0, 0.0)

    return base, vec3(base.x + offset.x, base.y + offset.y, base.z + offset.z)
end

local function spawnPreview(previewKey, state)
    if not Config.Preview.Enabled or not state.model or state.model == '' then return end

    if state.object and DoesEntityExist(state.object) then
        if state.currentModel == state.model then
            return
        end

        deletePreview(previewKey)
    end

    local token = state.token
    local model = joaat(state.model)
    local isWeapon = tostring(state.model):upper():find('^WEAPON_') ~= nil

    if isWeapon then
        RequestWeaponAsset(model, 31, 0)
        local timeout = GetGameTimer() + 5000
        while not HasWeaponAssetLoaded(model) and GetGameTimer() < timeout do
            Wait(0)
        end

        if not HasWeaponAssetLoaded(model) then
            return
        end
    else
        if not IsModelInCdimage(model) then
            return
        end

        lib.requestModel(model, 5000)
    end

    if previews[previewKey] ~= state or state.token ~= token or state.model == '' then
        if isWeapon then
            RemoveWeaponAsset(model)
        else
            SetModelAsNoLongerNeeded(model)
        end
        return
    end

    local base, coords = previewCoords(state.preview)
    if isWeapon then
        state.object = CreateWeaponObject(model, 1, coords.x, coords.y, coords.z, false, 1.0, 0)
    else
        state.object = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    end

    if not state.object or state.object == 0 then
        if isWeapon then
            RemoveWeaponAsset(model)
        else
            SetModelAsNoLongerNeeded(model)
        end
        return
    end

    state.currentModel = state.model
    state.heading = base.w or 0.0

    SetEntityAsMissionEntity(state.object, true, true)
    SetEntityHeading(state.object, state.heading)
    FreezeEntityPosition(state.object, true)
    SetEntityCollision(state.object, false, false)
    SetEntityAlpha(state.object, 245, false)
    if isWeapon then
        RemoveWeaponAsset(model)
    else
        SetModelAsNoLongerNeeded(model)
    end
end

local function updatePreviewVisibility(previewKey, state)
    local _, coords = previewCoords(state.preview)
    local distance = #(GetEntityCoords(cache.ped) - coords)

    if distance <= (state.distance or 25.0) then
        spawnPreview(previewKey, state)
    else
        deletePreview(previewKey)
    end
end

function Client.Preview.SetStation(preview, stationId, storeId)
    if activeStoreId and activeStationId and (activeStoreId ~= storeId or activeStationId ~= stationId) then
        TriggerServerEvent('qbx_weapondealer:server:setPreviewWeapon', activeStoreId, activeStationId, nil)
    end

    activeStoreId = storeId
    activeStationId = stationId
end

function Client.Preview.Clear()
    if activeStoreId and activeStationId then
        TriggerServerEvent('qbx_weapondealer:server:setPreviewWeapon', activeStoreId, activeStationId, nil)
    end
end

function Client.Preview.Show(modelName)
    if not activeStoreId or not activeStationId then return end

    TriggerServerEvent('qbx_weapondealer:server:setPreviewWeapon', activeStoreId, activeStationId, modelName)
end

RegisterNetEvent('qbx_weapondealer:client:setPreviewWeapon', function(storeId, stationId, modelName, preview, distance)
    local previewKey = key(storeId, stationId)

    if not modelName or modelName == '' then
        deletePreview(previewKey)
        previews[previewKey] = nil
        return
    end

    deletePreview(previewKey)
    previews[previewKey] = {
        model = modelName,
        preview = preview,
        distance = distance or 25.0,
        heading = 0.0,
        token = GetGameTimer()
    }

    updatePreviewVisibility(previewKey, previews[previewKey])
end)

CreateThread(function()
    while true do
        local active = false

        for previewKey, state in pairs(previews) do
            active = true
            updatePreviewVisibility(previewKey, state)

            if state.object and DoesEntityExist(state.object) then
                state.heading = state.heading + (Config.Preview.RotationSpeed or 0.35)
                if state.heading >= 360.0 then state.heading = 0.0 end
                SetEntityHeading(state.object, state.heading)
            end
        end

        Wait(active and 0 or 500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= WD.Resource then return end

    for previewKey in pairs(previews) do
        deletePreview(previewKey)
    end
end)
