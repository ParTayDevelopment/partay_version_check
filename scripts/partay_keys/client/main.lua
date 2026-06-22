lib.locale()

local LOCKED = 2
local nativeBlockNotifyAt = 0
local lockedBreakGuardVehicle = 0
local lockedBreakGuardUntil = 0
local lockedBreakGuardThreadActive = false
local hotwireCheckVehicle = 0
local hotwireCheckStartedAt = 0
local hotwireCheckStartedWithEngineRunning = false
local ignitionAccessVehicle = 0
local ignitionAccessPlate = nil
local ignitionAccessPossession = nil
local ignitionAccessRequested = false
local ignitionAccessResolved = false
local ignitionAccessAllowed = false
PartayKeysNuiTokens = PartayKeysNuiTokens or {}
local keepInputNuiOpen = false
local activeItemUi = nil
local activeItemSlot = nil
local activeItemDebugNextAt = 0
local activeItemOpenedAt = 0
local activeItemCloseArmed = false
local activeHandProp = nil
local activeHandPropAnimation = false
local activeHandPropType = nil
local activeHandPropSerial = 0
local nuiBlockedMouseControls = {
    21, -- Sprint
    22, -- Jump
    23, -- Enter vehicle
    30, -- Move left/right
    31, -- Move forward/back
    32, -- Move up
    33, -- Move down
    34, -- Move left
    35, -- Move right
    36, -- Duck
    1, -- Look left/right
    2, -- Look up/down
    14, -- Mouse wheel down
    15, -- Mouse wheel up
    24, -- Attack / left click
    25, -- Aim / right click
    68, -- Vehicle attack
    69, -- Vehicle attack 2
    70, -- Vehicle attack alternate
    71, -- Vehicle accelerate
    72, -- Vehicle brake
    75, -- Vehicle exit
    76, -- Vehicle handbrake
    87, -- Vehicle fly throttle up
    88, -- Vehicle fly throttle down
    89, -- Vehicle fly yaw left
    90, -- Vehicle fly yaw right
    91, -- Vehicle passenger aim
    92, -- Vehicle passenger attack
    140, -- Melee light
    141, -- Melee heavy
    142, -- Melee alternate
    257, -- Attack 2
    263, -- Melee attack 1
    264 -- Melee attack 2
}

local hotbarSlotControls = {
    [1] = 157,
    [2] = 158,
    [3] = 160,
    [4] = 164,
    [5] = 165
}

function PartayKeysDebugItemUse(message)
    if Config and Config.DebugMode then
        print(('^5[ParTay Keys Debug]^3 Item UI: %s^0'):format(tostring(message)))
    end
end

local function SetNuiKeepInput(enabled)
    local keepInputNative = rawget(_G, 'SetNuiFocusKeepInput')
    if keepInputNative then
        keepInputNative(enabled == true)
        return
    end

    Citizen.InvokeNative(0x3FF5E5F8, enabled == true)
end

local handPropConfigKeys = {
    fob = 'Fob',
    tablet = 'Tablet',
    clipboard = 'Clipboard',
    decoder = 'Decoder',
    terminal = 'Terminal'
}

local function GetHandPropConfig(propType)
    local root = Props and Props.Handheld
    if not root or root.Enabled == false then return nil end

    local config = root[handPropConfigKeys[propType] or propType]
    if not config or config.Enabled == false or not config.Model then return nil end

    return {
        model = config.Model,
        bone = config.Bone or 57005,
        pos = config.Pos or vector3(0.0, 0.0, 0.0),
        rot = config.Rot or vector3(0.0, 0.0, 0.0),
        animation = config.Animation
    }
end

function PartayKeysClearHandProp()
    activeHandPropSerial = activeHandPropSerial + 1

    if activeHandProp and DoesEntityExist(activeHandProp) then
        DeleteEntity(activeHandProp)
    end

    if activeHandPropAnimation then
        ClearPedSecondaryTask(cache.ped or PlayerPedId())
    end

    activeHandProp = nil
    activeHandPropAnimation = false
    activeHandPropType = nil
end

