-- [[ Framework Agnostic Notification Bridge ]] --

local warnedNotificationProviders = {}

local function NormalizeNotificationType()
    local configured = Config.Notifications and Config.Notifications.Provider or Config.NotificationType or 'ox_lib'
    local notifyType = tostring(configured):lower()
    notifyType = notifyType:gsub('%-', '_')

    if notifyType == 'qb' or notifyType == 'qbcore' then return 'qb_core' end
    if notifyType == 'qbx' or notifyType == 'qbxcore' then return 'qbx_core' end
    if notifyType == 'okok' then return 'okoknotify' end
    if notifyType == 'mythic_notify' then return 'mythic' end
    if notifyType == 'wasabi_notify' then return 'wasabi' end

    return notifyType
end

local function WarnNotificationProvider(message)
    if not Config or not Config.DebugMode or warnedNotificationProviders[message] then return end
    warnedNotificationProviders[message] = true
    print(('^5[ParTay Keys Debug]^3 Notification Warning: %s^0'):format(message))
end

local function SafeCall(fn)
    local ok, result = pcall(fn)
    return ok, result
end

local function OxNotifyClient(title, description, notifyType, duration)
    if lib and lib.notify then
        local settings = Config.Notifications or {}
        lib.notify({
            title = title,
            description = description,
            type = notifyType,
            duration = duration or settings.Duration,
            position = settings.Position
        })
        return true
    end
    return false
end

local function NotifyClient(title, description, notifyType, duration)
    local provider = NormalizeNotificationType()

    if provider == 'ox_lib' then
        if OxNotifyClient(title, description, notifyType, duration) then return end
    elseif provider == 'esx' then
        if SafeCall(function() ESX.ShowNotification(description) end) then return end
    elseif provider == 'qb_core' or provider == 'qbx_core' then
        if SafeCall(function() QBCore.Functions.Notify(description, notifyType, duration) end) then return end
        if SafeCall(function() TriggerEvent('QBCore:Notify', description, notifyType, duration) end) then return end
    elseif provider == 'okoknotify' then
        if SafeCall(function() exports['okokNotify']:Alert(title, description, duration or 3000, notifyType) end) then return end
    elseif provider == 'mythic' then
        if SafeCall(function() exports['mythic_notify']:DoHudText(notifyType or 'inform', description) end) then return end
    elseif provider == 'wasabi' then
        if SafeCall(function() exports.wasabi_notify:notify(title, description, duration or 3000, notifyType or 'info') end) then return end
    elseif provider == 'custom' and type(Config.CustomNotify) == 'function' then
        if SafeCall(function() Config.CustomNotify(title, description, notifyType) end) then return end
    end

    WarnNotificationProvider(('Provider "%s" failed on client. Falling back to ox_lib.'):format(provider))
    OxNotifyClient(title, description, notifyType, duration)
end

if not IsDuplicityVersion() then
    RegisterNetEvent('partay_keys:client:Notify', function(title, description, notifyType, duration)
        NotifyClient(title, description, notifyType, duration)
    end)
end

local function NotifyServer(target, title, description, notifyType, duration)
    local provider = NormalizeNotificationType()

    if provider == 'custom' and type(Config.CustomNotifyServer) == 'function' then
        local ok = SafeCall(function() Config.CustomNotifyServer(target, title, description, notifyType) end)
        if ok then return end
        WarnNotificationProvider('Custom server notification handler failed. Falling back to client notification relay.')
    end

    TriggerClientEvent('partay_keys:client:Notify', target, title, description, notifyType, duration)
end

function Notify(target, title, description, notifyType, duration)
    if IsDuplicityVersion() then
        NotifyServer(target, title, description, notifyType, duration)
        return
    end

    local clientDuration = notifyType
    notifyType = description
    description = title
    title = target
    NotifyClient(title, description, notifyType, clientDuration or duration)
end
