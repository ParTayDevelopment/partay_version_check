-- Detect framework early so downstream files can branch correctly
local function detectFramework()
    -- Prefer explicit config unless set to 'auto' or nil
    local cfg = Config and Config.Framework or nil
    if cfg and cfg ~= 'auto' then return cfg end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    -- Fallback to qb/qbx style
    return 'qbx'
end

Config.Framework = detectFramework()
if Config.Debug then
    print('[Partay_hustle] Detected framework: ' .. tostring(Config.Framework))
end

local function usingOxInventory()
    return GetResourceState('ox_inventory') == 'started'
end

-- simple per-player throttle for sale events
local _lastSellAt = {}
local _lastCbAt = {}
local _drugCache = {}
local _perItemLast = {}
local _hourly = {}
local _serverHourly = { count = 0, resetAt = 0 }
local _allowedNotifiedAt = {}
local _canSellItemAtLocation

-- Utility: check if a player's ped model is allowed to sell a given item
local function _isSellerModelAllowed(item, modelHash)
    if not item or not modelHash then return true end
    local entry = Config.DrugList and Config.DrugList[item]
    if not entry then return true end
    local allowed = entry.allowedSellerModels
    if not allowed then return true end

    local function toHash(v)
        if type(v) == 'number' then return v end
        if type(v) == 'string' then return GetHashKey(v) end
        return nil
    end

    -- single value shorthand
    if type(allowed) == 'string' or type(allowed) == 'number' then
        return toHash(allowed) == modelHash
    end
    -- list of models
    if type(allowed) == 'table' then
        for _, v in ipairs(allowed) do
            if toHash(v) == modelHash then return true end
        end
        return false
    end
    return true
end

-- Notify helper to inform players they are in the allowedSellerModels for an item (throttled)
local function _notifyAllowedIfApplicable(src, item, modelHash)
    local entry = Config.DrugList and Config.DrugList[item]
    if not entry then return end
    local allowed = entry.allowedSellerModels
    if not allowed then return end
    -- Only notify if model is explicitly allowed
    if not _isSellerModelAllowed(item, modelHash) then return end
    local now = GetGameTimer() or 0
    local last = _allowedNotifiedAt[src] or 0
    if now - last < 8000 then return end -- 8s cooldown to avoid spam
    _allowedNotifiedAt[src] = now
end


-- Find another sellable item for the player when the requested one is restricted
local function _findAlternateSellableItem(src, modelHash, skipItem)
    if not Config.DrugList then return nil end
    for name, _ in pairs(Config.DrugList) do
        if name ~= skipItem then
            local count = HasItem(src, name) or 0
            if count > 0 then
                if (not modelHash or _isSellerModelAllowed(name, modelHash)) and (not _canSellItemAtLocation or _canSellItemAtLocation(src, name)) then
                    return name, count
                end
            end
        end
    end
    return nil, 0
end
local function _perItemTooSoon(src, item)
    local cd = (Config.Server and tonumber(Config.Server.perItemCooldownMs)) or 0
    if cd <= 0 then return false end
    local now = GetGameTimer() or 0
    _perItemLast[src] = _perItemLast[src] or {}
    local last = _perItemLast[src][item] or 0
    if now - last < cd then return true end
    return false
end

local function _markPerItem(src, item)
    local now = GetGameTimer() or 0
    _perItemLast[src] = _perItemLast[src] or {}
    _perItemLast[src][item] = now
end

local function _checkAndBumpHourly(src)
    local cfg = (Config.Server and Config.Server.hourlyCap) or nil
    if not cfg then return true end
    local now = GetGameTimer() or 0
    -- per-player
    if (cfg.perPlayerSales or 0) > 0 then
        local rec = _hourly[src] or { count = 0, resetAt = 0 }
        if now > rec.resetAt then rec.count = 0; rec.resetAt = now + (60*60*1000) end
        if rec.count >= cfg.perPlayerSales then return false end
    end
    -- server-wide
    if (cfg.serverSales or 0) > 0 then
        local r = _serverHourly
        if now > r.resetAt then r.count = 0; r.resetAt = now + (60*60*1000) end
        if r.count >= cfg.serverSales then return false end
    end
    return true
end

local function _bumpHourly(src)
    local cfg = (Config.Server and Config.Server.hourlyCap) or nil
    if not cfg then return end
    local now = GetGameTimer() or 0
    if (cfg.perPlayerSales or 0) > 0 then
        local rec = _hourly[src] or { count = 0, resetAt = 0 }
        if now > rec.resetAt then rec.count = 0; rec.resetAt = now + (60*60*1000) end
        rec.count = rec.count + 1
        _hourly[src] = rec
    end
    if (cfg.serverSales or 0) > 0 then
        local r = _serverHourly
        if now > r.resetAt then r.count = 0; r.resetAt = now + (60*60*1000) end
        r.count = r.count + 1
        _serverHourly = r
    end
end
local function _tooSoon(src)
    local now = GetGameTimer() or 0
    local cd = (Config.Server and tonumber(Config.Server.sellCooldownMs)) or 2000
    local last = _lastSellAt[src] or 0
    if now - last < cd then return true end
    _lastSellAt[src] = now
    return false
end

-- Helpers for identifiers
local function getCitizenId(src)
    if Config.Framework == 'esx' then
        local x = GetPlayer(src)
        return x and x.identifier or nil
    else
        local p = GetPlayer(src)
        return p and p.PlayerData and p.PlayerData.citizenid or nil
    end
end

