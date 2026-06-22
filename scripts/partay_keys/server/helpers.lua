-- [[ ParTay Keys - Shared Server Helpers ]] --

function TrimPlate(plate)
    return plate and plate:gsub('^%s*(.-)%s*$', '%1') or plate
end

function GetVehicleTableName()
    return (Bridge.GetFramework() == 'esx') and 'owned_vehicles' or 'player_vehicles'
end

function GetOwnerColumn()
    return (Bridge.GetFramework() == 'esx') and 'owner' or 'citizenid'
end

local function T(localeKey, vars)
    if type(locale) ~= 'function' then return localeKey end

    local ok, value = pcall(locale, localeKey, vars)
    return ok and value or localeKey
end

local allowedSqlIdentifiers = {
    owned_vehicles = true,
    player_vehicles = true,
    partay_vehicle_trackers = true,
    partay_vehicle_keys = true,
    partay_locksmith_stock = true,
    partay_locksmith_locations = true,
    partay_locksmith_prices = true,
    partay_locksmith_settings = true,
    partay_locksmith_appointments = true,
    partay_locksmith_stock_orders = true,
    partay_locksmith_shop_orders = true,
    partay_locksmith_invoices = true,
    partay_locksmith_logs = true,
    owner = true,
    owner_id = true,
    owner_name = true,
    citizenid = true,
    plate = true,
    possession_id = true,
    shared_keys = true,
    key_version = true,
    has_alarm = true,
    alarm_tier = true,
    has_tracker = true,
    gps_tier = true,
    tracker_owner_id = true,
    has_valet_module = true,
    tracker_tier = true,
    vehicle = true,
    hash = true,
    mods = true,
    state = true,
    id = true,
    note = true,
    installed_at = true,
    holder_id = true,
    holder_name = true,
    key_type = true,
    issued_by = true,
    issued_by_name = true,
    issued_at = true,
    revoked_at = true,
    revoked_reason = true,
    last_used_at = true,
    metadata = true,
    location_name = true,
    shop_type = true,
    job_name = true,
    point_type = true,
    label = true,
    model = true,
    coords = true,
    target_distance = true,
    active = true,
    spawn_prop = true,
    stock_method = true,
    stock_settings = true,
    created_by = true,
    price_key = true,
    price = true,
    updated_by = true,
    setting_key = true,
    setting_value = true,
    item_name = true,
    quantity = true,
    updated_at = true,
    order_id = true,
    ordered_by = true,
    ordered_by_name = true,
    order_items = true,
    pickup_coords = true,
    ready_at = true,
    completed_at = true,
    appointment_id = true,
    contact_name = true,
    contact_phone = true,
    contact_email = true,
    expires_at = true,
    accepted_by = true,
    accepted_by_name = true,
    scheduled_for = true,
    scheduled_date = true,
    scheduled_time = true,
    schedule_note = true,
    invoice_id = true,
    employee_id = true,
    employee_name = true,
    customer_id = true,
    customer_name = true,
    status = true,
    total = true,
    services = true,
    payment_method = true,
    society_deposit = true,
    message = true,
    actor_id = true,
    actor_name = true,
    target_id = true,
    target_name = true,
    action = true,
    created_at = true,
}

function QuoteSqlIdentifier(identifier)
    identifier = tostring(identifier or '')
    if not allowedSqlIdentifiers[identifier] then
        error(('ERR_DB_IDENTIFIER - Unsafe SQL identifier requested: %s'):format(identifier))
    end

    return ('`%s`'):format(identifier)
end

function GetVehicleStorage()
    local tableName = GetVehicleTableName()
    local ownerColumn = GetOwnerColumn()

    return {
        tableName = tableName,
        ownerColumn = ownerColumn,
        tableSql = QuoteSqlIdentifier(tableName),
        ownerSql = QuoteSqlIdentifier(ownerColumn)
    }
end

function GetVehicleRegistration(plate)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return nil end

    local storage = GetVehicleStorage()
    local rows = MySQL.Sync.fetchAll(('SELECT * FROM %s WHERE plate = ? LIMIT 1'):format(storage.tableSql), { plate })
    return rows and rows[1] or nil
end

function GetInventoryItems(src)
    if Bridge and Bridge.GetInventoryItems then
        return Bridge.GetInventoryItems(src)
    end

    return {}
