local installedVehicles = {}
local actionCooldowns = {}
local transmitters = {}
local getPlayerVehicle

local function now()
    return GetGameTimer()
end

local function isCoolingDown(source, key)
    local cooldownKey = ('%s:%s'):format(source, key)
    local expires = actionCooldowns[cooldownKey]

    if expires and expires > now() then
        return true
    end

    actionCooldowns[cooldownKey] = now() + Config.Install.cooldownMs
    return false
end

local function log(message)
    if not Config.Logging.enabled or Config.Logging.webhook == '' then return end

    PerformHttpRequest(Config.Logging.webhook, function() end, 'POST', json.encode({
        username = Config.Item.label,
        embeds = {{
            title = 'Radar Detector',
            description = message,
            color = 3447003
        }}
    }), { ['Content-Type'] = 'application/json' })
end

local function setVehicleState(vehicle, installed)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        Entity(vehicle).state:set('radarDetectorInstalled', installed == true, true)
    end
end

local function getVehicleOccupants(vehicle)
    local occupants = {}

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return occupants
    end

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local targetVehicle = getPlayerVehicle(target)

        if targetVehicle == vehicle then
            occupants[#occupants + 1] = target
        end
    end

    return occupants
end

local function sendToVehicleOccupants(vehicle, eventName, ...)
    for _, target in ipairs(getVehicleOccupants(vehicle)) do
        TriggerClientEvent(eventName, target, ...)
    end
end

local function hasInstalled(plate)
    plate = RadarDetector.TrimPlate(plate)
    return plate and installedVehicles[plate] ~= nil
end

local function upsertInstalled(plate, source, metadata)
    plate = RadarDetector.TrimPlate(plate)
    if not plate then return false end

    installedVehicles[plate] = {
        plate = plate,
        installer = Bridge.GetIdentifier(source),
        metadata = metadata or {},
        installedAt = os.time()
    }

    if Config.Persistence.enabled then
        MySQL.insert.await(('INSERT INTO %s (plate, installer, metadata) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE installer = VALUES(installer), metadata = VALUES(metadata), installed_at = CURRENT_TIMESTAMP'):format(Config.Persistence.tableName), {
            plate,
            installedVehicles[plate].installer,
            json.encode(metadata or {})
        })
    end

    return true
end

local function removeInstalled(plate)
    plate = RadarDetector.TrimPlate(plate)
    if not plate then return false end

    installedVehicles[plate] = nil

    if Config.Persistence.enabled then
        MySQL.update.await(('DELETE FROM %s WHERE plate = ?'):format(Config.Persistence.tableName), { plate })
    end

    return true
end

local function loadInstalled()
    if not Config.Persistence.enabled then return end

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS %s (
            plate VARCHAR(16) NOT NULL PRIMARY KEY,
            installer VARCHAR(80) NULL,
            metadata LONGTEXT NULL,
            installed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    ]]):format(Config.Persistence.tableName))

    local rows = MySQL.query.await(('SELECT plate, installer, metadata, UNIX_TIMESTAMP(installed_at) AS installedAt FROM %s'):format(Config.Persistence.tableName))

    for _, row in ipairs(rows or {}) do
        local metadata = {}
        if row.metadata and row.metadata ~= '' then
            local ok, decoded = pcall(json.decode, row.metadata)
            metadata = ok and decoded or {}
        end

        installedVehicles[RadarDetector.TrimPlate(row.plate)] = {
            plate = RadarDetector.TrimPlate(row.plate),
            installer = row.installer,
            metadata = metadata,
            installedAt = row.installedAt
        }
    end
end

