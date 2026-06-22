local Target = _G.PartayTarget or {}
_G.PartayTarget = Target

local callbacks
local states = {}

local pedStreaming = Config.PedStreaming or {}
local streamingEnabled = pedStreaming.Enabled ~= false
local spawnDistance = pedStreaming.SpawnDistance or 30.0
local despawnDistance = pedStreaming.DespawnDistance or (spawnDistance + 10.0)
local checkInterval = pedStreaming.CheckInterval or 1000

if despawnDistance <= spawnDistance then
    despawnDistance = spawnDistance + 5.0
end

local oxTarget = exports and exports.ox_target or nil

local function toVector3(value)
    if type(value) == 'vector3' then
        return value
    end
    if type(value) == 'table' then
        local x = value.x or value[1] or 0.0
        local y = value.y or value[2] or 0.0
        local z = value.z or value[3] or 0.0
        return vector3(x + 0.0, y + 0.0, z + 0.0)
    end
    return nil
end

local function ensureModelHash(model)
    if type(model) == 'number' then
        return model
    end
    if type(model) == 'string' and model ~= '' then
        return joaat(model)
    end
    return nil
end

local function loadModel(hash)
    if not hash or hash == 0 then return false end
    if HasModelLoaded(hash) then return true end

    RequestModel(hash)
    local expires = GetGameTimer() + 5000

    while not HasModelLoaded(hash) do
        if GetGameTimer() >= expires then
            return false
        end
        Citizen.Wait(0)
    end

    return true
end

local function unloadModel(hash)
    if not hash or hash == 0 then return end
    SetModelAsNoLongerNeeded(hash)
end

local function loadAnimDict(dict)
    if not dict or dict == '' then return false end
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local expires = GetGameTimer() + 5000

    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() >= expires then
            return false
        end
        Citizen.Wait(0)
    end

    return true
end

local function stopPedAnimation(state)
    if not state or not state.ped then return end
    ClearPedTasksImmediately(state.ped)
end

local function applyPedAnimation(state)
    if not state or not state.ped then return end
    local anim = state.animation
    if not anim then return end

    if anim.scenario then
        ClearPedTasksImmediately(state.ped)
        FreezeEntityPosition(state.ped, false)
        TaskStartScenarioInPlace(state.ped, anim.scenario, 0, true)
        if anim.freezePosition == false then
            FreezeEntityPosition(state.ped, false)
        else
            FreezeEntityPosition(state.ped, true)
        end
        return
    end

    local dict = anim.dict or anim.animDict or anim.library
    local clip = anim.clip or anim.anim or anim.name
    if not dict or dict == '' or not clip or clip == '' then return end

    if not loadAnimDict(dict) then
        if Config.Debug then
            print(('[Partay_claimpacks] Failed to load anim dict %s for %s'):format(dict, state.location and state.location.id or 'unknown'))
        end
        return
    end

    ClearPedTasksImmediately(state.ped)

    local blendIn = anim.blendIn or anim.blendInSpeed or 4.0
    local blendOut = anim.blendOut or anim.blendOutSpeed or 4.0
    local duration = anim.duration or -1
    local flag = anim.flag or anim.flags or 1
    local rate = anim.playbackRate or 1.0
    local lockX = anim.lockX == true
    local lockY = anim.lockY == true
    local lockZ = anim.lockZ == true

    TaskPlayAnim(state.ped, dict, clip, blendIn, blendOut, duration, flag, rate, lockX, lockY, lockZ)

    if anim.freezePosition == false then
        FreezeEntityPosition(state.ped, false)
    else
        FreezeEntityPosition(state.ped, true)
    end

    if anim.keepDictLoaded ~= true then
        RemoveAnimDict(dict)
    end
end

local function canUseTarget()
    if oxTarget then
        return true
    end

    if Config.Debug then
        print('[Partay_claimpacks] ox_target export not found; targets disabled.')
    end

    return false
end

