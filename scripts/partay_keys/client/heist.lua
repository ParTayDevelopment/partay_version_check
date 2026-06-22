lib.locale()

-- [[ The Illegal Ecosystem ]] --

local function GetNearbyPlayers()
    local players = lib.getNearbyPlayers(GetEntityCoords(cache.ped or PlayerPedId()), Config.KeyHandoffRadius or 3.0, false)
    local nearby = {}

    for _, player in ipairs(players) do
        table.insert(nearby, {
            id = GetPlayerServerId(player.id),
            name = GetPlayerName(player.id) or ('Player %s'):format(GetPlayerServerId(player.id))
        })
    end

    return nearby
end

local function CanStartHeist()
    local ped = cache.ped or PlayerPedId()
    if IsEntityDead(ped) or IsPedFatallyInjured(ped) or IsPedCuffed(ped) then return false end
    if IsPedInMeleeCombat(ped) or IsPedInCombat(ped, 0) then return false end
    return true
end

local function GetClosestActionVehicle(maxDistance)
    local ped = cache.ped or PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then return veh end

    return lib.getClosestVehicle(GetEntityCoords(ped), maxDistance or 5.0, false)
end

local function HasDoorLockStep(vehicle)
    local class = GetVehicleClass(vehicle)
    return class ~= 8 and class ~= 13 and class ~= 14 and class ~= 15 and class ~= 16
end

local function PlayConfiguredAnimation(anim)
    local ped = cache.ped or PlayerPedId()
    if not anim then return end

    lib.requestAnimDict(anim.dict, 1000)
    TaskPlayAnim(ped, anim.dict, anim.name, 8.0, 8.0, anim.duration or 1500, anim.flags or 49, 1, false, false, false)
    return anim
end

local activeHeistAnimation = nil
local activeHeistHandProp = false

local function PlayHeistAnimation(heistType)
    if heistType == 'lockpick' then
        activeHeistAnimation = PlayConfiguredAnimation(Animations.Lockpick)
    elseif heistType == 'hotwire' then
        activeHeistAnimation = PlayConfiguredAnimation(Animations.Hotwire)
    elseif heistType == 'decoder' then
        PartayKeysShowHandProp('decoder')
        activeHeistHandProp = true
        activeHeistAnimation = PlayConfiguredAnimation(Animations.Decoder)
    end
end

local function StopHeistAnimation()
    if not activeHeistAnimation and not activeHeistHandProp then return end

    local ped = cache.ped or PlayerPedId()
    if activeHeistAnimation and activeHeistAnimation.dict and activeHeistAnimation.name then
        StopAnimTask(ped, activeHeistAnimation.dict, activeHeistAnimation.name, 1.0)
    end

    if activeHeistHandProp then
        PartayKeysClearHandProp()
    end

    activeHeistAnimation = nil
    activeHeistHandProp = false
end

