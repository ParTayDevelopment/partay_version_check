-- [[ Tier 1 & 2 Security Logistics ]] --

if lib and lib.locale then
    lib.locale()
end

local function T(localeKey, vars)
    if type(locale) ~= 'function' then return localeKey end

    local ok, value = pcall(locale, localeKey, vars)
    return ok and value or localeKey
end

local trackerPresenceByPlate = {}
local trackerOnlineNotificationAt = {}
local trackerMovementNotificationAt = {}
local trackerNotificationFirstScan = true

local function FindOnlinePlayerByCitizenId(citizenId)
    if not citizenId then return nil end
    citizenId = tostring(citizenId)

    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        local targetCitizenId = targetSrc and Bridge.GetCitizenID(targetSrc)
        if targetCitizenId and tostring(targetCitizenId) == citizenId then
            return targetSrc
        end
    end

    return nil
end

local function GetRegisteredVehicleOwnerId(plate)
    local registration = GetVehicleRegistration(plate)
    if not registration then return nil end

    local ownerColumn = GetOwnerColumn()
    return registration[ownerColumn]
end

local function NotifyTrackerOwner(ownerId, localeKey, params)
    local ownerSrc = FindOnlinePlayerByCitizenId(ownerId)
    if ownerSrc then
        Notify(ownerSrc, T('label_gps_tracker'), T(localeKey, params), 'warning')
    end
end

local function GetVehicleDriverSource(veh)
    local ok, driverPed = pcall(GetPedInVehicleSeat, veh, -1)
    if not ok or not driverPed or driverPed == 0 then return nil end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src and GetPlayerPed(src) == driverPed then
            return src
        end
    end

    return nil
end

local function IsOwnerInstalledProtectedTracker(src, plate, tracker)
    if not tracker or not PartayKeys_GpsTierHasFeature(tracker.tracker_tier or tracker.tier, 'OwnerInstallProtected') then
        return false
    end

    local trackerOwnerId = tracker.tracker_owner_id or tracker.owner_id
    local registeredOwnerId = GetRegisteredVehicleOwnerId(plate)
    local removerId = src and src > 0 and Bridge.GetCitizenID(src) or nil

    return trackerOwnerId ~= nil
        and registeredOwnerId ~= nil
        and tostring(trackerOwnerId) == tostring(registeredOwnerId)
        and tostring(removerId or '') ~= tostring(trackerOwnerId)
end

local function GetTrackerRowsForPlate(plate)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return {} end

    return MySQL.Sync.fetchAll([[
        SELECT id, tracker_owner_id, tracker_tier
        FROM partay_vehicle_trackers
        WHERE plate = ?
    ]], { plate }) or {}
end

local function NotifyTrackedVehicleOnline(plate, trackers)
    local now = os.time()
    for _, tracker in ipairs(trackers or {}) do
        local tierName = PartayKeys_GetGpsTierConfig(tracker.tracker_tier)
        if PartayKeys_GpsTierHasFeature(tierName, 'OnlineNotifications') then
            local key = ('%s:%s:online'):format(tostring(plate), tostring(tracker.tracker_owner_id))
            if not trackerOnlineNotificationAt[key] or now - trackerOnlineNotificationAt[key] >= 600 then
                trackerOnlineNotificationAt[key] = now
                NotifyTrackerOwner(tracker.tracker_owner_id, 'info_tracker_vehicle_online', { plate = plate })
            end
        end
    end
end

local function NotifyUnauthorizedTrackerMovement(veh, plate, trackers)
    local driverSrc = GetVehicleDriverSource(veh)
    if not driverSrc then return end

    local ok, speed = pcall(GetEntitySpeed, veh)
    if not ok or (tonumber(speed) or 0.0) < 2.0 then return end

    local registration = GetVehicleRegistration(plate)
    local possessionId = Entity(veh).state.possession_id
    local keyVersion = registration and tonumber(registration.key_version) or nil
    if registration and registration.possession_id and registration.possession_id ~= '' then
        possessionId = registration.possession_id
    end

    if type(PartayKeys_PlayerHasVehicleAccess) == 'function'
        and PartayKeys_PlayerHasVehicleAccess(driverSrc, plate, possessionId, keyVersion) then
        return
    end

    local now = os.time()
    for _, tracker in ipairs(trackers or {}) do
        local tierName = PartayKeys_GetGpsTierConfig(tracker.tracker_tier)
        if PartayKeys_GpsTierHasFeature(tierName, 'UnauthorizedMovementAlerts') then
            local key = ('%s:%s:%s:movement'):format(tostring(plate), tostring(tracker.tracker_owner_id), tostring(driverSrc))
            if not trackerMovementNotificationAt[key] or now - trackerMovementNotificationAt[key] >= 180 then
                trackerMovementNotificationAt[key] = now
                NotifyTrackerOwner(tracker.tracker_owner_id, 'warning_tracker_unauthorized_movement', { plate = plate })
            end
        end
    end
