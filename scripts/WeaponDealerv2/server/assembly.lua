Server = Server or {}
Server.Assembly = Server.Assembly or {}

local assemblyLocks = {}

local function getReadyAt(waitSeconds)
    return os.date('%Y-%m-%d %H:%M:%S', os.time() + (tonumber(waitSeconds) or 0))
end

local function getStoreAssembly(storeId)
    local store = Server.GetStore(storeId)
    if not store or not store.assembly then return nil, nil end
    if store.assembly.Enabled == false then return nil, nil end

    return store, store.assembly
end

local function canUseAssembly(source, store, assembly)
    if not Config.Assembly or Config.Assembly.Enabled == false then
        return false, 'not_authorized'
    end

    local allowed, reason = Bridge.Framework.IsAuthorized(source, 'Order')
    if not allowed then
        return false, reason
    end

    local job = Bridge.Framework.GetJob(source)
    if not job or tonumber(job.grade or 0) < tonumber(Config.Assembly.Grade or 0) then
        return false, 'not_authorized'
    end

    if not Server.IsNear(source, assembly.coords) then
        return false, 'not_at_assembly'
    end

    return true
end

local function recipeFor(weaponItem)
    return Config.Assembly and Config.Assembly.Recipes and Config.Assembly.Recipes[weaponItem]
end

local function hydrateRecipe(recipe, stashId)
    local rows = {}
    local hasAll = true

    for _, part in ipairs(recipe or {}) do
        local available = Bridge.Inventory.GetInventoryItemCount(stashId, part.item)
        local count = tonumber(part.count or 1) or 1

        if available < count then
            hasAll = false
        end

        rows[#rows + 1] = {
            item = part.item,
            label = part.label or part.item,
            count = count,
            available = available,
            has = available >= count
        }
    end

    return rows, hasAll
end

local function registerAssemblyStashes()
    if not Config.Assembly or Config.Assembly.Enabled == false then return end

    for _, store in ipairs(Config.Stores or {}) do
        local assembly = store.assembly
        if assembly and assembly.Enabled ~= false and assembly.stash then
            local groups = Config.Job and Config.Job.Name and {
                [Config.Job.Name] = Config.Assembly.Grade or 0
            } or nil

            Bridge.Inventory.RegisterStash(
                assembly.stash,
                assembly.stashLabel or (store.label .. ' Parts Storage'),
                assembly.stashSlots or 50,
                assembly.stashWeight or 250000,
                false,
                groups,
                assembly.coords and vec3(assembly.coords.x, assembly.coords.y, assembly.coords.z) or nil
            )
        end
    end
end

CreateThread(registerAssemblyStashes)

lib.callback.register('qbx_weapondealer:server:getAssemblyOrders', function(source, storeId)
    local store, assembly = getStoreAssembly(storeId)
    if not store then return {} end

    local allowed, reason = canUseAssembly(source, store, assembly)
    if not allowed then
        Server.Notify(source, reason, 'error')
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT id, buyer_identifier, buyer_name, weapon_item, weapon_label, price, ammo_item, ammo_count, attachments, created_at
        FROM weapon_orders
        WHERE store_id = ? AND status = "pending_assembly"
        ORDER BY created_at ASC
    ]], { storeId }) or {}

    for _, order in ipairs(rows) do
        local recipe = recipeFor(order.weapon_item) or {}
        order.parts, order.has_parts = hydrateRecipe(recipe, assembly.stash)
    end

    return rows
end)

lib.callback.register('qbx_weapondealer:server:assembleOrder', function(source, storeId, orderId)
    if not Server.CheckCooldown(source, 'assembly') then return false end

    orderId = tonumber(orderId)
    if not orderId then return false end

    if assemblyLocks[orderId] then
        Server.Notify(source, 'assembly_busy', 'warning')
        return false
    end

    local store, assembly = getStoreAssembly(storeId)
    if not store then return false end

    local allowed, reason = canUseAssembly(source, store, assembly)
    if not allowed then
        Server.Notify(source, reason, 'error')
        return false
    end

    assemblyLocks[orderId] = true

    local ok, result = pcall(function()
        local order = MySQL.single.await('SELECT * FROM weapon_orders WHERE id = ? AND store_id = ? FOR UPDATE', { orderId, storeId })
        if not order or order.status ~= 'pending_assembly' then
            Server.Notify(source, 'assembly_not_pending', 'error')
            return false
        end

        local weapon = Server.GetWeapon(order.weapon_item)
        local recipe = recipeFor(order.weapon_item)
        if not weapon or not recipe or #recipe == 0 then
            Server.Notify(source, 'assembly_missing_recipe', 'error')
            return false
        end

        local parts, hasAll = hydrateRecipe(recipe, assembly.stash)
        if not hasAll then
            Server.Notify(source, 'assembly_missing_parts', 'error')
            return false
        end

        Wait((Config.Assembly.CraftTimeSeconds or 12) * 1000)

        parts, hasAll = hydrateRecipe(recipe, assembly.stash)
        if not hasAll then
            Server.Notify(source, 'assembly_missing_parts', 'error')
            return false
        end

        for _, part in ipairs(parts) do
            local removed = Bridge.Inventory.RemoveFromInventory(assembly.stash, part.item, part.count)
            if not removed then
                Server.Notify(source, 'assembly_missing_parts', 'error')
                return false
            end
        end

        local readyAt = getReadyAt(weapon.waitSeconds)
        MySQL.update.await([[
            UPDATE weapon_orders
            SET status = "approved", ready_at = ?, assembled_by = ?, assembled_by_name = ?, assembled_at = NOW()
            WHERE id = ? AND status = "pending_assembly"
        ]], {
            readyAt,
            Bridge.Framework.GetIdentifier(source),
            Bridge.Framework.GetName(source),
            orderId
        })

        local buyer = Bridge.Framework.GetSourceByIdentifier(order.buyer_identifier)
        if buyer then
            Server.Notify(buyer, 'assembly_complete_buyer', 'success', { weapon = order.weapon_label })
            Bridge.Tablet.Notify(buyer, 'Firearm Assembly Complete', ('Your %s has entered clearance processing.'):format(order.weapon_label))
            Bridge.Phone.SendClearanceEmail(buyer, store, order)
        end

        Server.Notify(source, 'assembly_complete', 'success', { weapon = order.weapon_label })
        Server.Logs.Write('weapon_assembled', 'Weapon order assembled from store stash.', {
            order = orderId,
            store = storeId,
            weapon = order.weapon_item,
            employee = Bridge.Framework.GetIdentifier(source),
            readyAt = readyAt,
            parts = parts
        })

        return true
    end)

    assemblyLocks[orderId] = nil

    if not ok then
        Server.Notify(source, 'order_failed', 'error')
        Server.Logs.Write('assembly_exception', 'Weapon assembly threw an exception.', {
            order = orderId,
            store = storeId,
            error = tostring(result)
        })
        return false
    end

    return result == true
end)