local function getLicenseId(src, preferV2)
    local ids = GetPlayerIdentifiers(src) or {}
    local target = preferV2 and 'license2:' or 'license:'
    for _, id in ipairs(ids) do
        if type(id) == 'string' and id:sub(1, #target) == target then return id end
    end
    -- fallback to the other
    target = not preferV2 and 'license2:' or 'license:'
    for _, id in ipairs(ids) do
        if type(id) == 'string' and id:sub(1, #target) == target then return id end
    end
    return nil
end

-- External XP integration (e.g., pickle_crafting)
local function AwardExternalXP(source, info)
    local cfg = Config and Config.ExternalXP or nil
    if not cfg or cfg.enabled == false then return end

    -- Event-based integration
    if cfg.event then
        TriggerEvent(cfg.event, source, info)
        return
    end

    -- Export-based integration
    local ex = cfg.export
    if not ex or not ex.resource or not ex.method then return end
    if GetResourceState(ex.resource) ~= 'started' then return end

    local a1, a2, a3
    if type(ex.args) == 'function' then
        local ok, v1, v2, v3 = pcall(ex.args, source, info)
        if not ok then return end
        -- If function returned a table, unpack it
        if type(v1) == 'table' and v2 == nil and v3 == nil then
            a1, a2, a3 = v1[1], v1[2], v1[3]
        else
            a1, a2, a3 = v1, v2, v3
        end
    elseif type(ex.args) == 'table' then
        a1, a2, a3 = ex.args[1], ex.args[2], ex.args[3]
    else
        -- Build sensible defaults for common AddPlayerXP(signature)
        local id
        local mode = (cfg.identifierMode or 'source')
        if mode == 'citizenid' then
            id = getCitizenId(source) or source
        elseif mode == 'license2' then
            id = getLicenseId(source, true) or source
        elseif mode == 'license' then
            id = getLicenseId(source, false) or source
        else
            id = source
        end
        a1 = id
        a2 = (type(cfg.skill) == 'string' and cfg.skill ~= '' and cfg.skill) or 'networking'
        a3 = tonumber(cfg.xp) or 0
    end

    -- Final sanitize
    if a1 == nil then a1 = source end
    if type(a2) ~= 'string' or a2 == '' then a2 = 'networking' end
    a3 = tonumber(a3)
    if not a3 then a3 = tonumber(cfg and cfg.xp) end
    if not a3 then a3 = 1000 end
    if a3 < 0 then a3 = 0 end

    local expObj = exports[ex.resource]
    local fn = expObj and expObj[ex.method] or nil
    if not fn then return end
    if Config.Debug then
        print(('[Partay_hustle] ExternalXP -> %s:%s(%s, %s, %s)')
            :format(tostring(ex.resource), tostring(ex.method), tostring(a1), tostring(a2), tostring(a3)))
    end
    pcall(function()
        -- Many exports are defined with colon syntax, expecting the table as first arg
        fn(expObj, a1, a2, a3)
    end)
end

-- True/false: player is within any configured zone range
local function IsPlayerInAnyZone(source)
    if not Config or not Config.Zones then return true end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    local pcoords = GetEntityCoords(ped)
    for _, zone in ipairs(Config.Zones) do
        local maxr = zone.maxRange or 50.0
        if #(pcoords - zone.coords) <= maxr then
            return true, zone
        end
    end
    return false, nil
end

local function _getSellingDefaultMode()
    local mode = Config.Selling and Config.Selling.defaultMode
    if mode == 'anywhere' or mode == 'zones' then return mode end

    return (Config.Server and Config.Server.enforceZone == false) and 'anywhere' or 'zones'
end

local function _getItemZones(item)
    local entry = item and Config.DrugList and Config.DrugList[item]
    if not entry then return nil end

    local zones = entry.zones or entry.sellZones or entry.allowedZones
    if type(zones) == 'table' and #zones > 0 then
        return zones
    end
end

local function _isCoordsInZones(coords, zones)
    if not coords or type(zones) ~= 'table' then return false end

    for _, zone in ipairs(zones) do
        if zone and zone.coords then
            local maxRange = tonumber(zone.maxRange or zone.radius or zone.range) or 50.0
            if #(coords - zone.coords) <= maxRange then
                return true, zone
            end
        end
    end

    return false, nil
end

local function _getPlayerCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

_canSellItemAtLocation = function(source, item)
    local coords = _getPlayerCoords(source)
    if not coords then return false, nil end

    local itemZones = _getItemZones(item)
    if itemZones then
        return _isCoordsInZones(coords, itemZones)
    end

    if _getSellingDefaultMode() == 'anywhere' then
        return true, nil
    end

    return _isCoordsInZones(coords, Config.Zones)
end

-- Helper to resolve a friendly item label per framework/inventory
local function resolveItemLabel(source, name)
    if not name then return '' end
    -- ox_inventory item list (server export)
    if GetResourceState('ox_inventory') == 'started' then
        local ok, items = pcall(function() return exports.ox_inventory:Items() end)
        if ok and items and items[name] then
            local it = items[name]
            return tostring(it.label or it.name or name)
        end
    end
    -- ESX: try inventory item label
    if Config.Framework == 'esx' then
        local xPlayer = GetPlayer(source)
        if xPlayer and xPlayer.getInventoryItem then
            local itm = xPlayer.getInventoryItem(name)
            if itm and itm.label then return tostring(itm.label) end
        end
    end
    -- Fallback to raw name
    return tostring(name)
end

-- Global helper: grant one-time level rewards
function GrantReward(source, reward)
    if not reward or not reward.type then return false end
    local typ = reward.type
    if typ == 'money' then
        local account = reward.account or 'cash'
        local amount = tonumber(reward.amount or 0) or 0
        if amount <= 0 then return false end
        if Config.Debug then
            print(('[Partay_hustle] GrantReward money -> %s %s to %s'):format(amount, account, tostring(source)))
        end
        if Config.Framework == 'esx' then
            local xPlayer = GetPlayer(source)
            if not xPlayer then return false end
            if account == 'bank' then
                xPlayer.addAccountMoney('bank', amount)
            elseif account == 'black_money' then
                xPlayer.addAccountMoney('black_money', amount)
            else
                xPlayer.addMoney(amount)
            end
        else -- qb/qbx
            local Player = GetPlayer(source)
            if Player and Player.Functions and Player.Functions.AddMoney then
                Player.Functions.AddMoney(account, amount, 'level-reward')
            else
                return false
            end
        end
        if Config.Rewards and Config.Rewards.notify then
            TriggerClientEvent('Partay_hustle:client:notify', source, 'success', ('Level reward: %s %s'):format(amount, account))
        end
        return true
    elseif typ == 'item' then
        local name = reward.name
        local amount = tonumber(reward.amount or 1) or 1
        if not name or amount <= 0 then return false end
        if Config.Debug then
            print(('[Partay_hustle] GrantReward item -> %sx %s to %s'):format(amount, name, tostring(source)))
        end
        if GetResourceState('ox_inventory') == 'started' then
            local ok = exports.ox_inventory:AddItem(source, name, amount, reward.metadata)
            if not ok then return false end
        elseif Config.Framework == 'esx' then
            local xPlayer = GetPlayer(source)
            if xPlayer then xPlayer.addInventoryItem(name, amount) else return false end
        else
            local Player = GetPlayer(source)
            if Player and Player.Functions and Player.Functions.AddItem then
                local ok = Player.Functions.AddItem(name, amount)
                if not ok then return false end
            else
                return false
            end
        end
        if Config.Rewards and Config.Rewards.notify then
            local label = resolveItemLabel(source, name)
            local disp = (amount and amount > 1) and (tostring(amount)..'x '..label) or label
            local msg = (_L and _L('item_received', { text = disp })) or ('Nice work, you received %s'):format(disp)
            TriggerClientEvent('Partay_hustle:client:notify', source, 'success', msg)
        end
        return true
    elseif typ == 'vehicle' then
        local model = reward.model
        if not model then return false end
        if Config.Debug then
            print(('[Partay_hustle] GrantReward vehicle -> %s to %s'):format(model, tostring(source)))
        end
        local handler = Config.Rewards and Config.Rewards.vehicle and Config.Rewards.vehicle.handlerEvent
        local ok
        if handler then
            -- Custom handler: fire and optimistically treat as success
            TriggerEvent(handler, source, model, reward)
            ok = true
        elseif type(PartayHustle_GiveVehicle) == 'function' then
            ok = PartayHustle_GiveVehicle(source, model, reward)
        else
            -- Fallback to generic integration hook (no success feedback)
            TriggerEvent('Partay_hustle:garage:giveVehicle', source, model, reward)
            ok = true
        end
        if ok and (Config.Rewards and Config.Rewards.notify) then
            local msg = (_L and _L('vehicle_stored')) or 'Nice work, your reward has been stored in the garage for your safety.'
            TriggerClientEvent('Partay_hustle:client:notify', source, 'success', msg)
        end
        return ok and true or false
    end
    return false
end

if Config.Framework == 'esx' then
    ESX = exports["es_extended"]:getSharedObject()

    function GetPlayer(source)
        return ESX.GetPlayerFromId(source)
    end

    function HasItem(source, item)
        if usingOxInventory() then
            return exports.ox_inventory:GetItemCount(source, item) or 0
        end
        local player = GetPlayer(source)
        local invItem = player.getInventoryItem(item)
        if invItem ~= nil then return invItem.count else return 0 end
    end

    function RemoveItem(source, item, amount)
        if usingOxInventory() then
            local removed = exports.ox_inventory:RemoveItem(source, item, amount)
            return removed and true or false, item
        end
        local xPlayer = ESX.GetPlayerFromId(source)
        local itemData = xPlayer.getInventoryItem(item)
        if not itemData or itemData.count < amount then return false end
        xPlayer.removeInventoryItem(item, amount)
        return true, (itemData.label or item)
    end

    function GiveItem(source, item, amount, reason, drugsold)
        local xPlayer = ESX.GetPlayerFromId(source)

        local payout = (drugsold and Config.DrugList[drugsold] and Config.DrugList[drugsold].payout) or nil

        if payout and payout.type == 'money' then
            local account = payout.name or 'cash'
            if account == 'cash' or account == 'money' then
                xPlayer.addMoney(amount)
            elseif account == 'bank' then
                xPlayer.addAccountMoney('bank', amount)
            elseif account == 'black_money' or account == 'dirtycash' then
                xPlayer.addAccountMoney('black_money', amount)
            else
                xPlayer.addInventoryItem(account, amount)
            end
        elseif payout and payout.type == 'item' then
            if usingOxInventory() then
                if not exports.ox_inventory:AddItem(source, payout.name, amount) then return false end
            else
                if xPlayer.canCarryItem then
                    if not xPlayer.canCarryItem(payout.name, amount) then
                        return false
                    end
                else
                    local invItem = xPlayer.getInventoryItem(payout.name)
                    if invItem and not ((invItem.limit == -1) or ((invItem.count + amount) <= invItem.limit)) then
                        return false
                    end
                end
                xPlayer.addInventoryItem(payout.name, amount)
            end
        else
            if item == 'money' then
                if usingOxInventory() then
                    exports.ox_inventory:AddItem(source, 'money', amount)
                else
                    xPlayer.addInventoryItem('money', amount)
                end
            else
                if usingOxInventory() then
                    exports.ox_inventory:AddItem(source, item, amount)
                else
                    xPlayer.addInventoryItem(item, amount)
                end
            end
        end

        local pointsAwarded
        if drugsold and Config.DrugList[drugsold] then
            local closestZoneInfo = GetClosestZoneInfo(source)
            local levelAdd = Config.DrugList[drugsold].leveladd or 20
            local baseMul = (Config.Leveling and Config.Leveling.baseMultiplier) or 1
            local hotspotMul = (Config.Leveling and Config.Leveling.hotspotMultiplier) or 2
            local useHot = not (Config.Leveling and Config.Leveling.useHotspotMultiplier == false)
            local isHot = (closestZoneInfo and closestZoneInfo.isHotSpot) and true or false
            local multiplier = baseMul * ((useHot and isHot) and hotspotMul or 1)
            pointsAwarded = math.floor(levelAdd * multiplier)
            if pointsAwarded > 0 then
                addlevelpoints(source, pointsAwarded)
            end
        end

        return true, pointsAwarded
    end
elseif Config.Framework == 'qb' or Config.Framework == 'qbx' then
    local QBCore
    local function GetCore()
        if QBCore then return QBCore end
        if GetResourceState('qbx_core') == 'started' then
            local ok, obj = pcall(function() return exports['qbx_core']:GetCoreObject() end)
            if ok and obj then QBCore = obj end
            if not QBCore then
                local ok2, obj2 = pcall(function() return exports['qbx_core']:GetQBCore() end)
                if ok2 and obj2 then QBCore = obj2 end
            end
        end
        if not QBCore and GetResourceState('qb-core') == 'started' then
            local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if ok and obj then QBCore = obj end
        end
        return QBCore
    end

    function GetPlayer(source)
        local Core = GetCore()
        if not Core then return nil end
        return Core.Functions.GetPlayer(source)
    end

    function RemoveItem(source, item, amount)
        if usingOxInventory() then
            return exports.ox_inventory:RemoveItem(source, item, amount) and true or false
        else
            local Player = GetPlayer(source)
            if not Player then return false end
            Player.Functions.RemoveItem(item, amount)
            local Core = GetCore()
            if Core and GetResourceState('qb-inventory') == 'started' and Core.Shared and Core.Shared.Items and Core.Shared.Items[item] then
                TriggerClientEvent('inventory:client:ItemBox', source, Core.Shared.Items[item], "remove")
            end
            return true
        end
    end

    function GiveItem(source, item, amount, reason, drugsold)
        local Player = GetPlayer(source)

        local payout = (drugsold and Config.DrugList[drugsold] and Config.DrugList[drugsold].payout) or nil

        if payout and payout.type == 'money' then
            local account = payout.name or 'cash'
            local Core = GetCore()
            if Core and Player and Player.Functions and Player.Functions.AddMoney then
                Player.Functions.AddMoney(account, amount, reason or 'svdden_drugselling_payout')
            else
                if usingOxInventory() then
                    exports.ox_inventory:AddItem(source, account, amount)
                end
            end
        elseif payout and payout.type == 'item' then
            if usingOxInventory() then
                if not exports.ox_inventory:AddItem(source, payout.name, amount) then return false end
            else
                if not Player then return false end
                if Player.Functions and Player.Functions.CanCarryItem then
                    if not Player.Functions.CanCarryItem(payout.name, amount) then
                        return false
                    end
                end
                Player.Functions.AddItem(payout.name, amount)
                local Core = GetCore()
                if Core and GetResourceState('qb-inventory') == 'started' and Core.Shared and Core.Shared.Items and Core.Shared.Items[payout.name] then
                    TriggerClientEvent('inventory:client:ItemBox', source, Core.Shared.Items[payout.name], "add")
                end
            end
        else
            if usingOxInventory() then
                exports.ox_inventory:AddItem(source, item, amount)
            else
                if not Player then return false end
                Player.Functions.AddItem(item, amount)
                local Core = GetCore()
                if Core and GetResourceState('qb-inventory') == 'started' and Core.Shared and Core.Shared.Items and Core.Shared.Items[item] then
                    TriggerClientEvent('inventory:client:ItemBox', source, Core.Shared.Items[item], "add")
                end
            end
        end

        local pointsAwarded
        if drugsold and Config.DrugList[drugsold] then
            local closestZoneInfo = GetClosestZoneInfo(source)
            local levelAdd = Config.DrugList[drugsold].leveladd or 20
            local baseMul = (Config.Leveling and Config.Leveling.baseMultiplier) or 1
            local hotspotMul = (Config.Leveling and Config.Leveling.hotspotMultiplier) or 2
            local useHot = not (Config.Leveling and Config.Leveling.useHotspotMultiplier == false)
            local isHot = (closestZoneInfo and closestZoneInfo.isHotSpot) and true or false
            local multiplier = baseMul * ((useHot and isHot) and hotspotMul or 1)
            pointsAwarded = math.floor(levelAdd * multiplier)
            if pointsAwarded > 0 then
                addlevelpoints(source, pointsAwarded)
            end
        end

        return true, pointsAwarded
    end

    function HasItem(source, item)
        if usingOxInventory() then
            return exports.ox_inventory:GetItemCount(source, item) or 0
        end
        local Player = GetPlayer(source)
        if Player then
            local itemObject = Player.Functions.GetItemByName(item)
            if itemObject then
                return itemObject.amount
            end
        end
        return 0
    end
end
function GetClosestZoneInfo(source)
    local playerCoords = GetEntityCoords(GetPlayerPed(source))
    local closestZone = nil
    local closestDistance = 999999.0

    for _, v in pairs(Config.Zones) do
        local zoneCoords = v.coords

        local distance = #(playerCoords - zoneCoords)
        if distance < closestDistance then
            closestDistance = distance
            closestZone = v
        end
    end
    return closestZone
end

local function HandleSale(drugs, count)
    local source = source
    -- basic input sanitize
    local dname = type(drugs) == 'string' and drugs or nil
    count = tonumber(count) or 1
    count = math.floor(count)
    if count < 1 then count = 1 end

    -- rate-limit to protect server from spam
    if _tooSoon(source) then
        if Config.Debug then print(('[Partay_hustle] throttled sale from %s'):format(source)) end
        return
    end

    -- hour cap before heavy work
    if not _checkAndBumpHourly(source) then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'You reached the hourly sale cap.')
        return
    end

    -- Enforce server-side requirement for /hustle use
    if not MeetsHustleRequirement(source) then
        local needLabel = (Config.HustleRequirement and Config.HustleRequirement.label)
            or (Config.HustleRequirement and Config.HustleRequirement.items and Config.HustleRequirement.items[1])
            or 'required item'
        TriggerClientEvent("Partay_hustle:client:notify", source, "error", "You are missing: " .. tostring(needLabel))
        return
    end
    -- Require a valid configured item
    if not dname or not Config.DrugList[dname] then
        if Config.Debug then print(('[Partay_hustle] invalid item from %s: %s'):format(source, tostring(dname))) end
        return
    end


    -- Enforce per-item location rules on the server to prevent client bypass.
    if not _canSellItemAtLocation(source, dname) then
        TriggerClientEvent("Partay_hustle:client:notify", source, "error", ((_L and _L('cannot_sell_here')) or 'You cannot sell here.'))
        return
    end

    -- Disallow hustling from inside vehicles (only if native is available server-side)
    local ped, model
    if type(GetPlayerPed) == 'function' then ped = GetPlayerPed(source) end
    if ped and ped ~= 0 then
        -- Enforce per-item seller model restriction when configured
        if type(GetEntityModel) == 'function' then
            model = GetEntityModel(ped)
            if not _isSellerModelAllowed(dname, model) then
                local altName, altCount = _findAlternateSellableItem(source, model, dname)
                if altName then
                    dname = altName
                    if altCount and altCount > 0 then
                        count = math.min(count, altCount)
                        if count < 1 then count = 1 end
                    end
                else
                    TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'You cannot sell this item with your current character.')
                    return
                end
            end
        end

        if not _canSellItemAtLocation(source, dname) then
            TriggerClientEvent("Partay_hustle:client:notify", source, "error", ((_L and _L('cannot_sell_here')) or 'You cannot sell here.'))
            return
        end

        local inVeh = false
        if type(IsPedInAnyVehicle) == 'function' then
            inVeh = IsPedInAnyVehicle(ped, false) and true or false
        elseif type(GetVehiclePedIsIn) == 'function' then
            local veh = GetVehiclePedIsIn(ped, false)
            inVeh = veh and veh ~= 0
        end
        if inVeh then
            TriggerClientEvent("Partay_hustle:client:notify", source, "error", ((_L and _L('no_vehicle')) or 'You cannot hustle from a vehicle.'))
            return
        end
    end


    -- Per-item cooldown now that we know which product we will sell
    if _perItemTooSoon(source, dname) then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'Slow down; try a different product or wait a moment.')
        return
    end
    local hasItem = HasItem(source, dname)

    if hasItem > 0 then
        local drugInfo = Config.DrugList[dname]
        local price = math.random(drugInfo.price.min, drugInfo.price.max)
        local qmin = math.max(1, tonumber(drugInfo.quantity and drugInfo.quantity.min) or 1)
        local qmax = math.max(qmin, tonumber(drugInfo.quantity and drugInfo.quantity.max) or qmin)
        local ame = count and math.floor(count) or 0
        if ame < 1 then
            ame = math.random(qmin, qmax)
        end
        if ame > qmax then ame = qmax end
        if ame > hasItem then ame = hasItem end
        if ame < qmin then
            if hasItem >= qmin then
                ame = qmin
            else
                ame = hasItem
            end
        end
        if ame < 1 then
            TriggerClientEvent("Partay_hustle:client:notify", source, "error", "You don't have enough products.")
            return
        end

        getplayerlevel(source, function(levelData)
            if levelData then
                local priceIncreasePercent = calculateDrugPriceIncrease(levelData.levelpoints)

                if Config.Debug then
                    print('ID: '..source.. ' / Level Points: '..levelData.levelpoints.. ' / Percent Increase: '..priceIncreasePercent)
                end

                price = price + (price * (priceIncreasePercent / 100))
            end

            RemoveItem(source, dname, ame)
            local total = math.floor(price * ame)
            local _, pointsAwarded = GiveItem(source, "money", total, 'sold-drugs', dname)
            _bumpHourly(source)
            _markPerItem(source, dname)
            TriggerClientEvent('Partay_hustle:client:saleNotify', source, {
                label = Config.DrugList[dname].label,
                quantity = ame,
                total = total,
                points = pointsAwarded or 0
            })

            if Config.Debug then
                print('ID: '..source.. ' Sold '.. ame .. 'x ' ..Config.DrugList[dname].label.. ' for $'.. total)
            end
            AwardExternalXP(source, { item = dname, label = Config.DrugList[dname].label, quantity = ame, total = total })
            MaybeDispatch(source, dname)
        end)

    else
        TriggerClientEvent("Partay_hustle:client:notify", source, "error", "You're trying to do something funny?")
    end
