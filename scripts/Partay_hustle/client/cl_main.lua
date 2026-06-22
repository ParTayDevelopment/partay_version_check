local selling_drugs = false
local can_i_sell = true


local Currweapon = false


local propEntity

local requirementEnabled = not (Config.HustleRequirement and Config.HustleRequirement.enabled == false)
local requiredItems = (Config.HustleRequirement and Config.HustleRequirement.items) or { 'trap_phone' }
local requirementAny = not (Config.HustleRequirement and Config.HustleRequirement.any == false)

local function _resolveItemLabel(name)
    if not name then return '' end
    local cfg = Config.DrugList and Config.DrugList[name]
    if cfg and cfg.label then return tostring(cfg.label) end
    if GetResourceState('ox_inventory') == 'started' then
        local ok, items = pcall(function() return exports.ox_inventory:Items() end)
        if ok and items and items[name] then
            return tostring(items[name].label or items[name].name or name)
        end
    end
    return tostring(name)
end

local function HasRequiredItem()
    if not requirementEnabled then return true end
    if not requiredItems or #requiredItems == 0 then return true end

    if requirementAny then
        for _, item in ipairs(requiredItems) do
            local count = exports.ox_inventory:GetItemCount(item)
            if count and count > 0 then
                return count
            end
        end
        return false
    else
        for _, item in ipairs(requiredItems) do
            local count = exports.ox_inventory:GetItemCount(item)
            if not (count and count > 0) then
                return false
            end
        end
        return true
    end
end

AddEventHandler('ox_inventory:currentWeapon', function(weapon) 
    if not weapon or weapon == 'null' then
        Currweapon = false
        print('Weapon holstered')
    else
        Currweapon = true
        print(weapon.label .. ' equipped')
    end
end)


local _pcmd = (Config.Commands and Config.Commands.player) or {}
local _hustleCmd = _pcmd.hustle or Config.hustleCommand or 'hustle'
local _hotspotsCmd = _pcmd.hotspots or 'traphotspots'
local _cancelCmd = _pcmd.cancel or 'trapcancel'
local _lbCmd = _pcmd.leaderboard or Config.leaderboardCommand or 'trapleaderboard'

-- simple local debounce to avoid spamming callbacks
local _cmdCooldownMs = (Config.UI and Config.UI.hustleCmdCooldownMs) or 400
local _nextHustleAt = 0
local _buyerTargetOption = 'partay_hustle:sell_to_buyer'
local _activeBuyerPed = nil
local _activeBuyerBusy = false
local _activeBuyerBusyToken = 0
local _activeBuyerOptionName = nil
local _hustleStartedAt = 0
local _buyerRelationshipGroup = GetHashKey('PARTAY_HUSTLE_BUYER')

local function _ensureBuyerRelationshipGroup()
    pcall(function()
        AddRelationshipGroup('PARTAY_HUSTLE_BUYER')
        SetRelationshipBetweenGroups(0, _buyerRelationshipGroup, GetHashKey('PLAYER'))
        SetRelationshipBetweenGroups(0, GetHashKey('PLAYER'), _buyerRelationshipGroup)
        SetRelationshipBetweenGroups(0, _buyerRelationshipGroup, _buyerRelationshipGroup)
    end)
end

