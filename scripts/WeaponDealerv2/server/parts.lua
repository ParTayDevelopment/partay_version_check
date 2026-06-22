Server = Server or {}
Server.PartsOrdering = Server.PartsOrdering or {}

local function ensurePartsTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `weapon_part_orders` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `store_id` VARCHAR(64) NOT NULL,
            `employee_identifier` VARCHAR(64) NOT NULL,
            `employee_name` VARCHAR(128) NOT NULL,
            `payment_source` VARCHAR(16) NOT NULL,
            `total` INT UNSIGNED NOT NULL DEFAULT 0,
            `items` JSON NOT NULL,
            `status` ENUM('pending_delivery', 'delivered', 'cancelled') NOT NULL DEFAULT 'pending_delivery',
            `delivery_at` DATETIME NOT NULL,
            `delivered_at` DATETIME NULL DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_weapon_part_orders_store_status` (`store_id`, `status`),
            KEY `idx_weapon_part_orders_delivery` (`status`, `delivery_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

CreateThread(function()
    if Config.PartsOrdering and Config.PartsOrdering.Enabled ~= false then
        ensurePartsTable()
    end
end)

local function getStoreAssembly(storeId)
    local store = Server.GetStore(storeId)
    if not store or not store.assembly or store.assembly.Enabled == false then return nil, nil end
    return store, store.assembly
end

local function getDeliveryAt()
    return os.date('%Y-%m-%d %H:%M:%S', os.time() + (tonumber(Config.PartsOrdering.DeliverySeconds or 1800) or 1800))
end

local function getDeliveryTimestamp(value)
    if type(value) == 'number' then return math.floor(value / 1000) end
    if type(value) ~= 'string' then return nil end

    local year, month, day, hour, min, sec = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d):(%d%d):(%d%d)')
    if not year then return nil end

    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
    })
end

local function hasGrade(source, grade)
    local job = Bridge.Framework.GetJob(source)
    return job and job.name == Config.Job.Name and tonumber(job.grade or 0) >= tonumber(grade or 0)
end

local function canUsePartsOrdering(source, store, assembly)
    if not Config.PartsOrdering or Config.PartsOrdering.Enabled == false then
        return false, 'not_authorized'
    end

    if not hasGrade(source, Config.PartsOrdering.Grade) then
        return false, 'not_authorized'
    end

    if not Server.IsNear(source, store.salesDesk.coords, Config.Security.MaxInteractDistance + 1.5) and not Server.IsNear(source, assembly.coords, Config.Security.MaxInteractDistance + 1.5) then
        return false, 'not_at_sales_desk'
    end

    return true
end

local function canUsePaymentSource(source, paymentSource)
    local cfg = Config.PartsOrdering
    if paymentSource == 'society' then
        return cfg.PaymentSources.society == true and hasGrade(source, cfg.SocietyGrade or cfg.Grade)
    end

    if paymentSource == 'bank' or paymentSource == 'cash' then
        return cfg.PaymentSources[paymentSource] == true and hasGrade(source, cfg.PersonalGrade or cfg.Grade)
    end

    return false
end

local function packageOptions(cfg)
    local options = {}

    if type(cfg.packageOptions) == 'table' and #cfg.packageOptions > 0 then
        for _, option in ipairs(cfg.packageOptions) do
            local units = math.floor(tonumber(option.units or 0) or 0)
            local price = math.floor(tonumber(option.price or 0) or 0)

            if units > 0 and price > 0 then
                options[#options + 1] = {
                    units = units,
                    price = price,
                    label = option.label or ('%s Unit%s'):format(units, units == 1 and '' or 's')
                }
            end
        end
    end

    if #options == 0 then
        local defaultUnits = math.max(1, math.floor(tonumber(cfg.pack or 5) or 5))
        local defaultPrice = math.max(0, math.floor(tonumber(cfg.price or 0) or 0))
        local unitPrice = math.ceil(defaultPrice / defaultUnits)
        local seen = {}

        for _, units in ipairs({ 1, 3, 5 }) do
            if not seen[units] then
                local price = units == defaultUnits and defaultPrice or math.ceil(unitPrice * units)
                options[#options + 1] = {
                    units = units,
                    price = price,
                    label = ('%s Unit%s'):format(units, units == 1 and '' or 's')
                }
                seen[units] = true
            end
        end
    end

    table.sort(options, function(left, right)
        return left.units < right.units
    end)

    return options
end

