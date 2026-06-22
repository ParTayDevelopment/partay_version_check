-- Server-Side Execution Only
if not IsDuplicityVersion() then return end

-- [[ The Persistence Interceptor ]] --
local DEFAULT_GARAGE_PROVIDERS = {
    qbx = {
        Resource = 'qbx_garages',
        VehicleTable = 'player_vehicles',
        OwnerColumn = 'citizenid',
        VehicleSpawnedEvents = { 'qbx_garages:server:vehicleSpawned' }
    },
    qb = {
        Resource = { 'qb-garages', 'qb-garages2' },
        VehicleTable = 'player_vehicles',
        OwnerColumn = 'citizenid',
        VehicleSpawnedEvents = {
            'qb-garages:server:vehicleSpawned',
            'qb-garages:server:VehicleSpawned',
            'qb-garages:server:spawnedVehicle'
        }
    },
    esx = {
        Resource = { 'esx_garage', 'esx_advancedgarage' },
        VehicleTable = 'owned_vehicles',
        OwnerColumn = 'owner',
        VehicleSpawnedEvents = {
            'esx_garage:server:vehicleSpawned',
            'esx_advancedgarage:server:vehicleSpawned'
        }
    },
    jg = {
        Resource = { 'jg-advancedgarages', 'jg-advanced-garages' },
        VehicleTable = 'player_vehicles',
        OwnerColumn = 'citizenid',
        VehicleSpawnedEvents = {
            'jg-advancedgarages:server:vehicleSpawned',
            'jg-advanced-garages:server:vehicleSpawned'
        }
    }
}

local garageNotifyCooldown = {}

local function TrimPlate(plate)
    return plate and plate:gsub('^%s*(.-)%s*$', '%1') or nil
end

local function GetGarageConfig()
    return Config.Integrations and Config.Integrations.Garage or {}
end

local function IsResourceStarted(resourceName)
    if type(resourceName) == 'table' then
        for _, name in ipairs(resourceName) do
            if GetResourceState(name) == 'started' then return true end
            if GetResourceState(name) == 'starting' then return true end
        end
        return false
    end

    if type(resourceName) ~= 'string' or resourceName == '' then return false end
    local state = GetResourceState(resourceName)
    return state == 'started' or state == 'starting'
end

local function NormalizeGarageProvider(provider)
    provider = tostring(provider or 'auto'):lower():gsub('^%s*(.-)%s*$', '%1')
    local aliases = {
        ['qbx_garages'] = 'qbx',
        ['qb-garages'] = 'qb',
        ['qb-garages2'] = 'qb',
        ['esx_garage'] = 'esx',
        ['esx_advancedgarage'] = 'esx',
        ['jg'] = 'jg',
        ['jg-advancedgarages'] = 'jg',
        ['jg-advanced-garages'] = 'jg'
    }

    return aliases[provider] or provider
end

local function DetectGarageProvider()
    local cfg = GetGarageConfig()
    local selected = NormalizeGarageProvider(cfg.Provider or 'auto')
    if selected ~= 'auto' then return selected end

    local providers = cfg.Providers or DEFAULT_GARAGE_PROVIDERS
    for _, provider in ipairs({ 'qbx', 'qb', 'esx', 'jg' }) do
        local providerCfg = providers[provider]
        if providerCfg and IsResourceStarted(providerCfg.Resource) then
            return provider
        end
    end

    if cfg.Custom and IsResourceStarted(cfg.Custom.Resource) then
        return 'custom'
    end

    return 'none'
end

local function GetGarageProviderConfig()
    local cfg = GetGarageConfig()
    local provider = DetectGarageProvider()
    if provider == 'disabled' then return provider, nil end
    if provider == 'custom' or provider == 'none' then return provider, cfg.Custom or {} end
    return provider, (cfg.Providers or DEFAULT_GARAGE_PROVIDERS)[provider] or cfg.Custom or {}
end

local function GetVehicleStorage()
    local provider, providerCfg = GetGarageProviderConfig()
    providerCfg = providerCfg or {}

    local framework = Bridge.GetFramework()
    return {
        provider = provider,
        tableName = providerCfg.VehicleTable or ((framework == 'esx') and 'owned_vehicles' or 'player_vehicles'),
        ownerColumn = providerCfg.OwnerColumn or ((framework == 'esx') and 'owner' or 'citizenid')
    }
