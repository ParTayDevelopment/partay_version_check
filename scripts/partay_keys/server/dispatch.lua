-- [[ Dispatch Bridge ]] --

local lastAlertByKey = {}

local function DebugDispatch(message)
    if Config and Config.DebugMode then
        print(('^5[ParTay Keys Debug]^3 Dispatch: %s^0'):format(tostring(message)))
    end
end

local function GetDispatchConfig()
    return Config.Integrations and Config.Integrations.Dispatch or {}
end

local function IsResourceStarted(resource)
    return resource and resource ~= '' and GetResourceState(resource) == 'started'
end

local function ResolveDispatchProvider()
    local dispatch = GetDispatchConfig()
    local provider = dispatch.Provider or 'auto'
    if provider == 'disabled' then return 'disabled' end
    if provider ~= 'auto' then return provider end

    local providers = dispatch.Providers or {}
    for _, name in ipairs({ 'cd', 'ps', 'lb-tablet', 'qbx', 'qb', 'esx' }) do
        local resource = providers[name] and providers[name].Resource
        if IsResourceStarted(resource) then return name end
    end

    return Bridge.GetFramework()
end

function PartayKeys_GetDispatchProvider()
    return ResolveDispatchProvider()
end

exports('GetDispatchProvider', PartayKeys_GetDispatchProvider)

local function BuildAlertPayload(payload)
    payload = type(payload) == 'table' and payload or {}
    local coords = payload.coords or payload.location or vector3(0.0, 0.0, 0.0)

    return {
        code = payload.code or Config.Heist.PoliceAlerts.Code or '10-60',
        title = payload.title or Config.Heist.PoliceAlerts.Title or 'Vehicle Theft Alarm',
        message = payload.message or payload.description or 'A vehicle theft alarm was reported by a witness.',
        coords = coords,
        plate = payload.plate,
        vehicle = payload.vehicle,
        heistType = payload.heistType,
        source = payload.source,
        blip = payload.blip or {
            sprite = 225,
            color = 1,
            scale = 1.0,
            text = payload.title or Config.Heist.PoliceAlerts.Title or 'Vehicle Theft Alarm',
            time = 60
        }
    }
end

local function NotifyOnlinePolice(alert)
    local jobs = Config.Heist and Config.Heist.Police and Config.Heist.Police.Jobs or { 'police' }
    local sent = 0

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local job = src and Bridge.GetPlayerJob(src)
        if job then
            for _, jobName in ipairs(jobs) do
                if job.name == jobName and job.onduty ~= false then
                    Notify(src, alert.title, alert.message, 'warning')
                    TriggerClientEvent('partay_keys:client:PoliceAlertBlip', src, alert.coords, alert.blip)
                    sent = sent + 1
                    break
                end
            end
        end
    end

    return sent > 0
end

local function TryCustomDispatch(alert)
    local handler = GetDispatchConfig().CustomHandler
    if type(handler) ~= 'function' then return false end

    local ok, handled = pcall(handler, alert)
    if not ok then
        print(('^5[ParTay Keys Debug]^1 ERR_DISPATCH_CUSTOM - %s^0'):format(tostring(handled)))
        return false
    end

    return handled == true
end

local function TryProviderDispatch(provider, alert)
    local coords = alert.coords or vector3(0.0, 0.0, 0.0)

    if provider == 'custom' then
        return TryCustomDispatch(alert)
    elseif provider == 'cd' and IsResourceStarted('cd_dispatch') then
        TriggerClientEvent('cd_dispatch:AddNotification', -1, {
            job_table = Config.Heist.Police.Jobs or { 'police' },
            coords = coords,
            title = alert.code .. ' - ' .. alert.title,
            message = alert.message,
            flash = 0,
            unique_id = tostring(math.random(100000, 999999)),
            sound = 1,
            blip = {
                sprite = alert.blip.sprite or 225,
                scale = alert.blip.scale or 1.0,
                colour = alert.blip.color or 1,
                flashes = false,
                text = alert.blip.text or alert.title,
                time = alert.blip.time or 60,
                radius = 0
            }
        })
        return true
    elseif provider == 'ps' and IsResourceStarted('ps-dispatch') then
        local psPayload = {
            message = alert.message,
            codeName = 'vehicle_theft_alarm',
            code = alert.code,
            icon = 'fas fa-car-burst',
            priority = 2,
            coords = coords,
            street = alert.street or '',
            jobs = Config.Heist.Police.Jobs or { 'police' },
            alert = { displayCode = alert.code, description = alert.title }
        }

        local ok = pcall(function() exports['ps-dispatch']:CustomAlert(psPayload) end)
        if ok then return true end
        TriggerClientEvent('ps-dispatch:client:notify', -1, psPayload)
        return true
    elseif provider == 'lb-tablet' and IsResourceStarted('lb-tablet') then
        local ok = pcall(function()
            exports['lb-tablet']:AddDispatch({
                priority = 'medium',
                code = alert.code,
                title = alert.title,
                description = alert.message,
                location = { x = coords.x, y = coords.y, z = coords.z },
                time = 60,
                job = Config.Heist.Police.Jobs or { 'police' }
            })
        end)
        if ok then return true end
    elseif provider == 'qbx' and IsResourceStarted('qbx_police') then
        TriggerEvent('police:server:policeAlert', alert.message, nil, alert.source)
        return true
    elseif provider == 'qb' or provider == 'esx' then
        return NotifyOnlinePolice(alert)
    end

    return false
end

function PartayKeys_SendPoliceAlert(payload)
    local dispatchConfig = GetDispatchConfig()
    if dispatchConfig.Provider == 'disabled' then return false end

    local alert = BuildAlertPayload(payload)
    local cooldown = tonumber(payload and payload.cooldown) or tonumber(Config.Heist and Config.Heist.PoliceAlerts and Config.Heist.PoliceAlerts.Cooldown) or 60
    local key = payload and payload.cooldownKey or (alert.plate and (alert.code .. ':' .. alert.plate) or alert.code)
    local now = os.time()
    if key and lastAlertByKey[key] and now - lastAlertByKey[key] < cooldown then
        DebugDispatch(('cooldown key=%s remaining=%s'):format(tostring(key), tostring(cooldown - (now - lastAlertByKey[key]))))
        return false
    end
    if key then lastAlertByKey[key] = now end

    if TryCustomDispatch(alert) then
        DebugDispatch('handled by custom handler')
        return true
    end

    local provider = ResolveDispatchProvider()
    local handled = TryProviderDispatch(provider, alert)
    DebugDispatch(('provider=%s handled=%s'):format(tostring(provider), tostring(handled)))

    if handled then return true end
    return NotifyOnlinePolice(alert)
end

SendPoliceAlert = PartayKeys_SendPoliceAlert

exports('SendPoliceAlert', PartayKeys_SendPoliceAlert)
