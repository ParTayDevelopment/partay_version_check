-- [[ Core Keybinds & Interactions ]] --

local engineToggleCommand = 'partay_toggle_engine'
local fobCommand = Config.FobCommand or 'keyfob'
local keyMenuCommand = Config.KeyMenuCommand or 'keys'
local lockCommand = 'togglelock'

local lockHotkey = Config.LockHotkey or Config.UniversalHotkey or 'U'
local lastLockUse = 0
local proximityKeyTargets = {}
local proximityKeyState = {}
local proximityKeyRefreshAt = 0

local function TrimPlate(plate)
    return plate and tostring(plate):gsub('^%s*(.-)%s*$', '%1') or nil
end

local function IsLockedState(lockState)
    return lockState == 2 or lockState == 4 or lockState == 7
end

local function RefreshProximityKeyTargets()
    local now = GetGameTimer()
    if now < proximityKeyRefreshAt then return end
    proximityKeyRefreshAt = now + 30000

    CreateThread(function()
        local ok, targets = pcall(function()
            return lib.callback.await('partay_keys:server:GetProximityKeyTargets', false)
        end)

        proximityKeyTargets = ok and type(targets) == 'table' and targets or {}
    end)
end

local function FindVehicleByPlateNear(coords, plate, radius)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return 0, nil end

    local bestVehicle = 0
    local bestDistance = nil
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and TrimPlate(GetVehicleNumberPlateText(vehicle)) == plate then
            local distance = #(coords - GetEntityCoords(vehicle))
            if distance <= radius and (not bestDistance or distance < bestDistance) then
                bestVehicle = vehicle
                bestDistance = distance
            end
        end
    end

    return bestVehicle, bestDistance
end

local function RunProximityKeyTick()
    RefreshProximityKeyTargets()
    if #proximityKeyTargets < 1 then return 1500 end

    local ped = cache.ped or PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= 0 then return 1500 end

    local coords = GetEntityCoords(ped)
    for _, target in ipairs(proximityKeyTargets) do
        local unlockDistance = tonumber(target.unlockDistance) or 4.0
        local lockDistance = math.max(unlockDistance + 1.0, tonumber(target.lockDistance) or 8.0)
        local vehicle, distance = FindVehicleByPlateNear(coords, target.plate, lockDistance + 8.0)
        local state = proximityKeyState[target.plate] or { locked = nil, cooldown = 0 }
        proximityKeyState[target.plate] = state

        if vehicle ~= 0 and distance then
            local now = GetGameTimer()
            local lockState = Entity(vehicle).state.lockState or GetVehicleDoorLockStatus(vehicle)
            if distance <= unlockDistance and state.locked ~= false and now >= state.cooldown and lockState ~= 1 then
                state.locked = false
                state.cooldown = now + 2500
                TriggerServerEvent('partay_keys:server:FobAction', 'unlock', VehToNet(vehicle), 'proximity')
            elseif distance >= lockDistance and state.locked ~= true and now >= state.cooldown and not IsLockedState(lockState) then
                state.locked = true
                state.cooldown = now + 2500
                TriggerServerEvent('partay_keys:server:FobAction', 'lock', VehToNet(vehicle), 'proximity')
            end
        else
            state.locked = nil
        end
    end

    return 750
end

local function PlayConfiguredAnimation(anim)
    local ped = cache.ped or PlayerPedId()
    if not anim then return end

    lib.requestAnimDict(anim.dict, 1000)
    TaskPlayAnim(ped, anim.dict, anim.name, 8.0, 8.0, anim.duration or 800, anim.flags or 48, 1, false, false, false)
end

