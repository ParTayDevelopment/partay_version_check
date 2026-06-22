local registeredPhoneHandlers = {}

local function GetPhoneConfig()
    local integrations = Config and Config.Integrations or {}
    return integrations.Phone or {}
end

local function DebugPhone(message)
    if Config and Config.DebugMode then
        print(('^5[ParTay Keys Debug]^3 Phone: %s^0'):format(tostring(message)))
    end
end

local function ResourceStarted(resource)
    resource = tostring(resource or '')
    return resource ~= '' and GetResourceState(resource) == 'started'
end

local function FirstStartedResource(resourceConfig)
    if type(resourceConfig) == 'table' then
        for _, resource in ipairs(resourceConfig) do
            if ResourceStarted(resource) then return resource end
        end
        return resourceConfig[1]
    end

    resourceConfig = tostring(resourceConfig or '')
    if resourceConfig ~= '' then return resourceConfig end
    return nil
end

local function TryExport(resource, exportName, ...)
    if not ResourceStarted(resource) then return false end

    local ok, result = pcall(function(...)
        local resourceExports = exports[resource]
        local exportFn = resourceExports and resourceExports[exportName]
        if type(exportFn) ~= 'function' then return false end
        return exportFn(...)
    end, ...)

    if ok and result ~= false then
        DebugPhone(('export %s:%s handled message'):format(resource, exportName))
        return true
    end

    if not ok then
        DebugPhone(('export %s:%s failed: %s'):format(resource, exportName, tostring(result)))
    end

    return false
end

local function TryServerEvent(eventName, ...)
    eventName = tostring(eventName or '')
    if eventName == '' then return false end

    local ok, err = pcall(TriggerEvent, eventName, ...)
    if ok then
        DebugPhone(('server event %s fired'):format(eventName))
        return true
    end

    DebugPhone(('server event %s failed: %s'):format(eventName, tostring(err)))
    return false
end

local function TryClientEvent(targetSrc, eventName, ...)
    targetSrc = tonumber(targetSrc)
    eventName = tostring(eventName or '')
    if not targetSrc or eventName == '' or not GetPlayerName(targetSrc) then return false end

    local ok, err = pcall(TriggerClientEvent, eventName, targetSrc, ...)
    if ok then
        DebugPhone(('client event %s fired for %s'):format(eventName, targetSrc))
        return true
    end

    DebugPhone(('client event %s failed for %s: %s'):format(eventName, targetSrc, tostring(err)))
    return false
end

local function NormalizePayload(target, payload)
    payload = type(payload) == 'table' and payload or {}
    local targetSrc = tonumber(target or payload.source or payload.src)
    local citizenId = payload.citizenId or payload.citizen_id

    if targetSrc and not citizenId and Bridge and Bridge.GetCitizenID then
        citizenId = Bridge.GetCitizenID(targetSrc)
    end

    return {
        source = targetSrc,
        citizenId = citizenId,
        title = tostring(payload.title or 'Locksmith'),
        message = tostring(payload.message or payload.content or ''),
        type = tostring(payload.type or 'info'),
        category = tostring(payload.category or 'locksmith'),
        metadata = type(payload.metadata) == 'table' and payload.metadata or {}
    }
end

local function DetectPhoneProvider()
    local phone = GetPhoneConfig()
    local provider = tostring(phone.Provider or 'auto'):lower()
    if provider == 'disabled' then return 'disabled', nil end

    local providers = phone.Providers or {}
    if provider ~= 'auto' then
        local providerConfig = providers[provider] or {}
        return provider, FirstStartedResource(providerConfig.Resource)
    end

    local order = { 'lb-phone', 'npwd', 'qs-smartphone', 'gksphone' }
    for _, providerName in ipairs(order) do
        local providerConfig = providers[providerName] or {}
        local resource = FirstStartedResource(providerConfig.Resource)
        if ResourceStarted(resource) then
            return providerName, resource
        end
    end

    return 'disabled', nil
end

function PartayKeys_GetPhoneProvider()
    local provider, resource = DetectPhoneProvider()
    return provider, resource
end

local function SendLbPhone(resource, providerConfig, payload)
    local notification = {
        app = providerConfig.App or 'Mail',
        title = payload.title,
        content = payload.message
    }

    if TryExport(resource, 'SendNotification', payload.source, notification) then return true end
    if TryExport(resource, 'SendNotification', notification) then return true end

    local mail = {
        to = payload.source,
        sender = providerConfig.Sender or payload.title,
        subject = payload.title,
        message = payload.message
    }

    if TryExport(resource, 'SendMail', payload.source, mail) then return true end
    if TryExport(resource, 'SendMail', mail) then return true end

    return TryClientEvent(payload.source, 'lb-phone:client:CustomNotification', payload.title, payload.message, providerConfig.App or 'Mail')