end

local function ColumnExists(tableName, columnName)
    local ok, exists = pcall(function()
        return MySQL.Sync.fetchScalar([[
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
        ]], { tableName, columnName })
    end)

    return ok and tonumber(exists) and tonumber(exists) > 0
end

local function QuoteIdentifier(identifier)
    identifier = tostring(identifier or '')
    if not identifier:match('^[%w_]+$') then
        error(('ERR_DB_IDENTIFIER - Unsafe garage SQL identifier requested: %s'):format(identifier))
    end

    return ('`%s`'):format(identifier)
end

local function RestoreOutVehiclesOnStart()
    local cfg = GetGarageConfig()
    if cfg.RestoreOutVehiclesOnStart ~= true then return end

    local storage = GetVehicleStorage()
    local stateColumn = cfg.StateColumn or 'state'
    if not ColumnExists(storage.tableName, stateColumn) then
        if Config.DebugMode then
            print(('[ParTay Keys Debug] Garage restart recovery skipped: %s.%s does not exist.'):format(storage.tableName, stateColumn))
        end
        return
    end

    local outValue = cfg.OutStateValue
    if outValue == nil then outValue = 0 end
    local storedValue = cfg.StoredStateValue
    if storedValue == nil then storedValue = 1 end

    MySQL.Async.execute(('UPDATE %s SET %s = ? WHERE %s = ?'):format(
        QuoteIdentifier(storage.tableName),
        QuoteIdentifier(stateColumn),
        QuoteIdentifier(stateColumn)
    ), { storedValue, outValue }, function(affected)
        if Config.DebugMode then
            print(('[ParTay Keys Debug] Garage restart recovery restored %s out vehicle(s) in %s.'):format(tostring(affected or 0), storage.tableName))
        end
        if tonumber(affected) and tonumber(affected) > 0 then
            exports.partay_keys:SendAuditLog('Garage Restart Recovery', ('Restored %s out vehicle(s) to stored state in %s.'):format(affected, storage.tableName), 'info')
        end
    end)
end

local function GetVehicleRecord(plate)
    local storage = GetVehicleStorage()
    plate = TrimPlate(plate)
    if not plate or plate == '' then return nil, storage end

    local alarmTierSelect = ColumnExists(storage.tableName, 'alarm_tier') and ', alarm_tier' or ''
    local gpsTierSelect = ColumnExists(storage.tableName, 'gps_tier') and ', gps_tier' or ''
    local rows = MySQL.Sync.fetchAll(('SELECT %s, possession_id, has_alarm%s, has_tracker%s, tracker_owner_id FROM %s WHERE plate = ? LIMIT 1'):format(
        QuoteIdentifier(storage.ownerColumn),
        alarmTierSelect,
        gpsTierSelect,
        QuoteIdentifier(storage.tableName)
    ), {plate})
    return rows and rows[1] or nil, storage
end

local function GetTrackerCount(plate)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return 0 end

    local count = MySQL.Sync.fetchScalar('SELECT COUNT(*) FROM partay_vehicle_trackers WHERE plate = ?', { plate })
    return tonumber(count) or 0
end

local function ExtractVehicleAndPlate(vehicleOrNetId, plate)
    if type(vehicleOrNetId) == 'table' then
        local data = vehicleOrNetId
        plate = plate or data.plate or data.vehiclePlate or data.vehicle_plate or data.registration
        vehicleOrNetId = data.vehicle or data.veh or data.entity or data.netId or data.netid or data.networkId or data.networkid

        if not plate and type(data.props) == 'table' then
            plate = data.props.plate
        end

        if not plate and type(data.vehicleProps) == 'table' then
            plate = data.vehicleProps.plate
        end
    end

    local vehicle = tonumber(vehicleOrNetId) or 0
    if vehicle > 0 and not DoesEntityExist(vehicle) then
        local fromNetId = NetworkGetEntityFromNetworkId(vehicle)
        if fromNetId and fromNetId ~= 0 then
            vehicle = fromNetId
        end
    end

    if vehicle > 0 and DoesEntityExist(vehicle) then
        plate = plate or GetVehicleNumberPlateText(vehicle)
    end

    return vehicle, TrimPlate(plate)
