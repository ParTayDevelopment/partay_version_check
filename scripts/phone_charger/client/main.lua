-- phone_charger/client/main.lua

local chargerCooldown = false
local CHARGER_COOLDOWN = 60 * 1000
local FULL_CHARGE_TIME_MS = 5 * 60 * 1000
local CHARGER_TICK_MS = 1000

local manualCharging = false
local powerbankCharging = false
local manualChargingInVehicle = false
local lastChargeToggle = 0
local CHARGE_REASSERT_MS = 2000

local PHONE_ITEMS = { 'phone' }

local function clamp(n, a, b)
    return math.max(a, math.min(b, n))
end

local function Notify(data)
    data.position = data.position or 'top'
    lib.notify(data)
end

local function HasCharger()
    local count = exports.ox_inventory:Search('count', 'phone_charger') or 0
    return count > 0
end

local function HasChargerServer()
    local success, hasItem = pcall(lib.callback.await, 'phone_charger:server:hasItem', false, 'phone_charger')
    return success and hasItem == true
end

local function HasPhone()
    for i = 1, #PHONE_ITEMS do
        local count = exports.ox_inventory:Search('count', PHONE_ITEMS[i]) or 0
        if count > 0 then
            return true
        end
    end
    return false
end

local function GetPhoneBattery()
    local battery = exports['lb-phone']:GetBattery()
    return clamp(tonumber(battery) or 0, 0, 100)
end

local function SetPhoneBattery(battery)
    exports['lb-phone']:SetBattery(math.floor(clamp(battery, 0, 100)))
end

local function FormatMinutes(ms)
    return ('%.1f'):format(ms / 60000)
end