end

local function PersistSecurityDevice(plate, updates)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return end

    local storage = GetVehicleStorage()
    if updates.device == 'alarm' then
        MySQL.Async.execute(('UPDATE %s SET has_alarm = ?, alarm_tier = ? WHERE plate = ?'):format(storage.tableSql), {
            updates.enabled and 1 or 0,
            updates.enabled and updates.tier or nil,
            plate
        })
    elseif updates.device == 'tracker' then
        MySQL.Async.execute(('UPDATE %s SET has_tracker = ?, gps_tier = ?, tracker_owner_id = ? WHERE plate = ?'):format(storage.tableSql), {
            updates.enabled and 1 or 0,
            updates.enabled and updates.tier or nil,
            updates.enabled and updates.ownerId or nil,
            plate
        })
    elseif updates.device == 'valet_module' then
        MySQL.Async.execute(('UPDATE %s SET has_valet_module = ? WHERE plate = ?'):format(storage.tableSql), {
            updates.enabled and 1 or 0,
            plate
        })
    end
end

local function SyncTrackerState(veh, plate)
    if not veh or veh == 0 then return end

    plate = TrimPlate(plate or GetVehicleNumberPlateText(veh))
    local count = 0
    if plate and plate ~= '' then
        count = tonumber(MySQL.Sync.fetchScalar('SELECT COUNT(*) FROM partay_vehicle_trackers WHERE plate = ?', { plate })) or 0
    end

    Entity(veh).state:set('hasTracker', count > 0, true)
    if count == 0 then
        Entity(veh).state:set('tracker_owner_id', nil, true)
        Entity(veh).state:set('gpsTier', nil, true)
        PersistSecurityDevice(plate, { device = 'tracker', enabled = false })
    else
        local row = MySQL.Sync.fetchAll('SELECT tracker_tier FROM partay_vehicle_trackers WHERE plate = ? ORDER BY installed_at DESC, id DESC LIMIT 1', { plate }) or {}
        local tierName = row[1] and row[1].tracker_tier or PartayKeys_GetDefaultGpsTier()
        tierName = PartayKeys_GetGpsTierConfig(tierName)
        Entity(veh).state:set('gpsTier', tierName, true)
        PersistSecurityDevice(plate, { device = 'tracker', enabled = true, ownerId = nil, tier = tierName })
    end
end

local function GetGpsTrackerItemForTier(tierName)
    local resolvedTier, tierConfig = PartayKeys_GetGpsTierConfig(tierName)
    return tierConfig.Item or PartayKeys_GetGpsTrackerItem(), resolvedTier, tierConfig
end

local function GetVehicleTrackers(plate, requesterId)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return {} end

    local rows = MySQL.Sync.fetchAll([[
        SELECT id, tracker_owner_id, tracker_tier, installed_at
        FROM partay_vehicle_trackers
        WHERE plate = ?
        ORDER BY installed_at ASC, id ASC
    ]], { plate }) or {}

    local trackers = {}
    for _, row in ipairs(rows) do
        local tierName, tierConfig = PartayKeys_GetGpsTierConfig(row.tracker_tier)
        trackers[#trackers + 1] = {
            id = row.id,
            owner_id = row.tracker_owner_id,
            tier = tierName,
            tier_label = tierConfig.Label or tierName,
            protected = IsOwnerInstalledProtectedTracker(0, plate, row),
            own = requesterId ~= nil and tostring(row.tracker_owner_id or '') == tostring(requesterId),
            installed_at = row.installed_at
        }
    end

    return trackers
