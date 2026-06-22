Server = Server or {}
Server.Pickups = Server.Pickups or {}

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `weapon_pickup_items` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `buyer_identifier` VARCHAR(64) NOT NULL,
            `buyer_name` VARCHAR(128) NOT NULL,
            `seller_identifier` VARCHAR(64) NOT NULL,
            `seller_name` VARCHAR(128) NOT NULL,
            `store_id` VARCHAR(64) NOT NULL,
            `item_type` VARCHAR(32) NOT NULL,
            `item_name` VARCHAR(64) NOT NULL,
            `item_label` VARCHAR(128) NOT NULL,
            `count` INT UNSIGNED NOT NULL DEFAULT 1,
            `price` INT UNSIGNED NOT NULL DEFAULT 0,
            `metadata` JSON NULL DEFAULT NULL,
            `payment_method` VARCHAR(16) NULL DEFAULT NULL,
            `status` ENUM('ready', 'picked_up', 'cancelled') NOT NULL DEFAULT 'ready',
            `ready_at` DATETIME NOT NULL,
            `picked_up_at` DATETIME NULL DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_weapon_pickup_items_buyer_status` (`buyer_identifier`, `status`),
            KEY `idx_weapon_pickup_items_store_status` (`store_id`, `status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end)

local function generateSerial()
    local year = os.date('%Y')
    local seq = MySQL.scalar.await('SELECT COALESCE(MAX(id), 0) + 1 FROM registered_weapons') or 1
    return ('LSW-%s-%05d'):format(year, seq)
end

local function decodeAttachments(value)
    if not value or value == '' then
        return {
            package = nil,
            price = 0,
            items = {}
        }
    end

    if type(value) == 'table' then
        return value
    end

    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then
        decoded.items = type(decoded.items) == 'table' and decoded.items or {}
        return decoded
    end

    return {
        package = nil,
        price = 0,
        items = {}
    }
end

local function hydrateOrders(rows)
    local now = os.time()

    for _, order in ipairs(rows or {}) do
        local readyAt = order.ready_at
        local readyTimestamp = nil

        if type(readyAt) == 'number' then
            readyTimestamp = math.floor(readyAt / 1000)
        elseif type(readyAt) == 'string' then
            local year, month, day, hour, min, sec = readyAt:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d):(%d%d):(%d%d)')
            if year then
                readyTimestamp = os.time({
                    year = tonumber(year),
                    month = tonumber(month),
                    day = tonumber(day),
                    hour = tonumber(hour),
                    min = tonumber(min),
                    sec = tonumber(sec)
                })
            end
        end

        order.ready_timestamp = readyTimestamp
        order.remaining_seconds = readyTimestamp and math.max(readyTimestamp - now, 0) or 0
    end

    return rows or {}
end