local function OpenKeyShareMenu(plate, possession_id)
    local ped = cache.ped or PlayerPedId()
    local nearby = lib.getNearbyPlayers(GetEntityCoords(ped), Config.KeyHandoffRadius or 3.0, false)

    if #nearby == 0 then
        Notify(locale('label_key_share'), locale('error_no_players'), 'error')
        return
    end

    local options = {}
    for _, player in ipairs(nearby) do
        local serverId = GetPlayerServerId(player.id)
        table.insert(options, {
            title = player.name or locale('label_player_with_id', { id = serverId }),
            description = locale('description_share_key'),
            onSelect = function()
                TriggerServerEvent('partay_keys:server:GiveKeyCopy', serverId, plate, possession_id)
            end
        })
    end

    lib.registerContext({
        id = 'partay_share_menu',
        title = locale('menu_select_key_share_player'),
        options = options
    })
    lib.showContext('partay_share_menu')
end

local function FormatCurrency(amount)
    return tostring(tonumber(amount) or 0)
end

local function OpenPaymentMenu(menuId, title, price, onCash, onBank, parentMenu)
    lib.registerContext({
        id = menuId,
        title = title,
        menu = parentMenu,
        options = {
            {
                title = locale('menu_cash_price', { price = FormatCurrency(price) }),
                icon = 'money-bill',
                onSelect = onCash
            },
            {
                title = locale('menu_bank_price', { price = FormatCurrency(price) }),
                icon = 'building-columns',
                onSelect = onBank
            }
        }
    })
    lib.showContext(menuId)
end

-- Engine Toggle Override
RegisterCommand(engineToggleCommand, function()
    local ped = cache.ped or PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    
    if veh and veh ~= 0 then
        local isRunning = GetIsVehicleEngineRunning(veh)
        if not isRunning and PartayKeysIsIgnitionLocked and PartayKeysIsIgnitionLocked(veh) then
            Notify('Ignition Locked', 'Use a wiring kit to bypass this ignition.', 'error')
            return
        end

        SetVehicleEngineOn(veh, not isRunning, true, true)
        
        if not isRunning then
            Notify('Engine', 'Engine Started', 'success')
        else
            Notify('Engine', 'Engine Stopped', 'error')
        end
    end
end)
RegisterKeyMapping(engineToggleCommand, 'Toggle Vehicle Engine', 'keyboard', Config.EngineHotkey or 'G')

-- Key Fob UI Command
RegisterCommand(fobCommand, function()
    TriggerEvent('partay_keys:client:OpenFobUI')
end)

local function GetFobBrandFromMetadata(metadata)
    if type(metadata) ~= 'table' then return nil end

    local label = metadata.vehicle_label or metadata.brand or metadata.make or metadata.model_name
    if label and label ~= '' then return label end

    if metadata.label and metadata.label ~= '' then
        return metadata.label:gsub('%s+[Kk]ey$', '')
    end

    return nil
end

local function FindVehicleByKeyMetadata(metadata, fallbackDistance)
    local ped = cache.ped or PlayerPedId()
    local coords = GetEntityCoords(ped)

    if type(metadata) == 'table' and metadata.plate then
        local plate = tostring(metadata.plate):gsub('^%s*(.-)%s*$', '%1')
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            local vehiclePlate = GetVehicleNumberPlateText(vehicle)
            vehiclePlate = vehiclePlate and vehiclePlate:gsub('^%s*(.-)%s*$', '%1')
            if vehiclePlate == plate and #(coords - GetEntityCoords(vehicle)) <= (fallbackDistance or 25.0) then
                return vehicle
            end
        end
    end

    return lib.getClosestVehicle(coords, fallbackDistance or 10.0, false)
end

local function GetDriverDoorHandleCoords(vehicle)
    local boneNames = { 'handle_dside_f', 'door_dside_f', 'window_lf' }
    for _, boneName in ipairs(boneNames) do
        local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
        if boneIndex ~= -1 then
            return GetWorldPositionOfEntityBone(vehicle, boneIndex)
        end
    end

    return GetOffsetFromEntityInWorldCoords(vehicle, -0.95, 0.15, 0.15)
end

