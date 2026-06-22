Client = Client or {}
Client.Nui = Client.Nui or {}
Client.Nui.Opened = false

local activeStore = nil
local activeStation = nil

local function waitLabel(seconds)
    seconds = tonumber(seconds or 0) or 0
    if seconds < 60 then
        return ('%ss'):format(seconds)
    end

    local minutes = math.floor(seconds / 60)
    if minutes < 60 then
        return ('%sm'):format(minutes)
    end

    local hours = math.floor(minutes / 60)
    local rest = minutes % 60
    return rest > 0 and ('%sh %sm'):format(hours, rest) or ('%sh'):format(hours)
end

function Client.Nui.GetNearbyBuyers()
    local coords = GetEntityCoords(cache.ped)
    local nearby = lib.getNearbyPlayers(coords, Config.Security.NearbyBuyerDistance, false)
    local selfId = GetPlayerServerId(PlayerId())
    local playerIds = { selfId }

    for _, player in ipairs(nearby) do
        local serverId = GetPlayerServerId(player.id)
        if serverId ~= selfId then
            playerIds[#playerIds + 1] = serverId
        end
    end

    local labels = lib.callback.await('qbx_weapondealer:server:getPlayerLabels', false, playerIds) or {}
    local function playerLabel(serverId)
        return labels[serverId] or labels[tostring(serverId)] or {}
    end

    local selfLabel = playerLabel(selfId)
    local options = {
        {
            label = selfLabel.label or ('Player %s | You'):format(selfId),
            value = selfId,
            self = true,
            buyerName = selfLabel.name
        }
    }

    for _, player in ipairs(nearby) do
        local serverId = GetPlayerServerId(player.id)
        if serverId ~= selfId then
            local label = playerLabel(serverId)
            options[#options + 1] = {
                label = label.label or ('Player %s'):format(serverId),
                value = serverId,
                self = false,
                buyerName = label.name
            }
        end
    end

    return options
end

local function mergeBuyers(nearby, verified)
    local merged = {}
    local seen = {}
    local nearbyByValue = {}

    for _, buyer in ipairs(nearby or {}) do
        local value = tonumber(buyer.value)
        if value then
            nearbyByValue[value] = buyer
        end
    end

    for _, buyer in ipairs(verified or {}) do
        local value = tonumber(buyer.value)
        if value and not seen[value] then
            local nearbyBuyer = nearbyByValue[value]
            local label = nearbyBuyer and nearbyBuyer.label or buyer.label or ('Player ' .. value)

            seen[value] = true
            merged[#merged + 1] = {
                label = ('Verified - %s'):format(label),
                value = value,
                verified = true,
                citizenid = buyer.citizenid,
                buyerName = buyer.buyerName or nearbyBuyer and nearbyBuyer.buyerName,
                licenseId = buyer.licenseId
            }
        end
    end

    for _, buyer in ipairs(nearby or {}) do
        local value = tonumber(buyer.value)
        if value and not seen[value] then
            seen[value] = true
            merged[#merged + 1] = buyer
        end
    end

    return merged
end

function Client.Nui.GetWeapons()
    local weapons = {}

    for _, weapon in ipairs(Config.Weapons) do
        if weapon.enabled ~= false then
            local attachments = {}
            local packages = {}

            for _, attachment in ipairs(weapon.attachments or {}) do
                attachments[#attachments + 1] = {
                    id = attachment.id,
                    label = attachment.label,
                    item = attachment.item,
                    price = attachment.price or 0,
                    description = attachment.description or ''
                }
            end

            for _, package in ipairs(weapon.packages or {}) do
                packages[#packages + 1] = {
                    id = package.id,
                    label = package.label,
                    price = package.price or 0,
                    attachments = package.attachments or {}
                }
            end

            weapons[#weapons + 1] = {
                item = weapon.item,
                label = weapon.label,
                ammo = weapon.ammo or 'Unknown',
                image = weapon.image or (weapon.item .. '.png'),
                previewModel = weapon.previewModel,
                description = weapon.description or 'Licensed firearm available for regulated purchase and registration.',
                price = weapon.price,
                waitSeconds = weapon.waitSeconds,
                waitLabel = waitLabel(weapon.waitSeconds),
                attachments = attachments,
                packages = packages
            }
        end
    end

    return weapons
end

function Client.Nui.Open(store, mode)
    activeStore = store
    activeStation = nil
    Client.Nui.Opened = true
    if Client.TabletVisual and (mode == 'sales' or mode == 'order' or mode == 'assembly') then
        local terminal = mode == 'sales' and vec4(16.2932, -1103.1687, 29.8022, 247.4089) or nil
        Client.TabletVisual.Start(mode, { terminal = terminal })
    end
    SetNuiFocus(true, true)

    local orders = {}
    local assemblyOrders = {}
    local partsOrdering = { allowed = false }
    local quote = false
    local verified = {}
    if mode == 'pickup' then
        orders = lib.callback.await('qbx_weapondealer:server:getReadyOrders', false, store.id) or {}
    elseif mode == 'assembly' then
        assemblyOrders = lib.callback.await('qbx_weapondealer:server:getAssemblyOrders', false, store.id) or {}
        partsOrdering = lib.callback.await('qbx_weapondealer:server:getPartsOrderingData', false, store.id) or { allowed = false }
    elseif mode == 'sales' then
        quote = lib.callback.await('qbx_weapondealer:server:getOrderQuote', false, store.id) or false
        verified = lib.callback.await('qbx_weapondealer:server:getVerifiedCustomers', false, store.id) or {}
    end

    SendNUIMessage({
        action = 'open',
        resource = WD.Resource,
        mode = mode or 'sales',
        tab = mode == 'pickup' and 'pickup' or mode == 'assembly' and 'assembly' or 'scan',
        store = {
            id = store.id,
            label = store.label
        },
        employeeName = Client.Framework.GetName and Client.Framework.GetName() or nil,
        buyers = mergeBuyers(Client.Nui.GetNearbyBuyers(), verified),
        weapons = Client.Nui.GetWeapons(),
        orders = orders,
        assemblyOrders = assemblyOrders,
        partsOrdering = partsOrdering,
        quote = quote
    })
end

function Client.Nui.OpenOrderStation(store, station)
    activeStore = store
    activeStation = station
    Client.Nui.Opened = true
    if Client.TabletVisual then
        Client.TabletVisual.Start('order')
    end

    if Client.Preview then
        Client.Preview.SetStation(station.preview, station.id, store.id)
    end

    local quote = lib.callback.await('qbx_weapondealer:server:getBuyerOrderQuote', false, store.id, station.id) or false

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        resource = WD.Resource,
        mode = 'order',
        tab = 'order',
        store = {
            id = store.id,
            label = store.label
        },
        employeeName = quote and quote.sellerName or nil,
        station = {
            id = station.id
        },
        buyers = Client.Nui.GetNearbyBuyers(),
        weapons = Client.Nui.GetWeapons(),
        orders = {},
        quote = quote
    })