function PartayKeysShowHandProp(propType)
    local config = GetHandPropConfig(propType)
    if not config then return end

    PartayKeysClearHandProp()

    local ped = cache.ped or PlayerPedId()
    local model = GetHashKey(config.model)
    lib.requestModel(model, 1000)

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(model, coords.x, coords.y, coords.z + 0.2, true, true, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, config.bone), config.pos.x, config.pos.y, config.pos.z, config.rot.x, config.rot.y, config.rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)

    activeHandProp = prop
    activeHandPropType = propType
    activeHandPropSerial = activeHandPropSerial + 1

    local anim = config.animation and Animations and Animations[config.animation]
    if anim and anim.dict and anim.name then
        lib.requestAnimDict(anim.dict, 1000)
        TaskPlayAnim(ped, anim.dict, anim.name, 4.0, 4.0, -1, anim.flags or 49, 0, false, false, false)
        activeHandPropAnimation = true
    end
end

function PartayKeysShowHandPropOnce(propType, duration)
    if activeHandProp and DoesEntityExist(activeHandProp) then
        PartayKeysClearHandProp()
    end

    PartayKeysShowHandProp(propType)
    if not activeHandProp or not DoesEntityExist(activeHandProp) then return false end

    local serial = activeHandPropSerial
    local propDuration = math.max(250, tonumber(duration) or 1000)
    CreateThread(function()
        Wait(propDuration + 100)
        if activeHandPropSerial == serial and activeHandPropType == propType then
            PartayKeysClearHandProp()
        end
    end)

    return true
end

function PartayKeysOpenNui(keepPlayerInput, keepHandProp)
    SetNuiFocus(true, true)
    keepInputNuiOpen = keepPlayerInput == true
    SetNuiKeepInput(keepInputNuiOpen)
    PartayKeysDebugItemUse(('OpenNui keepPlayerInput=%s focused=%s keepInput=%s'):format(tostring(keepPlayerInput), tostring(IsNuiFocused()), tostring(keepInputNuiOpen)))

    if not keepInputNuiOpen and keepHandProp ~= true then
        PartayKeysClearHandProp()
    end

    if keepInputNuiOpen then
        CreateThread(function()
            for _ = 1, 15 do
                if not keepInputNuiOpen then return end
                SetNuiKeepInput(true)
                Wait(0)
            end
        end)
    end
end

function PartayKeysCloseNui()
    keepInputNuiOpen = false
    SetNuiFocus(false, false)
    SetNuiKeepInput(false)
    PartayKeysClearHandProp()
    PartayKeysDebugItemUse(('CloseNui focused=%s'):format(tostring(IsNuiFocused())))
end

function PartayKeysSetActiveItemUi(uiType, slot)
    activeItemUi = uiType
    activeItemSlot = slot and tonumber(slot) or nil
    activeItemDebugNextAt = 0
    activeItemOpenedAt = uiType and GetGameTimer() or 0
    activeItemCloseArmed = false
    PartayKeysDebugItemUse(('SetActive ui=%s slot=%s control=%s'):format(tostring(activeItemUi), tostring(activeItemSlot), tostring(activeItemSlot and hotbarSlotControls[activeItemSlot])))
end

function PartayKeysIsActiveItemUi(uiType)
    return activeItemUi ~= nil and (not uiType or activeItemUi == uiType)
end

function PartayKeysCloseItemUi(uiType)
    if uiType and activeItemUi ~= uiType then
        PartayKeysDebugItemUse(('CloseItem ignored requested=%s active=%s slot=%s'):format(tostring(uiType), tostring(activeItemUi), tostring(activeItemSlot)))
        return false
    end

    local closingUi = activeItemUi
    local closingSlot = activeItemSlot
    activeItemUi = nil
    activeItemSlot = nil
    activeItemDebugNextAt = 0
    activeItemOpenedAt = 0
    activeItemCloseArmed = false
    PartayKeysDebugItemUse(('CloseItem closing=%s slot=%s'):format(tostring(closingUi), tostring(closingSlot)))
    if closingUi == 'fob' then
        PartayKeysFobOpen = false
        PartayKeysActiveFobMetadata = nil
        PartayKeysClearNuiToken('fob')
    elseif closingUi == 'gps_tablet' then
        PartayKeysClearNuiToken('gps_tablet')
    elseif closingUi == 'signal_finder' then
        PartayKeysClearNuiToken('signal_finder')
    elseif closingUi == 'service_menu' then
        PartayKeysClearNuiToken('service_menu')
    elseif closingUi == 'key_menu' then
        PartayKeysClearNuiToken('key_menu')
    elseif closingUi == 'locksmith_setup' then
        PartayKeysClearNuiToken('locksmith_setup')
    end

    SendNUIMessage({ action = 'closeUI' })
    PartayKeysCloseNui()
    return true
