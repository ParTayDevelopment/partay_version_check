Bridge = Bridge or {}
Bridge.Tablet = {}

function Bridge.Tablet.RegisterWeapon(serial, data, seller)
    if not Config.Tablet.Enabled or GetResourceState(Config.Tablet.Resource) ~= 'started' then
        return nil
    end

    local registrant = seller.name
    if Config.Tablet.Registrant == 'sellerIdentifier' then
        registrant = seller.identifier
    elseif Config.Tablet.Registrant == 'storeName' then
        registrant = data.store
    end

    local ok, id = pcall(function()
        return exports[Config.Tablet.Resource]:RegisterMDTWeapon(Config.Tablet.MDT, serial, {
            owner = data.owner,
            weaponName = data.weaponName
        }, registrant)
    end)

    if not ok then
        WD.Debug('LB Tablet weapon registration failed', id)
        return nil
    end

    return id
end

function Bridge.Tablet.Notify(source, title, content)
    if not Config.Tablet.Enabled or GetResourceState(Config.Tablet.Resource) ~= 'started' then return end

    pcall(function()
        exports[Config.Tablet.Resource]:SendNotification({
            source = source,
            app = 'mdt',
            title = title,
            content = content,
            dontSaveToDatabase = false
        })
    end)
end
