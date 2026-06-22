local creatorOpen = false
local creatorAirports = {}
PartayAirports = PartayAirports or {}
local creatorBlips = {}
local placement = nil
local noclipActive = false
local noclipEntity
local restoringSafety = false
local previousPedCamMode
local previousVehicleCamMode
local airportTest = {
    active = false,
    airport = nil,
    runwayIndex = -1,
    directionIndex = -1
}
PartayCreatorSelection = PartayCreatorSelection or {
    airportId = nil,
    tab = 'overview',
    runwayZoneIndex = -1,
    directionZoneIndex = -1
}

local function notify(description, notifyType)
    lib.notify({ title = 'Airport Creator', description = description, type = notifyType or 'inform' })
end

local function showHelp(lines)
    local formatted = {}
    for i, line in ipairs(lines) do
        formatted[i] = i == 1 and line or ('- %s'):format(line)
    end

    lib.showTextUI(table.concat(formatted, '\n'), {
        position = Config.Creator.textUiPosition or 'right-center',
        icon = 'tower-broadcast'
    })
end

local function hideHelp()
    lib.hideTextUI()
end

local function controlPressed(control)
    return IsControlPressed(0, control) or IsDisabledControlPressed(0, control)
end

local function controlJustPressed(control)
    return IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control)
end

local function rotationToDirection(rotation)
    local adjustedRotation = vec3(math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z))
    local cosPitch = math.abs(math.cos(adjustedRotation.x))
    return vec3(-math.sin(adjustedRotation.z) * cosPitch, math.cos(adjustedRotation.z) * cosPitch, math.sin(adjustedRotation.x))
end

local function raycast(ignoreEntity)
    local from = GetGameplayCamCoord()
    local direction = rotationToDirection(GetGameplayCamRot(2))
    local to = from + direction * (Config.Creator.raycastDistance or Config.ZoneCreator.raycastDistance or 900.0)
    local handle = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, -1, ignoreEntity or cache.ped, 0)
    local _, hit, endCoords = GetShapeTestResult(handle)
    if hit == 1 then return vec3(endCoords.x, endCoords.y, endCoords.z) end
    return nil
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

local function pointInPolygon(coords, points)
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

local function zone2DInside(coords, zone)
    if not zone then return false end

    local zoneType = zone.type or 'sphere'
    if zoneType == 'poly' then
        return zone.points and #zone.points >= 3 and pointInPolygon(coords, zone.points)
    elseif zoneType == 'box' then
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

    local zoneCoords = asVec3(zone.coords)
    if not zoneCoords then return false end

    local horizontalDistance = #(vec3(coords.x, coords.y, zoneCoords.z) - vec3(zoneCoords.x, zoneCoords.y, zoneCoords.z))
    return horizontalDistance <= (zone.radius or 1.0)
end

local function zoneZBounds(zone)
    if not zone then return nil, nil end

    local zoneType = zone.type or 'sphere'
    if zoneType == 'poly' and zone.points and zone.points[1] then
        return zone.minZ or (zone.points[1].z - ((zone.thickness or 20.0) * 0.5)), zone.maxZ or (zone.points[1].z + ((zone.thickness or 20.0) * 0.5))
    elseif zoneType == 'box' then
        local zoneCoords = asVec3(zone.coords)
        if not zoneCoords then return nil, nil end
        return zone.minZ or (zoneCoords.z - ((zone.thickness or 10.0) * 0.5)), zone.maxZ or (zoneCoords.z + ((zone.thickness or 10.0) * 0.5))
    end

    local zoneCoords = asVec3(zone.coords)
    if not zoneCoords then return nil, nil end
    local radius = zone.radius or 1.0
    return zone.minZ or (zoneCoords.z - radius), zone.maxZ or (zoneCoords.z + radius)
end

local function insideZone(coords, zone)
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

local function selectedZoneCandidates(runway, direction, key)
    local candidates = {}
    addZoneCandidate(candidates, direction and direction.zones and direction.zones[key])
    addZoneCandidate(candidates, direction and direction[key])
    addZoneCandidate(candidates, runway and runway.zones and runway.zones[key])
    addZoneCandidate(candidates, runway and runway[key])
    return candidates
end

local function findZoneOnOtherRunway(airport, selectedRunway, key)
    for index, runway in ipairs(airport and airport.runways or {}) do
        if runway ~= selectedRunway then
            local candidates = selectedZoneCandidates(runway, nil, key)
            if #candidates > 0 then
                return runway.label or ('Runway %s'):format(index), #candidates
            end
        end
    end

    return nil, 0
end

local function insideAnyZone(coords, candidates)
    for _, zone in ipairs(candidates or {}) do
        if insideZone(coords, zone) then return true end
    end

    return false
end

local function getBoxCorners(zone)
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

local function drawGroundMarker(point, red, green, blue)
    local radius = point.radius or 2.0
    local coords = point.coords
    if not coords then return end

    DrawMarker(1, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, radius * 2.0, radius * 2.0, 2.5, red, green, blue, 120, false, false, 2, false, nil, nil, false)
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