local function MoveToDriverDoorHandle(vehicle)
    local ped = cache.ped or PlayerPedId()
    local handleCoords = GetDriverDoorHandleCoords(vehicle)
    local vehicleCoords = GetEntityCoords(vehicle)
    local approach = handleCoords + (handleCoords - vehicleCoords) * 0.35
    local heading = GetHeadingFromVector_2d(handleCoords.x - approach.x, handleCoords.y - approach.y)

    TaskGoStraightToCoord(ped, approach.x, approach.y, approach.z, 1.0, 1600, heading, 0.08)

    local timeout = GetGameTimer() + 1800
    while GetGameTimer() < timeout do
        if #(GetEntityCoords(ped) - approach) <= 0.32 then break end
        Wait(50)
    end

    ClearPedTasks(ped)
    SetEntityHeading(ped, heading)
    TaskTurnPedToFaceCoord(ped, handleCoords.x, handleCoords.y, handleCoords.z, 450)
    Wait(250)
end

local function PlayBlockingAnimation(anim, fallbackDuration)
    if not anim or not anim.dict or not anim.name then return false end

    local ped = cache.ped or PlayerPedId()
    local duration = tonumber(anim.duration) or fallbackDuration or 800
    lib.requestAnimDict(anim.dict, 1000)
    TaskPlayAnim(ped, anim.dict, anim.name, 8.0, 8.0, duration, anim.flags or 48, 0, false, false, false)
    Wait(duration)
    StopAnimTask(ped, anim.dict, anim.name, 1.0)
    return true
end

function PartayKeysPlayBasicKeyAnimation(vehicle)
    local ped = cache.ped or PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    MoveToDriverDoorHandle(vehicle)

    local turnAnim = Animations and (Animations.BasicKeyTurn or Animations.FobPress)

    if PartayKeysShowHandProp then
        PartayKeysShowHandProp('fob')
    end

    PlayBlockingAnimation(turnAnim, 900)

    if PartayKeysClearHandProp then
        PartayKeysClearHandProp()
    end

    ClearPedTasks(ped)
end

RegisterNetEvent('partay_keys:client:UseBasicKey', function(metadata)
    local veh = FindVehicleByKeyMetadata(metadata, 25.0)
    if not veh or veh == 0 then
        Notify('Basic Key', 'No keyed vehicle in range.', 'error')
        return
    end

    PartayKeysPlayBasicKeyAnimation(veh)
    TriggerServerEvent('partay_keys:server:FobAction', 'toggle', VehToNet(veh), 'basic_key_preanimated')
end)