end

RegisterNetEvent("Partay_hustle:server:sell", function(drugs, count)
    HandleSale(drugs, count)
end)

-- Backwards compatibility; forward old event name to new handler
RegisterNetEvent("Partay_hustle:server:banplayer", function(drugs, count, timesSold)
    if Config.Debug then print('[Partay_hustle] banplayer event is deprecated; use Partay_hustle:server:sell') end
    HandleSale(drugs, count)
end)

lib.callback.register('Partay_hustle:getallavailableDrugs', function(source)
    -- light callback rate limit
    local now = GetGameTimer() or 0
    local limit = (Config.RateLimits and Config.RateLimits.getAvailableDrugMs) or 300
    local last = _lastCbAt[source] or 0
    if now - last < limit then
        local c = _drugCache[source]
        local useFallbackScan = false
        if c and (now - (c.ts or 0) < 1500) then
            local cnt = HasItem(source, c.name) or 0
            if cnt > 0 then
                if not _canSellItemAtLocation(source, c.name) then
                    useFallbackScan = true
                else
                -- Enforce seller restriction even on cached fast-path and notify if applicable
                    local ped, model
                    if type(GetPlayerPed) == 'function' then ped = GetPlayerPed(source) end
                    if ped and ped ~= 0 and type(GetEntityModel) == 'function' then
                        model = GetEntityModel(ped)
                        if not _isSellerModelAllowed(c.name, model) then
                            useFallbackScan = true
                        else
                            _notifyAllowedIfApplicable(source, c.name, model)
                            return c.name, cnt
                        end
                    else
                        return c.name, cnt
                    end
                end
            else
                useFallbackScan = true
            end
        else
            useFallbackScan = true
        end
        if not useFallbackScan then
            return nil, 0
        end
    end

    _lastCbAt[source] = now

    -- short-lived cache to avoid scanning full list repeatedly
    local cached = _drugCache[source]
    if cached and (now - (cached.ts or 0) < 1500) then
        local cnt = HasItem(source, cached.name) or 0
        if cnt > 0 and _canSellItemAtLocation(source, cached.name) then
            local ped, model
            if type(GetPlayerPed) == 'function' then ped = GetPlayerPed(source) end
            if ped and ped ~= 0 and type(GetEntityModel) == 'function' then
                model = GetEntityModel(ped)
                if not _isSellerModelAllowed(cached.name, model) then
                    -- fall through to full scan below
                else
                    _notifyAllowedIfApplicable(source, cached.name, model)
                    return cached.name, cnt
                end
            else
                return cached.name, cnt
            end
        end
    end

    -- Determine player's model once for filtering
    local ped, model
    if type(GetPlayerPed) == 'function' then ped = GetPlayerPed(source) end
    if ped and ped ~= 0 and type(GetEntityModel) == 'function' then
        model = GetEntityModel(ped)
    end

    for drugName, _ in pairs(Config.DrugList) do
        local drugCount = HasItem(source, drugName) or 0
        if drugCount > 0 then
            -- If there is a seller model restriction, enforce it here
            if (not model or _isSellerModelAllowed(drugName, model)) and _canSellItemAtLocation(source, drugName) then
                _drugCache[source] = { name = drugName, ts = now }
                if model then _notifyAllowedIfApplicable(source, drugName, model) end
                return drugName, drugCount
            end
        end
    end
    return nil, 0
end)

