-- [[ Automated Admin Interceptor (Server) ]] --

local AdminGiveKeysCooldown = {}

local function IsPlayerAdmin(src)
    if IsPlayerAceAllowed(src, 'command.car') then return true end

    if type(Config.AdminGroup) == 'table' then
        for _, group in ipairs(Config.AdminGroup) do
            if IsPlayerAceAllowed(src, group) then return true end
        end
    else
        if IsPlayerAceAllowed(src, Config.AdminGroup or 'group.admin') then return true end
    end
    return false
end

local function GetPlayerLicense(src)
    return GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifierByType(src, 'license2')
end

local function GetVehicleModelData(veh, plate)
    local hash = GetEntityModel(veh)
    local modelName
    if Bridge.GetFramework() == 'qbx' then
        local ok, vehicleData = pcall(function()
            return exports.qbx_core:GetVehiclesByHash(hash)
        end)
        if ok and type(vehicleData) == 'table' then
            modelName = vehicleData.model
        end
    end

    modelName = modelName or tostring(hash)
    local props = {
        plate = plate,
        model = hash,
        engineHealth = 1000,
        bodyHealth = 1000,
        fuelLevel = 100
    }

    return modelName, hash, json.encode(props)
end

local function GetAdminVehicleKeyMetadata(veh, modelName, hash)
    local metadata = {
        vehicle_model = modelName,
        vehicle_model_hash = hash or (veh and veh ~= 0 and DoesEntityExist(veh) and GetEntityModel(veh) or nil)
    }

    local getVehicleClass = _G.GetVehicleClass
    if veh and veh ~= 0 and DoesEntityExist(veh) and type(getVehicleClass) == 'function' then
        local ok, vehicleClass = pcall(getVehicleClass, veh)
        if ok then
            metadata.vehicle_class = vehicleClass
        end
    end

    return metadata
end

local function GrantTemporaryAdminAccess(src, veh, plate)
    local identifier = Bridge.GetCitizenID(src)
    if not identifier then
        return false, 'Unable to find your character identifier.'
    end

    Entity(veh).state:set('possession_id', identifier, true)
    Entity(veh).state:set('isStolen', false, true)

    return true
end

local function AssignVehicleOwnership(adminSrc, targetSrc, veh, plate)
    targetSrc = tonumber(targetSrc) or adminSrc

    if not GetPlayerName(targetSrc) then
        return false, 'Target player is not online.'
    end

    local identifier = Bridge.GetCitizenID(targetSrc)
    if not identifier then
        return false, 'Unable to find the target character identifier.'
    end

    local storage = GetVehicleStorage()
    local ownerColumn = storage.ownerColumn
    local model, hash, mods = GetVehicleModelData(veh, plate)
    local keyVersion = 1
    local framework = Bridge.GetFramework()
    local selectColumns = (framework == 'esx')
        and ('%s, key_version'):format(storage.ownerSql)
        or ('id, %s, key_version, vehicle, mods'):format(storage.ownerSql)
    local registeredRow = MySQL.Sync.fetchAll(('SELECT %s FROM %s WHERE plate = ? LIMIT 1'):format(selectColumns, storage.tableSql), {plate})
    registeredRow = registeredRow and registeredRow[1]

    if registeredRow then
        local currentOwner = registeredRow[ownerColumn]
        if targetSrc == adminSrc and currentOwner and currentOwner ~= identifier then
            return false, 'This vehicle is already player owned. You cannot give yourself keys to it.'
        end

        keyVersion = tonumber(registeredRow.key_version) or 1
        MySQL.Sync.execute(('UPDATE %s SET %s = ?, possession_id = ? WHERE plate = ?'):format(storage.tableSql, storage.ownerSql), {identifier, identifier, plate})
        if framework ~= 'esx' then
            MySQL.Sync.execute(('UPDATE %s SET state = ? WHERE plate = ?'):format(storage.tableSql), {0, plate})
            if not registeredRow.mods or registeredRow.mods == '' or registeredRow.mods == '{}' then
                MySQL.Sync.execute(('UPDATE %s SET vehicle = ?, hash = ?, mods = ? WHERE plate = ?'):format(storage.tableSql), {model, hash, mods, plate})
            end
        end
    elseif framework == 'esx' then
        MySQL.Sync.execute('INSERT IGNORE INTO owned_vehicles (owner, plate, vehicle, possession_id, key_version) VALUES (?, ?, ?, ?, ?)', {
            identifier,
            plate,
            model,
            identifier,
            keyVersion
        })
    else
        MySQL.Sync.execute('INSERT IGNORE INTO player_vehicles (license, citizenid, plate, vehicle, hash, mods, state, possession_id, key_version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            GetPlayerLicense(targetSrc),
            identifier,
            plate,
            model,
            hash,
            mods,
            0,
            identifier,
            keyVersion
        })
    end

    if framework ~= 'esx' then
        local vehicleId = MySQL.Sync.fetchScalar(('SELECT id FROM %s WHERE plate = ? LIMIT 1'):format(storage.tableSql), {plate})
        if vehicleId then
            Entity(veh).state:set('vehicleid', tonumber(vehicleId), false)
        end
    end

    Entity(veh).state:set('possession_id', identifier, true)
    Entity(veh).state:set('isStolen', false, true)

    if Config.RequirePhysicalKey then
        Bridge.GiveVehicleKey(targetSrc, plate, model, keyVersion, identifier, GetAdminVehicleKeyMetadata(veh, model, hash))
    end

    return true, registeredRow and 'transferred' or 'registered', targetSrc