getPlayerVehicle = function(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return 0 end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return 0 end

    return vehicle, ped
end

local function isVehicleClassAllowed(source)
    local hasAllowedList = Config.Install.allowedVehicleClasses and #Config.Install.allowedVehicleClasses > 0
    local hasBlockedList = Config.Install.blockedVehicleClasses and #Config.Install.blockedVehicleClasses > 0

    if not hasAllowedList and not hasBlockedList then
        return true
    end

    local ok, vehicleClass = pcall(function()
        return lib.callback.await('RadarDetector:client:getVehicleClass', source)
    end)

    if not ok or vehicleClass == nil then
        return false
    end

    if hasAllowedList and not RadarDetector.TableContains(Config.Install.allowedVehicleClasses, vehicleClass) then
        return false
    end

    if hasBlockedList and RadarDetector.TableContains(Config.Install.blockedVehicleClasses, vehicleClass) then
        return false
    end

    return true
end

local function validateInstallSource(source)
    local vehicle, ped = getPlayerVehicle(source)
    if vehicle == 0 then
        return false, 'install_no_vehicle'
    end

    if Config.Install.requireDriverSeat and GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return false, 'install_not_driver'
    end

    if not isVehicleClassAllowed(source) then
        return false, 'install_blocked_vehicle'
    end

    local plate = RadarDetector.TrimPlate(GetVehicleNumberPlateText(vehicle))
    if not plate then
        return false, 'install_no_vehicle'
    end

    if hasInstalled(plate) then
        return false, 'install_already'
    end

    return true, nil, vehicle, plate
end

local function buildMetadata(itemMetadata)
    local metadata = {}

    for key, value in pairs(Config.Item.metadata or {}) do
        metadata[key] = value
    end

    for key, value in pairs(itemMetadata or {}) do
        metadata[key] = value
    end

    metadata.serial = metadata.serial or ('%s-%06d'):format(Config.Item.metadata.serialPrefix or 'RD', math.random(0, 999999))
    metadata.installedAt = os.time()

    return metadata
end

local function returnDetectorItem(source, metadata)
    if not Config.Item.returnOnRemove then return true end

    local ok = exports.ox_inventory:AddItem(source, Config.Item.name, 1, metadata or Config.Item.metadata)
    return ok == true
end

CreateThread(loadInstalled)

exports(Config.Item.name, function(event, item, inventory, slot)
    local source = inventory.id

    if event == 'usingItem' then
        if isCoolingDown(source, 'install') then
            Bridge.Notify(source, RadarDetector.Locale('blocked_spam'), 'error')
            return false
        end

        local valid, reason = validateInstallSource(source)
        if not valid then
            Bridge.Notify(source, RadarDetector.Locale(reason), 'error')
            return false
        end

        Bridge.Notify(source, RadarDetector.Locale('install_started'), 'inform')
        return true
    end

    if event == 'usedItem' then
        local valid, reason, vehicle, plate = validateInstallSource(source)
        if not valid then
            Bridge.Notify(source, RadarDetector.Locale(reason), 'error')
            return false
        end

        local metadata = buildMetadata(item and item.metadata or {})
        upsertInstalled(plate, source, metadata)
        setVehicleState(vehicle, true)

        sendToVehicleOccupants(vehicle, 'RadarDetector:client:installed', plate, metadata)
        Bridge.Notify(source, RadarDetector.Locale('install_success', Config.Command), 'success')

        if Config.Logging.logInstalls then
            log(('%s installed a detector in plate %s'):format(GetPlayerName(source), plate))
        end

        return true
    end
end)

RegisterNetEvent('RadarDetector:server:checkVehicle', function(netId)
    local source = source
    local vehicle = NetworkGetEntityFromNetworkId(netId or 0)
    local playerVehicle = getPlayerVehicle(source)

    if vehicle == 0 or vehicle ~= playerVehicle then
        TriggerClientEvent('RadarDetector:client:vehicleStatus', source, false)
        return
    end

    local plate = RadarDetector.TrimPlate(GetVehicleNumberPlateText(vehicle))

    if not plate then
        TriggerClientEvent('RadarDetector:client:vehicleStatus', source, false)
        return
    end

    local installed = hasInstalled(plate)
    if installed then setVehicleState(vehicle, true) end

    TriggerClientEvent('RadarDetector:client:vehicleStatus', source, installed, installedVehicles[plate])
end)

RegisterNetEvent('RadarDetector:server:remove', function()
    local source = source
    if isCoolingDown(source, 'remove') then
        Bridge.Notify(source, RadarDetector.Locale('blocked_spam'), 'error')
        return
    end

    local vehicle, ped = getPlayerVehicle(source)
    if vehicle == 0 then
        Bridge.Notify(source, RadarDetector.Locale('install_no_vehicle'), 'error')
        return
    end

    if Config.Install.requireDriverSeat and GetPedInVehicleSeat(vehicle, -1) ~= ped then
        Bridge.Notify(source, RadarDetector.Locale('remove_not_driver'), 'error')
        return
    end

    local plate = RadarDetector.TrimPlate(GetVehicleNumberPlateText(vehicle))
    if not hasInstalled(plate) then
        Bridge.Notify(source, RadarDetector.Locale('remove_none'), 'error')
        return
    end

    local metadata = installedVehicles[plate] and installedVehicles[plate].metadata or Config.Item.metadata
    removeInstalled(plate)
    setVehicleState(vehicle, false)
    returnDetectorItem(source, metadata)

    sendToVehicleOccupants(vehicle, 'RadarDetector:client:removed', plate)
    Bridge.Notify(source, RadarDetector.Locale('remove_success'), 'success')

    if Config.Logging.logRemovals then
        log(('%s removed a detector from plate %s'):format(GetPlayerName(source), plate))
    end
end)

RegisterNetEvent(Config.Radars.wk_wars2x.eventName, function(status)
    local source = source
    local radarConfig = Config.Radars.wk_wars2x
    if not radarConfig.enabled then return end

    if status ~= true then
        transmitters[source] = nil
        return
    end

    local vehicle = getPlayerVehicle(source)
    if radarConfig.requireVehicle and vehicle == 0 then
        transmitters[source] = nil
        return
    end

    if not Bridge.HasRadarPermission(source) then
        transmitters[source] = nil
        if Config.Logging.logBlockedAttempts then
            log(RadarDetector.Locale('radar_blocked', GetPlayerName(source)))
        end
        return
    end

    transmitters[source] = {
        vehicle = vehicle
    }
end)

AddEventHandler('playerDropped', function()
    transmitters[source] = nil
end)

CreateThread(function()
    while true do
        Wait(1000)

        local active = {}
        for source, data in pairs(transmitters) do
            local vehicle = data.vehicle
            local currentVehicle = getPlayerVehicle(source)

            if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or currentVehicle ~= vehicle then
                transmitters[source] = nil
            else
                active[#active + 1] = {
                    source = source,
                    coords = GetEntityCoords(vehicle)
                }
            end
        end

        if #active == 0 then
            TriggerClientEvent('RadarDetector:client:radarAlert', -1, { active = false })
            goto continue
        end

        for _, playerId in ipairs(GetPlayers()) do
            local target = tonumber(playerId)
            local vehicle = getPlayerVehicle(target)

            if vehicle ~= 0 then
                local plate = RadarDetector.TrimPlate(GetVehicleNumberPlateText(vehicle))
                if hasInstalled(plate) then
                    local targetCoords = GetEntityCoords(vehicle)
                    local nearest

                    for _, transmitter in ipairs(active) do
                        if transmitter.source ~= target then
                            local distance = #(targetCoords - transmitter.coords)
                            if distance <= Config.Detector.range and (not nearest or distance < nearest.distance) then
                                nearest = { distance = distance }
                            end
                        end
                    end

                    if nearest then
                        local strength = math.max(1, math.min(5, 6 - math.ceil((nearest.distance / Config.Detector.range) * 5)))
                        TriggerClientEvent('RadarDetector:client:radarAlert', target, {
                            active = true,
                            strength = strength,
                            distance = nearest.distance
                        })
                    else
                        TriggerClientEvent('RadarDetector:client:radarAlert', target, { active = false })
                    end
                end
            end
        end

        ::continue::
    end
end)
