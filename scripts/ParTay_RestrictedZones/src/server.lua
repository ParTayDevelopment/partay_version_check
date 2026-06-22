local resourceName = GetCurrentResourceName()

lib.locale()
if Config.Locale then pcall(function() lib.setLocale(Config.Locale) end) end

-- Framework bridge (server-side)
local Framework = { name = 'standalone' }

CreateThread(function()
    if GetResourceState('es_extended') == 'started' then
        Framework.name = 'esx'
        local ok, obj = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and obj then ESX = obj end
        print(('[%s] Server framework detected: ESX'):format(resourceName))
        return
    end
    local coreName
    if GetResourceState('qb-core') == 'started' then coreName = 'qb-core' end
    if not coreName and GetResourceState('qbx-core') == 'started' then coreName = 'qbx-core' end
    if coreName then
        Framework.name = 'qb'
        local ok, obj = pcall(function()
            return exports[coreName]:GetCoreObject()
        end)
        if ok and obj then QBCore = obj end
        print(('[%s] Server framework detected: %s'):format(resourceName, coreName))
        return
    end
    print(('[%s] Server framework: standalone'):format(resourceName))
end)

local function getPlayerJob(src)
    if Framework.name == 'esx' and ESX and ESX.GetPlayerFromId then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.job then
            local j = xPlayer.job
            return j.name, j.grade or j.grade_level, j.grade_name or j.grade_label
        end
    elseif Framework.name == 'qb' and QBCore and QBCore.Functions and QBCore.Functions.GetPlayer then
        local qbply = QBCore.Functions.GetPlayer(src)
        if qbply and qbply.PlayerData and qbply.PlayerData.job then
            local j = qbply.PlayerData.job
            local lvl = (j.grade and (j.grade.level or tonumber(j.grade))) or nil
            local gnm = (j.grade and (j.grade.name or tostring(j.grade))) or nil
            return j.name, lvl, gnm
        end
    end
    return nil, nil, nil
end

-- Wristband tracking (server authoritative)
local wristband = {}      -- [src][zoneName] = expireAt (os.time seconds)

local function hasWristband(src, zoneName)
    local z = wristband[src]
    if not z then return false end
    local exp = z[zoneName]
    if not exp then return false end
    if os.time() <= exp then return true end
    z[zoneName] = nil
    return false
end

local function grantWristband(src, zoneName)
    wristband[src] = wristband[src] or {}
    wristband[src][zoneName] = os.time() + (tonumber(Config.WristBandTime) or 300)
end

AddEventHandler('playerDropped', function()
    local src = source
    wristband[src] = nil
end)

-- Access check callback (authoritative on server)
lib.callback.register(resourceName .. ':server:CheckAccess', function(src, zoneName)
    if type(zoneName) ~= 'string' then return false, { type = 'invalid' } end
    local zoneCfg = Config.Zones and Config.Zones[zoneName]
    if not zoneCfg then return false, { type = 'invalid' } end

    -- Wristband grace
    if hasWristband(src, zoneName) then
        return true, { type = 'wristband' }
    end

    -- Job allowlist
    local jobAllowed = false
    if zoneCfg.jobs and next(zoneCfg.jobs) then
        local jname = getPlayerJob(src)
        if jname then
            for _, allowed in pairs(zoneCfg.jobs) do
                if allowed == jname then jobAllowed = true break end
            end
        end
    end

    -- Items requirement
    local requiresItem = false
    local itemsList = zoneCfg.items
    local hasItemsConfigured = itemsList and next(itemsList)
    local mustCheckItems = hasItemsConfigured and (not jobAllowed or Config.RequireItemEvenWithJob)
    local usedItem = nil
    if mustCheckItems then
        requiresItem = true
        if type(itemsList) ~= 'table' then itemsList = { itemsList } end
        for _, itemName in ipairs(itemsList) do
            local count = exports.ox_inventory:Search(src, 'count', itemName) or 0
            if count > 0 then
                usedItem = itemName
                break
            end
        end
        if usedItem then
            if zoneCfg.removeItem then
                exports.ox_inventory:RemoveItem(src, usedItem, 1)
            end
            grantWristband(src, zoneName)
            return true, { type = 'item', used = usedItem }
        end
    end

    -- If job allowed and item not required
    if jobAllowed and not mustCheckItems then
        return true, { type = 'job' }
    end

    -- Denied
    if requiresItem and not usedItem then
        -- send back names; client will map to labels for localization
        return false, { type = 'item', items = itemsList }
    end
    return false, { type = 'job' }
end)

-- Backwards compatibility: noop if called directly; keep to avoid errors
RegisterNetEvent(resourceName .. ':server:RemoveItem', function(_)
    -- Deprecated; use server callback for access which removes items internally
end)
