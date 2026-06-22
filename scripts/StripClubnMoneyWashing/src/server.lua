local resourceName = GetCurrentResourceName()

lib.locale()

local debugEnabled = Config.Debug
local framework = { type = 'standalone', object = nil }
local inventory = { type = nil }
local activeDancers = {}
local staticDancers = {}
local poleLookup = {}
local danceZoneLookup = {}
local societyConfig = Config.Society or {}
local tipOptions = Config.TipOptions or {}
local json = json or require('json')
local DEBUG_TOOL_PERMISSIONS = {
    esx = { 'admin', 'superadmin' },
    qb = { 'admin', 'god' },
    qbox = { 'admin', 'god' }
}
local MONEY_CONFIG = {
    dirty = {
        type = 'item',
        name = 'black_money',
        metadata = nil
    },
    clean = {
        type = 'item',
        name = 'money',
        metadata = nil
    }
}
local ESX_DIRTY_FALLBACKS = { 'dirty_money', 'black_money' }

local levelsConfig = Config.Levels or {}
local levelCount = #levelsConfig
local experienceFile = 'data/experience.json'
local experienceStore = {}

local function debugPrint(...)
    if not debugEnabled then return end
    local args = { ... }
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    print(('[%s][DEBUG] %s'):format(resourceName, table.concat(args, ' ')))
end

local function formatCurrency(amount)
    local integer = math.floor(amount or 0)
    local sign = integer < 0 and '-' or ''
    integer = math.abs(integer)
    local str = tostring(integer)
    while true do
        local replaced, count = str:gsub('^(%d+)(%d%d%d)', '%1,%2')
        str = replaced
        if count == 0 then break end
    end
    return sign .. str
end

