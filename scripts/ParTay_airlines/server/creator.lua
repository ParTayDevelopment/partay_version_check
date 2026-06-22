local function encode(data)
    return json.encode(data or {})
end

local function decode(value, fallback)
    if not value or value == '' then return fallback or {} end
    local ok, data = pcall(json.decode, value)
    if not ok or type(data) ~= 'table' then return fallback or {} end
    return data
end

local function getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function getCitizenId(src)
    local player = getPlayer(src)
    return player and player.PlayerData and player.PlayerData.citizenid
end

local function getJobGrade(player)
    local job = player and player.PlayerData and player.PlayerData.job or {}
    return job.grade and (job.grade.level or job.grade.grade or 0) or 0
end

local function hasAirlineCreatorAccess(src)
    if not Config.Creator.requireAirlineJob then return true end

    local player = getPlayer(src)
    local job = player and player.PlayerData and player.PlayerData.job or {}
    return job.name == Config.JobName and job.onduty ~= false and getJobGrade(player) >= (Config.Creator.minimumGrade or 2)
end

local function hasFrameworkCreatorAccess(src)
    if Config.Creator.acePermission and IsPlayerAceAllowed(src, Config.Creator.acePermission) then return true end

    for _, permission in ipairs(Config.Creator.qbxPermissions or {}) do
        if IsPlayerAceAllowed(src, permission) then return true end
    end

    if GetResourceState('amzn_admin') == 'started' and Config.Creator.amznPermission then
        local ok, allowed = pcall(function()
            return exports.amzn_admin:HasPermission(src, Config.Creator.amznPermission)
        end)
        if ok and allowed then return true end
    end

    return false
end

local function canUseCreator(src)
    return hasAirlineCreatorAccess(src) or hasFrameworkCreatorAccess(src)
end

local function normalizeAirport(airport)
    airport.runways = airport.runways or {}
    airport.gates = airport.gates or {}
    airport.hangars = airport.hangars or {}
    airport.zones = airport.zones or {}
    airport.blip = airport.blip or Config.Creator.defaultBlip
    airport.atc = airport.atc or {}
    airport.airspace = airport.airspace or { enabled = true }
    airport.airspace.enabled = airport.airspace.enabled ~= false
    airport.airspace.altitudeMin = airport.airspace.altitudeMin or 0
    airport.airspace.altitudeMax = airport.airspace.altitudeMax or 1600
    if airport.airspace.controlledZone then
        airport.airspace.controlledZone.minZ = airport.airspace.altitudeMin
        airport.airspace.controlledZone.maxZ = airport.airspace.altitudeMax
    end
    if airport.id == 'downtown' then
        airport.airspace.enabled = false
        airport.hidden = true
    end

    if airport.id == 'lsia' then
        airport.airspace.enabled = true
        airport.atc.coverageRadius = math.max(airport.atc.coverageRadius or 0, 2652)
        airport.airspace.radius = 2652
        airport.airspace.contactRadius = airport.airspace.radius
        airport.airspace.altitudeMax = math.max(airport.airspace.altitudeMax or 0, 1800)
    elseif airport.id == 'sandy' then
        airport.airspace.enabled = true
        airport.atc.coverageRadius = airport.atc.coverageRadius or 1000
        airport.atc.coords = vec4(1702.2449, 3291.2336, 50.6186, 74.2191)
        airport.airspace.radius = 864
        airport.airspace.contactRadius = airport.airspace.radius
        airport.airspace.altitudeMax = math.max(airport.airspace.altitudeMax or 0, 1400)
    elseif airport.id == 'grapeseed' then
        airport.airspace.enabled = true
        airport.atc.coverageRadius = airport.atc.coverageRadius or 1000
        airport.airspace.radius = 450
        airport.airspace.contactRadius = airport.airspace.radius
        airport.airspace.altitudeMax = math.max(airport.airspace.altitudeMax or 0, 1800)
    else
        airport.atc.coverageRadius = airport.atc.coverageRadius or 1200
        airport.airspace.radius = airport.airspace.radius or 2500
        airport.airspace.contactRadius = airport.airspace.radius
    end

    return airport