RegisterNetEvent('partay_keys:client:OpenFobUI', function(metadata, displayOnly, itemSlot)
    if PartayKeysDebugItemUse then
        PartayKeysDebugItemUse(('OpenFobUI received displayOnly=%s itemSlot=%s metadataPlate=%s tier=%s fobOpen=%s activeItem=%s'):format(
            tostring(displayOnly),
            tostring(itemSlot),
            tostring(type(metadata) == 'table' and metadata.plate),
            tostring(type(metadata) == 'table' and metadata.key_tier),
            tostring(PartayKeysIsFobUiOpen and PartayKeysIsFobUiOpen()),
            tostring(PartayKeysIsActiveItemUi and PartayKeysIsActiveItemUi())
        ))
    end

    if PartayKeysIsFobUiOpen and PartayKeysIsFobUiOpen() then
        if PartayKeysDebugItemUse then PartayKeysDebugItemUse('OpenFobUI toggling existing fob closed') end
        PartayKeysCloseFobUi()
        return
    end

    if PartayKeysIsActiveItemUi and PartayKeysIsActiveItemUi() then
        if PartayKeysDebugItemUse then PartayKeysDebugItemUse('OpenFobUI closing other active item UI before opening fob') end
        PartayKeysCloseItemUi()
    end

    local ped = cache.ped or PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local brandName = GetFobBrandFromMetadata(metadata)
    
    if veh == 0 then 
        veh = lib.getClosestVehicle(GetEntityCoords(ped), 5.0, false) 
    end
    
    local hasDisplayMetadata = type(metadata) == 'table' and metadata.plate
        and PartayKeys_KeyTierHasCapability(metadata.key_tier or Config.DefaultKeyTier or 'smart', 'nui')

    if (veh and veh ~= 0) or (displayOnly and type(metadata) == 'table') or hasDisplayMetadata then
        if not brandName then
            if veh and veh ~= 0 then
                brandName = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
                if brandName == 'NULL' then brandName = 'CUSTOM' end
            else
                brandName = 'UNKNOWN'
            end
        end
        
        PartayKeysActiveFobMetadata = type(metadata) == 'table' and metadata or nil
        PartayKeysFobOpen = true
        PartayKeysSetActiveItemUi('fob', itemSlot)
        if PartayKeysDebugItemUse then
            PartayKeysDebugItemUse(('OpenFobUI opening veh=%s displayOnly=%s storedSlot=%s brand=%s'):format(tostring(veh), tostring(displayOnly), tostring(itemSlot), tostring(brandName)))
        end
        PartayKeysShowHandProp('fob')
        PartayKeysOpenNui(true)
        SendNUIMessage({
            action = 'openFob',
            brand = brandName,
            plate = type(metadata) == 'table' and metadata.plate or nil,
            keyVersion = type(metadata) == 'table' and metadata.key_version or nil,
            keyTier = type(metadata) == 'table' and metadata.key_tier or Config.DefaultKeyTier or 'smart',
            capabilities = type(metadata) == 'table' and metadata.capabilities or nil,
            token = PartayKeysCreateNuiToken('fob')
        })
    else
        PartayKeysFobOpen = false
        PartayKeysActiveFobMetadata = nil
        PartayKeysSetActiveItemUi(nil)
        PartayKeysClearNuiToken('fob')
        if PartayKeysDebugItemUse then PartayKeysDebugItemUse('OpenFobUI failed no vehicle/no display metadata') end
        Notify('Error', 'No vehicle nearby to interact with.', 'error')
    end
end)

local function GetDisplayKeyMetadata(slot)
    if type(slot) ~= 'table' then return {} end

    local metadata = slot.metadata or slot.info or {}
    if type(metadata) ~= 'table' then metadata = {} end

    local itemName = slot.name or slot.item
    if itemName and not metadata.key_tier then
        metadata.key_tier = PartayKeys_GetKeyTierFromMetadata(metadata, itemName)
    end

    return metadata
end

local function GetDisplayKeySlot(itemData, slotData)
    if PartayKeysDebugItemUse then
        PartayKeysDebugItemUse(('DisplayKey slot resolver itemDataType=%s itemDataSlot=%s slotDataType=%s slotDataSlot=%s'):format(
            type(itemData),
            tostring(type(itemData) == 'table' and itemData.slot or itemData),
            type(slotData),
            tostring(type(slotData) == 'table' and slotData.slot or slotData)
        ))
    end

    if type(slotData) == 'table' then return slotData end
    if type(itemData) == 'table' and itemData.slot then return itemData end

    local slotId = tonumber(slotData) or tonumber(itemData)
    if slotId and GetResourceState('ox_inventory') == 'started' then
        local ok, items = pcall(function()
            return exports.ox_inventory:GetPlayerItems()
        end)

        if ok and type(items) == 'table' then
            if PartayKeysDebugItemUse then PartayKeysDebugItemUse(('DisplayKey slot resolver fetched ox slot=%s found=%s'):format(tostring(slotId), tostring(items[slotId] ~= nil))) end
            return items[slotId]
        end
    end

    return nil
end

