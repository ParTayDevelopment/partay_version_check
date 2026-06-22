local activePilotFlight
local deboardPrompted = {}
local atcNotices = {}
local flightRunwayAssignments = {}
local flightArrivalAssignments = {}
local flightArrivalGates = {}
local aircraftArrivalAssignments = {}
local aircraftArrivalGates = {}
local pendingFlightGateAssignments = {}
local pendingAircraftGateAssignments = {}
local aircraftDepartureAssignments = {}
local aircraftAtcStates = {}
local atcClearances = {}
local taxiHoldTimers = {}
local takeoffHoldTimers = {}
local takeoffZoneSeen = {}
local landingTimers = {}
local airspacePresence = {}
local aircraftAirspacePresence = {}
local airspaceIntent = {}
local airspaceReminders = {}
local airspacePromptOpen = false
local sandyDebugNoticeShown = false
local currentAircraftAtcKey
local currentAircraftAtcHandle
local currentPilotAircraft
local insideZone
local getGroundDistance
local pointInPolygon
local airportFor
local allAirports
local airportGroundDistance
PartayAirports = PartayAirports or {}
local navWaypoints = {}
local navWaypointHashes = {}

local function notify(description, notifyType)
    lib.notify({
        title = 'ParTay Airlines',
        description = description,
        type = notifyType or 'inform'
    })
end

local function getAircraftModelName(vehicle)
    local model = GetEntityModel(vehicle)

    for aircraftModel in pairs(Config.Aircraft) do
        if model == joaat(aircraftModel) then
            return aircraftModel
        end
    end

    return nil
end

local function isAircraftVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    local model = GetEntityModel(vehicle)
    local vehicleClass = GetVehicleClass(vehicle)

    return vehicleClass == 15
        or vehicleClass == 16
        or IsThisModelAPlane(model)
        or IsThisModelAHeli(model)
        or getAircraftModelName(vehicle) ~= nil
end

local function entityFromNetId(netId)
    if not netId or netId == 0 then return 0 end
    if not NetworkDoesNetworkIdExist(netId) then return 0 end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity == 0 or not DoesEntityExist(entity) then return 0 end

    return entity
end

