Client = Client or {}

function Client.Notify(key, notifyType, vars)
    lib.notify({
        title = 'Legal Firearm Registry',
        description = WD.Locale(key, vars),
        type = notifyType or 'inform',
        position = 'top'
    })
end

RegisterNetEvent('qbx_weapondealer:client:notify', function(message, notifyType)
    lib.notify({
        title = 'Legal Firearm Registry',
        description = message,
        type = notifyType or 'inform',
        position = 'top'
    })
end)
