-- [[ Heist Economy & Transactions ]] --

local PendingHeistAlarmWitnesses = {}

if lib and lib.locale then
    lib.locale()
end

local function T(localeKey, vars)
    if type(locale) ~= 'function' then return localeKey end

    local ok, value = pcall(locale, localeKey, vars)
    return ok and value or localeKey
end

local function SendHeistPoliceAlert(payload)
    local handler = rawget(_G, 'PartayKeys_SendPoliceAlert') or rawget(_G, 'SendPoliceAlert')
    if type(handler) == 'function' then
        return handler(payload)
    end

    local ok, result = pcall(function()
        return exports.partay_keys:SendPoliceAlert(payload)
    end)
    if ok then return result end

    print(('^5[ParTay Keys Debug]^1 ERR_DISPATCH_UNAVAILABLE - Failed to send police alert: %s^0'):format(tostring(result)))
    return false
end

local function SetLiveVehiclePossession(plate, possessionId, originalOwnerId)
    for _, veh in ipairs(GetAllVehicles()) do
        if GetVehicleNumberPlateText(veh):gsub('^%s*(.-)%s*$', '%1') == plate then
            Entity(veh).state:set('possession_id', possessionId, true)
            Entity(veh).state:set('isStolen', true, true)
            if originalOwnerId then
                Entity(veh).state:set('original_owner_id', originalOwnerId, true)
            end
            Entity(veh).state:set('lockState', 1, true)
            SetVehicleDoorsLocked(veh, 1)
            return
        end
    end
end

local function FindLiveVehicleByPlate(plate)
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    if not plate or plate == '' then return 0 end

    for _, veh in ipairs(GetAllVehicles()) do
        if GetVehicleNumberPlateText(veh):gsub('^%s*(.-)%s*$', '%1') == plate then
            return veh
        end
    end

    return 0
end

local function HasDecoderKit(src)
    if Config.Items.ElectronicDecoder and not Bridge.HasInventoryItem(src, Config.Items.ElectronicDecoder, 1) then return false end
    if Config.Items.BlankKey and not Bridge.HasInventoryItem(src, Config.Items.BlankKey, 1) then return false end
    return true
end

local NotifyOriginalOwner

local function CompleteStolenKeyDecode(src, netId, plate)
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    if veh == 0 or not plate or plate == '' then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_no_vehicle'), 'error')
        return
    end
    if GetVehicleNumberPlateText(veh):gsub('^%s*(.-)%s*$', '%1') ~= plate then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_verify_failed'), 'error')
        return
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 5.0 then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_too_far'), 'error')
        return
    end

    if not Config.RequirePhysicalKey then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_not_required'), 'error')
        return
    end

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then
        Notify(src, T('label_electronic_decoder'), T('error_character_unavailable'), 'error')
        return
    end

    local registration = GetVehicleRegistration(plate)
    if not registration then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_unregistered_vehicle'), 'error')
        return
    end

    local originalOwnerId = registration[GetOwnerColumn()]

    if not HasSatisfiedLockStep(veh, citizenId) then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_lockpick_first'), 'error')
        return
    end

    if RequiresHotwire(veh) and Entity(veh).state.hotwiredBy ~= citizenId then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_hotwire_first'), 'error')
        return
    end

    if not HasDecoderKit(src) then
        Notify(src, T('label_electronic_decoder'), T('error_need_decoder_kit'), 'error')
        return
    end

    if Config.Heist.ConsumeOnSuccess and Config.Items.BlankKey then
        if not Bridge.RemoveInventoryItem(src, Config.Items.BlankKey, 1) then
            Notify(src, T('label_electronic_decoder'), T('error_consume_blank_key_failed'), 'error')
            return
        end
    end

    local permanentTheft = Config.Heist.EnablePermanentTheft ~= false
    if permanentTheft then
        local storage = GetVehicleStorage()
        MySQL.Async.execute(('UPDATE %s SET possession_id = ? WHERE plate = ?'):format(storage.tableSql), {citizenId, plate})
    end

    Entity(veh).state:set('possession_id', citizenId, true)
    Entity(veh).state:set('isStolen', permanentTheft, true)
    Entity(veh).state:set('original_owner_id', originalOwnerId, true)
    Bridge.GiveVehicleKey(src, plate, registration.vehicle or registration.model or 'Stolen Vehicle', tonumber(registration.key_version) or 1, citizenId, {
        original_owner_id = originalOwnerId,
        current_possession_id = citizenId,
        stolen = true,
        temporary_theft = not permanentTheft
    })

    Notify(src, T('label_electronic_decoder'), permanentTheft and T('success_decoder_possession_transferred') or T('success_decoder_temporary_access'), 'success')
    exports.partay_keys:SendAuditLog('Vehicle Stolen', ('Player %s cloned key for %s (%s)'):format(src, plate, permanentTheft and 'permanent' or 'temporary'), 'info')
    if permanentTheft and Config.NotifyOwnerOnTheft then
        NotifyOriginalOwner(registration, plate)
    end
