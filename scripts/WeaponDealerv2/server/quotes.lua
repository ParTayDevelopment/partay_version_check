Server = Server or {}
Server.Quotes = Server.Quotes or {}

local function hasPriorPickup(citizenid)
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM weapon_orders WHERE buyer_identifier = ? AND status = "picked_up"', { citizenid })
    return tonumber(count or 0) > 0
end

local function activeOrderCount(citizenid)
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM weapon_orders WHERE buyer_identifier = ? AND status IN ("pending_assembly", "approved", "ready")', { citizenid })
    return tonumber(count or 0)
end

local function getLimit(citizenid)
    return hasPriorPickup(citizenid) and Config.OrderLimits.ReturningMaxWeapons or Config.OrderLimits.FirstTimeMaxWeapons
end

local function buyerMeetsWeaponJobRequirement(source, weapon)
    local requirement = weapon and weapon.jobRequirement
    if not requirement or requirement.enabled == false then return true end

    local jobs = requirement.jobs or {}
    if not next(jobs) then return true end

    local job = Bridge.Framework.GetJob(source)
    if not job or not jobs[job.name] then
        return false, requirement.message or 'Requires approved employment'
    end

    if requirement.requireDuty and not job.duty then
        return false, requirement.message or 'Requires on-duty employment'
    end

    local requiredGrade = tonumber(jobs[job.name] or 0) or 0
    if tonumber(job.grade or 0) < requiredGrade then
        return false, requirement.message or ('Requires %s grade %s'):format(job.label or job.name, requiredGrade)
    end

    return true
end

local function getAmmoCatalog()
    local ammo = {}

    for item, cfg in pairs(Config.Ammo.Packages or {}) do
        if cfg.enabled ~= false then
            ammo[item] = cfg
        end
    end

    return ammo
end

local function getMeleeCatalog()
    local melee = {}

    if not Config.Melee or Config.Melee.Enabled == false then
        return melee
    end

    for _, item in ipairs(Config.Melee.Items or {}) do
        melee[#melee + 1] = {
            item = item.item,
            label = item.label or item.item,
            price = item.price or 0,
            description = item.description or '',
            image = item.image or (item.item and (item.item .. '.png') or nil),
            previewModel = item.previewModel
        }
    end

    return melee
end