end

local function defaultAirportData()
    return {
        {
            id = 'lsia',
            label = 'Los Santos International',
            tower = 'LSIA Tower',
            atc = { coords = vec4(-980.4936, -2635.1267, 84.2745, 145.4245), coverageRadius = 2652 },
            airspace = { enabled = true, radius = 2652, altitudeMin = 0, altitudeMax = 1800 },
            blip = Config.Creator.defaultBlip,
            runways = {},
            gates = {},
            hangars = {},
            zones = {},
            restricted = false
        },
        {
            id = 'sandy',
            label = 'Sandy Shores Airfield',
            tower = 'Sandy Tower',
            atc = { coords = vec4(1702.2449, 3291.2336, 50.6186, 74.2191), coverageRadius = 1000 },
            airspace = { enabled = true, radius = 864, altitudeMin = 0, altitudeMax = 1400 },
            blip = Config.Creator.defaultBlip,
            runways = {},
            gates = {},
            hangars = {},
            zones = {},
            restricted = false
        },
        {
            id = 'grapeseed',
            label = 'Grapeseed Airstrip',
            tower = 'Grapeseed Traffic',
            atc = { coords = vec4(2099.8779, 4774.1357, 49.5900, 22.5873), coverageRadius = 1000, type = 'antenna' },
            airspace = { enabled = true, radius = 450, altitudeMin = 0, altitudeMax = 1800 },
            blip = Config.Creator.defaultBlip,
            runways = {},
            gates = {},
            hangars = {},
            zones = {},
            restricted = false
        },
        {
            id = 'zancudo',
            label = 'Fort Zancudo',
            tower = 'Zancudo Tower',
            atc = { coords = vec4(-2356.7454, 3251.4114, 103.7774, 139.1232), coverageRadius = 1600 },
            airspace = { enabled = true, radius = 3000, altitudeMin = 0, altitudeMax = 2200 },
            blip = { enabled = true, sprite = 90, color = 1, scale = 0.85 },
            runways = {},
            gates = {},
            hangars = {},
            zones = {},
            restricted = true,
            restrictedMessage = 'Restricted military airspace. Leave the area immediately.'
        },
        {
            id = 'cayo',
            label = 'Cayo Perico International',
            tower = 'Cayo Tower',
            atc = { coords = vec4(4480.0, -4520.0, 20.0, 0.0), coverageRadius = 1400 },
            airspace = { enabled = true, radius = 2200, altitudeMin = 0, altitudeMax = 1600 },
            blip = Config.Creator.defaultBlip,
            runways = {},
            gates = {},
            hangars = {},
            zones = {},
            restricted = false,
            international = true
        }
    }
end

local function upsertAirport(airport, updatedBy)
    MySQL.insert.await([[
        INSERT INTO partay_airports (id, label, tower, data, updated_by)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label = VALUES(label), tower = VALUES(tower), data = VALUES(data), updated_by = VALUES(updated_by)
    ]], {
        airport.id,
        airport.label or airport.id,
        airport.tower,
        encode(airport),
        updatedBy
    })
end

local function ensureAirportTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `partay_airports` (
            `id` VARCHAR(80) NOT NULL,
            `label` VARCHAR(120) NOT NULL,
            `tower` VARCHAR(120) DEFAULT NULL,
            `data` LONGTEXT NOT NULL,
            `updated_by` VARCHAR(64) DEFAULT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        )
    ]])

    for _, airport in ipairs(defaultAirportData()) do
        local exists = MySQL.scalar.await('SELECT id FROM partay_airports WHERE id = ?', { airport.id })
        if not exists then
            upsertAirport(airport, 'seed')
        end
    end
end

