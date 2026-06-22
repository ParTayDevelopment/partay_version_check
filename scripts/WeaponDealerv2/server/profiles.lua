Server = Server or {}
Server.Profiles = Server.Profiles or {}

function Server.Profiles.SaveFromScan(scan, idMeta, licenseMeta)
    local fullName = scan.buyerName
    local licenseStatus = licenseMeta.status or 'valid'

    MySQL.insert.await([[
        INSERT INTO weapon_customer_profiles
        (citizenid, full_name, first_name, last_name, dob, license_id, license_item, license_status, license_expiry, id_metadata, license_metadata, last_verified_by, last_store_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            full_name = VALUES(full_name),
            first_name = VALUES(first_name),
            last_name = VALUES(last_name),
            dob = VALUES(dob),
            license_id = VALUES(license_id),
            license_item = VALUES(license_item),
            license_status = VALUES(license_status),
            license_expiry = VALUES(license_expiry),
            id_metadata = VALUES(id_metadata),
            license_metadata = VALUES(license_metadata),
            last_verified_at = CURRENT_TIMESTAMP,
            last_verified_by = VALUES(last_verified_by),
            last_store_id = VALUES(last_store_id)
    ]], {
        scan.citizenid,
        fullName,
        idMeta.firstname,
        idMeta.lastname,
        idMeta.dob,
        scan.licenseId,
        Config.Documents.WeaponLicenseItem,
        licenseStatus,
        licenseMeta.expiry and tostring(licenseMeta.expiry) or nil,
        json.encode(idMeta),
        json.encode(licenseMeta),
        Bridge.Framework.GetIdentifier(scan.employee),
        scan.store
    })
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

local function markOrderCancelled(source, orderId, storeId)
    local employeeIdentifier = Bridge.Framework.GetIdentifier(source)
    local employeeName = Bridge.Framework.GetName(source)

    local ok, updated = pcall(function()
        return MySQL.update.await([[
            UPDATE weapon_orders
            SET status = "cancelled", refunded_by = ?, refunded_by_name = ?, refunded_at = NOW()
            WHERE id = ? AND store_id = ? AND status IN ("pending_assembly", "approved", "ready")
        ]], {
            employeeIdentifier,
            employeeName,
            orderId,
            storeId
        })
    end)

    if ok then return updated or 0 end

    Server.Logs.Write('order_cancel_schema_fallback', 'Order cancel audit columns missing; using status-only fallback update.', {
        order = orderId,
        store = storeId,
        employee = employeeIdentifier,
        error = tostring(updated)
    })

    return MySQL.update.await([[
        UPDATE weapon_orders
        SET status = "cancelled"
        WHERE id = ? AND store_id = ? AND status IN ("pending_assembly", "approved", "ready")
    ]], {
        orderId,
        storeId
    }) or 0
end

lib.callback.register('qbx_weapondealer:server:getCustomerProfile', function(source, storeId, buyer)
    local allowed, reason = Bridge.Framework.IsAuthorized(source, 'Scan')
    if not allowed then
        Server.Notify(source, reason, 'error')
        return false
    end

    local store = Server.GetStore(storeId)
    if not store or not Server.IsNear(source, store.salesDesk.coords) then
        Server.Notify(source, 'not_at_sales_desk', 'error')
        return false
    end

    buyer = tonumber(buyer)
    local citizenid = buyer and Bridge.Framework.GetIdentifier(buyer)
    if not citizenid then return false end

    local profile = MySQL.single.await('SELECT * FROM weapon_customer_profiles WHERE citizenid = ?', { citizenid })
    local active = hydrateOrders(MySQL.query.await('SELECT * FROM weapon_orders WHERE buyer_identifier = ? AND status IN ("pending_assembly", "approved", "ready") ORDER BY created_at DESC', { citizenid }))
    local history = hydrateOrders(MySQL.query.await([[
        SELECT o.*, r.serial
        FROM weapon_orders o
        LEFT JOIN registered_weapons r ON r.order_id = o.id
        WHERE o.buyer_identifier = ?
        ORDER BY o.created_at DESC
        LIMIT 30
    ]], { citizenid }))

    return {
        citizenid = citizenid,
        currentName = Bridge.Framework.GetName(buyer),
        profile = profile,
        activeOrders = active,
        orderHistory = history
    }
end)

lib.callback.register('qbx_weapondealer:server:getActiveOrders', function(source, storeId, buyer)
    local allowed, reason = Bridge.Framework.IsAuthorized(source, 'Scan')
    if not allowed then
        Server.Notify(source, reason, 'error')
        return {}
    end

    local store = Server.GetStore(storeId)
    if not store or not Server.IsNear(source, store.salesDesk.coords) then
        Server.Notify(source, 'not_at_sales_desk', 'error')
        return {}
    end

    buyer = tonumber(buyer)
    local citizenid = buyer and Bridge.Framework.GetIdentifier(buyer)
    if not citizenid then return {} end

    return hydrateOrders(MySQL.query.await('SELECT * FROM weapon_orders WHERE buyer_identifier = ? AND status IN ("pending_assembly", "approved", "ready") ORDER BY ready_at ASC', { citizenid }))
end)

lib.callback.register('qbx_weapondealer:server:refundActiveOrder', function(source, storeId, orderId)
    if not Server.CheckCooldown(source, 'refund_order') then return false end

    local allowed, reason = Bridge.Framework.IsAuthorized(source, 'Order')
    if not allowed then
        Server.Notify(source, reason, 'error')
        return false
    end

    local store = Server.GetStore(storeId)
    if not store or not Server.IsNear(source, store.salesDesk.coords) then
        Server.Notify(source, 'not_at_sales_desk', 'error')
        return false
    end

    orderId = tonumber(orderId)
    if not orderId then return false end

    local order = MySQL.single.await('SELECT * FROM weapon_orders WHERE id = ? AND store_id = ?', { orderId, storeId })
    if not order then return false end

    if order.status ~= 'pending_assembly' and order.status ~= 'approved' and order.status ~= 'ready' then
        Server.Notify(source, 'order_refund_not_allowed', 'error')
        return false
    end

    local buyer = Bridge.Framework.GetSourceByIdentifier(order.buyer_identifier)
    if not buyer and Bridge.Framework.SameIdentifier(Bridge.Framework.GetIdentifier(source), order.buyer_identifier) then
        buyer = source
    end

    if not buyer then
        Server.Notify(source, 'order_refund_failed', 'error')
        Server.Logs.Write('order_refund_buyer_offline', 'Order refund blocked because buyer source could not be resolved.', {
            order = orderId,
            buyer = order.buyer_identifier,
            employee = Bridge.Framework.GetIdentifier(source)
        })
        return false
    end

    local amount = tonumber(order.price or 0) or 0
    local paymentMethod = order.payment_method or Config.Payment.Account or 'bank'
    if amount > 0 and not Bridge.Banking.RemoveSociety(amount) then
        Server.Notify(source, 'order_refund_failed', 'error')
        return false
    end

    local updated = markOrderCancelled(source, orderId, storeId)
    if not updated or updated < 1 then
        if amount > 0 then Bridge.Banking.DepositSociety(amount) end
        Server.Notify(source, 'order_refund_failed', 'error')
        return false
    end

    if amount > 0 then
        if not Bridge.Framework.AddMoney(buyer, paymentMethod, amount, 'weapondealer-order-refund') then
            Bridge.Banking.DepositSociety(amount)
            Server.Notify(source, 'order_refund_failed', 'error')
            return false
        end
    end

    if Server.TradeIns and not Server.TradeIns.RestoreForOrder(buyer, orderId) then
        Server.Logs.Write('trade_in_refund_restore_failed', 'Order was refunded but the trade-in firearm could not be returned automatically.', {
            order = orderId,
            buyer = order.buyer_identifier,
            employee = Bridge.Framework.GetIdentifier(source)
        })
    end

    Server.Notify(source, 'order_refunded', 'success', { order = orderId, total = amount })
    Server.Notify(buyer, 'order_refunded', 'warning', { order = orderId, total = amount })
    Server.Logs.Write('order_refunded', 'Active firearm order refunded by employee.', {
        order = orderId,
        buyer = order.buyer_identifier,
        employee = Bridge.Framework.GetIdentifier(source),
        amount = amount,
        paymentMethod = paymentMethod
    })

    return true
end)

lib.callback.register('qbx_weapondealer:server:clearActiveOrder', function(source, storeId, orderId)
    if not Server.CheckCooldown(source, 'clear_order') then return false end

    local allowed, reason = Bridge.Framework.IsAuthorized(source, 'Order')
    if not allowed then
        Server.Notify(source, reason, 'error')
        return false
    end

    local store = Server.GetStore(storeId)
    if not store or not Server.IsNear(source, store.salesDesk.coords) then
        Server.Notify(source, 'not_at_sales_desk', 'error')
        return false
    end

    orderId = tonumber(orderId)
    if not orderId then return false end

    local order = MySQL.single.await('SELECT * FROM weapon_orders WHERE id = ? AND store_id = ?', { orderId, storeId })
    if not order then
        Server.Notify(source, 'order_clear_failed', 'error')
        return false
    end

    if order.status ~= 'pending_assembly' and order.status ~= 'approved' and order.status ~= 'ready' then
        Server.Notify(source, 'order_refund_not_allowed', 'error')
        return false
    end

    local updated = markOrderCancelled(source, orderId, storeId)

    if not updated or updated < 1 then
        Server.Notify(source, 'order_clear_failed', 'error')
        return false
    end

    local buyer = Bridge.Framework.GetSourceByIdentifier(order.buyer_identifier)
    Server.Notify(source, 'order_cleared', 'success', { order = orderId })
    if buyer then
        Server.Notify(buyer, 'order_cleared', 'warning', { order = orderId })
    end

    Server.Logs.Write('order_cleared', 'Active firearm order manually cleared by employee without refund.', {
        order = orderId,
        buyer = order.buyer_identifier,
        employee = Bridge.Framework.GetIdentifier(source),
        status = order.status,
        price = order.price
    })

    return true
end)
