Server = Server or {}
Server.TradeIns = Server.TradeIns or {}

local function weaponByItem(itemName)
    for _, weapon in ipairs(Config.Weapons or {}) do
        if weapon.item == itemName and weapon.enabled ~= false then
            return weapon
        end
    end
end

local function metadataSerial(metadata)
    metadata = metadata or {}
    return metadata.serial or metadata.Serial or metadata.weapon_serial or metadata.weaponSerial
end

local function timestampFromDb(value)
    if not value then return nil end

    if type(value) == 'number' then
        return math.floor(value > 100000000000 and value / 1000 or value)
    end

    local year, month, day, hour, min, sec = tostring(value):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d):(%d%d):(%d%d)')
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

local function tradeConfig()
    return Config.TradeIn or {}
end

local function percentValue(price, percent)
    return math.max(0, math.floor((tonumber(price or 0) or 0) * ((tonumber(percent or 0) or 0) / 100)))
end

local function valueRegisteredWeapon(source, storeId, citizenid, weapon, slot, metadata)
    local serial = metadataSerial(metadata)
    if not serial then return nil end

    local registered = MySQL.single.await([[
        SELECT *
        FROM registered_weapons
        WHERE serial = ? AND weapon_item = ?
        LIMIT 1
    ]], {
        serial,
        weapon.item
    })

    if not registered or registered.status ~= 'active' then return nil end

    local cfg = tradeConfig()
    local ownerMatch = Bridge.Framework.SameIdentifier(registered.owner_identifier, citizenid)
    local sameStore = registered.store_id == storeId
    local created = timestampFromDb(registered.created_at)
    local recent = created and (os.time() - created) <= ((tonumber(cfg.RecentWindowDays or 0) or 0) * 86400)

    local percent = cfg.UnownedPercent or 25
    local reason = 'Unowned registered firearm'
    local owned = false

    if ownerMatch and sameStore and recent then
        percent = cfg.OwnedRecentPercent or 120
        reason = ('Store trade-in bonus, within %s days'):format(cfg.RecentWindowDays or 0)
        owned = true
    elseif ownerMatch and sameStore then
        percent = cfg.OwnedExpiredPercent or 70
        reason = 'Store-purchased firearm outside bonus window'
        owned = true
    elseif ownerMatch then
        percent = cfg.OwnedExpiredPercent or 70
        reason = 'Owned registered firearm from another location'
        owned = true
    end

    return {
        slot = slot.slot,
        item = weapon.item,
        label = weapon.label,
        serial = serial,
        registered = true,
        owned = owned,
        value = percentValue(weapon.price, percent),
        reason = reason
    }
end

local function valueUnregisteredWeapon(weapon, slot)
    local cfg = tradeConfig()
    if cfg.AllowUnregistered == false then return nil end

    return {
        slot = slot.slot,
        item = weapon.item,
        label = weapon.label,
        serial = nil,
        registered = false,
        owned = false,
        value = percentValue(weapon.price, cfg.UnownedPercent or 25),
        reason = 'Unregistered firearm flat buyback'
    }
end

function Server.TradeIns.GetEligible(source, storeId, citizenid)
    local cfg = tradeConfig()
    if cfg.Enabled == false then return {} end

    local eligible = {}

    for _, weapon in ipairs(Config.Weapons or {}) do
        if weapon.enabled ~= false then
            local slots = Bridge.Inventory.GetSlots(source, weapon.item)

            for _, slot in pairs(slots or {}) do
                if type(slot) == 'table' and slot.name == weapon.item and slot.slot then
                    local metadata = slot.metadata or slot.info or {}
                    local row = valueRegisteredWeapon(source, storeId, citizenid, weapon, slot, metadata)
                        or valueUnregisteredWeapon(weapon, slot)

                    if row and row.value > 0 then
                        eligible[#eligible + 1] = row
                    end
                end
            end
        end
    end

    table.sort(eligible, function(left, right)
        return tonumber(left.value or 0) > tonumber(right.value or 0)
    end)

    return eligible
end

function Server.TradeIns.Resolve(source, storeId, citizenid, trade)
    local cfg = tradeConfig()
    if cfg.Enabled == false or type(trade) ~= 'table' then return nil end

    local slotId = tonumber(trade.slot)
    if not slotId then return nil end

    local slot = Bridge.Inventory.GetSlot(source, slotId)
    if not slot or type(slot) ~= 'table' then return nil end

    local weapon = weaponByItem(slot.name)
    if not weapon then return nil end

    local metadata = slot.metadata or slot.info or {}
    local row = valueRegisteredWeapon(source, storeId, citizenid, weapon, slot, metadata)
        or valueUnregisteredWeapon(weapon, slot)

    if not row or row.value <= 0 then return nil end

    row.metadata = metadata
    return row
end

function Server.TradeIns.Remove(source, trade)
    if not trade or not trade.item or not trade.slot then return false end
    return Bridge.Inventory.RemoveItem(source, trade.item, 1, nil, trade.slot) == true
end

function Server.TradeIns.MarkAccepted(trade, orderIds, storeId, citizenid, employeeIdentifier, employeeName)
    if not trade then return end

    local ok, err = pcall(function()
        MySQL.insert.await([[
            INSERT INTO weapon_trade_ins
            (store_id, buyer_identifier, employee_identifier, employee_name, item, label, serial, slot, value, registered, owned, primary_order_id, order_ids, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            storeId,
            citizenid,
            employeeIdentifier,
            employeeName,
            trade.item,
            trade.label,
            trade.serial,
            trade.slot,
            trade.appliedCredit or trade.value,
            trade.registered and 1 or 0,
            trade.owned and 1 or 0,
            orderIds and orderIds[1] or nil,
            json.encode(orderIds or {}),
            json.encode({
                reason = trade.reason,
                rawValue = trade.value,
                appliedCredit = trade.appliedCredit,
                metadata = trade.metadata or {}
            })
        })

        if trade.serial then
            MySQL.update.await('UPDATE registered_weapons SET status = "transferred" WHERE serial = ? AND status = "active"', { trade.serial })
        end
    end)

    if not ok then
        Server.Logs.Write('trade_in_audit_failed', 'Trade-in was accepted but audit write failed.', {
            buyer = citizenid,
            item = trade.item,
            serial = trade.serial,
            error = tostring(err)
        })
    end
end

function Server.TradeIns.RestoreForOrder(buyer, orderId)
    local ok, trade = pcall(function()
        return MySQL.single.await('SELECT * FROM weapon_trade_ins WHERE primary_order_id = ? LIMIT 1', { orderId })
    end)

    if not ok then
        Server.Logs.Write('trade_in_restore_lookup_failed', 'Trade-in restore lookup failed during order refund.', {
            order = orderId,
            error = tostring(trade)
        })
        return true
    end

    if not trade then return true end

    local metadata = {}
    if trade.metadata then
        local ok, decoded = pcall(json.decode, trade.metadata)
        if ok and type(decoded) == 'table' and type(decoded.metadata) == 'table' then
            metadata = decoded.metadata
        end
    end

    local added = Bridge.Inventory.AddItem(buyer, trade.item, 1, metadata)
    if not added then return false end

    if trade.serial then
        MySQL.update.await('UPDATE registered_weapons SET status = "active" WHERE serial = ?', { trade.serial })
    end

    return true
end