local function _hasSellableItemAtLocation(source)
    if not Config.DrugList then return false end

    local ped, model
    if type(GetPlayerPed) == 'function' then ped = GetPlayerPed(source) end
    if ped and ped ~= 0 and type(GetEntityModel) == 'function' then
        model = GetEntityModel(ped)
    end

    for item in pairs(Config.DrugList) do
        local count = HasItem(source, item) or 0
        if count > 0 and (not model or _isSellerModelAllowed(item, model)) and _canSellItemAtLocation(source, item) then
            return true, item
        end
    end

    return false
end

local function _hasAnySellableItem(source)
    if not Config.DrugList then return false end

    local ped, model
    if type(GetPlayerPed) == 'function' then ped = GetPlayerPed(source) end
    if ped and ped ~= 0 and type(GetEntityModel) == 'function' then
        model = GetEntityModel(ped)
    end

    for item in pairs(Config.DrugList) do
        local count = HasItem(source, item) or 0
        if count > 0 and (not model or _isSellerModelAllowed(item, model)) then
            return true, item
        end
    end

    return false
end

-- Server-side guard for /hustle requirement
function MeetsHustleRequirement(source)
    local req = Config.HustleRequirement
    if not req or req.enabled == false then return true end
    local items = req.items or {}
    if #items == 0 then return true end
    local any = req.any ~= false
    if any then
        for _, name in ipairs(items) do
            if (HasItem(source, name) or 0) > 0 then
                return true
            end
        end
        return false
    else
        for _, name in ipairs(items) do
            if (HasItem(source, name) or 0) <= 0 then
                return false
            end
        end
        return true
    end