function Server.Pickups.CreateItemOrders(buyer, storeId, scan, items, paymentMethod)
    if type(items) ~= 'table' or #items == 0 then return {} end

    local orderIds = {}
    local seller = scan and scan.employee or buyer
    local sellerIdentifier = Bridge.Framework.GetIdentifier(seller)
    local sellerName = Bridge.Framework.GetName(seller)
    local buyerIdentifier = scan and scan.citizenid or Bridge.Framework.GetIdentifier(buyer)
    local buyerName = scan and scan.buyerName or Bridge.Framework.GetName(buyer)

    for _, item in ipairs(items) do
        local metadata = item.metadata or {}
        metadata.legal_purchase = true
        metadata.store = storeId
        metadata.buyer = buyerIdentifier
        metadata.seller = sellerName
        metadata.purchase_date = os.time()
        metadata.pickup_item_type = item.type

        local id = MySQL.insert.await([[
            INSERT INTO weapon_pickup_items
            (buyer_identifier, buyer_name, seller_identifier, seller_name, store_id, item_type, item_name, item_label, count, price, metadata, payment_method, status, ready_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "ready", NOW())
        ]], {
            buyerIdentifier,
            buyerName,
            sellerIdentifier,
            sellerName,
            storeId,
            item.type or 'item',
            item.item,
            item.label or item.item,
            tonumber(item.count or 1) or 1,
            tonumber(item.price or 0) or 0,
            json.encode(metadata),
            paymentMethod
        })

        orderIds[#orderIds + 1] = id
    end

    return orderIds
end

lib.callback.register('qbx_weapondealer:server:getReadyOrders', function(source, storeId)
    local store = Server.GetStore(storeId)
    if not store or not Server.IsNear(source, store.pickup.coords) then
        Server.Notify(source, 'not_at_pickup', 'error')
        return {}
    end

    local identifier = Bridge.Framework.GetIdentifier(source)
    local weaponOrders = MySQL.query.await([[
        SELECT id, weapon_label, weapon_item, price, ready_at, status, ammo_item, ammo_count, ammo_price, attachments
        FROM weapon_orders
        WHERE buyer_identifier = ? AND store_id = ? AND status IN ("pending_assembly", "approved", "ready")
        ORDER BY ready_at ASC
    ]], {
        identifier,
        storeId
    }) or {}

    for _, order in ipairs(weaponOrders) do
        order.order_type = 'weapon'
    end

    local pickupItems = MySQL.query.await([[
        SELECT id, item_label AS weapon_label, item_name AS weapon_item, item_type, count, price, ready_at, status
        FROM weapon_pickup_items
        WHERE buyer_identifier = ? AND store_id = ? AND status = "ready"
        ORDER BY ready_at ASC
    ]], {
        identifier,
        storeId
    }) or {}

    for _, order in ipairs(pickupItems) do
        order.order_type = 'item'
        order.id = ('item:%s'):format(order.id)
        order.ammo_count = tonumber(order.count or 0) or 0
    end

    for _, order in ipairs(pickupItems) do
        weaponOrders[#weaponOrders + 1] = order
    end

    return hydrateOrders(weaponOrders)
end)

lib.callback.register('qbx_weapondealer:server:pickupOrder', function(source, storeId, orderId)
    if not Server.CheckCooldown(source, 'pickup') then return false end

    local store = Server.GetStore(storeId)
    if not store or not Server.IsNear(source, store.pickup.coords) then
        Server.Notify(source, 'not_at_pickup', 'error')
        return false
    end

    local itemOrderId = type(orderId) == 'string' and orderId:match('^item:(%d+)$')
    if itemOrderId then
        local itemOrder = MySQL.single.await('SELECT * FROM weapon_pickup_items WHERE id = ?', { tonumber(itemOrderId) })
        if not itemOrder then return false end

        local identifier = Bridge.Framework.GetIdentifier(source)
        if itemOrder.buyer_identifier ~= identifier or itemOrder.store_id ~= storeId then
            Server.Notify(source, 'pickup_denied', 'error')
            Server.Logs.Blocked(source, 'pickup_item', 'pickup_denied', { order = itemOrderId })
            return false
        end

        if itemOrder.status ~= 'ready' then
            Server.Notify(source, 'pickup_not_ready', 'error')
            return false
        end

        local metadata = {}
        if itemOrder.metadata then
            local ok, decoded = pcall(json.decode, itemOrder.metadata)
            if ok and type(decoded) == 'table' then
                metadata = decoded
            end
        end

        local count = tonumber(itemOrder.count or 1) or 1
        if not Bridge.Inventory.CanCarry(source, itemOrder.item_name, count, metadata) then
            Server.Notify(source, 'pickup_carry_failed', 'error')
            return false
        end

        if not Bridge.Inventory.AddItem(source, itemOrder.item_name, count, metadata) then
            Server.Notify(source, 'pickup_carry_failed', 'error')
            return false
        end

        MySQL.update.await('UPDATE weapon_pickup_items SET status = "picked_up", picked_up_at = NOW() WHERE id = ?', { itemOrder.id })
        Server.Notify(source, 'pickup_item_complete', 'success', { item = itemOrder.item_label })
        Server.Logs.Write('pickup_item_released', 'Pickup item released to buyer.', {
            order = itemOrder.id,
            buyer = itemOrder.buyer_identifier,
            item = itemOrder.item_name,
            count = count
        })
        return true
    end

    orderId = tonumber(orderId)
    local order = MySQL.single.await('SELECT * FROM weapon_orders WHERE id = ?', { orderId })
    if not order then return false end

    local identifier = Bridge.Framework.GetIdentifier(source)
    if order.buyer_identifier ~= identifier then
        Server.Notify(source, 'pickup_denied', 'error')
        Server.Logs.Blocked(source, 'pickup', 'pickup_denied', { order = orderId })
        return false
    end

    if order.status ~= 'ready' then
        Server.Notify(source, 'pickup_not_ready', 'error')
        return false
    end

    local serial = generateSerial()
    local attachments = decodeAttachments(order.attachments)
    local attachmentLabels = {}

    for _, attachment in ipairs(attachments.items or {}) do
        attachmentLabels[#attachmentLabels + 1] = attachment.label or attachment.item
    end

    local metadata = {
        serial = serial,
        registered = true,
        owner = order.buyer_identifier,
        owner_name = order.buyer_name,
        license_id = order.license_id,
        seller = order.seller_name,
        purchase_date = os.time(),
        attachments_purchased = attachmentLabels,
        description = ('Registered to %s | Serial: %s'):format(order.buyer_name, serial)
    }

    if not Bridge.Inventory.CanCarry(source, order.weapon_item, 1, metadata) then
        Server.Notify(source, 'pickup_carry_failed', 'error')
        return false
    end

    if order.ammo_item and tonumber(order.ammo_count or 0) > 0 and not Bridge.Inventory.CanCarry(source, order.ammo_item, tonumber(order.ammo_count), nil) then
        Server.Notify(source, 'pickup_carry_failed', 'error')
        return false
    end

    for _, attachment in ipairs(attachments.items or {}) do
        if attachment.item and not Bridge.Inventory.CanCarry(source, attachment.item, 1, nil) then
            Server.Notify(source, 'pickup_carry_failed', 'error')
            return false
        end
    end

    local added = Bridge.Inventory.AddItem(source, order.weapon_item, 1, metadata)
    if not added then
        Server.Notify(source, 'pickup_carry_failed', 'error')
        return false
    end

    if order.ammo_item and tonumber(order.ammo_count or 0) > 0 then
        Bridge.Inventory.AddItem(source, order.ammo_item, tonumber(order.ammo_count), {
            purchased_with_serial = serial,
            legal_purchase = true
        })
    end

    for _, attachment in ipairs(attachments.items or {}) do
        if attachment.item then
            Bridge.Inventory.AddItem(source, attachment.item, 1, {
                purchased_with_serial = serial,
                legal_purchase = true,
                order_id = order.id,
                weapon = order.weapon_item,
                attachment_id = attachment.id,
                description = ('Purchased for serial %s'):format(serial)
            })
        end
    end

    local tabletId = Bridge.Tablet.RegisterWeapon(serial, {
        owner = order.buyer_identifier,
        weaponName = order.weapon_label,
        store = store.label
    }, {
        identifier = order.seller_identifier,
        name = order.seller_name
    })

    local registeredId = MySQL.insert.await([[
        INSERT INTO registered_weapons
        (serial, order_id, owner_identifier, owner_name, seller_identifier, seller_name, store_id, weapon_item, weapon_label, license_id, tablet_weapon_id, status, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "active", ?)
    ]], {
        serial,
        order.id,
        order.buyer_identifier,
        order.buyer_name,
        order.seller_identifier,
        order.seller_name,
        storeId,
        order.weapon_item,
        order.weapon_label,
        order.license_id,
        tabletId,
        json.encode(metadata)
    })

    MySQL.update.await('UPDATE weapon_orders SET status = "picked_up", picked_up_at = NOW(), registered_weapon_id = ? WHERE id = ?', {
        registeredId,
        order.id
    })

    Server.Notify(source, 'pickup_complete', 'success', { serial = serial })
    Server.Logs.Write('weapon_registered', 'Registered firearm released to buyer.', {
        order = order.id,
        serial = serial,
        owner = order.buyer_identifier,
        tabletWeaponId = tabletId
    })

    return true
end)
