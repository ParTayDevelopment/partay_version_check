Client = Client or {}
Client.Testing = Client.Testing or {}

local activeWeapon = nil
local activeStore = nil
local activeSlot = nil
local expiresAt = 0

local function weaponHash(item)
    return GetHashKey(item)
end

local function equipInventoryWeapon(slot, weaponItem, ammo)
    local hash = weaponHash(weaponItem)

    for attempt = 1, 10 do
        if slot then
            exports.ox_inventory:useSlot(slot, true)
        end

        Wait(300)

        local ped = cache.ped or PlayerPedId()
        if HasPedGotWeapon(ped, hash, false) then
            SetPedAmmo(ped, hash, ammo or Config.TestWeapons.Ammo)
            SetCurrentPedWeapon(ped, hash, true)
        end

        Wait(150)

        if HasPedGotWeapon(ped, hash, false) and GetSelectedPedWeapon(ped) == hash then
            return true
        end
    end

    return false
end

RegisterNetEvent('qbx_weapondealer:client:giveTestWeapon', function(storeId, weaponItem, ammo, duration, slot)
    activeWeapon = weaponItem
    activeStore = storeId
    activeSlot = slot
    expiresAt = GetGameTimer() + ((duration or Config.TestWeapons.DurationSeconds) * 1000)

    CreateThread(function()
        Wait(500)

        local equipped = equipInventoryWeapon(slot, weaponItem, ammo)

        if not equipped then
            lib.notify({
                title = 'Weapon Dealer',
                description = 'The test weapon was issued to your inventory but could not be equipped automatically. Use it from your hotbar or inventory.',
                type = 'warning',
                position = 'top'
            })
        end
    end)
end)

RegisterNetEvent('qbx_weapondealer:client:removeTestWeapon', function(weaponItem)
    local weapon = weaponItem or activeWeapon
    if not weapon then return end

    TriggerEvent('ox_inventory:disarm', true)
    RemoveWeaponFromPed(cache.ped or PlayerPedId(), weaponHash(weapon))

    activeWeapon = nil
    activeStore = nil
    activeSlot = nil
    expiresAt = 0

    lib.notify({
        title = 'Weapon Dealer',
        description = WD.Locale('test_removed'),
        type = 'warning',
        position = 'top'
    })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= WD.Resource or not activeWeapon then return end

    TriggerEvent('ox_inventory:disarm', true)
    RemoveWeaponFromPed(cache.ped or PlayerPedId(), weaponHash(activeWeapon))
end)

CreateThread(function()
    while true do
        if activeWeapon then
            local ped = cache.ped or PlayerPedId()

            if IsEntityDead(ped) then
                TriggerEvent('qbx_weapondealer:client:removeTestWeapon', activeWeapon, 'death')
                TriggerServerEvent('qbx_weapondealer:server:endTestWeapon', 'death')
            elseif GetGameTimer() >= expiresAt then
                TriggerEvent('qbx_weapondealer:client:removeTestWeapon', activeWeapon, 'timeout')
                TriggerServerEvent('qbx_weapondealer:server:endTestWeapon', 'timeout')
            elseif Config.TestWeapons.RemoveOnLeaveRange and activeStore then
                local store = nil
                for _, candidate in ipairs(Config.Stores) do
                    if candidate.id == activeStore then
                        store = candidate
                        break
                    end
                end

                if store then
                    local coords = GetEntityCoords(ped)
                    local rangeCoords = vec3(store.range.coords.x, store.range.coords.y, store.range.coords.z)
                    if #(coords - rangeCoords) > store.range.radius then
                        TriggerEvent('qbx_weapondealer:client:removeTestWeapon', activeWeapon, 'left_range')
                        TriggerServerEvent('qbx_weapondealer:server:endTestWeapon', 'left_range')
                    end
                end
            end

            Wait(1000)
        else
            Wait(1500)
        end
    end
end)