end

function PartayKeysCloseFobUi()
    PartayKeysFobOpen = false
    PartayKeysActiveFobMetadata = nil
    PartayKeysSetActiveItemUi(nil)
    SendNUIMessage({ action = 'closeUI' })
    PartayKeysCloseNui()
    PartayKeysClearNuiToken('fob')
end

function PartayKeysIsFobUiOpen()
    return PartayKeysFobOpen == true
        or PartayKeysActiveFobMetadata ~= nil
        or (PartayKeysNuiTokens and PartayKeysNuiTokens.fob ~= nil)
end

CreateThread(function()
    while true do
        if keepInputNuiOpen then
            for _, control in ipairs(nuiBlockedMouseControls) do
                DisableControlAction(0, control, true)
            end

            if activeItemUi and activeItemSlot then
                local control = hotbarSlotControls[activeItemSlot]
                if control then
                    local released = IsControlJustReleased(0, control)
                    local disabledReleased = IsDisabledControlJustReleased(0, control)
                    local pressed = IsControlPressed(0, control) or IsDisabledControlPressed(0, control)

                    if not activeItemCloseArmed then
                        if GetGameTimer() - activeItemOpenedAt >= 250 and not pressed then
                            activeItemCloseArmed = true
                            if Config and Config.DebugMode then
                                PartayKeysDebugItemUse(('Hotkey close armed ui=%s slot=%s control=%s'):format(tostring(activeItemUi), tostring(activeItemSlot), tostring(control)))
                            end
                        elseif released or disabledReleased then
                            if Config and Config.DebugMode then
                                PartayKeysDebugItemUse(('Ignored opener release ui=%s slot=%s control=%s age=%s released=%s disabledReleased=%s pressed=%s'):format(tostring(activeItemUi), tostring(activeItemSlot), tostring(control), tostring(GetGameTimer() - activeItemOpenedAt), tostring(released), tostring(disabledReleased), tostring(pressed)))
                            end
                        end

                    elseif released or disabledReleased then
                        PartayKeysDebugItemUse(('Hotkey close detected ui=%s slot=%s control=%s released=%s disabledReleased=%s'):format(tostring(activeItemUi), tostring(activeItemSlot), tostring(control), tostring(released), tostring(disabledReleased)))
                        PartayKeysCloseItemUi()
                    elseif Config and Config.DebugMode and GetGameTimer() >= activeItemDebugNextAt then
                        activeItemDebugNextAt = GetGameTimer() + 3000
                        PartayKeysDebugItemUse(('Watcher active ui=%s slot=%s control=%s focused=%s keepInput=%s'):format(tostring(activeItemUi), tostring(activeItemSlot), tostring(control), tostring(IsNuiFocused()), tostring(keepInputNuiOpen)))
                    end
                elseif Config and Config.DebugMode and GetGameTimer() >= activeItemDebugNextAt then
                    activeItemDebugNextAt = GetGameTimer() + 3000
                    PartayKeysDebugItemUse(('Watcher has no mapped control ui=%s slot=%s'):format(tostring(activeItemUi), tostring(activeItemSlot)))
                end
            end

            Wait(0)
        else
            Wait(250)
        end
    end
end)

function PartayKeysCreateNuiToken(scope)
    local token = ('%s:%s:%s:%s'):format(scope or 'ui', GetGameTimer(), math.random(100000, 999999), math.random(100000, 999999))
    PartayKeysNuiTokens[scope] = token
    return token