local function _makeBuyerFearless(ped)
    if not ped or not DoesEntityExist(ped) then return end

    _ensureBuyerRelationshipGroup()
    SetPedRelationshipGroupHash(ped, _buyerRelationshipGroup)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)

    if type(SetPedFleeAttributes) == 'function' then
        SetPedFleeAttributes(ped, 0, false)
    end
    if type(SetPedCombatAttributes) == 'function' then
        SetPedCombatAttributes(ped, 17, false) -- do not use flee behavior
    end
    if type(SetPedCombatAbility) == 'function' then
        SetPedCombatAbility(ped, 0)
    end
    if type(SetPedCombatMovement) == 'function' then
        SetPedCombatMovement(ped, 0)
    end
    if type(SetPedSeeingRange) == 'function' then
        SetPedSeeingRange(ped, 0.0)
    end
    if type(SetPedHearingRange) == 'function' then
        SetPedHearingRange(ped, 0.0)
    end
    if type(SetPedAlertness) == 'function' then
        SetPedAlertness(ped, 0)
    end
    if type(SetPedCanEvasiveDive) == 'function' then
        SetPedCanEvasiveDive(ped, false)
    end
    if type(SetPedCanRagdoll) == 'function' then
        SetPedCanRagdoll(ped, false)
    end
    if type(SetPedCanRagdollFromPlayerImpact) == 'function' then
        SetPedCanRagdollFromPlayerImpact(ped, false)
    end
    if type(SetPedConfigFlag) == 'function' then
        SetPedConfigFlag(ped, 208, true) -- disable shocked events
        SetPedConfigFlag(ped, 294, true) -- no critical hits / less panic from impacts
        SetPedConfigFlag(ped, 430, true) -- ignore being surrounded by players
    end
end

