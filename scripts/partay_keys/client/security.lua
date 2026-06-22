-- [[ Tier 1 & 2 Security Mechanics ]] --

if lib and lib.locale then
    lib.locale()
end

local activeTracker = nil
local alarmHealthCache = {}
local alarmTriggerCooldown = {}
local alarmVehicles = {}
local trackerVehicles = {}

local wheelBones = {
    'wheel_lf',
    'wheel_rf',
    'wheel_rr',
    'wheel_lr'
}

local function TrackStateVehicle(store, vehicle, enabled)
    if not vehicle or vehicle == 0 then return end
    if enabled then
        store[vehicle] = true
    else
        store[vehicle] = nil
    end
end

local function PrimeTrackedVehicleSets()
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local state = Entity(veh).state
        if state.hasAlarm then alarmVehicles[veh] = true end
        if state.hasTracker then trackerVehicles[veh] = true end
    end
end

local function TableHasEntries(tbl)
    return next(tbl) ~= nil
end

local function IsAlarmArmed(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if not Entity(vehicle).state.hasAlarm or Entity(vehicle).state.alarmActive then return false end

    local lockState = Entity(vehicle).state.lockState or GetVehicleDoorLockStatus(vehicle)
    return (lockState == 2 or lockState == 4 or lockState == 7) and not GetIsVehicleEngineRunning(vehicle)
end

local function TryTriggerDamageAlarm(vehicle)
    if not IsAlarmArmed(vehicle) then return end

    local now = GetGameTimer()
    local alarmTier = Entity(vehicle).state.alarmTier
    local cooldown = PartayKeys_GetAlarmTierNumber(alarmTier, 'Cooldown', 60) * 1000
    if alarmTriggerCooldown[vehicle] and now - alarmTriggerCooldown[vehicle] <= cooldown then return end

    alarmTriggerCooldown[vehicle] = now
    TriggerServerEvent('partay_keys:server:TriggerVehicleAlarm', VehToNet(vehicle), GetVehicleNumberPlateText(vehicle))
end

local function GetNearbyVehicle(maxDistance)
    local ped = cache.ped or PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then return veh end

    return lib.getClosestVehicle(GetEntityCoords(ped), maxDistance or 5.0, false)
end

local function GetWheelBonePosition(vehicle, boneName)
    local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
    if boneIndex == -1 then return nil end

    return GetWorldPositionOfEntityBone(vehicle, boneIndex)
end

local function GetNearestWheelBone(vehicle)
    local ped = cache.ped or PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local nearestBone = wheelBones[1]
    local nearestCoords = nil
    local nearestDistance = 999999.0

    for _, boneName in ipairs(wheelBones) do
        local wheelCoords = GetWheelBonePosition(vehicle, boneName)
        if wheelCoords then
            local distance = #(pedCoords - wheelCoords)
            if distance < nearestDistance then
                nearestBone = boneName
                nearestCoords = wheelCoords
                nearestDistance = distance
            end
        end
    end

    return nearestBone, nearestCoords or GetEntityCoords(vehicle)
end

local function MovePedToVehicleBone(vehicle, boneName)
    local ped = cache.ped or PlayerPedId()
    local boneCoords = GetWheelBonePosition(vehicle, boneName)
    if not boneCoords then return nil end

    local vehicleCoords = GetEntityCoords(vehicle)
    local approach = boneCoords + (boneCoords - vehicleCoords) * 0.18
    local heading = GetHeadingFromVector_2d(boneCoords.x - approach.x, boneCoords.y - approach.y)

    TaskGoStraightToCoord(ped, approach.x, approach.y, approach.z, 1.0, 1600, heading, 0.08)

    local timeout = GetGameTimer() + 1800
    while GetGameTimer() < timeout do
        if #(GetEntityCoords(ped) - approach) <= 0.28 then break end
        Wait(50)
    end

    ClearPedTasks(ped)
    SetEntityHeading(ped, heading)
    TaskTurnPedToFaceCoord(ped, boneCoords.x, boneCoords.y, boneCoords.z, 500)
    Wait(250)

    return boneCoords
end

local function PlaySecurityAnimationAtWheel(vehicle, anim, duration, boneName)
    if not anim then return end

    local ped = cache.ped or PlayerPedId()
    boneName = boneName or GetNearestWheelBone(vehicle)
    MovePedToVehicleBone(vehicle, boneName)

    lib.requestAnimDict(anim.dict, 1000)
    TaskPlayAnim(ped, anim.dict, anim.name, 8.0, 8.0, duration or anim.duration, anim.flags or 1, 1, false, false, false)
    Wait(duration or anim.duration)
    ClearPedTasks(ped)
end

local function PlayInstallAnimation(vehicle, duration)
    PlaySecurityAnimationAtWheel(vehicle, Animations.TrackerInstall, duration)
end

local function GetEngineBayPosition(vehicle)
    local bonnetIndex = GetEntityBoneIndexByName(vehicle, 'bonnet')
    if bonnetIndex ~= -1 then
        local bonnetCoords = GetWorldPositionOfEntityBone(vehicle, bonnetIndex)
        local vehicleCoords = GetEntityCoords(vehicle)
        return bonnetCoords + (bonnetCoords - vehicleCoords) * 0.72, bonnetCoords
    end

    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local frontY = maxDim.y + 0.75
    local frontCoords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, frontY, 0.0)
    local lookCoords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, maxDim.y * 0.55, 0.0)
    return frontCoords, lookCoords