end

local function SendNpwd(resource, providerConfig, payload)
    -- NPWD exports can reject asynchronously in some framework/player unload states.
    -- Client notification is best-effort and keeps locksmith flows independent from phone internals.
    return TryClientEvent(payload.source, 'npwd:client:sendNotification', {
        app = providerConfig.App or 'MESSAGES',
        title = payload.title,
        content = payload.message
    })
end

local function SendQsSmartphone(resource, providerConfig, payload)
    local mail = {
        sender = providerConfig.Sender or payload.title,
        subject = payload.title,
        message = payload.message,
        button = {}
    }

    if TryExport(resource, 'sendNewMail', payload.source, mail) then return true end
    if TryExport(resource, 'SendMail', payload.source, mail) then return true end
    if TryServerEvent('qs-smartphone:server:sendNewMail', payload.source, mail) then return true end

    return TryClientEvent(payload.source, 'qs-smartphone:client:notify', payload.title, payload.message, payload.type)
end

local function SendGksPhone(resource, providerConfig, payload)
    local mail = {
        sender = providerConfig.Sender or payload.title,
        image = '/html/static/img/icons/mail.png',
        subject = payload.title,
        message = payload.message
    }

    if TryExport(resource, 'SendMail', payload.source, mail) then return true end
    if TryServerEvent('gksphone:NewMail', payload.source, mail) then return true end
    if TryServerEvent('gksphone:server:sendNewMail', payload.source, mail) then return true end

    return TryClientEvent(payload.source, 'gksphone:client:notification', payload.title, payload.message, payload.type)
end

local providerSenders = {
    ['lb-phone'] = SendLbPhone,
    npwd = SendNpwd,
    ['qs-smartphone'] = SendQsSmartphone,
    gksphone = SendGksPhone
}

local function SendCustomPhone(payload, reason)
    local phone = GetPhoneConfig()
    local custom = phone.Custom or {}

    if type(custom.Handler) == 'function' then
        local ok, handled = pcall(custom.Handler, payload, reason)
        if ok and handled == true then
            DebugPhone('custom config handler handled message')
            return true
        elseif not ok then
            DebugPhone(('custom config handler failed: %s'):format(tostring(handled)))
        end
    end

    for name, handler in pairs(registeredPhoneHandlers) do
        if type(handler) == 'function' then
            local ok, handled = pcall(handler, payload, reason)
            if ok and handled == true then
                DebugPhone(('custom registered handler %s handled message'):format(name))
                return true
            elseif not ok then
                DebugPhone(('custom registered handler %s failed: %s'):format(name, tostring(handled)))
            end
        end
    end

    if custom.Event and custom.Event ~= '' then
        return TryServerEvent(custom.Event, payload)
    end

    return false
end

function PartayKeys_SendLocksmithPhoneMessage(target, payload)
    payload = NormalizePayload(target, payload)
    if payload.message == '' then return false end

    local phone = GetPhoneConfig()
    local provider, resource = DetectPhoneProvider()
    DebugPhone(('provider=%s resource=%s target=%s'):format(tostring(provider), tostring(resource), tostring(payload.source)))

    if provider == 'disabled' then
        return SendCustomPhone(payload, 'disabled')
    end

    if provider == 'custom' then
        return SendCustomPhone(payload, 'custom')
    end

    local providers = phone.Providers or {}
    local providerConfig = providers[provider] or {}
    local sender = providerSenders[provider]
    if sender and resource and ResourceStarted(resource) then
        local ok, sent = pcall(sender, resource, providerConfig, payload)
        if ok and sent == true then
            return true
        end

        if not ok then
            DebugPhone(('provider %s failed: %s'):format(tostring(provider), tostring(sent)))
        end
    end

    return SendCustomPhone(payload, 'fallback')
end

function PartayKeys_RegisterLocksmithPhoneHandler(name, handler)
    name = tostring(name or ''):gsub('^%s*(.-)%s*$', '%1')
    if name == '' or type(handler) ~= 'function' then return false end
    registeredPhoneHandlers[name] = handler
    DebugPhone(('registered custom handler %s'):format(name))
    return true
end

exports('GetPhoneProvider', PartayKeys_GetPhoneProvider)
exports('SendLocksmithPhoneMessage', PartayKeys_SendLocksmithPhoneMessage)
exports('RegisterLocksmithPhoneHandler', PartayKeys_RegisterLocksmithPhoneHandler)