local function _clampPercent(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 100 then return 100 end
    return v
end

local function _getBuyerDenialChance(item)
    local base = _clampPercent(Config.Buyer and Config.Buyer.denialChance)
    local entry = item and Config.DrugList and Config.DrugList[item] or nil
    if not entry then return base end

    if entry.buyer and entry.buyer.denialChance ~= nil then
        return _clampPercent(entry.buyer.denialChance)
    end
    if entry.denialChance ~= nil then
        return _clampPercent(entry.denialChance)
    end
    return base
end

local function _loadAnimDict(dict, timeoutMs)
    timeoutMs = timeoutMs or 1500
    RequestAnimDict(dict)
    local started = GetGameTimer()
    while not HasAnimDictLoaded(dict) do
        if (GetGameTimer() - started) > timeoutMs then
            return false
        end
        Wait(0)
    end
    return true
end

local function _loadModel(model, timeoutMs)
    timeoutMs = timeoutMs or 3000
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        return false, hash
    end
    RequestModel(hash)
    local started = GetGameTimer()
    while not HasModelLoaded(hash) do
        if (GetGameTimer() - started) > timeoutMs then
            return false, hash
        end
        Wait(0)
    end
    return true, hash
end

local function _playPedDecline(ped, playerPed)
    if not DoesEntityExist(ped) then return end
    TaskTurnPedToFaceEntity(ped, playerPed, 900)
    Wait(250)

    local anims = {
        { dict = "gestures@m@standing@casual", clip = "gesture_no_way" },
        { dict = "gestures@f@standing@casual", clip = "gesture_no_way" }
    }

    for _, a in ipairs(anims) do
        if _loadAnimDict(a.dict, 1200) then
            TaskPlayAnim(ped, a.dict, a.clip, 8.0, -8.0, 1200, 49, 0.0, false, false, false)
            return
        end
    end
end

local function _removeBuyerTarget(ped, optionName)
    if not ped or ped == 0 then return end
    if GetResourceState('ox_target') ~= 'started' then return end
    pcall(function()
        local name = optionName or _activeBuyerOptionName or _buyerTargetOption
        exports.ox_target:removeLocalEntity(ped, name)
        -- safety cleanup for older sessions that used the static name
        if name ~= _buyerTargetOption then
            exports.ox_target:removeLocalEntity(ped, _buyerTargetOption)
        end
    end)
end

local function _cleanupActiveBuyer()
    if _activeBuyerPed and DoesEntityExist(_activeBuyerPed) then
        _removeBuyerTarget(_activeBuyerPed, _activeBuyerOptionName)
        SetPedAsNoLongerNeeded(_activeBuyerPed)
        DeletePed(_activeBuyerPed)
    end
    _activeBuyerPed = nil
    _activeBuyerBusy = false
    _activeBuyerBusyToken = 0
    _activeBuyerOptionName = nil
end

local function _setPedSafeForDespawn(ped)
    if not ped or not DoesEntityExist(ped) then return end
    _makeBuyerFearless(ped)
    SetEntityInvincible(ped, true)
    SetEntityCanBeDamaged(ped, false)
    if type(SetEntityProofs) == 'function' then
        SetEntityProofs(ped, true, true, true, true, true, true, true, true)
    end
    if type(SetPedCanRagdoll) == 'function' then
        SetPedCanRagdoll(ped, false)
    end
    if type(SetPedCanRagdollFromPlayerImpact) == 'function' then
        SetPedCanRagdollFromPlayerImpact(ped, false)
    end
    SetPedKeepTask(ped, true)
end

local function _sendBuyerAwayAndDelete(ped, fromPed)
    if not ped or not DoesEntityExist(ped) then return end

    _removeBuyerTarget(ped)
    _setPedSafeForDespawn(ped)
    FreezeEntityPosition(ped, false)

    local pedCoords = GetEntityCoords(ped)
    local fromCoords = (fromPed and DoesEntityExist(fromPed)) and GetEntityCoords(fromPed) or pedCoords

    local dx = pedCoords.x - fromCoords.x
    local dy = pedCoords.y - fromCoords.y
    local len = math.sqrt((dx * dx) + (dy * dy))
    if len < 0.01 then
        local heading = math.rad(GetEntityHeading(ped))
        dx = math.cos(heading)
        dy = math.sin(heading)
        len = 1.0
    end

    local walkDist = 10.0
    local tx = pedCoords.x + (dx / len) * walkDist
    local ty = pedCoords.y + (dy / len) * walkDist
    local tz = pedCoords.z
    local found, groundZ = GetGroundZFor_3dCoord(tx, ty, pedCoords.z + 1.0, 0)
    if found then tz = groundZ end

    ClearPedTasks(ped)
    TaskGoStraightToCoord(ped, tx, ty, tz, 1.1, -1, 0.0, 0.0)

    CreateThread(function()
        local timeoutAt = GetGameTimer() + 10000
        while DoesEntityExist(ped) and GetGameTimer() < timeoutAt do
            local c = GetEntityCoords(ped)
            local ddx = c.x - tx
            local ddy = c.y - ty
            if math.sqrt((ddx * ddx) + (ddy * ddy)) < 1.8 then
                break
            end
            Wait(250)
        end
        if DoesEntityExist(ped) then
            SetPedAsNoLongerNeeded(ped)
            DeletePed(ped)
        end
    end)
end

-- Prevent opening inventory while hustling to avoid dupes
local function _setInvBusyState(isBusy)
    if GetResourceState('ox_inventory') == 'started' then
        local ok = pcall(function()
            if LocalPlayer and LocalPlayer.state then
                LocalPlayer.state:set('invBusy', isBusy, true)
            end
            if isBusy then
                TriggerEvent('ox_inventory:closeInventory')
            end
        end)
        if not ok and Config.Debug then print('[Partay_hustle] invBusy state set failed') end
    end
end

local function _forceHustleReset(cleanupBuyer)
    selling_drugs = false
    can_i_sell = true
    _hustleStartedAt = 0
    _activeBuyerBusy = false
    _activeBuyerBusyToken = 0
    if cleanupBuyer ~= false then
        _cleanupActiveBuyer()
    else
        _activeBuyerPed = nil
        _activeBuyerOptionName = nil
    end
    _setInvBusyState(false)
end

CreateThread(function()
    local last = false
    while true do
        if selling_drugs ~= last then
            _setInvBusyState(selling_drugs)
            last = selling_drugs
        end
        if selling_drugs and _hustleStartedAt > 0 then
            local elapsed = (GetGameTimer() or 0) - _hustleStartedAt
            if elapsed > 120000 then
                if Config.Debug then
                    print('[Partay_hustle] safety reset: hustle timed out >120s')
                end
                _forceHustleReset(true)
            end
        end
        Wait(100)
    end
end)

RegisterCommand(_hustleCmd, function(source, args, raw)
    local now = GetGameTimer()
    if now < _nextHustleAt then
        return -- silently ignore to reduce spam
    end
    _nextHustleAt = now + _cmdCooldownMs
    
    if Currweapon then
        TriggerEvent('ox_inventory:disarm', true)
        -- put that bitch up 
    end
    
    if not HasRequiredItem() then
        local needLabel = (Config.HustleRequirement and Config.HustleRequirement.label) or (requiredItems and requiredItems[1]) or 'required item'
        ShowNotification(((_L and _L('need_item', { item = tostring(needLabel) })) or ("You need a " .. tostring(needLabel))))
        return
    end

    -- Server-side verification to prevent client bypass
    local ok, reason = lib.callback.await('Partay_hustle:canHustle', false)
    if not ok then
        if reason == 'no_products' then
            ShowNotification("You don't have any products twin!")
            return
        end
        if reason == 'not_in_zone' then
            ShowNotification(((_L and _L('cannot_sell_here')) or 'You cannot sell here.'))
            return
        end
        local needLabel = (Config.HustleRequirement and Config.HustleRequirement.label) or (requiredItems and requiredItems[1]) or 'required item'
        ShowNotification(((_L and _L('need_item', { item = tostring(needLabel) })) or ("You need a " .. tostring(needLabel))))
        return
    end
    
    if not can_i_sell then
        ShowNotification(((_L and _L('selling_already')) or 'You are already selling relax! For More Help discord.gg/sawl'))
        return
    end
    
    can_i_sell = false

    local playerPed = PlayerPedId()
    
    if selling_drugs then 
        can_i_sell = true
        return 
    end
    
    selling_drugs = true
    _hustleStartedAt = GetGameTimer() or 0
    
    if IsPedInAnyVehicle(playerPed) then 
        _forceHustleReset(true)
        ShowNotification("You cannot hustle from a car!")
        return 
    end
    
    local drugs, count = getDrugs()
    if count == 0 then
        ShowNotification("You don't have any products twin!")
        _forceHustleReset(true)
        return
    end
    
    local playerPed = PlayerPedId()
    
    
    local animDict = "anim@heists@heist_safehouse_intro@phone"
    local animName = "phone_intro"
    
    if not _loadAnimDict(animDict, 2500) then
        _forceHustleReset(true)
        ShowNotification("Could not start hustle animation. Try again.")
        return
    end
    
    local phoneModel = "prop_amb_phone"
    local phoneOk = _loadModel(phoneModel, 2500)
    if not phoneOk then
        _forceHustleReset(true)
        ShowNotification("Could not load phone prop. Try again.")
        return
    end
    
    local phoneObject = CreateObject(phoneModel, 0.0, 0.0, 0.0, true, true, true)
    AttachEntityToEntity(phoneObject, playerPed, GetPedBoneIndex(playerPed, 57005), 0.15, 0.07, -0.03, -275.0, 75.0, 0.0, true, true, false, true, 1, true)
    
    TaskPlayAnim(playerPed, animDict, animName, 8.0, 8.0, -1, 50, 0, false, false, false)
    Citizen.Wait(5000)
    
    DeleteEntity(phoneObject)
    SetModelAsNoLongerNeeded(`prop_amb_phone`)
    ClearPedTasks(playerPed)
    
    local function choosePedHashForItem(item)
        local cfg = item and Config.DrugList and Config.DrugList[item] or nil
        local list = cfg and cfg.allowedPedModels or nil
        local function toHash(model)
            if type(model) == 'number' then return model end
            if type(model) == 'string' then return GetHashKey(model) end
            return nil
        end
        if type(list) == 'table' and #list > 0 then
            local pick = list[math.random(1, #list)]
            return toHash(pick)
        end
        -- fallback to global pedlist
        local name = Config.pedlist[math.random(1, #Config.pedlist)]
        return toHash(name)
    end

    local npc = {}
    npc.hash = choosePedHashForItem(drugs)
    local npcOk = _loadModel(npc.hash, 3500)
    if not npcOk then
        _forceHustleReset(true)
        ShowNotification("Buyer couldn't be found right now.")
        return
    end
    npc.offset = Config.Offsets[math.random(1, #Config.Offsets)]
    npc.coords = GetOffsetFromEntityInWorldCoords(playerPed, npc.offset.x, npc.offset.y, npc.offset.z)
    
    local retval, npcz = GetGroundZFor_3dCoord(npc.coords.x, npc.coords.y, npc.coords.z, 0)
    
    if retval == false then
        ShowNotification("Buyer Couldn't Make It!")
        _forceHustleReset(true)
        return
    end
    
    npc.ped = CreatePed(4, npc.hash, npc.coords.x, npc.coords.y, npcz, 0.0, true, false)
    SetEntityAsMissionEntity(npc.ped)
    PlaceObjectOnGroundProperly(npc.ped)
    _makeBuyerFearless(npc.ped)
    _activeBuyerPed = npc.ped
    _activeBuyerBusy = false
    local pedSpeed = (Config.Buyer and Config.Buyer.speed) or 1.5
    local stopDist = (Config.Buyer and tonumber(Config.Buyer.stopDistance)) or 1.8
    if stopDist < 1.2 then stopDist = 1.2 end
    if stopDist > 3.0 then stopDist = 3.0 end
    _makeBuyerFearless(npc.ped)
    TaskGoToEntity(npc.ped, playerPed, -1, stopDist, pedSpeed, 0, 0)
    local start_time = GetGameTimer()
    local targetAdded = false
    local saleFinished = false
    local sessionToken = tostring(GetGameTimer()) .. ':' .. tostring(math.random(1000, 9999))

    local function closeSession(keepPed)
        if not keepPed then
            _cleanupActiveBuyer()
        else
            _activeBuyerPed = nil
            _activeBuyerBusy = false
            _activeBuyerBusyToken = 0
            _activeBuyerOptionName = nil
        end
        selling_drugs = false
        can_i_sell = true
        _hustleStartedAt = 0
        _setInvBusyState(false)
        saleFinished = true
    end

    while true do
        if saleFinished then
            break
        end
        if not DoesEntityExist(npc.ped) then
            closeSession(true)
            break
        end

        if Currweapon then
            _cleanupActiveBuyer()
            selling_drugs = false
            can_i_sell = true
            _hustleStartedAt = 0
            _setInvBusyState(false)
            saleFinished = true
            ShowNotification("You scared your client off")
            break
        end

        local dist = GetDistanceBetweenCoords(GetEntityCoords(npc.ped).x,GetEntityCoords(npc.ped).y, GetEntityCoords(npc.ped).z, GetEntityCoords(playerPed).x, GetEntityCoords(playerPed).y, GetEntityCoords(playerPed).z, true)
        if dist < 2.0 and not targetAdded then
            if GetResourceState('ox_target') ~= 'started' then
                _forceHustleReset(true)
                ShowNotification('ox_target is not started.')
                break
            end
            local previewCount = lib.callback.await('Partay_hustle:getSalePreview', false, drugs) or 0
            if previewCount <= 0 then
                ShowNotification("You don't have any products twin!")
                _forceHustleReset(true)
                break
            end
            count = previewCount

            targetAdded = true
            ClearPedTasks(npc.ped)
            _makeBuyerFearless(npc.ped)
            TaskTurnPedToFaceEntity(npc.ped, playerPed, 1500)
            FreezeEntityPosition(npc.ped, true)
            _makeBuyerFearless(npc.ped)

            local ped = npc.ped
            local targetOptionName = (_buyerTargetOption .. ':' .. sessionToken)
            _activeBuyerOptionName = targetOptionName
            local targetLabel = ('Sell %sx %s'):format(tostring(count), _resolveItemLabel(drugs))
            exports.ox_target:addLocalEntity(ped, {
                {
                    name = targetOptionName,
                    icon = 'fa-solid fa-handshake',
                    label = targetLabel,
                    distance = 2.0,
                    canInteract = function(entity)
                        return entity == _activeBuyerPed and not _activeBuyerBusy and selling_drugs and not Currweapon
                    end,
                    onSelect = function(data)
                        CreateThread(function()
                            local ok, err = pcall(function()
                                if saleFinished then return end
                                if _activeBuyerBusy then return end
                                if data.entity ~= _activeBuyerPed then return end
                                if not selling_drugs then return end

                                _activeBuyerBusy = true
                                _activeBuyerBusyToken = GetGameTimer() or 0
                                local myToken = _activeBuyerBusyToken

                                -- Failsafe in case callback/flow hangs and leaves player stuck.
                                CreateThread(function()
                                    Wait(9000)
                                    if _activeBuyerBusy and _activeBuyerBusyToken == myToken then
                                        if Config.Debug then
                                            print('[Partay_hustle] safety reset: buyer interaction timeout')
                                        end
                                        closeSession(false)
                                    end
                                end)

                                local currentCount = lib.callback.await('Partay_hustle:getItemCount', false, drugs) or 0
                                if currentCount <= 0 then
                                    ShowNotification("You don't have any products twin!")
                                    closeSession(false)
                                    return
                                end
                                local finalCount = math.min(count or 1, currentCount)
                                if finalCount < 1 then
                                    ShowNotification("You don't have any products twin!")
                                    closeSession(false)
                                    return
                                end

                                local denialChance = _getBuyerDenialChance(drugs)
                                if denialChance > 0 and math.random(1, 100) <= denialChance then
                                    _playPedDecline(ped, PlayerPedId())
                                    ShowNotification("They declined the deal.")
                                    Wait(1200)
                                    saleFinished = true
                                    _removeBuyerTarget(ped, _activeBuyerOptionName)
                                    _activeBuyerPed = nil
                                    _activeBuyerBusy = false
                                    _activeBuyerBusyToken = 0
                                    _activeBuyerOptionName = nil
                                    selling_drugs = false
                                    can_i_sell = true
                                    _hustleStartedAt = 0
                                    _setInvBusyState(false)
                                    _sendBuyerAwayAndDelete(ped, PlayerPedId())
                                    return
                                end

                                saleFinished = true
                                _removeBuyerTarget(ped, _activeBuyerOptionName)
                                _activeBuyerPed = nil
                                _activeBuyerBusy = false
                                _activeBuyerBusyToken = 0
                                _activeBuyerOptionName = nil
                                sell_ped(ped, drugs, finalCount)
                            end)
                            if not ok then
                                if Config.Debug then
                                    print(('[Partay_hustle] onSelect error: %s'):format(tostring(err)))
                                end
                                closeSession(false)
                            end
                        end)
                    end
                }
            })

            if Config.Debug then
                print(('[Partay_hustle] buyer target armed %s (%s)'):format(tostring(ped), sessionToken))
            end
        elseif GetGameTimer() - start_time > 30000 then
            ShowNotification("He Found A Hustler With A Better Price!")
            _forceHustleReset(true)
            break
        end
        Wait(0)
        --   print(dist)
    end
end)

function sell_ped(ped, drugs, count)
    if not ped or not DoesEntityExist(ped) then
        _forceHustleReset(true)
        return
    end
    local playerPed = PlayerPedId()
    FreezeEntityPosition(ped, false)
    _makeBuyerFearless(ped)
    local pedCoords = GetEntityCoords(ped)
    local playerCoords = GetEntityCoords(playerPed)

    ClearPedTasks(ped)
    ClearPedTasks(playerPed)
    _makeBuyerFearless(ped)
    TaskTurnPedToFaceEntity(playerPed, ped, -1)
    TaskTurnPedToFaceEntity(ped, playerPed, -1)
    
    if not _loadAnimDict("mp_common", 2500) then
        _sendBuyerAwayAndDelete(ped, playerPed)
        _forceHustleReset(false)
        return
    end
    
    -- Determine prop from config per item; fallback to Config.ItemPropFallback or generic
    local cfgEntry = Config.DrugList[drugs]
    local propModel = (cfgEntry and cfgEntry.prop) or Config.ItemPropFallback or 'prop_meth_bag_01'
    local propHash = type(propModel) == 'number' and propModel or GetHashKey(propModel)
    
    Wait(500)
    if propModel ~= nil then
        if IsModelInCdimage(propHash) and IsModelValid(propHash) then
            local propOk = _loadModel(propHash, 2000)
            if propOk and HasModelLoaded(propHash) then
                propEntity = CreateObject(propHash, 0, 0, 0, true, true, true)
                AttachEntityToEntity(propEntity, playerPed, GetPedBoneIndex(playerPed, 28422), 0.05, 0.01, -0.05, 0.0, 180.0, 0.0, true, true, false, true, 1, true)
            elseif Config.Debug then
                print(('[Partay_hustle] Prop load timeout for %s'):format(tostring(propModel)))
            end
        elseif Config.Debug then
            print(('[Partay_hustle] Invalid prop model: %s'):format(tostring(propModel)))
        end
    end
    TaskPlayAnim(playerPed, "mp_common", "givetake1_a", 8.0, -8.0, -1, 50, 0, false, false, false)
    
    Wait(1000)
    if propEntity and DoesEntityExist(propEntity) then
        AttachEntityToEntity(propEntity, ped, GetPedBoneIndex(ped, 60309), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end
    local cashNote = nil
    local cashOk = _loadModel(`prop_anim_cash_note`, 2000)
    if cashOk then
        cashNote = CreateObject(`prop_anim_cash_note`, 0, 0, 0, true, true, true)
    end
    if not cashNote or not DoesEntityExist(cashNote) then
        if propEntity and DoesEntityExist(propEntity) then
            DeleteEntity(propEntity)
            propEntity = nil
        end
        _sendBuyerAwayAndDelete(ped, playerPed)
        _forceHustleReset(false)
        return
    end
    AttachEntityToEntity(cashNote, ped, GetPedBoneIndex(ped, 60309), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    
    TaskPlayAnim(ped, "mp_common", "givetake1_a", 8.0, -8.0, -1, 50, 0, false, false, false)
    Wait(500)
    AttachEntityToEntity(cashNote, playerPed, GetPedBoneIndex(playerPed, 28422), 0.05, 0.01, -0.05, 0.0, 180.0, 0.0, true, true, false, true, 1, true)
    
    Wait(1500)
    ClearPedTasks(playerPed)
    ClearPedTasks(ped)
    if cashNote and DoesEntityExist(cashNote) then
        DeleteEntity(cashNote)
    end
    if propEntity and DoesEntityExist(propEntity) then
        DeleteEntity(propEntity)
        propEntity = nil
    end
    Wait(500)
    
    TriggerServerEvent("Partay_hustle:server:sell", drugs, count)
    _sendBuyerAwayAndDelete(ped, playerPed)
    selling_drugs = false
    can_i_sell = true
    _hustleStartedAt = 0
    _setInvBusyState(false)
end

function getDrugs()
    local availableDrug, availableDrugCount = lib.callback.await('Partay_hustle:getallavailableDrugs', false)
    if availableDrug and availableDrugCount then
        return availableDrug, availableDrugCount
    end
    return nil, 0
end

RegisterNetEvent("Partay_hustle:client:notify", function (type, msg)
    lib.notify({ type = type or 'inform', description = msg, position = 'topcenter' })
end)

RegisterNetEvent("Partay_hustle:client:saleNotify", function(data)
    data = data or {}
    SendNUIMessage({
        action = 'saleNotify',
        label = data.label or 'Product',
        quantity = data.quantity or 0,
        total = data.total or 0,
        points = data.points or 0
    })
end)

-- CreateThread(function()
--     for index, v in pairs(Config.Zones) do
--         if v.isHotSpot then
--             CreateBlip(v.coords, v.maxRange, 200, 42)
--         end
--     end
-- end)

function CreateBlip(coords, blipradius, alpha, color)
    local ZoneBlip = AddBlipForRadius(coords.x, coords.y, coords.z, blipradius)
    SetBlipHighDetail(ZoneBlip, true)
    SetBlipColour(ZoneBlip, color)
    SetBlipAlpha(ZoneBlip, alpha)
    SetBlipAsShortRange(ZoneBlip, true)
    SetBlipAlpha(ZoneBlip, alpha)
    return ZoneBlip
end

function ShowNotification(message)
    lib.notify({type = "inform", description = message, position = 'topcenter'})
end

-- QoL: Hotspot blip toggling and help
local hotspotBlips = {}
local hotspotsVisible = false

local function clearHotspotBlips()
    for _, b in ipairs(hotspotBlips) do
        if b and DoesBlipExist(b) then
            RemoveBlip(b)
        end
    end
    hotspotBlips = {}
end

local function showHotspotBlips()
    clearHotspotBlips()
    local hasFlagged = false
    for _, v in pairs(Config.Zones) do
        if v.isHotSpot then hasFlagged = true break end
    end
    for _, v in pairs(Config.Zones) do
        if (hasFlagged and v.isHotSpot) or (not hasFlagged) then
            local blip = CreateBlip(v.coords, v.maxRange or 50.0, hasFlagged and 160 or 120, 42)
            table.insert(hotspotBlips, blip)
        end
    end
end

local function setHotspots(state)
    if state == nil then state = not hotspotsVisible end
    hotspotsVisible = state
    if hotspotsVisible then
        showHotspotBlips()
        ShowNotification(((_L and _L('hotspots_on')) or 'Hotspots: ON'))
    else
        clearHotspotBlips()
        ShowNotification(((_L and _L('hotspots_off')) or 'Hotspots: OFF'))
    end
end

RegisterNetEvent('Partay_hustle:client:toggleHotspots', function(state)
    setHotspots(state)
end)

-- Allow using an ox_inventory item (e.g., trap_phone) to start a hustle
RegisterNetEvent('Partay_hustle:client:startHustle', function()
    ExecuteCommand(_hustleCmd)
end)

RegisterCommand(_hotspotsCmd, function(source, args)
    local arg = tostring(args[1] or 'toggle')
    if arg == 'on' then setHotspots(true)
    elseif arg == 'off' then setHotspots(false)
    else setHotspots(nil) end
end)

-- Cancel current hustle
RegisterCommand(_cancelCmd, function()
    if selling_drugs then
        selling_drugs = false
        can_i_sell = true
        _hustleStartedAt = 0
        _cleanupActiveBuyer()
        _setInvBusyState(false)
        if propEntity and DoesEntityExist(propEntity) then
            DeleteEntity(propEntity)
            propEntity = nil
        end
        ShowNotification('Hustle canceled.')
    else
        ShowNotification('No active hustle to cancel.')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    selling_drugs = false
    can_i_sell = true
    _hustleStartedAt = 0
    _cleanupActiveBuyer()
    _setInvBusyState(false)
end)

-- Chat suggestions for player commands (if default chat is running)
CreateThread(function()
    -- Give chat a moment to be ready after resource start
    Wait(1000)
    -- These events are no-ops if the default chat isn’t loaded
    TriggerEvent('chat:addSuggestion', '/'.._hustleCmd, 'Start the Sale of item')
    TriggerEvent('chat:addSuggestion', '/'.._lbCmd, 'Show dealer leaderboard')
    TriggerEvent('chat:addSuggestion', '/'.._hotspotsCmd, 'Toggle hotspot blips (on|off|toggle)', {
        { name = 'mode', help = 'on | off | toggle' }
    })
    TriggerEvent('chat:addSuggestion', '/'.._cancelCmd, 'Cancel your active hustle')
end)

-- Simple police blip helper used by basic dispatch fallback
RegisterNetEvent('Partay_hustle:client:policeBlip', function(coords, seconds, radius, color, alpha)
    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radius or 60.0)
    SetBlipHighDetail(blip, true)
    SetBlipColour(blip, color or 1)
    SetBlipAlpha(blip, alpha or 160)
    SetBlipAsShortRange(blip, true)
    local untilTime = GetGameTimer() + (math.floor((seconds or 30)) * 1000)
    CreateThread(function()
        while GetGameTimer() < untilTime do
            Wait(250)
        end
        if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)