end

NotifyOriginalOwner = function(registration, plate)
    local ownerId = registration and registration[GetOwnerColumn()]
    if not ownerId then return end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src and Bridge.GetCitizenID(src) == ownerId then
            Notify(src, T('label_vehicle_theft'), T('warning_vehicle_stolen', { plate = plate }), 'warning')
            return
        end
    end
end

local function ProcessHeistResult(src, plate, token, success)
    local heistData = ActiveHeists[src]

    -- Zero-Trust Validation
    if not heistData or heistData.token ~= token or heistData.plate ~= plate then
        exports.partay_keys:SendAuditLog('Exploit Attempt', ('Player %s attempted to bypass minigame token for %s'):format(src, plate), 'exploit')
        return
    end

    if success and heistData.heistType ~= 'decoder' and os.time() - heistData.startTime < 3 then
        ActiveHeists[src] = nil
        exports.partay_keys:SendAuditLog('Exploit Attempt', ('Player %s completed heist token too quickly for %s'):format(src, plate), 'exploit')
        return
    end

    if success and heistData.heistType == 'decoder' then
        ActiveHeists[src] = nil
        CompleteStolenKeyDecode(src, heistData.netId, heistData.plate)
        return
    end

    if success and heistData.heistType == 'hotwire' then
        ActiveHeists[src] = nil
        if PartayKeys_CompleteHotwire then
            PartayKeys_CompleteHotwire(src, heistData.netId, heistData.plate)
        end
        return
    end

    if success and heistData.heistType == 'lockpick' then
        local registration = GetVehicleRegistration(plate)
        local possessionId = Bridge.GetCitizenID(src)
        local veh = FindLiveVehicleByPlate(plate)

        if veh ~= 0 and possessionId then
            Entity(veh).state:set('lockDecodedBy', possessionId, true)
            Entity(veh).state:set('lockState', 1, true)
            SetVehicleDoorsLocked(veh, 1)
        end

        Notify(src, T('label_vehicle_theft'), T('success_lockpick_hotwire_next'), 'success')
        exports.partay_keys:SendAuditLog('Vehicle Lockpicked', ('Player %s picked vehicle lock %s'):format(src, plate), 'info')
    else
        local veh = heistData.netId and NetworkGetEntityFromNetworkId(heistData.netId) or 0
        local alarmStarted, alarmTier = TriggerInstalledAlarm(veh, true, 'FailedHeistAlarm')
        local alarmAllowsPolice = alarmStarted
            and PartayKeys_AlarmTierHasFeature(alarmTier, 'PoliceAlert')
        if alarmStarted and PartayKeys_AlarmTierHasFeature(alarmTier, 'FailedHeistVoiceWarning') then
            TriggerClientEvent(
                'partay_keys:client:AdvancedAlarmWarning',
                -1,
                heistData.netId,
                T('warning_advanced_alarm_failed_heist'),
                2
            )
        end
        if alarmStarted and type(PartayKeys_SendSmartAlarmNotification) == 'function' then
            PartayKeys_SendSmartAlarmNotification(veh, plate, alarmTier, 'failed_heist')
        end
        local shouldCheckWitnesses = Config.Heist.PoliceAlerts
            and Config.Heist.PoliceAlerts.Enabled
            and (alarmAllowsPolice or (not alarmStarted and heistData.heistType == 'lockpick'))
        if shouldCheckWitnesses then
            PendingHeistAlarmWitnesses[src] = {
                plate = plate,
                netId = heistData.netId,
                heistType = heistData.heistType,
                expires = os.time() + 10
            }
            TriggerClientEvent('partay_keys:client:CheckHeistAlarmWitnesses', src, heistData.netId, plate, heistData.heistType)
        end

        if heistData.heistType == 'decoder' then
            Notify(src, T('label_electronic_decoder'), T('error_decoder_failed'), 'error')
        elseif heistData.heistType == 'hotwire' then
            Notify(src, T('label_hotwire'), T('error_hotwire_failed'), 'error')
        elseif heistData.heistType == 'lockpick' then
            Notify(src, T('label_vehicle_theft'), T('error_lockpick_failed'), 'error')
        end

        -- Degradation Math
        local breakChance = tonumber(Config.Heist.BreakChanceOnFail) or 0
        local breakItem = heistData.heistType == 'decoder' and Config.Items.ElectronicDecoder
            or heistData.heistType == 'hotwire' and Config.Items.WiringKit
            or Config.Items.Lockpick
        if breakItem and breakChance > 0 and math.random(1, 100) <= breakChance then
            Bridge.RemoveInventoryItem(src, breakItem, 1)
            exports.partay_keys:SendAuditLog('Tool Broken', ('Player %s broke %s on vehicle %s'):format(src, breakItem, plate), 'info')
            TriggerClientEvent('partay_keys:client:CancelAnimation', src)
        end
    end

    ActiveHeists[src] = nil
