local Framework = _G.PartayFramework
local Storage = _G.PartayStorage
local Discord = _G.PartayDiscord

if not Framework or not Storage or not Discord then
    error('[Partay_claimpacks] Framework/Storage/Discord modules missing; ensure server scripts load in order.', 0)
end

local Claims = _G.PartayClaims or {}
_G.PartayClaims = Claims
local stayReady = {}

local LOCALE = Config.Locale or 'en'
local now = os.time

local function translate(key, ...)
    local locale = Locales and Locales[LOCALE]
    local text = locale and locale[key] or key
    if select('#', ...) > 0 and type(text) == 'string' and text:find('%%') then
        return text:format(...)
    end
    return text
end

local function toVector3(value)
    if type(value) == 'vector3' then
        return value
    end
    if type(value) == 'table' then
        local x = value.x or value[1] or 0.0
        local y = value.y or value[2] or 0.0
        local z = value.z or value[3] or 0.0
        return vector3(x + 0.0, y + 0.0, z + 0.0)
    end
    return vector3(0.0, 0.0, 0.0)
end

local function getLocationById(locationId)
    for _, location in ipairs(Config.Locations or {}) do
        if location.id == locationId then
            return location
        end
    end
    return nil
end

local function normalizeRewards(reward)
    if type(reward) ~= 'table' then return {} end

    if reward.name then
        return { reward }
    end

    local list = {}

    for _, item in ipairs(reward) do
        if type(item) == 'table' and item.name then
            list[#list + 1] = item
        end
    end

    for key, value in pairs(reward) do
        if type(key) == 'string' and list[key] == nil then
            if type(value) == 'number' then
                list[#list + 1] = { name = key, count = value }
            elseif type(value) == 'table' and value.name == nil then
                list[#list + 1] = { name = key, count = value.count or 1, metadata = value.metadata, money = value.money or value.cost }
            end
        end
    end

    return list
end

local function getReadyTable(source)
    local entry = stayReady[source]
    if not entry then
        entry = {}
        stayReady[source] = entry
    end
    return entry
end

local function clearReady(source, locationId)
    local entry = stayReady[source]
    if entry then
        if locationId then
            entry[locationId] = nil
        else
            stayReady[source] = nil
            return
        end
        if next(entry) == nil then
            stayReady[source] = nil
        end
    end
end

local function setReady(source, locationId, durationSeconds)
    local entry = getReadyTable(source)
    local current = GetGameTimer()
    local base = math.max(0, (durationSeconds or 0) * 1000)
    entry[locationId] = current + math.max(15000, base + 5000)
end

local function hasReady(source, locationId)
    local entry = stayReady[source]
    if not entry then return false end
    local expiry = entry[locationId]
    if not expiry then return false end
    if expiry < GetGameTimer() then
        clearReady(source, locationId)
        return false
    end
    return true
end

local function withinZone(source, location)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    local playerCoords = GetEntityCoords(ped)
    if not playerCoords then return false end
    local center = location.ped and location.ped.coords and toVector3(location.ped.coords)
    if not center then return false end
    local radius = location.zoneRadius or Config.DefaultZoneRadius or 3.0
    local distance = #(playerCoords - center)
    return distance <= (radius + 0.75)
end

local function meetsDiscordRestriction(source, location)
    if not location.allowedDiscordRoles then return true end
    return Discord.HasAnyRole(source, location.allowedDiscordRoles)
end

local function meetsJobRestriction(source, location)
    if not location.allowedJobs then return true end
    return Framework.HasJob(source, location.allowedJobs)
end

local function meetsGenderRestriction(source, location)
    if not location.gender then return true end
    local gender = Framework.GetGender(source)
    if not gender then return false end
    local required = type(location.gender) == 'string' and location.gender:lower() or location.gender
    return gender == required
end

local function giveRewards(source, location)
    local rewards = normalizeRewards(location.reward or location.rewards)
    if #rewards == 0 then return false, 'invalid_reward' end

    local inventory = exports['ox_inventory']
    if not inventory then
        return false, 'inventory_missing'
    end

    local currencyItem = Config.CurrencyItem or 'money'
    local freeRewards = {}
    local paidRewards = {}

    for _, item in ipairs(rewards) do
        local cost = tonumber(item.money or item.cost)
        if cost and cost > 0 then
            paidRewards[#paidRewards + 1] = { name = item.name, count = item.count or 1, metadata = item.metadata, cost = math.floor(cost) }
        else
            freeRewards[#freeRewards + 1] = item
        end
    end

    local payableRewards = {}
    local missingFunds = {}
    local totalCost = 0
    local removedCost = 0

    if #paidRewards > 0 then
        local balance = tonumber(inventory:Search(source, 'count', currencyItem)) or 0
        for _, item in ipairs(paidRewards) do
            if balance >= item.cost then
                balance = balance - item.cost
                totalCost = totalCost + item.cost
                payableRewards[#payableRewards + 1] = item
            else
                missingFunds[#missingFunds + 1] = item.name
            end
        end

        if totalCost > 0 then
            local removed = inventory:RemoveItem(source, currencyItem, totalCost)
            if not removed or removed == 0 then
                return false, 'payment_failed'
            end
            removedCost = totalCost
        end
    end

    local deliver = {}
    for _, item in ipairs(freeRewards) do
        deliver[#deliver + 1] = item
    end
    for _, item in ipairs(payableRewards) do
        deliver[#deliver + 1] = item
    end

    if #deliver == 0 then
        if removedCost > 0 then
            inventory:AddItem(source, currencyItem, removedCost)
        end
        if #missingFunds > 0 then
            return false, 'insufficient_funds', { items = missingFunds }
        end
        return false, 'invalid_reward'
    end

    if not Config.GrantToInventory then
        local center = location.ped and location.ped.coords and toVector3(location.ped.coords)
        inventory:CustomDrop(location.label or location.id, deliver, center or vector3(0.0, 0.0, 0.0))
        if #missingFunds > 0 then
            return true, 'reward_partial', { missing = missingFunds }
        end
        return true, 'reward_granted'
    end

    if Config.DenyIfFull then
        for _, item in ipairs(deliver) do
            if not inventory:CanCarryItem(source, item.name, item.count or 1, item.metadata) then
                if removedCost > 0 then
                    inventory:AddItem(source, currencyItem, removedCost)
                end
                return false, 'inventory_full'
            end
        end
    end

    local failed = {}
    for _, item in ipairs(deliver) do
        local success = inventory:AddItem(source, item.name, item.count or 1, item.metadata)
        if not success then
            failed[#failed + 1] = item
        end
    end

    if #failed > 0 then
        if Config.DenyIfFull then
            if removedCost > 0 then
                inventory:AddItem(source, currencyItem, removedCost)
            end
            return false, 'inventory_full'
        end
        local center = location.ped and location.ped.coords and toVector3(location.ped.coords)
        inventory:CustomDrop(location.label or location.id, failed, center or vector3(0.0, 0.0, 0.0))
        return true, 'reward_dropped'
    end

    if #missingFunds > 0 then
        return true, 'reward_partial', { missing = missingFunds }
    end

    return true, 'reward_granted'
end

local function parseOneTime(value)
    if value == nil then
        return true
    end
    if type(value) == 'boolean' then
        return value
    end
    if type(value) == 'string' then
        value = value:lower()
        if value == 'true' or value == '1' or value == 'yes' then
            return true
        end
        if value == 'false' or value == '0' or value == 'no' then
            return false
        end
    end
    return value and true or false
end

local function parseRoleCaps(roleCaps)
    if type(roleCaps) ~= 'table' then return nil end
    local result = {}
    for key, value in pairs(roleCaps) do
        local roleId
        local limit
        local label
        if type(key) == 'number' and type(value) == 'table' then
            roleId = value.role or value.roleId or value.id
            limit = value.limit or value.cap or value.count
            label = value.label
        elseif type(key) == 'string' then
            roleId = key
            if type(value) == 'table' then
                limit = value.limit or value.cap or value.count
                label = value.label
            else
                limit = value
            end
        end
        limit = tonumber(limit)
        if roleId and limit and limit > 0 then
            result[#result + 1] = { roleId = roleId, limit = math.floor(limit), label = label }
        end
    end
    if #result == 0 then
        return nil
    end
    return result
end

local function resolveRoleCap(source, location)
    local caps = parseRoleCaps(location.roleCaps)
    if not caps then
        return true, nil
    end

    for _, entry in ipairs(caps) do
        if Discord.HasDiscordRole(source, entry.roleId) then
            local count = Storage.GetRoleClaimCount(entry.roleId, location.id)
            if count >= entry.limit then
                return false, { roleId = entry.roleId, limit = entry.limit, label = entry.label }
            end
            entry.count = count
            return true, entry
        end
    end

    return false, { limit = 0 }
end

local function fetchLastClaim(identifier, locationId)
    if not identifier or identifier == '' then return nil end
    local data = Storage.GetClaimData(identifier, locationId)
    return data and tonumber(data.last) or nil
end

function Claims.HandleStayComplete(source, locationId)
    local location = getLocationById(locationId)
    if not location then return end
    if Config.RequireStay == false then return end
    if not location.requireTimeSeconds or location.requireTimeSeconds <= 0 then return end
    setReady(source, locationId, location.requireTimeSeconds)
end

function Claims.HandleStayReset(source, locationId)
    clearReady(source, locationId)
end

function Claims.HandleClaim(source, locationId)
    Storage.Init()
    local location = getLocationById(locationId)
    if not location then
        return false, 'invalid_location'
    end

    if location.requireTimeSeconds and location.requireTimeSeconds > 0 and Config.RequireStay ~= false then
        if not hasReady(source, locationId) then
            return false, 'not_ready', location
        end
        if not withinZone(source, location) then
            clearReady(source, locationId)
            return false, 'not_ready', location
        end
    end

    if not meetsGenderRestriction(source, location) then
        return false, 'wrong_gender', location
    end

    if not meetsJobRestriction(source, location) then
        return false, 'job_restricted', location
    end

    if not meetsDiscordRestriction(source, location) then
        return false, 'missing_role', location
    end

    local player = Framework.GetPlayerData(source)
    if not player then
        return false, 'framework_missing', location
    end

    local identifier = player.identifier or Framework.GetIdentifier(source) or ('source:' .. tostring(source))
    if not identifier or identifier == '' then
        return false, 'framework_missing', location
    end

    local lastClaimAt = fetchLastClaim(identifier, location.id)
    local isOneTime = parseOneTime(location.oneTime)

    if isOneTime and lastClaimAt then
        return false, 'already_claimed', location
    end

    local cooldown = tonumber(location.cooldownSeconds)
    if cooldown and cooldown > 0 and lastClaimAt then
        local remaining = cooldown - (now() - lastClaimAt)
        if remaining > 0 then
            return false, 'cooldown_active', location, { remaining = remaining }
        end
    end

    local roleOk, roleData = resolveRoleCap(source, location)
    if not roleOk then
        return false, 'role_cap_reached', location, roleData
    end

    if isOneTime and not lastClaimAt then
        if Storage.HasClaimed(identifier, location.id) then
            return false, 'already_claimed', location
        end
    end

    local granted, resultKey, resultMeta = giveRewards(source, location)
    if not granted then
        return false, resultKey or 'inventory_error', location, resultMeta
    end

    local timestamp = now()
    Storage.MarkClaimed(identifier, location.id, timestamp)

    if roleData and roleData.roleId then
        Storage.IncrementRoleClaim(roleData.roleId, location.id)
    end

    clearReady(source, locationId)

    local meta = type(resultMeta) == 'table' and resultMeta or {}
    if not meta.player then meta.player = player end
    if not meta.role then meta.role = roleData end

    return true, resultKey or 'reward_granted', location, meta
end

function Claims.Translate(key, ...)
    return translate(key, ...)
end

function Claims.LocationData(locationId)
    return getLocationById(locationId)
end

AddEventHandler('playerDropped', function()
    local src = source
    clearReady(src)
end)

return Claims