end

local function PlayerHasTrackerTablet(src)
    local items = GetInventoryItems(src)
    for _, item in pairs(items) do
        local itemName = item.name or item.item
        if itemName == PartayKeys_GetGpsTabletItem() then
            return true
        end
    end

    return false
end

local function FindTrackedVehicleForPlayer(src)
    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then return nil end

    local trackedRows = MySQL.Sync.fetchAll('SELECT plate FROM partay_vehicle_trackers WHERE tracker_owner_id = ?', { citizenId }) or {}
    local trackedPlates = {}
    for _, row in ipairs(trackedRows) do
        local plate = TrimPlate(row.plate)
        if plate and plate ~= '' then
            trackedPlates[plate] = true
        end
    end

    local ped = GetPlayerPed(src)
    local pedCoords = ped and ped ~= 0 and GetEntityCoords(ped) or nil
    local bestVehicle, bestDistance

    for _, veh in ipairs(GetAllVehicles()) do
        local plate = TrimPlate(GetVehicleNumberPlateText(veh))
        if plate and trackedPlates[plate] then
            local distance = pedCoords and #(pedCoords - GetEntityCoords(veh)) or 0.0
            if not bestDistance or distance < bestDistance then
                bestVehicle = veh
                bestDistance = distance
            end
        end
    end

    if bestVehicle and bestVehicle ~= 0 then
        return bestVehicle
    end

    return nil
end

local function FindTrackedVehicleByPlate(plate)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return nil end

    for _, veh in ipairs(GetAllVehicles()) do
        if TrimPlate(GetVehicleNumberPlateText(veh)) == plate then
            return veh
        end
    end

    return nil
end

local function GetPlayerTrackerTargets(src)
    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then return {} end

    local rows = MySQL.Sync.fetchAll([[
        SELECT id, plate, tracker_tier, note, installed_at
        FROM partay_vehicle_trackers
        WHERE tracker_owner_id = ?
        ORDER BY installed_at DESC, id DESC
    ]], { citizenId }) or {}

    local targets = {}
    for _, row in ipairs(rows) do
        local plate = TrimPlate(row.plate)
        local veh = FindTrackedVehicleByPlate(plate)
        local tierName, tierConfig = PartayKeys_GetGpsTierConfig(row.tracker_tier)
        targets[#targets + 1] = {
            id = row.id,
            note = row.note or '',
            tier = tierName,
            tier_label = tierConfig.Label or tierName,
            ping_refresh = PartayKeys_GetGpsTierNumber(tierName, 'PingRefresh', 15),
            radius_size = PartayKeys_GetGpsTierNumber(tierName, 'RadiusSize', 150.0),
            blip_color = PartayKeys_GetGpsTierNumber(tierName, 'BlipColor', 1),
            blip_alpha = PartayKeys_GetGpsTierNumber(tierName, 'BlipAlpha', 128),
            installed_at = row.installed_at,
            available = veh ~= nil and veh ~= 0
        }
    end

    return targets
end