end

local function MovePedToEngineBay(vehicle)
    local ped = cache.ped or PlayerPedId()
    local approach, lookCoords = GetEngineBayPosition(vehicle)
    if not approach then return nil end

    local heading = GetHeadingFromVector_2d(lookCoords.x - approach.x, lookCoords.y - approach.y)
    TaskGoStraightToCoord(ped, approach.x, approach.y, approach.z, 1.0, 1800, heading, 0.08)

    local timeout = GetGameTimer() + 2200
    while GetGameTimer() < timeout do
        if #(GetEntityCoords(ped) - approach) <= 0.32 then break end
        Wait(50)
    end

    ClearPedTasks(ped)
    SetEntityHeading(ped, heading)
    TaskTurnPedToFaceCoord(ped, lookCoords.x, lookCoords.y, lookCoords.z, 500)
    Wait(250)

    return lookCoords
end

local function PlayAlarmInstallAnimation(vehicle, duration)
    local anim = Animations.AlarmInstall or Animations.TrackerInstall
    local ped = cache.ped or PlayerPedId()
    local hoodWasOpen = GetVehicleDoorAngleRatio(vehicle, 4) > 0.1

    MovePedToEngineBay(vehicle)
    SetVehicleDoorOpen(vehicle, 4, false, false)
    Wait(650)

    lib.requestAnimDict(anim.dict, 1000)
    TaskPlayAnim(ped, anim.dict, anim.name, 8.0, 8.0, duration or anim.duration, anim.flags or 1, 1, false, false, false)
    Wait(duration or anim.duration)
    ClearPedTasks(ped)

    if not hoodWasOpen and DoesEntityExist(vehicle) then
        SetVehicleDoorShut(vehicle, 4, false)
    end
end

local function TrackNearestVehicle()
    local ped = cache.ped or PlayerPedId()
    local coords = GetEntityCoords(ped)
    local bestVeh = nil
    local bestDist = 999999

    for veh in pairs(trackerVehicles) do
        if DoesEntityExist(veh) and Entity(veh).state.hasTracker then
            local vehCoords = GetEntityCoords(veh)
            local dist = #(coords - vehCoords)
            if dist < bestDist then
                bestDist = dist
                bestVeh = veh
            end
        else
            trackerVehicles[veh] = nil
        end
    end

    if not bestVeh then
        TriggerServerEvent('partay_keys:server:RequestTrackCar')
        return
    end

    local vehCoords = GetEntityCoords(bestVeh)
    TriggerServerEvent('partay_keys:server:RequestTrackCar', VehToNet(bestVeh), { x = vehCoords.x, y = vehCoords.y, z = vehCoords.z })
