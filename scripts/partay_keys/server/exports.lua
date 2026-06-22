-- [[ API Gateway ]] --
if not IsDuplicityVersion() then return end

local function GetVehicleKeyVersionFromDB(plate)
    if not plate or plate == '' then return 1 end
    local storage = GetVehicleStorage()
    local result = MySQL.Sync.fetchScalar(('SELECT key_version FROM %s WHERE plate = ? LIMIT 1'):format(storage.tableSql), {plate})
    return tonumber(result) or 1
end

local FindVehicleByPlate

local function ResolveVehicleAndPlate(vehicleOrPlate)
    if type(vehicleOrPlate) == 'table' then
        local plate = TrimPlate(vehicleOrPlate.plate or vehicleOrPlate[1])
        local vehicle = tonumber(vehicleOrPlate.vehicle or vehicleOrPlate.entity or vehicleOrPlate.netId or vehicleOrPlate[2]) or 0

        if vehicle > 0 and not DoesEntityExist(vehicle) then
            local fromNetId = NetworkGetEntityFromNetworkId(vehicle)
            if fromNetId and fromNetId ~= 0 then
                vehicle = fromNetId
            end
        end

        if (vehicle == 0 or not DoesEntityExist(vehicle)) and plate then
            vehicle = FindVehicleByPlate(plate)
        end

        return vehicle, plate
    end

    if type(vehicleOrPlate) == 'string' then
        return 0, TrimPlate(vehicleOrPlate)
    end

    local vehicle = tonumber(vehicleOrPlate) or 0
    if vehicle > 0 and not DoesEntityExist(vehicle) then
        local fromNetId = NetworkGetEntityFromNetworkId(vehicle)
        if fromNetId and fromNetId ~= 0 then
            vehicle = fromNetId
        end
    end

    if vehicle > 0 and DoesEntityExist(vehicle) then
        return vehicle, TrimPlate(GetVehicleNumberPlateText(vehicle))
    end

    return 0, nil
end

function FindVehicleByPlate(plate)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return 0 end

    for _, vehicle in ipairs(GetAllVehicles()) do
        if TrimPlate(GetVehicleNumberPlateText(vehicle)) == plate then
            return vehicle
        end
    end

    return 0
end

local GrantTemporaryVehicleAccess

local function GetPlayerDistanceToEntity(src, entity)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not entity or entity == 0 then return 999999.0 end
    return #(GetEntityCoords(ped) - GetEntityCoords(entity))
end

local function AuditCompatibility(title, message, logType)
    if Config.Compatibility and Config.Compatibility.AuditLegacyEvents == false then return end
    exports.partay_keys:SendAuditLog(title, message, logType or 'info')
end

local function CanUseLegacyKeyEvent(src, plate, eventName)
    if not Config.Compatibility or Config.Compatibility.EnableLegacyKeyEvents ~= true then
        AuditCompatibility('ERR_LEGACY_KEY_EVENT_DISABLED', ('Blocked %s for source %s plate %s because legacy key events are disabled.'):format(eventName, tostring(src), tostring(plate)), 'warning')
        return false
    end

    if not src or src == 0 or not GetPlayerName(src) then
        AuditCompatibility('ERR_LEGACY_KEY_EVENT_SOURCE', ('Blocked %s for invalid source %s plate %s.'):format(eventName, tostring(src), tostring(plate)), 'warning')
        return false
    end

    plate = TrimPlate(plate)
    if not plate or plate == '' then
        AuditCompatibility('ERR_LEGACY_KEY_EVENT_PLATE', ('Blocked %s for source %s because plate was missing.'):format(eventName, tostring(src)), 'warning')
        return false
    end

    if Config.Compatibility.RequireLegacyVehicleNearby ~= false then
        local vehicle = FindVehicleByPlate(plate)
        local maxDistance = tonumber(Config.Compatibility.LegacyVehicleMaxDistance) or 15.0
        if vehicle == 0 or GetPlayerDistanceToEntity(src, vehicle) > maxDistance then
            AuditCompatibility('ERR_LEGACY_KEY_EVENT_DISTANCE', ('Blocked %s for source %s plate %s because the vehicle was not nearby.'):format(eventName, src, plate), 'warning')
            return false
        end
    end

    AuditCompatibility('Legacy Key Event', ('Allowed %s for source %s plate %s.'):format(eventName, src, plate), 'info')
    return true