end

RegisterNetEvent('partay_keys:server:ProcessHeistResult', function(plate, token, success)
    ProcessHeistResult(source, plate, token, success)
end)

RegisterNetEvent('partay_keys:server:HeistResult', function(token, success)
    local src = source
    local heistData = ActiveHeists[src]
    if not heistData then return end

    ProcessHeistResult(src, heistData.plate, token, success)
end)

RegisterNetEvent('partay_keys:server:ReportWitnessedHeistAlarm', function(netId, plate, heistType, witnessType)
    local src = source
    local pending = PendingHeistAlarmWitnesses[src]
    if not pending or pending.expires < os.time() then
        PendingHeistAlarmWitnesses[src] = nil
        return
    end

    plate = TrimPlate(plate)
    if pending.netId ~= netId or pending.plate ~= plate or pending.heistType ~= heistType then return end

    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or not DoesEntityExist(veh) then return end
    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 30.0 then return end

    PendingHeistAlarmWitnesses[src] = nil

    local title = Config.Heist.PoliceAlerts.Title
    local message = ('A witness reported a failed %s attempt near a vehicle. Plate: %s.'):format(heistType or 'theft', plate)
    if Entity(veh).state.alarmActive then
        message = ('A witness reported a vehicle alarm during a failed %s attempt. Plate: %s.'):format(heistType or 'theft', plate)
    elseif heistType == 'lockpick' then
        title = 'Suspicious Vehicle Tampering'
    end

    SendHeistPoliceAlert({
        source = src,
        coords = GetEntityCoords(veh),
        plate = plate,
        vehicle = veh,
        heistType = heistType,
        code = Config.Heist.PoliceAlerts.Code,
        title = title,
        message = message,
        cooldownKey = ('heist_alarm:%s'):format(plate),
        cooldown = Config.Heist.PoliceAlerts.Cooldown
    })

    exports.partay_keys:SendAuditLog('Police Alert', ('Witnessed heist alarm dispatched for %s (%s, %s)'):format(plate, heistType or 'unknown', witnessType or 'unknown'), 'info')
end)

RegisterNetEvent('partay_keys:server:RequestDecoderToken', function(netId, plate)
    local src = source
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')

    local policeAllowed, policeOnline, policeRequired = MeetsPoliceRequirement('Decoder')
    if not policeAllowed then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_police_required', { required = policeRequired, current = policeOnline }), 'error')
        return
    end

    if veh == 0 or not plate or plate == '' then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_no_vehicle'), 'error')
        return
    end
    if GetVehicleNumberPlateText(veh):gsub('^%s*(.-)%s*$', '%1') ~= plate then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_verify_failed'), 'error')
        return
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 5.0 then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_too_far'), 'error')
        return
    end

    if not Config.RequirePhysicalKey then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_not_required'), 'error')
        return
    end

    if not HasDecoderKit(src) then
        Notify(src, T('label_electronic_decoder'), T('error_need_decoder_kit'), 'error')
        return
    end

    local registration = GetVehicleRegistration(plate)
    if not registration then
        Notify(src, T('label_electronic_decoder'), T('error_decoder_unregistered_vehicle'), 'error')
        return
    end

    local token = math.random(100000, 999999)
    ActiveHeists[src] = {
        token = token,
        plate = plate,
        netId = netId,
        heistType = 'decoder',
        startTime = os.time(),
        originalOwnerId = registration[GetOwnerColumn()],
        thiefId = Bridge.GetCitizenID(src)
    }
    TriggerClientEvent('partay_keys:client:StartMinigame', src, token, 'decoder')
end)