end

function Client.Nui.Close()
    Client.Nui.Opened = false
    activeStore = nil
    activeStation = nil
    if Client.TabletVisual then
        Client.TabletVisual.Stop()
    end
    if Client.Preview then
        Client.Preview.Clear()
        Client.Preview.SetStation(nil)
    end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('qbx_weapondealer:client:scanProgress', function(rows)
    SendNUIMessage({
        action = 'scanProgress',
        checks = rows
    })
end)

RegisterNUICallback('close', function(_, cb)
    Client.Nui.Close()
    cb({ ok = true })
end)

RegisterNUICallback('scanDocuments', function(data, cb)
    if not activeStore then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('qbx_weapondealer:server:scanDocuments', false, activeStore.id, tonumber(data.buyer))
    if result then
        cb(result)
    else
        cb({ ok = false })
    end
end)

RegisterNUICallback('getVerifiedCustomers', function(_, cb)
    if not activeStore then
        cb({})
        return
    end

    cb(mergeBuyers(Client.Nui.GetNearbyBuyers(), lib.callback.await('qbx_weapondealer:server:getVerifiedCustomers', false, activeStore.id) or {}))
end)

RegisterNUICallback('createOrder', function(data, cb)
    if not activeStore then
        cb({ ok = false })
        return
    end

    local result
    if activeStation then
        result = lib.callback.await('qbx_weapondealer:server:createBuyerOrder', false, activeStore.id, activeStation.id, data.cart, data.paymentMethod, data.tradeIn)
    else
        result = lib.callback.await('qbx_weapondealer:server:createOrder', false, activeStore.id, tonumber(data.buyer), data.cart, data.paymentMethod, data.tradeIn)
    end
    cb({ ok = result ~= false, order = result })
end)

