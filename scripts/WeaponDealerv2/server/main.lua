Server = Server or {}
Server.Scans = Server.Scans or {}
Server.Orders = Server.Orders or {}

local cooldowns = {}

function Server.CheckCooldown(source, action)
    local now = os.time()
    cooldowns[source] = cooldowns[source] or {}

    if cooldowns[source][action] and now - cooldowns[source][action] < Config.Security.ServerCooldownSeconds then
        return false
    end

    cooldowns[source][action] = now
    return true
end

function Server.GetStore(storeId)
    for _, store in ipairs(Config.Stores) do
        if store.id == storeId then return store end
    end
end

function Server.GetWeapon(item)
    for _, weapon in ipairs(Config.Weapons) do
        if weapon.item == item then return weapon end
    end
end

function Server.IsNear(source, coords, distance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    return #(playerCoords - vector3(coords.x, coords.y, coords.z)) <= (distance or Config.Security.MaxInteractDistance)
end

local function isPointInPoly(point, points)
    local inside = false
    local count = #points
    if count < 3 then return false end

    local previous = points[count]
    for index = 1, count do
        local current = points[index]
        local intersects = ((current.y > point.y) ~= (previous.y > point.y))
            and (point.x < (previous.x - current.x) * (point.y - current.y) / ((previous.y - current.y) + 0.0) + current.x)

        if intersects then
            inside = not inside
        end

        previous = current
    end

    return inside
end

function Server.IsInStoreZone(source, store)
    if not store or not store.storeZone then return false end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local coords = GetEntityCoords(ped)
    local zone = store.storeZone

    if zone.type == 'poly' and zone.points then
        local minZ = tonumber(zone.minZ or -9999.0) or -9999.0
        local maxZ = tonumber(zone.maxZ or 9999.0) or 9999.0
        if coords.z < minZ or coords.z > maxZ then return false end

        return isPointInPoly(coords, zone.points)
    end

    return Server.IsNear(source, zone.coords, zone.radius)
end

function Server.Notify(source, key, notifyType, vars)
    TriggerClientEvent('qbx_weapondealer:client:notify', source, WD.Locale(key, vars), notifyType or 'inform')
end

lib.callback.register('qbx_weapondealer:server:isAuthorized', function(source, action)
    local allowed = Bridge.Framework.IsAuthorized(source, action)
    return allowed == true
end)

lib.callback.register('qbx_weapondealer:server:getPlayerLabels', function(source, targets)
    local labels = {}

    if type(targets) ~= 'table' then
        return labels
    end

    for _, target in ipairs(targets) do
        local targetSource = tonumber(target)
        if targetSource and GetPlayerPed(targetSource) ~= 0 then
            local name = Bridge.Framework.GetName(targetSource)
            labels[targetSource] = {
                source = targetSource,
                name = name,
                label = ('%s | ID %s%s'):format(name, targetSource, targetSource == source and ' | You' or '')
            }
        end
    end

    return labels
end)

RegisterCommand('wdjob', function(source)
    if source == 0 then
        print(('[%s] /wdjob must be run by an in-game player.'):format(WD.Resource))
        return
    end

    local job = Bridge.Framework.GetJob(source)
    local scanAllowed, scanReason = Bridge.Framework.IsAuthorized(source, 'Scan')
    local message = ('source=%s name=%s expected=%s actual=%s grade=%s duty=%s requireDuty=%s scan=%s(%s)'):format(
        source,
        GetPlayerName(source) or 'unknown',
        Config.Job.Name,
        job and job.name or 'none',
        job and tostring(job.grade) or 'none',
        job and tostring(job.duty) or 'none',
        tostring(Config.Job.RequireDuty),
        tostring(scanAllowed == true),
        scanReason or 'ok'
    )

    print(('[%s] WDJOB: %s'):format(WD.Resource, message))
    TriggerClientEvent('qbx_weapondealer:client:notify', source, message, scanAllowed and 'success' or 'error')
end, false)

AddEventHandler('playerDropped', function()
    local source = source
    if Server.Scans then
        Server.Scans.ClearBuyer(source)
        Server.Scans.ClearForEmployee(source)
    end
end)