end

function PartayKeysValidateNuiToken(scope, token)
    return token and PartayKeysNuiTokens[scope] and token == PartayKeysNuiTokens[scope]
end

function PartayKeysClearNuiToken(scope)
    PartayKeysNuiTokens[scope] = nil
end

local function HasIgnitionStep(vehicle)
    local class = GetVehicleClass(vehicle)
    return class ~= 13
end

local function ResetIgnitionAccess(vehicle, plate, possessionId)
    ignitionAccessVehicle = vehicle or 0
    ignitionAccessPlate = plate
    ignitionAccessPossession = possessionId
    ignitionAccessRequested = false
    ignitionAccessResolved = false
    ignitionAccessAllowed = false
end

local function ResolveIgnitionAccess(vehicle, plate, possessionId)
    if ignitionAccessVehicle ~= vehicle or ignitionAccessPlate ~= plate or ignitionAccessPossession ~= possessionId then
        ResetIgnitionAccess(vehicle, plate, possessionId)
    end

    if ignitionAccessRequested then return end
    ignitionAccessRequested = true

    CreateThread(function()
        local allowed = lib.callback.await('partay_keys:server:HasIgnitionAccess', false, VehToNet(vehicle), plate) == true
        if ignitionAccessVehicle == vehicle and ignitionAccessPlate == plate and ignitionAccessPossession == possessionId then
            ignitionAccessAllowed = allowed
            ignitionAccessResolved = true
        end
    end)
end

function PartayKeysIsIgnitionLocked(vehicle)
    if not vehicle or vehicle == 0 or not HasIgnitionStep(vehicle) then return false end
    if hotwireCheckVehicle ~= vehicle then return false end
    if hotwireCheckStartedWithEngineRunning then return false end
    return not (ignitionAccessResolved and ignitionAccessAllowed)
end

local function CanMountWithoutLockpick(vehicle)
    local class = GetVehicleClass(vehicle)
    return class == 8 or class == 13
end

local function IsLockedState(lockState)
    return lockState == 2 or lockState == 4 or lockState == 7
end

local function ApplyClientLockState(vehicle, lockState)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    SetVehicleDoorsLocked(vehicle, lockState)
    SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), IsLockedState(lockState))
end

local function ApplyNpcLockChance(vehicle)
    if not vehicle or vehicle == 0 then return end
    if Entity(vehicle).state.npcLockChanceRolled then return end
    if Entity(vehicle).state.possession_id then return end

    Entity(vehicle).state:set('npcLockChanceRolled', true, true)

    if not Config.Heist.NPCVehicles or not Config.Heist.NPCVehicles.EnableLockChance then return end

    local lockedChance = tonumber(Config.Heist.NPCVehicles.LockedChance) or 0
    lockedChance = math.max(0, math.min(100, lockedChance))
    local lockState = (math.random(1, 100) <= lockedChance) and LOCKED or 1

    Entity(vehicle).state:set('lockState', lockState, true)
    ApplyClientLockState(vehicle, lockState)
end

local function NotifyNativeBlock(title, description)
    local now = GetGameTimer()
    if now - nativeBlockNotifyAt < 3000 then return end
    nativeBlockNotifyAt = now

    Notify(title, description, 'error')
end

local function RestoreVehicleWindows(vehicle)
    for window = 0, 7 do
        if not IsVehicleWindowIntact(vehicle, window) then
            FixVehicleWindow(vehicle, window)
        end
    end
end

