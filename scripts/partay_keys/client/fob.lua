-- [[ Remote Fob NUI Callbacks ]] --

local function TrimPlate(plate)
    return plate and plate:gsub('^%s*(.-)%s*$', '%1') or nil
end

local function PlayFobAnimation()
    local anim = Animations and Animations.FobPress
    if not anim or not anim.dict or not anim.name then return end

    if PartayKeysShowHandPropOnce then
        PartayKeysShowHandPropOnce('fob', anim.duration or 1000)
    end

    lib.requestAnimDict(anim.dict, 1000)
    TaskPlayAnim(cache.ped or PlayerPedId(), anim.dict, anim.name, 8.0, 8.0, anim.duration or 1000, anim.flags or 48, 0, false, false, false)
end

local function GetMetadataVehicleLabel(metadata)
    if type(metadata) ~= 'table' then return nil end

    local label = metadata.vehicle_label or metadata.brand or metadata.make or metadata.model_name
    if label and label ~= '' then return label end

    if metadata.label and metadata.label ~= '' then
        return metadata.label:gsub('%s+[Kk]ey$', '')
    end

    return nil
end

local function FindVehicleByPlate(plate, coords, maxDistance)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return 0 end

    local closestVehicle = 0
    local closestDistance = maxDistance or 25.0

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and TrimPlate(GetVehicleNumberPlateText(vehicle)) == plate then
            local distance = #(coords - GetEntityCoords(vehicle))
            if distance <= closestDistance then
                closestVehicle = vehicle
                closestDistance = distance
            end
        end
    end

    return closestVehicle
end

local function GetActiveFobVehicle(coords, maxDistance)
    local metadata = PartayKeysActiveFobMetadata
    if type(metadata) == 'table' and metadata.plate then
        return FindVehicleByPlate(metadata.plate, coords, maxDistance or 25.0)
    end

    return lib.getClosestVehicle(coords, 10.0, false)
end