end

local function GetItemSlot(itemData, slotData)
    if PartayKeysDebugItemUse then
        PartayKeysDebugItemUse(('Security slot resolver itemDataType=%s itemDataSlot=%s slotDataType=%s slotDataSlot=%s'):format(
            type(itemData),
            tostring(type(itemData) == 'table' and itemData.slot or itemData),
            type(slotData),
            tostring(type(slotData) == 'table' and slotData.slot or slotData)
        ))
    end

    if type(slotData) == 'table' and slotData.slot then return slotData.slot end
    if type(itemData) == 'table' and itemData.slot then return itemData.slot end
    if type(slotData) == 'number' then return slotData end
    if type(itemData) == 'number' then return itemData end
    return nil
end

local function OpenGpsTablet(itemSlot)
    if PartayKeysDebugItemUse then
        PartayKeysDebugItemUse(('OpenGpsTablet requested itemSlot=%s activeGps=%s activeAny=%s'):format(
            tostring(itemSlot),
            tostring(PartayKeysIsActiveItemUi('gps_tablet')),
            tostring(PartayKeysIsActiveItemUi())
        ))
    end

    if PartayKeysIsActiveItemUi('gps_tablet') then
        if PartayKeysDebugItemUse then PartayKeysDebugItemUse('OpenGpsTablet toggling tablet closed') end
        PartayKeysCloseItemUi('gps_tablet')
        PartayKeysClearNuiToken('gps_tablet')
        return
    end
    if PartayKeysIsActiveItemUi() then
        if PartayKeysDebugItemUse then PartayKeysDebugItemUse('OpenGpsTablet closing other active item UI before opening tablet') end
        PartayKeysCloseItemUi()
    end

    local trackers = lib.callback.await('partay_keys:server:GetTrackerTargets', false) or {}
    if PartayKeysDebugItemUse then PartayKeysDebugItemUse(('OpenGpsTablet trackerCount=%s'):format(tostring(#trackers))) end
    if #trackers == 0 then
        Notify(locale('label_gps_tracker'), locale('error_tracker_records_empty'), 'error')
        return
    end

    PartayKeysShowHandProp('tablet')
    PartayKeysSetActiveItemUi('gps_tablet', itemSlot)
    PartayKeysOpenNui(true)
    SendNUIMessage({
        action = 'openGpsTablet',
        trackers = trackers,
        token = PartayKeysCreateNuiToken('gps_tablet')
    })
end

local function OpenSignalFinder(itemSlot)
    if PartayKeysDebugItemUse then
        PartayKeysDebugItemUse(('OpenSignalFinder requested itemSlot=%s activeSignal=%s activeAny=%s'):format(
            tostring(itemSlot),
            tostring(PartayKeysIsActiveItemUi('signal_finder')),
            tostring(PartayKeysIsActiveItemUi())
        ))
    end

    if PartayKeysIsActiveItemUi('signal_finder') then
        if PartayKeysDebugItemUse then PartayKeysDebugItemUse('OpenSignalFinder toggling signal finder closed') end
        PartayKeysCloseItemUi('signal_finder')
        PartayKeysClearNuiToken('signal_finder')
        return
    end
    if PartayKeysIsActiveItemUi() then
        if PartayKeysDebugItemUse then PartayKeysDebugItemUse('OpenSignalFinder closing other active item UI before opening finder') end
        PartayKeysCloseItemUi()
    end

    local veh = GetNearbyVehicle(4.0)
    if PartayKeysDebugItemUse then PartayKeysDebugItemUse(('OpenSignalFinder nearbyVehicle=%s'):format(tostring(veh))) end
    if not veh or veh == 0 then
        Notify(locale('label_signal_finder'), locale('error_no_vehicle_nearby'), 'error')
        return
    end

    local trackers = lib.callback.await('partay_keys:server:GetVehicleTrackers', false, VehToNet(veh), GetVehicleNumberPlateText(veh)) or {}
    if PartayKeysDebugItemUse then PartayKeysDebugItemUse(('OpenSignalFinder trackerCount=%s'):format(tostring(#trackers))) end
    PartayKeysShowHandProp('tablet')
    PartayKeysSetActiveItemUi('signal_finder', itemSlot)
    PartayKeysOpenNui(true)
    SendNUIMessage({
        action = 'openSignalFinder',
        vehicle = {
            netId = VehToNet(veh),
            plate = GetVehicleNumberPlateText(veh),
            label = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
        },
        trackers = trackers,
        token = PartayKeysCreateNuiToken('signal_finder')
    })
end

RegisterNUICallback('gpsTabletTrack', function(data, cb)
    if not PartayKeysValidateNuiToken('gps_tablet', data and data.token) then cb('error') return end
    TriggerServerEvent('partay_keys:server:RequestTrackCar', nil, nil, data and data.id)
    PartayKeysCloseItemUi('gps_tablet')
    PartayKeysClearNuiToken('gps_tablet')
    cb('ok')
end)

RegisterNUICallback('gpsTabletSaveNote', function(data, cb)
    if not PartayKeysValidateNuiToken('gps_tablet', data and data.token) then cb('error') return end
    TriggerServerEvent('partay_keys:server:UpdateTrackerNote', data and data.id, data and data.note)
    cb('ok')
end)

RegisterNUICallback('gpsTabletForgetTracker', function(data, cb)
    if not PartayKeysValidateNuiToken('gps_tablet', data and data.token) then cb('error') return end
    TriggerServerEvent('partay_keys:server:ForgetTrackerRecord', data and data.id)
    cb('ok')
end)

RegisterNUICallback('signalFinderRemoveTracker', function(data, cb)
    if not PartayKeysValidateNuiToken('signal_finder', data and data.token) then cb('error') return end

    local veh = data and data.netId and NetToVeh(data.netId) or 0
    if veh == 0 or not DoesEntityExist(veh) then
        Notify(locale('label_signal_finder'), locale('error_vehicle_signal_lost'), 'error')
        PartayKeysClearNuiToken('signal_finder')
        cb('error')
        return
    end

    PartayKeysCloseItemUi('signal_finder')
    PartayKeysClearNuiToken('signal_finder')
    PlaySecurityAnimationAtWheel(veh, Animations.RemoveTracker)
    TriggerServerEvent('partay_keys:server:RemoveTrackerById', data.netId, data.plate, data.id)
    cb('ok')
end)

RegisterNetEvent('partay_keys:client:UseSecurityItem', function(itemName, itemSlot)
    if PartayKeysDebugItemUse then PartayKeysDebugItemUse(('UseSecurityItem itemName=%s itemSlot=%s'):format(tostring(itemName), tostring(itemSlot))) end

    local alarmTier = PartayKeys_GetAlarmTierFromItem(itemName)
    if alarmTier then
        local veh = GetNearbyVehicle(4.0)
        if not veh or veh == 0 then
            Notify(locale('label_car_alarm'), locale('error_no_vehicle_nearby'), 'error')
            return
        end

        PlayAlarmInstallAnimation(veh, PartayKeys_GetAlarmInstallTime() or Animations.AlarmInstall.duration)
        TriggerServerEvent('partay_keys:server:InstallSecurityDevice', VehToNet(veh), GetVehicleNumberPlateText(veh), 'alarm', alarmTier, itemName)
        return
    end

    if itemName == Config.Items.AlarmRemovalTool then
        local veh = GetNearbyVehicle(4.0)
        if not veh or veh == 0 then
            Notify(locale('label_car_alarm'), locale('error_no_vehicle_nearby'), 'error')
            return
        end

        PlayAlarmInstallAnimation(veh, Animations.RemoveTracker.duration)
        TriggerServerEvent('partay_keys:server:RemoveVehicleAlarm', VehToNet(veh), GetVehicleNumberPlateText(veh), itemName)
        return
    end

    local gpsTier = PartayKeys_GetGpsTierFromItem(itemName)
    if gpsTier then
        local veh = GetNearbyVehicle(4.0)
        if not veh or veh == 0 then
            Notify(locale('label_gps_tracker'), locale('error_no_vehicle_nearby'), 'error')
            return
        end

        PlayInstallAnimation(veh, PartayKeys_GetGpsInstallTime() or Animations.TrackerInstall.duration)
        TriggerServerEvent('partay_keys:server:InstallSecurityDevice', VehToNet(veh), GetVehicleNumberPlateText(veh), 'tracker', gpsTier, itemName)
        return
    end

    if itemName == Config.Items.ValetModule then
        local veh = GetNearbyVehicle(4.0)
        if not veh or veh == 0 then
            Notify(locale('label_vehicle_security'), locale('error_no_vehicle_nearby'), 'error')
            return
        end

        PlayInstallAnimation(veh, Animations.TrackerInstall.duration)
        TriggerServerEvent('partay_keys:server:InstallSecurityDevice', VehToNet(veh), GetVehicleNumberPlateText(veh), 'valet_module', 'valet', itemName)
        return
    end

    if itemName == PartayKeys_GetGpsTabletItem() then
        OpenGpsTablet(itemSlot)
    elseif itemName == PartayKeys_GetSignalFinderItem() then
        OpenSignalFinder(itemSlot)
    end
end)

function UseGpsTabletItem(itemData, slotData)
    local itemSlot = GetItemSlot(itemData, slotData)
    if PartayKeysDebugItemUse then PartayKeysDebugItemUse(('UseGpsTabletItem export resolvedSlot=%s'):format(tostring(itemSlot))) end
    OpenGpsTablet(itemSlot)
end

function UseSignalFinderItem(itemData, slotData)
    local itemSlot = GetItemSlot(itemData, slotData)
    if PartayKeysDebugItemUse then PartayKeysDebugItemUse(('UseSignalFinderItem export resolvedSlot=%s'):format(tostring(itemSlot))) end
    OpenSignalFinder(itemSlot)
end

RegisterNetEvent('partay_keys:client:UseGpsTabletItem', UseGpsTabletItem)
RegisterNetEvent('partay_keys:client:UseSignalFinderItem', UseSignalFinderItem)
exports('UseGpsTabletItem', UseGpsTabletItem)
exports('UseSignalFinderItem', UseSignalFinderItem)

local function InspectAlarmVehicleDamage(veh)
    if not DoesEntityExist(veh) or not Entity(veh).state.hasAlarm then
        alarmVehicles[veh] = nil
        alarmHealthCache[veh] = nil
        alarmTriggerCooldown[veh] = nil
        return false
    end

    local bodyHealth = GetVehicleBodyHealth(veh)
    local engineHealth = GetVehicleEngineHealth(veh)
    local health = bodyHealth + engineHealth
    local previousHealth = alarmHealthCache[veh]
    local armed = IsAlarmArmed(veh)

    if armed then
        local alarmTier = Entity(veh).state.alarmTier
        local damageThreshold = PartayKeys_GetAlarmTierNumber(alarmTier, 'DamageThreshold', 0.1)
        if previousHealth and health < previousHealth - damageThreshold then
            TryTriggerDamageAlarm(veh)
        end

        if HasEntityBeenDamagedByAnyVehicle(veh) then
            TryTriggerDamageAlarm(veh)
            ClearEntityLastDamageEntity(veh)
        end
    else
        ClearEntityLastDamageEntity(veh)
    end

    alarmHealthCache[veh] = health
    return armed
end

CreateThread(function()
    Wait(1000)
    PrimeTrackedVehicleSets()

    while true do
        local sleep = TableHasEntries(alarmVehicles) and 1500 or 3000

        for veh in pairs(alarmVehicles) do
            if InspectAlarmVehicleDamage(veh) then
                sleep = 250
            end
        end

        Wait(sleep)
    end
end)

AddStateBagChangeHandler('hasAlarm', nil, function(bagName, _key, value)
    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 or GetEntityType(entity) ~= 2 then return end

    TrackStateVehicle(alarmVehicles, entity, value == true)
    if value ~= true then
        alarmHealthCache[entity] = nil
        alarmTriggerCooldown[entity] = nil
    else
        alarmHealthCache[entity] = GetVehicleBodyHealth(entity) + GetVehicleEngineHealth(entity)
    end
end)

AddStateBagChangeHandler('hasTracker', nil, function(bagName, _key, value)
    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 or GetEntityType(entity) ~= 2 then return end

    TrackStateVehicle(trackerVehicles, entity, value == true)
end)

AddEventHandler('gameEventTriggered', function(eventName, args)
    if eventName ~= 'CEventNetworkEntityDamage' then return end

    local victim = args and args[1]
    if not victim or victim == 0 or not DoesEntityExist(victim) then return end
    if GetEntityType(victim) ~= 2 then return end

    TryTriggerDamageAlarm(victim)
end)

-- [[ The GPS Tracking Command & Loop ]] --
RegisterCommand('trackcar', function()
    TrackNearestVehicle()
end)

RegisterNetEvent('partay_keys:client:StartTracking', function(vehNetId, coords, tierData)
    if activeTracker then
        RemoveBlip(activeTracker.blip)
        activeTracker = nil
    end
    
    -- Hardcoded min/max limits for performance safety
    tierData = type(tierData) == 'table' and tierData or {}
    local radiusSize = tonumber(tierData.radiusSize) or PartayKeys_GetGpsDefaultNumber('RadiusSize', 150.0)
    if radiusSize < 50.0 then radiusSize = 50.0 elseif radiusSize > 500.0 then radiusSize = 500.0 end
    
    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radiusSize)
    SetBlipHighDetail(blip, true)
    SetBlipColour(blip, tonumber(tierData.blipColor) or PartayKeys_GetGpsDefaultNumber('BlipColor', 1))
    SetBlipAlpha(blip, tonumber(tierData.blipAlpha) or PartayKeys_GetGpsDefaultNumber('BlipAlpha', 128))
    
    activeTracker = {
        blip = blip,
        netId = vehNetId,
        lastUpdate = GetGameTimer(),
        radius = radiusSize,
        pingRefresh = tonumber(tierData.pingRefresh) or PartayKeys_GetGpsDefaultNumber('PingRefresh', 15)
    }
    
    Notify(locale('label_tracker_active'), locale('success_tracker_location_acquired'), 'success')
    
    -- Lightweight tracking loop
    CreateThread(function()
        while activeTracker do
            Wait(2000)
            local ped = cache.ped or PlayerPedId()
            local pedCoords = GetEntityCoords(ped)
            local targetVeh = NetToVeh(activeTracker.netId)
            
            if DoesEntityExist(targetVeh) then
                local vehCoords = GetEntityCoords(targetVeh)
                local distToVeh = #(pedCoords - vehCoords)
                
                -- Terminate if player physically enters the zone
                if distToVeh <= activeTracker.radius then
                    Notify(locale('label_signal_strong'), locale('info_tracker_nearby'), 'info')
                    RemoveBlip(activeTracker.blip)
                    activeTracker = nil
                    break
                end
                
                -- Periodically refresh ping if timer exceeds config
                if GetGameTimer() - activeTracker.lastUpdate >= (activeTracker.pingRefresh * 1000) then
                    SetBlipCoords(activeTracker.blip, vehCoords.x, vehCoords.y, vehCoords.z)
                    activeTracker.lastUpdate = GetGameTimer()
                end
            end
        end
    end)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    pcall(TriggerEvent, 'chat:addSuggestion', '/trackcar', 'Request GPS tracking from your active tracker records.')
end)
