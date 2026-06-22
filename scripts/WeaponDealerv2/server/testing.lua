Server = Server or {}
Server.Testing = Server.Testing or {}

local sessions = {}

function Server.Testing.RemoveSession(source, reason)
    local session = sessions[source]
    if not session then return end

    sessions[source] = nil
    TriggerClientEvent('qbx_weapondealer:client:removeTestWeapon', source, session.weapon, reason)
    Bridge.Inventory.RemoveTestWeapon(source, session.weapon, session.slot)
    MySQL.update('UPDATE weapon_test_sessions SET ended_at = NOW(), end_reason = ? WHERE id = ?', { reason or 'removed', session.id })
end

lib.callback.register('qbx_weapondealer:server:issueTestWeapon', function(source, storeId, buyer, weaponItem)
    if not Server.CheckCooldown(source, 'test') then return false end

    local allowed, reason = Bridge.Framework.IsAuthorized(source, 'TestWeapon')
    if not allowed then
        Server.Notify(source, reason, 'error')
        WD.Debug('test weapon rejected: unauthorized', { source = source, reason = reason })
        return false
    end

    local store = Server.GetStore(storeId)
    if not store or not Server.IsNear(source, store.range.coords, store.range.radius) then
        Server.Notify(source, 'not_at_range', 'error')
        WD.Debug('test weapon rejected: employee not in range', { source = source, store = storeId })
        return false
    end

    buyer = tonumber(buyer)
    if not buyer or not Server.IsNear(buyer, store.range.coords, store.range.radius) then
        Server.Notify(source, 'not_at_range', 'error')
        WD.Debug('test weapon rejected: buyer not in range', { employee = source, buyer = buyer, store = storeId })
        return false
    end

    local weapon = Server.GetWeapon(weaponItem)
    if not weapon or not weapon.testable or not Config.TestWeapons.Weapons[weaponItem] then
        Server.Notify(source, 'test_not_allowed', 'error')
        WD.Debug('test weapon rejected: weapon not allowed', { weapon = weaponItem })
        return false
    end

    if sessions[buyer] then
        Server.Notify(source, 'test_active', 'error')
        WD.Debug('test weapon rejected: active session exists', { buyer = buyer, weapon = sessions[buyer].weapon })
        return false
    end

    local id = MySQL.insert.await('INSERT INTO weapon_test_sessions (buyer_identifier, employee_identifier, store_id, weapon_item, started_at) VALUES (?, ?, ?, ?, NOW())', {
        Bridge.Framework.GetIdentifier(buyer),
        Bridge.Framework.GetIdentifier(source),
        storeId,
        weaponItem
    })

    local metadata = {
        ammo = Config.TestWeapons.Ammo,
        registered = false,
        durability = 100,
        weapondealer_test = true,
        temporary_test_weapon = true,
        expires = os.time() + Config.TestWeapons.DurationSeconds,
        description = ('Supervised range test weapon. Expires in %s minutes.'):format(math.floor(Config.TestWeapons.DurationSeconds / 60))
    }

    local added, response = Bridge.Inventory.AddItem(buyer, weaponItem, 1, metadata)
    if not added then
        Server.Notify(source, 'test_not_allowed', 'error')
        WD.Debug('test weapon rejected: inventory add failed', { buyer = buyer, weapon = weaponItem, response = response })
        MySQL.update('UPDATE weapon_test_sessions SET ended_at = NOW(), end_reason = ? WHERE id = ?', { 'inventory_add_failed', id })
        return false
    end

    sessions[buyer] = {
        id = id,
        store = storeId,
        weapon = weaponItem,
        slot = response and response.slot,
        expires = os.time() + Config.TestWeapons.DurationSeconds
    }

    TriggerClientEvent('qbx_weapondealer:client:giveTestWeapon', buyer, storeId, weaponItem, Config.TestWeapons.Ammo, Config.TestWeapons.DurationSeconds, response and response.slot)
    WD.Debug('test weapon item added and equip event sent', { buyer = buyer, weapon = weaponItem, ammo = Config.TestWeapons.Ammo, slot = response and response.slot })
    Server.Notify(source, 'test_issued', 'success')
    Server.Notify(buyer, 'test_issued', 'success')

    Server.Logs.Write('test_weapon_issued', 'Supervised test weapon issued.', {
        buyer = Bridge.Framework.GetIdentifier(buyer),
        employee = Bridge.Framework.GetIdentifier(source),
        weapon = weaponItem
    })

    return true
end)

RegisterNetEvent('qbx_weapondealer:server:endTestWeapon', function(reason)
    Server.Testing.RemoveSession(source, reason or 'client_cleanup')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= WD.Resource then return end

    for source in pairs(sessions) do
        Server.Testing.RemoveSession(source, 'resource_stop')
    end
end)

CreateThread(function()
    while true do
        local now = os.time()
        for source, session in pairs(sessions) do
            if now >= session.expires then
                Server.Testing.RemoveSession(source, 'timeout')
            end
        end
        Wait(5000)
    end
end)