local function removeTarget(state)
    if not state.targetAdded or not state.ped then return end

    if oxTarget then
        local ok, err = pcall(oxTarget.removeLocalEntity, oxTarget, state.ped, state.targetName)
        if not ok and Config.Debug then
            print(('[Partay_claimpacks] Failed to remove target for %s: %s'):format(state.location.id, tostring(err)))
        end
    end

    state.targetAdded = nil
end

local function deletePed(state)
    if not state.ped then return end

    stopPedAnimation(state)
    removeTarget(state)

    if DoesEntityExist(state.ped) then
        DeletePed(state.ped)
    end

    state.ped = nil
end

local function addTarget(state)
    if not oxTarget or state.targetAdded or not state.ped then return end

    local location = state.location
    local targetData = location.target or {}

    local option = {
        name = state.targetName,
        icon = targetData.icon or 'fa-solid fa-gift',
        label = targetData.label or location.label or 'Claim',
        distance = targetData.distance or 2.0,
        onSelect = function()
            if callbacks and callbacks.onSelect then
                callbacks.onSelect(location.id)
            end
        end,
        canInteract = function()
            if callbacks and callbacks.canInteract then
                return callbacks.canInteract(location.id)
            end
            return true
        end
    }

    if targetData.requirements then
        option.requirements = targetData.requirements
    end
    if targetData.groups then
        option.groups = targetData.groups
    end
    if targetData.items then
        option.items = targetData.items
    end
    if targetData.bones then
        option.bones = targetData.bones
    end

    local ok, err = pcall(oxTarget.addLocalEntity, oxTarget, state.ped, { option })
    if not ok then
        if Config.Debug then
            print(('[Partay_claimpacks] Failed to add target for %s: %s'):format(location.id, tostring(err)))
        end
        return
    end

    state.targetAdded = true
end

local function spawnPed(state)
    if state.ped or not state.model or not state.coords then return end

    if not loadModel(state.model) then
        if Config.Debug then
            print(('[Partay_claimpacks] Failed to load model for %s'):format(state.location.id))
        end
        return
    end

    local ped = CreatePed(4, state.model, state.coords.x, state.coords.y, state.coords.z, state.heading, false, true)
    if not ped or ped == 0 then
        if Config.Debug then
            print(('[Partay_claimpacks] Failed to create ped for %s'):format(state.location.id))
        end
        unloadModel(state.model)
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityHeading(ped, state.heading)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedFleeAttributes(ped, 0, false)

    state.ped = ped

    applyPedAnimation(state)

    addTarget(state)
    unloadModel(state.model)
end

local function updateStreaming()
    if not streamingEnabled then
        for _, state in pairs(states) do
            spawnPed(state)
        end
        return
    end

    Citizen.CreateThread(function()
        while true do
            local playerPed = PlayerPedId()
            if playerPed and playerPed ~= 0 then
                local playerCoords = GetEntityCoords(playerPed)
                for _, state in pairs(states) do
                    if state.coords then
                        local distance = #(playerCoords - state.coords)
                        if distance <= spawnDistance then
                            if not state.ped then
                                spawnPed(state)
                            else
                                addTarget(state)
                            end
                        elseif state.ped and distance >= despawnDistance then
                            deletePed(state)
                        end
                    end
                end
            end
            Citizen.Wait(checkInterval)
        end
    end)
end

function Target.init(locations, cb)
    callbacks = cb or {}

    canUseTarget()

    for _, location in ipairs(locations or {}) do
        if location.id and location.ped and location.ped.model and location.ped.coords then
            local coords = toVector3(location.ped.coords)
            local modelHash = ensureModelHash(location.ped.model)
            states[location.id] = {
                location = location,
                coords = coords,
                heading = location.ped.heading or 0.0,
                model = modelHash,
                animation = location.ped.animation,
                targetName = ('partay_claimpacks:%s'):format(location.id)
            }
        end
    end

    updateStreaming()
end

function Target.refresh(locationId)
    local state = states[locationId]
    if not state then return end
    removeTarget(state)
    applyPedAnimation(state)
    addTarget(state)
end

function Target.cleanup()
    for _, state in pairs(states) do
        deletePed(state)
    end
    states = {}
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Target.cleanup()
end)