end

function VehicleHasAlarm(veh, plate)
    if veh ~= 0 and DoesEntityExist(veh) and Entity(veh).state.hasAlarm then return true end

    plate = TrimPlate(plate)
    if not plate or plate == '' then return false end

    local ok, value = pcall(function()
        local storage = GetVehicleStorage()
        return MySQL.Sync.fetchScalar(('SELECT has_alarm FROM %s WHERE plate = ? LIMIT 1'):format(storage.tableSql), { plate })
    end)
    local hasAlarm = ok and tonumber(value) == 1
    if hasAlarm and veh ~= 0 and DoesEntityExist(veh) then
        Entity(veh).state:set('hasAlarm', true, true)
    end

    return hasAlarm
end

function GetVehicleAlarmTier(veh, plate)
    if veh ~= 0 and DoesEntityExist(veh) then
        local stateTier = Entity(veh).state.alarmTier
        if stateTier and stateTier ~= '' then
            return PartayKeys_GetAlarmTierConfig(stateTier)
        end
    end

    plate = TrimPlate(plate)
    if plate and plate ~= '' then
        local ok, value = pcall(function()
            local storage = GetVehicleStorage()
            return MySQL.Sync.fetchScalar(('SELECT alarm_tier FROM %s WHERE plate = ? LIMIT 1'):format(storage.tableSql), { plate })
        end)
        if ok and value and value ~= '' then
            local tierName, tierConfig = PartayKeys_GetAlarmTierConfig(value)
            if veh ~= 0 and DoesEntityExist(veh) then
                Entity(veh).state:set('alarmTier', tierName, true)
            end
            return tierName, tierConfig
        end
    end

    return PartayKeys_GetAlarmTierConfig()
end

function VehicleHasValetModule(veh, plate)
    if veh ~= 0 and DoesEntityExist(veh) and Entity(veh).state.hasValetModule then return true end

    plate = TrimPlate(plate)
    if not plate or plate == '' then return false end

    local ok, value = pcall(function()
        local storage = GetVehicleStorage()
        return MySQL.Sync.fetchScalar(('SELECT has_valet_module FROM %s WHERE plate = ? LIMIT 1'):format(storage.tableSql), { plate })
    end)
    local hasValetModule = ok and tonumber(value) == 1
    if hasValetModule and veh ~= 0 and DoesEntityExist(veh) then
        Entity(veh).state:set('hasValetModule', true, true)
    end

    return hasValetModule
end

function StartAlarmTimer(veh)
    local tierName = GetVehicleAlarmTier(veh, veh ~= 0 and DoesEntityExist(veh) and GetVehicleNumberPlateText(veh) or nil)
    local duration = PartayKeys_GetAlarmTierNumber(tierName, 'Duration', 30) * 1000
    CreateThread(function()
        Wait(duration)
        if veh ~= 0 and DoesEntityExist(veh) and Entity(veh).state.alarmActive then
            Entity(veh).state:set('alarmActive', false, true)
        end
    end)
end

local smartAlarmNotifyAt = {}
local smartAlarmEscalationAt = {}
local smartAlarmAttempts = {}

local function FindOnlineCharacterByCitizenId(citizenId)
    if not citizenId then return nil end
    citizenId = tostring(citizenId)

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local playerCitizenId = src and Bridge.GetCitizenID(src)
        if playerCitizenId and tostring(playerCitizenId) == citizenId then
            return src
        end
    end

    return nil
end

local function IsPlayerNearEntity(src, entity, distance)
    local ped = src and GetPlayerPed(src) or 0
    if not ped or ped == 0 or not entity or entity == 0 then return false end

    return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= (tonumber(distance) or 75.0)
end

