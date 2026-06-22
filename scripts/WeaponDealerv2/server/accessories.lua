Server = Server or {}
Server.Accessories = Server.Accessories or {}

local function findStation(storeId, stationId)
    local store = Server.GetStore(storeId)
    if not store then return nil, nil end

    for _, station in ipairs(store.orderStations or {}) do
        if station.id == stationId then
            return store, station
        end
    end
end

local function normalizeItems(items)
    if type(items) ~= 'table' then return {} end

    local normalized = {}
    local seen = {}

    for _, entry in ipairs(items) do
        if type(entry) == 'table' and type(entry.item) == 'string' and not seen[entry.item] then
            local cfg = Config.Ammo.Packages[entry.item]
            local packages = math.floor(tonumber(entry.packages or 0) or 0)

            if (entry.type == nil or entry.type == 'ammo') and cfg and cfg.enabled ~= false and packages > 0 then
                packages = math.min(packages, tonumber(cfg.maxPackages or 0) or 0)
                if packages > 0 then
                    normalized[#normalized + 1] = {
                        type = 'ammo',
                        item = entry.item,
                        label = cfg.label or entry.item,
                        packages = packages,
                        count = packages * (tonumber(cfg.count or 0) or 0),
                        price = packages * (tonumber(cfg.price or 0) or 0)
                    }
                    seen[entry.item] = true
                end
            end
        end
    end

    return normalized
end

local function getAttachmentCatalog()
    local byItem = {}

    for _, weapon in ipairs(Config.Weapons or {}) do
        if weapon.enabled ~= false then
            for _, attachment in ipairs(weapon.attachments or {}) do
                if attachment.item then
                    local row = byItem[attachment.item]
                    if not row then
                        row = {
                            type = 'attachment',
                            item = attachment.item,
                            label = attachment.label or attachment.item,
                            price = tonumber(attachment.price or 0) or 0,
                            compatible = {}
                        }
                        byItem[attachment.item] = row
                    end

                    row.compatible[weapon.item] = weapon.label
                end
            end
        end
    end

    return byItem
end

local function hasCompatibleWeapon(citizenid, attachment)
    for weaponItem in pairs(attachment.compatible or {}) do
        local owned = MySQL.scalar.await('SELECT COUNT(*) FROM registered_weapons WHERE owner_identifier = ? AND weapon_item = ? AND status = "active"', {
            citizenid,
            weaponItem
        })

        if tonumber(owned or 0) > 0 then
            return true
        end

        local pending = MySQL.scalar.await('SELECT COUNT(*) FROM weapon_orders WHERE buyer_identifier = ? AND weapon_item = ? AND status IN ("pending_assembly", "approved", "ready")', {
            citizenid,
            weaponItem
        })

        if tonumber(pending or 0) > 0 then
            return true
        end
    end

    return false
end

local function normalizeAttachments(items, citizenid)
    if type(items) ~= 'table' then return {} end

    local catalog = getAttachmentCatalog()
    local normalized = {}
    local seen = {}

    for _, entry in ipairs(items) do
        if type(entry) == 'table' and entry.type == 'attachment' and type(entry.item) == 'string' and not seen[entry.item] then
            local cfg = catalog[entry.item]
            if cfg and hasCompatibleWeapon(citizenid, cfg) then
                normalized[#normalized + 1] = {
                    type = 'attachment',
                    item = cfg.item,
                    label = cfg.label,
                    count = 1,
                    price = cfg.price,
                    compatible = cfg.compatible
                }
                seen[entry.item] = true
            end
        end
    end

    return normalized
end

lib.callback.register('qbx_weapondealer:server:purchaseAccessories', function(source, storeId, stationId, items, paymentMethod)
    if not Server.CheckCooldown(source, 'accessories') then return false end

    if paymentMethod ~= 'bank' and paymentMethod ~= 'cash' then
        return false
    end

    local store, station = findStation(storeId, stationId)
    if not store or not station or not Server.IsNear(source, station.coords) then
        return false
    end

    local scan = Server.Scans.GetForBuyer(source, storeId)
    if not scan then
        Server.Notify(source, 'license_invalid', 'error')
        return false
    end

    local prepared = normalizeItems(items)
    local attachments = normalizeAttachments(items, scan.citizenid)
    for _, attachment in ipairs(attachments) do
        prepared[#prepared + 1] = attachment
    end

    if #prepared == 0 then
        return false
    end

    local total = 0
    for _, entry in ipairs(prepared) do
        total = total + entry.price
        if entry.count <= 0 then
            return false
        end
    end

    if total <= 0 or Bridge.Framework.GetMoney(source, paymentMethod) < total then
        Server.Notify(source, 'insufficient_funds', 'error')
        return false
    end

    if not Bridge.Framework.RemoveMoney(source, paymentMethod, total, 'weapondealer-accessories') then
        Server.Notify(source, 'insufficient_funds', 'error')
        return false
    end

    for _, entry in ipairs(prepared) do
        entry.metadata = {
            legal_accessory_purchase = true,
            accessory_type = entry.type,
            compatible_weapons = entry.compatible,
            description = ('Legal accessory pickup from %s.'):format(store.label)
        }
    end

    local inserted, result = pcall(function()
        return Server.Pickups.CreateItemOrders(source, storeId, scan, prepared, paymentMethod)
    end)

    if not inserted or not result or #result == 0 then
        Bridge.Framework.AddMoney(source, paymentMethod, total, 'weapondealer-accessory-refund')
        Server.Notify(source, 'order_failed_refunded', 'error')
        Server.Logs.Write('accessory_pickup_insert_failed', 'Accessory pickup order failed after payment; refund attempted.', {
            buyer = scan.citizenid,
            store = storeId,
            total = total,
            error = tostring(result)
        })
        return false
    end

    local commission = Bridge.Banking.PayCommission(scan.employee, total)
    Bridge.Banking.DepositSociety(math.max(total - commission, 0))
    Bridge.Banking.AddTransaction(source, 'withdrawal', total, paymentMethod, 'Legal Firearm Accessories', ('Accessory purchase at %s'):format(store.label))

    Server.Notify(source, 'accessory_order_ready', 'success', { total = total })
    if scan.employee and scan.employee ~= source then
        Server.Notify(scan.employee, 'accessory_order_ready', 'inform', { total = total })
    end

    Server.Logs.Write('accessory_purchase', 'Verified accessory purchase queued for pickup.', {
        buyer = scan.citizenid,
        seller = Bridge.Framework.GetIdentifier(scan.employee),
        store = storeId,
        total = total,
        paymentMethod = paymentMethod,
        items = prepared,
        commission = commission
    })

    return true
end)