end

function Bridge.SyncSpawnedVehicleState(vehicle, plate)
    if not vehicle or vehicle == 0 then return false, 'invalid_entity' end
    plate = TrimPlate(plate or GetVehicleNumberPlateText(vehicle))
    if not plate or plate == '' then return false, 'invalid_plate' end

    local record, storage = GetVehicleRecord(plate)
    if not record then return false, 'not_registered' end

    local possessionId = record.possession_id
    local ownerId = record[storage.ownerColumn]
    local isStolen = possessionId ~= nil and possessionId ~= '' and possessionId ~= ownerId

    Entity(vehicle).state:set('possession_id', possessionId or ownerId, true)
    Entity(vehicle).state:set('isStolen', isStolen, true)
    Entity(vehicle).state:set('original_owner_id', ownerId, true)
    Entity(vehicle).state:set('hasAlarm', tonumber(record.has_alarm) == 1, true)
    Entity(vehicle).state:set('alarmTier', record.alarm_tier or nil, true)
    local trackerCount = GetTrackerCount(plate)
    Entity(vehicle).state:set('hasTracker', trackerCount > 0 or tonumber(record.has_tracker) == 1, true)
    Entity(vehicle).state:set('gpsTier', record.gps_tier or nil, true)
    Entity(vehicle).state:set('tracker_owner_id', record.tracker_owner_id, true)

    return true, isStolen and 'stolen' or 'registered'
end

function Bridge.CanRetrieveVehicle(src, plate)
    if not src or not plate or plate == '' then return false, 'invalid' end

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then return false, 'no_identifier' end

    local vehicle, storage = GetVehicleRecord(plate)

    if not vehicle then return false, 'not_registered' end
    if vehicle.possession_id and vehicle.possession_id ~= '' and vehicle.possession_id ~= vehicle[storage.ownerColumn] then
        if vehicle.possession_id == citizenId then
            return true, 'possessor'
        end
        return false, 'stolen'
    end

    if vehicle[storage.ownerColumn] == citizenId then
        return true, 'owner'
    end

    return false, 'not_owner'
end

function Bridge.CanParkVehicle(src, plate)
    local canRetrieve, reason = Bridge.CanRetrieveVehicle(src, plate)
    if canRetrieve then return true, reason end
    return false, reason
end

function Bridge.NotifyGarageBlocked(src, reason, context)
    local cfg = GetGarageConfig()
    context = context or 'manual'

    if context == 'park' then
        if cfg.NotifyOnBlockedPark == false then return end
    elseif context == 'retrieve' then
        if cfg.NotifyOnBlockedRetrieve == false then return end
    elseif cfg.NotifyOnBlockedRetrieve == false and cfg.NotifyOnBlockedPark == false then
        return
    end

    local messages = {
        stolen = context == 'park'
            and 'This vehicle is stolen or held by another possessor. Recover it through a locksmith before storing it.'
            or 'This vehicle is stolen or held by another possessor. Recover it through a locksmith before taking it out.',
        not_owner = 'You are not registered to this vehicle.',
        not_registered = 'This vehicle is not registered.',
        no_identifier = 'Unable to verify your character identity.',
        invalid = 'Invalid vehicle record.'
    }
    local duration = reason == 'stolen' and 7500 or nil
    local notifyKey = ('%s:%s:%s'):format(tostring(src), tostring(context), tostring(reason))
    local now = GetGameTimer()
    if garageNotifyCooldown[notifyKey] and now - garageNotifyCooldown[notifyKey] < 2000 then return end
    garageNotifyCooldown[notifyKey] = now

    local fallback = context == 'park' and 'This vehicle cannot be stored.' or 'This vehicle cannot be retrieved.'
    Notify(src, context == 'park' and 'Storage Blocked' or 'Retrieval Blocked', messages[reason] or fallback, 'error', duration)
end

function CanRetrieveVehicle(src, plate)
    return Bridge.CanRetrieveVehicle(src, plate)
end

