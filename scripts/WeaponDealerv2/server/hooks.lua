Server = Server or {}
Server.Hooks = Server.Hooks or {}

local function isTestWeapon(slot)
    return type(slot) == 'table'
        and slot.metadata
        and slot.metadata.weapondealer_test == true
end

local function blockTestWeaponMove(payload)
    if not isTestWeapon(payload.fromSlot) and not isTestWeapon(payload.toSlot) then
        return true
    end

    Server.Logs.Write('blocked_test_weapon_move', 'Blocked movement of supervised test weapon.', {
        source = payload.source,
        action = payload.action,
        fromInventory = payload.fromInventory,
        toInventory = payload.toInventory,
        fromType = payload.fromType,
        toType = payload.toType,
        weapon = payload.fromSlot and payload.fromSlot.name or payload.toSlot and payload.toSlot.name
    })

    if payload.source then
        Server.Notify(payload.source, 'test_weapon_locked', 'error')
    end

    return false
end

local function getPartsStashes()
    local stashes = {}

    for _, store in ipairs(Config.Stores or {}) do
        local assembly = store.assembly
        if assembly and assembly.stash then
            stashes[assembly.stash] = true
        end
    end

    return stashes
end

local function inventoryId(value)
    if type(value) == 'table' then
        return value.id or value.name or value.owner
    end

    return value
end

local function hasStorageGrade(source, grade)
    local job = Bridge.Framework.GetJob(source)
    return job
        and job.name == Config.Job.Name
        and (Config.Job.RequireDuty ~= true or job.duty == true)
        and tonumber(job.grade or 0) >= tonumber(grade or 0)
end

local function guardPartsStorageMove(payload)
    local source = payload.source
    if not source then return true end

    local stashes = getPartsStashes()
    local fromInventory = tostring(inventoryId(payload.fromInventory) or '')
    local toInventory = tostring(inventoryId(payload.toInventory) or '')
    local fromPartsStorage = stashes[fromInventory] == true
    local toPartsStorage = stashes[toInventory] == true

    if not fromPartsStorage and not toPartsStorage then
        return true
    end

    if toPartsStorage and not fromPartsStorage then
        if hasStorageGrade(source, Config.PartsStorage and Config.PartsStorage.DepositGrade or 0) then
            return true
        end

        Server.Notify(source, 'parts_storage_deposit_denied', 'error')
        Server.Logs.Blocked(source, 'parts_storage_deposit', 'not_authorized', {
            fromInventory = fromInventory,
            toInventory = toInventory,
            action = payload.action
        })
        return false
    end

    if fromPartsStorage and not toPartsStorage then
        if hasStorageGrade(source, Config.PartsStorage and Config.PartsStorage.WithdrawGrade or 99) then
            return true
        end

        Server.Notify(source, 'parts_storage_withdraw_denied', 'error')
        Server.Logs.Blocked(source, 'parts_storage_withdraw', 'not_authorized', {
            fromInventory = fromInventory,
            toInventory = toInventory,
            action = payload.action
        })
        return false
    end

    return true
end

CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(500)
    end

    Server.Hooks.TestWeaponSwap = exports.ox_inventory:registerHook('swapItems', blockTestWeaponMove, {
        print = Config.Debug
    })

    Server.Hooks.PartsStorageSwap = exports.ox_inventory:registerHook('swapItems', guardPartsStorageMove, {
        print = Config.Debug
    })
end)