end

-- Server-side predicate to allow client to pre-check before spawning buyer
lib.callback.register('Partay_hustle:canHustle', function(source)
    if not MeetsHustleRequirement(source) then
        return false, 'missing_item'
    end
    local hasAnyProduct = _hasAnySellableItem(source)
    if not hasAnyProduct then
        return false, 'no_products'
    end
    local hasSellable = _hasSellableItemAtLocation(source)
    if not hasSellable then
        return false, 'not_in_zone'
    end
    return true
end)

-- Dispatch helpers
local function getJobName(src)
    if Config.Framework == 'esx' then
        local xPlayer = GetPlayer(src)
        if xPlayer then
            if xPlayer.getJob then
                local job = xPlayer.getJob()
                return job and job.name
            elseif xPlayer.job then
                return xPlayer.job.name
            end
        end
    else
        local Player = GetPlayer(src)
        if Player and Player.PlayerData and Player.PlayerData.job then
            return Player.PlayerData.job.name
        end
    end
    return nil
end

local function isJobListed(jobName, list)
    if not jobName or not list then return false end
    for _, j in ipairs(list) do
        if j == jobName then return true end
    end
    return false
end

local function basicNotifyPolice(coords, message)
    local cfg = Config.Dispatch and Config.Dispatch.basic or {}
    local policeJobs = (Config.Dispatch and Config.Dispatch.jobs) or { 'police' }
    for _, id in ipairs(GetPlayers()) do
        local pid = tonumber(id)
        if pid then
            local job = getJobName(pid)
            if isJobListed(job, policeJobs) then
                TriggerClientEvent('Partay_hustle:client:notify', pid, 'warning', message or (Config.Dispatch and Config.Dispatch.message) or 'Suspicious activity reported')
                if cfg.blip then
                    TriggerClientEvent('Partay_hustle:client:policeBlip', pid, coords, cfg.blipTime or 30, cfg.radius or 60.0, cfg.color or 1, cfg.alpha or 160)
                end
            end
        end
    end