end

RegisterNetEvent('partay_keys:server:RequestAdminSpawnAccess', function(netId, explicitSource)
    local src = tonumber(explicitSource) or source
    if not IsPlayerAdmin(src) then return end

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return end

    local plate = TrimPlate(GetVehicleNumberPlateText(veh))
    if not plate or plate == '' then return end

    local storage = GetVehicleStorage()
    Wait(2500)

    if not DoesEntityExist(veh) then return end
    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then return end

    local isRegistered = MySQL.Sync.fetchScalar(('SELECT plate FROM %s WHERE plate = ? LIMIT 1'):format(storage.tableSql), {plate}) ~= nil
    if isRegistered then return end

    local ok, result = GrantTemporaryAdminAccess(src, veh, plate)
    if not ok then
        Notify(src, 'Admin Access', result or 'Unable to grant temporary access.', 'error')
        return
    end

    exports.partay_keys:SendAuditLog('Admin Temporary Access', ('Admin %s received temporary access for plate [%s]'):format(GetPlayerName(src), plate), 'info')
    Notify(src, 'Admin Override', ('Temporary vehicle access granted. Use /%s [id] to assign ownership.'):format(Config.AdminGiveKeysCommand or 'givekeys'), 'success')
end)

RegisterNetEvent('partay_keys:server:RequestAdminGiveKeys', function(netId, plate, targetId)
    local src = source
    if not IsPlayerAdmin(src) then
        Notify(src, 'Give Keys', 'You do not have permission to use this command.', 'error')
        return
    end

    local now = os.time()
    local cooldown = Config.AdminGiveKeysCooldown or 30
    if AdminGiveKeysCooldown[src] and now < AdminGiveKeysCooldown[src] + cooldown then
        local remaining = (AdminGiveKeysCooldown[src] + cooldown) - now
        Notify(src, 'Give Keys Cooldown', ('Please wait %s seconds before using /%s again.'):format(remaining, Config.AdminGiveKeysCommand or 'givekeys'), 'error')
        return
    end

    if not netId or not plate then
        Notify(src, 'Give Keys', 'Unable to identify this vehicle.', 'error')
        return
    end

    plate = TrimPlate(plate)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then
        Notify(src, 'Give Keys', 'Unable to find this networked vehicle.', 'error')
        return
    end

    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then
        Notify(src, 'Give Keys', 'Vehicle plate changed before keys could be granted.', 'error')
        return
    end

    local ok, result, targetSrc = AssignVehicleOwnership(src, targetId, veh, plate)
    if not ok then
        Notify(src, 'Give Keys', result or 'Unable to grant access.', 'error')
        return
    end

    AdminGiveKeysCooldown[src] = now
    exports.partay_keys:SendAuditLog('Admin GiveKeys', ('Admin %s assigned vehicle [%s] ownership to %s'):format(GetPlayerName(src), plate, GetPlayerName(targetSrc)), 'info')

    Notify(src, 'Give Keys', ('Vehicle ownership %s for %s.'):format(result == 'transferred' and 'transferred' or 'registered', GetPlayerName(targetSrc)), 'success')
    if targetSrc ~= src then
        Notify(targetSrc, 'Vehicle Ownership', ('You received ownership of vehicle %s.'):format(plate), 'success')
    end
end)