local function GuardLockedDoorAttempt(vehicle)
    if not vehicle or vehicle == 0 then return end

    DisableControlAction(0, 24, true) -- INPUT_ATTACK
    DisableControlAction(0, 25, true) -- INPUT_AIM
    DisableControlAction(0, 68, true) -- INPUT_VEH_ATTACK
    DisableControlAction(0, 69, true) -- INPUT_VEH_ATTACK2
    DisableControlAction(0, 70, true) -- INPUT_VEH_ATTACK3
    DisableControlAction(0, 140, true) -- INPUT_MELEE_ATTACK_LIGHT
    DisableControlAction(0, 141, true) -- INPUT_MELEE_ATTACK_HEAVY
    DisableControlAction(0, 142, true) -- INPUT_MELEE_ATTACK_ALTERNATE
    DisableControlAction(0, 257, true) -- INPUT_ATTACK2

    lockedBreakGuardVehicle = vehicle
    lockedBreakGuardUntil = GetGameTimer() + 2200
    SetVehicleCanBreak(vehicle, false)
    SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), true)
    RestoreVehicleWindows(vehicle)

    if lockedBreakGuardThreadActive then return end
    lockedBreakGuardThreadActive = true

    CreateThread(function()
        while GetGameTimer() < lockedBreakGuardUntil do
            if lockedBreakGuardVehicle ~= 0 and DoesEntityExist(lockedBreakGuardVehicle) then
                SetVehicleCanBreak(lockedBreakGuardVehicle, false)
                SetVehicleDoorsLockedForPlayer(lockedBreakGuardVehicle, PlayerId(), true)
                RestoreVehicleWindows(lockedBreakGuardVehicle)
            end
            Wait(0)
        end

        if lockedBreakGuardVehicle ~= 0 and DoesEntityExist(lockedBreakGuardVehicle) then
            SetVehicleCanBreak(lockedBreakGuardVehicle, true)
            ApplyClientLockState(lockedBreakGuardVehicle, Entity(lockedBreakGuardVehicle).state.lockState or GetVehicleDoorLockStatus(lockedBreakGuardVehicle))
        end

        lockedBreakGuardVehicle = 0
        lockedBreakGuardUntil = 0
        lockedBreakGuardThreadActive = false
    end)
end

RegisterNetEvent('partay_keys:client:TryLockedDoor', function(netId)
    local vehicle = netId and NetToVeh(netId) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local ped = cache.ped or PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 8.0 then return end

    ApplyClientLockState(vehicle, LOCKED)
    GuardLockedDoorAttempt(vehicle)
    TaskEnterVehicle(ped, vehicle, 1800, -1, 1.0, 1, 0)
end)

-- [[ Leave Engine Running (Native Override) ]] --
if Config.LeaveEngineRunning then
    local exitPressedAt = 0
    local exitVehicle = 0
    local exitWasRunning = false
    local exitShouldLeaveRunning = false
    local holdToLeaveRunningMs = Config.LeaveEngineRunningHoldTime or 650

    CreateThread(function()
        while true do
            local sleep = 250
            local ped = cache.ped or PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                sleep = 0

                if IsControlJustPressed(0, 75) then -- INPUT_VEH_EXIT
                    exitPressedAt = GetGameTimer()
                    exitVehicle = veh
                    exitWasRunning = GetIsVehicleEngineRunning(veh)
                    exitShouldLeaveRunning = false
                elseif IsControlJustReleased(0, 75) and exitVehicle == veh then
                    if exitWasRunning and (GetGameTimer() - exitPressedAt) >= holdToLeaveRunningMs then
                        exitShouldLeaveRunning = true
                    else
                        exitVehicle = 0
                        exitWasRunning = false
                        exitShouldLeaveRunning = false
                    end
                end
            elseif exitVehicle ~= 0 then
                sleep = 0

                local heldLongEnough = exitPressedAt ~= 0 and (GetGameTimer() - exitPressedAt) >= holdToLeaveRunningMs

                if exitShouldLeaveRunning or (exitWasRunning and heldLongEnough) then
                    local targetVeh = exitVehicle

                    if DoesEntityExist(targetVeh) then
                        CreateThread(function()
                            Wait(250)

                            local engineConfirmed = false
                            for _ = 1, 4 do
                                if DoesEntityExist(targetVeh) then
                                    SetVehicleEngineOn(targetVeh, true, true, true)
                                    if GetIsVehicleEngineRunning(targetVeh) then
                                        engineConfirmed = true
                                        break
                                    end
                                end
                                Wait(250)
                            end

                            if engineConfirmed then
                                local playerPed = cache.ped or PlayerPedId()
                                if not IsPedInAnyVehicle(playerPed, false) then
                                    ClearPedTasks(playerPed)
                                end
                            end
                        end)
                    end

                    exitVehicle = 0
                    exitPressedAt = 0
                    exitWasRunning = false
                    exitShouldLeaveRunning = false
                elseif not IsControlPressed(0, 75) then
                    exitVehicle = 0
                    exitPressedAt = 0
                    exitWasRunning = false
                    exitShouldLeaveRunning = false
                end
            else
                exitPressedAt = 0
                exitWasRunning = false
                exitShouldLeaveRunning = false
            end

            Wait(sleep)
        end
    end)