local function normalizeSlotResults(slots)
    if not slots then return {} end
    if type(slots) ~= 'table' then return {} end
    if #slots > 0 then
        return slots
    end
    local out = {}
    for _, v in pairs(slots) do
        if type(v) == 'table' then
            out[#out + 1] = v
        end
    end
    return out
end

local function getItemSlots(itemName)
    local slots = exports.ox_inventory:Search('slots', itemName)
    return normalizeSlotResults(slots)
end

local function findSlotData(itemName, wantedSlot)
    local slots = getItemSlots(itemName)
    for _, s in pairs(slots) do
        if tonumber(s.slot) == wantedSlot then
            return s
        end
    end
    return nil
end

local function findAnySlotData(itemName)
    local slots = getItemSlots(itemName)
    for _, s in pairs(slots) do
        return s
    end
    return nil
end

local function getDurabilityFromSlotData(slotData)
    if not slotData or not slotData.metadata then return 100 end
    local d = slotData.metadata.durability
    if type(d) ~= 'number' then return 100 end
    if d > 1000 then return 100 end -- ignore degrade timestamp style
    return clamp(d, 0, 100)
end

local function SyncPowerbankMetadata()
    local slots = getItemSlots('powerbank_charger')
    for _, s in pairs(slots) do
        local power = getDurabilityFromSlotData(s)
        TriggerServerEvent('phone_charger:setPowerbankDurability', s.slot, power)
    end
end

local function StopAllCharging()
    manualCharging = false
    powerbankCharging = false
    manualChargingInVehicle = false
    exports['lb-phone']:ToggleCharging(false)
    ClearPedTasks(PlayerPedId())
end

local function EnsureChargingOn()
    local now = GetGameTimer()
    if not exports['lb-phone']:IsCharging() and (now - lastChargeToggle) > CHARGE_REASSERT_MS then
        exports['lb-phone']:ToggleCharging(true)
        lastChargeToggle = now
    end
end

local function SetChargingOff()
    local now = GetGameTimer()
    if exports['lb-phone']:IsCharging() then
        exports['lb-phone']:ToggleCharging(false)
        lastChargeToggle = now
    end
end

-- Optional: label durability tooltip as "Charge"
CreateThread(function()
    exports.ox_inventory:displayMetadata({
        durability = 'Charge',
        charge = 'Charge',
    })
end)

CreateThread(function()
    Wait(2000)
    SyncPowerbankMetadata()
end)

AddEventHandler('playerSpawned', function()
    CreateThread(function()
        Wait(2000)
        SyncPowerbankMetadata()
    end)
end)

RegisterNetEvent('ox_inventory:loaded', function()
    SyncPowerbankMetadata()
end)

RegisterNetEvent('ox_inventory:inventoryLoaded', function()
    SyncPowerbankMetadata()
end)

-- =========================================
-- PHONE CHARGER (manual item use)
-- =========================================
exports('useCharger', function(data, slot)
    local ped = PlayerPedId()

    if chargerCooldown then
        Notify({ description = 'Charger is recharging', type = 'error' })
        return
    end

    if not HasCharger() then
        Notify({ description = 'You need a phone charger', type = 'error' })
        return
    end

    if not HasChargerServer() then
        Notify({ description = 'You need a phone charger', type = 'error' })
        return
    end

    if not HasPhone() then
        Notify({ description = 'You need a phone', type = 'error' })
        return
    end

    if manualCharging or powerbankCharging then
        Notify({ description = 'You are already charging', type = 'error' })
        return
    end

    if exports['lb-phone']:IsCharging() then
        Notify({ description = 'Your phone is already charging', type = 'error' })
        return
    end

    if not IsPedInAnyVehicle(ped, false) then
        Notify({ description = 'You need to be in a vehicle to use the charger', type = 'error' })
        return
    end

    local startBattery = GetPhoneBattery()
    if startBattery >= 100 then
        Notify({ description = 'Phone is already fully charged', type = 'success' })
        return
    end

    local chargeDuration = math.ceil(((100 - startBattery) / 100) * FULL_CHARGE_TIME_MS)
    local startedAt = GetGameTimer()

    manualCharging = true
    manualChargingInVehicle = IsPedInAnyVehicle(ped, false)

    -- no animation
    exports['lb-phone']:ToggleCharging(true)
    lastChargeToggle = GetGameTimer()
    Notify({
        description = ('Phone charging (%d%% to 100%%, about %s minutes)'):format(math.floor(startBattery), FormatMinutes(chargeDuration)),
        type = 'success'
    })

    chargerCooldown = true
    SetTimeout(CHARGER_COOLDOWN, function()
        chargerCooldown = false
        Notify({ description = 'Charger is ready to use again', type = 'success' })
    end)

    CreateThread(function()
        while manualCharging do
            Wait(CHARGER_TICK_MS)

            -- Stop if charger removed
            if not HasCharger() then
                StopAllCharging()
                Notify({ description = 'Charging stopped (charger removed)', type = 'error' })
                break
            end
            -- Stop if player left vehicle after starting in one
            if manualChargingInVehicle and not IsPedInAnyVehicle(ped, false) then
                StopAllCharging()
                Notify({ description = 'Charging stopped (left vehicle)', type = 'error' })
                break
            end

            local elapsed = GetGameTimer() - startedAt
            local targetBattery = startBattery + ((elapsed / FULL_CHARGE_TIME_MS) * 100)
            SetPhoneBattery(targetBattery)

            if elapsed >= chargeDuration or GetPhoneBattery() >= 100 then
                SetPhoneBattery(100)
                StopAllCharging()
                Notify({ description = 'Phone fully charged', type = 'success' })
                break
            end

            -- If something toggled it off, force it back on
            EnsureChargingOn()
        end
    end)
end)

-- =========================================
-- POWERBANK (durability-based, ~10 full charges)
-- =========================================
exports('usePowerbank', function(data, slot)
    local ped = PlayerPedId()
    local slotId = slot or (data and data.slot)
    slotId = tonumber(slotId)

    if powerbankCharging then
        Notify({ description = 'Power bank already in use', type = 'error' })
        return
    end

    if manualCharging then
        Notify({ description = 'You are already charging', type = 'error' })
        return
    end

    if exports['lb-phone']:IsCharging() then
        Notify({ description = 'Your phone is already charging', type = 'error' })
        return
    end

    -- Validate slot still contains the powerbank
    if not slotId then
        local anySlot = findAnySlotData('powerbank_charger')
        if not anySlot then
            Notify({ description = 'Power bank not found', type = 'error' })
            return
        end
        slotId = tonumber(anySlot.slot)
    end

    local slotData = findSlotData('powerbank_charger', slotId)
    if not slotData then
        local anySlot = findAnySlotData('powerbank_charger')
        if not anySlot then
            Notify({ description = 'Power bank not found', type = 'error' })
            return
        end
        slotId = tonumber(anySlot.slot)
        slotData = anySlot
    end

    local power = getDurabilityFromSlotData(slotData)
    if power <= 0 then
        Notify({ description = 'Power bank is empty (recharge it in a vehicle)', type = 'error' })
        return
    end

    -- Ensure metadata shows the current percent
    TriggerServerEvent('phone_charger:setPowerbankDurability', slotId, power)

    powerbankCharging = true

    -- no animation
    exports['lb-phone']:ToggleCharging(true)
    lastChargeToggle = GetGameTimer()
    Notify({ description = ('Charging from power bank (%d%%)'):format(math.floor(power)), type = 'success' })

    local lastBattery = exports['lb-phone']:GetBattery()

    CreateThread(function()
        while powerbankCharging do
            Wait(2000)

            -- Stop if removed/dropped
            slotData = findSlotData('powerbank_charger', slotId)
            if not slotData then
                powerbankCharging = false
                SetChargingOff()
                ClearPedTasks(ped)
                Notify({ description = 'Charging stopped (power bank removed)', type = 'error' })
                break
            end

            power = getDurabilityFromSlotData(slotData)
            if power <= 0 then
                powerbankCharging = false
                SetChargingOff()
                ClearPedTasks(ped)
                Notify({ description = 'Power bank drained (0%)', type = 'error' })
                break
            end

            local battery = exports['lb-phone']:GetBattery()
            if battery >= 100 then
                powerbankCharging = false
                SetChargingOff()
                ClearPedTasks(ped)
                Notify({ description = 'Phone fully charged', type = 'success' })
                break
            end

            -- Force charging back on if something toggled it off
            EnsureChargingOn()

            -- Consume based on actual phone charge gained
            local gained = math.max(0, battery - lastBattery)
            lastBattery = battery

            if gained > 0 then
                -- 10 full charges: +1% phone = -0.1% powerbank
                power = clamp(power - (gained / 10.0), 0, 100)
                TriggerServerEvent('phone_charger:setPowerbankDurability', slotId, power)

                if power <= 0 then
                    powerbankCharging = false
                    SetChargingOff()
                    ClearPedTasks(ped)
                    Notify({ description = 'Power bank drained (0%)', type = 'error' })
                    break
                end
            end
        end
    end)
end)

-- Safety
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        StopAllCharging()
    end
end)