local function attachmentCatalog(citizenid)
    local owned = {}
    local pending = {}
    local rows = {}
    local byItem = {}

    for _, row in ipairs(MySQL.query.await('SELECT weapon_item FROM registered_weapons WHERE owner_identifier = ? AND status = "active"', { citizenid }) or {}) do
        owned[row.weapon_item] = true
    end

    for _, row in ipairs(MySQL.query.await('SELECT weapon_item FROM weapon_orders WHERE buyer_identifier = ? AND status IN ("pending_assembly", "approved", "ready")', { citizenid }) or {}) do
        pending[row.weapon_item] = true
    end

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
                            description = attachment.description or '',
                            image = attachment.image or (attachment.item and (attachment.item .. '.png') or nil),
                            compatibleWeapons = {},
                            canBuy = false,
                            reasons = {}
                        }
                        byItem[attachment.item] = row
                        rows[#rows + 1] = row
                    end

                    row.compatibleWeapons[#row.compatibleWeapons + 1] = {
                        item = weapon.item,
                        label = weapon.label,
                        owned = owned[weapon.item] == true,
                        pending = pending[weapon.item] == true
                    }

                    if owned[weapon.item] or pending[weapon.item] then
                        row.canBuy = true
                    end
                end
            end
        end
    end

    for _, row in ipairs(rows) do
        if not row.canBuy then
            row.reasons[#row.reasons + 1] = 'Requires owned or pending compatible weapon'
        end
    end

    table.sort(rows, function(left, right)
        return tostring(left.label) < tostring(right.label)
    end)

    return rows
end

function Server.Quotes.Get(source, storeId)
    local scan = Server.Scans.GetForEmployee(source, storeId)
    if not scan then return false end

    local bank = Bridge.Framework.GetMoney(scan.buyer, 'bank')
    local cash = Bridge.Framework.GetMoney(scan.buyer, 'cash')
    local job = Bridge.Framework.GetJob(source)
    local active = activeOrderCount(scan.citizenid)
    local limit = getLimit(scan.citizenid)
    local remaining = math.max(limit - active, 0)
    local weapons = {}
    local tradeIns = Server.TradeIns.GetEligible(scan.buyer, storeId, scan.citizenid)
    local bestTradeCredit = 0

    for _, trade in ipairs(tradeIns) do
        bestTradeCredit = math.max(bestTradeCredit, tonumber(trade.value or 0) or 0)
    end

    for _, weapon in ipairs(Config.Weapons) do
        if weapon.enabled ~= false then
            local reasons = {}
            local canOrder = true

            if tonumber(job.grade) < tonumber(weapon.minGrade or 0) then
                canOrder = false
                reasons[#reasons + 1] = 'Grade restricted'
            end

            if weapon.license and weapon.license ~= Config.Documents.WeaponLicenseItem then
                canOrder = false
                reasons[#reasons + 1] = 'License required'
            end

            local jobAllowed, jobReason = buyerMeetsWeaponJobRequirement(scan.buyer, weapon)
            if not jobAllowed then
                canOrder = false
                reasons[#reasons + 1] = jobReason
            end

            if remaining <= 0 then
                canOrder = false
                reasons[#reasons + 1] = 'Order limit reached'
            end

            if (bank + bestTradeCredit) < weapon.price and (cash + bestTradeCredit) < weapon.price then
                canOrder = false
                reasons[#reasons + 1] = 'Insufficient funds'
            end

            weapons[#weapons + 1] = {
                item = weapon.item,
                canOrder = canOrder,
                reasons = reasons,
                payment = {
                    bank = (bank + bestTradeCredit) >= weapon.price,
                    cash = (cash + bestTradeCredit) >= weapon.price
                }
            }
        end
    end

    return {
        buyer = scan.buyer,
        buyerName = scan.buyerName,
        citizenid = scan.citizenid,
        balances = {
            bank = bank,
            cash = cash
        },
        limits = {
            maxWeapons = limit,
            activeOrders = active,
            remaining = remaining
        },
        ammo = getAmmoCatalog(),
        attachments = attachmentCatalog(scan.citizenid),
        melee = getMeleeCatalog(),
        tradeIn = {
            enabled = Config.TradeIn.Enabled ~= false,
            maxCreditPercent = Config.TradeIn.MaxCreditPercent or 100
        },
        tradeIns = tradeIns,
        weapons = weapons
    }
end

function Server.Quotes.GetForBuyer(source, storeId)
    local scan = Server.Scans.GetForBuyer(source, storeId)
    if not scan then return false end

    local bank = Bridge.Framework.GetMoney(source, 'bank')
    local cash = Bridge.Framework.GetMoney(source, 'cash')
    local sellerJob = Bridge.Framework.GetJob(scan.employee)
    local active = activeOrderCount(scan.citizenid)
    local limit = getLimit(scan.citizenid)
    local remaining = math.max(limit - active, 0)
    local weapons = {}
    local tradeIns = Server.TradeIns.GetEligible(source, storeId, scan.citizenid)
    local bestTradeCredit = 0

    for _, trade in ipairs(tradeIns) do
        bestTradeCredit = math.max(bestTradeCredit, tonumber(trade.value or 0) or 0)
    end

    for _, weapon in ipairs(Config.Weapons) do
        if weapon.enabled ~= false then
            local reasons = {}
            local canOrder = true

            if not sellerJob or tonumber(sellerJob.grade) < tonumber(weapon.minGrade or 0) then
                canOrder = false
                reasons[#reasons + 1] = 'Seller grade restricted'
            end

            if weapon.license and weapon.license ~= Config.Documents.WeaponLicenseItem then
                canOrder = false
                reasons[#reasons + 1] = 'License required'
            end

            local jobAllowed, jobReason = buyerMeetsWeaponJobRequirement(source, weapon)
            if not jobAllowed then
                canOrder = false
                reasons[#reasons + 1] = jobReason
            end

            if remaining <= 0 then
                canOrder = false
                reasons[#reasons + 1] = 'Order limit reached'
            end

            if (bank + bestTradeCredit) < weapon.price and (cash + bestTradeCredit) < weapon.price then
                canOrder = false
                reasons[#reasons + 1] = 'Insufficient funds'
            end

            weapons[#weapons + 1] = {
                item = weapon.item,
                canOrder = canOrder,
                reasons = reasons,
                payment = {
                    bank = (bank + bestTradeCredit) >= weapon.price,
                    cash = (cash + bestTradeCredit) >= weapon.price
                }
            }
        end
    end

    return {
        buyer = scan.buyer,
        buyerName = scan.buyerName,
        sellerName = Bridge.Framework.GetName(scan.employee),
        citizenid = scan.citizenid,
        balances = {
            bank = bank,
            cash = cash
        },
        limits = {
            maxWeapons = limit,
            activeOrders = active,
            remaining = remaining
        },
        ammo = getAmmoCatalog(),
        attachments = attachmentCatalog(scan.citizenid),
        melee = getMeleeCatalog(),
        tradeIn = {
            enabled = Config.TradeIn.Enabled ~= false,
            maxCreditPercent = Config.TradeIn.MaxCreditPercent or 100
        },
        tradeIns = tradeIns,
        weapons = weapons
    }
end

lib.callback.register('qbx_weapondealer:server:getOrderQuote', function(source, storeId)
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

    return Server.Quotes.Get(source, storeId)
end)

lib.callback.register('qbx_weapondealer:server:getBuyerOrderQuote', function(source, storeId, stationId)
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

    return Server.Quotes.GetForBuyer(source, storeId)
end)