local function DisplayKeyFromInventory(itemData, slotData)
    local slot = GetDisplayKeySlot(itemData, slotData)
    local metadata = GetDisplayKeyMetadata(slot)
    if PartayKeysDebugItemUse then
        PartayKeysDebugItemUse(('DisplayKey export resolvedSlot=%s itemName=%s plate=%s tier=%s'):format(
            tostring(type(slot) == 'table' and slot.slot),
            tostring(type(slot) == 'table' and (slot.name or slot.item)),
            tostring(metadata and metadata.plate),
            tostring(metadata and metadata.key_tier)
        ))
    end

    if not PartayKeys_KeyTierHasCapability(metadata.key_tier, 'nui') then
        Notify('Vehicle Key', 'This key does not have a display fob.', 'info')
        return
    end

    TriggerEvent('partay_keys:client:OpenFobUI', metadata, true, type(slot) == 'table' and slot.slot or nil)
end

RegisterNetEvent('partay_keys:client:DisplayKeyItem', DisplayKeyFromInventory)
DisplayKey = DisplayKeyFromInventory
exports('DisplayKey', DisplayKeyFromInventory)

-- Key Management Menu (Key Ring)
RegisterCommand(keyMenuCommand, function()
    -- Request keys from server to build context menu
    TriggerServerEvent('partay_keys:server:RequestKeyMenu')
end)

local function BuildKeyMenuTierOptions()
    local options = {}

    for rank, tier in ipairs(Config.KeyTierOrder or {}) do
        local tierConfig = Config.KeyTiers and Config.KeyTiers[tier]
        if tierConfig then
            local itemName = tierConfig.Item
            options[#options + 1] = {
                tier = tier,
                rank = rank,
                label = tierConfig.UpgradeLabel or tierConfig.Label or tier,
                price = tonumber(tierConfig.UpgradePrice) or 0,
                description = tierConfig.Description or 'Upgrade and re-key this vehicle.',
                image = itemName and ('assets/%s.png'):format(itemName) or nil
            }
        end
    end

    return options
end