local function airspaceVolumesForAirport(airportId)
    local volumes = {}
    for _, volume in ipairs(Config.AirspaceVolumes or {}) do
        if volume.airport == airportId then
            volumes[#volumes + 1] = volume
        end
    end
    return volumes
end

local function insideAirspaceVolume(coords, volume)
    if not coords or not volume or not volume.polygon or #volume.polygon < 3 then return false end

    local floor = tonumber(volume.floor) or 0.0
    local ceiling = tonumber(volume.ceiling) or 99999.0
    return coords.z >= floor and coords.z <= ceiling and pointInPolygon(coords, volume.polygon)
end

local function drawAirspaceSpheres(airport)
    if not airport or not airport.atc or not airport.atc.coords then return end
    normalizeKnownAirport(airport)
    if airport.airspace and airport.airspace.enabled == false then return end

    local center = asVec3(airport.atc.coords)
    if not center then return end

    if Config.Airspace and Config.Airspace.useVolumes ~= false then
        for _, volume in ipairs(airspaceVolumesForAirport(airport.id)) do
            drawAirspaceVolume(volume, airport.restricted and 220 or 20, airport.restricted and 80 or 160, airport.restricted and 80 or 255)
        end
        DrawMarker(2, center.x, center.y, center.z + 12.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 12.0, 12.0, 12.0, 20, 95, 180, 230, false, true, 2, false, nil, nil, false)
        DrawMarker(1, center.x, center.y, center.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 18.0, 18.0, 8.0, 20, 95, 180, 180, false, false, 2, false, nil, nil, false)
        return
    end

    local airspace = airport.airspace or {}
    local innerRadius = tonumber(airspace.radius) or tonumber(airport.atc.coverageRadius) or 2500.0
    local badRadius = innerRadius <= 0.0
    if badRadius then innerRadius = 120.0 end

    DrawMarker(28, center.x, center.y, center.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, innerRadius * 2.0, innerRadius * 2.0, innerRadius * 2.0, badRadius and 255 or 20, badRadius and 80 or 95, badRadius and 80 or 190, 55, false, false, 2, false, nil, nil, false)
    DrawMarker(2, center.x, center.y, center.z + 12.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 12.0, 12.0, 12.0, 20, 95, 180, 230, false, true, 2, false, nil, nil, false)
    DrawMarker(1, center.x, center.y, center.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 18.0, 18.0, 8.0, 20, 95, 180, 180, false, false, 2, false, nil, nil, false)

    local red, green, blue = badRadius and 255 or 20, badRadius and 80 or 160, badRadius and 80 or 255
    drawAirspaceBoundary(center, innerRadius, airspace.altitudeMin, airspace.altitudeMax, red, green, blue)
end

local function drawZone(zone, red, green, blue)
    if not zone then return end

    if (zone.type or 'sphere') == 'poly' and zone.points then
        for index, point in ipairs(zone.points) do
            local nextPoint = zone.points[index + 1] or zone.points[1]
            DrawMarker(28, point.x, point.y, point.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, red, green, blue, 170, false, false, 2, false, nil, nil, false)
            if nextPoint then
                DrawLine(point.x, point.y, point.z + 1.0, nextPoint.x, nextPoint.y, nextPoint.z + 1.0, red, green, blue, 220)
            end
        end
    elseif (zone.type or 'sphere') == 'box' then
        for index, point in ipairs(getBoxCorners(zone)) do
            local nextPoint = getBoxCorners(zone)[index + 1] or getBoxCorners(zone)[1]
            DrawMarker(28, point.x, point.y, point.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, red, green, blue, 170, false, false, 2, false, nil, nil, false)
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
    drawPolyFill(runwayZone, red, green, blue, 95)
    drawZone(runwayZone, red, green, blue)
end

local function drawHoldHighlight(zone, red, green, blue)
    if not zone then return end

    drawPolyFill(zone, red, green, blue, 85)
    drawZone(zone, red, green, blue)
end

local function drawZoneCandidates(candidates, red, green, blue)
    for _, zone in ipairs(candidates or {}) do
        drawZone(zone, red, green, blue)
    end
end

local function drawHoldCandidates(candidates, red, green, blue)
    for _, zone in ipairs(candidates or {}) do
        drawHoldHighlight(zone, red, green, blue)
    end
end

local function drawDirectionArrow(direction, red, green, blue)
    if not direction or not direction.threshold or not direction.departureEnd then return end

    local threshold = asVec3(direction.threshold)
    local departureEnd = asVec3(direction.departureEnd)
    local dx = departureEnd.x - threshold.x
    local dy = departureEnd.y - threshold.y
    local length = math.sqrt((dx * dx) + (dy * dy))
    if length <= 0.01 then return end

    local ux = dx / length
    local uy = dy / length
    local px = -uy
    local py = ux
    local z = threshold.z + 18.0
    local startX = threshold.x - (ux * 75.0)
    local startY = threshold.y - (uy * 75.0)
    local tipX = threshold.x + (ux * 135.0)
    local tipY = threshold.y + (uy * 135.0)
    local leftX = tipX - (ux * 42.0) + (px * 34.0)
    local leftY = tipY - (uy * 42.0) + (py * 34.0)
    local rightX = tipX - (ux * 42.0) - (px * 34.0)
    local rightY = tipY - (uy * 42.0) - (py * 34.0)

    DrawLine(startX, startY, z, tipX, tipY, z, red, green, blue, 255)
    DrawLine(tipX, tipY, z, leftX, leftY, z, red, green, blue, 255)
    DrawLine(tipX, tipY, z, rightX, rightY, z, red, green, blue, 255)
    DrawLine(leftX, leftY, z, rightX, rightY, z, red, green, blue, 220)
    DrawMarker(2, threshold.x, threshold.y, threshold.z + 8.0, 0.0, 0.0, 0.0, 0.0, 0.0, direction.heading or 0.0, 8.0, 8.0, 8.0, red, green, blue, 210, false, true, 2, false, nil, nil, false)
end

local function forceAircraftGearDown(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    pcall(function() SetVehicleLandingGear(vehicle, 0) end)
    pcall(function() ControlLandingGear(vehicle, 0) end)
end

local function createGizmoAnchor(coords, heading)
    local model = joaat('prop_mp_cone_02')
    lib.requestModel(model, 10000)

    local anchor = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(model)

    if anchor == 0 or not DoesEntityExist(anchor) then return nil end

    SetEntityAsMissionEntity(anchor, true, true)
    SetEntityHeading(anchor, heading or 0.0)
    SetEntityAlpha(anchor, 0, false)
    SetEntityVisible(anchor, false, false)
    SetEntityCollision(anchor, true, true)
    FreezeEntityPosition(anchor, false)

    return anchor
end

local function mirrorVehicleToAnchor(vehicle, anchor)
    if not DoesEntityExist(vehicle) or not DoesEntityExist(anchor) then return end

    local coords = GetEntityCoords(anchor)
    local rotation = GetEntityRotation(anchor, 2)
    SetEntityCoordsNoOffset(vehicle, coords.x, coords.y, coords.z, false, false, false)
    SetEntityRotation(vehicle, rotation.x, rotation.y, rotation.z, 2, true)
    SetEntityHeading(vehicle, GetEntityHeading(anchor))
    forceAircraftGearDown(vehicle)
end

local function getSafeGround(coords)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    for i = 1, 18 do
        local checkZ = coords.z + 80.0 - (i * 10.0)
        local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, checkZ, false)
        if found then
            return vec3(coords.x, coords.y, groundZ + 1.0)
        end
        Wait(0)
    end

    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1000.0, false)
    if found then
        return vec3(coords.x, coords.y, groundZ + 1.0)
    end

    return coords