end

local function HandleLegacyKeyEvent(eventName, requestedTarget, plate)
    local src = source
    local target = src

    if requestedTarget and Config.Compatibility and Config.Compatibility.AllowLegacyTargetedKeyGrant == true then
        target = tonumber(requestedTarget) or src
    end

    plate = TrimPlate(plate or requestedTarget)
    if not CanUseLegacyKeyEvent(src, plate, eventName) then return false end
    if target ~= src and not GetPlayerName(target) then return false end

    return GrantTemporaryVehicleAccess(target, plate)
end

local function SetLiveVehicleAccess(vehicle, citizenId)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        Entity(vehicle).state:set('possession_id', citizenId, true)
        Entity(vehicle).state:set('isStolen', false, true)
    end
end

local ResolveGrantVehicleModel

function GrantTemporaryVehicleAccess(source, vehicleOrPlate)
    local vehicle, plate = ResolveVehicleAndPlate(vehicleOrPlate)
    if vehicle == 0 and plate then
        vehicle = FindVehicleByPlate(plate)
    end

    if not source or not plate or plate == '' then return false end

    local citizenId = Bridge.GetCitizenID(source)
    if not citizenId then return false end

    SetLiveVehicleAccess(vehicle, citizenId)

    return true
end

local function GetClientVehicleKeyMetadata(source, vehicle, plate)
    if not source or not lib or not lib.callback then return nil end

    local netId = 0
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local getNetId = _G.NetworkGetNetworkIdFromEntity
        if type(getNetId) == 'function' then
            local ok, result = pcall(getNetId, vehicle)
            if ok then netId = tonumber(result) or 0 end
        end
    end

    local ok, clientMetadata = pcall(function()
        return lib.callback.await('partay_keys:client:GetVehicleKeyMetadata', source, netId, plate)
    end)

    return ok and type(clientMetadata) == 'table' and clientMetadata or nil
end

local function GetVehicleKeyMetadata(source, vehicle, plate)
    local metadata = {}

    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        metadata.vehicle_model_hash = GetEntityModel(vehicle)
        metadata.vehicle_model = ResolveGrantVehicleModel(vehicle)

        local getVehicleClass = _G.GetVehicleClass
        if type(getVehicleClass) == 'function' then
            local ok, vehicleClass = pcall(getVehicleClass, vehicle)
            if ok then
                metadata.vehicle_class = vehicleClass
            end
        end
    end

    if not metadata.vehicle_class then
        local clientMetadata = GetClientVehicleKeyMetadata(source, vehicle, plate)
        if clientMetadata then
            metadata.vehicle_class = metadata.vehicle_class or clientMetadata.vehicle_class
            metadata.vehicle_model_hash = metadata.vehicle_model_hash or clientMetadata.vehicle_model_hash
        end
    end

    return next(metadata) and metadata or nil
end

function ResolveGrantVehicleModel(vehicle, fallbackModel)
    if fallbackModel and fallbackModel ~= '' and fallbackModel ~= 'Unknown' then
        return fallbackModel
    end

    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local hash = GetEntityModel(vehicle)
        if Bridge.GetFramework() == 'qbx' then
            local ok, vehicleData = pcall(function()
                return exports.qbx_core:GetVehiclesByHash(hash)
            end)
            if ok and type(vehicleData) == 'table' then
                return vehicleData.model or vehicleData.name or vehicleData.label or tostring(hash)
            end
        end

        if QBCore and QBCore.Shared and QBCore.Shared.Vehicles then
            for modelName, vehicleData in pairs(QBCore.Shared.Vehicles) do
                if type(vehicleData) == 'table' and tonumber(vehicleData.hash) == hash then
                    return vehicleData.model or modelName
                end
            end
        end

        return tostring(hash)
    end

    return fallbackModel or 'Unknown'
end