local function getPlayersWithinRadius(originCoords, radius)
    if not originCoords then return {} end

    radius = tonumber(radius) or 25.0
    if radius < 0.0 then
        radius = 0.0
    end

    local nearby = {}
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target then
            local ped = GetPlayerPed(target)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                if coords and #(coords - originCoords) <= radius then
                    nearby[#nearby + 1] = target
                end
            end
        end
    end

    return nearby
end

local function syncTipFxNearby(sourceId, landingCoords)
    local ped = GetPlayerPed(sourceId)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return
    end

    local originCoords = GetEntityCoords(ped)
    local recipients = getPlayersWithinRadius(originCoords, Config.TipSyncRadius or 25.0)
    for i = 1, #recipients do
        TriggerClientEvent(resourceName .. ':client:PlayTipFxOnPlayer', recipients[i], sourceId, landingCoords)
    end
end

local function detectFramework()
    local mode = (Config.Framework and Config.Framework.mode) or 'auto'

    local function tryESX()
        if GetResourceState('es_extended') ~= 'started' then return false end
        local obj
        local ok, result = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok then obj = result end
        if not obj then
            TriggerEvent('esx:getSharedObject', function(shared)
                obj = shared
            end)
        end
        if obj then
            framework.type = 'esx'
            framework.object = obj
            debugPrint('Detected ESX framework')
            return true
        end
        return false
    end

    local function tryQB(resource, label)
        resource = resource or 'qb-core'
        if GetResourceState(resource) ~= 'started' then return false end
        local obj
        local ok, result = pcall(function()
            return exports[resource]:GetCoreObject()
        end)
        if ok then obj = result end
        if not obj then
            TriggerEvent('QBCore:GetObject', function(shared)
                obj = shared
            end)
        end
        if obj then
            framework.type = label or 'qb'
            framework.object = obj
            debugPrint(('Detected %s framework'):format(label or 'QB'))
            return true
        end
        return false
    end

    if mode == 'esx' then
        tryESX()
        return
    end
    if mode == 'qb' then
        tryQB('qb-core', 'qb')
        return
    end
    if mode == 'qbox' then
        tryQB('qbx_core', 'qbox')
        return
    end

    if mode == 'auto' then
        if tryESX() then return end
        if tryQB('qb-core', 'qb') then return end
        if tryQB('qbx_core', 'qbox') then return end
    end

    framework.type = 'standalone'
    framework.object = nil
    debugPrint('Falling back to standalone mode')
end

local function detectInventory()
    local mode = (Config.Framework and Config.Framework.inventory) or 'auto'
    if mode == 'ox' or (mode == 'auto' and GetResourceState('ox_inventory') == 'started') then
        inventory.type = 'ox'
        debugPrint('Using ox_inventory for item handling')
    else
        inventory.type = nil
    end
end

local function buildPoleLookup()
    poleLookup = {}
    staticDancers = {}
    if type(Config.Poles) ~= 'table' then return end

    for index, pole in ipairs(Config.Poles) do
        if type(pole) ~= 'table' or not pole.coords then goto continue end
        if type(pole.id) ~= 'string' or pole.id == '' then
            pole.id = ('pole_%d'):format(index)
        end
        if type(pole.coords) == 'vector4' then
            pole.heading = pole.heading or pole.coords.w
            pole.coords = vector3(pole.coords.x, pole.coords.y, pole.coords.z)
        end
        if type(pole.zoneId) ~= 'string' or pole.zoneId == '' then
            pole.zoneId = pole.id
        end
        if type(pole.ped) == 'table' and pole.ped.heading == nil and pole.heading ~= nil then
            pole.ped.heading = pole.heading
        end
        poleLookup[pole.id] = pole
        if pole.ped and pole.ped.enabled and pole.ped.wash and pole.ped.wash.enabled then
            staticDancers[pole.id] = {
                coords = pole.coords,
                poleId = pole.id,
                zoneId = pole.zoneId,
                society = pole.society or societyConfig.fallback
            }
        end
        ::continue::
    end
end

local function buildDanceZoneLookup()
    danceZoneLookup = {}

    if type(Config.DanceZones) ~= 'table' then
        return
    end

    for index, zone in ipairs(Config.DanceZones) do
        if type(zone) ~= 'table' or not zone.coords then goto continue end
        if type(zone.id) ~= 'string' or zone.id == '' then
            zone.id = ('dance_zone_%d'):format(index)
        end
        if type(zone.coords) == 'vector4' then
            zone.heading = zone.heading or zone.coords.w
            zone.coords = vector3(zone.coords.x, zone.coords.y, zone.coords.z)
        end
        danceZoneLookup[zone.id] = zone
        ::continue::
    end
end

local function saveExperience()
    local ok, encoded = pcall(json.encode, experienceStore)
    if not ok then
        debugPrint('Failed to encode experience store', encoded)
        return
    end
    SaveResourceFile(resourceName, experienceFile, encoded, -1)
end

local function loadExperience()
    local raw = LoadResourceFile(resourceName, experienceFile)
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            experienceStore = decoded
        else
            debugPrint('Failed to decode experience store, resetting')
            experienceStore = {}
        end
    else
        experienceStore = {}
    end
end

local function getLevelInfo(xp)
    xp = math.max(0, math.floor(xp or 0))
    local currentIndex = 1
    for i = 1, levelCount do
        local levelCfg = levelsConfig[i]
        if levelCfg and xp >= math.floor(levelCfg.xp or 0) then
            currentIndex = i
        else
            break
        end
    end
    local currentLevel = levelsConfig[currentIndex] or { xp = 0, name = ('Level %s'):format(currentIndex), taxRate = Config.SocietyCut or 0 }
    local nextLevel = levelsConfig[currentIndex + 1]
    return currentIndex, currentLevel, nextLevel
end

local function getPlayer(src)
    if framework.type == 'esx' then
        return framework.object and framework.object.GetPlayerFromId(src) or nil
    end
    if framework.object then
        if framework.object.Functions and framework.object.Functions.GetPlayer then
            return framework.object.Functions.GetPlayer(src)
        end
        if framework.object.Player then
            return framework.object.Player(src)
        end
    end
    return nil
end

local function refreshPlayer(src)
    local player = getPlayer(src)
    if not player then
        activeDancers[src] = nil
    end
    return player
end

local function getPlayerJob(player)
    if not player then return nil end
    if framework.type == 'esx' then
        return player.job and player.job.name or nil
    end
    local data = player.PlayerData or player
    if data.job then
        return data.job.name or data.job.id or data.job.label
    end
    return nil
end

local function normalizeJobName(jobName)
    if type(jobName) ~= 'string' then return nil end
    jobName = jobName:lower():gsub('^%s+', ''):gsub('%s+$', '')
    if jobName == '' then return nil end
    return jobName
end

local function hasAdminToolPermission(src, player)
    if framework.type == 'esx' then
        local allowedGroups = DEBUG_TOOL_PERMISSIONS.esx
        local group = player and player.getGroup and player.getGroup() or player and player.group or nil
        if type(group) ~= 'string' then
            return false
        end

        group = group:lower()
        for i = 1, #allowedGroups do
            if group == tostring(allowedGroups[i]):lower() then
                return true
            end
        end

        return false
    end

    if framework.type == 'qb' then
        local allowedPerms = DEBUG_TOOL_PERMISSIONS.qb
        local qb = framework.object
        if not qb or not qb.Functions or not qb.Functions.HasPermission then
            return false
        end

        for i = 1, #allowedPerms do
            if qb.Functions.HasPermission(src, allowedPerms[i]) then
                return true
            end
        end

        return false
    end

    if framework.type == 'qbox' then
        local allowedPerms = DEBUG_TOOL_PERMISSIONS.qbox

        if GetResourceState('qbx_core') == 'started' then
            for i = 1, #allowedPerms do
                local group = allowedPerms[i]
                local ok = false

                if exports.qbx_core and exports.qbx_core.HasPermission then
                    ok = exports.qbx_core:HasPermission(src, group)
                end

                if not ok and exports.qbx_core and exports.qbx_core.HasGroup then
                    ok = exports.qbx_core:HasGroup(src, group)
                end

                if ok then
                    return true
                end
            end
        end

        local qb = framework.object
        if qb and qb.Functions and qb.Functions.HasPermission then
            for i = 1, #allowedPerms do
                if qb.Functions.HasPermission(src, allowedPerms[i]) then
                    return true
                end
            end
        end

        return false
    end

    return false
end

local function getPoleRequiredJob(poleId)
    if not poleId then return nil end
    local pole = poleLookup[poleId]
    if not pole then return nil end

    local society = type(pole.society) == 'table' and pole.society or {}
    local fallback = type(societyConfig.fallback) == 'table' and societyConfig.fallback or {}
    return normalizeJobName(society.job or fallback.job)
end

local function getPoleZoneId(poleId)
    if not poleId then return nil end
    local pole = poleLookup[poleId]
    if not pole then return nil end
    return pole.zoneId or pole.id
end

local function getZoneRequiredJob(zoneId)
    if not zoneId then return nil end

    local zone = danceZoneLookup[zoneId]
    if zone then
        local society = type(zone.society) == 'table' and zone.society or {}
        local fallback = type(societyConfig.fallback) == 'table' and societyConfig.fallback or {}
        return normalizeJobName(society.job or fallback.job)
    end

    for _, pole in pairs(poleLookup) do
        if (pole.zoneId or pole.id) == zoneId then
            local society = type(pole.society) == 'table' and pole.society or {}
            local fallback = type(societyConfig.fallback) == 'table' and societyConfig.fallback or {}
            return normalizeJobName(society.job or fallback.job)
        end
    end

    return nil
end

local function getStaticDancerForZone(zoneId, preferredPoleId)
    if not zoneId then return nil end

    if preferredPoleId then
        local preferred = staticDancers[preferredPoleId]
        if preferred and preferred.zoneId == zoneId then
            return preferred
        end
    end

    for _, entry in pairs(staticDancers) do
        if entry.zoneId == zoneId then
            return entry
        end
    end

    return nil
end

local function getActiveZoneDancer(zoneId, excludeSource)
    if not zoneId then return nil, nil end

    for dancerSrc, entry in pairs(activeDancers) do
        if dancerSrc ~= excludeSource and entry and entry.zoneId == zoneId then
            local dancerPed = GetPlayerPed(dancerSrc)
            if DoesEntityExist(dancerPed) then
                return dancerSrc, entry
            end

            activeDancers[dancerSrc] = nil
        end
    end

    return nil, nil
end

local function canPlayerDancePole(player, poleId, src)
    local requiredJob = getPoleRequiredJob(poleId)
    local playerJob = normalizeJobName(getPlayerJob(player))
    local zoneId = getPoleZoneId(poleId)

    if requiredJob and playerJob ~= requiredJob then
        return false, requiredJob, playerJob, zoneId, nil
    end

    local staticEntry = getStaticDancerForZone(zoneId, poleId)
    if staticEntry then
        return false, requiredJob, playerJob, zoneId, 'npc'
    end

    local occupantSrc = getActiveZoneDancer(zoneId, src)
    if occupantSrc then
        return false, requiredJob, playerJob, zoneId, 'player'
    end

    return true, requiredJob, playerJob, zoneId, nil
end

local function canPlayerDanceZone(player, zoneId, src)
    local requiredJob = getZoneRequiredJob(zoneId)
    local playerJob = normalizeJobName(getPlayerJob(player))

    if requiredJob and playerJob ~= requiredJob then
        return false, requiredJob, playerJob, zoneId, nil
    end

    local staticEntry = getStaticDancerForZone(zoneId)
    if staticEntry then
        return false, requiredJob, playerJob, zoneId, 'npc'
    end

    local occupantSrc = getActiveZoneDancer(zoneId, src)
    if occupantSrc then
        return false, requiredJob, playerJob, zoneId, 'player'
    end

    return true, requiredJob, playerJob, zoneId, nil
end

local function getIdentifierFromPlayer(player, src)
    if not player then return nil end
    if framework.type == 'esx' then
        return player.identifier or player.getIdentifier and player:getIdentifier()
    end
    if framework.type == 'qb' or framework.type == 'qbox' then
        if player.PlayerData and player.PlayerData.citizenid then
            return player.PlayerData.citizenid
        end
    end
    if src then
        local identifiers = GetPlayerIdentifiers(src)
        for _, identifier in ipairs(identifiers) do
            if identifier:find('license', 1, true) then
                return identifier
            end
        end
        return identifiers[1] or ('source:%s'):format(src)
    end
    return nil
end

local function getExperienceEntry(identifier)
    if not identifier then return nil end
    local entry = experienceStore[identifier]
    if not entry then
        entry = { xp = 0 }
        experienceStore[identifier] = entry
    end
    return entry
end

local function getPlayerTaxRate(player, src)
    local identifier = getIdentifierFromPlayer(player, src)
    if not identifier then
        return Config.SocietyCut or 0
    end
    local entry = getExperienceEntry(identifier)
    local _, currentLevel = getLevelInfo(entry.xp)
    return tonumber(currentLevel.taxRate) or Config.SocietyCut or 0
end

local function notifyPlayer(src, message, type)
    TriggerClientEvent(resourceName .. ':client:Notify', src, message, type or 'inform')
end

local function syncPlayerTaxRate(src, taxRate)
    TriggerClientEvent(resourceName .. ':client:UpdateTaxRate', src, tonumber(taxRate) or Config.SocietyCut or 0)
end

local function addExperience(src, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    local player = refreshPlayer(src)
    if not player then return end
    local identifier = getIdentifierFromPlayer(player, src)
    if not identifier then return end

    local entry = getExperienceEntry(identifier)
    local previousLevelIndex = select(1, getLevelInfo(entry.xp))
    entry.xp = math.max(0, entry.xp + amount)
    local levelIndex, currentLevel, nextLevel = getLevelInfo(entry.xp)
    saveExperience()
    syncPlayerTaxRate(src, currentLevel.taxRate or Config.SocietyCut or 0)

    notifyPlayer(src, locale('xp_gain', amount, entry.xp), 'success')

    if levelIndex > previousLevelIndex then
        notifyPlayer(src, locale('xp_level_up', levelIndex, currentLevel.name or ('Level ' .. levelIndex), currentLevel.taxRate or Config.SocietyCut or 0), 'success')
    end

    if nextLevel then
        local xpNeeded = math.max(0, math.floor(nextLevel.xp or 0) - entry.xp)
        if xpNeeded > 0 then
            notifyPlayer(src, locale('xp_next', xpNeeded, levelIndex + 1, nextLevel.name or ('Level ' .. (levelIndex + 1))), 'inform')
        end
    elseif levelIndex > previousLevelIndex then
        notifyPlayer(src, locale('leaderboard_max'), 'inform')
    end

    return entry.xp, levelIndex, currentLevel
end

local function getLeaderboardText(entry)
    entry = entry or { xp = 0 }
    local levelIndex, currentLevel, nextLevel = getLevelInfo(entry.xp)
    local lines = {
        locale('leaderboard_current', levelIndex, currentLevel.name or ('Level ' .. levelIndex), entry.xp)
    }
    if nextLevel then
        local xpNeeded = math.max(0, math.floor(nextLevel.xp or 0) - entry.xp)
        lines[#lines + 1] = locale('leaderboard_next', xpNeeded, levelIndex + 1, nextLevel.name or ('Level ' .. (levelIndex + 1)))
    else
        lines[#lines + 1] = locale('leaderboard_max')
    end
    lines[#lines + 1] = locale('leaderboard_tax', string.format('%.2f', tonumber(currentLevel.taxRate) or Config.SocietyCut or 0))
    return table.concat(lines, '\n')
end

local function getActivePoleStates()
    local states = {}

    for dancerSrc, entry in pairs(activeDancers) do
        local poleId = entry and entry.poleId or nil
        if poleId then
            local dancerPed = GetPlayerPed(dancerSrc)
            if DoesEntityExist(dancerPed) then
                states[poleId] = (states[poleId] or 0) + 1
            else
                activeDancers[dancerSrc] = nil
            end
        end
    end

    return states
end

local function getActiveZoneStates()
    local states = {}

    for dancerSrc, entry in pairs(activeDancers) do
        local zoneId = entry and entry.zoneId or nil
        if zoneId then
            local dancerPed = GetPlayerPed(dancerSrc)
            if DoesEntityExist(dancerPed) then
                states[zoneId] = (states[zoneId] or 0) + 1
            else
                activeDancers[dancerSrc] = nil
            end
        end
    end

    return states
end

local function syncActivePoleStates(target)
    TriggerClientEvent(resourceName .. ':client:SyncActivePoles', target or -1, getActivePoleStates())
    TriggerClientEvent(resourceName .. ':client:SyncActiveZones', target or -1, getActiveZoneStates())
end

detectFramework()
detectInventory()
buildPoleLookup()
buildDanceZoneLookup()
loadExperience()

RegisterCommand('moneywashleaderboard', function(source)
    if source == 0 then
        print(('[%s] %s'):format(resourceName, locale('leaderboard_title')))
        return
    end

    local player = refreshPlayer(source)
    if not player then
        notifyPlayer(source, locale('nobody_dancing'), 'error')
        return
    end

    local identifier = getIdentifierFromPlayer(player, source)
    local entry = identifier and getExperienceEntry(identifier) or { xp = 0 }
    TriggerClientEvent('ox_lib:notify', source, {
        title = locale('leaderboard_title'),
        description = getLeaderboardText(entry),
        type = 'inform',
        position = 'top-center'
    })
end, false)

lib.callback.register(resourceName .. ':getTaxData', function(source)
    local player = refreshPlayer(source)
    local rate = getPlayerTaxRate(player, source)
    local enabled = societyConfig.enabled ~= false
    return {
        taxRate = rate,
        societyEnabled = enabled
    }
end)

lib.callback.register(resourceName .. ':canDanceOnPole', function(source, poleId)
    local player = refreshPlayer(source)
    if not player then
        return {
            allowed = false,
            requiredJob = getPoleRequiredJob(poleId)
        }
    end

    local allowed, requiredJob, playerJob, zoneId, occupiedBy = canPlayerDancePole(player, poleId, source)
    return {
        allowed = allowed,
        requiredJob = requiredJob,
        playerJob = playerJob,
        zoneId = zoneId,
        occupiedBy = occupiedBy
    }
end)

lib.callback.register(resourceName .. ':canDanceInZone', function(source, zoneId)
    local player = refreshPlayer(source)
    if not player then
        return {
            allowed = false,
            requiredJob = getZoneRequiredJob(zoneId),
            zoneId = zoneId
        }
    end

    local allowed, requiredJob, playerJob, resolvedZoneId, occupiedBy = canPlayerDanceZone(player, zoneId, source)
    return {
        allowed = allowed,
        requiredJob = requiredJob,
        playerJob = playerJob,
        zoneId = resolvedZoneId,
        occupiedBy = occupiedBy
    }
end)

lib.callback.register(resourceName .. ':canUseAdminTool', function(source)
    local player = refreshPlayer(source)
    return hasAdminToolPermission(source, player)
end)

lib.callback.register(resourceName .. ':getActivePoleStates', function()
    return getActivePoleStates()
end)

lib.callback.register(resourceName .. ':getActiveZoneStates', function()
    return getActiveZoneStates()
end)

local function alignTipAmount(amount)
    local min = math.floor(tonumber(tipOptions.min) or 1)
    if min < 0 then min = 0 end
    local max = math.floor(tonumber(tipOptions.max) or min)
    if max < min then max = min end
    local step = math.floor(tonumber(tipOptions.step) or 1)
    if step < 1 then step = 1 end
    local default = math.floor(tonumber(tipOptions.default) or min)

    local value = math.floor(tonumber(amount) or default)
    if value < min then value = min end
    if value > max then value = max end
    if step > 1 and max > min then
        local offset = value - min
        local remainder = offset % step
        value = value - remainder
        if value < min then value = min end
    end

    if value > max then value = max end

    return value, min, max, default
end

local function getBalance(player, account)
    if not player or not account then return 0 end
    if framework.type == 'esx' then
        if account == 'money' or account == 'cash' then
            return player.getMoney and player.getMoney() or 0
        end
        if player.getAccount then
            local acc = player.getAccount(account)
            return acc and acc.money or 0
        end
        return 0
    end

    if (framework.type == 'qb' or framework.type == 'qbox') and player.Functions then
        if player.Functions.GetMoney then
            local ok, balance = pcall(player.Functions.GetMoney, player, account)
            if ok then return balance or 0 end
        end
        if player.PlayerData and player.PlayerData.money then
            return player.PlayerData.money[account] or 0
        end
    end

    return 0
end

local function removeMoney(player, account, amount)
    if not player or not account or amount <= 0 then return false end
    local reason = Config.Framework and Config.Framework.transactionReason or 'club_dancer'

    if framework.type == 'esx' then
        if account == 'money' or account == 'cash' then
            local balance = player.getMoney and player.getMoney() or 0
            if balance < amount then return false end
            if player.removeMoney then
                player.removeMoney(amount)
                return true
            end
            return false
        end
        local balance = getBalance(player, account)
        if balance < amount then return false end
        if player.removeAccountMoney then
            player.removeAccountMoney(account, amount)
            return true
        end
        return false
    end

    if (framework.type == 'qb' or framework.type == 'qbox') and player.Functions and player.Functions.RemoveMoney then
        local balance = getBalance(player, account)
        if balance < amount then return false end
        player.Functions.RemoveMoney(account, amount, reason)
        return true
    end

    return false
end

local function addMoney(player, account, amount)
    if not player or not account or amount <= 0 then return false end
    local reason = Config.Framework and Config.Framework.transactionReason or 'club_dancer'

    if framework.type == 'esx' then
        if account == 'money' or account == 'cash' then
            if player.addMoney then
                player.addMoney(amount)
                return true
            end
            return false
        end
        if player.addAccountMoney then
            player.addAccountMoney(account, amount)
            return true
        end
        return false
    end

    if (framework.type == 'qb' or framework.type == 'qbox') and player.Functions and player.Functions.AddMoney then
        player.Functions.AddMoney(account, amount, reason)
        return true
    end

    return false
end

local function inventoryCount(player, src, accountConfig)
    if inventory.type == 'ox' then
        local ok, result = pcall(function()
            return exports.ox_inventory:Search(src, 'count', accountConfig.name, accountConfig.metadata)
        end)
        if not ok then
            debugPrint('Failed to count item', accountConfig.name, result)
            return 0
        end
        return tonumber(result) or 0
    end

    if framework.type == 'esx' and player and player.getInventoryItem then
        local ok, item = pcall(player.getInventoryItem, player, accountConfig.name)
        if ok and item then
            local count = item.count or item.amount or item.value or 0
            return tonumber(count) or 0
        end
    end

    if (framework.type == 'qb' or framework.type == 'qbox') and player and player.Functions and player.Functions.GetItemByName then
        local ok, item = pcall(player.Functions.GetItemByName, player.Functions, accountConfig.name)
        if ok and item then
            local count = item.amount or item.count or (item.info and item.info.amount) or 0
            return tonumber(count) or 0
        end
    end

    return 0
end

local function inventoryRemove(player, src, accountConfig, amount)
    if inventory.type == 'ox' then
        local ok, removed = pcall(function()
            return exports.ox_inventory:RemoveItem(src, accountConfig.name, amount, accountConfig.metadata)
        end)
        if ok and removed then
            return true
        end
        debugPrint('Failed to remove item', accountConfig.name, removed)
        return false
    end

    if framework.type == 'esx' and player and player.removeInventoryItem then
        local ok = pcall(player.removeInventoryItem, player, accountConfig.name, amount)
        if ok then
            return true
        end
        debugPrint('Failed to remove ESX item', accountConfig.name)
        return false
    end

    if (framework.type == 'qb' or framework.type == 'qbox') and player and player.Functions and player.Functions.RemoveItem then
        local metadata = accountConfig.metadata
        local ok, removed = pcall(player.Functions.RemoveItem, player.Functions, accountConfig.name, amount, nil, metadata)
        if ok and removed ~= false then
            return true
        end
        debugPrint('Failed to remove QB item', accountConfig.name, removed)
        return false
    end

    debugPrint('No inventory handler for item removal', accountConfig.name)
    return false
end

local function inventoryAdd(player, src, accountConfig, amount)
    if inventory.type == 'ox' then
        local ok, added = pcall(function()
            return exports.ox_inventory:AddItem(src, accountConfig.name, amount, accountConfig.metadata)
        end)
        if ok and added then
            return true
        end
        debugPrint('Failed to add item', accountConfig.name, added)
        return false
    end

    if framework.type == 'esx' and player and player.addInventoryItem then
        local ok = pcall(player.addInventoryItem, player, accountConfig.name, amount)
        if ok then
            return true
        end
        debugPrint('Failed to add ESX item', accountConfig.name)
        return false
    end

    if (framework.type == 'qb' or framework.type == 'qbox') and player and player.Functions and player.Functions.AddItem then
        local metadata = accountConfig.metadata
        local ok, added = pcall(player.Functions.AddItem, player.Functions, accountConfig.name, amount, nil, metadata)
        if ok and added ~= false then
            return true
        end
        debugPrint('Failed to add QB item', accountConfig.name, added)
        return false
    end

    debugPrint('No inventory handler for item addition', accountConfig.name)
    return false
end

local function hasFunds(player, src, accountConfig, amount)
    if not accountConfig or amount <= 0 then return false end
    if accountConfig.type == 'item' then
        return inventoryCount(player, src, accountConfig) >= amount
    end
    return getBalance(player, accountConfig.name) >= amount
end

local function getMoneyConfigCandidates(accountConfig)
    if not accountConfig then return {} end

    local candidates = {}
    local seen = {}

    local function addCandidate(configType, configName, metadata)
        if not configType or not configName then return end
        local key = ('%s:%s'):format(configType, configName)
        if seen[key] then return end
        seen[key] = true
        candidates[#candidates + 1] = {
            type = configType,
            name = configName,
            metadata = metadata
        }
    end

    addCandidate(accountConfig.type, accountConfig.name, accountConfig.metadata)

    if framework.type == 'esx' and accountConfig == MONEY_CONFIG.dirty then
        for i = 1, #ESX_DIRTY_FALLBACKS do
            local alias = ESX_DIRTY_FALLBACKS[i]
            addCandidate(accountConfig.type, alias, accountConfig.metadata)
            addCandidate('account', alias, nil)
        end
    end

    return candidates
end

local function getAvailableFunds(player, src, accountConfig)
    local candidates = getMoneyConfigCandidates(accountConfig)
    for i = 1, #candidates do
        local candidate = candidates[i]
        local amount = 0

        if candidate.type == 'item' then
            amount = inventoryCount(player, src, candidate)
        else
            amount = getBalance(player, candidate.name)
        end

        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if amount > 0 then
            return amount, candidate
        end
    end

    return 0, candidates[1] or accountConfig
end

lib.callback.register(resourceName .. ':getTipTaxData', function(source)
    local player = refreshPlayer(source)
    local rate = getPlayerTaxRate(player, source)
    local enabled = societyConfig.enabled ~= false
    local dirtyAccount = MONEY_CONFIG.dirty or { type = 'account', name = 'black_money' }
    local cleanAccount = MONEY_CONFIG.clean or { type = 'account', name = 'money' }
    local dirtyBalance = 0
    local cleanBalance = 0
    local minTip = math.max(0, math.floor(tonumber(tipOptions.min) or 1))

    if player then
        dirtyBalance = getAvailableFunds(player, source, dirtyAccount)
        cleanBalance = getAvailableFunds(player, source, cleanAccount)
    end

    return {
        taxRate = rate,
        societyEnabled = enabled,
        hasDirtyMoney = dirtyBalance >= minTip,
        dirtyBalance = dirtyBalance,
        cleanBalance = cleanBalance,
        availableBalance = dirtyBalance >= minTip and dirtyBalance or cleanBalance
    }
end)

local function removeFunds(player, src, accountConfig, amount)
    if not accountConfig or amount <= 0 then return false end
    if accountConfig.type == 'item' then
        return inventoryRemove(player, src, accountConfig, amount)
    end
    return removeMoney(player, accountConfig.name, amount)
end

local function addFunds(player, src, accountConfig, amount)
    if not accountConfig or amount <= 0 then return true end
    if accountConfig.type == 'item' then
        return inventoryAdd(player, src, accountConfig, amount)
    end
    return addMoney(player, accountConfig.name, amount)
end

local function addSocietyMoney(societyData, amount)
    if amount <= 0 or not societyConfig.enabled then return false end
    societyData = societyData or societyConfig.fallback or {}

    local jobName = societyData.job or societyData.name
    local accountName = societyData.account
    local success = false

    if framework.type == 'esx' then
        accountName = accountName or ((societyConfig.accountPrefix or 'society_') .. (jobName or 'unemployed'))
        TriggerEvent('esx_addonaccount:getSharedAccount', accountName, function(account)
            if account then
                account.addMoney(amount)
                success = true
            end
        end)
        return success
    end

    if framework.type == 'qb' or framework.type == 'qbox' then
        jobName = jobName or societyConfig.fallback and societyConfig.fallback.job
        if not jobName then return false end

        if GetResourceState('qb-management') == 'started' then
            local ok = pcall(function()
                exports['qb-management']:AddMoney(jobName, amount)
            end)
            if ok then return true end
        end

        if GetResourceState('qb-bossmenu') == 'started' then
            TriggerEvent('qb-bossmenu:server:addAccountMoney', jobName, amount)
            return true
        end

        if GetResourceState('qbx_management') == 'started' then
            local ok = pcall(function()
                exports['qbx_management']:AddMoney(jobName, amount)
            end)
            if ok then return true end
        end
    end

    return false
end

local function computeWashDistribution(amount, taxPercent)
    local total = math.floor(amount or 0)
    if total < 0 then total = 0 end
    local distribution = {
        total = total,
        clean = total,
        society = 0,
        dancer = 0
    }

    local effectiveTax = tonumber(taxPercent) or Config.SocietyCut or 0

    if total > 0 and effectiveTax > 0 then
        local societyCut = math.floor(total * effectiveTax / 100)
        local dancerCut = 0
        if societyConfig.enabled then
            dancerCut = math.floor(societyCut * (Config.DancerCut or 0) / 100)
        end
        distribution.society = societyCut - dancerCut
        distribution.dancer = dancerCut
        distribution.clean = total - societyCut
    end

    return distribution
end
local function computeTipDistribution(amount)
    local total = math.floor(amount or 0)
    if total < 0 then total = 0 end
    if not societyConfig.enabled then
        return total, 0
    end
    local dancerTip = math.floor(total * (Config.DancerCut or 0) / 100)
    if dancerTip > total then
        dancerTip = total
    end
    return dancerTip, total - dancerTip
end

local function findNearestDancer(src, context)
    local ped = GetPlayerPed(src)
    if not DoesEntityExist(ped) then return nil end
    local playerCoords = GetEntityCoords(ped)
    local targetPoleId = context and context.poleId or nil
    local targetZoneId = context and context.zoneId or nil

    if not targetZoneId then
        targetZoneId = getPoleZoneId(targetPoleId)
    end

    if context and context.targetType == 'ped' and targetPoleId then
        local entry = staticDancers[targetPoleId]
        if entry then
            return {
                type = 'ped',
                poleId = targetPoleId,
                zoneId = entry.zoneId,
                coords = entry.coords,
                society = entry.society or societyConfig.fallback
            }
        end
    end

    local closestDistance = math.huge
    local closestEntry = nil

    for dancerSrc, entry in pairs(activeDancers) do
        local dancerPed = GetPlayerPed(dancerSrc)
        if DoesEntityExist(dancerPed) then
            local coords = entry.coords or GetEntityCoords(dancerPed)
            local distance = #(playerCoords - coords)
            if distance < closestDistance then
                if not targetPoleId or targetPoleId == entry.poleId or (targetZoneId and targetZoneId == entry.zoneId) then
                    closestDistance = distance
                    closestEntry = {
                        type = 'player',
                        source = dancerSrc,
                        coords = coords,
                        poleId = entry.poleId,
                        zoneId = entry.zoneId,
                        job = entry.job,
                        animation = entry.animation
                    }
                end
            end
        else
            activeDancers[dancerSrc] = nil
        end
    end

    for poleId, entry in pairs(staticDancers) do
        if not targetPoleId or targetPoleId == poleId or (targetZoneId and targetZoneId == entry.zoneId) then
            local coords = entry.coords
            local distance = #(playerCoords - coords)
            if distance < closestDistance then
                closestDistance = distance
                closestEntry = {
                    type = 'ped',
                    poleId = poleId,
                    zoneId = entry.zoneId,
                    coords = coords,
                    society = entry.society or societyConfig.fallback
                }
            end
        end
    end

    if closestDistance > 5.0 then
        return nil
    end

    return closestEntry
end

RegisterNetEvent(resourceName .. ':server:UpdatePoleDancers', function(isDancing, data)
    local src = source
    if type(isDancing) ~= 'boolean' then return end

    if isDancing then
        local player = refreshPlayer(src)
        if not player then return end
        local coords = (data and data.coords) or GetEntityCoords(GetPlayerPed(src))
        local poleId = data and data.poleId or nil
        local zoneId = data and data.zoneId or nil
        local allowed, requiredJob, _, resolvedZoneId, occupiedBy

        if poleId then
            allowed, requiredJob, _, resolvedZoneId, occupiedBy = canPlayerDancePole(player, poleId, src)
        else
            allowed, requiredJob, _, resolvedZoneId, occupiedBy = canPlayerDanceZone(player, zoneId, src)
        end

        if not allowed then
            activeDancers[src] = nil
            if occupiedBy then
                notifyPlayer(src, locale('zone_occupied'), 'error')
            else
                notifyPlayer(src, locale('dance_job_required', requiredJob or 'unknown'), 'error')
            end
            return
        end
        activeDancers[src] = {
            coords = coords,
            poleId = poleId,
            zoneId = resolvedZoneId,
            job = getPlayerJob(player),
            animation = data and data.animation or nil
        }
        debugPrint('Registered dancer', src, poleId or 'no pole', resolvedZoneId or 'no zone')
    else
        activeDancers[src] = nil
        debugPrint('Removed dancer', src)
    end

    syncActivePoleStates()
end)

AddEventHandler('playerDropped', function()
    activeDancers[source] = nil
    syncActivePoleStates()
end)

RegisterNetEvent(resourceName .. ':server:ThrowMoney', function(context)
    local src = source
    local payload = type(context) == 'table' and context or {}
    local player = refreshPlayer(src)

    if not player then
        notifyPlayer(src, locale('nobody_dancing'), 'error')
        return
    end

    local dancer = findNearestDancer(src, payload)
    if not dancer then
        notifyPlayer(src, locale('no_close_dancer'), 'error')
        return
    end

    local dirtyAccount = MONEY_CONFIG.dirty or { type = 'account', name = 'black_money' }
    local cleanAccount = MONEY_CONFIG.clean or { type = 'account', name = 'money' }
    local tipAmount, _, _ = alignTipAmount(payload.amount)

    if tipAmount <= 0 then
        notifyPlayer(src, locale('invalid_amount'), 'error')
        return
    end

    local taxPercent = getPlayerTaxRate(player, src)
    local xpConfig = Config.Experience or {}
    local tipXP = tonumber(xpConfig.tip) or 0
    local washXP = tonumber(xpConfig.wash) or 0
    local dirtyBalance, resolvedDirtyAccount = getAvailableFunds(player, src, dirtyAccount)
    local cleanBalance, resolvedCleanAccount = getAvailableFunds(player, src, cleanAccount)

    if dirtyBalance < tipAmount then
        if cleanBalance < tipAmount then
            notifyPlayer(src, locale('not_enough_money'), 'error')
            return
        end

        local dancerTip, societyTip = computeTipDistribution(tipAmount)

        TriggerClientEvent(resourceName .. ':client:PlayAnimation', src, Config.Tip.name, dancer.coords)
        syncTipFxNearby(src, dancer.coords)
        Wait((Config.WashingWaitTime or 0) * 1000)

        if not removeFunds(player, src, resolvedCleanAccount, tipAmount) then
            notifyPlayer(src, locale('not_enough_money'), 'error')
            return
        end

        if dancer.type == 'player' then
            local dancerPlayer = refreshPlayer(dancer.source)
            if dancerPlayer and dancerTip > 0 then
                addFunds(dancerPlayer, dancer.source, resolvedCleanAccount, dancerTip)
                notifyPlayer(dancer.source, locale('dancer_tipped', formatCurrency(dancerTip)), 'success')
            end
        elseif dancer.type == 'ped' and societyConfig.pedShare == 'clean' and dancerTip > 0 then
            addFunds(player, src, resolvedCleanAccount, dancerTip)
        end

        if societyTip > 0 then
            local societyData = dancer.type == 'player' and { job = dancer.job } or dancer.society
            if dancer.type == 'ped' and societyConfig.pedShare == 'clean' then
                addFunds(player, src, resolvedCleanAccount, societyTip)
            elseif dancer.type ~= 'ped' or societyConfig.pedShare ~= 'none' then
                addSocietyMoney(societyData, societyTip)
            end
        end

        TriggerClientEvent(resourceName .. ':client:StopTipAnimation', src)

        if tipXP > 0 then
            addExperience(src, tipXP)
        end
        return
    end

    local distribution = computeWashDistribution(tipAmount, taxPercent)
    if dancer.type == 'player' and tipAmount > 0 then
        local desiredDancerShare = math.floor(tipAmount * (Config.DancerCut or 0) / 100)
        if desiredDancerShare > tipAmount then
            desiredDancerShare = tipAmount
        end

        if desiredDancerShare > distribution.dancer and distribution.clean > 0 then
            local extra = math.min(desiredDancerShare - distribution.dancer, distribution.clean)
            distribution.clean = distribution.clean - extra
            distribution.dancer = distribution.dancer + extra
        end
    end
    TriggerClientEvent(resourceName .. ':client:PlayAnimation', src, Config.Tip.name, dancer.coords)
    syncTipFxNearby(src, dancer.coords)
    Wait((Config.WashingWaitTime or 0) * 1000)

    if not removeFunds(player, src, resolvedDirtyAccount, tipAmount) then
        notifyPlayer(src, locale('dirty_missing'), 'error')
        return
    end

    if distribution.clean > 0 then
        addFunds(player, src, resolvedCleanAccount, distribution.clean)
    end

    if distribution.dancer > 0 then
        if dancer.type == 'player' then
            local dancerPlayer = refreshPlayer(dancer.source)
            if dancerPlayer then
                addFunds(dancerPlayer, dancer.source, resolvedCleanAccount, distribution.dancer)
                notifyPlayer(dancer.source, locale('dancer_tipped', formatCurrency(distribution.dancer)), 'success')
            end
        elseif societyConfig.pedShare == 'clean' then
            addFunds(player, src, resolvedCleanAccount, distribution.dancer)
        end
    end

    if distribution.society > 0 then
        local societyData = dancer.type == 'player' and { job = dancer.job } or dancer.society
        if dancer.type == 'ped' and societyConfig.pedShare == 'clean' then
            addFunds(player, src, resolvedCleanAccount, distribution.society)
        elseif dancer.type ~= 'ped' or societyConfig.pedShare ~= 'none' then
            addSocietyMoney(societyData, distribution.society)
        end
    end

    TriggerClientEvent(resourceName .. ':client:StopTipAnimation', src)

    if washXP > 0 then
        addExperience(src, washXP)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= resourceName then return end
    saveExperience()
end)