RegisterNetEvent('partay_keys:client:OpenKeyMenu', function(keyData)
    if true then
    if type(keyData) ~= 'table' then keyData = {} end

    if PartayKeysIsActiveItemUi and PartayKeysIsActiveItemUi() then
        PartayKeysCloseItemUi()
    end

    if not (keyData.owned or keyData.shared or keyData.stolen or keyData.sharedOut) then
        keyData = {
            owned = {},
            shared = keyData,
            stolen = {},
            sharedOut = {}
        }
    end

    local playerRun = Config.PlayerJobs and Config.PlayerJobs.Locksmith
    local locksmithEnabled = playerRun and playerRun.Enabled == true
    local playerRunEnabled = locksmithEnabled
    local selfService = Config.PlayerJobDefaults
        and Config.PlayerJobDefaults.Locksmith
        and Config.PlayerJobDefaults.Locksmith.SelfService
        or {}
    local locksmithTierServicesEnabled = (locksmithEnabled or playerRunEnabled) and selfService.EnableKeyTierServices ~= false
    keyData.action = 'openKeyMenu'
    keyData.token = PartayKeysCreateNuiToken('key_menu')
    keyData.keyTiers = BuildKeyMenuTierOptions()
    local serviceFees = selfService.ServiceFees or {}
    keyData.rekeyFee = tonumber(serviceFees.ReKey) or 0
    keyData.menuRekeyAllowed = not (Config.Heist and Config.Heist.ReKeyRequiresLocksmith and locksmithEnabled)
    keyData.copyAllowed = not playerRunEnabled
    keyData.appointmentsAllowed = playerRunEnabled and playerRun.Appointments and playerRun.Appointments.AllowKeyMenuRequest ~= false
    keyData.allowTierChange = not locksmithTierServicesEnabled
    keyData.allowUpgrade = keyData.allowTierChange

    PartayKeysShowHandProp('tablet')
    PartayKeysSetActiveItemUi('key_menu')
    PartayKeysOpenNui(false, true)
    SendNUIMessage(keyData)
    else

    if type(keyData) == 'table' and (keyData.owned or keyData.shared or keyData.stolen or keyData.sharedOut) then
        local function keyDescription(key)
            local physical = key.has_physical and locale('label_physical_key_present') or locale('label_no_physical_key_inventory')
            local tier = key.key_tier or 'smart'
            return locale('description_key_record', {
                physical = physical,
                tier = tier,
                version = key.key_version or 'N/A'
            })
        end

        local function openRecordList(menuId, title, records, action)
            local options = {}
            if #records == 0 then
                options[#options + 1] = { title = locale('menu_none_found'), disabled = true }
            else
                for _, key in ipairs(records) do
                    options[#options + 1] = {
                        title = key.label or locale('label_plate_value', { plate = key.plate or locale('label_unknown') }),
                        description = keyDescription(key),
                        icon = key.has_physical and 'key' or 'key-skeleton',
                        onSelect = action and function()
                            action(key)
                        end or nil,
                        disabled = action == nil
                    }
                end
            end

            lib.registerContext({
                id = menuId,
                title = title,
                menu = 'partay_key_menu',
                options = options
            })
            lib.showContext(menuId)
        end

        local function openKeyholderList(key)
            local keyholders = lib.callback.await('partay_keys:server:GetVehicleKeyholders', false, key.plate) or {}
            local options = {}

            if #keyholders == 0 then
                options[#options + 1] = { title = locale('menu_no_shared_keyholders'), disabled = true }
            else
                for _, holder in ipairs(keyholders) do
                    options[#options + 1] = {
                        title = holder.holder_name or locale('label_unknown_holder'),
                        description = locale('description_keyholder_record', {
                            type = holder.key_type or 'key',
                            version = holder.key_version or 'N/A'
                        }),
                        icon = holder.key_type == 'shared' and 'user' or 'key',
                        disabled = true
                    }
                end
            end

            lib.registerContext({
                id = 'partay_keyholders_menu',
                title = locale('menu_keyholders'),
                menu = 'partay_owned_vehicle_menu',
                options = options
            })
            lib.showContext('partay_keyholders_menu')
        end

        local function openKeyUpgradeMenu(key)
            local options = {}
            for _, tier in ipairs(Config.KeyTierOrder or {}) do
                local tierConfig = Config.KeyTiers and Config.KeyTiers[tier]
                if tierConfig then
                    local title = tierConfig.UpgradeLabel or tierConfig.Label or tier
                    local price = tonumber(tierConfig.UpgradePrice) or 0
                    options[#options + 1] = {
                        title = title,
                        description = key.key_tier == tier and locale('description_current_key_system') or locale('description_price', { price = FormatCurrency(price) }),
                        icon = key.key_tier == tier and 'check' or 'key',
                        disabled = key.key_tier == tier,
                        onSelect = function()
                            OpenPaymentMenu(
                                'partay_key_upgrade_payment_' .. tostring(tier),
                                title,
                                price,
                                function() TriggerServerEvent('partay_keys:server:UpgradeKeySystem', key.plate, tier, 'cash') end,
                                function() TriggerServerEvent('partay_keys:server:UpgradeKeySystem', key.plate, tier, 'bank') end,
                                'partay_key_upgrade_menu'
                            )
                        end
                    }
                end
            end

            lib.registerContext({
                id = 'partay_key_upgrade_menu',
                title = locale('menu_upgrade_key_system'),
                menu = 'partay_owned_vehicle_menu',
                options = options
            })
            lib.showContext('partay_key_upgrade_menu')
        end

        local function openOwnedVehicleMenu(key)
            local options = {
                {
                    title = locale('menu_view_keyholders'),
                    description = locale('description_view_keyholders'),
                    icon = 'users',
                    onSelect = function()
                        openKeyholderList(key)
                    end
                },
                {
                    title = locale('menu_give_shared_key'),
                    description = locale('description_give_shared_key'),
                    icon = 'share-nodes',
                    onSelect = function()
                        OpenKeyShareMenu(key.plate, key.possession_id)
                    end
                },
                {
                    title = locale('menu_create_physical_copy'),
                    description = key.has_physical and locale('description_physical_key_exists') or locale('description_create_physical_key'),
                    icon = 'key',
                    disabled = key.has_physical == true,
                    onSelect = function()
                        TriggerServerEvent('partay_keys:server:CreatePhysicalKeyCopy', key.plate)
                    end
                }
            }

            local locksmithEnabled = Config.PlayerJobs and Config.PlayerJobs.Locksmith and Config.PlayerJobs.Locksmith.Enabled == true
            local menuRekeyAllowed = not (Config.Heist and Config.Heist.ReKeyRequiresLocksmith and locksmithEnabled)
            if menuRekeyAllowed then
                options[#options + 1] = {
                    title = locale('menu_rekey_vehicle'),
                    description = locale('description_rekey_vehicle'),
                    icon = 'rotate',
                    onSelect = function()
                        TriggerServerEvent('partay_keys:server:ReKeyVehicle', key.plate)
                    end
                }
            end

            if not locksmithEnabled then
                options[#options + 1] = {
                    title = locale('menu_upgrade_key_system'),
                    description = locale('description_upgrade_key_system'),
                    icon = 'wrench',
                    onSelect = function()
                        openKeyUpgradeMenu(key)
                    end
                }
            end

            lib.registerContext({
                id = 'partay_owned_vehicle_menu',
                title = key.label or locale('label_vehicle_plate', { plate = key.plate or locale('label_unknown') }),
                menu = 'partay_key_owned_menu',
                options = options
            })
            lib.showContext('partay_owned_vehicle_menu')
        end

        local options = {
            {
                title = locale('menu_vehicles_i_own'),
                description = locale('description_vehicle_count', { count = #keyData.owned }),
                icon = 'car',
                onSelect = function()
                    openRecordList('partay_key_owned_menu', locale('menu_vehicles_i_own'), keyData.owned, function(key)
                        openOwnedVehicleMenu(key)
                    end)
                end
            },
            {
                title = locale('menu_shared_keys_i_have'),
                description = locale('description_key_count', { count = #keyData.shared }),
                icon = 'key',
                onSelect = function()
                    openRecordList('partay_key_shared_menu', locale('menu_shared_keys_i_have'), keyData.shared)
                end
            },
            {
                title = locale('menu_keys_i_have_shared'),
                description = locale('description_key_count', { count = #keyData.sharedOut }),
                icon = 'users',
                onSelect = function()
                    openRecordList('partay_key_shared_out_menu', locale('menu_keys_i_have_shared'), keyData.sharedOut, function(key)
                        lib.registerContext({
                            id = 'partay_shared_out_detail_menu',
                            title = key.holder_name or locale('label_shared_keyholder'),
                            menu = 'partay_key_shared_out_menu',
                            options = {
                                {
                                    title = key.label or locale('label_vehicle_plate', { plate = key.plate or locale('label_unknown') }),
                                    description = keyDescription(key),
                                    icon = 'key',
                                    disabled = true
                                }
                            }
                        })
                        lib.showContext('partay_shared_out_detail_menu')
                    end)
                end
            },
            {
                title = locale('menu_stolen_vehicle_keys'),
                description = locale('description_key_count', { count = #keyData.stolen }),
                icon = 'user-secret',
                onSelect = function()
                    openRecordList('partay_key_stolen_menu', locale('menu_stolen_vehicle_keys'), keyData.stolen)
                end
            }
        }

        lib.registerContext({
            id = 'partay_key_menu',
            title = locale('menu_my_key_management'),
            options = options
        })
        lib.showContext('partay_key_menu')
        return
    end

    local options = {}
    
    if #keyData == 0 then
        table.insert(options, { title = locale('menu_no_keys_on_keyring'), disabled = true })
    else
        for _, key in ipairs(keyData) do
            table.insert(options, {
                title = key.label or locale('label_plate_value', { plate = key.plate or locale('label_unknown') }),
                description = locale('description_assigned_holder', { holder = key.possession_id or 'N/A' }),
                icon = 'key',
                onSelect = function()
                    OpenKeyShareMenu(key.plate, key.possession_id)
                end
            })
        end
    end

    lib.registerContext({
        id = 'partay_key_menu',
        title = locale('menu_my_key_ring'),
        options = options
    })
    lib.showContext('partay_key_menu')
    end
end)

RegisterNUICallback('keyMenuAction', function(data, cb)
    if not PartayKeysValidateNuiToken('key_menu', data and data.token) then
        Notify(locale('label_key_management'), locale('error_invalid_key_menu_session'), 'error')
        cb({ ok = false })
        return
    end

    local action = data and data.action
    local plate = data and data.plate

    if action == 'keyholders' then
        cb({ ok = true, keyholders = lib.callback.await('partay_keys:server:GetVehicleKeyholders', false, plate) or {} })
        return
    elseif action == 'share' then
        PartayKeysCloseItemUi('key_menu')
        OpenKeyShareMenu(plate, data.possession_id)
    elseif action == 'copy' then
        local locksmith = Config.PlayerJobs and Config.PlayerJobs.Locksmith
        if locksmith and locksmith.Enabled == true then
            Notify(locale('label_locksmith'), locale('error_locksmith_staff_required'), 'error')
            cb({ ok = false })
            return
        end
        TriggerServerEvent('partay_keys:server:CreatePhysicalKeyCopy', plate)
    elseif action == 'appointment' then
        TriggerServerEvent('partay_keys:server:RequestLocksmithAppointment', plate, data.message)
    elseif action == 'rekey' then
        TriggerServerEvent('partay_keys:server:ReKeyVehicle', plate, data.paymentMethod)
    elseif action == 'upgrade' then
        TriggerServerEvent('partay_keys:server:UpgradeKeySystem', plate, data.tier, data.paymentMethod)
    end

    cb({ ok = true })
end)

-- [[ Lock / Unlock Toggle (Command & Hotkey) ]] --
local function HandleToggleLock()
    local now = GetGameTimer()
    if now - lastLockUse < 1500 then return end
    lastLockUse = now

    local ped = cache.ped or PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    -- 1. Check if inside a vehicle first
    local veh = GetVehiclePedIsIn(ped, false)
    
    -- 2. If not inside, scan proximity
    if not veh or veh == 0 then
        veh = lib.getClosestVehicle(coords, 10.0, false)
    end
    
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        TriggerServerEvent('partay_keys:server:FobAction', 'toggle', VehToNet(veh))
    else
        Notify('Error', 'No vehicle in range.', 'error')
    end
end

RegisterCommand(lockCommand, function()
    HandleToggleLock()
end)
RegisterKeyMapping(lockCommand, 'Toggle Vehicle Locks', 'keyboard', lockHotkey)

CreateThread(function()
    Wait(5000)

    while true do
        Wait(RunProximityKeyTick())
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    pcall(TriggerEvent, 'chat:addSuggestion', '/' .. engineToggleCommand, 'Toggle the current vehicle engine.')
    pcall(TriggerEvent, 'chat:addSuggestion', '/' .. fobCommand, 'Open the key fob interaction UI for nearby vehicles.')
    pcall(TriggerEvent, 'chat:addSuggestion', '/' .. keyMenuCommand, 'Open your key ring to manage and share vehicle keys.')
    pcall(TriggerEvent, 'chat:addSuggestion', '/' .. lockCommand, 'Toggle locks on the nearest vehicle.')
end)
