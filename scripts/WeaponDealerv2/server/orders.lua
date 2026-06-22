Server = Server or {}
Server.Orders = Server.Orders or {}

local orderLocks = {}

local function getReadyAt(waitSeconds)
    return os.date('%Y-%m-%d %H:%M:%S', os.time() + waitSeconds)
end

local function activeOrderCount(citizenid)
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM weapon_orders WHERE buyer_identifier = ? AND status IN ("pending_assembly", "approved", "ready")', { citizenid })
    return tonumber(count or 0)
end

local function priorPickupCount(citizenid)
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM weapon_orders WHERE buyer_identifier = ? AND status = "picked_up"', { citizenid })
    return tonumber(count or 0)
end

local function orderLimit(citizenid)
    return priorPickupCount(citizenid) > 0 and Config.OrderLimits.ReturningMaxWeapons or Config.OrderLimits.FirstTimeMaxWeapons
end

local function buyerMeetsWeaponJobRequirement(source, weapon)
    local requirement = weapon and weapon.jobRequirement
    if not requirement or requirement.enabled == false then return true end

    local jobs = requirement.jobs or {}
    if not next(jobs) then return true end

    local job = Bridge.Framework.GetJob(source)
    if not job or not jobs[job.name] then
        return false
    end

    if requirement.requireDuty and not job.duty then
        return false
    end

    return tonumber(job.grade or 0) >= (tonumber(jobs[job.name] or 0) or 0)
end

local function normalizeCart(cart, fallbackWeapon)
    if type(cart) == 'table' and cart[1] then return cart end
    if type(fallbackWeapon) == 'string' then
        return { { weapon = fallbackWeapon, ammoPackages = 0, package = 'standard', attachments = {} } }
    end
    return {}
end

local function getPackage(weapon, packageId)
    for _, package in ipairs(weapon.packages or {}) do
        if package.id == packageId then
            return package
        end
    end

    return nil
end

local function getAttachment(weapon, attachmentId)
    for _, attachment in ipairs(weapon.attachments or {}) do
        if attachment.id == attachmentId then
            return attachment
        end
    end

    return nil
end

local function prepareAttachments(weapon, entry)
    local hasPackages = type(weapon.packages) == 'table' and #weapon.packages > 0
    local selectedPackageId = hasPackages and (type(entry.package) == 'string' and entry.package or 'standard') or ''
    local selectedPackage = getPackage(weapon, selectedPackageId)

    if not selectedPackage and selectedPackageId ~= '' then
        return false, 'invalid_attachment_package'
    end

    local attachmentRows = {}
    local included = {}
    local selected = {}
    local price = selectedPackage and tonumber(selectedPackage.price or 0) or 0

    if selectedPackage then
        for _, attachmentId in ipairs(selectedPackage.attachments or {}) do
            local attachment = getAttachment(weapon, attachmentId)
            if not attachment then
                return false, 'invalid_attachment_package'
            end

            included[attachment.id] = true
            attachmentRows[#attachmentRows + 1] = {
                id = attachment.id,
                label = attachment.label,
                item = attachment.item,
                price = 0,
                package = selectedPackage.id,
                included = true
            }
        end
    end

    if type(entry.attachments) == 'table' then
        for _, attachmentId in ipairs(entry.attachments) do
            if type(attachmentId) ~= 'string' then
                return false, 'invalid_attachment'
            end

            if not included[attachmentId] and not selected[attachmentId] then
                local attachment = getAttachment(weapon, attachmentId)
                if not attachment then
                    return false, 'invalid_attachment'
                end

                selected[attachmentId] = true
                price = price + tonumber(attachment.price or 0)
                attachmentRows[#attachmentRows + 1] = {
                    id = attachment.id,
                    label = attachment.label,
                    item = attachment.item,
                    price = tonumber(attachment.price or 0),
                    package = selectedPackage and selectedPackage.id or nil,
                    included = false
                }
            end
        end
    end

    return {
        package = selectedPackage and {
            id = selectedPackage.id,
            label = selectedPackage.label,
            price = tonumber(selectedPackage.price or 0)
        } or nil,
        price = price,
        items = attachmentRows
    }