local function GivePhysicalKeyWhenRegistered(source, plate, model)
    plate = TrimPlate(plate)
    if not source or not plate or plate == '' or not Config.RequirePhysicalKey then return end

    CreateThread(function()
        local citizenId = Bridge.GetCitizenID(source)
        if not citizenId then return end

        local storage = GetVehicleStorage()
        local ownerColumn = storage.ownerColumn

        for _ = 1, 20 do
            local row = MySQL.Sync.fetchAll(('SELECT %s, possession_id, key_version, vehicle FROM %s WHERE plate = ? LIMIT 1'):format(storage.ownerSql, storage.tableSql), {plate})
            row = row and row[1]

            if row and row[ownerColumn] == citizenId then
                local keyVersion = tonumber(row.key_version) or 1
                local vehicle = FindVehicleByPlate(plate)
                local vehicleModel = ResolveGrantVehicleModel(vehicle, model or row.vehicle)
                if Config.DebugMode then
                    print(('[ParTay Keys Debug] GiveKeys delayed row found plate=%s model=%s keyVersion=%s possession=%s'):format(
                        tostring(plate),
                        tostring(vehicleModel),
                        tostring(keyVersion),
                        tostring(row.possession_id)
                    ))
                end
                Bridge.GiveVehicleKey(source, plate, vehicleModel, keyVersion, citizenId, GetVehicleKeyMetadata(source, vehicle, plate))
                SetLiveVehicleAccess(vehicle, citizenId)
                Notify(source, 'Vehicle Purchase', 'Your vehicle key has been added to your inventory.', 'success')
                return
            elseif Config.DebugMode and row then
                print(('[ParTay Keys Debug] GiveKeys delayed row owner mismatch plate=%s rowOwner=%s expected=%s'):format(
                    tostring(plate),
                    tostring(row[ownerColumn]),
                    tostring(citizenId)
                ))
            end

            Wait(500)
        end

        if Config.DebugMode then
            print(('[ParTay Keys Debug] ERR_GIVEKEYS_REGISTRATION_TIMEOUT - GiveKeys retry expired before vehicle row was registered for plate %s.'):format(plate))
        end
    end)
end

local function GrantVehicleAccess(source, vehicleOrPlate, model)
    local vehicle, plate = ResolveVehicleAndPlate(vehicleOrPlate)
    if not source or not plate or plate == '' then return false end

    local citizenId = Bridge.GetCitizenID(source)
    if not citizenId then return false end

    local storage = GetVehicleStorage()
    local ownerColumn = storage.ownerColumn
    local keyVersion = GetVehicleKeyVersionFromDB(plate)
    local vehicleModel = ResolveGrantVehicleModel(vehicle, model)
    local existingOwner = MySQL.Sync.fetchScalar(('SELECT %s FROM %s WHERE plate = ? LIMIT 1'):format(storage.ownerSql, storage.tableSql), {plate})

    if Config.DebugMode then
        print(('[ParTay Keys Debug] GiveKeys resolved plate=%s model=%s ownerRow=%s keyVersion=%s vehicleEntity=%s'):format(
            tostring(plate),
            tostring(vehicleModel),
            tostring(existingOwner),
            tostring(keyVersion),
            tostring(vehicle)
        ))
    end

    if existingOwner then
        MySQL.Async.execute(('UPDATE %s SET possession_id = ? WHERE plate = ?'):format(storage.tableSql), {citizenId, plate})
    else
        local granted = GrantTemporaryVehicleAccess(source, vehicleOrPlate)
        GivePhysicalKeyWhenRegistered(source, plate, vehicleModel)
        return granted
    end

    SetLiveVehicleAccess(vehicle, citizenId)

    if Config.RequirePhysicalKey then
        Bridge.GiveVehicleKey(source, plate, vehicleModel, keyVersion, citizenId, GetVehicleKeyMetadata(source, vehicle, plate))
    end

    return true
end

local function SetVehicleLockState(vehicleOrNetId, state)
    local vehicle = tonumber(vehicleOrNetId) or 0
    state = tonumber(state) or 1

    if vehicle > 0 and not DoesEntityExist(vehicle) then
        local fromNetId = NetworkGetEntityFromNetworkId(vehicle)
        if fromNetId and fromNetId ~= 0 then
            vehicle = fromNetId
        end
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    Entity(vehicle).state:set('lockState', state, true)
    SetVehicleDoorsLocked(vehicle, state)
    return true
end