function PartayKeys_SendSmartAlarmNotification(veh, plate, tierName, reason)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    plate = TrimPlate(plate or GetVehicleNumberPlateText(veh))
    if not plate or plate == '' then return end

    tierName = tierName or GetVehicleAlarmTier(veh, plate)
    if not PartayKeys_AlarmTierHasFeature(tierName, 'OwnerTamperNotifications') then return end

    local registration = GetVehicleRegistration(plate)
    if not registration then return end

    local ownerId = registration[GetOwnerColumn()]
    local ownerSrc = FindOnlineCharacterByCitizenId(ownerId)
    if not ownerSrc or IsPlayerNearEntity(ownerSrc, veh, 75.0) then return end

    local now = os.time()
    local notifyKey = ('%s:%s'):format(tostring(plate), tostring(ownerId))
    if not smartAlarmNotifyAt[notifyKey] or now - smartAlarmNotifyAt[notifyKey] >= 300 then
        smartAlarmNotifyAt[notifyKey] = now
        Notify(ownerSrc, 'Vehicle Security', T('warning_alarm_owner_tamper', { plate = plate }), 'warning')
    end

    if not PartayKeys_AlarmTierHasFeature(tierName, 'RepeatedAttemptEscalation') then return end

    local attempts = smartAlarmAttempts[notifyKey]
    if not attempts or now - attempts.startedAt > 300 then
        attempts = { startedAt = now, count = 0 }
        smartAlarmAttempts[notifyKey] = attempts
    end

    attempts.count = attempts.count + 1
    if attempts.count >= 2 and (not smartAlarmEscalationAt[notifyKey] or now - smartAlarmEscalationAt[notifyKey] >= 600) then
        smartAlarmEscalationAt[notifyKey] = now
        Notify(ownerSrc, 'Vehicle Security', T('warning_alarm_owner_repeated_attempts', { plate = plate }), 'warning')
    end
end

function TriggerInstalledAlarm(veh, requireInstalledAlarm, featureName)
    if veh == 0 or not DoesEntityExist(veh) then return false end
    if requireInstalledAlarm ~= false and not VehicleHasAlarm(veh, GetVehicleNumberPlateText(veh)) then return false end
    if Entity(veh).state.alarmActive then return false end

    local tierName = GetVehicleAlarmTier(veh, GetVehicleNumberPlateText(veh))
    featureName = featureName or 'FobPanic'
    if requireInstalledAlarm ~= false and not PartayKeys_AlarmTierHasFeature(tierName, featureName) then return false end
    Entity(veh).state:set('alarmActive', true, true)
    TriggerClientEvent('partay_keys:client:FobAlarm', -1, NetworkGetNetworkIdFromEntity(veh))
    StartAlarmTimer(veh)
    return true, tierName
end

function GetSafeVehicleClass(veh)
    local ok, class = pcall(GetVehicleClass, veh)
    return ok and tonumber(class) or nil
end

function HasDoorLockStep(veh)
    local class = GetSafeVehicleClass(veh)
    return class ~= 8 and class ~= 13 and class ~= 14 and class ~= 15 and class ~= 16
end

function HasIgnitionStep(veh)
    local class = GetSafeVehicleClass(veh)
    return class ~= 13
end

function IsEngineRunning(veh)
    local ok, running = pcall(GetIsVehicleEngineRunning, veh)
    return ok and running == true
end

function RequiresLockpick(veh)
    if not Config.Heist.EnableLockpicking or not HasDoorLockStep(veh) then return false end
    local lockState = Entity(veh).state.lockState or GetVehicleDoorLockStatus(veh)
    return lockState == 2 or lockState == 4 or lockState == 7
end

function RequiresHotwire(veh)
    if not Config.Heist.EnableHotwiring or not HasIgnitionStep(veh) then return false end
    if IsEngineRunning(veh) then return false end
    return true
end

function HasSatisfiedLockStep(veh, citizenId)
    if not Config.Heist.EnableLockpicking or not HasDoorLockStep(veh) then return true end

    local decodedBy = Entity(veh).state.lockDecodedBy
    if decodedBy then
        return decodedBy == citizenId
    end

    return not RequiresLockpick(veh)
end

function GetOnlinePoliceCount()
    local police = Config.Heist and Config.Heist.Police or {}
    return Bridge.CountOnlineJobs(police.Jobs or { 'police' }, true)
end

function MeetsPoliceRequirement(stepName)
    local police = Config.Heist and Config.Heist.Police
    local step = police and police[stepName]
    if not step or step.RequireOnline ~= true then return true, GetOnlinePoliceCount(), 0 end

    local required = math.max(0, tonumber(step.MinimumOnline) or 0)
    local online = GetOnlinePoliceCount()
    return online >= required, online, required
end