local function getAirports()
    local rows = MySQL.query.await('SELECT id, label, tower, data, updated_at FROM partay_airports ORDER BY label ASC') or {}
    local airports = {}

    for _, row in ipairs(rows) do
        local airport = decode(row.data, {})
        airport.id = airport.id or row.id
        airport.label = airport.label or row.label
        airport.tower = airport.tower or row.tower
        airport.updatedAt = row.updated_at
        normalizeAirport(airport)
        if not airport.hidden then
            airports[#airports + 1] = airport
        end
    end

    return airports
end

local function getAirport(id)
    local row = MySQL.single.await('SELECT id, label, tower, data FROM partay_airports WHERE id = ?', { id })
    if not row then return nil end

    local airport = decode(row.data, {})
    airport.id = airport.id or row.id
    airport.label = airport.label or row.label or airport.id
    airport.tower = airport.tower or row.tower or airport.label
    return normalizeAirport(airport)
end

local function patchAirport(airport, patch)
    if type(patch) ~= 'table' then return false, 'Invalid patch.' end

    local placement = patch.placement or {}

    local function samePointSet(left, right)
        if type(left) ~= 'table' or type(right) ~= 'table' or #left ~= #right then return false end

        for index, point in ipairs(left) do
            local other = right[index]
            if not other then return false end

            local dx = math.abs((point.x or 0.0) - (other.x or 0.0))
            local dy = math.abs((point.y or 0.0) - (other.y or 0.0))
            local dz = math.abs((point.z or 0.0) - (other.z or 0.0))
            if dx > 0.05 or dy > 0.05 or dz > 0.05 then return false end
        end

        return true
    end

    local function runwayForPlacement()
        local index = tonumber(placement.runwayIndex)
        if not index or index < 0 then return nil end

        airport.runways = airport.runways or {}
        airport.runways[index + 1] = airport.runways[index + 1] or {
            label = ('Runway %s'):format(index + 1),
            zones = {}
        }

        return airport.runways[index + 1]
    end

    if patch.action == 'pointPlaced' and patch.target == 'atc' and patch.point then
        airport.atc = airport.atc or {}
        airport.atc.coords = patch.point
        return true
    end

    if patch.action == 'pointPlaced' and patch.target == 'hangar' and patch.point then
        airport.hangars = airport.hangars or {}
        local index = tonumber(placement.index)
        local hangar = {
            label = ('Hangar %s'):format((index and index >= 0 and index + 1) or (#airport.hangars + 1)),
            coords = patch.point
        }

        if index and index >= 0 and airport.hangars[index + 1] then
            airport.hangars[index + 1] = hangar
        else
            airport.hangars[#airport.hangars + 1] = hangar
        end

        return true
    end

    if patch.action == 'zonePlaced' and placement.zoneKey and patch.zone then
        if placement.target == 'runwayZone' then
            local runway = runwayForPlacement()
            if not runway then return false, 'Runway required.' end
            runway.zones = runway.zones or {}
            runway.zones[placement.zoneKey] = patch.zone
            runway[placement.zoneKey] = patch.zone
        else
            airport.zones = airport.zones or {}
            airport.zones[placement.zoneKey] = patch.zone
            airport[placement.zoneKey] = patch.zone
        end
        return true
    end

    if patch.action == 'zoneDeleted' and placement.zoneKey then
        if placement.target == 'runwayZone' then
            local runway = runwayForPlacement()
            if not runway then return false, 'Runway required.' end
            runway.zones = runway.zones or {}
            runway.zones[placement.zoneKey] = nil
            runway[placement.zoneKey] = nil
        else
            airport.zones = airport.zones or {}
            airport.zones[placement.zoneKey] = nil
            airport[placement.zoneKey] = nil
        end
        return true
    end

    if patch.action == 'zoneDeletedAll' and placement.zoneKey then
        airport.zones = airport.zones or {}
        airport.zones[placement.zoneKey] = nil
        airport[placement.zoneKey] = nil

        for _, runway in ipairs(airport.runways or {}) do
            runway.zones = runway.zones or {}
            runway.zones[placement.zoneKey] = nil
            runway[placement.zoneKey] = nil
        end

        return true
    end

    if patch.action == 'polyPlaced' then
        local zone = {
            type = 'poly',
            label = placement.zoneKey or 'Zone',
            points = patch.points or {},
            thickness = Config.ZoneCreator.defaultThickness or 35.0
        }

        if placement.target == 'runway' then
            airport.runways = airport.runways or {}
            local index = tonumber(placement.index)
            if index and index >= 0 and airport.runways[index + 1] then
                airport.runways[index + 1].zone = zone
                airport.runways[index + 1].points = zone.points
            else
                for _, runway in ipairs(airport.runways) do
                    if samePointSet(runway.points or runway.zone and runway.zone.points, zone.points) then
                        runway.zone = zone
                        runway.points = zone.points
                        return true
                    end
                end

                airport.runways[#airport.runways + 1] = {
                    label = ('Runway %s'):format(#airport.runways + 1),
                    zone = zone,
                    points = zone.points
                }
            end
            return true
        end

        if placement.target == 'runwayZone' and placement.zoneKey then
            local runway = runwayForPlacement()
            if not runway then return false, 'Runway required.' end
            runway.zones = runway.zones or {}
            runway.zones[placement.zoneKey] = zone
            runway[placement.zoneKey] = zone
            return true
        end

        if placement.target == 'airspace' and placement.zoneKey then
            airport.airspace = airport.airspace or { enabled = true }
            zone.label = placement.label or zone.label
            zone.minZ = airport.airspace.altitudeMin or 0
            zone.maxZ = airport.airspace.altitudeMax or 1600
            airport.airspace[placement.zoneKey] = zone
            return true
        end

        if placement.target == 'zone' and placement.zoneKey then
            airport.zones = airport.zones or {}
            airport.zones[placement.zoneKey] = zone
            airport[placement.zoneKey] = zone
            return true
        end
    end

    if patch.action == 'ghostPlaced' and patch.gate then
        airport.gates = airport.gates or {}
        local index = tonumber(placement.index)
        if index and index >= 0 and airport.gates[index + 1] then
            for key, value in pairs(patch.gate) do
                airport.gates[index + 1][key] = value
            end
        else
            airport.gates[#airport.gates + 1] = patch.gate
        end
        return true
    end

    return false, 'Unsupported patch.'
end

lib.callback.register('partay_airlines:server:creatorCanOpen', function(source)
    return canUseCreator(source)
end)

lib.callback.register('partay_airlines:server:getCreatorAirports', function(source)
    if not canUseCreator(source) then return false, 'No creator access.' end
    return true, getAirports()
end)

lib.callback.register('partay_airlines:server:saveCreatorAirport', function(source, airport)
    if not canUseCreator(source) then return false, 'No creator access.' end
    if type(airport) ~= 'table' or not airport.id or airport.id == '' then return false, 'Airport ID required.' end

    airport.label = airport.label or airport.id
    airport.tower = airport.tower or airport.label
    airport.hangars = airport.hangars or {}
    normalizeAirport(airport)

    upsertAirport(airport, getCitizenId(source))
    TriggerClientEvent('partay_airlines:client:airportsUpdated', -1, getAirports())
    return true, airport
end)

lib.callback.register('partay_airlines:server:patchCreatorAirport', function(source, airportId, patch)
    if not canUseCreator(source) then return false, 'No creator access.' end
    if not airportId or airportId == '' then return false, 'Airport ID required.' end

    local airport = getAirport(airportId)
    if not airport then return false, 'Airport not found.' end

    local success, message = patchAirport(airport, patch)
    if not success then return false, message end

    upsertAirport(airport, getCitizenId(source))
    TriggerClientEvent('partay_airlines:client:airportsUpdated', -1, getAirports())
    return true, airport
end)

lib.callback.register('partay_airlines:server:getRuntimeAirports', function()
    return getAirports()
end)

CreateThread(function()
    Wait(1000)
    ensureAirportTables()
end)