RegisterNetEvent('partay_keys:client:UseHeistItem', function(itemName)
    if itemName == Config.Items.Lockpick then
        if not Config.Heist.EnableLockpicking then
            Notify(locale('label_vehicle_theft'), locale('error_lockpicking_disabled'), 'error')
            return
        end

        if not CanStartHeist() then
            Notify(locale('label_vehicle_theft'), locale('error_lockpick_busy'), 'error')
            return
        end

        local veh = GetClosestActionVehicle(4.0)
        if not veh or veh == 0 then
            Notify(locale('label_vehicle_theft'), locale('error_no_vehicle_nearby'), 'error')
            return
        end

        TriggerServerEvent('partay_keys:server:RequestHeistToken', GetVehicleNumberPlateText(veh), VehToNet(veh))
    elseif itemName == Config.Items.WiringKit then
        if not Config.Heist.EnableHotwiring then
            Notify(locale('label_hotwire'), locale('error_hotwiring_disabled'), 'error')
            return
        end

        if not CanStartHeist() then
            Notify(locale('label_hotwire'), locale('error_hotwire_busy'), 'error')
            return
        end

        local veh = GetClosestActionVehicle(4.0)
        if not veh or veh == 0 then
            Notify(locale('label_hotwire'), locale('error_no_vehicle_nearby'), 'error')
            return
        end

        TriggerServerEvent('partay_keys:server:RequestHotwire', VehToNet(veh), GetVehicleNumberPlateText(veh))
    elseif itemName == Config.Items.ElectronicDecoder then
        if not CanStartHeist() then
            Notify(locale('label_electronic_decoder'), locale('error_decoder_busy'), 'error')
            return
        end

        local veh = GetClosestActionVehicle(4.0)
        if not veh or veh == 0 then
            Notify(locale('label_electronic_decoder'), locale('error_no_vehicle_nearby'), 'error')
            return
        end

        TriggerServerEvent('partay_keys:server:RequestDecoderToken', VehToNet(veh), GetVehicleNumberPlateText(veh))
    elseif itemName == Config.Items.BlankKey then
        Notify(locale('label_blank_key_fob'), locale('info_blank_key_fob'), 'info')
    elseif itemName == Config.Items.SaleContract then
        if not CanStartHeist() then
            Notify(locale('label_blackmarket'), locale('error_contract_busy'), 'error')
            return
        end

        local veh = GetClosestActionVehicle(Config.Heist.MaxSaleDistance or 5.0)
        if not veh or veh == 0 then
            Notify(locale('label_blackmarket'), locale('error_no_vehicle_nearby'), 'error')
            return
        end

        local plate = GetVehicleNumberPlateText(veh)
        local input = lib.inputDialog(locale('input_draft_contract'), {
                {type = 'number', label = locale('input_sale_price'), required = true, min = 1}
            })
        if not input then return end
        local price = input[1]

        local nearby = GetNearbyPlayers()
        if #nearby == 0 then Notify(locale('label_no_players'), locale('error_no_buyers'), 'error') return end

        local options = {}
        for _, player in pairs(nearby) do
            table.insert(options, {
                title = locale('menu_hand_to', { name = player.name }),
                onSelect = function()
                    PlayConfiguredAnimation(Animations.ContractHandoff)
                    TriggerServerEvent('partay_keys:server:ProposeSale', player.id, plate, price, VehToNet(veh))
                end
            })
        end
        lib.registerContext({ id = 'buyer_select', title = locale('menu_select_buyer'), options = options })
        lib.showContext('buyer_select')
    end
end)

exports.ox_target:addGlobalVehicle({
    {
        name = 'partay_vehicle_lockpick',
        icon = 'fas fa-screwdriver',
        label = locale('target_lockpick_vehicle'),
        distance = 2.0,
        canInteract = function(entity, distance, coords, name)
            if not Config.Heist.EnableLockpicking or not CanStartHeist() then return false end
            if not HasDoorLockStep(entity) then return false end
            local lockState = Entity(entity).state.lockState or GetVehicleDoorLockStatus(entity)
            return lockState == 2 or lockState == 4 or lockState == 7
        end,
        onSelect = function(data)
            local veh = data.entity
            TriggerServerEvent('partay_keys:server:RequestHeistToken', GetVehicleNumberPlateText(veh), VehToNet(veh))
        end
    }
})

local npcRobberyAimTarget = 0
local npcRobberyAimStartedAt = 0
local npcRobberyLastRequest = 0
local npcDoorFleeLastVehicle = 0
local npcDoorFleeLastAt = 0
local npcHeldDriver = 0
local npcHeldVehicle = 0
local npcHeldUntil = 0
local npcPendingHandoffDriver = 0
local npcPendingHandoffVehicle = 0
local npcRobberyDebugNextAt = 0
local npcRetaliationCooldown = {}
local npcRetaliatingUntil = {}
local IsValidNpcPed

local npcRetaliationFirearms = {
    'WEAPON_PISTOL',
    'WEAPON_COMBATPISTOL',
    'WEAPON_APPISTOL',
    'WEAPON_PISTOL50',
    'WEAPON_SNSPISTOL',
    'WEAPON_HEAVYPISTOL',
    'WEAPON_VINTAGEPISTOL',
    'WEAPON_REVOLVER',
    'WEAPON_MICROSMG',
    'WEAPON_SMG',
    'WEAPON_ASSAULTSMG',
    'WEAPON_MINISMG',
    'WEAPON_MACHINEPISTOL',
    'WEAPON_PUMPSHOTGUN',
    'WEAPON_SAWNOFFSHOTGUN',
    'WEAPON_ASSAULTRIFLE',
    'WEAPON_CARBINERIFLE',
    'WEAPON_COMPACTRIFLE'
}

local function DebugNpcRobbery(message, throttleMs)
    if not Config or not Config.DebugMode then return end

    local now = GetGameTimer()
    if throttleMs and throttleMs > 0 then
        if now < npcRobberyDebugNextAt then return end
        npcRobberyDebugNextAt = now + throttleMs
    end

    print(('^5[ParTay Keys Debug]^3 NPC Robbery: %s^0'):format(tostring(message)))
end