end

local function restoreNoclipEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    local coords = GetEntityCoords(entity)
    local safe = getSafeGround(coords)

    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    SetEntityCoordsNoOffset(entity, safe.x, safe.y, safe.z, false, false, false)
    FreezeEntityPosition(entity, false)
    SetEntityCollision(entity, true, true)
end

local function setNoclip(enabled, keepPosition)
    noclipActive = enabled
    noclipEntity = GetVehiclePedIsIn(cache.ped, false)
    if noclipEntity == 0 then noclipEntity = cache.ped end

    if enabled then
        previousPedCamMode = GetFollowPedCamViewMode()
        previousVehicleCamMode = GetFollowVehicleCamViewMode()
        FreezeEntityPosition(noclipEntity, true)
        SetEntityCollision(noclipEntity, false, false)
        SetFollowPedCamViewMode(4)
        SetFollowVehicleCamViewMode(4)
    else
        local entity = noclipEntity
        if not keepPosition then restoreNoclipEntity(entity) end
        SetFollowPedCamViewMode(previousPedCamMode or 1)
        SetFollowVehicleCamViewMode(previousVehicleCamMode or 1)
        previousPedCamMode = nil
        previousVehicleCamMode = nil
        hideHelp()
        if not restoringSafety then
            restoringSafety = true
            CreateThread(function()
                SetEntityInvincible(cache.ped, true)
                SetPedCanRagdoll(cache.ped, false)
                Wait(3500)
                SetPedCanRagdoll(cache.ped, true)
                SetEntityInvincible(cache.ped, false)
                restoringSafety = false
            end)
        end
    end

    SetEntityInvincible(cache.ped, enabled or restoringSafety)
end

local function noclipTick()
    CreateThread(function()
        while noclipActive do
            Wait(0)
            local entity = noclipEntity or cache.ped
            local coords = GetEntityCoords(entity)
            local heading = GetGameplayCamRot(2).z
            local direction = rotationToDirection(GetGameplayCamRot(2))
            local right = vec3(math.cos(math.rad(heading)), math.sin(math.rad(heading)), 0.0)
            local speed = controlPressed(21) and (Config.Creator.noclipFastSpeed or 7.0) or (Config.Creator.noclipSpeed or 1.8)

            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 22, true)

            if controlPressed(32) then coords = coords + direction * speed * 0.1 end
            if controlPressed(33) then coords = coords - direction * speed * 0.1 end
            if controlPressed(35) then coords = coords + right * speed * 0.1 end
            if controlPressed(34) then coords = coords - right * speed * 0.1 end
            if controlPressed(22) then coords = coords + vec3(0, 0, speed * 0.1) end
            if controlPressed(36) then coords = coords - vec3(0, 0, speed * 0.1) end

            SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
            SetEntityHeading(entity, heading)
        end
    end)