local function RequestVehicleControl(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if NetworkHasControlOfEntity(vehicle) then return true end

    NetworkRequestControlOfEntity(vehicle)
    local timeout = GetGameTimer() + 500
    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeout do
        Wait(0)
        NetworkRequestControlOfEntity(vehicle)
    end

    return NetworkHasControlOfEntity(vehicle)
end

local function ApplyRemoteHeadlights(vehicle, enabled)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    RequestVehicleControl(vehicle)
    SetVehicleLights(vehicle, enabled and 2 or 1)
    SetVehicleFullbeam(vehicle, enabled)
    SetVehicleInteriorlight(vehicle, enabled)
end

local function FlashLockFeedbackLights(vehicle, lockState)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local flashes = lockState == 2 and 1 or 2
    local restoreRemoteHeadlights = Entity(vehicle).state.remoteHeadlights == true

    CreateThread(function()
        if not RequestVehicleControl(vehicle) then return end

        for _ = 1, flashes do
            if not DoesEntityExist(vehicle) then return end

            SetVehicleIndicatorLights(vehicle, 0, true)
            SetVehicleIndicatorLights(vehicle, 1, true)
            SetVehicleLights(vehicle, 2)
            Wait(160)

            SetVehicleIndicatorLights(vehicle, 0, false)
            SetVehicleIndicatorLights(vehicle, 1, false)
            SetVehicleLights(vehicle, 1)
            Wait(140)
        end

        if DoesEntityExist(vehicle) then
            ApplyRemoteHeadlights(vehicle, restoreRemoteHeadlights)
        end
    end)
end

RegisterNUICallback('closeUI', function(data, cb)
    PartayKeysCloseNui()
    PartayKeysSetActiveItemUi(nil)
    PartayKeysFobOpen = false
    PartayKeysActiveFobMetadata = nil
    PartayKeysClearNuiToken('fob')
    PartayKeysClearNuiToken('contract')
    PartayKeysClearNuiToken('gps_tablet')
    PartayKeysClearNuiToken('signal_finder')
    PartayKeysClearNuiToken('service_menu')
    PartayKeysClearNuiToken('key_menu')
    PartayKeysClearNuiToken('locksmith_setup')
    cb('ok')
end)

RegisterNUICallback('fobAction', function(data, cb)
    if not PartayKeysValidateNuiToken('fob', data and data.token) then
        Notify('Key Fob', 'Invalid fob session.', 'error')
        cb('error')
        return
    end

    local action = data.action
    local ped = cache.ped or PlayerPedId()
    local coords = GetEntityCoords(ped)
    local activeMetadata = PartayKeysActiveFobMetadata

    if action == 'info' and type(activeMetadata) == 'table' and activeMetadata.plate then
        PlayFobAnimation()
        local makeName = GetMetadataVehicleLabel(activeMetadata)

        Notify('Vehicle Info', ('Make: %s | Plate: %s'):format(makeName or 'Unknown', activeMetadata.plate), 'info')
        cb('ok')
        return
    end
    
    local vehicle = GetActiveFobVehicle(coords, action == 'valet' and PartayKeys_GetKeyTierNumber('oled', 'Valet', 'MaxDistance', 50.0) or 25.0)
    
    if not vehicle or vehicle == 0 then
        Notify('Error', 'No keyed vehicle in range.', 'error')
        cb('ok')
        return
    end

    if action == 'info' then
        PlayFobAnimation()
        local makeName = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
        local plate = GetVehicleNumberPlateText(vehicle)
        Notify('Vehicle Info', ('Make: %s | Plate: %s'):format(makeName, plate), 'info')
        
    elseif action == 'lock' or action == 'unlock' or action == 'trunk' or action == 'alarm' or action == 'headlights' or action == 'remote_engine' or action == 'valet' then
        -- Route these core actions back to the server for Zero-Trust Metadata Validation
        TriggerServerEvent('partay_keys:server:FobAction', action, VehToNet(vehicle))
    end

    cb('ok')
end)

RegisterNetEvent('partay_keys:client:StartValetDrive', function(netId, targetCoords)
    local vehicle = netId and NetToVeh(netId) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        Notify('OLED Valet', 'The vehicle signal was lost.', 'error')
        return
    end

    if not RequestVehicleControl(vehicle) then
        Notify('OLED Valet', 'Unable to control the vehicle for valet mode.', 'error')
        return
    end

    local driver = GetPedInVehicleSeat(vehicle, -1)
    if driver and driver ~= 0 and IsPedAPlayer(driver) then
        Notify('OLED Valet', 'Valet mode is unavailable while someone is driving.', 'error')
        return
    end

    if not driver or driver == 0 then
        local model = joaat('s_m_m_valet_01')
        lib.requestModel(model, 1500)
        driver = CreatePedInsideVehicle(vehicle, 26, model, -1, true, false)
        SetModelAsNoLongerNeeded(model)
    end

    if not driver or driver == 0 then
        Notify('OLED Valet', 'Unable to start valet driver.', 'error')
        return
    end

    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedKeepTask(driver, true)
    SetDriverAbility(driver, 0.8)
    SetDriverAggressiveness(driver, 0.15)

    local destination = vector3(tonumber(targetCoords and targetCoords.x) or 0.0, tonumber(targetCoords and targetCoords.y) or 0.0, tonumber(targetCoords and targetCoords.z) or 0.0)
    TaskVehicleDriveToCoordLongrange(driver, vehicle, destination.x, destination.y, destination.z, 10.0, 786603, 6.0)

    CreateThread(function()
        local timeout = GetGameTimer() + 45000
        while DoesEntityExist(vehicle) and DoesEntityExist(driver) and GetGameTimer() < timeout do
            if #(GetEntityCoords(vehicle) - destination) <= 8.0 then
                break
            end
            Wait(750)
        end

        if DoesEntityExist(driver) then
            ClearPedTasks(driver)
            TaskLeaveVehicle(driver, vehicle, 0)
            Wait(2500)
            if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
                DeleteEntity(driver)
            end
        end
    end)
end)

RegisterNetEvent('partay_keys:client:FobFeedback', function(action, netId, lockState, remoteHeadlights, remoteEngineRunning, actionSource)
    local vehicle = netId and NetToVeh(netId) or 0
    local ped = cache.ped or PlayerPedId()
    local isPhysicalKey = actionSource == 'basic_key' or actionSource == 'basic_key_preanimated'
    local isProximity = actionSource == 'proximity'
    local shouldPlayPhysicalKey = actionSource == 'basic_key'

    if shouldPlayPhysicalKey and vehicle ~= 0 and PartayKeysPlayBasicKeyAnimation then
        PartayKeysPlayBasicKeyAnimation(vehicle)
    elseif not isPhysicalKey and not isProximity and GetVehiclePedIsIn(ped, false) == 0 then
        PlayFobAnimation()
    end

    if not isPhysicalKey and vehicle ~= 0 then
        PlaySoundFromEntity(-1, "Remote_Control_Fob", vehicle, "PI_Menu_Sounds", false, 0)
    end

    if action == 'lock' or (action == 'toggle' and lockState == 2) then
        if vehicle ~= 0 then
            SetVehicleAlarm(vehicle, false)
            FlashLockFeedbackLights(vehicle, lockState)
        end
        if not isProximity then Notify('Vehicle', 'Vehicle locked.', 'success') end
    elseif action == 'unlock' or (action == 'toggle' and lockState == 1) then
        if vehicle ~= 0 then
            SetVehicleAlarm(vehicle, false)
            FlashLockFeedbackLights(vehicle, lockState)
        end
        if not isProximity then Notify('Vehicle', 'Vehicle unlocked.', 'success') end
    elseif action == 'trunk' and vehicle ~= 0 then
        local isOpen = GetVehicleDoorAngleRatio(vehicle, 5) > 0.1
        SetVehicleDoorShut(vehicle, 5, false)
        if not isOpen then SetVehicleDoorOpen(vehicle, 5, false, false) end
    elseif action == 'alarm' and vehicle ~= 0 then
        SetVehicleAlarm(vehicle, true)
        StartVehicleAlarm(vehicle)
    elseif action == 'headlights' and vehicle ~= 0 then
        ApplyRemoteHeadlights(vehicle, remoteHeadlights == true)
        Notify('Vehicle', 'Remote headlights toggled.', 'success')
    elseif action == 'remote_engine' and vehicle ~= 0 then
        SetVehicleEngineOn(vehicle, remoteEngineRunning == true, true, true)
        Notify('Vehicle', remoteEngineRunning and 'Remote engine started.' or 'Remote engine stopped.', remoteEngineRunning and 'success' or 'info')
    end
end)

RegisterNetEvent('partay_keys:client:FobAlarm', function(netId)
    local vehicle = netId and NetToVeh(netId) or 0
    if vehicle == 0 then return end

    SetVehicleAlarm(vehicle, true)
    StartVehicleAlarm(vehicle)
end)

RegisterNetEvent('partay_keys:client:AdvancedAlarmWarning', function(netId, message, repeats)
    local vehicle = netId and NetToVeh(netId) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local ped = cache and cache.ped or PlayerPedId()
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 45.0 then return end

    message = tostring(message or 'Warning, unauthorized entry attempt.')
    repeats = math.max(1, math.min(3, tonumber(repeats) or 2))

    Notify('Vehicle Alarm', message, 'warning')
    SendNUIMessage({
        action = 'alarmVoiceWarning',
        message = message,
        repeats = repeats
    })
end)

AddStateBagChangeHandler('alarmActive', nil, function(bagName, key, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle == 0 then return end

    if value == true then
        SetVehicleAlarm(vehicle, true)
        StartVehicleAlarm(vehicle)
    else
        SetVehicleAlarm(vehicle, false)
    end
end)

AddStateBagChangeHandler('remoteHeadlights', nil, function(bagName, key, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle == 0 then return end

    ApplyRemoteHeadlights(vehicle, value == true)
end)

AddStateBagChangeHandler('remoteEngineRunning', nil, function(bagName, key, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle == 0 then return end

    SetVehicleEngineOn(vehicle, value == true, true, true)
end)