local function GetNpcRobberyConfig()
    local npcConfig = Config.Heist and Config.Heist.NPCVehicles
    return npcConfig and npcConfig.Robbery or nil
end

local function GetNpcRetaliationConfig()
    local robbery = GetNpcRobberyConfig()
    return robbery and robbery.Retaliation or nil
end

local function GetNpcFirearm(ped)
    if not IsValidNpcPed(ped) then return nil end

    local selected = GetSelectedPedWeapon(ped)
    if selected and selected ~= 0 and IsPedArmed(ped, 4) then
        return selected
    end

    for _, weaponName in ipairs(npcRetaliationFirearms) do
        local weaponHash = GetHashKey(weaponName)
        if HasPedGotWeapon(ped, weaponHash, false) then
            return weaponHash
        end
    end

    return nil
end

local function IsAggressiveNpcPed(ped, retaliation)
    if not IsValidNpcPed(ped) then return false end

    local pedGroup = GetPedRelationshipGroupHash(ped)
    for _, groupName in ipairs(retaliation.AggressiveRelationshipGroups or {}) do
        if pedGroup == GetHashKey(groupName) then
            return true
        end
    end

    return false
end

local function ShouldNpcRetaliate(driver, retaliation)
    if not retaliation or retaliation.Enabled ~= true then return false, nil end
    if not IsValidNpcPed(driver) then return false, nil end

    local weaponHash = GetNpcFirearm(driver)
    if not weaponHash then return false, nil end

    local now = GetGameTimer()
    if npcRetaliationCooldown[driver] and now < npcRetaliationCooldown[driver] then
        return false, nil
    end

    local aggressive = IsAggressiveNpcPed(driver, retaliation)
    if retaliation.AggressiveOnly ~= false and not aggressive then
        return false, nil
    end

    local chance = aggressive and tonumber(retaliation.ArmedAggressiveChance) or tonumber(retaliation.ArmedCivilianChance)
    chance = math.max(0, math.min(100, chance or 0))
    if chance < 100 and math.random(1, 100) > chance then
        npcRetaliationCooldown[driver] = now + (tonumber(retaliation.Cooldown) or 15000)
        return false, nil
    end

    return true, weaponHash
end

local function IsPlayerOwnedOrPossessedVehicle(vehicle)
    if not vehicle or vehicle == 0 then return true end
    if Entity(vehicle).state.possession_id then return true end
    if Entity(vehicle).state.isStolen then return true end
    return false
end

local function IsRobbableNpcDriver(driver)
    if not driver or driver == 0 or not DoesEntityExist(driver) then return false end
    if IsPedAPlayer(driver) or IsEntityDead(driver) or IsPedFatallyInjured(driver) then return false end
    if npcRetaliatingUntil[driver] and GetGameTimer() < npcRetaliatingUntil[driver] then return false end
    if not IsPedInAnyVehicle(driver, false) then return false end
    return true
end