end

function MaybeDispatch(source, item)
    if not Config.Dispatch then return end
    local per = Config.DrugList[item] and Config.DrugList[item].dispatch or nil
    local enabled = (per and per.enabled)
    if enabled == nil then enabled = Config.Dispatch.enabled end
    if enabled == false then return end

    local chance = tonumber((per and per.chance) or Config.Dispatch.chance or 0) or 0
    if chance <= 0 then return end
    if chance < 100 and math.random(1,100) > chance then return end

    local coords
    if type(GetPlayerPed) == 'function' and type(GetEntityCoords) == 'function' then
        coords = GetEntityCoords(GetPlayerPed(source))
    else
        -- Fallback: try player ped coords via client if needed, but keep a sane default
        coords = vec3(0.0, 0.0, 0.0)
    end
    local system = (per and per.system) or Config.Dispatch.system or 'basic'
    if system == 'none' then return end
    local rawTitle = (per and per.title) or Config.Dispatch.title or 'Suspicious Activity'
    local rawMessage = (per and per.message) or Config.Dispatch.message or 'Possible street deal reported'
    local code = (per and per.code) or Config.Dispatch.code or '10-66'

    -- dynamic details (server-safe: some natives are client-only)
    local label = (Config.DrugList[item] and Config.DrugList[item].label) or tostring(item)
    local street = 'unknown street'
    local zoneLabel = 'Unknown'

    -- Only attempt if the native exists in this runtime
    if type(GetStreetNameAtCoord) == 'function' and type(GetStreetNameFromHashKey) == 'function' then
        local s1, s2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
        local street1 = s1 and GetStreetNameFromHashKey(s1) or ''
        local street2 = s2 and GetStreetNameFromHashKey(s2) or ''
        street = street1 ~= '' and (street2 ~= '' and (street1 .. ' & ' .. street2) or street1) or street
    end

    if type(GetNameOfZone) == 'function' and type(GetLabelText) == 'function' then
        local zone = GetNameOfZone(coords.x, coords.y, coords.z)
        local zl = (zone and GetLabelText(zone)) or zone
        if zl and zl ~= '' and zl ~= 'NULL' then zoneLabel = zl end
    end
    local function fmt(str)
        if not str then return '' end
        str = str:gsub('%%', '%%%%')
        str = str:gsub('{item}', tostring(item))
                 :gsub('{label}', tostring(label))
                 :gsub('{street}', tostring(street))
                 :gsub('{zone}', tostring(zoneLabel))
                 :gsub('{code}', tostring(code))
        return str
    end
    -- inject placeholders
    local title = fmt(rawTitle)
    local message = fmt(rawMessage)

    -- optionally prefix code in title if not already present or templated
    if (Config.Dispatch and Config.Dispatch.includeCodeInTitle) and code and code ~= '' then
        local plain = title:lower()
        if not plain:find(code:lower(), 1, true) and not rawTitle:find('{code}', 1, true) then
            title = (code .. ' ' .. title)
        end
    end

    if system == 'cd' and GetResourceState('cd_dispatch') == 'started' then
        local jobs = Config.Dispatch.jobs or { 'police' }
        local cd = Config.Dispatch.cd or {}
        -- Send one styled notification per department for custom colors/sprites
        for _, job in ipairs(jobs) do
            local style = (cd.styles and cd.styles[job]) or {}
            TriggerEvent('cd_dispatch:AddNotification', {
                job_table = { job },
                coords = coords,
                title = title,
                message = message,
                unique_id = tostring(source) .. '-' .. tostring(math.random(1000,9999)),
                blip = {
                    sprite = style.sprite or cd.sprite or 51,
                    colour = style.color or cd.color or 1,
                    scale = style.scale or cd.scale or 1.0,
                    radius = style.radius or cd.radius or 60.0,
                    alpha = 180,
                    length = ((cd.blipTime or 60)) * 1000
                }
            })
        end
        return
    end

    if system == 'ps' and GetResourceState('ps-dispatch') == 'started' then
        local ok = pcall(function()
            if exports['ps-dispatch'] and exports['ps-dispatch'].CustomDispatch then
                exports['ps-dispatch']:CustomDispatch({
                    code = code,
                    message = message,
                    coords = coords,
                    radius = (Config.Dispatch.cd and Config.Dispatch.cd.radius) or 60.0
                })
            else
                -- Fallback event if your ps-dispatch defines it
                if Config.Dispatch.ps and Config.Dispatch.ps.event then
                    TriggerEvent(Config.Dispatch.ps.event, { code = code, message = message, coords = coords })
                else
                    basicNotifyPolice(coords, message)
                end
            end
        end)
        if ok then return end
    end

    if system == 'lb' and (GetResourceState('lb-tablet') == 'started' or GetResourceState('lb_tablet') == 'started') then
        if Config.Dispatch.lb and Config.Dispatch.lb.event then
            TriggerEvent(Config.Dispatch.lb.event, { code = code, message = message, coords = coords })
            return
        end
        -- no defined event; fall back
    end

    -- basic or fallback
    basicNotifyPolice(coords, message)