exports('CanRetrieveVehicle', CanRetrieveVehicle)

function CanParkVehicle(src, plate)
    return Bridge.CanParkVehicle(src, plate)
end

exports('CanParkVehicle', CanParkVehicle)

function AssertCanRetrieveVehicle(src, plate)
    local allowed, reason = Bridge.CanRetrieveVehicle(src, plate)
    if not allowed then Bridge.NotifyGarageBlocked(src, reason, 'retrieve') end
    return allowed, reason
end

exports('AssertCanRetrieveVehicle', AssertCanRetrieveVehicle)

function AssertCanParkVehicle(src, plate)
    local allowed, reason = Bridge.CanParkVehicle(src, plate)
    if not allowed then Bridge.NotifyGarageBlocked(src, reason, 'park') end
    return allowed, reason
end

exports('AssertCanParkVehicle', AssertCanParkVehicle)

function NotifyGarageBlocked(src, reason, context)
    return Bridge.NotifyGarageBlocked(src, reason, context)
end

exports('NotifyGarageBlocked', NotifyGarageBlocked)

function SyncSpawnedVehicleState(netIdOrEntity, plate)
    local vehicle, resolvedPlate = ExtractVehicleAndPlate(netIdOrEntity, plate)
    return Bridge.SyncSpawnedVehicleState(vehicle, resolvedPlate)
end

exports('SyncSpawnedVehicleState', SyncSpawnedVehicleState)

if lib and lib.callback then
    lib.callback.register('partay_keys:server:CanRetrieveVehicle', function(src, plate)
        return CanRetrieveVehicle(src, plate)
    end)

    lib.callback.register('partay_keys:server:CanParkVehicle', function(src, plate)
        return CanParkVehicle(src, plate)
    end)

    lib.callback.register('partay_keys:server:AssertCanRetrieveVehicle', function(src, plate)
        return AssertCanRetrieveVehicle(src, plate)
    end)

    lib.callback.register('partay_keys:server:AssertCanParkVehicle', function(src, plate)
        return AssertCanParkVehicle(src, plate)
    end)
end

RegisterNetEvent('partay_keys:server:NotifyGarageBlocked', function(reason, context)
    Bridge.NotifyGarageBlocked(source, reason, context)
end)

RegisterNetEvent('partay_keys:server:SyncSpawnedVehicleState', function(netIdOrEntity, plate)
    SyncSpawnedVehicleState(netIdOrEntity, plate)
end)

function GetGarageProvider()
    return DetectGarageProvider()
end

exports('GetGarageProvider', GetGarageProvider)

local registeredSpawnEvents = {}
local function RegisterVehicleSpawnedEvent(eventName)
    if type(eventName) ~= 'string' or eventName == '' or registeredSpawnEvents[eventName] then return end
    registeredSpawnEvents[eventName] = true

    AddEventHandler(eventName, function(vehicleOrNetId, plate)
        SyncSpawnedVehicleState(vehicleOrNetId, plate)
    end)
end

local garageConfig = GetGarageConfig()
local selectedProvider = garageConfig.Provider or 'auto'
if selectedProvider == 'auto' then
    for _, providerCfg in pairs(garageConfig.Providers or DEFAULT_GARAGE_PROVIDERS) do
        for _, eventName in ipairs(providerCfg.VehicleSpawnedEvents or {}) do
            RegisterVehicleSpawnedEvent(eventName)
        end
    end
else
    local _, selectedGarageConfig = GetGarageProviderConfig()
    for _, eventName in ipairs((selectedGarageConfig and selectedGarageConfig.VehicleSpawnedEvents) or {}) do
        RegisterVehicleSpawnedEvent(eventName)
    end
end
for _, eventName in ipairs((GetGarageConfig().Custom and GetGarageConfig().Custom.VehicleSpawnedEvents) or {}) do
    RegisterVehicleSpawnedEvent(eventName)
end

CreateThread(function()
    Wait(1000)
    RestoreOutVehiclesOnStart()
    if Config.DebugMode then
        local provider, providerCfg = GetGarageProviderConfig()
        print(('[ParTay Keys Debug] Garage provider selected: %s'):format(tostring(provider)))
    end
end)