local function ProcessBlackmarketSale(src, plate, targetId, price)
    targetId = tonumber(targetId)
    price = tonumber(price)
    if not targetId or not plate or not price or price < 1 then
        Notify(src, T('label_blackmarket'), T('error_sale_contract_process'), 'error')
        return
    end

    local sellerName = GetPlayerName(src) or ('Player %s'):format(src)
    local buyerName = GetPlayerName(targetId) or ('Player %s'):format(targetId)
    local registration = GetVehicleRegistration(plate)
    local sellerCitizenId = Bridge.GetCitizenID(src)
    local buyerCitizenId = Bridge.GetCitizenID(targetId)

    if not registration then
        Notify(src, T('label_blackmarket'), T('error_sale_unregistered_vehicle'), 'error')
        Notify(targetId, T('label_blackmarket'), T('error_sale_contract_incomplete'), 'error')
        return
    end

    if not sellerCitizenId or not buyerCitizenId then
        Notify(src, T('label_blackmarket'), T('error_sale_party_verify'), 'error')
        Notify(targetId, T('label_blackmarket'), T('error_sale_party_verify'), 'error')
        return
    end

    local sellerPed = GetPlayerPed(src)
    local buyerPed = GetPlayerPed(targetId)
    if not sellerPed or sellerPed == 0 or not buyerPed or buyerPed == 0 or #(GetEntityCoords(sellerPed) - GetEntityCoords(buyerPed)) > (Config.Heist.MaxSaleDistance or 5.0) + 1.0 then
        Notify(src, T('label_blackmarket'), T('error_sale_buyer_too_far_seller'), 'error')
        Notify(targetId, T('label_blackmarket'), T('error_sale_buyer_too_far_buyer'), 'error')
        return
    end

    if registration.possession_id ~= sellerCitizenId then
        Notify(src, T('label_blackmarket'), T('error_sale_seller_not_possession'), 'error')
        Notify(targetId, T('label_blackmarket'), T('error_sale_seller_lost_possession'), 'error')
        return
    end

    if not Bridge.HasCurrency(targetId, Config.Heist.BlackmarketCurrency, price) then
        if Config.Items.SaleContract then
            Bridge.AddInventoryItem(src, Config.Items.SaleContract, 1)
        end

        Notify(targetId, T('label_blackmarket'), T('error_sale_buyer_insufficient_currency'), 'error')
        Notify(src, T('label_blackmarket'), T('error_sale_contract_returned'), 'error')
        return
    end

    local sellerItems = GetInventoryItems(src)
    local keyMetadata = nil
    local keyItemName = nil
    for _, item in pairs(sellerItems) do
        local itemName = item.name or item.item
        if PartayKeys_IsKeyItem(itemName) then
            local metadata = item.metadata or item.info
            if metadata and metadata.plate == plate then
                keyMetadata = metadata
                keyItemName = itemName
                break
            end
        end
    end

    if not keyMetadata then
        Notify(src, T('label_blackmarket'), T('error_sale_seller_missing_key'), 'error')
        Notify(targetId, T('label_blackmarket'), T('error_sale_key_unavailable'), 'error')
        return
    end

    if not Bridge.RemoveCurrency(targetId, Config.Heist.BlackmarketCurrency, price) then
        Notify(targetId, T('label_blackmarket'), T('error_payment_process_failed'), 'error')
        Notify(src, T('label_blackmarket'), T('error_sale_payment_process_failed'), 'error')
        return
    end

    Bridge.AddCurrency(src, Config.Heist.BlackmarketCurrency, price)

    keyMetadata.possession_id = buyerCitizenId
    keyMetadata.current_possession_id = buyerCitizenId
    keyMetadata.original_owner_id = keyMetadata.original_owner_id or registration[GetOwnerColumn()]
    keyMetadata.stolen = true
    keyMetadata.key_tier = PartayKeys_GetKeyTierFromMetadata(keyMetadata, keyItemName)
    keyMetadata.key_version = tonumber(registration.key_version) or tonumber(keyMetadata.key_version) or 1
    Bridge.AddInventoryItem(targetId, PartayKeys_GetKeyItemForTier(keyMetadata.key_tier), 1, keyMetadata)

    local storage = GetVehicleStorage()
    MySQL.Async.execute(('UPDATE %s SET possession_id = ? WHERE plate = ?'):format(storage.tableSql), {buyerCitizenId, plate})
    SetLiveVehiclePossession(plate, buyerCitizenId, keyMetadata.original_owner_id)

    Notify(src, T('label_blackmarket'), T('success_sale_seller', { price = price, buyer = buyerName }), 'success')
    Notify(targetId, T('label_blackmarket'), T('success_sale_buyer', { plate = plate }), 'success')

    exports.partay_keys:SendAuditLog('Blackmarket Sale', ('Player %s sold stolen vehicle %s to Player %s for %s'):format(sellerName, plate, buyerName, price), 'info')
end

AddEventHandler('partay_keys:server:ProcessBlackmarketSaleInternal', function(sellerId, plate, targetId, price)
    ProcessBlackmarketSale(sellerId, plate, targetId, price)
end)