end

lib.callback.register('Partay_hustle:getItemCount', function(source, item)
    if type(item) ~= 'string' or item == '' then return 0 end
    if not Config.DrugList[item] then return 0 end
    return HasItem(source, item) or 0
end)

lib.callback.register('Partay_hustle:getSalePreview', function(source, item)
    if type(item) ~= 'string' or item == '' then return 0 end
    local entry = Config.DrugList[item]
    if not entry then return 0 end
    local hasItem = HasItem(source, item) or 0
    if hasItem <= 0 then return 0 end

    local qmin = math.max(1, tonumber(entry.quantity and entry.quantity.min) or 1)
    local qmax = math.max(qmin, tonumber(entry.quantity and entry.quantity.max) or qmin)
    local qty = math.random(qmin, qmax)
    if qty > hasItem then qty = hasItem end
    if qty < 1 then qty = 1 end
    return qty
end)


-- Utility: check if a resource exports a specific function
local function _resourceHasExport(resource, exportName)
    if not resource or not exportName then return false end
    local function hasMeta(key)
        local idx = 0
        while true do
            local value = GetResourceMetadata(resource, key, idx)
            if not value then break end
            if value == exportName then return true end
            idx = idx + 1
        end
        return false
    end
    if hasMeta('server_export') then return true end
    if hasMeta('export') then return true end
    return false