end

-- [[ State Bag Listener ]] --
AddStateBagChangeHandler('lockState', nil, function(bagName, _key, value, _reserved, _replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 then return end
    if Config.DebugMode then
        print(('^5[ParTay Keys Debug]^2 Client State-Bag Update - LockState: %s^0'):format(value))
    end
    ApplyClientLockState(entity, value)
end)

CreateThread(function()
    while true do
        local sleep = 500
        local ped = cache.ped or PlayerPedId()

        if Config.Heist.EnableLockpicking then
            local tryingVehicle = GetVehiclePedIsTryingToEnter(ped)
            if tryingVehicle and tryingVehicle ~= 0 then
                ApplyNpcLockChance(tryingVehicle)
                local lockState = Entity(tryingVehicle).state.lockState or GetVehicleDoorLockStatus(tryingVehicle)
                if lockState == 2 or lockState == 4 or lockState == 7 then
                    if CanMountWithoutLockpick(tryingVehicle) then
                        Entity(tryingVehicle).state:set('lockState', 1, true)
                        ApplyClientLockState(tryingVehicle, 1)
                    else
                        sleep = 0
                        ApplyClientLockState(tryingVehicle, LOCKED)
                        GuardLockedDoorAttempt(tryingVehicle)
                        NotifyNativeBlock('Vehicle Locked', 'Use a lockpick to open this vehicle lock.')
                    end
                end
            end
        end

        if Config.Heist.EnableHotwiring then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                if hotwireCheckVehicle ~= vehicle then
                    hotwireCheckVehicle = vehicle
                    hotwireCheckStartedAt = GetGameTimer()
                    hotwireCheckStartedWithEngineRunning = GetIsVehicleEngineRunning(vehicle)
                end

                local possessionId = Entity(vehicle).state.possession_id
                local plate = GetVehicleNumberPlateText(vehicle)
                ResolveIgnitionAccess(vehicle, plate, possessionId)

                local needsIgnitionBypass = HasIgnitionStep(vehicle)
                local hasIgnitionAccess = ignitionAccessResolved and ignitionAccessAllowed
                if needsIgnitionBypass and not hotwireCheckStartedWithEngineRunning and not hasIgnitionAccess then
                    sleep = 0
                    DisableControlAction(0, 71, true) -- INPUT_VEH_ACCELERATE
                    DisableControlAction(0, 72, true) -- INPUT_VEH_BRAKE
                    DisableControlAction(0, 76, true) -- INPUT_VEH_HANDBRAKE
                    SetVehicleEngineOn(vehicle, false, true, true)
                    SetVehicleUndriveable(vehicle, true)

                    local warningDelay = Config.Heist.HotwireWarningDelay or 3500
                    if GetGameTimer() - hotwireCheckStartedAt >= warningDelay then
                        NotifyNativeBlock('Ignition Locked', 'Use a wiring kit to bypass this ignition.')
                    end
                else
                    SetVehicleUndriveable(vehicle, false)
                end
            else
                hotwireCheckVehicle = 0
                hotwireCheckStartedAt = 0
                hotwireCheckStartedWithEngineRunning = false
                ResetIgnitionAccess(0, nil, nil)
            end
        end

        Wait(sleep)
    end
end)

RegisterNUICallback('signContract', function(data, cb)
    if not PartayKeysValidateNuiToken('contract', data and data.token) then
        Notify('Contract', 'Invalid contract session.', 'error')
        cb('error')
        return
    end

    PartayKeysClearNuiToken('contract')
    PartayKeysCloseNui()
    TriggerServerEvent('partay_keys:server:FinalizeSale', data.seller, data.plate)
    cb('ok')
end)

lib.callback.register('partay_keys:client:GetVehicleKeyMetadata', function(netId, plate)
    local vehicle = 0
    netId = tonumber(netId) or 0

    if netId > 0 then
        vehicle = NetToVeh(netId)
    end

    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1') or nil
    if (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and plate and plate ~= '' then
        for _, candidate in ipairs(GetGamePool('CVehicle')) do
            if candidate ~= 0 and DoesEntityExist(candidate) then
                local candidatePlate = GetVehicleNumberPlateText(candidate)
                candidatePlate = candidatePlate and candidatePlate:gsub('^%s*(.-)%s*$', '%1') or nil
                if candidatePlate == plate then
                    vehicle = candidate
                    break
                end
            end
        end
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    return {
        vehicle_class = GetVehicleClass(vehicle),
        vehicle_model_hash = GetEntityModel(vehicle)
    }
end)

-- Compatibility for QB/QBX resources that still emit stock vehicle key events.
local function GrantCompatKeys(plate)
    if not plate or plate == '' then return end
    TriggerServerEvent('partay_keys:server:GiveKeysForPlate', plate)
end

RegisterNetEvent('vehiclekeys:client:SetOwner', GrantCompatKeys)
RegisterNetEvent('qbx_vehiclekeys:client:SetOwner', GrantCompatKeys)
RegisterNetEvent('qbx_vehiclekeys:client:AddKeys', GrantCompatKeys)
RegisterNetEvent('qbx_vehiclekeys:client:GiveKeys', GrantCompatKeys)
RegisterNetEvent('qbx_vehiclekeys:client:AcquireVehicleKeys', GrantCompatKeys)
RegisterNetEvent('qb-vehiclekeys:client:AddKeys', GrantCompatKeys)
RegisterNetEvent('qb-vehiclekeys:client:GiveKeys', GrantCompatKeys)
RegisterNetEvent('qb-vehiclekeys:client:AcquireVehicleKeys', GrantCompatKeys)
RegisterNetEvent('esx_vehiclelock:client:addKey', GrantCompatKeys)
RegisterNetEvent('esx_vehiclelock:client:givekey', GrantCompatKeys)
RegisterNetEvent('esx_vehiclekeys:client:addKey', GrantCompatKeys)
RegisterNetEvent('esx_vehiclekeys:client:givekey', GrantCompatKeys)

function HasKeys(vehicle)
    return true
end

exports('HasKeys', HasKeys)

function GiveKeys(vehicleOrPlate)
    if type(vehicleOrPlate) == 'number' and vehicleOrPlate ~= 0 then
        GrantCompatKeys(GetVehicleNumberPlateText(vehicleOrPlate))
    else
        GrantCompatKeys(vehicleOrPlate)
    end
    return true
end

exports('GiveKeys', GiveKeys)

function RemoveKeys(...)
    return true
end

exports('RemoveKeys', RemoveKeys)

local function RegisterClientExportAlias(resourceName, exportName, handler)
    AddEventHandler(('__cfx_export_%s_%s'):format(resourceName, exportName), function(setCB)
        setCB(handler)
    end)
end

local function RegisterVehicleKeyExportAliases(resourceName)
    RegisterClientExportAlias(resourceName, 'HasKeys', function(...)
        return HasKeys(...)
    end)
    RegisterClientExportAlias(resourceName, 'GiveKeys', function(...)
        return GiveKeys(...)
    end)
    RegisterClientExportAlias(resourceName, 'RemoveKeys', function(...)
        return RemoveKeys(...)
    end)
end

RegisterVehicleKeyExportAliases('qbx_vehiclekeys')
RegisterVehicleKeyExportAliases('qb-vehiclekeys')
RegisterVehicleKeyExportAliases('vehiclekeys')
RegisterVehicleKeyExportAliases('esx_vehiclelock')
RegisterVehicleKeyExportAliases('esx_vehiclekeys')