RegisterNUICallback('purchaseAccessories', function(data, cb)
    if not activeStore or not activeStation then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('qbx_weapondealer:server:purchaseAccessories', false, activeStore.id, activeStation.id, data.items, data.paymentMethod)
    cb({ ok = result == true })
end)

RegisterNUICallback('purchaseMelee', function(data, cb)
    if not activeStore or not activeStation then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('qbx_weapondealer:server:purchaseMelee', false, activeStore.id, activeStation.id, data.items, data.paymentMethod, data.tradeIn)
    cb({ ok = result == true })
end)

RegisterNUICallback('getOrderQuote', function(_, cb)
    if not activeStore then
        cb(false)
        return
    end

    if activeStation then
        cb(lib.callback.await('qbx_weapondealer:server:getBuyerOrderQuote', false, activeStore.id, activeStation.id) or false)
    else
        cb(lib.callback.await('qbx_weapondealer:server:getOrderQuote', false, activeStore.id) or false)
    end
end)

RegisterNUICallback('previewWeapon', function(data, cb)
    if Client.Preview then
        Client.Preview.Show(data.model)
    end

    cb({ ok = true })
end)

RegisterNUICallback('getReadyOrders', function(_, cb)
    if not activeStore then
        cb({})
        return
    end

    cb(lib.callback.await('qbx_weapondealer:server:getReadyOrders', false, activeStore.id) or {})
end)

RegisterNUICallback('getAssemblyOrders', function(_, cb)
    if not activeStore then
        cb({})
        return
    end

    cb(lib.callback.await('qbx_weapondealer:server:getAssemblyOrders', false, activeStore.id) or {})
end)

RegisterNUICallback('getPartsOrderingData', function(_, cb)
    if not activeStore then
        cb({ allowed = false })
        return
    end

    cb(lib.callback.await('qbx_weapondealer:server:getPartsOrderingData', false, activeStore.id) or { allowed = false })
end)

RegisterNUICallback('createPartsOrder', function(data, cb)
    if not activeStore then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('qbx_weapondealer:server:createPartsOrder', false, activeStore.id, data.cart or {}, data.paymentSource)
    cb({ ok = result == true })
end)

RegisterNUICallback('expeditePartsOrder', function(data, cb)
    if not activeStore then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('qbx_weapondealer:server:expeditePartsOrder', false, activeStore.id, tonumber(data.orderId))
    cb({ ok = result == true })
end)

RegisterNUICallback('assembleOrder', function(data, cb)
    if not activeStore then
        cb({ ok = false })
        return
    end

    if Client.AssemblyCraft then
        Client.AssemblyCraft.Start()
    end

    local result = lib.callback.await('qbx_weapondealer:server:assembleOrder', false, activeStore.id, tonumber(data.orderId))

    if Client.AssemblyCraft then
        Client.AssemblyCraft.Stop()
    end

    cb({ ok = result == true })
end)

RegisterNUICallback('getActiveOrders', function(data, cb)
    if not activeStore then
        cb({})
        return
    end

    cb(lib.callback.await('qbx_weapondealer:server:getActiveOrders', false, activeStore.id, tonumber(data.buyer)) or {})
end)

RegisterNUICallback('refundActiveOrder', function(data, cb)
    if not activeStore then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('qbx_weapondealer:server:refundActiveOrder', false, activeStore.id, tonumber(data.orderId))
    cb({ ok = result == true })
end)

RegisterNUICallback('clearActiveOrder', function(data, cb)
    if not activeStore then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('qbx_weapondealer:server:clearActiveOrder', false, activeStore.id, tonumber(data.orderId))
    cb({ ok = result == true })
end)

RegisterNUICallback('getCustomerProfile', function(data, cb)
    if not activeStore then
        cb(false)
        return
    end

    cb(lib.callback.await('qbx_weapondealer:server:getCustomerProfile', false, activeStore.id, tonumber(data.buyer)) or false)
end)

RegisterNUICallback('pickupOrder', function(data, cb)
    if not activeStore then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('qbx_weapondealer:server:pickupOrder', false, activeStore.id, data.orderId)
    if result == true and Client.PickupPed then
        Client.PickupPed.PlayExchange()
    end
    cb({ ok = result == true })
end)

RegisterNUICallback('issueTestWeapon', function(data, cb)
    if not activeStore then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('qbx_weapondealer:server:issueTestWeapon', false, activeStore.id, tonumber(data.buyer), data.weapon)
    cb({ ok = result == true })
end)