local function RegisterVehiclePurchaseInternal(source, plate, model)
    if not source or not plate or plate == '' then return false end

    local citizenId = Bridge.GetCitizenID(source)
    if not citizenId then return false end

    local storage = GetVehicleStorage()
    local ownerColumn = storage.ownerColumn
    local possession_id = citizenId

    local keyVersion = GetVehicleKeyVersionFromDB(plate)
    local existingVehicle = MySQL.Sync.fetchAll(('SELECT %s, possession_id, key_version FROM %s WHERE plate = ? LIMIT 1'):format(storage.ownerSql, storage.tableSql), {plate})
    existingVehicle = existingVehicle and existingVehicle[1]

    if existingVehicle then
        local existingOwner = existingVehicle[ownerColumn]
        local currentPossession = existingVehicle.possession_id
        local canTransfer = existingOwner == citizenId
            or currentPossession == nil
            or currentPossession == ''
            or currentPossession == existingOwner
            or currentPossession == citizenId

        if not canTransfer then
            Notify(source, 'Vehicle Purchase', 'This vehicle is already possessed by another player.', 'error')
            return false
        end

        keyVersion = tonumber(existingVehicle.key_version) or keyVersion
        MySQL.Async.execute(('UPDATE %s SET %s = ?, possession_id = ? WHERE plate = ?'):format(storage.tableSql, storage.ownerSql), {citizenId, possession_id, plate})
        if Config.RequirePhysicalKey then
            Bridge.GiveVehicleKey(source, plate, model or 'Unknown', keyVersion, possession_id, GetVehicleKeyMetadata(source, FindVehicleByPlate(plate), plate))
            Notify(source, 'Vehicle Purchase', 'Your vehicle key has been added to your inventory.', 'success')
        end
    else
        if Config.DebugMode then
            print(('[ParTay Keys Debug] RegisterVehiclePurchaseInternal insert values: framework=%s owner=%s plate=%s model=%s possession_id=%s key_version=%s'):format(
                Bridge.GetFramework(), tostring(citizenId), tostring(plate), tostring(model or 'Unknown'), tostring(possession_id), tostring(keyVersion)
            ))
        end

        if Bridge.GetFramework() == 'esx' then
            MySQL.Async.execute('INSERT INTO owned_vehicles (owner, plate, vehicle, possession_id, key_version) VALUES (?, ?, ?, ?, ?)', {
                citizenId,
                plate,
                model or 'Unknown',
                possession_id,
                keyVersion
            })
        else
            MySQL.Async.execute('INSERT INTO player_vehicles (citizenid, plate, vehicle, possession_id, key_version) VALUES (?, ?, ?, ?, ?)', {
                citizenId,
                plate,
                model or 'Unknown',
                possession_id,
                keyVersion
            })
        end

        if Config.RequirePhysicalKey then
            Bridge.GiveVehicleKey(source, plate, model or 'Unknown', keyVersion, possession_id, GetVehicleKeyMetadata(source, FindVehicleByPlate(plate), plate))
            Notify(source, 'Vehicle Purchase', 'Your new vehicle has been registered and a physical key has been added to your inventory.', 'success')
        end
    end

    SetLiveVehicleAccess(FindVehicleByPlate(plate), citizenId)
    if PartayKeys_RecordVehicleKey then
        PartayKeys_RecordVehicleKey({
            plate = plate,
            owner_id = citizenId,
            owner_name = Bridge.GetCharacterName and Bridge.GetCharacterName(source) or GetPlayerName(source),
            holder_id = citizenId,
            holder_name = Bridge.GetCharacterName and Bridge.GetCharacterName(source) or GetPlayerName(source),
            key_type = 'owner',
            key_version = keyVersion,
            possession_id = possession_id,
            metadata = {
                plate = plate,
                key_version = keyVersion,
                possession_id = possession_id,
                vehicle_label = model or 'Unknown',
                vehicle_model = model or 'Unknown'
            }
        })
    end

    exports.partay_keys:SendAuditLog('Vehicle Purchase', ('Player %s purchased vehicle %s with plate %s'):format(GetPlayerName(source), model or 'Unknown', plate), 'info')
    return true
end

