Server = Server or {}
Server.Melee = Server.Melee or {}

local function findStation(storeId, stationId)
    local store = Server.GetStore(storeId)
    if not store then return nil, nil end

    for _, station in ipairs(store.orderStations or {}) do
        if station.id == stationId then
            return store, station
        end
    end
end

local function getMeleeItem(itemName)
    for _, item in ipairs(Config.Melee.Items or {}) do
        if item.item == itemName then
            return item
        end
    end
end

local function normalizeItems(items)
    if type(items) ~= 'table' then return {} end

    local normalized = {}
    local seen = {}

    for _, entry in ipairs(items) do
        if type(entry) == 'table' and type(entry.item) == 'string' and not seen[entry.item] then
            local cfg = getMeleeItem(entry.item)

            if cfg then
                normalized[#normalized + 1] = {
                    item = cfg.item,
                    label = cfg.label or cfg.item,
                    price = tonumber(cfg.price or 0) or 0
                }
                seen[entry.item] = true
            end
        end
    end

    return normalized
end

lib.callback.register('qbx_weapondealer:server:purchaseMelee', function(source, storeId, stationId, items, paymentMethod, tradeIn)
    if not Config.Melee or Config.Melee.Enabled == false then return false end
    if not Server.CheckCooldown(source, 'melee') then return false end

    if paymentMethod ~= 'bank' and paymentMethod ~= 'cash' then
        return false
    end

    local store, station = findStation(storeId, stationId)
    if not store or not station or not Server.IsNear(source, station.coords) then
        return false
    end

    local scan = Server.Scans.GetForBuyer(source, storeId)
    if Config.Melee.RequiresVerification ~= false and not scan then
        Server.Notify(source, 'license_invalid', 'error')
        return false
    end

    local prepared = normalizeItems(items)
    if #prepared == 0 then
        return false
    end

    local total = 0
    for _, entry in ipairs(prepared) do
        total = total + entry.price
        entry.type = 'melee'
        entry.count = 1
    end

    local citizenid = scan and scan.citizenid or Bridge.Framework.GetIdentifier(source)
    local requestedTrade = type(tradeIn) == 'table' and tradeIn.slot ~= nil
    local resolvedTrade = Server.TradeIns.Resolve(source, storeId, citizenid, tradeIn)
    if requestedTrade and not resolvedTrade then
        Server.Notify(source, 'trade_in_failed', 'error')
        return false
    end

    local tradeCredit = 0
    if resolvedTrade then
        local maxPercent = tonumber((Config.TradeIn and Config.TradeIn.MaxCreditPercent) or 100) or 100
        tradeCredit = math.min(tonumber(resolvedTrade.value or 0) or 0, math.floor(total * (maxPercent / 100)), total)
        resolvedTrade.appliedCredit = tradeCredit
    end

    local amountDue = math.max(total - tradeCredit, 0)

    if total <= 0 or Bridge.Framework.GetMoney(source, paymentMethod) < amountDue then
        Server.Notify(source, 'insufficient_funds', 'error')
        return false
    end

    if amountDue > 0 then
        if not Bridge.Framework.RemoveMoney(source, paymentMethod, amountDue, 'weapondealer-melee') then
            Server.Notify(source, 'insufficient_funds', 'error')
            return false
        end
    end

    if resolvedTrade and not Server.TradeIns.Remove(source, resolvedTrade) then
        if amountDue > 0 then
            Bridge.Framework.AddMoney(source, paymentMethod, amountDue, 'weapondealer-melee-refund')
        end
        Server.Notify(source, 'trade_in_failed', 'error')
        return false
    end

    for _, entry in ipairs(prepared) do
        entry.metadata = {
            legal_melee_purchase = true,
            registered = false,
            store = storeId,
            seller = scan and Bridge.Framework.GetName(scan.employee) or store.label,
            purchase_date = os.time(),
            description = ('Legal melee item purchased from %s.'):format(store.label)
        }
    end

    local inserted, pickupIds = pcall(function()
        return Server.Pickups.CreateItemOrders(source, storeId, scan, prepared, paymentMethod)
    end)

    if not inserted or not pickupIds or #pickupIds == 0 then
        if resolvedTrade then
            Bridge.Inventory.AddItem(source, resolvedTrade.item, 1, resolvedTrade.metadata)
        end
        if amountDue > 0 then
            Bridge.Framework.AddMoney(source, paymentMethod, amountDue, 'weapondealer-melee-refund')
        end
        Server.Notify(source, 'order_failed_refunded', 'error')
        Server.Logs.Write('melee_pickup_insert_failed', 'Melee pickup order failed after payment; refund attempted.', {
            buyer = citizenid,
            total = amountDue,
            tradeCredit = tradeCredit,
            paymentMethod = paymentMethod,
            error = tostring(pickupIds)
        })
        return false
    end

    local employee = scan and scan.employee or source
    local commission = Bridge.Banking.PayCommission(employee, amountDue)
    Bridge.Banking.DepositSociety(math.max(amountDue - commission, 0))
    if amountDue > 0 then
        Bridge.Banking.AddTransaction(source, 'withdrawal', amountDue, paymentMethod, 'Legal Melee Purchase', ('%s melee item(s) at %s'):format(#prepared, store.label))
    end

    if resolvedTrade then
        Server.TradeIns.MarkAccepted(
            resolvedTrade,
            pickupIds,
            storeId,
            citizenid,
            Bridge.Framework.GetIdentifier(employee),
            Bridge.Framework.GetName(employee)
        )
    end

    Server.Notify(source, 'melee_order_ready', 'success', { total = amountDue })
    if scan and scan.employee ~= source then
        Server.Notify(scan.employee, 'melee_order_ready', 'inform', { total = amountDue })
    end

    Server.Logs.Write('melee_purchase', 'Verified melee purchase queued for pickup.', {
        buyer = citizenid,
        seller = scan and Bridge.Framework.GetIdentifier(scan.employee) or Bridge.Framework.GetIdentifier(source),
        total = amountDue,
        grossTotal = total,
        tradeCredit = tradeCredit,
        paymentMethod = paymentMethod,
        items = prepared,
        commission = commission
    })

    return true
end)
