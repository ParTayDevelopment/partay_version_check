local Framework = _G.PartayFramework
local Claims = _G.PartayClaims
local Storage = _G.PartayStorage
if not Framework or not Claims or not Storage then
    error('[Partay_claimpacks] Server modules missing; check fxmanifest load order.', 0)
end

local Notify = PartayClaimpacksNotify
local LOCALE = Config.Locale or 'en'

local function translate(key, ...)
    local locale = Locales and Locales[LOCALE]
    local text = locale and locale[key] or key
    if select('#', ...) > 0 and type(text) == 'string' and text:find('%%') then
        return text:format(...)
    end
    return text
end

local function formatJobList(jobs)
    if type(jobs) ~= 'table' then
        return tostring(jobs)
    end
    local names = {}
    for key, value in pairs(jobs) do
        local name = type(key) == 'number' and value or key
        if type(name) == 'string' then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return table.concat(names, ', ')
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds <= 0 then return '0s' end

    local units = {
        { label = 'd', value = 86400 },
        { label = 'h', value = 3600 },
        { label = 'm', value = 60 },
        { label = 's', value = 1 }
    }

    local parts = {}
    for _, unit in ipairs(units) do
        if seconds >= unit.value then
            local amount = math.floor(seconds / unit.value)
            seconds = seconds - (amount * unit.value)
            parts[#parts + 1] = ('%d%s'):format(amount, unit.label)
        end
    end

    return table.concat(parts, ' ')
end

local function sendNotification(source, kind, message, location)
    if not Notify then return end
    local title = location and (location.label or location.id) or 'partay_claimpacks'
    local payload = {
        title = title,
        description = message
    }

    if kind == 'success' then
        Notify.Success(source, message, payload)
    elseif kind == 'warning' then
        Notify.Warning(source, message, payload)
    else
        Notify.Error(source, message, payload)
    end
end

local function sanitizeLocationId(locationId)
    if type(locationId) ~= 'string' then return nil end
    return locationId
end

local function handleClaim(source, locationId)
    locationId = sanitizeLocationId(locationId)
    if not locationId then
        local message = translate('invalid_location')
        sendNotification(source, 'error', message)
        return { success = false, reason = 'invalid_location', message = message }
    end

    local success, key, location, meta = Claims.HandleClaim(source, locationId)

    if not success then
        local message
        local notificationKind = 'error'

        if key == 'wrong_gender' and location then
            message = translate('wrong_gender', location.gender)
        elseif key == 'job_restricted' and location then
            message = translate('job_restricted', formatJobList(location.allowedJobs))
        elseif key == 'cooldown_active' and meta and meta.remaining then
            message = translate('cooldown_active', formatDuration(meta.remaining))
            notificationKind = 'warning'
        elseif key == 'role_cap_reached' and meta and meta.limit then
            local label = meta.label or meta.roleId or 'your role'
            message = translate('role_cap_reached', meta.limit, label)
            notificationKind = 'warning'
        elseif key == 'insufficient_funds' and meta and meta.items then
            message = translate('insufficient_funds', table.concat(meta.items, ', '))
            notificationKind = 'warning'
        elseif key == 'payment_failed' then
            message = translate('payment_failed')
        else
            message = translate(key or 'permission_denied')
        end

        sendNotification(source, notificationKind, message, location)
        return { success = false, reason = key, message = message, meta = meta }
    end

    local message
    if key == 'reward_dropped' then
        message = translate('reward_dropped')
    elseif key == 'reward_partial' then
        if meta and meta.missing then
            message = translate('reward_partial', table.concat(meta.missing, ', '))
        else
            message = translate('reward_partial', 'items')
        end
        notificationKind = 'warning'
    else
        message = translate('reward_granted', location and location.label or '')
    end

    sendNotification(source, 'success', message, location)
    TriggerClientEvent('Partay_claimpacks:client:claimed', source, locationId)

    return {
        success = true,
        key = key,
        message = message,
        location = location and location.id or locationId,
        meta = meta
    }
end

RegisterNetEvent('Partay_claimpacks:server:stayComplete', function(locationId)
    local src = source
    locationId = sanitizeLocationId(locationId)
    if not locationId then return end
    Claims.HandleStayComplete(src, locationId)
end)

RegisterNetEvent('Partay_claimpacks:server:stayReset', function(locationId)
    local src = source
    locationId = sanitizeLocationId(locationId)
    if not locationId then return end
    Claims.HandleStayReset(src, locationId)
end)

lib.callback.register('Partay_claimpacks:server:claim', function(source, locationId)
    return handleClaim(source, locationId)
end)

lib.callback.register('Partay_claimpacks:server:hasClaimed', function(source, locationId)
    locationId = sanitizeLocationId(locationId)
    if not locationId then return false end

    local location = Claims.LocationData(locationId)
    if not location or location.oneTime == false then
        return false
    end

    Storage.Init()
    local player = Framework.GetPlayerData(source)
    if not player or not player.identifier then
        if Config.Debug then
            print(('[Partay_claimpacks] hasClaimed pending framework data for source=%s location=%s'):format(tostring(source), tostring(locationId)))
        end
        return false, 'pending_player_data'
    end
    return Storage.HasClaimed(player.identifier, locationId), nil
end)

CreateThread(function()
    Storage.Init()
    Wait(500)
    local frameworkName = Framework.GetFramework() or 'none'
    local storageMode = Storage.UsingSql() and 'oxmysql' or 'unavailable'
    print(('[Partay_claimpacks] Initialised. Framework=%s, Storage=%s'):format(frameworkName, storageMode))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    print('[Partay_claimpacks] Resource stopping.')
end)