local function aircraftAtcKey(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId and netId ~= 0 then
        local netKey = ('aircraft:%s'):format(netId)
        if currentAircraftAtcKey and currentAircraftAtcKey ~= netKey then
            if aircraftArrivalAssignments[currentAircraftAtcKey] and not aircraftArrivalAssignments[netKey] then
                aircraftArrivalAssignments[netKey] = aircraftArrivalAssignments[currentAircraftAtcKey]
                aircraftArrivalAssignments[currentAircraftAtcKey] = nil
            end
            if atcClearances[currentAircraftAtcKey] and not atcClearances[netKey] then
                atcClearances[netKey] = atcClearances[currentAircraftAtcKey]
                atcClearances[currentAircraftAtcKey] = nil
            end
        end
        currentAircraftAtcKey = netKey
        return currentAircraftAtcKey
    end

    if currentAircraftAtcHandle ~= vehicle then
        currentAircraftAtcHandle = vehicle
        currentAircraftAtcKey = ('aircraft:local:%s'):format(vehicle)
    end

    return currentAircraftAtcKey
end

local function currentAtcTarget(vehicle, flight)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil, nil end

    local aircraftKey = aircraftAtcKey(vehicle)
    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
    local flightMatchesVehicle = flight and (not flight.aircraftNetId or flight.aircraftNetId == vehicleNetId)
    local activeFlight = flightMatchesVehicle and flight or nil
    local target = activeFlight or (aircraftKey and {
        id = aircraftKey,
        flightNumber = 'Aircraft',
        aircraftNetId = vehicleNetId,
        temporary = true
    }) or nil

    return target, activeFlight
end

local function getGateConfig(gateName, airport)
    for _, gate in ipairs(Config.Locations.boardingGates) do
        if gate.gate == gateName and (not airport or gate.airport == airport) then
            return gate
        end
    end

    return nil
end

local function isSpawnClear(coords)
    local closest = GetClosestVehicle(coords.x, coords.y, coords.z, Config.Spawning.clearRadius or 8.0, 0, 70)
    return closest == 0 or not DoesEntityExist(closest)
end

local function spawnFlightAircraft(flight)
    local gate = getGateConfig(flight.gate, flight.departure)
    if not gate or not gate.aircraftSpawn then
        return nil, 'This gate is missing aircraft spawn coords in config.'
    end

    if not flight.aircraftModel or not Config.Aircraft[flight.aircraftModel] then
        return nil, 'This flight has no configured aircraft model.'
    end

    local spawn = gate.aircraftSpawn
    local spawnCoords = vec3(spawn.x, spawn.y, spawn.z)
    if not isSpawnClear(spawnCoords) then
        return nil, 'Aircraft spawn is blocked. Clear the gate ramp and try again.'
    end

    local model = joaat(flight.aircraftModel)
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
        return nil, ('Invalid aircraft model: %s'):format(flight.aircraftModel)
    end

    lib.requestModel(model, 10000)

    local vehicle = CreateVehicle(model, spawn.x, spawn.y, spawn.z, spawn.w or 0.0, true, true)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        SetModelAsNoLongerNeeded(model)
        return nil, 'Aircraft could not be spawned.'
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleEngineOn(vehicle, Config.Spawning.engineOnAfterSpawn == true, true, false)
    SetModelAsNoLongerNeeded(model)

    if Config.Spawning.warpPilotIntoSeat ~= false then
        TaskWarpPedIntoVehicle(cache.ped, vehicle, -1)
    end

    local timeout = GetGameTimer() + 5000
    while not NetworkGetEntityIsNetworked(vehicle) and GetGameTimer() < timeout do
        NetworkRegisterEntityAsNetworked(vehicle)
        Wait(0)
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        DeleteEntity(vehicle)
        return nil, 'Aircraft spawned but did not receive a network ID.'
    end

    SetNetworkIdCanMigrate(netId, true)
    SetNetworkIdExistsOnAllMachines(netId, true)

    return vehicle, nil
end

local function formatClock(timestamp)
    if not timestamp then return 'TBD' end

    local now = GetCloudTimeAsInt()
    if not now or now <= 0 then
        return ('Unix %s'):format(timestamp)
    end

    local minutes = math.floor((timestamp - now) / 60)
    if minutes > 90 then
        local hours = math.floor(minutes / 60)
        local remainingMinutes = minutes % 60
        return ('in %sh %sm'):format(hours, remainingMinutes)
    elseif minutes > 1 then
        return ('in %sm'):format(minutes)
    elseif minutes >= 0 then
        return 'now'
    end

    return 'expired'
end

local function classPrice(routeId, ticketClass)
    local route = Config.Routes[routeId]
    local classConfig = Config.TicketClasses[ticketClass]

    if not route or not classConfig then return 0 end
    return math.floor(route.basePrice * classConfig.priceMultiplier)
end

local function routeBadges(flight)
    local badges = {}
    local requirements = flight.requirements or {}

    if flight.routeType == 'international' then badges[#badges + 1] = 'International' end
    if requirements.passport then badges[#badges + 1] = 'Passport Required' end
    if requirements.customsClearance then badges[#badges + 1] = 'Customs Required' end

    return table.concat(badges, ' | ')
end

local function sortedKeys(data)
    local keys = {}
    for key in pairs(data or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function drawGroundMarker(point, red, green, blue)
    if not point or not point.coords then return end

    local radius = point.radius or 2.0
    local coords = point.coords

    DrawMarker(
        1,
        coords.x, coords.y, coords.z - 1.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        radius * 2.0, radius * 2.0, 2.5,
        red, green, blue, 120,
        false, false, 2, false, nil, nil, false
    )
end

local function asVec3(value)
    if not value then return nil end
    return vec3(value.x or value[1] or 0.0, value.y or value[2] or 0.0, value.z or value[3] or 0.0)
end

local function normalizeKnownAirport(airport)
    if not airport or not airport.id then return airport end

    airport.atc = airport.atc or {}
    airport.airspace = airport.airspace or { enabled = true }
    airport.airspace.enabled = airport.airspace.enabled ~= false

    if airport.id == 'sandy' then
        airport.atc.coords = { x = 1702.2449, y = 3291.2336, z = 50.6186, w = 74.2191 }
        airport.atc.coverageRadius = tonumber(airport.atc.coverageRadius) or 1000.0
        airport.airspace.radius = math.max(tonumber(airport.airspace.radius) or 0.0, 864.0)
        airport.airspace.altitudeMin = tonumber(airport.airspace.altitudeMin) or 0.0
        airport.airspace.altitudeMax = tonumber(airport.airspace.altitudeMax) or 1400.0
        airport.airspace.contactRadius = airport.airspace.radius
    elseif airport.id == 'lsia' then
        airport.airspace.radius = math.max(tonumber(airport.airspace.radius) or 0.0, 2652.0)
        airport.airspace.altitudeMin = tonumber(airport.airspace.altitudeMin) or 0.0
        airport.airspace.altitudeMax = tonumber(airport.airspace.altitudeMax) or 1800.0
        airport.airspace.contactRadius = airport.airspace.radius
    elseif airport.id == 'grapeseed' then
        airport.airspace.radius = tonumber(airport.airspace.radius) or 450.0
        airport.airspace.altitudeMin = tonumber(airport.airspace.altitudeMin) or 0.0
        airport.airspace.altitudeMax = tonumber(airport.airspace.altitudeMax) or 1800.0
        airport.airspace.contactRadius = airport.airspace.radius
    end

    return airport
end

local function getBoxCorners(zone)
    if not zone or not zone.coords then return {} end

    local heading = math.rad(zone.heading or 0.0)
    local halfLength = (zone.length or 20.0) * 0.5
    local halfWidth = (zone.width or 20.0) * 0.5
    local offsets = {
        vec2(halfLength, halfWidth),
        vec2(halfLength, -halfWidth),
        vec2(-halfLength, -halfWidth),
        vec2(-halfLength, halfWidth)
    }
    local corners = {}

    for _, offset in ipairs(offsets) do
        local x = zone.coords.x + offset.x * math.cos(heading) - offset.y * math.sin(heading)
        local y = zone.coords.y + offset.x * math.sin(heading) + offset.y * math.cos(heading)
        corners[#corners + 1] = vec3(x, y, zone.coords.z)
    end

    return corners
end

local function drawZone(zone, red, green, blue)
    if not zone then return end

    if type(zone) == 'table' and zone[1] and not zone.type and not zone.coords and not zone.points then
        for _, candidate in ipairs(zone) do
            drawZone(candidate, red, green, blue)
        end
        return
    end

    if (zone.type or 'sphere') == 'poly' and zone.points then
        for index, point in ipairs(zone.points) do
            local nextPoint = zone.points[index + 1] or zone.points[1]
            if point and point.x and point.y and point.z then
                DrawMarker(28, point.x, point.y, point.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.5, 2.5, 2.5, red, green, blue, 170, false, false, 2, false, nil, nil, false)
            end
            if point and nextPoint and point.x and point.y and point.z and nextPoint.x and nextPoint.y and nextPoint.z then
                DrawLine(point.x, point.y, point.z + 1.0, nextPoint.x, nextPoint.y, nextPoint.z + 1.0, red, green, blue, 220)
            end
        end
    elseif (zone.type or 'sphere') == 'box' then
        local corners = getBoxCorners(zone)
        for index, point in ipairs(corners) do
            local nextPoint = corners[index + 1] or corners[1]
            DrawMarker(28, point.x, point.y, point.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.5, 2.5, 2.5, red, green, blue, 170, false, false, 2, false, nil, nil, false)
            DrawLine(point.x, point.y, point.z + 1.0, nextPoint.x, nextPoint.y, nextPoint.z + 1.0, red, green, blue, 220)
        end
    else
        drawGroundMarker(zone, red, green, blue)
    end
end

local function drawPolyFill(zone, red, green, blue, alpha)
    if not zone or (zone.type or 'poly') ~= 'poly' or not zone.points or #zone.points < 3 then return end

    local points = zone.points
    local origin = points[1]
    local zOffset = 0.35

    for index = 2, #points - 1 do
        local a = points[index]
        local b = points[index + 1]
        DrawPoly(
            origin.x, origin.y, origin.z + zOffset,
            a.x, a.y, a.z + zOffset,
            b.x, b.y, b.z + zOffset,
            red, green, blue, alpha or 90
        )
        DrawPoly(
            b.x, b.y, b.z + zOffset,
            a.x, a.y, a.z + zOffset,
            origin.x, origin.y, origin.z + zOffset,
            red, green, blue, alpha or 90
        )
    end
end

local function runwaySurfaceZone(runway)
    if not runway then return nil end
    if runway.zone then return runway.zone end
    if runway.points then return { type = 'poly', points = runway.points } end
    return runway
end

local function drawRunwayHighlight(runway, red, green, blue)
    if not runway then return end

    local runwayZone = runwaySurfaceZone(runway)
    drawPolyFill(runwayZone, red, green, blue, 125)
    drawZone(runwayZone, red, green, blue)
end

local function drawHoldHighlight(zone, red, green, blue)
    if not zone then return end

    drawPolyFill(zone, red, green, blue, 85)
    drawZone(zone, red, green, blue)
end

local function zoneCenter(zone)
    if not zone then return nil end

    if (zone.type or 'sphere') == 'poly' and zone.points and #zone.points > 0 then
        local x, y, z = 0.0, 0.0, 0.0
        for _, point in ipairs(zone.points) do
            x = x + point.x
            y = y + point.y
            z = z + point.z
        end

        return vec3(x / #zone.points, y / #zone.points, z / #zone.points)
    end

    if zone.coords then return asVec3(zone.coords) end
    return nil
end

local function navigationEnabled()
    local nav = Config.Navigation or {}
    return nav.enabled ~= false
        and nav.resource
        and GetResourceState(nav.resource) == 'started'
end

local function navigationData(label, coords, color, waypointType, size)
    local nav = Config.Navigation or {}
    return {
        coords = coords,
        type = waypointType or 'checkpoint',
        label = label,
        color = color or '#4aa3ff',
        size = size or 0.8,
        drawDistance = nav.drawDistance or 2500.0,
        fadeDistance = nav.fadeDistance or 2100.0,
        displayDistance = true,
        groundZ = coords.z - 1.0,
        minHeight = 3.0,
        maxHeight = 90.0
    }
end

local function navigationHash(data)
    local coords = data and data.coords
    if not coords then return nil end

    return ('%s:%s:%s:%s:%s:%s'):format(
        data.label or '',
        data.color or '',
        data.type or '',
        math.floor((coords.x or 0.0) * 10.0 + 0.5),
        math.floor((coords.y or 0.0) * 10.0 + 0.5),
        math.floor((coords.z or 0.0) * 10.0 + 0.5)
    )
end

local function aircraftOccupantServerIds()
    local vehicle = currentPilotAircraft()
    if not vehicle then return nil end

    local targets = {}
    local myServerId = GetPlayerServerId(PlayerId())
    local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle)

    for seat = -1, maxPassengers - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped and ped ~= 0 and IsPedAPlayer(ped) then
            local player = NetworkGetPlayerIndexFromPed(ped)
            local serverId = player and GetPlayerServerId(player) or nil
            if serverId and serverId ~= myServerId then
                targets[#targets + 1] = serverId
            end
        end
    end

    return #targets > 0 and targets or nil
end

local function syncNavigationWaypoint(key, data, targets)
    targets = targets or aircraftOccupantServerIds()
    if not targets then return end

    TriggerServerEvent('partay_airlines:server:setNavigationWaypoint', key, data, targets)
end

local function clearSyncedNavigationWaypoint(key)
    TriggerServerEvent('partay_airlines:server:clearNavigationWaypoint', key)
end

local function setNavigationWaypoint(key, label, coords, color, waypointType, size)
    if not key or not coords or not navigationEnabled() then return end

    local resource = Config.Navigation.resource
    local data = navigationData(label, coords, color, waypointType, size)
    local targets = aircraftOccupantServerIds()
    local hash = navigationHash(data)
    if targets then hash = ('%s:%s'):format(hash, table.concat(targets, ',')) end
    if navWaypointHashes[key] == hash then return end

    local currentId = navWaypoints[key]

    if currentId then
        local ok = pcall(function()
            exports[resource]:update(currentId, data)
        end)
        if ok then
            navWaypointHashes[key] = hash
            syncNavigationWaypoint(key, data, targets)
            return
        end
        navWaypoints[key] = nil
    end

    local ok, waypointId = pcall(function()
        return exports[resource]:create(data)
    end)
    if ok and waypointId then
        navWaypoints[key] = waypointId
    end

    navWaypointHashes[key] = hash
    syncNavigationWaypoint(key, data, targets)
end

local function clearNavigationWaypoint(key)
    local waypointId = navWaypoints[key]
    if not waypointId then return end

    local resource = Config.Navigation and Config.Navigation.resource
    if resource and GetResourceState(resource) == 'started' then
        pcall(function()
            exports[resource]:remove(waypointId)
        end)
    end

    navWaypoints[key] = nil
    navWaypointHashes[key] = nil
    clearSyncedNavigationWaypoint(key)
end

local function clearNavigationPrefix(prefix)
    for key in pairs(navWaypoints) do
        if key:sub(1, #prefix) == prefix then
            clearNavigationWaypoint(key)
        end
    end
end

local function setZoneNavigation(prefix, slot, label, zone, color, waypointType, size)
    local coords = zoneCenter(zone)
    if coords then
        setNavigationWaypoint(('%s:%s'):format(prefix, slot), label, coords, color, waypointType, size)
    end
end

local function setPointNavigation(prefix, slot, label, coords, color, waypointType, size)
    coords = asVec3(coords)
    if coords then
        setNavigationWaypoint(('%s:%s'):format(prefix, slot), label, coords, color, waypointType, size)
    end
end

local function airportCenter(airport)
    if not airport then return nil end

    if airport.atc and airport.atc.coords then
        return asVec3(airport.atc.coords)
    end

    for _, runway in ipairs(airport.runways or {}) do
        local center = runway.center and asVec3(runway.center) or zoneCenter(runwaySurfaceZone(runway))
        if center then return center end
    end

    return nil
end

local function drawSphereAt(center, radius, red, green, blue, alpha)
    if not center or not radius or radius <= 0.0 then return end

    DrawMarker(
        28,
        center.x, center.y, center.z,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        radius * 2.0, radius * 2.0, radius * 2.0,
        red, green, blue, alpha or 45,
        false, false, 2, false, nil, nil, false
    )
end

local function drawAtcPoint(center)
    if not center then return end

    DrawMarker(
        2,
        center.x, center.y, center.z + 12.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        12.0, 12.0, 12.0,
        20, 95, 180, 230,
        false, true, 2, false, nil, nil, false
    )

    DrawMarker(
        1,
        center.x, center.y, center.z - 1.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        18.0, 18.0, 8.0,
        20, 95, 180, 180,
        false, false, 2, false, nil, nil, false
    )
end

local function drawAirspaceRing(center, radius, red, green, blue)
    if not center or not radius or radius <= 0.0 then return end

    local ringZ = center.z + 6.0
    local segments = 96

    for index = 0, segments - 1 do
        local angleA = (index / segments) * math.pi * 2.0
        local angleB = ((index + 1) / segments) * math.pi * 2.0
        local ax = center.x + math.cos(angleA) * radius
        local ay = center.y + math.sin(angleA) * radius
        local bx = center.x + math.cos(angleB) * radius
        local by = center.y + math.sin(angleB) * radius
        DrawLine(ax, ay, ringZ, bx, by, ringZ, red, green, blue, 235)
    end
end

local function drawAirspaceBoundary(center, radius, minZ, maxZ, red, green, blue)
    if not center or not radius or radius <= 0.0 then return end

    local bottomZ = center.z + (tonumber(minZ) or 0.0)
    local topZ = center.z + math.min(tonumber(maxZ) or 900.0, 900.0)
    local midZ = center.z + 6.0
    local segments = 96

    for index = 0, segments - 1 do
        local angleA = (index / segments) * math.pi * 2.0
        local angleB = ((index + 1) / segments) * math.pi * 2.0
        local ax = center.x + math.cos(angleA) * radius
        local ay = center.y + math.sin(angleA) * radius
        local bx = center.x + math.cos(angleB) * radius
        local by = center.y + math.sin(angleB) * radius

        DrawLine(ax, ay, bottomZ, bx, by, bottomZ, red, green, blue, 235)
        DrawLine(ax, ay, midZ, bx, by, midZ, red, green, blue, 255)
        DrawLine(ax, ay, topZ, bx, by, topZ, red, green, blue, 190)

        if index % 12 == 0 then
            DrawLine(ax, ay, bottomZ, ax, ay, topZ, red, green, blue, 210)
            DrawMarker(28, ax, ay, midZ, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 5.0, 5.0, 5.0, red, green, blue, 220, false, false, 2, false, nil, nil, false)
        end
    end

    DrawLine(center.x - radius, center.y, midZ, center.x + radius, center.y, midZ, red, green, blue, 170)
    DrawLine(center.x, center.y - radius, midZ, center.x, center.y + radius, midZ, red, green, blue, 170)
end

local function drawAirspaceVolume(volume, red, green, blue)
    if not volume or not volume.polygon or #volume.polygon < 3 then return end

    local bottomZ = tonumber(volume.floor) or 0.0
    local topZ = tonumber(volume.ceiling) or bottomZ + 1000.0
    local midZ = bottomZ + ((topZ - bottomZ) * 0.5)

    for index, point in ipairs(volume.polygon) do
        local nextPoint = volume.polygon[index + 1] or volume.polygon[1]
        DrawLine(point.x, point.y, bottomZ, nextPoint.x, nextPoint.y, bottomZ, red, green, blue, 235)
        DrawLine(point.x, point.y, topZ, nextPoint.x, nextPoint.y, topZ, red, green, blue, 190)
        DrawLine(point.x, point.y, midZ, nextPoint.x, nextPoint.y, midZ, red, green, blue, 255)

        if index % 2 == 1 then
            DrawLine(point.x, point.y, bottomZ, point.x, point.y, topZ, red, green, blue, 180)
            DrawMarker(28, point.x, point.y, midZ, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 7.5, 7.5, 7.5, red, green, blue, 210, false, false, 2, false, nil, nil, false)
        end
    end
end

local function airportById(id)
    if not id then return nil end

    for _, airport in ipairs(allAirports()) do
        if airport.id == id then return airport end
    end

    local airport = Config.Airports and Config.Airports[id] or nil
    if airport then
        local copy = {}
        for key, value in pairs(airport) do
            copy[key] = value
        end
        copy.id = copy.id or id
        return copy
    end

    return nil
end

local function pointInAirspaceVolume(coords, volume)
    if not coords or not volume or not volume.polygon or #volume.polygon < 3 then return false end

    local floor = tonumber(volume.floor) or 0.0
    local ceiling = tonumber(volume.ceiling) or 99999.0
    if coords.z < floor or coords.z > ceiling then return false end

    return pointInPolygon(coords, volume.polygon)
end

local function volumeCenter(volume)
    if not volume or not volume.polygon or #volume.polygon == 0 then return nil end

    local x, y = 0.0, 0.0
    for _, point in ipairs(volume.polygon) do
        x = x + point.x
        y = y + point.y
    end

    return vec3(x / #volume.polygon, y / #volume.polygon, ((tonumber(volume.floor) or 0.0) + (tonumber(volume.ceiling) or 0.0)) * 0.5)
end

local function airspaceVolumeDistance(coords, volume)
    local center = volumeCenter(volume)
    if not coords or not center then return nil end

    return #(vec3(coords.x, coords.y, center.z) - vec3(center.x, center.y, center.z))
end

local function matchingAirspaceVolumes(coords, departureId)
    if not coords or not (Config.Airspace and Config.Airspace.useVolumes ~= false) then return {} end

    local matches = {}
    for _, volume in ipairs(Config.AirspaceVolumes or {}) do
        if volume.enabled ~= false and volume.airport ~= departureId and pointInAirspaceVolume(coords, volume) then
            matches[#matches + 1] = volume
        end
    end

    table.sort(matches, function(a, b)
        local ap = tonumber(a.priority) or 50
        local bp = tonumber(b.priority) or 50
        if ap ~= bp then return ap < bp end

        local af = tonumber(a.floor) or 0.0
        local bf = tonumber(b.floor) or 0.0
        if af ~= bf then return af < bf end

        return tostring(a.id or '') < tostring(b.id or '')
    end)

    return matches
end

local function activeAirspaceVolume(coords, departureId)
    return matchingAirspaceVolumes(coords, departureId)[1]
end

local function airportForAirspaceVolume(volume, coords)
    if not volume then return nil end

    local airport = airportById(volume.airport)
    if airport then
        normalizeKnownAirport(airport)
        airport.airspaceVolume = volume
        airport.tower = volume.facility or airport.tower
        airport.label = airport.label or volume.label
        return airport
    end

    local nearest
    local nearestDistance
    for _, candidate in ipairs(allAirports()) do
        normalizeKnownAirport(candidate)
        local distance = airportGroundDistance(coords, candidate)
        if distance and (not nearestDistance or distance < nearestDistance) then
            nearest = candidate
            nearestDistance = distance
        end
    end

    if nearest then
        nearest.airspaceVolume = volume
        nearest.tower = volume.facility or nearest.tower
    end

    return nearest
end

local function insideAirportAirspace(coords, airport)
    if not coords or not airport or airport.airspace and airport.airspace.enabled == false then return false end

    local center = airportCenter(airport)
    local radius = airport.airspace and airport.airspace.radius or nil
    if not center or not radius or radius <= 0 then return false end

    local minAlt = airport.airspace.altitudeMin or 0.0
    local maxAlt = airport.airspace.altitudeMax or 99999.0
    local horizontalDistance = #(vec3(coords.x, coords.y, center.z) - vec3(center.x, center.y, center.z))

    return horizontalDistance <= radius and coords.z >= minAlt and coords.z <= maxAlt
end

local function airportAirspaceDistance(coords, airport)
    local center = airportCenter(airport)
    if not coords or not center then return nil end

    return #(vec3(coords.x, coords.y, center.z) - vec3(center.x, center.y, center.z))
end

local function zoneDistance(coords, zone)
    local center = zoneCenter(zone)
    if not coords or not center then return nil end

    return #(vec3(coords.x, coords.y, center.z) - vec3(center.x, center.y, center.z))
end

airportGroundDistance = function(coords, airport)
    if not coords or not airport then return nil end

    local nearest = airportAirspaceDistance(coords, airport)

    local function consider(distance)
        if distance and (not nearest or distance < nearest) then
            nearest = distance
        end
    end

    for _, gate in ipairs(airport.gates or {}) do
        local spawn = gate.aircraftSpawn or gate.coords
        if spawn then
            consider(#(vec3(coords.x, coords.y, spawn.z or coords.z) - vec3(spawn.x, spawn.y, spawn.z or coords.z)))
        end
    end

    for _, hangar in ipairs(airport.hangars or {}) do
        local hangarCoords = hangar.coords
        if hangarCoords then
            consider(#(vec3(coords.x, coords.y, hangarCoords.z or coords.z) - vec3(hangarCoords.x, hangarCoords.y, hangarCoords.z or coords.z)))
        end
    end

    for _, runway in ipairs(airport.runways or {}) do
        consider(zoneDistance(coords, runwaySurfaceZone(runway)))

        for _, zone in pairs(runway.zones or {}) do
            consider(zoneDistance(coords, zone))
        end

        for _, direction in ipairs(runway.directions or {}) do
            for _, zone in pairs(direction.zones or {}) do
                consider(zoneDistance(coords, zone))
            end
        end
    end

    for _, zone in pairs(airport.zones or {}) do
        consider(zoneDistance(coords, zone))
    end

    return nearest
end

local function insideAirportContactAirspace(coords, airport)
    if not coords or not airport or airport.airspace and airport.airspace.enabled == false then return false end

    local distance = airportAirspaceDistance(coords, airport)
    local radius = airport.airspace and airport.airspace.radius or nil
    if not distance or not radius or radius <= 0 then return false end

    local minAlt = airport.airspace.altitudeMin or 0.0
    local maxAlt = airport.airspace.altitudeMax or 99999.0

    return distance <= radius and coords.z >= minAlt and coords.z <= maxAlt
end

allAirports = function()
    if PartayAirports and #PartayAirports > 0 then
        return PartayAirports
    end

    local airports = {}
    for id, airport in pairs(Config.Airports or {}) do
        local copy = {}
        for key, value in pairs(airport) do
            copy[key] = value
        end
        copy.id = copy.id or id
        airports[#airports + 1] = copy
    end

    return airports
end

local function nearestContactAirport(coords, departureId)
    local volume = activeAirspaceVolume(coords, departureId)
    if volume then
        return airportForAirspaceVolume(volume, coords)
    end

    if Config.Airspace and Config.Airspace.allowRadiusFallback == false then
        return nil
    end

    local nearest
    local nearestDistance

    for _, airport in ipairs(allAirports()) do
        if airport.id ~= departureId and airport.airspace and airport.airspace.enabled ~= false and insideAirportContactAirspace(coords, airport) then
            local distance = airportAirspaceDistance(coords, airport)
            if distance and (not nearestDistance or distance < nearestDistance) then
                nearest = airport
                nearestDistance = distance
            end
        end
    end

    return nearest
end

pointInPolygon = function(coords, points)
    local inside = false
    local j = #points

    for i = 1, #points do
        local pi = points[i]
        local pj = points[j]

        if ((pi.y > coords.y) ~= (pj.y > coords.y)) and (coords.x < (pj.x - pi.x) * (coords.y - pi.y) / ((pj.y - pi.y) + 0.000001) + pi.x) then
            inside = not inside
        end

        j = i
    end

    return inside
end

local function insideBox(coords, zone)
    local heading = math.rad(-(zone.heading or 0.0))
    local zoneCoords = asVec3(zone.coords)
    if not zoneCoords then return false end

    local dx = coords.x - zoneCoords.x
    local dy = coords.y - zoneCoords.y
    local localX = dx * math.cos(heading) - dy * math.sin(heading)
    local localY = dx * math.sin(heading) + dy * math.cos(heading)
    local halfLength = (zone.length or zone.radius or 10.0) * 0.5
    local halfWidth = (zone.width or zone.radius or 10.0) * 0.5
    local minZ = zone.minZ or (zoneCoords.z - ((zone.thickness or 10.0) * 0.5))
    local maxZ = zone.maxZ or (zoneCoords.z + ((zone.thickness or 10.0) * 0.5))

    return math.abs(localX) <= halfLength and math.abs(localY) <= halfWidth and coords.z >= minZ and coords.z <= maxZ
end

local function insideBox2d(coords, zone)
    local heading = math.rad(-(zone.heading or 0.0))
    local zoneCoords = asVec3(zone.coords)
    if not zoneCoords then return false end

    local dx = coords.x - zoneCoords.x
    local dy = coords.y - zoneCoords.y
    local localX = dx * math.cos(heading) - dy * math.sin(heading)
    local localY = dx * math.sin(heading) + dy * math.cos(heading)
    local halfLength = (zone.length or zone.radius or 10.0) * 0.5
    local halfWidth = (zone.width or zone.radius or 10.0) * 0.5

    return math.abs(localX) <= halfLength and math.abs(localY) <= halfWidth
end

local function insideZone2d(coords, zone)
    if not zone then return false end

    local zoneType = zone.type or 'sphere'
    if zoneType == 'poly' then
        return zone.points and #zone.points >= 3 and pointInPolygon(coords, zone.points)
    elseif zoneType == 'box' then
        return insideBox2d(coords, zone)
    end

    local zoneCoords = asVec3(zone.coords)
    if not zoneCoords then return false end

    local dx = coords.x - zoneCoords.x
    local dy = coords.y - zoneCoords.y
    return math.sqrt((dx * dx) + (dy * dy)) <= (zone.radius or 1.0)
end

insideZone = function(coords, zone)
    if not zone then return false end

    local zoneType = zone.type or 'sphere'
    if zoneType == 'poly' then
        if not zone.points or #zone.points < 3 then return false end

        local minZ = zone.minZ or (zone.points[1].z - ((zone.thickness or 20.0) * 0.5))
        local maxZ = zone.maxZ or (zone.points[1].z + ((zone.thickness or 20.0) * 0.5))
        return coords.z >= minZ and coords.z <= maxZ and pointInPolygon(coords, zone.points)
    elseif zoneType == 'box' then
        return insideBox(coords, zone)
    end

    local zoneCoords = asVec3(zone.coords)
    return zoneCoords and #(coords - zoneCoords) <= (zone.radius or 1.0)
end

airportFor = function(id)
    if PartayAirports then
        for _, airport in ipairs(PartayAirports) do
            if airport.id == id then
                if airport.zones then
                    airport.taxiHold = airport.zones.taxiHold or airport.taxiHold
                    airport.takeoffHold = airport.zones.takeoffHold or airport.takeoffHold
                    airport.takeoffZone = airport.zones.takeoffZone or airport.takeoffZone
                    airport.approachZone = airport.zones.approachZone or airport.approachZone
                    airport.landingZone = airport.zones.landingZone or airport.landingZone
                end
                return airport
            end
        end
    end

    return Config.Airports and Config.Airports[id]
end

local function gateArrivalZone(airport, coords)
    for _, gate in ipairs(airport and airport.gates or {}) do
        local spawn = gate.aircraftSpawn or gate.coords
        if spawn then
            local zone = {
                type = 'sphere',
                label = gate.label or gate.gate or 'Arrival Gate',
                coords = { x = spawn.x, y = spawn.y, z = spawn.z },
                radius = gate.aircraftBoardingRadius or gate.radius or 28.0
            }

            if not coords or insideZone(coords, zone) then
                return zone, nil, nil, nil, gate
            end
        end
    end

    return nil
end

local function bestArrivalGate(airport, coords)
    local bestZone
    local bestGate
    local bestDistance

    for _, gate in ipairs(airport and airport.gates or {}) do
        local spawn = gate.aircraftSpawn or gate.coords
        if spawn then
            local zone = {
                type = 'sphere',
                label = gate.label or gate.gate or 'Arrival Gate',
                coords = vec3(spawn.x, spawn.y, spawn.z),
                radius = gate.aircraftBoardingRadius or gate.radius or 28.0
            }
            local distance = coords and #(vec3(coords.x, coords.y, spawn.z or coords.z) - vec3(spawn.x, spawn.y, spawn.z or coords.z)) or 0.0

            if not bestDistance or distance < bestDistance then
                bestDistance = distance
                bestZone = zone
                bestGate = gate
            end
        end
    end

    return bestZone, bestGate
end

local function holdSatisfied(timers, key, inZone, speed, holdMs)
    if not inZone or speed > 2.25 then
        timers[key] = nil
        return false
    end

    local now = GetGameTimer()
    timers[key] = timers[key] or now
    return now - timers[key] >= (holdMs or 5000)
end

local function takeoffConfirmed(key, vehicle, coords, takeoffZone, speed)
    if not key or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or not takeoffZone then return false end

    local airborneAltitude = (Config.ATC and Config.ATC.takeoffConfirmAltitude) or Config.Tracking.takeoffAltitude or 30.0
    local groundDistance = getGroundDistance(vehicle)
    local airborne = groundDistance > airborneAltitude and speed > Config.Tracking.takeoffSpeed
    local inTakeoffZone = insideZone(coords, takeoffZone)
    if inTakeoffZone then
        takeoffZoneSeen[key] = true
        return airborne
    end

    return airborne
end

local function aircraftRunwayState(vehicle, coords, landingZone, runwayZone, speed)
    local groundDistance = getGroundDistance(vehicle)
    return {
        inLandingZone = insideZone(coords, landingZone) or insideZone2d(coords, landingZone),
        onRunway = insideZone2d(coords, runwayZone),
        runwayVacated = runwayZone and not insideZone2d(coords, runwayZone) or false,
        groundDistance = groundDistance,
        onGround = not IsEntityInAir(vehicle),
        speed = speed or 0.0
    }
end

local function landingConfirmed(key, vehicle, coords, landingZone, runwayZone, speed)
    if not key or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or (not landingZone and not runwayZone) then return false end

    local state = aircraftRunwayState(vehicle, coords, landingZone, runwayZone, speed)
    local landingAltitude = (Config.ATC and Config.ATC.landingConfirmAltitude) or Config.Tracking.landingAltitude or 12.0
    local landingSpeed = (Config.ATC and Config.ATC.landingConfirmSpeed) or Config.Tracking.landingSpeed
    local touchdownSpeed = (Config.ATC and Config.ATC.touchdownConfirmSpeed) or math.max(landingSpeed, 85.0)
    local landed = (state.inLandingZone or state.onRunway)
        and (state.groundDistance <= landingAltitude or state.onGround)
        and (state.speed < landingSpeed or (state.onGround and state.speed < touchdownSpeed))
        and GetVehicleEngineHealth(vehicle) > Config.Tracking.aircraftMinimumHealth

    if not landed then
        landingTimers[key] = nil
        return false
    end

    local now = GetGameTimer()
    landingTimers[key] = landingTimers[key] or now
    local confirmMs = ((Config.ATC and Config.ATC.landingConfirmSeconds) or 3) * 1000
    return now - landingTimers[key] >= confirmMs
end

local function isZone(value)
    return type(value) == 'table' and (value.type ~= nil or value.coords ~= nil or value.points ~= nil)
end

local function addZoneCandidate(candidates, zone)
    if not zone then return end

    if isZone(zone) then
        candidates[#candidates + 1] = zone
        return
    end

    if type(zone) == 'table' then
        for _, candidate in ipairs(zone) do
            if isZone(candidate) then candidates[#candidates + 1] = candidate end
        end
    end
end

local function zoneCandidates(owner, key)
    local candidates = {}
    addZoneCandidate(candidates, owner and owner.zones and owner.zones[key])
    addZoneCandidate(candidates, owner and owner[key])
    return candidates
end

local function matchingZone(candidates, coords)
    for _, zone in ipairs(candidates or {}) do
        if not coords or insideZone(coords, zone) then return zone end
    end

    return nil
end

local function zoneFromRunway(runway, key, coords)
    if not runway then return nil end
    return matchingZone(zoneCandidates(runway, key), coords)
end

local function airportZone(airport, key, coords)
    if not airport then return nil end

    local hasRunways = airport.runways and #airport.runways > 0

    if key == 'arrivalGate' then
        local gateZone, _, _, _, gate = gateArrivalZone(airport, coords)
        if gateZone then return gateZone, nil, nil, nil, gate end

        local legacyAirportGate = matchingZone(zoneCandidates(airport, key), coords)
        return legacyAirportGate, nil
    end

    for runwayIndex, runway in ipairs(airport.runways or {}) do
        for _, direction in ipairs(runway.directions or {}) do
            local directionZone = matchingZone(zoneCandidates(direction, key), coords)
            if directionZone then
                return directionZone, runway, direction, runwayIndex
            end
        end

        local zone = zoneFromRunway(runway, key, coords)
        if zone then
            return zone, runway, nil, runwayIndex
        end
    end

    if hasRunways then return nil end

    return matchingZone(zoneCandidates(airport, key), coords), nil
end

local function assignedDirectionZone(airport, key, assignment)
    if not airport or not assignment then return nil end

    local runway = assignment.runwayIndex and (airport.runways or {})[assignment.runwayIndex]
    if not runway then return nil end

    local direction
    for _, candidate in ipairs(runway.directions or {}) do
        if candidate.id == assignment.directionId then
            direction = candidate
            break
        end
    end

    local zone = matchingZone(zoneCandidates(direction, key))
    return zone, runway, direction
end

local function assignedRunwayZone(airport, key, assignment)
    if not airport or not assignment then return nil end

    local runway = assignment.runwayIndex and (airport.runways or {})[assignment.runwayIndex]
    if not runway then return nil end

    local direction
    for _, candidate in ipairs(runway.directions or {}) do
        if candidate.id == assignment.directionId then
            direction = candidate
            break
        end
    end

    local directionZone = matchingZone(zoneCandidates(direction, key))
    if directionZone then return directionZone, runway, direction end

    local runwayZone = zoneFromRunway(runway, key)
    if runwayZone then return runwayZone, runway, direction end

    return nil, runway, direction
end

-- ===== ATC NUI panel bridge =====
local atcRadioTarget, atcRadioAirport
local atcRadioOpen = false
local atcPos  -- saved radio placement {left,top,scale}, loaded from KVP later
local function atcAirportLabel(id)
    local ap = airportFor(id)
    return ap and (ap.label or ap.id) or id
end
local function pushAtcLog(who, text, kind)
    if not text then return end
    SendNUIMessage({ action = 'atcLog', who = who or 'ATC', text = text, kind = kind or 'atc' })
end
local function pushAtcClearance(text, emergency, readbackRequired, readbackComplete)
    SendNUIMessage({
        action = 'atcClearance',
        text = text or 'None',
        emergency = emergency and true or false,
        readbackRequired = readbackRequired and true or false,
        readbackComplete = readbackComplete and true or false
    })
end

local function atcNotify(airportId, message, notifyType)
    local airport = airportFor(airportId)
    local tower = airport and airport.tower or 'Air Traffic Control'

    lib.notify({
        title = tower,
        description = message,
        type = notifyType or 'inform'
    })

    pushAtcLog(tower, message, 'atc')
end

local function radioExchangeNotify(airport, pilotMessage, atcMessage, notifyType)
    local tower = airport and (airport.tower or airport.label) or 'Air Traffic Control'

    lib.notify({
        title = tower,
        description = ('You: %s\nATC: %s'):format(pilotMessage or 'Radio check.', atcMessage or 'Stand by.'),
        type = notifyType or 'inform',
        duration = 9000
    })

    pushAtcLog('PILOT', pilotMessage or 'Radio check.', 'pilot')
    pushAtcLog(tower, atcMessage or 'Stand by.', 'atc')
end

local function atcOnce(flightId, key, airportId, message, notifyType)
    local noticeKey = ('%s:%s'):format(flightId, key)
    if atcNotices[noticeKey] then return end

    atcNotices[noticeKey] = true
    atcNotify(airportId, message, notifyType)
end

local function firstRunwayDirectionAssignment(airport)
    if not airport then return nil end

    for runwayIndex, runway in ipairs(airport.runways or {}) do
        for _, direction in ipairs(runway.directions or {}) do
            if direction.zones and direction.zones.approachZone and direction.zones.landingZone then
                return {
                    runwayIndex = runwayIndex,
                    directionId = direction.id,
                    runway = runway,
                    direction = direction
                }
            end
        end

        if zoneFromRunway(runway, 'landingZone') or runway.zone then
            return {
                runwayIndex = runwayIndex,
                runway = runway
            }
        end
    end

    return nil
end

local function distance2D(a, b)
    if not a or not b then return nil end

    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    return math.sqrt((dx * dx) + (dy * dy))
end

local function directionReferencePoint(direction)
    if not direction then return nil end

    if direction.approachStart then return asVec3(direction.approachStart) end
    local approachCenter = zoneCenter(direction.zones and direction.zones.approachZone)
    if approachCenter then return approachCenter end
    if direction.threshold then return asVec3(direction.threshold) end
    return nil
end

local function bestRunwayDirectionAssignment(airport, coords)
    if not airport or not coords then return firstRunwayDirectionAssignment(airport) end

    local best
    local bestScore

    for runwayIndex, runway in ipairs(airport.runways or {}) do
        for _, direction in ipairs(runway.directions or {}) do
            local zones = direction.zones or {}
            if zones.approachZone and zones.landingZone then
                local reference = directionReferencePoint(direction)
                local score = distance2D(coords, reference)

                if zones.approachZone and insideZone(coords, zones.approachZone) then
                    score = (score or 0.0) * 0.1
                end

                if score and (not bestScore or score < bestScore) then
                    bestScore = score
                    best = {
                        runwayIndex = runwayIndex,
                        directionId = direction.id,
                        runway = runway,
                        direction = direction
                    }
                end
            end
        end
    end

    return best or firstRunwayDirectionAssignment(airport)
end

local function bestDepartureAssignment(airport, coords)
    if not airport then return nil end

    local best
    local bestScore

    for runwayIndex, runway in ipairs(airport.runways or {}) do
        for _, direction in ipairs(runway.directions or {}) do
            local taxiHold = matchingZone(zoneCandidates(direction, 'taxiHold')) or zoneFromRunway(runway, 'taxiHold')
            local takeoffHold = matchingZone(zoneCandidates(direction, 'takeoffHold')) or zoneFromRunway(runway, 'takeoffHold')
            local takeoffZone = matchingZone(zoneCandidates(direction, 'takeoffZone')) or zoneFromRunway(runway, 'takeoffZone')

            if taxiHold or takeoffHold or takeoffZone or runway.zone then
                local reference = zoneCenter(taxiHold or takeoffHold or takeoffZone or runwaySurfaceZone(runway))
                local score = distance2D(coords, reference) or 0.0

                if not bestScore or score < bestScore then
                    bestScore = score
                    best = {
                        airportId = airport.id,
                        runwayIndex = runwayIndex,
                        directionId = direction.id,
                        runway = runway,
                        direction = direction,
                        phase = 'taxi'
                    }
                end
            end
        end

        if not best then
            local taxiHold = zoneFromRunway(runway, 'taxiHold')
            local takeoffHold = zoneFromRunway(runway, 'takeoffHold')
            local takeoffZone = zoneFromRunway(runway, 'takeoffZone')
            if taxiHold or takeoffHold or takeoffZone or runway.zone then
                best = {
                    airportId = airport.id,
                    runwayIndex = runwayIndex,
                    runway = runway,
                    phase = 'taxi'
                }
            end
        end
    end

    return best
end

local function assignmentLabel(assignment)
    if not assignment then return 'unassigned runway' end
    if assignment.direction then return assignment.direction.label or 'assigned runway direction' end
    if assignment.runway then return assignment.runway.label or 'assigned runway' end
    return 'assigned runway'
end

local function setArrivalAssignment(flight, airport, assignment)
    if not flight or not airport or not assignment then return end

    local target = flight.temporary and aircraftArrivalAssignments or flightArrivalAssignments
    target[flight.id] = {
        airportId = airport.id,
        runwayIndex = assignment.runwayIndex,
        directionId = assignment.direction and assignment.direction.id or assignment.directionId
    }

    if flight.temporary then
        aircraftAtcStates[flight.id] = aircraftAtcStates[flight.id] or {}
        aircraftAtcStates[flight.id].phase = 'landing_cleared'
        aircraftAtcStates[flight.id].airportId = airport.id
    end
end

local function setDepartureAssignment(target, airport, assignment, phase)
    if not target or not airport or not assignment then return end

    local stored = {
        airportId = airport.id,
        runwayIndex = assignment.runwayIndex,
        directionId = assignment.direction and assignment.direction.id or assignment.directionId,
        phase = phase or assignment.phase or 'taxi'
    }

    if target.temporary then
        aircraftDepartureAssignments[target.id] = stored
        aircraftAtcStates[target.id] = aircraftAtcStates[target.id] or {}
        aircraftAtcStates[target.id].phase = stored.phase
        aircraftAtcStates[target.id].airportId = airport.id
    else
        flightRunwayAssignments[target.id] = {
            runwayIndex = stored.runwayIndex,
            directionId = stored.directionId
        }
        aircraftDepartureAssignments[target.id] = stored
    end
end

local function setPilotFlightStatus(flight, status)
    if not flight then return false end

    local success, message = lib.callback.await('partay_airlines:server:setPilotFlightStatus', false, flight.id, status)
    if not success and message then
        notify(message, 'error')
    end

    return success
end

local function atcFrequencyFor(airport, channel)
    if airport and airport.airspaceVolume and airport.airspaceVolume.frequency then
        return airport.airspaceVolume.frequency
    end

    local frequencies = Config.ATC and Config.ATC.frequencies or {}
    local airportFrequencies = airport and airport.id and frequencies[airport.id] or nil
    return airportFrequencies and (airportFrequencies[channel or 'tower'] or airportFrequencies.tower) or '122.800'
end

local function clearanceFor(target)
    return target and atcClearances[target.id] or nil
end

local function radioModeLabel(target)
    if target and target.temporary then
        return 'General Aviation'
    end

    return 'Airline Flight'
end

local function setAtcClearance(target, airport, intent, text, assignment)
    if not target or not airport then return end

    atcClearances[target.id] = {
        airportId = airport.id,
        intent = intent,
        text = text,
        runway = assignment and assignmentLabel(assignment) or nil,
        frequency = atcFrequencyFor(airport, 'tower'),
        readbackRequired = text and true or false,
        readbackComplete = false
    }

    pushAtcClearance(text, intent == 'emergency', text ~= nil, false)
end

local function aircraftTypeLabel(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 'aircraft' end

    local configuredModel = getAircraftModelName(vehicle)
    if configuredModel and Config.Aircraft[configuredModel] and Config.Aircraft[configuredModel].label then
        return Config.Aircraft[configuredModel].label
    end

    local displayName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = displayName and GetLabelText(displayName) or nil
    if label and label ~= 'NULL' then return label end
    if displayName and displayName ~= '' then return displayName end

    return 'aircraft'
end

local function cardinalDirectionFromAirport(coords, airport)
    local center = airportCenter(airport)
    if not coords or not center then return 'nearby', 0.0 end

    local dx = coords.x - center.x
    local dy = coords.y - center.y
    local distance = math.sqrt((dx * dx) + (dy * dy))
    if distance < 1.0 then return 'overhead', distance end

    local heading = (math.deg(math.atan(dx, dy)) + 360.0) % 360.0
    local labels = {
        'north', 'north-northeast', 'northeast', 'east-northeast',
        'east', 'east-southeast', 'southeast', 'south-southeast',
        'south', 'south-southwest', 'southwest', 'west-southwest',
        'west', 'west-northwest', 'northwest', 'north-northwest'
    }
    local index = math.floor((heading + 11.25) / 22.5) % 16

    return labels[index + 1], distance
end

local function intentPhrase(intent)
    if intent == 'landing' then return 'inbound for full stop landing' end
    if intent == 'touch_go' then return 'inbound for touch and go' end
    if intent == 'low_pass' then return 'requesting low pass' end
    if intent == 'transit' then return 'requesting airspace transit' end
    if intent == 'flight_following' then return 'requesting VFR flight following' end
    if intent == 'emergency' then return 'declaring emergency, requesting immediate landing' end
    if intent == 'departure' then return 'requesting taxi and departure' end
    if intent == 'takeoff' then return 'holding short, ready for takeoff' end
    return 'requesting ATC service'
end

local function sendInitialContact(target, airport, intent, vehicle, coords)
    if not target or not airport then return nil end

    local direction, distance = cardinalDirectionFromAirport(coords, airport)
    local distanceMiles = distance / 1609.34
    local altitude = coords and math.floor(coords.z + 0.5) or 0
    local speed = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and math.floor((GetEntitySpeed(vehicle) * 2.236936) + 0.5) or 0
    local heading = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and math.floor(GetEntityHeading(vehicle) + 0.5) or 0
    local aircraftType = aircraftTypeLabel(vehicle)
    local tower = airport.tower or airport.label or 'Tower'
    local callsign = target.flightNumber or (target.temporary and 'General Aviation Aircraft' or 'Aircraft')

    return ('%s, %s, %s %.1f miles %s, altitude %s ft, speed %s mph, heading %03d, %s.'):format(
        tower,
        callsign,
        aircraftType,
        distanceMiles,
        direction,
        altitude,
        speed,
        heading % 360,
        intentPhrase(intent)
    )
end

local function submitAtcIntent(target, airport, intent)
    if not target or not airport then return end

    local ped = cache.ped
    local vehicle = GetVehiclePedIsIn(ped, false)
    local coords = vehicle ~= 0 and DoesEntityExist(vehicle) and GetEntityCoords(vehicle) or GetEntityCoords(ped)
    local assignment = bestRunwayDirectionAssignment(airport, coords)
    local intentKey = ('%s:%s'):format(target.id, airport.id)
    local callsign = target.flightNumber or (target.temporary and 'General Aviation Aircraft' or 'Aircraft')

    airspaceIntent[intentKey] = intent
    airspaceReminders[intentKey] = nil
    local pilotMessage = sendInitialContact(target, airport, intent, vehicle, coords)

    if intent == 'landing' or intent == 'touch_go' or intent == 'low_pass' or intent == 'emergency' then
        if not assignment then
            radioExchangeNotify(airport, pilotMessage, ('%s, unable runway assignment. No runway is built for %s.'):format(callsign, airport.label or airport.id), 'error')
            return
        end

        setArrivalAssignment(target, airport, assignment)

        local actionText = 'radar contact. Enter approach for'
        if intent == 'touch_go' then actionText = 'radar contact. Enter pattern for touch and go' end
        if intent == 'low_pass' then actionText = 'radar contact. Low pass approved for' end
        if intent == 'emergency' then actionText = 'emergency acknowledged. Immediate landing approved for' end

        local clearance = ('%s, %s %s. Continue inbound and report final.'):format(callsign, actionText, assignmentLabel(assignment))
        setAtcClearance(target, airport, intent, clearance, assignment)
        radioExchangeNotify(airport, pilotMessage, clearance, intent == 'emergency' and 'warning' or 'success')
        return
    end

    if intent == 'departure' then
        local departureAssignment = bestDepartureAssignment(airport, coords)
        if not departureAssignment then
            radioExchangeNotify(airport, pilotMessage, ('%s, unable taxi clearance. No taxi/takeoff holds are built for %s.'):format(callsign, airport.label or airport.id), 'error')
            return
        end

        setDepartureAssignment(target, airport, departureAssignment, 'taxi')
        if not target.temporary and target.status ~= 'taxiing' and target.status ~= 'taxi_hold' and target.status ~= 'takeoff_hold' and target.status ~= 'takeoff_cleared' then
            setPilotFlightStatus(target, 'taxiing')
            activePilotFlight = lib.callback.await('partay_airlines:server:getPilotFlight', false) or activePilotFlight
        end

        local taxiHold = assignedDirectionZone(airport, 'taxiHold', departureAssignment) or airportZone(airport, 'taxiHold')
        local taxiLabel = taxiHold and (taxiHold.label or 'taxi hold') or 'the taxi hold'
        local clearance = ('%s, check-in received. Taxi to %s and hold position. Await further instructions before runway hold.'):format(callsign, taxiLabel)
        setAtcClearance(target, airport, intent, clearance, departureAssignment)
        radioExchangeNotify(airport, pilotMessage, clearance, 'inform')
        return
    end

    if intent == 'takeoff' then
        local departureAssignment = (target.temporary and aircraftDepartureAssignments[target.id]) or aircraftDepartureAssignments[target.id]
        if not departureAssignment then
            departureAssignment = bestDepartureAssignment(airport, coords)
        end

        if not departureAssignment then
            radioExchangeNotify(airport, pilotMessage, ('%s, unable takeoff clearance. No runway hold is built for %s.'):format(callsign, airport.label or airport.id), 'error')
            return
        end

        local takeoffHold = assignedDirectionZone(airport, 'takeoffHold', departureAssignment) or airportZone(airport, 'takeoffHold')
        if takeoffHold and not insideZone(coords, takeoffHold) then
            setDepartureAssignment(target, airport, departureAssignment, 'takeoff_hold')
            radioExchangeNotify(airport, pilotMessage, ('%s, check-in received. Taxi to %s, line up and wait. Hold position until cleared for takeoff.'):format(callsign, takeoffHold.label or 'takeoff hold'), 'warning')
            return
        end

        setDepartureAssignment(target, airport, departureAssignment, 'takeoff_cleared')
        local clearance = ('%s, ready call received. Cleared for takeoff from %s. Maintain runway heading until clear of the field.'):format(callsign, assignmentLabel(departureAssignment))
        setAtcClearance(target, airport, intent, clearance, departureAssignment)
        radioExchangeNotify(airport, pilotMessage, clearance, 'success')
        return
    end

    if intent == 'flight_following' then
        local clearance = ('%s, radar contact. VFR flight following approved, maintain safe altitude.'):format(callsign)
        setAtcClearance(target, airport, intent, clearance)
        radioExchangeNotify(airport, pilotMessage, clearance, 'success')
        return
    end

    local clearance = ('%s, radar contact. Transit approved through %s airspace. Maintain safe altitude.'):format(callsign, airport.label or airport.id)
    setAtcClearance(target, airport, intent, clearance)
    radioExchangeNotify(airport, pilotMessage, clearance, 'inform')
end

local openAircraftRadio

local function nearestAirportByDistance(coords)
    local nearest
    local nearestDistance

    for _, airport in ipairs(allAirports()) do
        normalizeKnownAirport(airport)

        local distance = airportGroundDistance(coords, airport)
        if distance and (not nearestDistance or distance < nearestDistance) then
            nearest = airport
            nearestDistance = distance
        end
    end

    return nearest
end

currentPilotAircraft = function()
    local ped = cache.ped
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return nil
    end

    if isAircraftVehicle(vehicle) then
        return vehicle
    end

    return nil
end

local function currentAtcContact()
    local vehicle = currentPilotAircraft()
    if not vehicle then return nil, nil end

    local target = currentAtcTarget(vehicle, activePilotFlight)
    if not target then return nil, nil end

    local coords = GetEntityCoords(vehicle)
    local airborneEnough = getGroundDistance(vehicle) >= ((Config.ATC or {}).intentMinimumAirborneAltitude or 30.0)
    local nearestAirport = airborneEnough and nearestContactAirport(coords, target.temporary and nil or target.departure) or nil
    nearestAirport = nearestAirport or nearestAirportByDistance(coords)

    return target, nearestAirport
end

local function openAircraftRadioForCurrentAircraft()
    local vehicle = currentPilotAircraft()
    if not vehicle then
        notify('You need to be piloting an aircraft to use the aircraft radio.', 'error')
        return
    end

    local target, nearestAirport = currentAtcContact()
    if not target then
        notify('Aircraft radio could not identify this aircraft.', 'error')
        return
    end

    if not nearestAirport then
        notify('No ATC facility is available nearby. Make sure airports are loaded or move closer to an airport.', 'error')
        return
    end

    notify(('Opening aircraft radio: %s %s'):format(nearestAirport.tower or nearestAirport.label or 'ATC', atcFrequencyFor(nearestAirport, 'tower')), 'inform')
    openAircraftRadio(target, nearestAirport)
end

openAircraftRadio = function(target, airport)
    if not target or not airport then return end

    local clearance = clearanceFor(target)
    local frequency = atcFrequencyFor(airport, 'tower')
    local vehicle = currentPilotAircraft()
    local onGround = vehicle and getGroundDistance(vehicle) < ((Config.ATC or {}).intentMinimumAirborneAltitude or 30.0)
    local mode = radioModeLabel(target)
    local status = onGround and 'On ground / ready for ground control' or (target.temporary and 'VFR aircraft' or 'Airline flight')
    airspacePromptOpen = true

    -- ATC NUI panel.
    atcRadioTarget = target
    atcRadioAirport = airport
    local flight = nil
    if not target.temporary then
        flight = {
            callsign = target.flightNumber,
            airline = Config.Airline and Config.Airline.name or nil,
            origin = atcAirportLabel(target.departure),
            dest = atcAirportLabel(target.arrival),
            aircraft = target.aircraftLabel or aircraftTypeLabel(vehicle),
            gate = target.gate,
            status = target.status,
            statusLabel = target.status,
            booked = target.ticketed,
            seats = target.seats,
            boarded = target.boarded
        }
    end
    SendNUIMessage({
        action = 'atcOpen',
        facility = airport.tower or airport.label or 'ATC',
        frequency = frequency,
        mode = mode,
        status = status,
        onGround = onGround and true or false,
        emergency = (clearance and clearance.intent == 'emergency') or false,
        clearance = {
            text = clearance and clearance.text or 'None',
            emergency = (clearance and clearance.intent == 'emergency') or false,
            readbackRequired = clearance and clearance.readbackRequired or false,
            readbackComplete = clearance and clearance.readbackComplete or false
        },
        flight = flight,
        pos = atcPos
    })
    atcRadioOpen = true
    SetNuiFocus(true, true)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(true) end
end

RegisterNUICallback('atcIntent', function(data, cb)
    cb({})
    local intent = data and data.intent
    if not intent or not atcRadioTarget or not atcRadioAirport then return end
    submitAtcIntent(atcRadioTarget, atcRadioAirport, intent)
end)

RegisterNUICallback('atcReadback', function(data, cb)
    cb({})
    if not atcRadioTarget then return end
    local clearance = clearanceFor(atcRadioTarget)
    local callsign = atcRadioTarget.flightNumber or (atcRadioTarget.temporary and 'General Aviation' or 'Aircraft')
    if clearance and clearance.text then
        clearance.readbackComplete = true
        pushAtcLog(callsign, ('%s, %s'):format(clearance.text, callsign), 'pilot')
        pushAtcClearance(clearance.text, clearance.intent == 'emergency', clearance.readbackRequired, true)
        notify(('Readback sent: %s'):format(clearance.text), 'inform')
    else
        pushAtcLog(callsign, 'Standing by.', 'pilot')
    end
end)

RegisterNUICallback('atcClose', function(data, cb)
    cb({})
    airspacePromptOpen = false
    atcRadioOpen = false
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(false, false)
end)

local function atcRadioControlLock()
    while true do
        if atcRadioOpen then
            Wait(0)
            DisableControlAction(0, 1, true) -- LOOK_LR
            DisableControlAction(0, 2, true) -- LOOK_UD
            DisableControlAction(0, 106, true) -- VEH_MOUSE_CONTROL_OVERRIDE
            DisableControlAction(0, 122, true) -- VEH_FLY_MOUSE_CONTROL_OVERRIDE
        else
            Wait(250)
        end
    end
end

local function getGateBoardingPoint(gate)
    local spawn = gate and gate.aircraftSpawn
    if spawn then
        return {
            coords = vec3(spawn.x, spawn.y, spawn.z),
            radius = gate.aircraftBoardingRadius or 25.0
        }
    end

    return {
        coords = gate.coords,
        radius = gate.aircraftBoardingRadius or gate.radius or 25.0
    }
end

local function aircraftAtGate(flight, gate)
    if not flight.aircraftNetId then return false, 'No aircraft assigned to this flight yet.' end

    local vehicle = entityFromNetId(flight.aircraftNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false, 'The aircraft is not available at this gate.'
    end

    local boardingPoint = getGateBoardingPoint(gate)
    if not insideZone(GetEntityCoords(vehicle), boardingPoint) then
        return false, 'Aircraft must be parked at the gate boarding spot before boarding passes can be scanned.'
    end

    return true, vehicle
end

local function seatIndexFromSeatLabel(seat)
    local number = tonumber(tostring(seat or ''):match('%d+')) or 1
    return math.max(number - 1, 0)
end

local function boardPassengerIntoAircraft(result)
    if not result or not result.aircraftNetId then return end

    local vehicle = entityFromNetId(result.aircraftNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        notify('Boarding accepted, but the aircraft is not available. Ask airline staff to respawn it.', 'error')
        return
    end

    local ped = cache.ped
    local doorCoords = GetOffsetFromEntityInWorldCoords(vehicle, -2.0, -4.0, 0.0)
    local seatIndex = seatIndexFromSeatLabel(result.seat)

    TaskGoStraightToCoord(ped, doorCoords.x, doorCoords.y, doorCoords.z, 1.0, 8000, GetEntityHeading(vehicle), 0.4)

    local timeout = GetGameTimer() + 8500
    while #(GetEntityCoords(ped) - doorCoords) > 2.5 and GetGameTimer() < timeout do
        Wait(250)
    end

    TaskEnterVehicle(ped, vehicle, 10000, seatIndex, 1.0, 1, 0)

    timeout = GetGameTimer() + 9000
    while not IsPedInVehicle(ped, vehicle, false) and GetGameTimer() < timeout do
        Wait(250)
    end

    if not IsPedInVehicle(ped, vehicle, false) then
        TaskWarpPedIntoVehicle(ped, vehicle, seatIndex)
    end
end

local function showBoardingPass(metadata)
    if not metadata or not metadata.flightNumber then
        notify('This boarding pass has no readable flight metadata.', 'error')
        return
    end

    lib.alertDialog({
        header = ('Boarding Pass %s'):format(metadata.flightNumber),
        content = ('Airline: %s\nPassenger: %s\nClass: %s\nRoute: %s to %s\nGate: %s\nSeat: %s\nBoards: %s\nDeparts: %s'):format(
            metadata.airline or Config.Airline.name,
            metadata.passengerName or 'Unknown',
            metadata.ticketClass or 'unknown',
            metadata.departure or 'TBD',
            metadata.destination or 'TBD',
            metadata.gate or 'TBD',
            metadata.seat or 'TBD',
            formatClock(metadata.boardingTime),
            formatClock(metadata.departureTime)
        ),
        centered = true,
        cancel = false
    })
end

RegisterNetEvent('partay_airlines:client:showBoardingPass', showBoardingPass)

local function openClassMenu(flight)
    local options = {}
    local route = Config.Routes[flight.routeId]

    for _, className in ipairs(sortedKeys(Config.TicketClasses)) do
        local classConfig = Config.TicketClasses[className]
        local allowed = route and route.allowedTicketClasses[className]

        if allowed then
            options[#options + 1] = {
                title = classConfig.label,
                description = ('$%s - Gate %s - %s seats open%s'):format(
                    classPrice(flight.routeId, className),
                    flight.gate,
                    flight.seatsAvailable,
                    routeBadges(flight) ~= '' and (' | ' .. routeBadges(flight)) or ''
                ),
                icon = className == 'basic' and 'ticket' or 'star',
                onSelect = function()
                    local success, message = lib.callback.await('partay_airlines:server:buyTicket', false, flight.id, className)
                    if success then
                        notify('Boarding pass issued.', 'success')
                    else
                        notify(message or 'Could not buy ticket.', 'error')
                    end
                end
            }
        end
    end

    lib.registerContext({
        id = 'partay_airlines_ticket_classes',
        title = flight.flightNumber .. ' Ticket Class',
        menu = 'partay_airlines_flights',
        options = options
    })

    lib.showContext('partay_airlines_ticket_classes')
end

local function openTicketDesk()
    local flights = lib.callback.await('partay_airlines:server:getFlights', false) or {}
    local options = {}

    for _, flight in ipairs(flights) do
        if flight.seatsAvailable > 0 and (flight.status == 'scheduled' or flight.status == 'awaiting_pilot' or flight.status == 'boarding_soon' or flight.status == 'boarding' or flight.status == 'final_call' or flight.status == 'delayed') then
            options[#options + 1] = {
                title = ('%s - %s'):format(flight.flightNumber, flight.routeLabel),
                description = ('Gate %s | %s | %s seats open | Departs %s%s'):format(
                    flight.gate,
                    flight.status,
                    flight.seatsAvailable,
                    formatClock(flight.departureTime),
                    routeBadges(flight) ~= '' and (' | ' .. routeBadges(flight)) or ''
                ),
                icon = 'plane',
                onSelect = function()
                    openClassMenu(flight)
                end
            }
        end
    end

    if #options == 0 then
        options[1] = {
            title = 'No passenger flights available',
            description = 'Flights require a real pilot before departure.',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'partay_airlines_flights',
        title = 'No Love Lost Airways',
        options = options
    })

    lib.showContext('partay_airlines_flights')
end

local function selectAircraftForRoute(routeId)
    local route = Config.Routes[routeId]
    local options = {}

    for _, aircraftModel in ipairs(route.allowedAircraft or {}) do
        local aircraft = Config.Aircraft[aircraftModel]
        if aircraft then
            options[#options + 1] = {
                title = aircraft.label,
                description = ('%s seats'):format(aircraft.seats),
                icon = 'plane',
                onSelect = function()
                    local input = lib.inputDialog('Schedule Flight', {
                        {
                            type = 'number',
                            label = 'Minutes until departure',
                            default = 15,
                            min = 1,
                            max = 240,
                            required = true
                        }
                    })

                    if not input then return end

                    local success, message = lib.callback.await('partay_airlines:server:createFlight', false, {
                        routeId = routeId,
                        aircraftModel = aircraftModel,
                        departureMinutes = input[1]
                    })

                    if success then
                        notify('Flight scheduled.', 'success')
                    else
                        notify(message or 'Could not schedule flight.', 'error')
                    end
                end
            }
        end
    end

    lib.registerContext({
        id = 'partay_airlines_aircraft_select',
        title = 'Select Aircraft',
        menu = 'partay_airlines_route_select',
        options = options
    })

    lib.showContext('partay_airlines_aircraft_select')
end

local function openCreateFlight()
    local routes = lib.callback.await('partay_airlines:server:getRoutes', false) or {}
    local options = {}

    for _, route in ipairs(routes) do
        options[#options + 1] = {
            title = route.label,
            description = ('Gate %s | Base fare $%s'):format(route.gate, route.basePrice),
            icon = 'route',
            onSelect = function()
                selectAircraftForRoute(route.id)
            end
        }
    end

    if #options == 0 then
        options[1] = {
            title = 'No routes available',
            description = 'You need airline duty and the configured grade.',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'partay_airlines_route_select',
        title = 'Schedule Airline Flight',
        options = options
    })

    lib.showContext('partay_airlines_route_select')
end

local function claimFlight(flight)
    local vehicle, spawnError = spawnFlightAircraft(flight)
    if not vehicle then
        notify(spawnError or 'Could not spawn aircraft.', 'error')
        return
    end

    local aircraftModel = flight.aircraftModel
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local success, message = lib.callback.await('partay_airlines:server:claimFlight', false, flight.id, netId, aircraftModel)

    if success then
        notify(('Spawned aircraft and claimed %s.'):format(flight.flightNumber), 'success')
        activePilotFlight = flight
        activePilotFlight.aircraftNetId = netId
        activePilotFlight.aircraftModel = aircraftModel
    else
        DeleteEntity(vehicle)
        notify(message or 'Could not claim flight.', 'error')
    end
end

local function setFlightStatus(flight, status, label)
    local success, message = lib.callback.await('partay_airlines:server:setFlightStatus', false, flight.id, status)
    if success then
        if label then notify(label, 'success') end
        local latest = lib.callback.await('partay_airlines:server:getPilotFlight', false)
        activePilotFlight = latest or activePilotFlight
        return true
    else
        notify(message or 'Could not update flight.', 'error')
        return false
    end
end

local function completeFlight(flight)
    local success, result = lib.callback.await('partay_airlines:server:completeFlight', false, flight.id)
    if not success then
        notify(result or 'Could not complete flight.', 'error')
        return
    end

    notify(('Flight complete. Score %s%%, %s passengers, pilot pay $%s.'):format(result.score, result.completedPassengers, result.pilotPayout), 'success')
    flightRunwayAssignments[flight.id] = nil
    flightArrivalAssignments[flight.id] = nil
    flightArrivalGates[flight.id] = nil
    pendingFlightGateAssignments[flight.id] = nil
    clearNavigationPrefix(('dep:%s'):format(flight.id))
    clearNavigationPrefix(('arr:%s'):format(flight.id))
    clearNavigationPrefix(('gate:%s'):format(flight.id))
    activePilotFlight = nil
end

local function finalTakeoffCheck(flight)
    local airport = airportFor(flight.departure)
    local vehicle = flight.aircraftNetId and entityFromNetId(flight.aircraftNetId) or GetVehiclePedIsIn(cache.ped, false)
    local takeoffHold, runway, direction, runwayIndex
    if vehicle ~= 0 then
        takeoffHold, runway, direction, runwayIndex = airportZone(airport, 'takeoffHold', GetEntityCoords(vehicle))
    else
        takeoffHold, runway, direction, runwayIndex = airportZone(airport, 'takeoffHold')
    end

    if not takeoffHold then
        notify('Departure airport is missing a runway hold zone.', 'error')
        return
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= cache.ped then
        notify('You must be in the pilot seat for final departure check.', 'error')
        return
    end

    if not insideZone(GetEntityCoords(vehicle), takeoffHold) then
        notify(('Taxi to %s before requesting departure clearance.'):format(takeoffHold.label), 'error')
        return
    end

    local confirmed = lib.alertDialog({
        header = 'Final Departure Check',
        content = 'ATC requires doors secured, passengers seated, runway heading confirmed, and aircraft ready for departure.',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Ready for Takeoff',
            cancel = 'Hold Position'
        }
    })

    if confirmed ~= 'confirm' then
        atcNotify(flight.departure, ('%s, hold short and advise when ready.'):format(flight.flightNumber), 'inform')
        return
    end

    if setFlightStatus(flight, 'takeoff_cleared') then
        if runwayIndex and direction then
            flightRunwayAssignments[flight.id] = { runwayIndex = runwayIndex, directionId = direction.id }
        end
        local runwayLabel = direction and (direction.label or 'assigned direction') or runway and (runway.label or 'assigned runway') or 'assigned runway'
        atcNotify(flight.departure, ('%s, cleared for takeoff from %s. Maintain runway heading until clear of the field.'):format(flight.flightNumber, runwayLabel), 'success')
    end
end

local function managePilotFlight(flight)
    local options = {
        {
            title = ('%s - %s'):format(flight.flightNumber, flight.routeLabel),
            description = ('Status: %s | Boarded: %s | Completed: %s'):format(flight.status, flight.boarded, flight.completed),
            disabled = true
        }
    }

    if flight.status == 'boarding_soon' or flight.status == 'delayed' then
        options[#options + 1] = {
            title = 'Open Boarding',
            icon = 'door-open',
            onSelect = function()
                setFlightStatus(flight, 'boarding')
                atcNotify(flight.departure, ('%s boarding is open at Gate %s.'):format(flight.flightNumber, flight.gate), 'success')
            end
        }
    end

    if flight.status == 'boarding' then
        options[#options + 1] = {
            title = 'Final Call',
            icon = 'bell',
            onSelect = function()
                setFlightStatus(flight, 'final_call')
                atcNotify(flight.departure, ('%s final boarding call. Gate %s closing soon.'):format(flight.flightNumber, flight.gate), 'inform')
            end
        }
    end

    if flight.status == 'boarding' or flight.status == 'final_call' then
        options[#options + 1] = {
            title = 'Close Boarding',
            icon = 'door-closed',
            onSelect = function()
                setFlightStatus(flight, 'boarding_closed')
                atcNotify(flight.departure, ('%s boarding closed. Contact ground when ready to taxi.'):format(flight.flightNumber), 'inform')
            end
        }
    end

    if flight.status == 'boarding_closed' then
        options[#options + 1] = {
            title = 'Contact Ground: Start Taxi',
            icon = 'plane-departure',
            onSelect = function()
                setFlightStatus(flight, 'taxiing')
                atcNotify(flight.departure, ('%s, taxi to the intermediate hold point. Hold short and await runway clearance.'):format(flight.flightNumber), 'inform')
            end
        }
    end

    if flight.status == 'taxi_hold' then
        options[#options + 1] = {
            title = 'Request Runway Hold',
            icon = 'tower-broadcast',
            onSelect = function()
                setFlightStatus(flight, 'takeoff_hold')
                atcNotify(flight.departure, ('%s, continue taxi to runway hold. Hold short for final departure check.'):format(flight.flightNumber), 'inform')
            end
        }
    end

    if flight.status == 'takeoff_hold' then
        options[#options + 1] = {
            title = 'Final Check / Request Takeoff',
            icon = 'clipboard-check',
            onSelect = function() finalTakeoffCheck(flight) end
        }
    end

    if flight.status ~= 'completed' and flight.status ~= 'cancelled' and flight.status ~= 'failed' then
        options[#options + 1] = {
            title = 'Delay Flight',
            icon = 'clock',
            onSelect = function() setFlightStatus(flight, 'delayed', 'Flight delayed.') end
        }
    end

    if flight.status == 'deboarding' then
        options[#options + 1] = {
            title = 'Complete Flight',
            icon = 'circle-check',
            onSelect = function() completeFlight(flight) end
        }
    end

    options[#options + 1] = {
            title = 'Cancel Flight',
            icon = 'ban',
            onSelect = function() setFlightStatus(flight, 'cancelled', 'Flight cancelled.') end
    }

    lib.registerContext({
        id = 'partay_airlines_manage_flight',
        title = 'Pilot Dispatch',
        options = options
    })

    lib.showContext('partay_airlines_manage_flight')
end

local function openClaimFlight()
    local flights = lib.callback.await('partay_airlines:server:getFlights', false) or {}
    local options = {}

    for _, flight in ipairs(flights) do
        if not flight.pilotAssigned and flight.status ~= 'cancelled' then
            options[#options + 1] = {
                title = ('%s - %s'):format(flight.flightNumber, flight.routeLabel),
                description = ('Gate %s | Aircraft %s | %s tickets'):format(flight.gate, flight.aircraftLabel, flight.ticketed),
                icon = 'plane',
                onSelect = function()
                    claimFlight(flight)
                end
            }
        end
    end

    if #options == 0 then
        options[1] = {
            title = 'No unclaimed flights',
            description = 'Schedule a flight or wait for one to be created.',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'partay_airlines_claim_flight',
        title = 'Claim Flight',
        options = options
    })

    lib.showContext('partay_airlines_claim_flight')
end

local dispatchTabletOpen = false

local function sendDispatchTabletData()
    local data = lib.callback.await('partay_airlines:server:getDispatchData', false)
    if data and data.currentFlight then
        activePilotFlight = data.currentFlight
    end

    SendNUIMessage({
        action = 'businessTabletData',
        data = data or {}
    })

    return data
end

local function closeDispatchTablet()
    dispatchTabletOpen = false
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SendNUIMessage({ action = 'businessTabletClose' })
end

local function openPilotTerminalMenu()
    local current = lib.callback.await('partay_airlines:server:getPilotFlight', false)
    if current then
        activePilotFlight = current
    end

    local options = {
        {
            title = 'Schedule Flight',
            description = 'Create a player-operated route from config.',
            icon = 'calendar-plus',
            onSelect = openCreateFlight
        },
        {
            title = 'Claim Flight',
            description = 'Assign yourself and your current aircraft.',
            icon = 'plane',
            onSelect = openClaimFlight
        }
    }

    if current then
        options[#options + 1] = {
            title = 'Manage Claimed Flight',
            description = ('%s | %s'):format(current.flightNumber, current.status),
            icon = 'tablet',
            onSelect = function()
                managePilotFlight(current)
            end
        }
    end

    lib.registerContext({
        id = 'partay_airlines_pilot_terminal',
        title = 'No Love Lost Airline Ops',
        options = options
    })

    lib.showContext('partay_airlines_pilot_terminal')
end

local function openPilotTerminal(terminal)
    if not (Config.DispatchTablet and Config.DispatchTablet.enabled) then
        openPilotTerminalMenu()
        return
    end

    local data = sendDispatchTabletData()
    dispatchTabletOpen = true
    SetNuiFocus(true, true)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SendNUIMessage({
        action = Config.DispatchTablet.nuiAction or 'businessTabletOpen',
        data = data or {},
        terminal = terminal
    })
end

RegisterNUICallback('businessTabletClose', function(_, cb)
    cb({})
    closeDispatchTablet()
end)

RegisterNUICallback('businessTabletRefresh', function(_, cb)
    cb(sendDispatchTabletData() or {})
end)

RegisterNUICallback('businessTabletCreateFlight', function(data, cb)
    local success, result = lib.callback.await('partay_airlines:server:createFlight', false, {
        routeId = data and data.routeId,
        aircraftModel = data and data.aircraftModel,
        departureMinutes = data and data.departureMinutes
    })

    cb({ success = success == true, message = success and 'Flight scheduled.' or result, flightId = success and result or nil })
    if success then
        notify('Flight scheduled.', 'success')
        sendDispatchTabletData()
    else
        notify(result or 'Could not schedule flight.', 'error')
    end
end)

RegisterNUICallback('businessTabletClaimFlight', function(data, cb)
    local flightId = data and tonumber(data.flightId)
    if not flightId then
        cb({ success = false, message = 'Missing flight ID.' })
        return
    end

    local flights = lib.callback.await('partay_airlines:server:getFlights', false) or {}
    local selected
    for _, flight in ipairs(flights) do
        if tonumber(flight.id) == flightId then
            selected = flight
            break
        end
    end

    if not selected then
        cb({ success = false, message = 'Flight not found.' })
        return
    end

    local vehicle, spawnError = spawnFlightAircraft(selected)
    if not vehicle then
        cb({ success = false, message = spawnError or 'Could not spawn aircraft.' })
        notify(spawnError or 'Could not spawn aircraft.', 'error')
        return
    end

    local aircraftModel = selected.aircraftModel
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local success, message = lib.callback.await('partay_airlines:server:claimFlight', false, selected.id, netId, aircraftModel)

    if success then
        activePilotFlight = selected
        activePilotFlight.aircraftNetId = netId
        activePilotFlight.aircraftModel = aircraftModel
        notify(('Spawned aircraft and claimed %s.'):format(selected.flightNumber), 'success')
        cb({ success = true, message = 'Flight claimed.', aircraftNetId = netId })
        sendDispatchTabletData()
    else
        DeleteEntity(vehicle)
        notify(message or 'Could not claim flight.', 'error')
        cb({ success = false, message = message or 'Could not claim flight.' })
    end
end)

RegisterNUICallback('businessTabletSetFlightStatus', function(data, cb)
    local flightId = data and tonumber(data.flightId)
    local status = data and data.status
    if not flightId or not status then
        cb({ success = false, message = 'Missing flight status data.' })
        return
    end

    local success, message = lib.callback.await('partay_airlines:server:setFlightStatus', false, flightId, status)
    cb({ success = success == true, message = message })

    if success then
        activePilotFlight = lib.callback.await('partay_airlines:server:getPilotFlight', false) or activePilotFlight
        sendDispatchTabletData()
    else
        notify(message or 'Could not update flight.', 'error')
    end
end)

RegisterNUICallback('businessTabletCompleteFlight', function(data, cb)
    local flightId = data and tonumber(data.flightId)
    if not flightId then
        cb({ success = false, message = 'Missing flight ID.' })
        return
    end

    local success, result = lib.callback.await('partay_airlines:server:completeFlight', false, flightId)
    if success then
        flightRunwayAssignments[flightId] = nil
        flightArrivalAssignments[flightId] = nil
        flightArrivalGates[flightId] = nil
        pendingFlightGateAssignments[flightId] = nil
        clearNavigationPrefix(('dep:%s'):format(flightId))
        clearNavigationPrefix(('arr:%s'):format(flightId))
        clearNavigationPrefix(('gate:%s'):format(flightId))
        activePilotFlight = nil
        notify(('Flight complete. Score %s%%, %s passengers, pilot pay $%s.'):format(result.score, result.completedPassengers, result.pilotPayout), 'success')
        cb({ success = true, result = result })
        sendDispatchTabletData()
    else
        notify(result or 'Could not complete flight.', 'error')
        cb({ success = false, message = result or 'Could not complete flight.' })
    end
end)

local function openBoardingGate(gate)
    local flights = lib.callback.await('partay_airlines:server:getFlights', false) or {}
    local options = {}

    for _, flight in ipairs(flights) do
        if flight.gate == gate.gate and (flight.status == 'boarding' or flight.status == 'final_call') then
            options[#options + 1] = {
                title = ('Board %s'):format(flight.flightNumber),
                description = ('%s | %s boarded | Aircraft must be parked at gate'):format(flight.routeLabel, flight.boarded),
                icon = 'ticket',
                onSelect = function()
                    local aircraftReady, vehicleOrMessage = aircraftAtGate(flight, gate)
                    if not aircraftReady then
                        notify(vehicleOrMessage, 'error')
                        return
                    end

                    local success, result = lib.callback.await('partay_airlines:server:boardFlight', false, flight.id, gate.gate)
                    if success then
                        notify(('Boarding pass scanned for %s. Proceeding to seat %s.'):format(result.flightNumber, result.seat or 'assigned'), 'success')
                        boardPassengerIntoAircraft(result)
                    else
                        notify(result or 'Boarding denied.', 'error')
                    end
                end
            }
        end
    end

    if #options == 0 then
        options[1] = {
            title = 'No flights boarding at this gate',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'partay_airlines_boarding_gate',
        title = gate.label,
        options = options
    })

    lib.showContext('partay_airlines_boarding_gate')
end

local function openCustomsDesk(customs)
    local flights = lib.callback.await('partay_airlines:server:getFlights', false) or {}
    local options = {}

    for _, flight in ipairs(flights) do
        local requirements = flight.requirements or {}
        if flight.departure == customs.airport and requirements.customsClearance and flight.status ~= 'cancelled' and flight.status ~= 'completed' and flight.status ~= 'failed' then
            options[#options + 1] = {
                title = ('Clear Customs: %s'):format(flight.flightNumber),
                description = ('%s | Gate %s | Passport required'):format(flight.routeLabel, flight.gate),
                icon = 'passport',
                onSelect = function()
                    local success, result = lib.callback.await('partay_airlines:server:clearCustoms', false, flight.id)
                    if success then
                        notify(result or 'Customs cleared.', 'success')
                    else
                        notify(result or 'Customs denied.', 'error')
                    end
                end
            }
        end
    end

    if #options == 0 then
        options[1] = {
            title = 'No international departures available',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'partay_airlines_customs',
        title = customs.label,
        options = options
    })

    lib.showContext('partay_airlines_customs')
end

local function registerTargets()
    for _, desk in ipairs(Config.Locations.ticketDesks) do
        exports.ox_target:addSphereZone({
            coords = desk.coords,
            radius = desk.radius or 1.5,
            debug = Config.Debug,
            options = {
                {
                    name = 'partay_airlines_ticket_' .. desk.id,
                    label = 'Book Airline Ticket',
                    icon = 'fa-solid fa-ticket',
                    onSelect = openTicketDesk
                }
            }
        })
    end

    for _, terminal in ipairs(Config.Locations.pilotTerminals) do
        exports.ox_target:addSphereZone({
            coords = terminal.coords,
            radius = terminal.radius or 1.5,
            debug = Config.Debug,
            options = {
                {
                    name = 'partay_airlines_dispatch_' .. terminal.id,
                    label = 'Airline Dispatch',
                    icon = 'fa-solid fa-plane',
                    groups = Config.JobName,
                    onSelect = function()
                        openPilotTerminal(terminal)
                    end
                }
            }
        })
    end

    for _, customs in ipairs(Config.Locations.customsDesks or {}) do
        exports.ox_target:addSphereZone({
            coords = customs.coords,
            radius = customs.radius or 1.8,
            debug = Config.Debug,
            options = {
                {
                    name = 'partay_airlines_customs_' .. customs.id,
                    label = 'Clear International Customs',
                    icon = 'fa-solid fa-passport',
                    onSelect = function()
                        openCustomsDesk(customs)
                    end
                }
            }
        })
    end

    for _, gate in ipairs(Config.Locations.boardingGates) do
        exports.ox_target:addSphereZone({
            coords = gate.coords,
            radius = gate.radius or 2.5,
            debug = Config.Debug,
            options = {
                {
                    name = 'partay_airlines_gate_' .. gate.id,
                    label = 'Scan Boarding Pass',
                    icon = 'fa-solid fa-qrcode',
                    onSelect = function()
                        openBoardingGate(gate)
                    end
                }
            }
        })
    end
end

getGroundDistance = function(vehicle)
    local coords = GetEntityCoords(vehicle)
    local hasGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, false)
    if not hasGround then return coords.z end
    return coords.z - groundZ
end

local function zoneBaseAltitude(coords, zone, fallbackVehicle)
    if zone and zone.baseZ then
        return coords.z - zone.baseZ
    end

    if zone and zone.glideSlope and zone.glideSlope.threshold then
        return coords.z - zone.glideSlope.threshold.z
    end

    if zone and zone.points and zone.points[1] then
        return coords.z - zone.points[1].z
    end

    if fallbackVehicle and fallbackVehicle ~= 0 and DoesEntityExist(fallbackVehicle) then
        return getGroundDistance(fallbackVehicle)
    end

    return coords.z
end

local function glideAllowedAltitude(coords, zone)
    local glide = zone and zone.glideSlope
    if not glide or not glide.threshold or not glide.axis then
        return zone and zone.altitudeMax
    end

    local threshold = glide.threshold
    local axis = glide.axis
    local dx = coords.x - threshold.x
    local dy = coords.y - threshold.y
    local distanceFromThreshold = math.max(0.0, -((dx * axis.x) + (dy * axis.y)))
    local progress = math.min(distanceFromThreshold / math.max(glide.length or 1.0, 1.0), 1.0)
    local thresholdAltitude = glide.thresholdAltitude or Config.Tracking.approachAltitude or 120.0
    local outerAltitude = glide.outerAltitude or zone.altitudeMax or Config.Tracking.approachAltitude or 900.0

    return thresholdAltitude + ((outerAltitude - thresholdAltitude) * progress)
end

local function runwayVacatedForPendingGate(pending, coords)
    if not pending then return false end
    if not pending.exitZone then return true end

    return not insideZone2d(coords, pending.exitZone)
end

local function gateLabelFromAssignment(pending)
    if not pending then return 'arrival ramp' end
    return pending.gateLabel or 'arrival ramp'
end

local function activateGateAssignment(prefix, gateZone)
    clearNavigationPrefix(('gate:%s'):format(prefix))

    local gateCoords = gateZone and asVec3(gateZone.coords)
    if gateCoords then
        SetNewWaypoint(gateCoords.x, gateCoords.y)
    end
end

local function assignFlightGateAfterRunwayExit(flight, airport, coords)
    local pending = flight and pendingFlightGateAssignments[flight.id] or nil
    if not pending or not runwayVacatedForPendingGate(pending, coords) then return false end

    pendingFlightGateAssignments[flight.id] = nil
    flightArrivalGates[flight.id] = pending.gateZone
    activateGateAssignment(flight.id, pending.gateZone)
    atcNotify(airport.id, ('%s, runway vacated. Taxi to %s for deboarding.'):format(flight.flightNumber, gateLabelFromAssignment(pending)), 'success')
    return true
end

local function assignAircraftGateAfterRunwayExit(aircraftKey, airport, callsign, coords)
    local pending = aircraftKey and pendingAircraftGateAssignments[aircraftKey] or nil
    if not pending or not runwayVacatedForPendingGate(pending, coords) then return false end

    pendingAircraftGateAssignments[aircraftKey] = nil
    aircraftArrivalGates[aircraftKey] = pending.gateZone
    activateGateAssignment(aircraftKey, pending.gateZone)
    atcNotify(airport.id, ('%s, runway vacated. Taxi to %s.'):format(callsign, gateLabelFromAssignment(pending)), 'success')
    return true
end

local function trackPilotFlight()
    while true do
        Wait(Config.Tracking.tickMs)

        if not activePilotFlight then
            activePilotFlight = lib.callback.await('partay_airlines:server:getPilotFlight', false)
        end

        local flight = activePilotFlight
        if flight then
            local departureAirport = airportFor(flight.departure)
            local arrivalAirport = airportFor(flight.arrival)
            if not departureAirport or not arrivalAirport then
                activePilotFlight = nil
            else
                local ped = cache.ped
                local vehicle = flight.aircraftNetId and entityFromNetId(flight.aircraftNetId) or GetVehiclePedIsIn(ped, false)

                if vehicle ~= 0 and DoesEntityExist(vehicle) then
                    local coords = GetEntityCoords(vehicle)
                    local speed = GetEntitySpeed(vehicle)
                    local groundDistance = getGroundDistance(vehicle)
                    local driverIsPilot = GetPedInVehicleSeat(vehicle, -1) == ped
                    local holdMs = ((Config.ATC and Config.ATC.holdShortSeconds) or 5) * 1000

                    local taxiHold, taxiRunway, taxiDirection, taxiRunwayIndex = airportZone(departureAirport, 'taxiHold', coords)
                    local takeoffHold, takeoffRunway, takeoffDirection, takeoffRunwayIndex = airportZone(departureAirport, 'takeoffHold', coords)
                    local assignment = flightRunwayAssignments[flight.id]
                    local takeoffZone, departureRunway, departureDirection = assignedDirectionZone(departureAirport, 'takeoffZone', assignment)
                    if not takeoffZone then takeoffZone, departureRunway, departureDirection = airportZone(departureAirport, 'takeoffZone', coords) end
                    local arrivalAssignment = flightArrivalAssignments[flight.id]
                    local approachZone, approachRunway, approachDirection = assignedRunwayZone(arrivalAirport, 'approachZone', arrivalAssignment)
                    local landingZone, landingRunway, landingDirection = assignedRunwayZone(arrivalAirport, 'landingZone', arrivalAssignment)
                    landingRunway = landingRunway or approachRunway
                    landingDirection = landingDirection or approachDirection

                    if driverIsPilot and flight.status == 'taxiing' and taxiHold and insideZone(coords, taxiHold) then
                        if setPilotFlightStatus(flight, 'taxi_hold') then
                            if taxiRunwayIndex and taxiDirection then
                                flightRunwayAssignments[flight.id] = { runwayIndex = taxiRunwayIndex, directionId = taxiDirection.id }
                                aircraftDepartureAssignments[flight.id] = {
                                    airportId = departureAirport.id,
                                    runwayIndex = taxiRunwayIndex,
                                    directionId = taxiDirection.id,
                                    phase = 'taxi'
                                }
                            end
                            local runwayLabel = taxiDirection and (taxiDirection.label or 'assigned direction') or taxiRunway and (taxiRunway.label or 'assigned runway') or 'assigned runway'
                            atcNotify(flight.departure, ('%s, hold at %s for %s. Stop and hold position for clearance.'):format(flight.flightNumber, taxiHold.label, runwayLabel), 'inform')
                            activePilotFlight = lib.callback.await('partay_airlines:server:getPilotFlight', false)
                        end
                    end

                    if driverIsPilot and flight.status == 'taxi_hold' and taxiHold and insideZone(coords, taxiHold) then
                        local timerKey = ('%s:taxi'):format(flight.id)
                        if holdSatisfied(taxiHoldTimers, timerKey, true, speed, holdMs) then
                            taxiHoldTimers[timerKey] = nil
                            if setPilotFlightStatus(flight, 'takeoff_hold') then
                                local departureAssignment = aircraftDepartureAssignments[flight.id] or {
                                    airportId = departureAirport.id,
                                    runwayIndex = taxiRunwayIndex,
                                    directionId = taxiDirection and taxiDirection.id or nil,
                                    phase = 'takeoff_hold'
                                }
                                departureAssignment.phase = 'takeoff_hold'
                                aircraftDepartureAssignments[flight.id] = departureAssignment

                                local assignedTakeoffHold = assignedDirectionZone(departureAirport, 'takeoffHold', departureAssignment) or airportZone(departureAirport, 'takeoffHold')
                                local holdLabel = assignedTakeoffHold and (assignedTakeoffHold.label or 'runway hold') or 'runway hold'
                                atcNotify(flight.departure, ('%s, taxi hold complete. Proceed to %s, line up and wait.'):format(flight.flightNumber, holdLabel), 'inform')
                                activePilotFlight = lib.callback.await('partay_airlines:server:getPilotFlight', false)
                            end
                        end
                    else
                        taxiHoldTimers[('%s:taxi'):format(flight.id)] = nil
                    end

                    if driverIsPilot and flight.status == 'takeoff_hold' and takeoffHold and insideZone(coords, takeoffHold) then
                        if takeoffRunwayIndex and takeoffDirection then
                            flightRunwayAssignments[flight.id] = { runwayIndex = takeoffRunwayIndex, directionId = takeoffDirection.id }
                            aircraftDepartureAssignments[flight.id] = {
                                airportId = departureAirport.id,
                                runwayIndex = takeoffRunwayIndex,
                                directionId = takeoffDirection.id,
                                phase = 'takeoff_hold'
                            }
                        end
                        local runwayLabel = takeoffDirection and (takeoffDirection.label or 'assigned direction') or takeoffRunway and (takeoffRunway.label or 'assigned runway') or 'assigned runway'
                        atcOnce(flight.id, 'takeoff_hold', flight.departure, ('%s, hold position at %s for %s. ATC will clear takeoff automatically.'):format(flight.flightNumber, takeoffHold.label, runwayLabel), 'inform')

                        local timerKey = ('%s:takeoff'):format(flight.id)
                        if holdSatisfied(takeoffHoldTimers, timerKey, true, speed, holdMs) then
                            takeoffHoldTimers[timerKey] = nil
                            if setPilotFlightStatus(flight, 'takeoff_cleared') then
                                local departureAssignment = aircraftDepartureAssignments[flight.id]
                                if departureAssignment then departureAssignment.phase = 'takeoff_cleared' end
                                atcNotify(flight.departure, ('%s, cleared for takeoff from %s. Maintain runway heading until clear of the field.'):format(flight.flightNumber, runwayLabel), 'success')
                                activePilotFlight = lib.callback.await('partay_airlines:server:getPilotFlight', false)
                            end
                        end
                    else
                        takeoffHoldTimers[('%s:takeoff'):format(flight.id)] = nil
                    end

                    if driverIsPilot and flight.status == 'takeoff_cleared' and takeoffZone then
                        local takeoffKey = ('flight:%s'):format(flight.id)
                        if takeoffConfirmed(takeoffKey, vehicle, coords, takeoffZone, speed) then
                            if lib.callback.await('partay_airlines:server:markTakeoff', false, flight.id) then
                                takeoffZoneSeen[takeoffKey] = nil
                                flightRunwayAssignments[flight.id] = nil
                                aircraftDepartureAssignments[flight.id] = nil
                                clearNavigationPrefix(('dep:%s'):format(flight.id))
                                atcNotify(flight.departure, ('%s radar contact. Climb approved, proceed on course.'):format(flight.flightNumber), 'success')
                                activePilotFlight = lib.callback.await('partay_airlines:server:getPilotFlight', false)
                            end
                        end
                    end

                    if driverIsPilot and flight.status == 'in_air' and approachZone and insideZone(coords, approachZone) then
                        if lib.callback.await('partay_airlines:server:markApproach', false, flight.id) then
                            local runwayLabel = approachDirection and (approachDirection.label or 'assigned direction') or approachRunway and (approachRunway.label or 'assigned runway') or 'assigned runway'
                            atcNotify(flight.arrival, ('%s, approach radar contact. Descend and continue inbound for %s.'):format(flight.flightNumber, runwayLabel), 'inform')
                            activePilotFlight = lib.callback.await('partay_airlines:server:getPilotFlight', false)
                        end
                    end

                    local departureAltitude = zoneBaseAltitude(coords, takeoffZone, vehicle)
                    if driverIsPilot and flight.status == 'in_air' and departureAltitude > (Config.Tracking.takeoffAltitude + 80.0) then
                        local gearState = GetLandingGearState(vehicle)
                        if gearState ~= 3 then
                            atcOnce(flight.id, 'gear_up', flight.departure, ('%s, positive climb. Raise landing gear.'):format(flight.flightNumber), 'inform')
                        end
                    end

                    if driverIsPilot and flight.status == 'approach' then
                        local gearState = GetLandingGearState(vehicle)
                        if gearState == 3 then
                            atcOnce(flight.id, 'gear_down', flight.arrival, ('%s, lower landing gear and continue approach.'):format(flight.flightNumber), 'inform')
                        end

                        if speed > 85.0 then
                            atcOnce(flight.id, 'approach_speed', flight.arrival, ('%s, reduce speed for approach.'):format(flight.flightNumber), 'inform')
                        end
                    end

                    if driverIsPilot and arrivalAssignment and (flight.status == 'approach' or flight.status == 'in_air' or flight.status == 'takeoff_cleared') and landingConfirmed(('flight:%s'):format(flight.id), vehicle, coords, landingZone, runwaySurfaceZone(landingRunway), speed) then
                        if lib.callback.await('partay_airlines:server:markLanded', false, flight.id) then
                            landingTimers[('flight:%s'):format(flight.id)] = nil
                            flightArrivalAssignments[flight.id] = nil
                            flightArrivalGates[flight.id] = nil
                            clearNavigationPrefix(('arr:%s'):format(flight.id))
                            local runwayLabel = landingDirection and (landingDirection.label or 'assigned direction') or landingRunway and (landingRunway.label or 'assigned runway') or 'assigned runway'
                            local arrivalGate, gate = bestArrivalGate(arrivalAirport, coords)
                            local gateLabel = gate and (gate.label or gate.gate) or arrivalGate and (arrivalGate.label or 'arrival gate') or 'arrival ramp'
                            clearNavigationPrefix(('gate:%s'):format(flight.id))
                            pendingFlightGateAssignments[flight.id] = {
                                airportId = arrivalAirport.id,
                                runwayLabel = runwayLabel,
                                gateZone = arrivalGate,
                                gateLabel = gateLabel,
                                exitZone = runwaySurfaceZone(landingRunway) or landingZone
                            }
                            atcNotify(flight.arrival, ('%s, welcome to %s. Landing recorded on %s. Exit the runway when able and hold clear for gate assignment.'):format(flight.flightNumber, arrivalAirport.label, runwayLabel), 'success')
                            activePilotFlight = lib.callback.await('partay_airlines:server:getPilotFlight', false)
                            if activePilotFlight and activePilotFlight.status == 'deboarding' then
                                assignFlightGateAfterRunwayExit(activePilotFlight, arrivalAirport, GetEntityCoords(vehicle))
                            end
                        end
                    end

                    if driverIsPilot and flight.status == 'deboarding' then
                        assignFlightGateAfterRunwayExit(flight, arrivalAirport, coords)
                    end

                    if GetVehicleEngineHealth(vehicle) <= Config.Tracking.aircraftMinimumHealth and flight.status == 'in_air' then
                        TriggerServerEvent('partay_airlines:server:failFlight', flight.id, 'aircraft damage')
                        activePilotFlight = nil
                    end
                end
            end
        end
    end
end

local function trackAirportAirspaceIntent()
    while true do
        Wait(1500)

        local flight = activePilotFlight
        local ped = cache.ped
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped and PartayAirports then
            local isAircraft = isAircraftVehicle(vehicle)
            if not isAircraft then
                aircraftAirspacePresence = {}
                airspacePresence = {}
                airspacePromptOpen = false
            else
                local coords = GetEntityCoords(vehicle)
                local airborneEnough = getGroundDistance(vehicle) >= ((Config.ATC or {}).intentMinimumAirborneAltitude or 30.0)
                local aircraftKey = aircraftAtcKey(vehicle)
                local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
                local flightMatchesVehicle = flight and (not flight.aircraftNetId or flight.aircraftNetId == vehicleNetId)
                local activeFlight = flightMatchesVehicle and flight or nil
                local nearestAirport = airborneEnough and nearestContactAirport(coords, activeFlight and activeFlight.departure or nil) or nil
                local nearestId = nearestAirport and nearestAirport.id or nil
                local activeVolumes = airborneEnough and matchingAirspaceVolumes(coords, activeFlight and activeFlight.departure or nil) or {}
                local activeVolumeIds = {}
                local atcTarget = flightMatchesVehicle and flight or (aircraftKey and {
                    id = aircraftKey,
                    flightNumber = 'Aircraft',
                    aircraftNetId = vehicleNetId,
                    temporary = true
                }) or nil
                local callsign = atcTarget and atcTarget.flightNumber or 'Aircraft'

                for index, volume in ipairs(activeVolumes) do
                    local airport = airportForAirspaceVolume(volume, coords)
                    local presenceKey = volume.id
                    activeVolumeIds[presenceKey] = true

                    if airport and not aircraftAirspacePresence[presenceKey] then
                        aircraftAirspacePresence[presenceKey] = true
                        atcNotify(airport.id, ('%s entering %s controlled airspace.'):format(callsign, volume.facility or volume.label or airport.label or airport.id), 'inform')
                    end

                    if atcTarget and airport then
                        local isControllingVolume = index == 1
                        local intentKey = ('%s:%s'):format(atcTarget.id, airport.id)
                        local canPromptIntent = isControllingVolume and (not activeFlight or airport.id ~= activeFlight.departure)

                        if canPromptIntent and not airspacePresence[presenceKey] then
                            airspacePresence[presenceKey] = true
                            airspaceReminders[intentKey] = {
                                nextAt = 0,
                                count = 0
                            }
                        end

                        if canPromptIntent and not airspaceIntent[intentKey] then
                            local reminder = airspaceReminders[intentKey] or { nextAt = 0, count = 0 }
                            local now = GetGameTimer()
                            if now >= (reminder.nextAt or 0) then
                                reminder.count = (reminder.count or 0) + 1
                                local atcConfig = Config.ATC or {}
                                reminder.nextAt = now + ((atcConfig.intentReminderSeconds or 35) * 1000)
                                airspaceReminders[intentKey] = reminder

                                local facility = volume.facility or airport.tower or airport.label or 'ATC'
                                local message
                                if reminder.count == 1 then
                                    message = ('%s, %s available on %s. Open aircraft radio to state intentions.'):format(callsign, facility, atcFrequencyFor(airport, 'tower'))
                                elseif reminder.count >= (atcConfig.intentReminderEscalateAfter or 2) then
                                    message = ('%s, radio contact requested in %s controlled airspace. Use /%s or your radio key.'):format(callsign, facility, atcConfig.radioCommand or 'airradio')
                                else
                                    message = ('%s, ATC is still awaiting radio contact.'):format(callsign)
                                end

                                atcNotify(airport.id, message, reminder.count >= (atcConfig.intentReminderEscalateAfter or 2) and 'warning' or 'inform')
                            end
                        elseif not canPromptIntent and airspacePresence[presenceKey] then
                            airspacePresence[presenceKey] = nil
                            airspaceIntent[intentKey] = nil
                            airspaceReminders[intentKey] = nil
                        end
                    end
                end

                for presenceKey in pairs(aircraftAirspacePresence) do
                    if not activeVolumeIds[presenceKey] and tostring(presenceKey):find('_') then
                        aircraftAirspacePresence[presenceKey] = nil
                        local volume
                        for _, candidate in ipairs(Config.AirspaceVolumes or {}) do
                            if candidate.id == presenceKey then
                                volume = candidate
                                break
                            end
                        end
                        local airport = airportForAirspaceVolume(volume, coords)
                        if airport then
                            atcNotify(airport.id, ('%s leaving %s controlled airspace.'):format(callsign, volume and (volume.facility or volume.label) or airport.label or airport.id), 'inform')
                        end
                    end
                end

                if not (Config.Airspace and Config.Airspace.useVolumes ~= false and #activeVolumes > 0) then
                    for _, airport in ipairs(PartayAirports) do
                        normalizeKnownAirport(airport)

                        if airport.airspace and airport.airspace.enabled ~= false then
                            local insideAirspace = insideAirportContactAirspace(coords, airport)
                            local isNearestAirspace = nearestId == airport.id
                            local presenceKey = airport.id
                            local intentKey = atcTarget and ('%s:%s'):format(atcTarget.id, airport.id) or nil
                            local canPromptIntent = atcTarget and isNearestAirspace and (not activeFlight or airport.id ~= activeFlight.departure)

                            if insideAirspace and not aircraftAirspacePresence[presenceKey] then
                                aircraftAirspacePresence[presenceKey] = true
                                atcNotify(airport.id, ('%s entering %s controlled airspace.'):format(callsign, airport.label or airport.id), 'inform')
                            end

                            if not insideAirspace and aircraftAirspacePresence[presenceKey] then
                                aircraftAirspacePresence[presenceKey] = nil
                                atcNotify(airport.id, ('%s leaving %s controlled airspace.'):format(callsign, airport.label or airport.id), 'inform')
                            end

                            if canPromptIntent and not airspacePresence[presenceKey] then
                                airspacePresence[presenceKey] = true
                                airspaceReminders[intentKey] = {
                                    nextAt = 0,
                                    count = 0
                                }
                            end

                            if canPromptIntent and not airspaceIntent[intentKey] then
                                local reminder = airspaceReminders[intentKey] or { nextAt = 0, count = 0 }
                                local now = GetGameTimer()
                                if now >= (reminder.nextAt or 0) then
                                    reminder.count = (reminder.count or 0) + 1
                                    local atcConfig = Config.ATC or {}
                                    reminder.nextAt = now + ((atcConfig.intentReminderSeconds or 35) * 1000)
                                    airspaceReminders[intentKey] = reminder

                                    local message
                                    if reminder.count == 1 then
                                        message = ('%s, %s available on %s. Open aircraft radio to state intentions.'):format(callsign, airport.tower or airport.label or 'ATC', atcFrequencyFor(airport, 'tower'))
                                    elseif reminder.count >= (atcConfig.intentReminderEscalateAfter or 2) then
                                        message = ('%s, radio contact requested in %s controlled airspace. Use /%s or your radio key.'):format(callsign, airport.label or airport.id, atcConfig.radioCommand or 'airradio')
                                    else
                                        message = ('%s, ATC is still awaiting radio contact.'):format(callsign)
                                    end

                                    atcNotify(airport.id, message, reminder.count >= (atcConfig.intentReminderEscalateAfter or 2) and 'warning' or 'inform')
                                end
                            elseif atcTarget and not isNearestAirspace and airspacePresence[presenceKey] then
                                airspacePresence[presenceKey] = nil
                                airspaceIntent[intentKey] = nil
                                airspaceReminders[intentKey] = nil
                                if activeFlight and flightArrivalAssignments[activeFlight.id] and flightArrivalAssignments[activeFlight.id].airportId == airport.id and activeFlight.status ~= 'approach' and activeFlight.status ~= 'deboarding' then
                                    flightArrivalAssignments[activeFlight.id] = nil
                                end
                                if atcTarget.temporary and aircraftArrivalAssignments[atcTarget.id] and aircraftArrivalAssignments[atcTarget.id].airportId == airport.id then
                                    aircraftArrivalAssignments[atcTarget.id] = nil
                                end
                            end
                        end
                    end
                end
            end
        else
            airspacePresence = {}
            aircraftAirspacePresence = {}
            airspacePromptOpen = false
        end
    end
end

local function trackPassengerDeboarding()
    while true do
        Wait(2500)

        local flights = lib.callback.await('partay_airlines:server:getFlights', false) or {}
        local ped = cache.ped
        local coords = GetEntityCoords(ped)

        for _, flight in ipairs(flights) do
            local airport = airportFor(flight.arrival)
            local arrivalGate = flightArrivalGates[flight.id] or airportZone(airport, 'arrivalGate', coords)
            if arrivalGate and flight.status == 'deboarding' and not IsPedInAnyVehicle(ped, false) and insideZone(coords, arrivalGate) and not deboardPrompted[flight.id] then
                deboardPrompted[flight.id] = true
                local success, message = lib.callback.await('partay_airlines:server:markDeboarded', false, flight.id)

                if success then
                    notify(message or 'Travel completed.', 'success')
                end
            end
        end
    end
end

local function arrivalGuidanceZones(arrivalAirport, arrivalAssignment, coords)
    if not arrivalAirport or not arrivalAssignment then return {} end

    local approachZone, approachRunway, approachDirection = assignedRunwayZone(arrivalAirport, 'approachZone', arrivalAssignment)
    local landingZone, landingRunway, landingDirection = assignedRunwayZone(arrivalAirport, 'landingZone', arrivalAssignment)
    landingRunway = landingRunway or approachRunway

    return {
        approachZone = approachZone,
        landingZone = landingZone,
        landingRunway = landingRunway,
        landingDirection = landingDirection,
        approachDirection = approachDirection
    }
end

local function trackGeneralAviationLanding()
    while true do
        Wait(500)

        local ped = cache.ped
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped and isAircraftVehicle(vehicle) then
            local aircraftKey = aircraftAtcKey(vehicle)
            local arrivalAssignment = aircraftKey and aircraftArrivalAssignments[aircraftKey] or nil
            local state = aircraftKey and aircraftAtcStates[aircraftKey] or nil

            if aircraftKey and arrivalAssignment and state and state.phase == 'landing_cleared' then
                local arrivalAirport = airportFor(arrivalAssignment.airportId)
                local coords = GetEntityCoords(vehicle)
                local speed = GetEntitySpeed(vehicle)
                local zones = arrivalGuidanceZones(arrivalAirport, arrivalAssignment, coords)

                if landingConfirmed(('ga:%s'):format(aircraftKey), vehicle, coords, zones.landingZone, runwaySurfaceZone(zones.landingRunway), speed) then
                    landingTimers[('ga:%s'):format(aircraftKey)] = nil
                    aircraftArrivalAssignments[aircraftKey] = nil
                    aircraftArrivalGates[aircraftKey] = nil
                    clearNavigationPrefix(('arr:%s'):format(aircraftKey))

                    local arrivalGate, gate = bestArrivalGate(arrivalAirport, coords)
                    clearNavigationPrefix(('gate:%s'):format(aircraftKey))
                    local gateLabel = gate and (gate.label or gate.gate) or arrivalGate and (arrivalGate.label or 'arrival gate') or 'arrival ramp'
                    local runwayLabel = zones.landingDirection and (zones.landingDirection.label or 'assigned direction') or zones.landingRunway and (zones.landingRunway.label or 'assigned runway') or 'assigned runway'
                    state.phase = 'landed_on_runway'
                    pendingAircraftGateAssignments[aircraftKey] = {
                        airportId = arrivalAirport.id,
                        runwayLabel = runwayLabel,
                        gateZone = arrivalGate,
                        gateLabel = gateLabel,
                        exitZone = runwaySurfaceZone(zones.landingRunway) or zones.landingZone
                    }

                    atcNotify(arrivalAirport.id, ('General Aviation Aircraft, landing confirmed on %s. Exit the runway when able and hold clear for gate assignment.'):format(runwayLabel), 'success')
                end
            elseif aircraftKey and state and state.phase == 'landed_on_runway' then
                local pending = pendingAircraftGateAssignments[aircraftKey]
                local arrivalAirport = pending and airportFor(pending.airportId) or nil
                if arrivalAirport then
                    local coords = GetEntityCoords(vehicle)
                    if assignAircraftGateAfterRunwayExit(aircraftKey, arrivalAirport, 'General Aviation Aircraft', coords) then
                        state.phase = 'taxi_gate'
                    end
                end
            end
        end
    end
end

local function drawArrivalGuidance(arrivalAirport, arrivalAssignment, coords, target)
    if not arrivalAssignment then
        if target then clearNavigationPrefix(('arr:%s'):format(target.id)) end
        return false
    end

    local zones = arrivalGuidanceZones(arrivalAirport, arrivalAssignment, coords)
    local approachZone = zones.approachZone
    local landingZone = zones.landingZone
    local landingRunway = zones.landingRunway
    local landingDirection = zones.landingDirection or zones.approachDirection or arrivalAssignment.direction

    if not (landingRunway or landingZone or approachZone) then return false end

    local nav = Config.Navigation or {}
    local showLegacyMarkers = nav.showLegacyMarkers == true or Config.Debug
    local showAssignedRunway = target ~= nil and nav.highlightAssignedRunway ~= false
    if target then
        local prefix = ('arr:%s'):format(target.id)
        local landingPoint = landingDirection and (landingDirection.threshold or zoneCenter(landingDirection.zones and landingDirection.zones.landingZone)) or nil
        local landingLabel = landingDirection and (landingDirection.label or 'Assigned Landing End') or 'Assigned Landing Runway'
        if landingPoint then
            setPointNavigation(prefix, 'landing', landingLabel, landingPoint, nav.colors and nav.colors.approach or '#65d6ff', 'checkpoint', nav.sizes and nav.sizes.runway or 0.9)
        else
            setZoneNavigation(prefix, 'landing', landingLabel, landingZone or runwaySurfaceZone(landingRunway), nav.colors and nav.colors.approach or '#65d6ff', 'checkpoint', nav.sizes and nav.sizes.runway or 0.9)
        end
    end

    if showAssignedRunway and landingRunway then
        drawRunwayHighlight(landingRunway, 80, 255, 120)
    end

    if showLegacyMarkers then
        if approachZone then drawZone(approachZone, 120, 210, 255) end
        if landingZone then drawZone(landingZone, 80, 255, 120) end
    end

    return true
end

local function departureGuidanceZones(departureAirport, departureAssignment, coords)
    if not departureAirport or not departureAssignment then return {} end

    local taxiHold, taxiRunway, taxiDirection = assignedDirectionZone(departureAirport, 'taxiHold', departureAssignment)
    local takeoffHold, takeoffRunway, takeoffDirection = assignedDirectionZone(departureAirport, 'takeoffHold', departureAssignment)
    local takeoffZone, takeoffRunwayZone, takeoffZoneDirection = assignedDirectionZone(departureAirport, 'takeoffZone', departureAssignment)

    if not taxiHold then taxiHold, taxiRunway, taxiDirection = airportZone(departureAirport, 'taxiHold', coords) end
    if not taxiHold then taxiHold, taxiRunway, taxiDirection = airportZone(departureAirport, 'taxiHold') end
    if not takeoffHold then takeoffHold, takeoffRunway, takeoffDirection = airportZone(departureAirport, 'takeoffHold', coords) end
    if not takeoffHold then takeoffHold, takeoffRunway, takeoffDirection = airportZone(departureAirport, 'takeoffHold') end
    if not takeoffZone then takeoffZone, takeoffRunwayZone, takeoffZoneDirection = airportZone(departureAirport, 'takeoffZone', coords) end
    if not takeoffZone then takeoffZone, takeoffRunwayZone, takeoffZoneDirection = airportZone(departureAirport, 'takeoffZone') end

    return {
        taxiHold = taxiHold,
        takeoffHold = takeoffHold,
        takeoffZone = takeoffZone,
        runway = takeoffRunwayZone or takeoffRunway or taxiRunway or departureAssignment.runway,
        direction = takeoffZoneDirection or takeoffDirection or taxiDirection or departureAssignment.direction
    }
end

local function drawDepartureGuidance(departureAirport, departureAssignment, coords, target)
    if not departureAirport or not departureAssignment then return false end

    local zones = departureGuidanceZones(departureAirport, departureAssignment, coords)
    if not (zones.taxiHold or zones.takeoffHold or zones.takeoffZone or zones.runway) then return false end

    local phase = departureAssignment.phase or 'taxi'
    local nav = Config.Navigation or {}
    local showLegacyMarkers = nav.showLegacyMarkers == true or Config.Debug
    local showAssignedRunway = target ~= nil and nav.highlightAssignedRunway ~= false
    if target then
        local prefix = ('dep:%s'):format(target.id)
        if phase == 'taxi' then
            setZoneNavigation(prefix, 'taxi', 'Taxi Hold', zones.taxiHold, nav.colors and nav.colors.taxi or '#f4d35e', 'checkpoint', nav.sizes and nav.sizes.hold or 0.75)
            clearNavigationWaypoint(('%s:takeoff'):format(prefix))
            clearNavigationWaypoint(('%s:runway'):format(prefix))
        elseif phase == 'takeoff_hold' then
            setZoneNavigation(prefix, 'takeoff', 'Takeoff Hold', zones.takeoffHold, nav.colors and nav.colors.takeoff or '#ff4d4d', 'checkpoint', nav.sizes and nav.sizes.hold or 0.75)
            clearNavigationWaypoint(('%s:taxi'):format(prefix))
            clearNavigationWaypoint(('%s:runway'):format(prefix))
        elseif phase == 'takeoff_cleared' then
            setZoneNavigation(prefix, 'runway', 'Cleared Runway', zones.takeoffZone or runwaySurfaceZone(zones.runway), nav.colors and nav.colors.runway or '#4aa3ff', 'checkpoint', nav.sizes and nav.sizes.runway or 0.9)
            clearNavigationWaypoint(('%s:taxi'):format(prefix))
            clearNavigationWaypoint(('%s:takeoff'):format(prefix))
        end
    end

    if showAssignedRunway and phase == 'takeoff_cleared' and zones.runway then
        drawRunwayHighlight(zones.runway, 80, 200, 255)
    end

    if showLegacyMarkers then
        if zones.taxiHold then drawHoldHighlight(zones.taxiHold, 255, 220, 80) end
        if zones.takeoffHold then drawHoldHighlight(zones.takeoffHold, 255, 70, 70) end
        if zones.takeoffZone then drawZone(zones.takeoffZone, 80, 200, 255) end
    end

    if target and coords then
        local callsign = target.flightNumber or (target.temporary and 'General Aviation Aircraft' or 'Aircraft')

        if target.temporary then
            local vehicle = currentPilotAircraft()
            local speed = vehicle and GetEntitySpeed(vehicle) or 0.0
            local holdMs = ((Config.ATC and Config.ATC.holdShortSeconds) or 5) * 1000

            if phase == 'taxi' and zones.taxiHold then
                local inTaxiHold = insideZone(coords, zones.taxiHold)
                if inTaxiHold then
                    atcOnce(target.id, 'taxi_hold_hold_position', departureAirport.id, ('%s, hold at %s. ATC will call your runway hold clearance.'):format(callsign, zones.taxiHold.label or 'taxi hold'), 'inform')
                end

                if holdSatisfied(taxiHoldTimers, ('%s:taxi'):format(target.id), inTaxiHold, speed, holdMs) then
                    taxiHoldTimers[('%s:taxi'):format(target.id)] = nil
                    departureAssignment.phase = 'takeoff_hold'
                    local holdLabel = zones.takeoffHold and (zones.takeoffHold.label or 'takeoff hold') or 'takeoff hold'
                    local clearance = ('%s, taxi hold complete. Proceed to %s, line up and wait.'):format(callsign, holdLabel)
                    setAtcClearance(target, departureAirport, 'departure', clearance, departureAssignment)
                    atcNotify(departureAirport.id, clearance, 'inform')
                end
            elseif phase == 'takeoff_hold' and zones.takeoffHold then
                local inTakeoffHold = insideZone(coords, zones.takeoffHold)
                if inTakeoffHold then
                    atcOnce(target.id, 'takeoff_hold_hold_position', departureAirport.id, ('%s, hold position at %s. ATC will issue takeoff clearance.'):format(callsign, zones.takeoffHold.label or 'takeoff hold'), 'warning')
                end

                if holdSatisfied(takeoffHoldTimers, ('%s:takeoff'):format(target.id), inTakeoffHold, speed, holdMs) then
                    takeoffHoldTimers[('%s:takeoff'):format(target.id)] = nil
                    departureAssignment.phase = 'takeoff_cleared'
                    aircraftAtcStates[target.id] = aircraftAtcStates[target.id] or {}
                    aircraftAtcStates[target.id].phase = 'takeoff_cleared'
                    aircraftAtcStates[target.id].airportId = departureAirport.id
                    local clearance = ('%s, cleared for takeoff from %s. Maintain runway heading until clear of the field.'):format(callsign, assignmentLabel(departureAssignment))
                    setAtcClearance(target, departureAirport, 'takeoff', clearance, departureAssignment)
                    atcNotify(departureAirport.id, clearance, 'success')
                end
            elseif phase == 'takeoff_cleared' and zones.takeoffZone then
                if takeoffConfirmed(('ga:%s'):format(target.id), vehicle, coords, zones.takeoffZone, speed) then
                    takeoffZoneSeen[('ga:%s'):format(target.id)] = nil
                    aircraftDepartureAssignments[target.id] = nil
                    clearNavigationPrefix(('dep:%s'):format(target.id))
                    aircraftAtcStates[target.id] = aircraftAtcStates[target.id] or {}
                    aircraftAtcStates[target.id].phase = 'departed'
                    aircraftAtcStates[target.id].airportId = departureAirport.id
                    atcNotify(departureAirport.id, ('%s radar contact. Departure approved, proceed on course.'):format(callsign), 'success')
                end
            end
        elseif phase == 'taxi' and zones.taxiHold and insideZone(coords, zones.taxiHold) then
            atcOnce(target.id, 'taxi_hold_reached', departureAirport.id, ('%s, hold at %s. ATC will call your runway hold clearance.'):format(callsign, zones.taxiHold.label or 'taxi hold'), 'inform')
        elseif phase == 'takeoff_hold' and zones.takeoffHold and insideZone(coords, zones.takeoffHold) then
            atcOnce(target.id, 'takeoff_hold_reached', departureAirport.id, ('%s, hold position at %s. ATC will issue takeoff clearance.'):format(callsign, zones.takeoffHold.label or 'takeoff hold'), 'warning')
        end
    end

    return true
end

local function renderPilotMarkers()
    while true do
        Wait(0)

        local flight = activePilotFlight
        if flight then
            local departureAirport = airportFor(flight.departure)
            local arrivalAirport = airportFor(flight.arrival)
            local ped = cache.ped
            local vehicle = flight.aircraftNetId and entityFromNetId(flight.aircraftNetId) or GetVehiclePedIsIn(ped, false)
            local coords = vehicle ~= 0 and DoesEntityExist(vehicle) and GetEntityCoords(vehicle) or GetEntityCoords(ped)
            local taxiHold = airportZone(departureAirport, 'taxiHold', coords)
            local takeoffHold = airportZone(departureAirport, 'takeoffHold', coords) or airportZone(departureAirport, 'takeoffHold')
            local departureAssignment = flightRunwayAssignments[flight.id]
            local departureGuidance = aircraftDepartureAssignments[flight.id]
            local takeoffZone, takeoffRunway = assignedDirectionZone(departureAirport, 'takeoffZone', departureAssignment)
            if not takeoffZone then takeoffZone, takeoffRunway = airportZone(departureAirport, 'takeoffZone', coords) end
            if not takeoffZone then takeoffZone, takeoffRunway = airportZone(departureAirport, 'takeoffZone') end
            local arrivalAssignment = flightArrivalAssignments[flight.id]
            local arrivalGate = flightArrivalGates[flight.id]
            local nav = Config.Navigation or {}
            local showLegacyMarkers = nav.showLegacyMarkers == true or Config.Debug

            if showLegacyMarkers and flight.status == 'taxiing' and taxiHold then
                drawHoldHighlight(taxiHold, 255, 220, 80)
            elseif showLegacyMarkers and flight.status == 'takeoff_hold' and takeoffHold then
                drawHoldHighlight(takeoffHold, 255, 70, 70)
            elseif showLegacyMarkers and flight.status == 'takeoff_cleared' and takeoffZone then
                drawRunwayHighlight(takeoffRunway, 80, 220, 255)
                drawZone(takeoffZone, 80, 200, 255)
            elseif flight.status == 'in_air' or flight.status == 'approach' then
                drawArrivalGuidance(arrivalAirport, arrivalAssignment, coords, flight)
            elseif flight.status == 'deboarding' and arrivalGate then
                clearNavigationPrefix(('arr:%s'):format(flight.id))
                setZoneNavigation(('gate:%s'):format(flight.id), 'arrival', 'Assigned Gate', arrivalGate, nav.colors and nav.colors.gate or '#b47cff', 'checkpoint', nav.sizes and nav.sizes.gate or 0.7)
                if showLegacyMarkers then
                    drawZone(arrivalGate, 180, 120, 255)
                end
            else
                clearNavigationPrefix(('arr:%s'):format(flight.id))
            end

            if departureGuidance and (flight.status == 'taxiing' or flight.status == 'taxi_hold' or flight.status == 'takeoff_hold' or flight.status == 'takeoff_cleared') then
                drawDepartureGuidance(departureAirport, departureGuidance, coords, flight)
            elseif flight.status == 'in_air' or flight.status == 'approach' or flight.status == 'deboarding' then
                flightRunwayAssignments[flight.id] = nil
                aircraftDepartureAssignments[flight.id] = nil
                clearNavigationPrefix(('dep:%s'):format(flight.id))
            end
        end

        local ped = cache.ped
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped then
            local _, activeFlightForVehicle = currentAtcTarget(vehicle, activePilotFlight)
            local isAircraft = isAircraftVehicle(vehicle)
            local aircraftKey = isAircraft and aircraftAtcKey(vehicle) or nil
            local assignment = aircraftKey and aircraftArrivalAssignments[aircraftKey] or nil
            local departureAssignment = aircraftKey and aircraftDepartureAssignments[aircraftKey] or nil
            local assignedGate = aircraftKey and aircraftArrivalGates[aircraftKey] or nil

            if activeFlightForVehicle then
                if aircraftKey then
                    clearNavigationPrefix(('arr:%s'):format(aircraftKey))
                    clearNavigationPrefix(('dep:%s'):format(aircraftKey))
                    aircraftArrivalAssignments[aircraftKey] = nil
                    aircraftDepartureAssignments[aircraftKey] = nil
                end
            else
                local airport = assignment and airportFor(assignment.airportId) or nil
                if airport then
                    drawArrivalGuidance(airport, assignment, GetEntityCoords(vehicle), { id = aircraftKey, flightNumber = 'General Aviation Aircraft', temporary = true })
                elseif aircraftKey then
                    clearNavigationPrefix(('arr:%s'):format(aircraftKey))
                end
                if assignedGate then
                    local nav = Config.Navigation or {}
                    setZoneNavigation(('gate:%s'):format(aircraftKey), 'arrival', 'Assigned Gate', assignedGate, nav.colors and nav.colors.gate or '#b47cff', 'checkpoint', nav.sizes and nav.sizes.gate or 0.7)
                    if nav.showLegacyMarkers == true or Config.Debug then
                        drawZone(assignedGate, 180, 120, 255)
                    end
                end
                local departureAirport = departureAssignment and airportFor(departureAssignment.airportId) or nil
                if departureAirport then
                    drawDepartureGuidance(departureAirport, departureAssignment, GetEntityCoords(vehicle), { id = aircraftKey, flightNumber = 'Aircraft', temporary = true })
                end
            end
        end
    end
end

local function renderCreatorDebugZones()
    while true do
        Wait(0)

        if PartayAirports then
            for _, airport in ipairs(PartayAirports) do
                normalizeKnownAirport(airport)
                if airport.debug or airport.id == 'sandy' then
                    local center = airportCenter(airport)
                    local airspaceRadius = airport.airspace and tonumber(airport.airspace.radius) or nil

                    if center then
                        if airport.id == 'sandy' and not sandyDebugNoticeShown then
                            sandyDebugNoticeShown = true
                            lib.notify({
                                title = 'Airport Debug',
                                description = ('Sandy airspace drawing at %.1f, %.1f, %.1f / radius %.0f'):format(center.x, center.y, center.z, airspaceRadius or 0.0),
                                type = 'inform'
                            })
                        end

                        drawAtcPoint(center)
                        if Config.Airspace and Config.Airspace.useVolumes ~= false then
                            for _, volume in ipairs(Config.AirspaceVolumes or {}) do
                                if volume.airport == airport.id then
                                    drawAirspaceVolume(volume, airport.restricted and 220 or 20, airport.restricted and 80 or 160, airport.restricted and 80 or 255)
                                end
                            end
                        elseif airport.airspace and airport.airspace.enabled ~= false and airspaceRadius and airspaceRadius > 0.0 then
                            drawSphereAt(center, airspaceRadius, airport.restricted and 180 or 25, airport.restricted and 30 or 95, airport.restricted and 30 or 190, 48)
                            drawAirspaceRing(center, airspaceRadius, airport.restricted and 220 or 20, airport.restricted and 80 or 160, airport.restricted and 80 or 255)
                            drawAirspaceBoundary(center, airspaceRadius, airport.airspace.altitudeMin, airport.airspace.altitudeMax, airport.restricted and 220 or 20, airport.restricted and 80 or 160, airport.restricted and 80 or 255)
                        elseif airport.airspace and airport.airspace.enabled ~= false then
                            drawSphereAt(center, 120.0, 255, 80, 80, 58)
                            drawAirspaceRing(center, 120.0, 255, 80, 80)
                            drawAirspaceBoundary(center, 120.0, 0.0, 160.0, 255, 80, 80)
                        end
                    end

                    for _, runway in ipairs(airport.runways or {}) do
                        drawZone(runwaySurfaceZone(runway), 120, 180, 255)
                        for _, direction in ipairs(runway.directions or {}) do
                            for _, zone in pairs(direction.zones or {}) do
                                drawZone(zone, airport.restricted and 255 or 120, 210, airport.restricted and 80 or 255)
                            end
                        end
                        for _, zone in pairs(runway.zones or {}) do
                            drawZone(zone, airport.restricted and 255 or 80, 160, airport.restricted and 80 or 255)
                        end
                    end

                    for _, zone in pairs(airport.zones or {}) do
                        drawZone(zone, airport.restricted and 255 or 80, airport.restricted and 80 or 220, 120)
                    end

                    for _, gate in ipairs(airport.gates or {}) do
                        local spawn = gate.aircraftSpawn or gate.coords
                        if spawn then
                            drawGroundMarker({ coords = vec3(spawn.x, spawn.y, spawn.z), radius = gate.aircraftBoardingRadius or gate.radius or 28.0 }, 180, 120, 255)
                        end
                    end

                    for _, hangar in ipairs(airport.hangars or {}) do
                        local coords = hangar.coords
                        if coords then
                            drawGroundMarker({ coords = vec3(coords.x, coords.y, coords.z), radius = 6.0 }, 255, 180, 80)
                        end
                    end
                end
            end
        end

    end
end

local function trackRestrictedAirspace()
    while true do
        Wait(2500)

        local ped = cache.ped
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped and PartayAirports then
            local coords = GetEntityCoords(vehicle)

            for _, airport in ipairs(PartayAirports) do
                if airport.restricted then
                    local insideRestricted = insideAirportAirspace(coords, airport)
                    for _, runway in ipairs(airport.runways or {}) do
                        if insideZone(coords, runwaySurfaceZone(runway)) then
                            insideRestricted = true
                            break
                        end

                        for _, zone in pairs(runway.zones or {}) do
                            if insideZone(coords, zone) then
                                insideRestricted = true
                                break
                            end
                        end

                        if insideRestricted then break end

                        for _, direction in ipairs(runway.directions or {}) do
                            for _, zone in pairs(direction.zones or {}) do
                                if insideZone(coords, zone) then
                                    insideRestricted = true
                                    break
                                end
                            end

                            if insideRestricted then break end
                        end

                        if insideRestricted then break end
                    end

                    if not insideRestricted then
                        for _, zone in pairs(airport.zones or {}) do
                            if insideZone(coords, zone) then
                                insideRestricted = true
                                break
                            end
                        end
                    end

                    if insideRestricted then
                        atcOnce(('restricted:%s'):format(airport.id), 'warning', airport.id, airport.restrictedMessage or 'Restricted airspace. Leave the area immediately.', 'error')
                    end
                end
            end
        end
    end
end

CreateThread(registerTargets)
CreateThread(trackPilotFlight)
CreateThread(trackAirportAirspaceIntent)
CreateThread(trackPassengerDeboarding)
CreateThread(trackGeneralAviationLanding)
CreateThread(renderPilotMarkers)
CreateThread(renderCreatorDebugZones)
CreateThread(trackRestrictedAirspace)
CreateThread(atcRadioControlLock)

RegisterCommand('airline', openPilotTerminal, false)
RegisterCommand('flights', openTicketDesk, false)

-- Open the dispatch tablet from the pilot tablet item (used anywhere)
RegisterNetEvent('partay_airlines:client:openTablet', function()
    openPilotTerminal(nil)
end)
PartayOpenAircraftRadio = openAircraftRadioForCurrentAircraft
print('[ParTay Airlines] client radio commands registered')
local radioCommand = Config.ATC.radioCommand or 'airradio'
RegisterCommand(radioCommand, function()
    PartayOpenAircraftRadio()
end, false)
RegisterKeyMapping(radioCommand, 'Open aircraft radio', 'keyboard', Config.ATC.radioKey or 'F1')

-- Z opens the aircraft radio (same as /airradio). Close with ESC.
CreateThread(function()
    while true do
        local wait = 500
        if currentPilotAircraft() then
            wait = 0
            if IsRawKeyJustReleased(90) and not IsPauseMenuActive() then
                PartayOpenAircraftRadio()
            end
        end
        Wait(wait)
    end
end)

-- ============================================================
-- Glass cockpit HUD (PFD + MFD) — passive avionics overlay
-- Auto-shows for the pilot (-1) or front passenger (0) of an aircraft.
-- /airhud toggles it; jg-hud is hidden while the cockpit HUD is up.
-- ============================================================
local airHudEnabled = true
local airHudVisible = false
local airHudPrevAlt, airHudPrevT
local airHudBlips, airHudBlipsAt = {}, 0
local airHudEditing = false
local airHudPos, atcWasOpen
do
    local function loadUi(key)
        local raw = GetResourceKvpString(key)
        if raw and raw ~= '' then
            local ok, data = pcall(json.decode, raw)
            if ok and data and data.left ~= nil then return data end
        end
    end
    airHudPos = loadUi('airhud_ui')
    atcPos = loadUi('atc_ui')
end

local function jgHud(state)
    pcall(function()
        exports['jg-hud']:toggleHud(state)
        exports['jg-hud']:toggleVehicleControl(state)
    end)
end

local function airHudCrewVehicle()
    local ped = cache.ped or PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    if not isAircraftVehicle(veh) then return nil end
    if GetPedInVehicleSeat(veh, -1) == ped or GetPedInVehicleSeat(veh, 0) == ped then
        return veh
    end
    return nil
end

local function airHudBuildBlips()
    local now = GetGameTimer()
    if now - airHudBlipsAt < 1500 and #airHudBlips > 0 then return airHudBlips end
    airHudBlipsAt = now
    local list = {}
    local originId = activePilotFlight and activePilotFlight.departure
    local destId = activePilotFlight and activePilotFlight.arrival
    for _, airport in ipairs(PartayAirports or {}) do
        local c = airportCenter(airport)
        if c then
            local t = 'airport'
            if airport.id == destId then t = 'dest'
            elseif airport.id == originId then t = 'origin' end
            list[#list + 1] = { x = c.x, y = c.y, type = t, label = airport.label or airport.id }
        end
    end
    airHudBlips = list
    return list
end

local function airHudWaypoint()
    local blip = GetFirstBlipInfoId(8)
    if blip ~= 0 and DoesBlipExist(blip) then
        local c = GetBlipInfoIdCoord(blip)
        return { x = c.x, y = c.y }
    end
    return nil
end

local function airHudSend(veh)
    local coords = GetEntityCoords(veh)
    local compass = (360.0 - GetEntityHeading(veh)) % 360.0
    local kias = GetEntitySpeed(veh) * 1.94384
    local altMSL = coords.z * 3.28084
    local agl = GetEntityHeightAboveGround(veh) * 3.28084

    local now = GetGameTimer()
    local vsi = 0.0
    if airHudPrevAlt and airHudPrevT and now > airHudPrevT then
        local dtMin = (now - airHudPrevT) / 60000.0
        if dtMin > 0 then vsi = (altMSL - airHudPrevAlt) / dtMin end
    end
    airHudPrevAlt, airHudPrevT = altMSL, now

    SendNUIMessage({
        action = 'airhudData',
        pitch = GetEntityPitch(veh),
        roll = GetEntityRoll(veh),
        hdg = compass,
        kias = kias, gs = kias,
        altMSL = altMSL, altAGL = agl, vsi = vsi,
        x = coords.x, y = coords.y,
        blips = airHudBuildBlips(),
        waypoint = airHudWaypoint()
    })
end

local function airHudShow()
    if airHudVisible then return end
    airHudVisible = true
    airHudPrevAlt, airHudPrevT = nil, nil
    jgHud(false)
    SendNUIMessage({ action = 'airhudShow', pos = airHudPos })
end

local function airHudHide()
    if not airHudVisible then return end
    airHudVisible = false
    if airHudEditing then
        airHudEditing = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'airhudEdit', on = false })
        SendNUIMessage({ action = 'atcEdit', on = false, keepOpen = atcWasOpen })
    end
    SendNUIMessage({ action = 'airhudHide' })
    jgHud(true)
end

CreateThread(function()
    while true do
        local veh = airHudEnabled and airHudCrewVehicle() or nil
        if veh then
            if not airHudVisible then airHudShow() end
            airHudSend(veh)
            Wait(0)
        else
            if airHudVisible then airHudHide() end
            Wait(500)
        end
    end
end)

RegisterCommand('airhud', function()
    airHudEnabled = not airHudEnabled
    if not airHudEnabled and airHudVisible then airHudHide() end
    notify(('Cockpit HUD %s'):format(airHudEnabled and 'enabled' or 'disabled'), 'inform')
end, false)

local function airUiEnterEdit()
    atcWasOpen = atcRadioOpen
    airHudEditing = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'airhudEdit', on = true, pos = airHudPos })
    SendNUIMessage({ action = 'atcEdit', on = true, pos = atcPos })
    notify('Drag each panel; use \u{2212}/+ to resize. Press Lock In when done.', 'inform')
end

local function airUiExitEdit()
    airHudEditing = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'airhudEdit', on = false })
    SendNUIMessage({ action = 'atcEdit', on = false, keepOpen = atcWasOpen })
end

RegisterCommand('airhudmove', function()
    if not airHudVisible then
        notify('Get in a plane as pilot or front passenger to move the HUD.', 'error')
        return
    end
    if airHudEditing then airUiExitEdit() else airUiEnterEdit() end
end, false)
RegisterKeyMapping('airhudmove', 'Move/resize cockpit HUD + radio', 'keyboard', '')

RegisterNUICallback('airhudSavePos', function(data, cb)
    cb({})
    if data and data.left ~= nil then
        airHudPos = { left = data.left + 0.0, top = data.top + 0.0, scale = (data.scale or 1.0) + 0.0 }
        SetResourceKvp('airhud_ui', json.encode(airHudPos))
    end
end)

RegisterNUICallback('atcSavePos', function(data, cb)
    cb({})
    if data and data.left ~= nil then
        atcPos = { left = data.left + 0.0, top = data.top + 0.0, scale = (data.scale or 1.0) + 0.0 }
        SetResourceKvp('atc_ui', json.encode(atcPos))
    end
end)

RegisterNUICallback('uiEditExit', function(data, cb)
    cb({})
    airUiExitEdit()
end)

RegisterNUICallback('uiEditReset', function(data, cb)
    cb({})
    airHudPos = nil; atcPos = nil
    DeleteResourceKvp('airhud_ui'); DeleteResourceKvp('atc_ui')
    SendNUIMessage({ action = 'airhudEdit', on = true, reset = true })
    SendNUIMessage({ action = 'atcEdit', on = true, reset = true })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        if airHudEditing then SetNuiFocus(false, false) end
        if airHudVisible then jgHud(true) end
    end
end)
