local function copyTableShallow(source)
    local copy = {}
    if type(source) ~= 'table' then
        return copy
    end

    for key, value in pairs(source) do
        copy[key] = value
    end

    return copy
end

local function buildLegacyZoneTables()
    local legacyDanceZones = {}
    local legacyPoles = {}

    if type(Config.ClubZones) ~= 'table' or #Config.ClubZones == 0 then
        return legacyDanceZones, legacyPoles
    end

    for zoneIndex, clubZone in ipairs(Config.ClubZones) do
        if type(clubZone) ~= 'table' then goto continue end

        local zoneId = clubZone.id or ('club_zone_%d'):format(zoneIndex)
        local zoneLabel = clubZone.label or zoneId
        local zoneSociety = copyTableShallow(clubZone.society)
        local danceArea = type(clubZone.danceArea) == 'table' and clubZone.danceArea or {}
        local defaultPoleDanceArea = type(clubZone.poleDanceAreaDefaults) == 'table' and clubZone.poleDanceAreaDefaults or {}

        if danceArea.coords then
            legacyDanceZones[#legacyDanceZones + 1] = {
                id = zoneId,
                label = danceArea.label or zoneLabel,
                coords = danceArea.coords,
                radius = danceArea.radius or 4.0,
                heading = danceArea.heading,
                society = next(zoneSociety) and zoneSociety or nil,
                animations = danceArea.animations
            }
        end

        if type(clubZone.poles) == 'table' then
            for poleIndex, pole in ipairs(clubZone.poles) do
                if type(pole) ~= 'table' or not pole.coords then goto pole_continue end

                local poleEntry = copyTableShallow(pole)
                poleEntry.id = poleEntry.id or ('%s_pole_%d'):format(zoneId, poleIndex)
                poleEntry.label = poleEntry.label or zoneLabel
                poleEntry.zoneId = poleEntry.zoneId or zoneId

                if next(zoneSociety) and poleEntry.society == nil then
                    poleEntry.society = copyTableShallow(zoneSociety)
                end

                local poleDanceArea = {}
                if type(defaultPoleDanceArea) == 'table' then
                    poleDanceArea = copyTableShallow(defaultPoleDanceArea)
                end
                if type(pole.danceArea) == 'table' then
                    for key, value in pairs(pole.danceArea) do
                        poleDanceArea[key] = value
                    end
                end

                if next(poleDanceArea) and poleDanceArea.enabled ~= false then
                    local areaId = poleDanceArea.id or ('%s_dance_area'):format(poleEntry.id)
                    local areaCoords = poleDanceArea.coords
                    local offset = poleDanceArea.offset

                    if not areaCoords and type(offset) == 'vector3' and type(pole.coords) == 'vector3' then
                        areaCoords = vector3(
                            pole.coords.x + offset.x,
                            pole.coords.y + offset.y,
                            pole.coords.z + offset.z
                        )
                    end

                    areaCoords = areaCoords or pole.coords

                    legacyDanceZones[#legacyDanceZones + 1] = {
                        id = areaId,
                        label = poleDanceArea.label or ((poleEntry.label or zoneLabel) .. ' Dance Area'),
                        coords = areaCoords,
                        radius = poleDanceArea.radius or 4.0,
                        heading = poleDanceArea.heading or poleEntry.heading,
                        society = next(zoneSociety) and copyTableShallow(zoneSociety) or nil,
                        animations = poleDanceArea.animations or danceArea.animations,
                        poleId = poleEntry.id
                    }

                    if poleDanceArea.bindToPole ~= false then
                        poleEntry.zoneId = areaId
                    end
                end

                legacyPoles[#legacyPoles + 1] = poleEntry
                ::pole_continue::
            end
        end

        ::continue::
    end

    return legacyDanceZones, legacyPoles
end

Config.DanceZones, Config.Poles = buildLegacyZoneTables()