end

local function openCreator()
    local allowed = lib.callback.await('partay_airlines:server:creatorCanOpen', false)
    if not allowed then
        notify('You do not have airport creator access.', 'error')
        return
    end

    local success, airports = lib.callback.await('partay_airlines:server:getCreatorAirports', false)
    if not success then
        notify(airports or 'Could not load airports.', 'error')
        return
    end

    creatorAirports = airports or {}
    creatorOpen = true
    SetNuiFocusKeepInput(false)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', airports = creatorAirports })
end

local function closeCreator()
    creatorOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function saveAirport(airport)
    local success, result = lib.callback.await('partay_airlines:server:saveCreatorAirport', false, airport)
    if success then
        notify('Airport saved.', 'success')
        return { success = true, airport = result }
    end
    notify(result or 'Airport save failed.', 'error')
    return { success = false, message = result }
end

local function clearCreatorBlips()
    for _, blip in ipairs(creatorBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    creatorBlips = {}
end

local function refreshCreatorBlips()
    clearCreatorBlips()

    for _, airport in ipairs(PartayAirports or {}) do
        local blipConfig = airport.blip or {}
        local coords = airport.atc and airport.atc.coords
        if blipConfig.enabled ~= false and coords then
            local blip = AddBlipForCoord(coords.x or 0.0, coords.y or 0.0, coords.z or 0.0)
            SetBlipSprite(blip, blipConfig.sprite or 90)
            SetBlipColour(blip, blipConfig.color or 3)
            SetBlipScale(blip, blipConfig.scale or 0.85)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(airport.label or airport.id or 'Airport')
            EndTextCommandSetBlipName(blip)
            creatorBlips[#creatorBlips + 1] = blip
        end
    end
end

local function sendPlacementResult(message)
    local placementData = message and message.placement or {}
    if placementData.airportId then
        local success, result = lib.callback.await('partay_airlines:server:patchCreatorAirport', false, placementData.airportId, message)
        if not success then
            notify(result or 'Could not save placement to airport.', 'error')
            message.saved = false
            message.error = result
        else
            message.saved = true
            message.airport = result
        end
    end

    openCreator()
    Wait(350)
    SendNUIMessage(message)
end

local function startPointPlacement(data)
    closeCreator()
    Wait(150)
    setNoclip(true)
    noclipTick()
    showHelp({
        'Airport Creator: Point Placement',
        'WASD: move noclip',
        'Aim camera at target',
        'E: capture point',
        'Backspace: cancel'
    })

    CreateThread(function()
        local done = false
        while not done do
            Wait(0)
            local hit = raycast()
            if hit then
                DrawMarker(28, hit.x, hit.y, hit.z, 0, 0, 0, 0, 0, 0, Config.Creator.raycastMarkerSize or 0.35, Config.Creator.raycastMarkerSize or 0.35, Config.Creator.raycastMarkerSize or 0.35, 80, 220, 255, 230, false, false, 2, false, nil, nil, false)
            end
            if controlJustPressed(38) and hit then
                local heading = GetEntityHeading(cache.ped)
                setNoclip(false)
                done = true
                sendPlacementResult({ action = 'pointPlaced', placement = data, target = data.target, point = { x = hit.x, y = hit.y, z = hit.z, w = heading } })
            elseif controlJustPressed(177) then
                setNoclip(false)
                done = true
                openCreator()
            end
        end
    end)
end

local function startPolyPlacement(data)
    closeCreator()
    Wait(150)
    setNoclip(true)
    noclipTick()
    local points = {}
    local sameZ = true
    local done = false
    showHelp({
        'Airport Creator: Raycast Poly',
        'WASD: move noclip',
        'E: add point',
        'Backspace: undo',
        'G: toggle same-Z',
        'Enter: save with 4+ points',
        'Delete: cancel'
    })

    CreateThread(function()
        while not done do
            Wait(0)
            local hit = raycast()
            if hit and sameZ and points[1] then hit = vec3(hit.x, hit.y, points[1].z) end
            for i, point in ipairs(points) do
                local nextPoint = points[i + 1] or (#points >= 4 and points[1] or nil)
                DrawMarker(28, point.x, point.y, point.z, 0, 0, 0, 0, 0, 0, 1.3, 1.3, 1.3, 255, 150, 80, 210, false, false, 2, false, nil, nil, false)
                if nextPoint then DrawLine(point.x, point.y, point.z + 1.0, nextPoint.x, nextPoint.y, nextPoint.z + 1.0, 255, 150, 80, 220) end
            end
            if hit then
                DrawMarker(28, hit.x, hit.y, hit.z, 0, 0, 0, 0, 0, 0, Config.Creator.raycastMarkerSize or 0.35, Config.Creator.raycastMarkerSize or 0.35, Config.Creator.raycastMarkerSize or 0.35, 80, 220, 255, 230, false, false, 2, false, nil, nil, false)
                if points[#points] then
                    local last = points[#points]
                    DrawLine(last.x, last.y, last.z + 1.0, hit.x, hit.y, hit.z + 1.0, 80, 220, 255, 190)
                end
            end
            if controlJustPressed(38) and hit then
                points[#points + 1] = hit
                notify(('Point %s added.'):format(#points), 'inform')
            elseif controlJustPressed(177) and #points > 0 then
                points[#points] = nil
                notify(('Point removed. Current: %s.'):format(#points), 'inform')
            elseif controlJustPressed(47) then
                sameZ = not sameZ
                notify(sameZ and 'Same-Z snapping on.' or 'Same-Z snapping off.', 'inform')
            elseif controlJustPressed(191) then
                if #points >= 4 then
                    setNoclip(false)
                    done = true
                    sendPlacementResult({ action = 'polyPlaced', placement = data, points = points })
                else
                    notify(('Poly zones need at least 4 points. Current: %s.'):format(#points), 'error')
                end
            elseif controlJustPressed(178) then
                setNoclip(false)
                done = true
                openCreator()
            end
        end
    end)
end

local function startSimpleZonePlacement(data)
    closeCreator()
    Wait(150)
    setNoclip(true)
    noclipTick()
    showHelp({
        ('Airport Creator: %s Zone'):format(data.mode),
        'WASD: move noclip',
        'Aim camera at center',
        'E: capture',
        'Backspace: cancel'
    })

    CreateThread(function()
        local done = false
        while not done do
            Wait(0)
            local hit = raycast()
            if hit then
                DrawMarker(28, hit.x, hit.y, hit.z, 0, 0, 0, 0, 0, 0, Config.Creator.raycastMarkerSize or 0.35, Config.Creator.raycastMarkerSize or 0.35, Config.Creator.raycastMarkerSize or 0.35, 80, 220, 255, 230, false, false, 2, false, nil, nil, false)
            end

            if controlJustPressed(38) and hit then
                setNoclip(false)
                done = true
                openCreator()
                local zone
                if data.mode == 'box' then
                    zone = {
                        type = 'box',
                        label = data.zoneKey or 'Box Zone',
                        coords = { x = hit.x, y = hit.y, z = hit.z },
                        length = Config.ZoneCreator.defaultBoxLength,
                        width = Config.ZoneCreator.defaultBoxWidth,
                        heading = GetGameplayCamRot(2).z,
                        thickness = Config.ZoneCreator.defaultThickness
                    }
                else
                    zone = {
                        type = 'sphere',
                        label = data.zoneKey or 'Sphere Zone',
                        coords = { x = hit.x, y = hit.y, z = hit.z },
                        radius = Config.ZoneCreator.defaultRadius
                    }
                end
                sendPlacementResult({ action = 'zonePlaced', placement = data, zone = zone })
            elseif controlJustPressed(177) then
                setNoclip(false)
                done = true
                openCreator()
            end
        end
    end)
end

local function startGhostGate(data)
    closeCreator()
    Wait(150)
    if GetResourceState('object_gizmo') ~= 'started' then
        notify('object_gizmo must be started before using gate plane placement.', 'error')
        openCreator()
        return
    end

    setNoclip(true, true)
    noclipTick()
    showHelp({
        'Airport Creator: Gizmo Plane',
        'Noclip is active for camera movement',
        'W: translate mode',
        'R: rotate mode',
        'Q: local/world mode',
        'LAlt: snap plane to ground',
        'Enter: save gate placement'
    })

    CreateThread(function()
        local modelName = data.aircraftModel or 'shamal'
        local model = joaat(modelName)
        lib.requestModel(model, 10000)
        local spawn = data.aircraftSpawn
        local coords = spawn and vec3(spawn.x, spawn.y, spawn.z) or raycast()
        if not coords then
            coords = GetEntityCoords(cache.ped) + GetEntityForwardVector(cache.ped) * 8.0
        end
        if not spawn then coords = getSafeGround(coords) end

        local vehicle = CreateVehicle(model, coords.x, coords.y, coords.z, spawn and spawn.w or GetEntityHeading(cache.ped), false, false)
        SetModelAsNoLongerNeeded(model)
        if vehicle == 0 or not DoesEntityExist(vehicle) then
            setNoclip(false)
            hideHelp()
            notify('Could not create ghost aircraft.', 'error')
            openCreator()
            return
        end

        SetEntityAsMissionEntity(vehicle, true, true)
        forceAircraftGearDown(vehicle)
        SetVehicleOnGroundProperly(vehicle)
        local anchorCoords = GetEntityCoords(vehicle)
        local anchor = createGizmoAnchor(anchorCoords, GetEntityHeading(vehicle))
        if not anchor then
            DeleteEntity(vehicle)
            setNoclip(false)
            hideHelp()
            notify('Could not create gizmo anchor.', 'error')
            openCreator()
            return
        end

        SetEntityAlpha(vehicle, Config.ZoneCreator.ghostAlpha or 120, false)
        SetEntityCollision(vehicle, true, true)
        SetEntityNoCollisionEntity(vehicle, cache.ped, true)
        SetEntityHasGravity(vehicle, false)
        FreezeEntityPosition(vehicle, true)
        SetEntityInvincible(vehicle, true)
        SetVehicleDoorsLocked(vehicle, 2)
        SetVehicleUndriveable(vehicle, true)
        SetVehicleEngineOn(vehicle, false, true, true)
        forceAircraftGearDown(vehicle)

        local editing = true
        CreateThread(function()
            while editing do
                Wait(0)
                if not DoesEntityExist(vehicle) or not DoesEntityExist(anchor) then
                    editing = false
                    return
                end

                mirrorVehicleToAnchor(vehicle, anchor)

                if controlJustPressed(19) then
                    Wait(60)
                    mirrorVehicleToAnchor(vehicle, anchor)
                    SetVehicleOnGroundProperly(vehicle)
                    local grounded = GetEntityCoords(vehicle)
                    SetEntityCoordsNoOffset(anchor, grounded.x, grounded.y, grounded.z, false, false, false)
                end
            end
        end)

        local result = exports.object_gizmo:useGizmo(anchor)
        editing = false
        Wait(0)
        mirrorVehicleToAnchor(vehicle, anchor)
        forceAircraftGearDown(vehicle)

        local finalCoords = result and result.position or GetEntityCoords(anchor)
        local heading = DoesEntityExist(anchor) and GetEntityHeading(anchor) or GetEntityHeading(vehicle)
        FreezeEntityPosition(vehicle, true)
        DeleteEntity(vehicle)
        if DoesEntityExist(anchor) then DeleteEntity(anchor) end
        setNoclip(false)
        hideHelp()

        sendPlacementResult({
            action = 'ghostPlaced',
            placement = data,
            gate = {
                id = data.gateId or data.id,
                label = data.label or 'Gate',
                gate = data.gate or 'A1',
                aircraftModel = modelName,
                aircraftSpawn = { x = finalCoords.x, y = finalCoords.y, z = finalCoords.z, w = heading },
                aircraftBoardingRadius = data.aircraftBoardingRadius or data.boardingRadius or Config.ZoneCreator.defaultBoardingRadius
            }
        })
    end)
end

local function testZoneLine(label, coords, zone)
    if not zone then return ('%s: missing'):format(label) end
    local inside = insideZone(coords, zone)
    local inside2D = zone2DInside(coords, zone)
    local minZ, maxZ = zoneZBounds(zone)

    if minZ and maxZ then
        local zState = coords.z >= minZ and coords.z <= maxZ and 'Z ok' or 'Z outside'
        return ('%s: %s | 2D %s | %s %.1f in %.1f-%.1f'):format(label, inside and 'INSIDE' or 'outside', inside2D and 'yes' or 'no', zState, coords.z, minZ, maxZ)
    end

    return ('%s: %s | 2D %s'):format(label, inside and 'INSIDE' or 'outside', inside2D and 'yes' or 'no')
end

local function testZoneCandidatesLine(label, coords, candidates, airport, selectedRunway)
    if not candidates or #candidates == 0 then
        local otherRunway, count = findZoneOnOtherRunway(airport, selectedRunway, label)
        if otherRunway then
            return ('%s: missing on selected runway | found %s on %s'):format(label, count, otherRunway)
        end

        return ('%s: missing'):format(label)
    end

    if #candidates == 1 then
        return testZoneLine(label, coords, candidates[1])
    end

    return ('%s: %s | %s zones on selected runway'):format(label, insideAnyZone(coords, candidates) and 'INSIDE ANY' or 'outside all', #candidates)
end

local function testGroundDistance(entity)
    local coords = GetEntityCoords(entity)
    local hasGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, false)
    if not hasGround then return coords.z end
    return coords.z - groundZ
end

local function testZoneAltitude(entity, coords, zone)
    if zone and zone.baseZ then
        return coords.z - zone.baseZ, 'base'
    end

    if zone and zone.glideSlope and zone.glideSlope.threshold then
        return coords.z - zone.glideSlope.threshold.z, 'threshold'
    end

    if zone and zone.points and zone.points[1] then
        return coords.z - zone.points[1].z, 'zone'
    end

    return testGroundDistance(entity), 'ground'
end

local function testGlideLine(entity, coords, zone)
    local glide = zone and zone.glideSlope
    if not zone then return 'glide path: missing' end
    if not glide or not glide.threshold or not glide.axis then return 'glide path: no slope data' end

    local threshold = glide.threshold
    local axis = glide.axis
    local dx = coords.x - threshold.x
    local dy = coords.y - threshold.y
    local distanceFromThreshold = math.max(0.0, -((dx * axis.x) + (dy * axis.y)))
    local progress = math.min(distanceFromThreshold / math.max(glide.length or 1.0, 1.0), 1.0)
    local allowed = (glide.thresholdAltitude or 140.0) + (((glide.outerAltitude or zone.altitudeMax or 900.0) - (glide.thresholdAltitude or 140.0)) * progress)
    local actual, source = testZoneAltitude(entity, coords, zone)
    local tolerance = glide.tolerance or 0.0
    local status = actual <= (allowed + tolerance) and 'OK' or 'too high'
    local groundActual = testGroundDistance(entity)

    return ('glide path: %s %.1fm %s / allowed %.1fm / ground %.1fm'):format(status, actual, source, allowed + tolerance, groundActual)
end

local function testAirspaceLine(coords, airport)
    if not airport or not airport.atc or not airport.atc.coords then return 'airspace: no ATC center set' end
    normalizeKnownAirport(airport)
    if airport.airspace and airport.airspace.enabled == false then return 'airspace: disabled' end

    if Config.Airspace and Config.Airspace.useVolumes ~= false then
        local volumes = airspaceVolumesForAirport(airport.id)
        for _, volume in ipairs(volumes) do
            if insideAirspaceVolume(coords, volume) then
                local label = volume.facility or volume.controller or volume.id or 'volume'
                local class = volume.class and (' class %s'):format(volume.class) or ''
                return ('airspace volume: INSIDE %s%s | Z %.0f-%.0f'):format(label, class, tonumber(volume.floor) or 0.0, tonumber(volume.ceiling) or 0.0)
            end
        end

        if #volumes > 0 then
            return ('airspace volume: outside | %s shelves | Z %.0f'):format(#volumes, coords.z)
        end

        if not (Config.Airspace and Config.Airspace.allowRadiusFallback) then
            return 'airspace volume: no shelves configured'
        end
    end

    local airspace = airport.airspace or {}
    local center = asVec3(airport.atc.coords)
    if not center then return 'airspace: no ATC center set' end

    local innerRadius = tonumber(airspace.radius) or tonumber(airport.atc.coverageRadius) or 2500.0
    local distance = #(vec3(coords.x, coords.y, center.z) - vec3(center.x, center.y, center.z))
    local minAlt = tonumber(airspace.altitudeMin) or 0.0
    local maxAlt = tonumber(airspace.altitudeMax) or 99999.0
    local bubbleInside = distance <= innerRadius and coords.z >= minAlt and coords.z <= maxAlt
    local bubbleLine = ('bubble: %s | dist %.0fm / radius %.0fm / Z %.0f-%.0f'):format(bubbleInside and 'INSIDE' or 'outside', distance, innerRadius, minAlt, maxAlt)

    if airspace.controlledZone then
        return ('%s | custom poly saved inactive'):format(bubbleLine)
    end

    return bubbleLine
end

local function startAirportTest(data)
    local airport = data and data.airport
    if not airport then
        notify('No airport selected for testing.', 'error')
        return
    end

    local runways = airport.runways or {}
    local runwayIndex = tonumber(data.runwayIndex) or -1
    if (runwayIndex < 0 or not runways[runwayIndex + 1]) and #runways > 0 then
        runwayIndex = 0
    end

    local runway = runways[runwayIndex + 1]
    local directionIndex = tonumber(data.directionIndex) or -1
    if runway and (directionIndex < 0 or not (runway.directions or {})[directionIndex + 1]) and #(runway.directions or {}) > 0 then
        directionIndex = 0
    end

    closeCreator()
    airportTest.active = false
    Wait(100)

    airportTest = {
        active = true,
        airport = airport,
        runwayIndex = runwayIndex,
        directionIndex = directionIndex
    }

    notify('Airport test mode started. Drive or fly through zones. Backspace exits.', 'success')

    CreateThread(function()
        while airportTest.active do
            Wait(0)

            local ped = cache.ped
            local vehicle = GetVehiclePedIsIn(ped, false)
            local entity = vehicle ~= 0 and vehicle or ped
            local coords = GetEntityCoords(entity)
            local airportData = airportTest.airport
            local runway = (airportData.runways or {})[(airportTest.runwayIndex or -1) + 1]
            local direction = runway and (runway.directions or {})[(airportTest.directionIndex or -1) + 1]
            local zones = {}
            for _, key in ipairs({ 'taxiHold', 'takeoffHold', 'takeoffZone', 'approachZone', 'landingZone' }) do
                zones[key] = selectedZoneCandidates(runway, direction, key)
            end
            local runwayZone = runwaySurfaceZone(runway)

            drawAirspaceSpheres(airportData)
            if runwayZone then drawRunwayHighlight(runway, 80, 255, 180) end
            if direction then drawDirectionArrow(direction, 80, 255, 120) end
            if zones then
                drawHoldCandidates(zones.taxiHold, 255, 220, 80)
                drawHoldCandidates(zones.takeoffHold, 255, 70, 70)
                drawZoneCandidates(zones.takeoffZone, 80, 200, 255)
                drawZoneCandidates(zones.approachZone, 120, 210, 255)
                drawZoneCandidates(zones.landingZone, 80, 255, 120)
            end

            for _, gate in ipairs(airportData.gates or {}) do
                local spawn = gate.aircraftSpawn or gate.coords
                if spawn then
                    drawGroundMarker({ coords = vec3(spawn.x, spawn.y, spawn.z), radius = gate.aircraftBoardingRadius or gate.radius or 28.0 }, 180, 120, 255)
                end
            end

            if controlJustPressed(177) then
                airportTest.active = false
                hideHelp()
                openCreator()
                return
            end

            if GetGameTimer() % 250 < 16 then
                local runwayLabel = runway and (runway.label or ('Runway %s'):format((airportTest.runwayIndex or 0) + 1)) or 'No runway selected'
                local directionLabel = direction and (direction.label or ('Direction %s'):format((airportTest.directionIndex or 0) + 1)) or 'manual runway zones'
                local speed = vehicle ~= 0 and (GetEntitySpeed(vehicle) * 2.236936) or 0.0

                showHelp({
                    ('Airport Test: %s'):format(airportData.label or airportData.id or 'Airport'),
                    ('Runway: %s'):format(runwayLabel),
                    ('Direction: %s'):format(directionLabel),
                    ('Speed: %.1f mph / Alt Z: %.1f'):format(speed, coords.z),
                    testAirspaceLine(coords, airportData),
                    runwayZone and testZoneLine('runway surface', coords, runwayZone) or 'runway surface: missing',
                    testZoneCandidatesLine('taxiHold', coords, zones and zones.taxiHold, airportData, runway),
                    testZoneCandidatesLine('takeoffHold', coords, zones and zones.takeoffHold, airportData, runway),
                    testZoneCandidatesLine('takeoffZone', coords, zones and zones.takeoffZone, airportData, runway),
                    testZoneCandidatesLine('approachZone', coords, zones and zones.approachZone, airportData, runway),
                    testGlideLine(entity, coords, zones and zones.approachZone and zones.approachZone[1]),
                    testZoneCandidatesLine('landingZone', coords, zones and zones.landingZone, airportData, runway),
                    ('airport gates: %s'):format(#(airportData.gates or {})),
                    'Backspace: exit test'
                })
            end
        end

        hideHelp()
    end)
end

local function selectedCreatorAirport()
    local selection = PartayCreatorSelection or {}
    if selection.airport then return normalizeKnownAirport(selection.airport) end

    if selection.airportId then
        for _, airport in ipairs(creatorAirports or {}) do
            if airport.id == selection.airportId then return normalizeKnownAirport(airport) end
        end
    end

    return nil
end

CreateThread(function()
    while true do
        Wait(0)

        if creatorOpen then
            local airport = selectedCreatorAirport()
            if airport then
                drawAirspaceSpheres(airport)
                local selection = PartayCreatorSelection or {}
                local runway = airport.runways and airport.runways[(tonumber(selection.runwayZoneIndex) or -1) + 1]
                if runway then
                    drawRunwayHighlight(runway, 80, 255, 180)
                    local direction = (runway.directions or {})[(tonumber(selection.directionZoneIndex) or -1) + 1]
                    drawHoldCandidates(selectedZoneCandidates(runway, direction, 'taxiHold'), 255, 220, 80)
                    drawHoldCandidates(selectedZoneCandidates(runway, direction, 'takeoffHold'), 255, 70, 70)
                    if direction then drawDirectionArrow(direction, 80, 255, 120) end
                end
            end
        end
    end
end)

RegisterNUICallback('creatorClose', function(_, cb)
    closeCreator()
    cb({ success = true })
end)

RegisterNUICallback('creatorSaveAirport', function(data, cb)
    cb(saveAirport(data))
end)

RegisterNUICallback('creatorPatchAirport', function(data, cb)
    if not data or not data.airportId then
        cb({ success = false, message = 'Airport ID required.' })
        return
    end

    local success, result = lib.callback.await('partay_airlines:server:patchCreatorAirport', false, data.airportId, data.patch)
    cb({ success = success, result = result })
end)

RegisterNUICallback('creatorSelection', function(data, cb)
    PartayCreatorSelection = {
        airportId = data and data.airportId or nil,
        airport = data and data.airport or nil,
        tab = data and data.tab or 'overview',
        runwayZoneIndex = tonumber(data and data.runwayZoneIndex) or -1,
        directionZoneIndex = tonumber(data and data.directionZoneIndex) or -1
    }
    cb({ success = true })
end)

RegisterNUICallback('creatorPlace', function(data, cb)
    if data.mode == 'point' then
        startPointPlacement(data)
    elseif data.mode == 'poly' then
        startPolyPlacement(data)
    elseif data.mode == 'box' or data.mode == 'sphere' then
        startSimpleZonePlacement(data)
    elseif data.mode == 'ghostGate' then
        startGhostGate(data)
    else
        notify('That placement mode is not implemented yet.', 'error')
    end
    cb({ success = true })
end)

RegisterNUICallback('creatorTestAirport', function(data, cb)
    startAirportTest(data)
    cb({ success = true })
end)

RegisterNUICallback('creatorCurrentPoint', function(data, cb)
    local coords = GetEntityCoords(cache.ped)
    SendNUIMessage({ action = 'pointPlaced', placement = data, target = data.target, point = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(cache.ped) } })
    cb({ success = true })
end)

RegisterNetEvent('partay_airlines:client:airportsUpdated', function(airports)
    creatorAirports = airports or {}
    for _, airport in ipairs(creatorAirports) do normalizeKnownAirport(airport) end
    PartayAirports = creatorAirports
    refreshCreatorBlips()
    SendNUIMessage({ action = 'airports', airports = creatorAirports })
end)

RegisterCommand(Config.Creator.command, openCreator, false)
RegisterCommand(Config.ZoneCreator.command, openCreator, false)

CreateThread(function()
    Wait(3000)
    creatorAirports = lib.callback.await('partay_airlines:server:getRuntimeAirports', false) or {}
    for _, airport in ipairs(creatorAirports) do normalizeKnownAirport(airport) end
    PartayAirports = creatorAirports
    refreshCreatorBlips()
end)