end

local function refundBuyer(buyer, paymentMethod, amount)
    if amount <= 0 then return false end

    return Bridge.Framework.AddMoney(buyer, paymentMethod, amount, 'weapondealer-refund')
end

local function deleteInsertedOrders(orderIds)
    if not orderIds or #orderIds == 0 then return end

    pcall(function()
        MySQL.update.await(('DELETE FROM weapon_orders WHERE id IN (%s) AND status = "pending_assembly"'):format(table.concat(orderIds, ',')))
    end)
end

local function giveReceipt(buyer, store, scan, orderIds, prepared, total, paymentMethod, readyAt)
    local cfg = Config.Receipts
    if not cfg or not cfg.Enabled then return true end

    local metadata = {
        type = 'legal_firearm_order',
        order_id = orderIds[1],
        order_ids = orderIds,
        buyer = scan.citizenid,
        buyer_name = scan.buyerName,
        seller = Bridge.Framework.GetName(scan.employee),
        seller_identifier = Bridge.Framework.GetIdentifier(scan.employee),
        store = store.label,
        store_id = store.id,
        total = total,
        payment = paymentMethod,
        item_count = #prepared,
        ready_at = readyAt,
        issued_at = os.time(),
        items = {}
    }

    for index, entry in ipairs(prepared) do
        metadata.items[#metadata.items + 1] = {
            order_id = orderIds[index],
            weapon = entry.weapon.item,
            weapon_label = entry.weapon.label,
            ammo_item = entry.ammoItem,
            ammo_count = entry.ammoCount,
            attachments = entry.attachments and entry.attachments.items or {}
        }
    end

    local ok, result = pcall(function()
        return Bridge.Inventory.AddItem(buyer, cfg.Item, cfg.Count or 1, metadata)
    end)

    if ok and result then
        Server.Notify(buyer, 'receipt_issued', 'inform')
        return true
    end

    Server.Logs.Write('receipt_failed', 'Weapon order receipt could not be issued.', {
        buyer = scan.citizenid,
        item = cfg.Item,
        orders = orderIds
    })

    return false
end

local function canIssueReceipt(buyer)
    local cfg = Config.Receipts
    if not cfg or not cfg.Enabled or not cfg.Required then return true end

    local ok, result = pcall(function()
        return Bridge.Inventory.CanCarry(buyer, cfg.Item, cfg.Count or 1)
    end)

    return ok and result == true
end

local function lockOrder(citizenid)
    if orderLocks[citizenid] then
        return false
    end

    orderLocks[citizenid] = true
    return true
end

local function unlockOrder(citizenid)
    orderLocks[citizenid] = nil
end

local function createOrderFromScan(actor, storeId, buyer, scan, cart, paymentMethod, tradeIn)
    if not lockOrder(scan.citizenid) then
        Server.Notify(actor, 'order_processing', 'warning')
        Server.Notify(buyer or scan.buyer, 'order_processing', 'warning')
        return false
    end

    local ok, result = pcall(function()
        return Server.Orders.CreateLocked(actor, storeId, buyer, scan, cart, paymentMethod, tradeIn)
    end)

    unlockOrder(scan.citizenid)

    if not ok then
        Server.Notify(actor, 'order_failed', 'error')
        Server.Notify(buyer or scan.buyer, 'order_failed', 'error')
        Server.Logs.Write('order_exception', 'Weapon order creation threw an exception.', {
            buyer = scan.citizenid,
            error = tostring(result)
        })
        return false
    end

    return result
end

local function restoreTradeIn(buyer, trade)
    if not trade or not trade.item then return true end

    local ok, result = pcall(function()
        return Bridge.Inventory.AddItem(buyer, trade.item, 1, trade.metadata or {})
    end)

    return ok and result == true
end

local function allocateTradeCredit(prepared, credit)
    local remaining = tonumber(credit or 0) or 0
    if remaining <= 0 then
        for _, entry in ipairs(prepared) do
            entry.netPrice = entry.grossPrice
        end
        return
    end

    for _, entry in ipairs(prepared) do
        local discount = math.min(entry.grossPrice, remaining)
        entry.tradeCredit = discount
        entry.netPrice = entry.grossPrice - discount
        remaining = remaining - discount
    end