function WipeVehicleData(plate)
    if not plate then return false end
    local storage = GetVehicleStorage()
    
    MySQL.Async.execute(('UPDATE %s SET possession_id = NULL, shared_keys = \'[]\', key_version = 1 WHERE plate = @plate'):format(storage.tableSql), {
        ['@plate'] = plate
    })
    return true
end

exports('WipeVehicleData', WipeVehicleData)

function AdminSpawnVehicle(source, targetPlayer, model)
    if not Config.AdminPermanentSave then return false end

    local citizenId = Bridge.GetCitizenID(targetPlayer)
    if not citizenId then return false end

    local generatedPlate = Bridge.GeneratePlate()
    local fw = Bridge.GetFramework()
    local possession_id = citizenId
    local keyVersion = 1

    if fw == 'esx' then
        MySQL.Async.execute('INSERT INTO owned_vehicles (owner, plate, vehicle, possession_id, key_version) VALUES (?, ?, ?, ?, ?)', {
            citizenId,
            generatedPlate,
            model,
            possession_id,
            keyVersion
        })
    else
        MySQL.Async.execute('INSERT INTO player_vehicles (citizenid, plate, vehicle, possession_id, key_version) VALUES (?, ?, ?, ?, ?)', {
            citizenId,
            generatedPlate,
            model,
            possession_id,
            keyVersion
        })
    end

    if Config.RequirePhysicalKey then
        Bridge.GiveVehicleKey(targetPlayer, generatedPlate, model, keyVersion, possession_id, GetVehicleKeyMetadata(targetPlayer, FindVehicleByPlate(generatedPlate), generatedPlate))
        Notify(targetPlayer, 'Vehicle Spawned', 'Your new vehicle has been registered and a physical key has been added to your inventory.', 'success')
    else
        Notify(targetPlayer, 'Vehicle Spawned', 'Your new vehicle has been registered. Physical keys are disabled on this server.', 'info')
    end

    exports.partay_keys:SendAuditLog('Admin Spawn Vehicle', ('Admin %s spawned %s for player %s with plate %s'):format(GetPlayerName(source), model, GetPlayerName(targetPlayer), generatedPlate), 'info')
    return true
end

exports('AdminSpawnVehicle', AdminSpawnVehicle)

function RegisterVehiclePurchase(source, plate, model)
    return RegisterVehiclePurchaseInternal(source, plate, model)
end

exports('RegisterVehiclePurchase', RegisterVehiclePurchase)

local function NormalizePlayerVehicleArgs(source, vehicleOrPlate, model)
    if type(source) == 'table' then
        return vehicleOrPlate, model
    end

    if type(source) == 'number' or type(source) == 'string' then
        local playerId = tonumber(source)
        if playerId then
            return playerId, vehicleOrPlate, model
        end
    end

    if type(vehicleOrPlate) == 'number' or type(vehicleOrPlate) == 'string' then
        local playerId = tonumber(vehicleOrPlate)
        if playerId and model ~= nil then
            return playerId, model
        end
    end

    return nil, vehicleOrPlate, model
end

local function ResolveGiveKeysArgs(args)
    local src, vehicleOrPlate, model

    local firstArg = tonumber(args[1])
    if firstArg and GetPlayerName(firstArg) then
        src = firstArg

        if type(args[2]) == 'string' and args[2] ~= '' then
            if type(args[3]) == 'number' then
                vehicleOrPlate = {
                    plate = args[2],
                    vehicle = args[3]
                }
            else
                vehicleOrPlate = args[2]
            end

            if type(args[3]) == 'string' then
                model = args[3]
            elseif type(args[4]) == 'string' then
                model = args[4]
            end

            return src, vehicleOrPlate, model
        elseif type(args[2]) == 'number' then
            vehicleOrPlate = args[2]
            if type(args[3]) == 'string' then
                model = args[3]
            end

            return src, vehicleOrPlate, model
        end
    end

    for i = 1, #args do
        local arg = args[i]
        if not src and (type(arg) == 'number' or type(arg) == 'string') then
            local possibleSrc = tonumber(arg)
            if possibleSrc and GetPlayerName(possibleSrc) then
                src = possibleSrc
            end
        elseif not vehicleOrPlate and (type(arg) == 'number' or type(arg) == 'string') then
            vehicleOrPlate = arg
        elseif not model and (type(arg) == 'number' or type(arg) == 'string') then
            model = tostring(arg)
        end
    end

    return src, vehicleOrPlate, model