end

-- Allow requirement items to trigger /hustle when used
local function _triggerHustleFromItem(source)
    if not source then return end
    TriggerClientEvent('Partay_hustle:client:startHustle', source)
end

local function _registerHustleUsableItems()
    local req = Config.HustleRequirement
    if not req or not req.items then return end
    local seen = {}

    local function registerOx(item)
        if GetResourceState('ox_inventory') ~= 'started' then return false end
        local registeredAs = nil
        if _resourceHasExport('ox_inventory', 'RegisterUsableItem') and exports.ox_inventory and exports.ox_inventory.RegisterUsableItem then
            local ok = pcall(function()
                exports.ox_inventory:RegisterUsableItem(item, function(data, slot)
                    local src = source
                    if type(data) == 'table' then
                        src = data.source or data.playerId or src
                    elseif type(data) == 'number' then
                        src = data
                    end
                    _triggerHustleFromItem(src)
                end)
            end)
            if ok then registeredAs = 'ox_export' end
        end
        if not registeredAs then
            local ok = pcall(function()
                TriggerEvent('ox_inventory:registerUsableItem', item, function(data, slot)
                    local src = source
                    if type(data) == 'table' then
                        src = data.source or data.playerId or src
                    elseif type(data) == 'number' then
                        src = data
                    end
                    _triggerHustleFromItem(src)
                end)
            end)
            if ok then registeredAs = 'ox_event' end
        end
        if registeredAs then return true, registeredAs end
        return false
    end

    local function registerQB(item)
        if Config.Framework ~= 'qb' and Config.Framework ~= 'qbx' then return false end
        local core
        if GetResourceState('qbx_core') == 'started' then
            local ok, obj = pcall(function() return exports['qbx_core']:GetCoreObject() end)
            if ok and obj then core = obj end
            if not core then
                local ok2, obj2 = pcall(function() return exports['qbx_core']:GetQBCore() end)
                if ok2 and obj2 then core = obj2 end
            end
        end
        if not core and GetResourceState('qb-core') == 'started' then
            local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if ok and obj then core = obj end
        end
        if not core or not core.Functions or not core.Functions.CreateUseableItem then return false end
        local ok = pcall(function()
            core.Functions.CreateUseableItem(item, function(source, itemData)
                _triggerHustleFromItem(source)
            end)
        end)
        if ok then return true, 'qb' end
        return false
    end

    local function registerESX(item)
        if Config.Framework ~= 'esx' then return false end
        if not ESX or not ESX.RegisterUsableItem then return false end
        local ok = pcall(function()
            ESX.RegisterUsableItem(item, function(source)
                _triggerHustleFromItem(source)
            end)
        end)
        if ok then return true, 'esx' end
        return false
    end

    for _, name in ipairs(req.items) do
        local item = (type(name) == 'string') and name or nil
        if item and item ~= '' and not seen[item] then
            seen[item] = true
            local registeredVia = {}
            local okOx, tagOx = registerOx(item)
            if okOx then table.insert(registeredVia, tagOx or 'ox') end
            local okQB, tagQB = registerQB(item)
            if okQB then table.insert(registeredVia, tagQB or 'qb') end
            local okESX, tagESX = registerESX(item)
            if okESX then table.insert(registeredVia, tagESX or 'esx') end
            if Config.Debug then
                local status = (#registeredVia > 0) and ('registered via ' .. table.concat(registeredVia, ', ')) or 'no handler'
                print(('[Partay_hustle] Hustle usable item %s -> %s'):format(item, status))
            end
        end
    end
end

CreateThread(function()
    Wait(500)
    _registerHustleUsableItems()
end)