end

function Server.Orders.CreateLocked(actor, storeId, buyer, scan, cart, paymentMethod, tradeIn)
    local store = Server.GetStore(storeId)
    if not store then return false end

    buyer = tonumber(buyer or scan.buyer)
    if buyer ~= scan.buyer then
        Server.Notify(actor, 'buyer_mismatch', 'error')
        return false
    end

    if paymentMethod ~= 'bank' and paymentMethod ~= 'cash' then
        return false
    end

    local licenseOk, licenseReason = Bridge.License.HasWeaponLicense(buyer, scan.citizenid, Config.Documents.WeaponLicenseItem)
    if not licenseOk then
        Server.Notify(actor, licenseReason or 'license_invalid', 'error')
        return false
    end

    local items = normalizeCart(cart)
    local limit = orderLimit(scan.citizenid)
    local active = activeOrderCount(scan.citizenid)
    local remaining = math.max(limit - active, 0)

    if #items == 0 or #items > remaining then
        Server.Notify(actor, 'active_order', 'error')
        return false
    end

    local job = Bridge.Framework.GetJob(scan.employee)
    if not job then
        Server.Notify(actor, 'not_authorized', 'error')
        return false
    end

    local total = 0
    local prepared = {}
    local seen = {}
    local latestReadyAt = nil

    for _, entry in ipairs(items) do
        if type(entry) ~= 'table' or type(entry.weapon) ~= 'string' then
            return false
        end

        if seen[entry.weapon] then
            return false
        end
        seen[entry.weapon] = true

        local weapon = Server.GetWeapon(entry.weapon)
        if not weapon or weapon.enabled == false then
            Server.Notify(actor, 'invalid_weapon', 'error')
            return false
        end

        if tonumber(job.grade) < tonumber(weapon.minGrade or 0) then
            Server.Notify(actor, 'not_authorized', 'error')
            return false
        end

        if not buyerMeetsWeaponJobRequirement(buyer, weapon) then
            Server.Notify(actor, 'not_authorized', 'error')
            Server.Notify(buyer, 'not_authorized', 'error')
            return false
        end

        local ammoPackages = tonumber(entry.ammoPackages or 0) or 0
        local ammoItem = weapon.ammo
        local ammoCfg = ammoItem and Config.Ammo.Packages[ammoItem]
        local ammoCount = 0
        local ammoPrice = 0

        if ammoPackages > 0 then
            if not Config.Ammo.Enabled or not ammoCfg then
                return false
            end

            ammoPackages = math.min(math.floor(ammoPackages), ammoCfg.maxPackages or 0)
            ammoCount = ammoPackages * (ammoCfg.count or 0)
            ammoPrice = ammoPackages * (ammoCfg.price or 0)
        end

        local readyAt = getReadyAt(weapon.waitSeconds)
        latestReadyAt = 'After assembly clearance'

        local attachments, attachmentReason = prepareAttachments(weapon, entry)
        if attachments == false then
            Server.Notify(actor, attachmentReason or 'invalid_weapon', 'error')
            return false
        end

        local grossPrice = weapon.price + ammoPrice + attachments.price
        total = total + grossPrice
        prepared[#prepared + 1] = {
            weapon = weapon,
            ammoItem = ammoItem,
            ammoCount = ammoCount,
            ammoPrice = ammoPrice,
            attachments = attachments,
            readyAt = 'Pending assembly',
            clearanceReadyAt = readyAt,
            grossPrice = grossPrice,
            netPrice = grossPrice,
            tradeCredit = 0
        }
    end

    local requestedTrade = type(tradeIn) == 'table' and tradeIn.slot ~= nil
    local resolvedTrade = Server.TradeIns.Resolve(buyer, storeId, scan.citizenid, tradeIn)
    if requestedTrade and not resolvedTrade then
        Server.Notify(actor, 'trade_in_failed', 'error')
        Server.Notify(buyer, 'trade_in_failed', 'error')
        return false
    end
    local tradeCredit = 0
    if resolvedTrade then
        local maxPercent = tonumber(Config.TradeIn.MaxCreditPercent or 100) or 100
        local maxCredit = math.floor(total * (maxPercent / 100))
        tradeCredit = math.min(tonumber(resolvedTrade.value or 0) or 0, maxCredit, total)
        resolvedTrade.appliedCredit = tradeCredit
    end

    local amountDue = math.max(total - tradeCredit, 0)
    allocateTradeCredit(prepared, tradeCredit)

    if Bridge.Framework.GetMoney(buyer, paymentMethod) < amountDue then
        Server.Notify(actor, 'insufficient_funds', 'error')
        Server.Notify(buyer, 'insufficient_funds', 'error')
        return false
    end

    if not canIssueReceipt(buyer) then
        Server.Notify(actor, 'receipt_required_failed', 'error')
        Server.Notify(buyer, 'receipt_required_failed', 'error')
        return false
    end

    local orderIds = {}
    local sellerIdentifier = Bridge.Framework.GetIdentifier(scan.employee)
    local sellerName = Bridge.Framework.GetName(scan.employee)

    local paid = true
    if amountDue > 0 then
        paid = Bridge.Framework.RemoveMoney(buyer, paymentMethod, amountDue, 'weapondealer-purchase')
        if not paid then
            Server.Notify(actor, 'insufficient_funds', 'error')
            Server.Notify(buyer, 'insufficient_funds', 'error')
            return false
        end
    end

    if resolvedTrade and not Server.TradeIns.Remove(buyer, resolvedTrade) then
        if amountDue > 0 then refundBuyer(buyer, paymentMethod, amountDue) end
        Server.Notify(actor, 'trade_in_failed', 'error')
        Server.Notify(buyer, 'trade_in_failed', 'error')
        return false
    end

    local inserted, insertError = pcall(function()
        for _, entry in ipairs(prepared) do
            local weapon = entry.weapon
            local orderId = MySQL.insert.await([[
            INSERT INTO weapon_orders
            (buyer_identifier, buyer_name, seller_identifier, seller_name, store_id, weapon_item, weapon_label, price, ammo_item, ammo_count, ammo_price, attachments, license_id, payment_method, status, ready_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "pending_assembly", NOW())
            ]], {
                scan.citizenid,
                scan.buyerName,
                sellerIdentifier,
                sellerName,
                storeId,
                weapon.item,
                weapon.label,
                entry.netPrice,
                entry.ammoItem,
                entry.ammoCount,
                entry.ammoPrice,
                json.encode(entry.attachments),
                scan.licenseId,
                paymentMethod
            })

            if not orderId then
                error('insert returned nil')
            end

            orderIds[#orderIds + 1] = orderId
        end
    end)

    if not inserted then
        deleteInsertedOrders(orderIds)
        if amountDue > 0 then refundBuyer(buyer, paymentMethod, amountDue) end
        if resolvedTrade and not restoreTradeIn(buyer, resolvedTrade) then
            Server.Logs.Write('trade_in_restore_failed', 'Trade-in firearm could not be returned after failed order insert.', {
                buyer = scan.citizenid,
                item = resolvedTrade.item,
                serial = resolvedTrade.serial,
                slot = resolvedTrade.slot
            })
        end
        Server.Notify(actor, 'order_failed_refunded', 'error')
        Server.Notify(buyer, 'order_failed_refunded', 'error')
        Server.Logs.Write('order_insert_failed', 'Weapon order insert failed after payment; refund attempted.', {
            buyer = scan.citizenid,
            seller = sellerIdentifier,
            total = amountDue,
            grossTotal = total,
            tradeCredit = tradeCredit,
            paymentMethod = paymentMethod,
            error = tostring(insertError)
        })
        return false
    end

    if resolvedTrade then
        Server.TradeIns.MarkAccepted(resolvedTrade, orderIds, storeId, scan.citizenid, sellerIdentifier, sellerName)
    end

    local commission = Bridge.Banking.PayCommission(scan.employee, amountDue)
    Bridge.Banking.DepositSociety(math.max(amountDue - commission, 0))
    if amountDue > 0 then
        Bridge.Banking.AddTransaction(buyer, 'withdrawal', amountDue, paymentMethod, 'Legal Firearm Purchase', ('%s firearm order(s) at %s'):format(#prepared, store.label))
    end

    local receiptIssued = giveReceipt(buyer, store, scan, orderIds, prepared, amountDue, paymentMethod, latestReadyAt)
    if Config.Receipts and Config.Receipts.Enabled and not receiptIssued then
        Server.Notify(buyer, 'receipt_failed', 'warning')
    end

    local emailSent = Bridge.Phone.SendOrderEmail(buyer, store, scan, orderIds, prepared, amountDue, paymentMethod)

    Server.Notify(actor, 'order_created_pending_assembly', 'success', { weapon = ('%s item(s)'):format(#prepared), total = amountDue, order = table.concat(orderIds, ', ') })
    if actor ~= scan.employee then
        Server.Notify(scan.employee, 'new_order_pending_assembly', 'inform', { order = table.concat(orderIds, ', '), name = scan.buyerName })
    end
    Server.Notify(buyer, 'order_created_pending_assembly', 'success', { weapon = ('%s item(s)'):format(#prepared), total = amountDue, order = table.concat(orderIds, ', ') })
    Server.Logs.Write('order_created', 'Legal firearm order created.', {
        orders = orderIds,
        buyer = scan.citizenid,
        seller = sellerIdentifier,
        total = amountDue,
        grossTotal = total,
        tradeCredit = tradeCredit,
        tradeIn = resolvedTrade and {
            item = resolvedTrade.item,
            serial = resolvedTrade.serial,
            value = resolvedTrade.value,
            appliedCredit = resolvedTrade.appliedCredit
        } or nil,
        paymentMethod = paymentMethod,
        commission = commission,
        receiptIssued = receiptIssued,
        emailSent = emailSent
    })

    return orderIds
end

lib.callback.register('qbx_weapondealer:server:createOrder', function(source, storeId, buyer, cart, paymentMethod, tradeIn)
    if not Server.CheckCooldown(source, 'order') then return false end

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

    local scan = Server.Scans.GetForEmployee(source, storeId)
    if not scan then
        Server.Notify(source, 'license_invalid', 'error')
        return false
    end

    return createOrderFromScan(source, storeId, buyer, scan, cart, paymentMethod, tradeIn)
end)

lib.callback.register('qbx_weapondealer:server:createBuyerOrder', function(source, storeId, stationId, cart, paymentMethod, tradeIn)
    if not Server.CheckCooldown(source, 'buyer_order') then return false end

    local store = Server.GetStore(storeId)
    if not store then return false end

    local station
    for _, candidate in ipairs(store.orderStations or {}) do
        if candidate.id == stationId then
            station = candidate
            break
        end
    end

    if not station or not Server.IsNear(source, station.coords) then
        return false
    end

    local scan = Server.Scans.GetForBuyer(source, storeId)
    if not scan then
        Server.Notify(source, 'license_invalid', 'error')
        return false
    end

    return createOrderFromScan(source, storeId, source, scan, cart, paymentMethod, tradeIn)
end)

CreateThread(function()
    while true do
        local ready = MySQL.query.await('SELECT id, buyer_identifier, weapon_label, store_id FROM weapon_orders WHERE status = "approved" AND ready_at <= NOW()') or {}
        if #ready > 0 then
            MySQL.update.await('UPDATE weapon_orders SET status = "ready" WHERE status = "approved" AND ready_at <= NOW()')

            for _, order in ipairs(ready) do
                local buyer = Bridge.Framework.GetSourceByIdentifier(order.buyer_identifier)
                if buyer then
                    Server.Notify(buyer, 'order_ready', 'success')
                    Bridge.Tablet.Notify(buyer, 'Weapon Order Ready', ('Your %s is ready for pickup.'):format(order.weapon_label))
                    local store = Server.GetStore(order.store_id)
                    if store then
                        Bridge.Phone.SendReadyEmail(buyer, store, order)
                    end
                end

                Server.Logs.Write('order_ready', 'Weapon order marked ready for pickup.', {
                    order = order.id,
                    buyer = order.buyer_identifier,
                    weapon = order.weapon_label
                })
            end
        end
        Wait(60000)
    end
end)