end

local function FormatGiveKeysArgs(args)
    local formatted = {}
    for i = 1, #args do
        formatted[#formatted + 1] = ('%s=%s:%s'):format(i, type(args[i]), tostring(args[i]))
    end

    return table.concat(formatted, ', ')
end

function GiveKeys(...)
    local args = {...}

    local function runGrant()
        local ok, result = pcall(function()
            local src, vehicleOrPlate, model = ResolveGiveKeysArgs(args)
            src, vehicleOrPlate, model = NormalizePlayerVehicleArgs(src, vehicleOrPlate, model)
            if Config.DebugMode then
                print(('[ParTay Keys Debug] GiveKeys args [%s] -> src=%s vehicleOrPlate=%s model=%s'):format(
                    FormatGiveKeysArgs(args),
                    tostring(src),
                    tostring(vehicleOrPlate),
                    tostring(model)
                ))
            end

            if not src or not vehicleOrPlate then
                if Config.DebugMode then
                    print('^5[ParTay Keys Debug]^3 GiveKeys skipped because source or vehicle/plate was missing.^0')
                end
                return false
            end

            local granted = GrantVehicleAccess(src, vehicleOrPlate, model)
            if Config.DebugMode then
                print(('[ParTay Keys Debug] GiveKeys grant result for source %s vehicleOrPlate %s: %s'):format(
                    tostring(src),
                    tostring(vehicleOrPlate),
                    tostring(granted)
                ))
            end

            return granted
        end)

        if not ok then
            local message = ('GiveKeys export failed: %s'):format(tostring(result))
            print(('^5[ParTay Keys Debug]^1 ERR_GIVEKEYS_EXPORT - %s^0'):format(message))
            if exports and exports.partay_keys and exports.partay_keys.SendAuditLog then
                pcall(function()
                    exports.partay_keys:SendAuditLog('ERR_GIVEKEYS_EXPORT', message, 'error')
                end)
            end
        end
    end

    local createThread = type(CreateThread) == 'function' and CreateThread or Citizen and Citizen.CreateThread
    if type(createThread) == 'function' then
        local ok, result = pcall(createThread, runGrant)
        if not ok then
            print(('^5[ParTay Keys Debug]^1 ERR_GIVEKEYS_THREAD - %s^0'):format(tostring(result)))
            runGrant()
        end
    else
        runGrant()
    end

    return true
end

exports('GiveKeys', GiveKeys)

function RemoveKeys(source, vehicleOrPlate)
    return true
end

exports('RemoveKeys', RemoveKeys)

function SetLockState(vehicleOrNetId, state)
    return SetVehicleLockState(vehicleOrNetId, state)
end

exports('SetLockState', SetLockState)

local function RegisterProvidedExport(resourceName, exportName, handler)
    AddEventHandler(('__cfx_export_%s_%s'):format(resourceName, exportName), function(setCB)
        setCB(handler)
    end)
end

for _, resourceName in ipairs({ 'qbx_vehiclekeys', 'qb-vehiclekeys', 'vehiclekeys', 'esx_vehiclelock', 'esx_vehiclekeys' }) do
    RegisterProvidedExport(resourceName, 'GiveKeys', GiveKeys)
    RegisterProvidedExport(resourceName, 'RemoveKeys', RemoveKeys)
    RegisterProvidedExport(resourceName, 'SetLockState', SetLockState)
end

RegisterNetEvent('partay_keys:server:GiveKeysForPlate', function(plate)
    HandleLegacyKeyEvent('partay_keys:server:GiveKeysForPlate', nil, plate)
end)

RegisterNetEvent('vehiclekeys:server:SetOwner', function(plate)
    HandleLegacyKeyEvent('vehiclekeys:server:SetOwner', nil, plate)
end)

RegisterNetEvent('qbx_vehiclekeys:server:SetOwner', function(plate)
    HandleLegacyKeyEvent('qbx_vehiclekeys:server:SetOwner', nil, plate)
end)

RegisterNetEvent('qbx_vehiclekeys:server:AcquireVehicleKeys', function(plate)
    HandleLegacyKeyEvent('qbx_vehiclekeys:server:AcquireVehicleKeys', nil, plate)
end)

RegisterNetEvent('qbx_vehiclekeys:server:AddKeys', function(plate)
    HandleLegacyKeyEvent('qbx_vehiclekeys:server:AddKeys', nil, plate)
end)

RegisterNetEvent('qbx_vehiclekeys:server:GiveVehicleKeys', function(target, plate)
    HandleLegacyKeyEvent('qbx_vehiclekeys:server:GiveVehicleKeys', target, plate)
end)

RegisterNetEvent('qb-vehiclekeys:server:AcquireVehicleKeys', function(plate)
    HandleLegacyKeyEvent('qb-vehiclekeys:server:AcquireVehicleKeys', nil, plate)
end)

RegisterNetEvent('qb-vehiclekeys:server:AddKeys', function(plate)
    HandleLegacyKeyEvent('qb-vehiclekeys:server:AddKeys', nil, plate)
end)

RegisterNetEvent('qb-vehiclekeys:server:GiveVehicleKeys', function(target, plate)
    HandleLegacyKeyEvent('qb-vehiclekeys:server:GiveVehicleKeys', target, plate)
end)

RegisterNetEvent('vehiclekeys:server:GiveVehicleKeys', function(target, plate)
    HandleLegacyKeyEvent('vehiclekeys:server:GiveVehicleKeys', target, plate)
end)

RegisterNetEvent('esx_vehiclelock:givekey', function(target, plate)
    HandleLegacyKeyEvent('esx_vehiclelock:givekey', target, plate)
end)

RegisterNetEvent('esx_vehiclelock:registerkey', function(plate)
    HandleLegacyKeyEvent('esx_vehiclelock:registerkey', nil, plate)
end)

RegisterNetEvent('esx_vehiclekeys:givekey', function(target, plate)
    HandleLegacyKeyEvent('esx_vehiclekeys:givekey', target, plate)
end)

RegisterNetEvent('esx_vehiclekeys:registerkey', function(plate)
    HandleLegacyKeyEvent('esx_vehiclekeys:registerkey', nil, plate)
end)

AddEventHandler('qb-vehiclekeys:server:setVehLockState', function(vehicleOrNetId, state)
    SetVehicleLockState(vehicleOrNetId, state)
end)

AddEventHandler('qbx_vehiclekeys:server:setVehLockState', function(vehicleOrNetId, state)
    SetVehicleLockState(vehicleOrNetId, state)
end)

AddEventHandler('vehiclekeys:server:setVehLockState', function(vehicleOrNetId, state)
    SetVehicleLockState(vehicleOrNetId, state)
end)

function HasKeys(source, vehicleOrPlate)
    local _, plate = ResolveVehicleAndPlate(vehicleOrPlate)
    if not source or not plate then return false end

    local citizenId = Bridge.GetCitizenID(source)
    if not citizenId then return false end

    local storage = GetVehicleStorage()
    local ownerColumn = storage.ownerColumn
    local rows = MySQL.Sync.fetchAll(('SELECT %s, possession_id FROM %s WHERE plate = ? LIMIT 1'):format(storage.ownerSql, storage.tableSql), {plate})
    local vehicle = rows and rows[1]
    if not vehicle then return false end

    return vehicle[ownerColumn] == citizenId or vehicle.possession_id == citizenId
end

exports('HasKeys', HasKeys)

RegisterNetEvent('partay_keys:server:RegisterVehiclePurchase', function(plate, model)
    local src = source
    if not Config.Compatibility or Config.Compatibility.AllowClientPurchaseRegistration ~= true then
        AuditCompatibility('ERR_CLIENT_PURCHASE_REGISTRATION', ('Blocked client purchase registration from source %s plate %s. Use bridge/export registration instead.'):format(src, tostring(plate)), 'warning')
        return
    end

    RegisterVehiclePurchaseInternal(src, plate, model)
end)

AddEventHandler('partay_keys:server:RegisterVehiclePurchaseFromBridge', function(src, plate, model)
    RegisterVehiclePurchaseInternal(src, plate, model)
end)