RegisterNetEvent('partay_keys:server:RemoveTracker', function(netId, plate)
    local src = source
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or not plate then
        Notify(src, T('label_gps_tracker'), T('error_tracker_remove_no_vehicle'), 'error')
        return
    end
    plate = TrimPlate(plate)
    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then
        Notify(src, T('label_gps_tracker'), T('error_tracker_verify_failed'), 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 5.0 then
        Notify(src, T('label_gps_tracker'), T('error_tracker_remove_too_far'), 'error')
        return
    end
    if not Entity(veh).state.hasTracker then
        Notify(src, T('label_gps_tracker'), T('error_tracker_not_found'), 'error')
        return
    end

    local trackers = GetVehicleTrackers(plate, Bridge.GetCitizenID(src))
    if #trackers == 0 then
        Entity(veh).state:set('hasTracker', false, true)
        Entity(veh).state:set('tracker_owner_id', nil, true)
        PersistSecurityDevice(plate, { device = 'tracker', enabled = false })
        Bridge.AddInventoryItem(src, PartayKeys_GetGpsTrackerItem(), 1)
        Notify(src, T('label_gps_tracker'), T('success_tracker_removed'), 'success')
        return
    end

    if #trackers ~= 1 then
        Notify(src, T('label_gps_tracker'), T('info_tracker_choose_remove'), 'info')
        return
    end

    if IsOwnerInstalledProtectedTracker(src, plate, trackers[1]) then
        Notify(src, T('label_gps_tracker'), T('error_tracker_protected_owner_installed'), 'error')
        return
    end

    MySQL.Async.execute('DELETE FROM partay_vehicle_trackers WHERE id = ? AND plate = ?', { trackers[1].id, plate }, function(affected)
        if not affected or affected < 1 then
            Notify(src, T('label_gps_tracker'), T('error_tracker_remove_failed'), 'error')
            return
        end
        SyncTrackerState(veh, plate)
        Bridge.AddInventoryItem(src, GetGpsTrackerItemForTier(trackers[1].tier), 1)
        Notify(src, T('label_gps_tracker'), T('success_tracker_removed'), 'success')
    end)
end)

lib.callback.register('partay_keys:server:GetVehicleTrackers', function(src, netId, plate)
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or not plate then return {} end

    plate = TrimPlate(plate)
    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then return {} end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 5.0 then return {} end

    return GetVehicleTrackers(plate, Bridge.GetCitizenID(src))
end)

lib.callback.register('partay_keys:server:GetTrackerTargets', function(src)
    if not PlayerHasTrackerTablet(src) then
        return {}
    end

    return GetPlayerTrackerTargets(src)
end)

RegisterNetEvent('partay_keys:server:UpdateTrackerNote', function(trackerId, note)
    local src = source
    local citizenId = Bridge.GetCitizenID(src)
    trackerId = tonumber(trackerId)
    if not citizenId or not trackerId then return end

    note = tostring(note or ''):sub(1, 255)
    MySQL.Async.execute('UPDATE partay_vehicle_trackers SET note = ? WHERE id = ? AND tracker_owner_id = ?', {
        note,
        trackerId,
        citizenId
    }, function(affected)
        if not affected or affected < 1 then
            Notify(src, T('label_gps_tablet'), T('error_tracker_note_save_failed'), 'error')
        end
    end)
end)

RegisterNetEvent('partay_keys:server:ForgetTrackerRecord', function(trackerId)
    local src = source
    local citizenId = Bridge.GetCitizenID(src)
    trackerId = tonumber(trackerId)
    if not citizenId or not trackerId then return end

    local rows = MySQL.Sync.fetchAll('SELECT plate FROM partay_vehicle_trackers WHERE id = ? AND tracker_owner_id = ? LIMIT 1', { trackerId, citizenId }) or {}
    local tracker = rows[1]
    if not tracker then
        Notify(src, T('label_gps_tablet'), T('error_tracker_record_unavailable'), 'error')
        return
    end

    MySQL.Async.execute('DELETE FROM partay_vehicle_trackers WHERE id = ? AND tracker_owner_id = ?', { trackerId, citizenId }, function(affected)
        if not affected or affected < 1 then
            Notify(src, T('label_gps_tablet'), T('error_tracker_record_remove_failed'), 'error')
            return
        end

        local veh = FindTrackedVehicleByPlate(tracker.plate) or 0
        if veh ~= 0 then
            SyncTrackerState(veh, tracker.plate)
        end

        Notify(src, T('label_gps_tablet'), T('success_tracker_forgotten'), 'success')
    end)
end)

RegisterNetEvent('partay_keys:server:RemoveTrackerById', function(netId, plate, trackerId)
    local src = source
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    trackerId = tonumber(trackerId)
    if veh == 0 or not plate or not trackerId then
        Notify(src, T('label_gps_tracker'), T('error_tracker_no_selection'), 'error')
        return
    end

    plate = TrimPlate(plate)
    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then
        Notify(src, T('label_gps_tracker'), T('error_tracker_verify_failed'), 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 5.0 then
        Notify(src, T('label_gps_tracker'), T('error_tracker_remove_too_far'), 'error')
        return
    end

    local rows = MySQL.Sync.fetchAll('SELECT id, tracker_owner_id, tracker_tier FROM partay_vehicle_trackers WHERE id = ? AND plate = ? LIMIT 1', { trackerId, plate }) or {}
    local tracker = rows[1]
    if tracker and IsOwnerInstalledProtectedTracker(src, plate, tracker) then
        Notify(src, T('label_gps_tracker'), T('error_tracker_protected_owner_installed'), 'error')
        return
    end

    local trackerTier = tracker and tracker.tracker_tier or nil
    MySQL.Async.execute('DELETE FROM partay_vehicle_trackers WHERE id = ? AND plate = ?', { trackerId, plate }, function(affected)
        if not affected or affected < 1 then
            Notify(src, T('label_gps_tracker'), T('error_tracker_remove_failed'), 'error')
            return
        end
        SyncTrackerState(veh, plate)
        Bridge.AddInventoryItem(src, GetGpsTrackerItemForTier(trackerTier), 1)
        Notify(src, T('label_gps_tracker'), T('success_tracker_removed'), 'success')
    end)
end)

RegisterNetEvent('partay_keys:server:InstallSecurityDevice', function(netId, plate, deviceType, deviceTier, itemName)
    local src = source
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or not plate then
        Notify(src, T('label_vehicle_security'), T('error_security_install_no_vehicle'), 'error')
        return
    end

    plate = TrimPlate(plate)
    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then
        Notify(src, T('label_vehicle_security'), T('error_security_verify_failed'), 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 6.0 then
        Notify(src, T('label_vehicle_security'), T('error_security_install_too_far'), 'error')
        return
    end

    if deviceType == 'alarm' then
        if Entity(veh).state.hasAlarm then
            Notify(src, T('label_car_alarm'), T('error_alarm_already_installed'), 'error')
            return
        end

        local resolvedTier, tierConfig = PartayKeys_GetAlarmTierConfig(deviceTier)
        local expectedItem = tierConfig.Item or PartayKeys_GetAlarmItem()
        if not tierConfig.Item and resolvedTier ~= PartayKeys_GetDefaultAlarmTier() then
            Notify(src, T('label_car_alarm'), T('error_security_device_unsupported'), 'error')
            return
        end
        if itemName and itemName ~= expectedItem then
            local itemTier = PartayKeys_GetAlarmTierFromItem(itemName)
            if itemTier ~= resolvedTier then
                Notify(src, T('label_car_alarm'), T('error_security_device_unsupported'), 'error')
                return
            end
            expectedItem = itemName
        end

        if not Bridge.RemoveInventoryItem(src, expectedItem, 1) then
            Notify(src, T('label_car_alarm'), T('error_need_car_alarm'), 'error')
            return
        end

        Entity(veh).state:set('hasAlarm', true, true)
        Entity(veh).state:set('alarmTier', resolvedTier, true)
        PersistSecurityDevice(plate, { device = 'alarm', enabled = true, tier = resolvedTier })
        Notify(src, T('label_car_alarm'), T('success_alarm_installed_tier', { tier = tierConfig.Label or resolvedTier }), 'success')
    elseif deviceType == 'tracker' then
        local citizenId = Bridge.GetCitizenID(src)
        if not citizenId then
            Notify(src, T('label_gps_tracker'), T('error_character_unavailable'), 'error')
            return
        end

        local existing = MySQL.Sync.fetchScalar('SELECT id FROM partay_vehicle_trackers WHERE plate = ? AND tracker_owner_id = ? LIMIT 1', { plate, citizenId })
        if existing then
            Notify(src, T('label_gps_tracker'), T('error_tracker_already_installed'), 'error')
            return
        end

        local resolvedTier, tierConfig = PartayKeys_GetGpsTierConfig(deviceTier)
        local expectedItem = tierConfig.Item or PartayKeys_GetGpsTrackerItem()
        if not tierConfig.Item and resolvedTier ~= PartayKeys_GetDefaultGpsTier() then
            Notify(src, T('label_gps_tracker'), T('error_security_device_unsupported'), 'error')
            return
        end
        if itemName and itemName ~= expectedItem then
            local itemTier = PartayKeys_GetGpsTierFromItem(itemName)
            if itemTier ~= resolvedTier then
                Notify(src, T('label_gps_tracker'), T('error_security_device_unsupported'), 'error')
                return
            end
            expectedItem = itemName
        end

        if not Bridge.RemoveInventoryItem(src, expectedItem, 1) then
            Notify(src, T('label_gps_tracker'), T('error_need_gps_tracker'), 'error')
            return
        end

        MySQL.Async.execute('INSERT INTO partay_vehicle_trackers (plate, tracker_owner_id, tracker_tier) VALUES (?, ?, ?)', { plate, citizenId, resolvedTier })
        Entity(veh).state:set('hasTracker', true, true)
        Entity(veh).state:set('gpsTier', resolvedTier, true)
        Entity(veh).state:set('tracker_owner_id', citizenId, true)
        PersistSecurityDevice(plate, { device = 'tracker', enabled = true, ownerId = citizenId, tier = resolvedTier })
        Notify(src, T('label_gps_tracker'), T('success_tracker_installed_tier', { tier = tierConfig.Label or resolvedTier }), 'success')
    elseif deviceType == 'valet_module' then
        local expectedItem = Config.Items.ValetModule
        if itemName and itemName ~= expectedItem then
            Notify(src, T('label_vehicle_security'), T('error_security_device_unsupported'), 'error')
            return
        end

        if Entity(veh).state.hasValetModule or VehicleHasValetModule(veh, plate) then
            Notify(src, T('label_vehicle_security'), 'This vehicle already has a valet module installed.', 'error')
            return
        end

        if not Bridge.RemoveInventoryItem(src, expectedItem, 1) then
            Notify(src, T('label_vehicle_security'), 'You need a valet module to install this upgrade.', 'error')
            return
        end

        Entity(veh).state:set('hasValetModule', true, true)
        PersistSecurityDevice(plate, { device = 'valet_module', enabled = true })
        Notify(src, T('label_vehicle_security'), 'Valet module installed.', 'success')
    else
        Notify(src, T('label_vehicle_security'), T('error_security_device_unsupported'), 'error')
    end
end)

RegisterNetEvent('partay_keys:server:RemoveVehicleAlarm', function(netId, plate, itemName)
    local src = source
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or not plate then
        Notify(src, T('label_car_alarm'), T('error_security_install_no_vehicle'), 'error')
        return
    end

    plate = TrimPlate(plate)
    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then
        Notify(src, T('label_car_alarm'), T('error_security_verify_failed'), 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 6.0 then
        Notify(src, T('label_car_alarm'), T('error_security_install_too_far'), 'error')
        return
    end

    if itemName ~= Config.Items.AlarmRemovalTool or not Bridge.HasInventoryItem(src, Config.Items.AlarmRemovalTool, 1) then
        Notify(src, T('label_car_alarm'), 'You need an alarm removal tool to remove this alarm.', 'error')
        return
    end

    if not VehicleHasAlarm(veh, plate) then
        Notify(src, T('label_car_alarm'), 'This vehicle does not have an alarm installed.', 'error')
        return
    end

    local alarmTier = GetVehicleAlarmTier(veh, plate)
    local returnItem = PartayKeys_GetAlarmItemForTier(alarmTier)
    Entity(veh).state:set('hasAlarm', false, true)
    Entity(veh).state:set('alarmTier', nil, true)
    Entity(veh).state:set('alarmActive', false, true)
    PersistSecurityDevice(plate, { device = 'alarm', enabled = false })

    if returnItem then
        Bridge.AddInventoryItem(src, returnItem, 1)
    end

    Notify(src, T('label_car_alarm'), 'Vehicle alarm removed.', 'success')
end)

RegisterNetEvent('partay_keys:server:TriggerVehicleAlarm', function(netId, plate)
    local src = source
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    if veh == 0 or not plate or plate == '' then return end
    if GetVehicleNumberPlateText(veh):gsub('^%s*(.-)%s*$', '%1') ~= plate then return end
    if not VehicleHasAlarm(veh, plate) then return end
    if Entity(veh).state.alarmActive then return end
    local alarmTier = GetVehicleAlarmTier(veh, plate)
    if not PartayKeys_AlarmTierHasFeature(alarmTier, 'DamageAlarm') then return end

    local lockState = Entity(veh).state.lockState or GetVehicleDoorLockStatus(veh)
    if lockState ~= 2 and lockState ~= 4 and lockState ~= 7 then return end

    local ok, engineRunning = pcall(GetIsVehicleEngineRunning, veh)
    if ok and engineRunning then return end

    Entity(veh).state:set('alarmActive', true, true)
    TriggerClientEvent('partay_keys:client:FobAlarm', -1, NetworkGetNetworkIdFromEntity(veh))
    StartAlarmTimer(veh)
    if type(PartayKeys_SendSmartAlarmNotification) == 'function' then
        PartayKeys_SendSmartAlarmNotification(veh, plate, alarmTier, 'damage')
    end
    exports.partay_keys:SendAuditLog('Vehicle Alarm Triggered', ('Vehicle alarm triggered by damage on plate %s near player %s'):format(plate, src), 'info')
end)

RegisterNetEvent('partay_keys:server:RequestTrackCar', function(vehNetId, coords, trackerId)
    local src = source

    if not PlayerHasTrackerTablet(src) then
        Notify(src, T('label_gps_tracker'), T('error_need_gps_tablet'), 'error')
        return
    end

    local veh = vehNetId and NetworkGetEntityFromNetworkId(vehNetId) or 0

    trackerId = tonumber(trackerId)
    local selectedTracker = trackerId ~= nil
    local trackingTier = nil
    if trackerId then
        local citizenId = Bridge.GetCitizenID(src)
        local row = citizenId and MySQL.Sync.fetchAll('SELECT plate, tracker_tier FROM partay_vehicle_trackers WHERE id = ? AND tracker_owner_id = ? LIMIT 1', { trackerId, citizenId }) or nil
        local tracker = row and row[1]
        if not tracker then
            Notify(src, T('label_gps_tracker'), T('error_tracker_unavailable'), 'error')
            return
        end

        trackingTier = tracker.tracker_tier
        veh = FindTrackedVehicleByPlate(tracker.plate) or 0
        vehNetId = veh ~= 0 and NetworkGetNetworkIdFromEntity(veh) or nil
    end

    if (not veh or veh == 0) and not selectedTracker then
        veh = FindTrackedVehicleForPlayer(src) or 0
        vehNetId = veh ~= 0 and NetworkGetNetworkIdFromEntity(veh) or nil
    end

    if not veh or veh == 0 or not Entity(veh).state.hasTracker then
        Notify(src, T('label_gps_tracker'), T('error_tracker_signal_missing'), 'error')
        return
    end

    local vehCoords = GetEntityCoords(veh)
    local tierName, tierConfig = PartayKeys_GetGpsTierConfig(trackingTier or Entity(veh).state.gpsTier)
    TriggerClientEvent('partay_keys:client:StartTracking', src, vehNetId, { x = vehCoords.x, y = vehCoords.y, z = vehCoords.z }, {
        tier = tierName,
        label = tierConfig.Label or tierName,
        pingRefresh = PartayKeys_GetGpsTierNumber(tierName, 'PingRefresh', 15),
        radiusSize = PartayKeys_GetGpsTierNumber(tierName, 'RadiusSize', 150.0),
        blipColor = PartayKeys_GetGpsTierNumber(tierName, 'BlipColor', 1),
        blipAlpha = PartayKeys_GetGpsTierNumber(tierName, 'BlipAlpha', 128)
    })
end)

CreateThread(function()
    Wait(5000)

    while true do
        local currentPlates = {}

        for _, veh in ipairs(GetAllVehicles()) do
            if veh and veh ~= 0 and Entity(veh).state.hasTracker == true then
                local plate = TrimPlate(GetVehicleNumberPlateText(veh))
                if plate and plate ~= '' then
                    currentPlates[plate] = true
                    local trackers = GetTrackerRowsForPlate(plate)
                    if #trackers > 0 then
                        if trackerPresenceByPlate[plate] ~= true then
                            trackerPresenceByPlate[plate] = true
                            if not trackerNotificationFirstScan then
                                NotifyTrackedVehicleOnline(plate, trackers)
                            end
                        end

                        NotifyUnauthorizedTrackerMovement(veh, plate, trackers)
                    end
                end
            end
        end

        for plate in pairs(trackerPresenceByPlate) do
            if not currentPlates[plate] then
                trackerPresenceByPlate[plate] = false
            end
        end

        trackerNotificationFirstScan = false
        Wait(15000)
    end
end)