local function resolvePackageOption(cfg, requestedUnits)
    local options = packageOptions(cfg)
    local units = math.floor(tonumber(requestedUnits or 0) or 0)

    for _, option in ipairs(options) do
        if option.units == units then
            return option
        end
    end

    return options[#options]
end

local function smallestOptionForCount(cfg, count)
    local options = packageOptions(cfg)
    count = math.max(1, math.floor(tonumber(count or 1) or 1))

    for _, option in ipairs(options) do
        if option.units >= count then
            return option
        end
    end

    return options[#options]
end

local function normalizeCart(cart)
    if type(cart) ~= 'table' then return {}, 0 end

    local catalog = Config.PartsOrdering.Catalog or {}
    local prepared = {}
    local seen = {}
    local total = 0

    for _, entry in ipairs(cart) do
        if type(entry) == 'table' and type(entry.item) == 'string' and not seen[entry.item] then
            local cfg = catalog[entry.item]
            local packages = math.floor(tonumber(entry.packages or 0) or 0)
            packages = math.min(packages, tonumber(Config.PartsOrdering.MaxPackagesPerItem or 10) or 10)

            if cfg and cfg.enabled ~= false and packages > 0 then
                local option = resolvePackageOption(cfg, entry.packageUnits or entry.pack)
                if option then
                    local pack = tonumber(option.units or 1) or 1
                    local price = tonumber(option.price or 0) or 0

                    prepared[#prepared + 1] = {
                        item = entry.item,
                        label = cfg.label or entry.item,
                        packages = packages,
                        count = pack * packages,
                        pack = pack,
                        price = price * packages
                    }

                    total = total + (price * packages)
                    seen[entry.item] = true
                end
            end
        end

        if #prepared >= (tonumber(Config.PartsOrdering.MaxCartItems or 20) or 20) then
            break
        end
    end

    return prepared, total
end

local function hydrateOrders(rows)
    local now = os.time()

    for _, order in ipairs(rows or {}) do
        local timestamp = getDeliveryTimestamp(order.delivery_at)
        order.remaining_seconds = timestamp and math.max(timestamp - now, 0) or 0

        if type(order.items) == 'string' then
            local ok, decoded = pcall(json.decode, order.items)
            order.items = ok and decoded or {}
        end
    end

    return rows or {}
end

local function getCatalog()
    local catalog = {}

    for item, cfg in pairs(Config.PartsOrdering.Catalog or {}) do
        if cfg.enabled ~= false then
            catalog[#catalog + 1] = {
                item = item,
                label = cfg.label or item,
                price = cfg.price or 0,
                pack = cfg.pack or 1,
                packageOptions = packageOptions(cfg),
                image = cfg.image or Config.PartsOrdering.DefaultImage or 'WEAPON_PISTOL.png'
            }
        end
    end

    table.sort(catalog, function(left, right)
        return left.label < right.label
    end)

    return catalog
end

local function getWeaponKits()
    local kits = {}
    local catalog = Config.PartsOrdering.Catalog or {}
    local recipes = Config.Assembly and Config.Assembly.Recipes or {}

    for weaponItem, recipe in pairs(recipes) do
        local weapon = Server.GetWeapon(weaponItem)
        if weapon and weapon.enabled ~= false and type(recipe) == 'table' and #recipe > 0 then
            local parts = {}
            local total = 0

            for _, recipePart in ipairs(recipe) do
                local partCfg = catalog[recipePart.item]
                if partCfg and partCfg.enabled ~= false then
                    local count = tonumber(recipePart.count or 1) or 1
                    local option = smallestOptionForCount(partCfg, count)
                    if option then
                        local pack = tonumber(option.units or 1) or 1
                        local packages = math.max(1, math.ceil(count / pack))
                        local price = tonumber(option.price or 0) or 0

                        parts[#parts + 1] = {
                            item = recipePart.item,
                            label = recipePart.label or partCfg.label or recipePart.item,
                            count = count,
                            pack = pack,
                            packageUnits = pack,
                            packages = packages,
                            price = price * packages
                        }

                        total = total + (price * packages)
                    end
                end
            end

            if #parts > 0 then
                kits[#kits + 1] = {
                    item = weapon.item,
                    label = weapon.label or weapon.item,
                    image = weapon.image or Config.PartsOrdering.DefaultImage or 'WEAPON_PISTOL.png',
                    category = weapon.category or weapon.legalClass or 'weapon',
                    parts = parts,
                    total = total
                }
            end
        end
    end

    table.sort(kits, function(left, right)
        return left.label < right.label
    end)

    return kits
end

local function charge(source, paymentSource, total)
    if paymentSource == 'society' then
        if not Config.Payment.Society.Enabled or GetResourceState(Config.Payment.Society.Resource) ~= 'started' then
            return false
        end

        return Bridge.Banking.RemoveSociety(total)
    end

    if paymentSource == 'bank' or paymentSource == 'cash' then
        return Bridge.Framework.RemoveMoney(source, paymentSource, total, 'weapondealer-parts-order')
    end

    return false
end

local function refund(source, paymentSource, total)
    if paymentSource == 'society' then
        Bridge.Banking.DepositSociety(total)
        return
    end

    if paymentSource == 'bank' or paymentSource == 'cash' then
        Bridge.Framework.AddMoney(source, paymentSource, total, 'weapondealer-parts-order-refund')
    end
end

local function notifyOnDutyEmployees(key, notifyType, vars)
    for _, playerId in ipairs(GetPlayers()) do
        local player = tonumber(playerId)
        local job = Bridge.Framework.GetJob(player)

        if job and job.name == Config.Job.Name and job.duty == true then
            Server.Notify(player, key, notifyType, vars)
        end
    end
end

local function deliverOrder(order)
    local store, assembly = getStoreAssembly(order.store_id)
    if not store or not assembly or not assembly.stash then return false end

    local items = order.items
    if type(items) == 'string' then
        local ok, decoded = pcall(json.decode, items)
        items = ok and decoded or {}
    end

    local delivered = {}
    for _, item in ipairs(items or {}) do
        local count = tonumber(item.count or 0) or 0
        if item.item and count > 0 then
            local added = Bridge.Inventory.AddToInventory(assembly.stash, item.item, count, {
                legal_stock_order = true,
                stock_order_id = order.id,
                store = order.store_id,
                delivered_at = os.time()
            })

            if not added then return false end
            delivered[#delivered + 1] = item
        end
    end

    MySQL.update.await('UPDATE weapon_part_orders SET status = "delivered", delivered_at = NOW() WHERE id = ?', { order.id })
    Server.Logs.Write('parts_order_delivered', 'Weapon dealer parts stock order delivered to stash.', {
        order = order.id,
        store = order.store_id,
        stash = assembly.stash,
        items = delivered
    })

    return true
end

lib.callback.register('qbx_weapondealer:server:getPartsOrderingData', function(source, storeId)
    local store, assembly = getStoreAssembly(storeId)
    if not store then return { allowed = false } end

    local allowed = canUsePartsOrdering(source, store, assembly)
    if not allowed then return { allowed = false } end

    local orders = MySQL.query.await([[
        SELECT id, employee_name, payment_source, total, items, status, delivery_at, created_at
        FROM weapon_part_orders
        WHERE store_id = ? AND status IN ("pending_delivery", "delivered")
        ORDER BY created_at DESC
        LIMIT 20
    ]], { storeId }) or {}

    return {
        allowed = true,
        catalog = getCatalog(),
        weaponKits = getWeaponKits(),
        orders = hydrateOrders(orders),
        paymentSources = Config.PartsOrdering.PaymentSources,
        balances = {
            society = Bridge.Banking.GetSocietyBalance(),
            bank = Bridge.Framework.GetMoney(source, 'bank'),
            cash = Bridge.Framework.GetMoney(source, 'cash')
        }
    }
end)

lib.callback.register('qbx_weapondealer:server:createPartsOrder', function(source, storeId, cart, paymentSource)
    if not Server.CheckCooldown(source, 'parts_order') then return false end

    local store, assembly = getStoreAssembly(storeId)
    if not store then return false end

    local allowed, reason = canUsePartsOrdering(source, store, assembly)
    if not allowed then
        Server.Notify(source, reason, 'error')
        return false
    end

    if not canUsePaymentSource(source, paymentSource) then
        Server.Notify(source, 'not_authorized', 'error')
        return false
    end

    local items, total = normalizeCart(cart)
    if #items == 0 or total <= 0 then
        Server.Notify(source, 'parts_order_invalid', 'error')
        return false
    end

    if paymentSource ~= 'society' and Bridge.Framework.GetMoney(source, paymentSource) < total then
        Server.Notify(source, 'insufficient_funds', 'error')
        return false
    end

    if not charge(source, paymentSource, total) then
        Server.Notify(source, 'insufficient_funds', 'error')
        return false
    end

    local deliveryAt = getDeliveryAt()
    local orderId = MySQL.insert.await([[
        INSERT INTO weapon_part_orders
        (store_id, employee_identifier, employee_name, payment_source, total, items, status, delivery_at)
        VALUES (?, ?, ?, ?, ?, ?, "pending_delivery", ?)
    ]], {
        storeId,
        Bridge.Framework.GetIdentifier(source),
        Bridge.Framework.GetName(source),
        paymentSource,
        total,
        json.encode(items),
        deliveryAt
    })

    if not orderId then
        refund(source, paymentSource, total)
        Server.Notify(source, 'parts_order_failed', 'error')
        return false
    end

    Server.Notify(source, 'parts_order_created', 'success', { order = orderId, total = total })
    if paymentSource == 'bank' or paymentSource == 'cash' then
        Bridge.Banking.AddTransaction(source, 'withdrawal', total, paymentSource, 'Weapon Parts Stock Order', ('Parts stock order #%s for %s'):format(orderId, store.label))
    end

    Server.Logs.Write('parts_order_created', 'Weapon dealer parts stock order submitted.', {
        order = orderId,
        store = storeId,
        employee = Bridge.Framework.GetIdentifier(source),
        paymentSource = paymentSource,
        total = total,
        items = items,
        deliveryAt = deliveryAt,
        destinationStash = assembly.stash
    })

    return true
end)

lib.callback.register('qbx_weapondealer:server:expeditePartsOrder', function(source, storeId, orderId)
    if not Server.CheckCooldown(source, 'parts_expedite') then return false end

    local cfg = Config.PartsOrdering and Config.PartsOrdering.ExpeditedShipping or {}
    if cfg.Enabled == false then return false end

    local store, assembly = getStoreAssembly(storeId)
    if not store then return false end

    local allowed, reason = canUsePartsOrdering(source, store, assembly)
    if not allowed then
        Server.Notify(source, reason, 'error')
        return false
    end

    orderId = tonumber(orderId)
    if not orderId then return false end

    local order = MySQL.single.await('SELECT * FROM weapon_part_orders WHERE id = ? AND store_id = ? AND status = "pending_delivery"', { orderId, storeId })
    if not order then return false end

    local paymentSource = order.payment_source
    if not canUsePaymentSource(source, paymentSource) then
        Server.Notify(source, 'not_authorized', 'error')
        return false
    end

    local remaining = getDeliveryTimestamp(order.delivery_at)
    local targetSeconds = tonumber(cfg.RemainingSeconds or 30) or 30
    if remaining and remaining - os.time() <= targetSeconds then
        Server.Notify(source, 'parts_order_expedited', 'inform', { order = orderId })
        return true
    end

    local percent = tonumber(cfg.Percent or 7) or 7
    local price = math.max(1, math.floor((tonumber(order.total or 0) or 0) * (percent / 100)))
    if price > 0 and not charge(source, paymentSource, price) then
        Server.Notify(source, 'insufficient_funds', 'error')
        return false
    end

    local deliveryAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + targetSeconds)
    local updated = MySQL.update.await([[
        UPDATE weapon_part_orders
        SET delivery_at = ?
        WHERE id = ? AND store_id = ? AND status = "pending_delivery" AND delivery_at > ?
    ]], {
        deliveryAt,
        orderId,
        storeId,
        deliveryAt
    })

    if not updated or updated < 1 then
        if price > 0 then refund(source, paymentSource, price) end
        return false
    end

    if price > 0 and (paymentSource == 'bank' or paymentSource == 'cash') then
        Bridge.Banking.AddTransaction(source, 'withdrawal', price, paymentSource, 'Expedited Parts Shipping', ('Expedited shipping for stock order #%s'):format(orderId))
    end

    Server.Notify(source, 'parts_order_expedited', 'success', { order = orderId })
    Server.Logs.Write('parts_order_expedited', 'Parts stock order expedited.', {
        order = orderId,
        store = storeId,
        employee = Bridge.Framework.GetIdentifier(source),
        paymentSource = paymentSource,
        price = price,
        deliveryAt = deliveryAt
    })

    return true
end)

CreateThread(function()
    while true do
        Wait(10000)

        if Config.PartsOrdering and Config.PartsOrdering.Enabled ~= false then
            local rows = MySQL.query.await('SELECT * FROM weapon_part_orders WHERE status = "pending_delivery" AND delivery_at <= NOW()') or {}
            for _, order in ipairs(rows) do
                local ok = deliverOrder(order)
                if ok then
                    notifyOnDutyEmployees('parts_order_arrived', 'success', { order = order.id })
                end
            end
        end
    end
end)