function IsValidNpcPed(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsPedAPlayer(ped) or IsEntityDead(ped) or IsPedFatallyInjured(ped) then return false end
    return true
end

local function GetRobbableNpcVehicle(driver)
    if not IsRobbableNpcDriver(driver) then return 0 end

    local vehicle = GetVehiclePedIsIn(driver, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end
    if GetPedInVehicleSeat(vehicle, -1) ~= driver then return 0 end
    if IsPlayerOwnedOrPossessedVehicle(vehicle) then return 0 end

    return vehicle
end

local function GetRobberyTargetVehicle(target)
    if not target or target == 0 or not DoesEntityExist(target) then return 0, 0 end

    if npcRobberyAimTarget ~= 0 and target == npcRobberyAimTarget and npcPendingHandoffVehicle ~= 0 and DoesEntityExist(npcPendingHandoffVehicle) then
        if IsValidNpcPed(npcRobberyAimTarget) and not IsPlayerOwnedOrPossessedVehicle(npcPendingHandoffVehicle) then
            DebugNpcRobbery(('continuing active target ped=%s vehicle=%s'):format(tostring(npcRobberyAimTarget), tostring(npcPendingHandoffVehicle)), 1000)
            return npcPendingHandoffVehicle, npcRobberyAimTarget
        end
    end

    if IsEntityAVehicle(target) then
        local driver = GetPedInVehicleSeat(target, -1)
        if GetRobbableNpcVehicle(driver) ~= 0 then
            DebugNpcRobbery(('target vehicle=%s driver=%s'):format(tostring(target), tostring(driver)), 1000)
            return target, driver
        end
        DebugNpcRobbery(('aimed vehicle rejected vehicle=%s driver=%s'):format(tostring(target), tostring(driver)), 1000)
        return 0, 0
    end

    if IsEntityAPed(target) then
        local vehicle = GetRobbableNpcVehicle(target)
        if vehicle ~= 0 then
            DebugNpcRobbery(('target ped=%s vehicle=%s'):format(tostring(target), tostring(vehicle)), 1000)
            return vehicle, target
        end
        DebugNpcRobbery(('aimed ped rejected ped=%s'):format(tostring(target)), 1000)
    end

    return 0, 0
end

local function RequestEntityControl(entity, timeoutMs)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end

    NetworkRequestControlOfEntity(entity)
    local timeout = GetGameTimer() + (timeoutMs or 500)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end

    return NetworkHasControlOfEntity(entity)
end

local function DrawGunpointProgress(progress)
    progress = math.max(0.0, math.min(1.0, progress or 0.0))

    local x = 0.5
    local y = 0.82
    local width = 0.18
    local height = 0.012
    DrawRect(x, y, width + 0.004, height + 0.006, 12, 16, 22, 190)
    DrawRect(x - (width * (1.0 - progress) / 2.0), y, width * progress, height, 66, 153, 225, 230)
end

local function PlayNpcSurrenderPose(driver, duration)
    if not IsValidNpcPed(driver) then return end

    TaskHandsUp(driver, duration or 1200, cache.ped or PlayerPedId(), -1, false)
end

local function PlayNpcWalkingSurrenderPose(driver, duration)
    if not IsValidNpcPed(driver) then return end

    lib.requestAnimDict('missminuteman_1ig_2', 1000)
    TaskPlayAnim(driver, 'missminuteman_1ig_2', 'handsup_base', 4.0, 4.0, duration or -1, 49, 0, false, false, false)
end

local function HoldNpcDriverAtGunpoint(driver, vehicle)
    if not IsRobbableNpcDriver(driver) or vehicle == 0 then return end

    DebugNpcRobbery(('holding driver=%s vehicle=%s'):format(tostring(driver), tostring(vehicle)), 1500)
    SetEntityAsMissionEntity(driver, true, true)
    npcHeldDriver = driver
    npcHeldVehicle = vehicle
    npcHeldUntil = GetGameTimer() + math.max(1250, tonumber((GetNpcRobberyConfig() or {}).AimHoldTime) or 1500)
    npcPendingHandoffDriver = driver
    npcPendingHandoffVehicle = vehicle

    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedFleeAttributes(driver, 0, false)
    SetPedCombatAttributes(driver, 17, true)
    SetPedCanRagdoll(driver, false)
    SetPedKeepTask(driver, true)
    SetVehicleHandbrake(vehicle, true)
    SetVehicleForwardSpeed(vehicle, 0.0)
    PlayNpcSurrenderPose(driver, 1400)
end

local function StartNpcRobberyRetaliation(driver, vehicle, weaponHash)
    if not IsValidNpcPed(driver) then return end

    DebugNpcRobbery(('retaliation started driver=%s vehicle=%s weapon=%s'):format(tostring(driver), tostring(vehicle), tostring(weaponHash)))
    npcRetaliationCooldown[driver] = GetGameTimer() + (tonumber((GetNpcRetaliationConfig() or {}).Cooldown) or 15000)
    npcRetaliatingUntil[driver] = GetGameTimer() + 6000

    if npcHeldDriver == driver then
        npcHeldDriver = 0
        npcHeldVehicle = 0
        npcHeldUntil = 0
    end

    if npcPendingHandoffDriver == driver then
        npcPendingHandoffDriver = 0
        npcPendingHandoffVehicle = 0
    end

    RequestEntityControl(driver, 1000)
    if vehicle and vehicle ~= 0 then
        RequestEntityControl(vehicle, 1000)
        SetVehicleHandbrake(vehicle, true)
        SetVehicleForwardSpeed(vehicle, 0.0)
    end

    SetEntityAsMissionEntity(driver, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedFleeAttributes(driver, 0, false)
    SetPedCombatAttributes(driver, 0, true)
    SetPedCombatAttributes(driver, 5, true)
    SetPedCombatAttributes(driver, 46, true)
    SetPedCombatAbility(driver, 2)
    SetPedCombatRange(driver, 2)
    SetPedCombatMovement(driver, 2)
    SetPedAccuracy(driver, 35)
    SetPedKeepTask(driver, true)
    if weaponHash then
        GiveWeaponToPed(driver, weaponHash, 90, false, true)
        SetCurrentPedWeapon(driver, weaponHash, true)
    end

    ClearPedTasks(driver)
    if IsPedInAnyVehicle(driver, false) and vehicle and vehicle ~= 0 then
        TaskLeaveVehicle(driver, vehicle, 256)
    end

    CreateThread(function()
        local playerPed = cache.ped or PlayerPedId()
        local deadline = GetGameTimer() + 2500
        while IsValidNpcPed(driver) and IsPedInAnyVehicle(driver, false) and GetGameTimer() < deadline do
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetVehicleHandbrake(vehicle, true)
                SetVehicleForwardSpeed(vehicle, 0.0)
            end
            Wait(100)
        end

        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            SetVehicleHandbrake(vehicle, false)
        end

        if IsValidNpcPed(driver) then
            TaskCombatPed(driver, playerPed, 0, 16)
        end
    end)
end

local function WaitForNpcToExitVehicle(driver, vehicle)
    if not IsValidNpcPed(driver) or vehicle == 0 or not DoesEntityExist(vehicle) then
        DebugNpcRobbery(('exit wait invalid driver=%s vehicle=%s'):format(tostring(driver), tostring(vehicle)))
        return false
    end
    if not IsPedInAnyVehicle(driver, false) then
        DebugNpcRobbery(('driver already out driver=%s'):format(tostring(driver)))
        PlayNpcSurrenderPose(driver, 1500)
        return true
    end

    RequestEntityControl(driver, 1000)
    RequestEntityControl(vehicle, 1000)
    SetEntityAsMissionEntity(driver, true, true)
    SetVehicleHandbrake(vehicle, true)
    SetVehicleForwardSpeed(vehicle, 0.0)
    ClearPedTasks(driver)
    PlayNpcSurrenderPose(driver, 1200)
    Wait(350)
    TaskLeaveVehicle(driver, vehicle, 256)

    local timeout = GetGameTimer() + 2500
    while IsValidNpcPed(driver) and IsPedInAnyVehicle(driver, false) and GetGameTimer() < timeout do
        SetVehicleHandbrake(vehicle, true)
        SetVehicleForwardSpeed(vehicle, 0.0)
        Wait(50)
    end

    local exited = IsValidNpcPed(driver) and not IsPedInAnyVehicle(driver, false)
    if exited then
        PlayNpcSurrenderPose(driver, 1500)
    end
    DebugNpcRobbery(('exit wait result driver=%s exited=%s inVehicle=%s'):format(tostring(driver), tostring(exited), tostring(IsValidNpcPed(driver) and IsPedInAnyVehicle(driver, false))))
    return exited
end

local function MoveNpcToPlayerForHandoff(driver)
    if not IsValidNpcPed(driver) then return false end

    local playerPed = cache.ped or PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local driverCoords = GetEntityCoords(driver)
    local direction = driverCoords - playerCoords
    local length = #direction
    local targetCoords = length > 0.01 and (playerCoords + (direction / length) * 1.15) or playerCoords

    RequestEntityControl(driver, 750)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedFleeAttributes(driver, 0, false)
    SetPedKeepTask(driver, true)
    PlayNpcSurrenderPose(driver, 1000)
    Wait(250)
    TaskGoStraightToCoord(driver, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, 4500, GetEntityHeading(playerPed), 0.2)
    PlayNpcWalkingSurrenderPose(driver, 4500)

    local timeout = GetGameTimer() + 4500
    while IsValidNpcPed(driver) and GetGameTimer() < timeout do
        if #(GetEntityCoords(driver) - targetCoords) <= 0.9 then
            break
        end
        Wait(100)
    end

    if not IsValidNpcPed(driver) then return false end

    ClearPedTasks(driver)
    TaskTurnPedToFaceEntity(driver, playerPed, 600)
    PlayNpcSurrenderPose(driver, 900)
    Wait(300)
    return true
end

local function PlayNpcKeyHandoff(driver, vehicle)
    if not IsValidNpcPed(driver) or vehicle == 0 or not DoesEntityExist(vehicle) then
        DebugNpcRobbery(('handoff invalid driver=%s vehicle=%s'):format(tostring(driver), tostring(vehicle)))
        return 0
    end

    local playerPed = cache.ped or PlayerPedId()
    local giveAnim = Animations and Animations.NpcKeyGive
    local receiveAnim = Animations and Animations.NpcKeyReceive
    local duration = math.max(900, tonumber(giveAnim and giveAnim.duration or receiveAnim and receiveAnim.duration) or 1400)

    RequestEntityControl(driver, 750)
    RequestEntityControl(vehicle, 750)
    DebugNpcRobbery(('handoff start driver=%s vehicle=%s duration=%s'):format(tostring(driver), tostring(vehicle), tostring(duration)))
    SetEntityAsMissionEntity(driver, true, true)
    FreezeEntityPosition(driver, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetVehicleHandbrake(vehicle, true)
    SetVehicleForwardSpeed(vehicle, 0.0)
    ClearPedTasks(driver)

    if giveAnim and giveAnim.dict and giveAnim.name then
        lib.requestAnimDict(giveAnim.dict, 1000)
        TaskPlayAnim(driver, giveAnim.dict, giveAnim.name, 4.0, 4.0, duration, giveAnim.flags or 48, 0, false, false, false)
    end

    if receiveAnim and receiveAnim.dict and receiveAnim.name then
        lib.requestAnimDict(receiveAnim.dict, 1000)
        TaskPlayAnim(playerPed, receiveAnim.dict, receiveAnim.name, 4.0, 4.0, duration, receiveAnim.flags or 48, 0, false, false, false)
    end

    local prop = 0
    local propConfig = Props and Props.Handheld and Props.Handheld.Fob
    if propConfig and propConfig.Enabled ~= false and propConfig.Model then
        local model = GetHashKey(propConfig.Model)
        lib.requestModel(model, 1000)
        local coords = GetEntityCoords(driver)
        prop = CreateObject(model, coords.x, coords.y, coords.z + 0.2, true, true, false)
        AttachEntityToEntity(prop, driver, GetPedBoneIndex(driver, propConfig.Bone or 57005), propConfig.Pos.x, propConfig.Pos.y, propConfig.Pos.z, propConfig.Rot.x, propConfig.Rot.y, propConfig.Rot.z, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(model)
        DebugNpcRobbery(('handoff prop created prop=%s model=%s'):format(tostring(prop), tostring(propConfig.Model)))
    else
        DebugNpcRobbery('handoff prop skipped')
    end

    CreateThread(function()
        Wait(math.floor(duration * 0.65))
        if prop ~= 0 and DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
        if PartayKeysShowHandPropOnce then
            PartayKeysShowHandPropOnce('fob', math.max(600, duration - 300))
        end
    end)

    CreateThread(function()
        Wait(duration + 250)
        if prop ~= 0 and DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
    end)

    return duration
end

local function MakeNpcDriverFlee(driver, vehicle)
    if not IsValidNpcPed(driver) or vehicle == 0 then return end

    if npcHeldDriver == driver then
        npcHeldDriver = 0
        npcHeldVehicle = 0
        npcHeldUntil = 0
    end

    SetVehicleHandbrake(vehicle, false)
    FreezeEntityPosition(driver, false)
    SetBlockingOfNonTemporaryEvents(driver, false)
    SetPedCanRagdoll(driver, true)
    SetPedFleeAttributes(driver, 0, false)
    SetPedCombatAttributes(driver, 17, true)
    ClearPedTasks(driver)
    if IsPedInAnyVehicle(driver, false) then
        TaskLeaveVehicle(driver, vehicle, 256)
    end

    CreateThread(function()
        local startedAt = GetGameTimer()
        while GetGameTimer() - startedAt < 3000 do
            if not DoesEntityExist(driver) or IsEntityDead(driver) then return end
            if not IsPedInAnyVehicle(driver, false) then break end
            Wait(150)
        end

        if DoesEntityExist(driver) and not IsEntityDead(driver) then
            FreezeEntityPosition(driver, false)
            TaskSmartFleePed(driver, cache.ped or PlayerPedId(), 120.0, -1, false, false)
        end
    end)
end

CreateThread(function()
    while true do
        local sleep = 250
        local robbery = GetNpcRobberyConfig()

        if robbery and robbery.Enabled and robbery.UnlockedDoorFlee then
            local ped = cache.ped or PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsTryingToEnter(ped)
                if vehicle and vehicle ~= 0 and vehicle ~= npcDoorFleeLastVehicle then
                    sleep = 0
                    local driver = GetPedInVehicleSeat(vehicle, -1)
                    if IsRobbableNpcDriver(driver) and not IsPlayerOwnedOrPossessedVehicle(vehicle) then
                        local lockState = Entity(vehicle).state.lockState or GetVehicleDoorLockStatus(vehicle)
                        if lockState == 0 or lockState == 1 then
                            npcDoorFleeLastVehicle = vehicle
                            npcDoorFleeLastAt = GetGameTimer()
                            MakeNpcDriverFlee(driver, vehicle)
                        end
                    end
                elseif npcDoorFleeLastVehicle ~= 0 and GetGameTimer() - npcDoorFleeLastAt > 5000 then
                    npcDoorFleeLastVehicle = 0
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 500
        local robbery = GetNpcRobberyConfig()

        if robbery and robbery.Enabled and robbery.GunpointEnabled then
            local ped = cache.ped or PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) and IsPedArmed(ped, 4) and IsPlayerFreeAiming(PlayerId()) then
                sleep = 0
                local aiming, target = GetEntityPlayerIsFreeAimingAt(PlayerId())
                local vehicle, driver = 0, 0
                if aiming then
                    vehicle, driver = GetRobberyTargetVehicle(target)
                end

                if vehicle ~= 0 then
                    local now = GetGameTimer()
                    local maxDistance = robbery.MaxDistance or 12.0
                    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= maxDistance then
                        local shouldRetaliate, weaponHash = ShouldNpcRetaliate(driver, GetNpcRetaliationConfig())
                        if shouldRetaliate then
                            npcRobberyAimTarget = 0
                            npcRobberyAimStartedAt = 0
                            StartNpcRobberyRetaliation(driver, vehicle, weaponHash)
                            Wait(1000)
                        else
                            HoldNpcDriverAtGunpoint(driver, vehicle)

                            if npcRobberyAimTarget ~= driver then
                                npcRobberyAimTarget = driver
                                npcRobberyAimStartedAt = now
                                DebugNpcRobbery(('aim hold started driver=%s vehicle=%s holdMs=%s'):format(tostring(driver), tostring(vehicle), tostring(robbery.AimHoldTime or 1500)))
                                DrawGunpointProgress(0.0)
                            elseif now - npcRobberyAimStartedAt >= (robbery.AimHoldTime or 1500) and now - npcRobberyLastRequest >= (robbery.Cooldown or 8000) then
                                npcRobberyLastRequest = now
                                DebugNpcRobbery(('requesting server grant driver=%s vehicle=%s net=%s plate=%s'):format(tostring(driver), tostring(vehicle), tostring(VehToNet(vehicle)), tostring(GetVehicleNumberPlateText(vehicle))))
                                DrawGunpointProgress(1.0)
                                TriggerServerEvent('partay_keys:server:RobNpcVehicleKeys', VehToNet(vehicle), GetVehicleNumberPlateText(vehicle))
                                npcRobberyAimTarget = 0
                                npcRobberyAimStartedAt = 0
                            else
                                local progress = (now - npcRobberyAimStartedAt) / (robbery.AimHoldTime or 1500)
                                DebugNpcRobbery(('aim progress driver=%s progress=%s'):format(tostring(driver), tostring(math.floor(progress * 100))), 500)
                                DrawGunpointProgress(progress)
                            end
                        end
                    else
                        npcRobberyAimTarget = 0
                        npcRobberyAimStartedAt = 0
                    end
                else
                    npcRobberyAimTarget = 0
                    npcRobberyAimStartedAt = 0
                end
            else
                npcRobberyAimTarget = 0
                npcRobberyAimStartedAt = 0
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 500

        if npcHeldDriver ~= 0 then
            sleep = 0
            if GetGameTimer() > npcHeldUntil or not IsRobbableNpcDriver(npcHeldDriver) or npcHeldVehicle == 0 or not DoesEntityExist(npcHeldVehicle) then
                if npcHeldVehicle ~= 0 and DoesEntityExist(npcHeldVehicle) then
                    SetVehicleHandbrake(npcHeldVehicle, false)
                end
                if npcHeldDriver ~= 0 and DoesEntityExist(npcHeldDriver) then
                    SetPedCanRagdoll(npcHeldDriver, true)
                    SetBlockingOfNonTemporaryEvents(npcHeldDriver, false)
                end
                npcHeldDriver = 0
                npcHeldVehicle = 0
                npcHeldUntil = 0
            else
                SetVehicleHandbrake(npcHeldVehicle, true)
                SetVehicleForwardSpeed(npcHeldVehicle, 0.0)
                DisableControlAction(0, 24, true)
            end
        end

        Wait(sleep)
    end
end)

RegisterNetEvent('partay_keys:client:NpcVehicleRobberyComplete', function(netId)
    local vehicle = netId and NetToVeh(netId) or 0
    DebugNpcRobbery(('complete received netId=%s vehicle=%s pendingDriver=%s pendingVehicle=%s'):format(tostring(netId), tostring(vehicle), tostring(npcPendingHandoffDriver), tostring(npcPendingHandoffVehicle)))
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        DebugNpcRobbery('complete aborted: vehicle missing')
        return
    end

    SetVehicleDoorsLocked(vehicle, 1)
    local driver = (npcPendingHandoffVehicle == vehicle and npcPendingHandoffDriver ~= 0) and npcPendingHandoffDriver or GetPedInVehicleSeat(vehicle, -1)
    DebugNpcRobbery(('complete selected driver=%s seatDriver=%s'):format(tostring(driver), tostring(GetPedInVehicleSeat(vehicle, -1))))
    npcPendingHandoffDriver = 0
    npcPendingHandoffVehicle = 0
    if npcHeldDriver == driver then
        npcHeldDriver = 0
        npcHeldVehicle = 0
        npcHeldUntil = 0
    end

    CreateThread(function()
        if not WaitForNpcToExitVehicle(driver, vehicle) then
            DebugNpcRobbery('handoff fallback: driver failed to exit')
            MakeNpcDriverFlee(driver, vehicle)
            return
        end

        if not MoveNpcToPlayerForHandoff(driver) then
            DebugNpcRobbery('handoff fallback: driver failed to approach player')
            MakeNpcDriverFlee(driver, vehicle)
            return
        end

        local handoffDuration = PlayNpcKeyHandoff(driver, vehicle)
        DebugNpcRobbery(('handoff duration=%s'):format(tostring(handoffDuration)))
        Wait(handoffDuration > 0 and handoffDuration or 250)
        MakeNpcDriverFlee(driver, vehicle)
    end)
end)

local function IsValidWitnessPed(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if ped == (cache.ped or PlayerPedId()) or IsPedAPlayer(ped) then return false end
    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then return false end
    return true
end

RegisterNetEvent('partay_keys:client:CheckHeistAlarmWitnesses', function(netId, plate, heistType)
    local alerts = Config.Heist and Config.Heist.PoliceAlerts
    if not alerts or alerts.Enabled ~= true then return end

    local vehicle = netId and NetToVeh(netId) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local vehicleCoords = GetEntityCoords(vehicle)
    local hearingDistance = tonumber(alerts.HearingDistance) or 35.0
    local sightDistance = tonumber(alerts.SightDistance) or 22.0

    for _, ped in ipairs(GetGamePool('CPed')) do
        if IsValidWitnessPed(ped) then
            local distance = #(GetEntityCoords(ped) - vehicleCoords)
            if distance <= hearingDistance then
                local witnessedBySight = distance <= sightDistance and HasEntityClearLosToEntity(ped, vehicle, 17)
                local witnessedBySound = distance <= hearingDistance
                if witnessedBySight or witnessedBySound then
                    TriggerServerEvent('partay_keys:server:ReportWitnessedHeistAlarm', netId, plate, heistType, witnessedBySight and 'sight' or 'hearing')
                    return
                end
            end
        end
    end
end)

RegisterNetEvent('partay_keys:client:PoliceAlertBlip', function(coords, blipConfig)
    if not coords then return end
    blipConfig = type(blipConfig) == 'table' and blipConfig or {}

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, blipConfig.sprite or 225)
    SetBlipColour(blip, blipConfig.color or 1)
    SetBlipScale(blip, blipConfig.scale or 1.0)
    SetBlipDisplay(blip, 4)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipConfig.text or 'Vehicle Theft Alarm')
    EndTextCommandSetBlipName(blip)

    SetTimeout((tonumber(blipConfig.time) or 60) * 1000, function()
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
end)

RegisterNetEvent('partay_keys:client:StartMinigame', function(token, heistType)
    PlayHeistAnimation(heistType)
    RunHeistMinigame(3, function(success)
        StopHeistAnimation()
        TriggerServerEvent('partay_keys:server:HeistResult', token, success, heistType)
    end)
end)

RegisterNetEvent('partay_keys:client:CancelAnimation', function()
    StopHeistAnimation()
    Notify(locale('label_failed'), locale('error_tool_broken'), 'error')
end)

-- Receive Contract from Server
RegisterNetEvent('partay_keys:client:ReceiveContract', function(sellerId, plate, price)
    PartayKeysShowHandProp('clipboard')
    SendNUIMessage({ action = 'openContract', sellerId = sellerId, plate = plate, price = price, token = PartayKeysCreateNuiToken('contract') })
    PartayKeysOpenNui(true)
end)
