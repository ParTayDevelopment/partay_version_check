local resourceName = GetCurrentResourceName()

lib.locale()

local oxTarget = exports.ox_target
local debugEnabled = Config.Debug
local promptPosition = Config.PromptPosition or 'left-center'
local DEBUG_TOOL_PED_MODEL = 's_f_y_stripper_01'
local DEBUG_TOOL_MOVE_STEP = 0.02
local DEBUG_TOOL_FAST_MULTIPLIER = 5.0
local DEBUG_TOOL_VERTICAL_STEP = 0.01
local DEBUG_TOOL_HEADING_STEP = 1.0

local poles = Config.Poles or {}
local danceZones = Config.DanceZones or {}
local poleMap = {}
local danceZoneMap = {}
local poleModels = {}
local poleOptions = {}
local poleZones = {}
local danceZoneTargets = {}
local pedHandles = {}
local pedTargets = {}
local pedCycles = {}
local activePoleStates = {}
local activeZoneStates = {}
local currentShiftZoneId = nil
local isDancing = false
local isSelectingTip = false
local currentPlayerJobName = nil


local stopUi
local placementTool = {
    active = false,
    ped = nil,
    heading = 0.0,
    animationIndex = 1,
    scene = nil,
    contextId = resourceName .. ':placement:animations'
}
local tipPtfxTool = {
    active = false,
    prop = nil,
    handle = nil,
    asset = nil,
    offset = vec3(0.0, 0.0, 0.0),
    rotation = vec3(0.0, 180.0, 0.0)
}
local activeTipProps = {
    attached = {},
    dropped = {}
}

local animationList = Config.Animations or {}
local defaultAnimationIndices = {}
for index = 1, #animationList do
    defaultAnimationIndices[index] = index
end

local function normalizeJobName(jobName)
    if type(jobName) ~= 'string' then return nil end
    jobName = jobName:lower():gsub('^%s+', ''):gsub('%s+$', '')
    if jobName == '' then return nil end
    return jobName
end

local function resolveJobNameFromData(data)
    if type(data) ~= 'table' then
        return nil
    end

    return normalizeJobName(data.name or data.id or data.label)
end

local function setCurrentPlayerJobName(jobData)
    if type(jobData) == 'string' then
        currentPlayerJobName = normalizeJobName(jobData)
        return currentPlayerJobName
    end

    currentPlayerJobName = resolveJobNameFromData(jobData)
    return currentPlayerJobName
end

local function refreshCurrentPlayerJobName()
    if LocalPlayer and LocalPlayer.state then
        local stateJob = LocalPlayer.state.job or LocalPlayer.state['qbx:job']
        local resolvedStateJob = resolveJobNameFromData(stateJob)
        if resolvedStateJob then
            currentPlayerJobName = resolvedStateJob
            return currentPlayerJobName
        end
    end

    if GetResourceState('es_extended') == 'started' then
        local ok, esx = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and esx and esx.PlayerData then
            local resolvedEsxJob = resolveJobNameFromData(esx.PlayerData.job)
            if resolvedEsxJob then
                currentPlayerJobName = resolvedEsxJob
                return currentPlayerJobName
            end
        end
    end

    if GetResourceState('qb-core') == 'started' then
        local ok, qb = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and qb and qb.Functions and qb.Functions.GetPlayerData then
            local resolvedQbJob = resolveJobNameFromData(qb.Functions.GetPlayerData().job)
            if resolvedQbJob then
                currentPlayerJobName = resolvedQbJob
                return currentPlayerJobName
            end
        end
    end

    if GetResourceState('qbx_core') == 'started' then
        local ok, playerData = pcall(function()
            return exports.qbx_core:GetPlayerData()
        end)
        if ok then
            local resolvedQboxJob = resolveJobNameFromData(playerData and playerData.job)
            if resolvedQboxJob then
                currentPlayerJobName = resolvedQboxJob
                return currentPlayerJobName
            end
        end
    end

    currentPlayerJobName = nil
    return currentPlayerJobName
end

local function getCurrentPlayerJobName()
    if currentPlayerJobName ~= nil then
        return currentPlayerJobName
    end

    return refreshCurrentPlayerJobName()
end

local function getZoneRequiredJobLocal(zoneId)
    local zone = zoneId and danceZoneMap[zoneId] or nil
    if not zone or type(zone.society) ~= 'table' then
        return nil
    end

    return normalizeJobName(zone.society.job or zone.society.name)
end

local function getAnimationIndicesForPole(pole)
    if pole and type(pole.animations) == 'table' and #pole.animations > 0 then
        local indices = {}
        for _, idx in ipairs(pole.animations) do
            idx = tonumber(idx)
            if idx and animationList[idx] then
                indices[#indices + 1] = idx
            end
        end
        if #indices > 0 then
            return indices
        end
    end

    return defaultAnimationIndices
end

local function getAnimationIndicesForZone(zone)
    return getAnimationIndicesForPole(zone)
end

local function formatCurrency(amount)
    local integer = math.floor(amount or 0)
    local sign = integer < 0 and '-' or ''
    integer = math.abs(integer)
    local str = tostring(integer)
    local count
    while true do
        str, count = str:gsub('^(%d+)(%d%d%d)', '%1,%2')
        if count == 0 then break end
    end
    return sign .. str
end
local taxInfoCache = {
    rate = nil,
    societyEnabled = Config.Society and Config.Society.enabled ~= false,
    hasDirtyMoney = false,
    dirtyBalance = 0,
    cleanBalance = 0,
    availableBalance = 0,
    updated = 0
}

local TAX_CACHE_DURATION = 30000

local function computeWashEstimate(amount, taxRate, societyEnabled, hasDirtyMoney)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local effectiveRate = (hasDirtyMoney ~= false) and (tonumber(taxRate) or 0) or 0
    if effectiveRate < 0 then
        effectiveRate = 0
    end
    local taxAmount = 0
    if effectiveRate > 0 and amount > 0 then
        taxAmount = math.floor(amount * effectiveRate / 100)
        if taxAmount > amount then
            taxAmount = amount
        end
    end
    local clean = amount - taxAmount
    if clean < 0 then clean = 0 end
    return {
        clean = clean,
        taxAmount = taxAmount,
        taxRate = effectiveRate
    }
end

local function buildEstimateDescription(estimate, societyEnabled, hasDirtyMoney)
    local description = locale('tip_slider_description', string.format('%.2f', estimate.taxRate))
    description = description .. '\n' .. locale(
        'tip_slider_description_amounts',
        formatCurrency(estimate.taxAmount),
        formatCurrency(estimate.clean)
    )

    if hasDirtyMoney ~= false then
        description = description .. '\n' .. locale('tip_slider_description_note_dirty')
    else
        description = description .. '\n' .. locale('tip_slider_description_note_clean')
    end

    return description
end

local function fetchTaxInfo(forceRefresh)
    local now = GetGameTimer()
    if not forceRefresh and taxInfoCache.rate ~= nil and now - (taxInfoCache.updated or 0) < TAX_CACHE_DURATION then
        return taxInfoCache
    end

    taxInfoCache.rate = Config.SocietyCut or 0
    taxInfoCache.societyEnabled = Config.Society and Config.Society.enabled ~= false
    taxInfoCache.hasDirtyMoney = false
    taxInfoCache.dirtyBalance = 0
    taxInfoCache.cleanBalance = 0
    taxInfoCache.availableBalance = 0
    taxInfoCache.updated = now

    if not lib or not lib.callback or not lib.callback.await then
        return taxInfoCache
    end

    local result = lib.callback.await(resourceName .. ':getTipTaxData', false)
    if type(result) ~= 'table' then
        result = lib.callback.await(resourceName .. ':getTaxData', false)
    end
    if type(result) == 'table' then
        if result.taxRate ~= nil then
            local rate = tonumber(result.taxRate)
            if rate then
                taxInfoCache.rate = rate
            end
        end
        if result.societyEnabled ~= nil then
            taxInfoCache.societyEnabled = result.societyEnabled ~= false
        end
        taxInfoCache.hasDirtyMoney = result.hasDirtyMoney == true
        taxInfoCache.dirtyBalance = math.max(0, math.floor(tonumber(result.dirtyBalance) or 0))
        taxInfoCache.cleanBalance = math.max(0, math.floor(tonumber(result.cleanBalance) or 0))
        taxInfoCache.availableBalance = math.max(0, math.floor(tonumber(result.availableBalance) or 0))
        taxInfoCache.updated = now
    end

    return taxInfoCache
end

RegisterNetEvent(resourceName .. ':client:UpdateTaxRate', function(taxRate)
    taxInfoCache.rate = tonumber(taxRate) or Config.SocietyCut or 0
    taxInfoCache.updated = 0
end)

local function promptTipAmount(initialAmount, tipSettings)
    if not lib or not lib.inputDialog then
        return initialAmount
    end

    local taxInfo = fetchTaxInfo(true)
    local affordableMax = tipSettings.alignMax(taxInfo.availableBalance or 0)
    if affordableMax < tipSettings.min then
        return false
    end

    local amount = tipSettings.align(initialAmount or tipSettings.default, affordableMax)
    if amount < tipSettings.min then amount = tipSettings.min end

    local estimate = computeWashEstimate(amount, taxInfo.rate, taxInfo.societyEnabled, taxInfo.hasDirtyMoney)
    local dialog = lib.inputDialog(
        tipSettings.title,
        {
            {
                type = 'slider',
                label = locale('tip_slider_label_tax', tipSettings.label, string.format('%.2f', estimate.taxRate)),
                default = amount,
                min = tipSettings.min,
                max = affordableMax,
                step = tipSettings.step,
                icon = tipSettings.icon,
                description = buildEstimateDescription(estimate, taxInfo.societyEnabled, taxInfo.hasDirtyMoney)
            }
        }
    )

    if not dialog then
        return nil
    end

    local chosen = tipSettings.align(dialog[1], affordableMax)
    local finalEstimate = computeWashEstimate(chosen, taxInfo.rate, taxInfo.societyEnabled, taxInfo.hasDirtyMoney)
    return chosen, finalEstimate
end

local function loadAnimDict(dict)
    if not dict or dict == '' then return end
    if HasAnimDictLoaded(dict) then return end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(10)
    end
end

local function getTipSettings()
    local opts = Config.TipOptions or {}
    local min = math.floor(tonumber(opts.min) or 1)
    if min < 0 then min = 0 end
    local max = math.floor(tonumber(opts.max) or min)
    if max < min then max = min end
    local step = math.floor(tonumber(opts.step) or 1)
    if step < 1 then step = 1 end
    local defaultValue = tonumber(opts.default)

    local function alignMax(value)
        value = tonumber(value)
        if not value then
            value = max
        end
        value = math.floor(value)
        if value < min then
            return value
        end
        if value > max then value = max end
        if step > 1 then
            local offset = value - min
            local remainder = offset % step
            value = value - remainder
        end
        if value > max then value = max end
        return value
    end

    local function align(value, dynamicMax)
        value = tonumber(value)
        if not value then
            value = defaultValue or min
        end
        value = math.floor(value)
        local cappedMax = alignMax(dynamicMax or max)
        if value < min then value = min end
        if value > cappedMax then value = cappedMax end
        if step > 1 then
            local offset = value - min
            local remainder = offset % step
            value = value - remainder
            if value < min then value = min end
        end
        if value > cappedMax then value = cappedMax end
        return value
    end

    local default = align(defaultValue or min)

    return {
        min = min,
        max = max,
        step = step,
        default = default,
        title = opts.title or locale('tip_slider_title'),
        label = opts.label or locale('tip_slider_label'),
        icon = opts.icon,
        align = align,
        alignMax = alignMax
    }
end

local function resolveAnimationIndex(pole, requestedIndex)
    local indices = getAnimationIndicesForPole(pole)
    if #indices == 0 then return nil end

    if requestedIndex then
        for _, idx in ipairs(indices) do
            if idx == requestedIndex and animationList[idx] then
                return idx
            end
        end
    end

    for _, idx in ipairs(indices) do
        if animationList[idx] then
            return idx
        end
    end

    return nil
end

local function resolveAnimation(pole, requestedIndex)
    local index = resolveAnimationIndex(pole, requestedIndex)
    if not index then return nil end
    return animationList[index], index
end

local function getAnimationDisplayLabel(index, animation)
    local resolvedAnimation = animation or (index and animationList[index]) or nil
    local baseLabel = resolvedAnimation and resolvedAnimation.label or locale('dance_text', index or '?')

    if index then
        return ('%s. %s'):format(index, baseLabel)
    end

    return baseLabel
end

local function playPedAnimation(ped, animation)
    if not animation or not animation.dict or not animation.anim then return end
    loadAnimDict(animation.dict)
    TaskPlayAnim(ped, animation.dict, animation.anim, animation.blendIn or 8.0, animation.blendOut or -8.0, animation.duration or -1, animation.flag or 1, animation.speed or 0.0, false, false, false)
end

local function awaitServerCallback(name, ...)
    if not lib or not lib.callback or not lib.callback.await then
        return nil
    end

    local attempts = 10
    local delay = 250

    for _ = 1, attempts do
        local ok, result = pcall(lib.callback.await, name, false, ...)
        if ok then
            return result
        end

        Wait(delay)
    end

    return nil
end

local function stopPlacementTool()
    if placementTool.scene then
        NetworkStopSynchronisedScene(placementTool.scene)
        placementTool.scene = nil
    end

    if placementTool.ped and DoesEntityExist(placementTool.ped) then
        ClearPedTasksImmediately(placementTool.ped)
        DeleteEntity(placementTool.ped)
    end

    placementTool.active = false
    placementTool.ped = nil
    placementTool.heading = 0.0
    stopUi()
end

local function playPlacementAnimation()
    local ped = placementTool.ped
    if not ped or not DoesEntityExist(ped) then return end

    local animation = animationList[placementTool.animationIndex]
    if not animation then return end

    ClearPedTasksImmediately(ped)

    if placementTool.scene then
        NetworkStopSynchronisedScene(placementTool.scene)
        placementTool.scene = nil
    end

    if animation.dict and animation.anim then
        loadAnimDict(animation.dict)
        TaskPlayAnim(
            ped,
            animation.dict,
            animation.anim,
            animation.blendIn or 8.0,
            animation.blendOut or -8.0,
            -1,
            animation.flag or 1,
            animation.speed or 0.0,
            false,
            false,
            false
        )
        return
    end

    if animation.scenario then
        TaskStartScenarioInPlace(ped, animation.scenario, 0, true)
        return
    end

    playPedAnimation(ped, animation)
end

local function formatVector4(coords, heading)
    return ('vector4(%.4f, %.4f, %.4f, %.4f)'):format(coords.x, coords.y, coords.z, heading)
end

local function showPlacementUi()
    if not placementTool.active or not placementTool.ped or not DoesEntityExist(placementTool.ped) then return end

    local coords = GetEntityCoords(placementTool.ped)
    local animation = animationList[placementTool.animationIndex]
    local label = getAnimationDisplayLabel(placementTool.animationIndex, animation)
    local text = table.concat({
        locale('placement_tool_title'),
        ('Animation: %s'):format(label),
        ('Position: %s'):format(formatVector4(coords, placementTool.heading)),
        locale('placement_tool_controls_move'),
        locale('placement_tool_controls_manage')
    }, '\n')
    lib.showTextUI(text, { position = promptPosition })
end

local function updatePlacementTransform(deltaX, deltaY, deltaZ, deltaHeading)
    local ped = placementTool.ped
    if not ped or not DoesEntityExist(ped) then return end

    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local right = vector3(-forward.y, forward.x, 0.0)

    local newCoords = vector3(
        coords.x + (forward.x * deltaY) + (right.x * deltaX),
        coords.y + (forward.y * deltaY) + (right.y * deltaX),
        coords.z + deltaZ
    )

    placementTool.heading = (placementTool.heading + deltaHeading) % 360.0
    SetEntityCoordsNoOffset(ped, newCoords.x, newCoords.y, newCoords.z, false, false, false)
    SetEntityHeading(ped, placementTool.heading)
    showPlacementUi()
end

local function setPlacementAnimation(animationIndex, forceReplay)
    animationIndex = tonumber(animationIndex)
    if not animationIndex then return end
    animationIndex = math.floor(animationIndex)
    if animationIndex < 1 or not animationList[animationIndex] then
        Config.Notify(locale('admin_tool_anim_invalid'), 'error')
        return
    end

    if not forceReplay and placementTool.animationIndex == animationIndex and placementTool.ped and DoesEntityExist(placementTool.ped) then
        showPlacementUi()
        return
    end

    placementTool.animationIndex = animationIndex
    playPlacementAnimation()
    showPlacementUi()
end

local function openPlacementAnimationMenu()
    if not placementTool.active then return end
    if not lib or not lib.registerContext or not lib.showContext then
        Config.Notify(locale('placement_tool_context_missing'), 'error')
        return
    end

    local options = {}
    for index, animation in ipairs(animationList) do
        options[#options + 1] = {
            title = getAnimationDisplayLabel(index, animation),
            icon = animation.icon or 'fas fa-person-running',
            onSelect = function()
                setPlacementAnimation(index)
            end
        }
    end

    lib.registerContext({
        id = placementTool.contextId,
        title = locale('placement_tool_menu_title'),
        options = options
    })
    lib.showContext(placementTool.contextId)
end

local function savePlacementToolCoords()
    local ped = placementTool.ped
    if not ped or not DoesEntityExist(ped) then return end

    local coords = GetEntityCoords(ped)
    local output = ('coords = %s,\nanimation = %s'):format(
        formatVector4(coords, placementTool.heading),
        placementTool.animationIndex
    )

    if lib and lib.setClipboard then
        lib.setClipboard(output)
        Config.Notify(locale('admin_tool_saved', output), 'success')
    else
        print(('[%s] %s'):format(resourceName, output))
        Config.Notify(locale('admin_tool_saved_fallback', output), 'success')
    end

    stopPlacementTool()
end

local function startPlacementTool(animationIndex)
    if placementTool.active then
        stopPlacementTool()
    end

    animationIndex = tonumber(animationIndex) or 1
    animationIndex = math.floor(animationIndex)
    if animationIndex < 1 or not animationList[animationIndex] then
        Config.Notify(locale('admin_tool_anim_invalid'), 'error')
        return
    end

    local model = DEBUG_TOOL_PED_MODEL
    local modelHash = type(model) == 'string' and joaat(model) or model
    if not modelHash then return end

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(10)
    end

    local playerPed = PlayerPedId()
    local spawnCoords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 1.0, 0.0)
    placementTool.heading = GetEntityHeading(playerPed)
    placementTool.animationIndex = animationIndex
    placementTool.ped = CreatePed(4, modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z - 1.0, placementTool.heading, false, false)
    placementTool.active = placementTool.ped and DoesEntityExist(placementTool.ped) or false

    SetModelAsNoLongerNeeded(modelHash)

    if not placementTool.active then
        placementTool.ped = nil
        return
    end

    SetEntityInvincible(placementTool.ped, true)
    SetBlockingOfNonTemporaryEvents(placementTool.ped, true)
    FreezeEntityPosition(placementTool.ped, true)
    SetPedCanRagdoll(placementTool.ped, false)
    SetEntityProofs(placementTool.ped, true, true, true, true, true, true, true, true, true)

    setPlacementAnimation(animationIndex, true)
    showPlacementUi()
    Config.Notify(locale('admin_tool_started'), 'inform')

    CreateThread(function()
        local moveStep = DEBUG_TOOL_MOVE_STEP
        local fastMultiplier = DEBUG_TOOL_FAST_MULTIPLIER
        local verticalStep = DEBUG_TOOL_VERTICAL_STEP
        local headingStep = DEBUG_TOOL_HEADING_STEP

        while placementTool.active do
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 36, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 47, true)
            DisableControlAction(0, 177, true)
            DisableControlAction(0, 191, true)
            DisablePlayerFiring(PlayerId(), true)

            local speed = IsDisabledControlPressed(0, 21) and fastMultiplier or 1.0
            local deltaX = 0.0
            local deltaY = 0.0
            local deltaZ = 0.0
            local deltaHeading = 0.0

            if IsDisabledControlPressed(0, 32) then deltaY = deltaY + (moveStep * speed) end
            if IsDisabledControlPressed(0, 33) then deltaY = deltaY - (moveStep * speed) end
            if IsDisabledControlPressed(0, 34) then deltaX = deltaX - (moveStep * speed) end
            if IsDisabledControlPressed(0, 35) then deltaX = deltaX + (moveStep * speed) end
            if IsDisabledControlPressed(0, 22) then deltaZ = deltaZ + (verticalStep * speed) end
            if IsDisabledControlPressed(0, 36) then deltaZ = deltaZ - (verticalStep * speed) end
            if IsDisabledControlPressed(0, 44) then deltaHeading = deltaHeading - (headingStep * speed) end
            if IsDisabledControlPressed(0, 38) then deltaHeading = deltaHeading + (headingStep * speed) end

            if deltaX ~= 0.0 or deltaY ~= 0.0 or deltaZ ~= 0.0 or deltaHeading ~= 0.0 then
                updatePlacementTransform(deltaX, deltaY, deltaZ, deltaHeading)
            end

            if IsDisabledControlJustPressed(0, 47) then
                openPlacementAnimationMenu()
            end

            if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201) then
                savePlacementToolCoords()
                break
            end

            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 202) then
                Config.Notify(locale('admin_tool_cancelled'), 'inform')
                stopPlacementTool()
                break
            end

            Wait(0)
        end
    end)
end

local function buildPoleMap()
    for index, pole in ipairs(poles) do
        if type(pole.id) ~= 'string' or pole.id == '' then
            pole.id = ('pole_%d'):format(index)
        end
        if type(pole.coords) == 'vector4' then
            pole.heading = pole.heading or pole.coords.w
            pole.coords = vector3(pole.coords.x, pole.coords.y, pole.coords.z)
        end
        if type(pole.ped) == 'table' and pole.ped.heading == nil and pole.heading ~= nil then
            pole.ped.heading = pole.heading
        end
        poleMap[pole.id] = pole
    end
end

local function buildDanceZoneMap()
    for index, zone in ipairs(danceZones) do
        if type(zone.id) ~= 'string' or zone.id == '' then
            zone.id = ('dance_zone_%d'):format(index)
        end
        if type(zone.coords) == 'vector4' then
            zone.heading = zone.heading or zone.coords.w
            zone.coords = vector3(zone.coords.x, zone.coords.y, zone.coords.z)
        end
        danceZoneMap[zone.id] = zone
    end
end

local function findClosestPole(coords)
    if not coords then return nil end
    local closestId
    local closestDistance = math.huge
    for _, pole in ipairs(poles) do
        if pole.coords then
            local distance = #(coords - pole.coords)
            if distance < closestDistance then
                closestDistance = distance
                closestId = pole.id
            end
        end
    end
    if closestDistance > 6.0 then return nil end
    return closestId
end

stopUi = function()
    if lib and lib.hideTextUI then
        lib.hideTextUI()
    end
end

local function canDanceOnPole(poleId)
    if not poleId then
        return true
    end

    if not lib or not lib.callback or not lib.callback.await then
        return true
    end

    local result = lib.callback.await(resourceName .. ':canDanceOnPole', false, poleId)
    if type(result) ~= 'table' then
        return true
    end

    if result.allowed == false then
        if result.occupiedBy then
            Config.Notify(locale('zone_occupied'), 'error')
        else
            Config.Notify(locale('dance_job_required', result.requiredJob or 'unknown'), 'error')
        end
        return false
    end

    return true
end

local function canDanceInZone(zoneId)
    if not zoneId then
        return true
    end

    if not lib or not lib.callback or not lib.callback.await then
        return true
    end

    local result = lib.callback.await(resourceName .. ':canDanceInZone', false, zoneId)
    if type(result) ~= 'table' then
        return true
    end

    if result.allowed == false then
        if result.occupiedBy then
            Config.Notify(locale('zone_occupied'), 'error')
        else
            Config.Notify(locale('dance_job_required', result.requiredJob or 'unknown'), 'error')
        end
        return false
    end

    return true
end

local getPoleZoneIdLocal
local hasStaticDancerForZone
local zoneHasPedTipTarget
local zoneHasPlayerTipTarget

local function hasTipTargetForPole(poleId)
    if not poleId then
        return false
    end

    local pole = poleMap[poleId]
    if not pole then
        return false
    end

    local zoneId = getPoleZoneIdLocal and getPoleZoneIdLocal(poleId) or nil
    if hasStaticDancerForZone(zoneId) then
        return true
    end

    if (tonumber(activeZoneStates[zoneId]) or 0) > 0 then
        return true
    end

    return (tonumber(activePoleStates[poleId]) or 0) > 0
end

local function hasTipTargetForZone(zoneId)
    if not zoneId then
        return false
    end

    if hasStaticDancerForZone(zoneId) then
        return true
    end

    return (tonumber(activeZoneStates[zoneId]) or 0) > 0
end

zoneHasPlayerTipTarget = function(zoneId)
    if not zoneId then
        return false
    end

    return (tonumber(activeZoneStates[zoneId]) or 0) > 0
end

getPoleZoneIdLocal = function(poleId)
    if not poleId then return nil end
    local pole = poleMap[poleId]
    if not pole then return nil end
    return pole.zoneId or pole.id
end

hasStaticDancerForZone = function(zoneId)
    if not zoneId then return false end

    for _, pole in pairs(poleMap) do
        if (pole.zoneId or pole.id) == zoneId then
            local pedCfg = pole.ped
            if pedCfg and pedCfg.enabled and pedCfg.wash and pedCfg.wash.enabled then
                return true
            end
        end
    end

    return false
end

local function canDanceTargetPole(poleId)
    if not poleId then
        return true
    end

    local pole = poleMap[poleId]
    if not pole then
        return true
    end

    local zoneId = getPoleZoneIdLocal(poleId)
    if currentShiftZoneId ~= zoneId then
        return false
    end

    if hasStaticDancerForZone(zoneId) then
        return false
    end

    return (tonumber(activeZoneStates[zoneId]) or 0) <= 0
end

local function canDanceTargetZone(zoneId)
    if not zoneId then
        return false
    end

    if hasStaticDancerForZone(zoneId) then
        return false
    end

    return (tonumber(activeZoneStates[zoneId]) or 0) <= 0
end

local function canStartShiftTarget(zoneId)
    if not zoneId then
        return false
    end

    if isDancing or currentShiftZoneId or not canDanceTargetZone(zoneId) then
        return false
    end

    local requiredJob = getZoneRequiredJobLocal(zoneId)
    if not requiredJob then
        return true
    end

    local currentJob = getCurrentPlayerJobName()
    if not currentJob then
        return true
    end

    return currentJob == requiredJob
end

local function resolvePoleIdFromTargetData(data)
    if data and data.poleId then
        return data.poleId
    end

    local coords
    if data and data.coords then
        coords = data.coords
    elseif data and data.entity and DoesEntityExist(data.entity) then
        coords = GetEntityCoords(data.entity)
    end

    if not coords then
        return nil
    end

    return findClosestPole(coords)
end

local function cleanupPoleDance()
    isDancing = false
    TriggerServerEvent(resourceName .. ':server:UpdatePoleDancers', false)
end

local function startShift(zoneId)
    if not zoneId then return end
    if isDancing then return end
    if currentShiftZoneId and currentShiftZoneId ~= zoneId then
        return
    end

    if not canDanceInZone(zoneId) then
        return
    end

    currentShiftZoneId = zoneId
    Config.Notify(locale('shift_start'), 'success')
end

local function endShift(zoneId)
    if isDancing then
        return
    end

    if zoneId and currentShiftZoneId ~= zoneId then
        return
    end

    currentShiftZoneId = nil
    Config.Notify(locale('shift_end'), 'inform')
end

local function resolveDanceHeading(pole, data, ped)
    if pole and pole.heading ~= nil then
        local heading = tonumber(pole.heading)
        if heading then
            return heading
        end
    end

    if data and data.heading ~= nil then
        local heading = tonumber(data.heading)
        if heading then
            return heading
        end
    end

    if data and data.entity and DoesEntityExist(data.entity) then
        return GetEntityHeading(data.entity)
    end

    return GetEntityHeading(ped)
end

local function startPoleDance(animationIndex, data)
    if isDancing then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    local coords
    if data and data.coords then
        coords = data.coords
    elseif data and data.entity and DoesEntityExist(data.entity) then
        coords = GetEntityCoords(data.entity)
    end

    if not coords then
        coords = GetEntityCoords(ped)
    end

    local poleId = data and data.poleId or nil
    if not poleId then
        poleId = findClosestPole(coords)
    end
    local pole = poleId and poleMap[poleId] or nil
    if pole and pole.coords then
        coords = pole.coords
    end
    local zoneId = pole and (pole.zoneId or pole.id) or nil
    if zoneId and currentShiftZoneId ~= zoneId then
        Config.Notify(locale('shift_required'), 'error')
        return
    end
    local heading = resolveDanceHeading(pole, data, ped)

    if not canDanceOnPole(poleId) then
        return
    end

    local animation, resolvedIndex = resolveAnimation(pole, animationIndex)
    if not animation then return end

    local dict = animation.dict
    local anim = animation.anim
    local scenario = animation.scenario
    local sceneHandle

    if animation.scene and dict and anim then
        loadAnimDict(dict)
        SetEntityHeading(ped, heading)
        sceneHandle = NetworkCreateSynchronisedScene(coords.x, coords.y, coords.z, 0.0, 0.0, heading, 2, false, Config.LoopDances, 1065353216, 0, 1.3)
        NetworkAddPedToSynchronisedScene(ped, sceneHandle, dict, anim, animation.speed or 1.5, animation.blendOut or -4.0, 1, 1, 1148846080, 0)
        NetworkStartSynchronisedScene(sceneHandle)
    elseif scenario then
        SetEntityHeading(ped, heading)
        TaskStartScenarioInPlace(ped, scenario, 0, true)
    elseif dict and anim then
        loadAnimDict(dict)
        SetEntityHeading(ped, heading)
        TaskPlayAnim(ped, dict, anim, animation.blendIn or 8.0, animation.blendOut or -8.0, animation.duration or -1, animation.flag or 1, animation.speed or 0.0, false, false, false)
    else
        return
    end

    isDancing = true
    TriggerServerEvent(resourceName .. ':server:UpdatePoleDancers', true, {
        coords = coords,
        poleId = poleId,
        animation = resolvedIndex
    })

    lib.showTextUI(locale('stop_text'), { position = promptPosition })

    CreateThread(function()
        local loops = 0
        while isDancing do
            loops = loops + 1
            if loops > 1000 then
                local stillPlaying = false
                if scenario then
                    stillPlaying = IsPedUsingScenario(ped, scenario)
                elseif dict and anim then
                    stillPlaying = IsEntityPlayingAnim(ped, dict, anim, 3)
                end

                if not stillPlaying then
                    break
                end
                loops = 0
            end

            if IsControlJustPressed(0, 73) then
                break
            end

            Wait(0)
        end

        ClearPedTasks(ped)
        stopUi()
        cleanupPoleDance()
    end)
end

local function startZoneDance(animationIndex, zone)
    if isDancing then return end
    if not zone or not zone.id then return end
    if currentShiftZoneId ~= zone.id then
        Config.Notify(locale('shift_required'), 'error')
        return
    end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    if not canDanceInZone(zone.id) then return end

    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local animation, resolvedIndex = resolveAnimation(zone, animationIndex)
    if not animation then return end

    local dict = animation.dict
    local anim = animation.anim
    local scenario = animation.scenario
    local sceneHandle

    if animation.scene and dict and anim then
        loadAnimDict(dict)
        SetEntityHeading(ped, heading)
        sceneHandle = NetworkCreateSynchronisedScene(coords.x, coords.y, coords.z, 0.0, 0.0, heading, 2, false, Config.LoopDances, 1065353216, 0, 1.3)
        NetworkAddPedToSynchronisedScene(ped, sceneHandle, dict, anim, animation.speed or 1.5, animation.blendOut or -4.0, 1, 1, 1148846080, 0)
        NetworkStartSynchronisedScene(sceneHandle)
    elseif scenario then
        SetEntityHeading(ped, heading)
        TaskStartScenarioInPlace(ped, scenario, 0, true)
    elseif dict and anim then
        loadAnimDict(dict)
        SetEntityHeading(ped, heading)
        TaskPlayAnim(ped, dict, anim, animation.blendIn or 8.0, animation.blendOut or -8.0, animation.duration or -1, animation.flag or 1, animation.speed or 0.0, false, false, false)
    else
        return
    end

    isDancing = true
    TriggerServerEvent(resourceName .. ':server:UpdatePoleDancers', true, {
        coords = coords,
        zoneId = zone.id,
        animation = resolvedIndex
    })

    lib.showTextUI(locale('stop_text'), { position = promptPosition })

    CreateThread(function()
        local loops = 0
        while isDancing do
            loops = loops + 1
            if loops > 1000 then
                local stillPlaying = false
                if scenario then
                    stillPlaying = IsPedUsingScenario(ped, scenario)
                elseif dict and anim then
                    stillPlaying = IsEntityPlayingAnim(ped, dict, anim, 3)
                end

                if not stillPlaying then
                    break
                end
                loops = 0
            end

            if IsControlJustPressed(0, 73) then
                break
            end

            Wait(0)
        end

        ClearPedTasks(ped)
        stopUi()
        cleanupPoleDance()
    end)
end

local function startMobileTip(targetData)
    if isSelectingTip then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    isSelectingTip = true

    local tipSettings = getTipSettings()
    local selectedAmount = tipSettings.default
    if lib and lib.inputDialog then
        local chosenAmount = promptTipAmount(selectedAmount, tipSettings)
        if chosenAmount == false then
            Config.Notify(locale('not_enough_money'), 'error')
            isSelectingTip = false
            return
        end
        if not chosenAmount then
            isSelectingTip = false
            return
        end
        selectedAmount = chosenAmount
    end

    local poleId = targetData and targetData.poleId or nil
    if not poleId then
        local coords
        if targetData and targetData.coords then
            coords = targetData.coords
        elseif targetData and targetData.entity and DoesEntityExist(targetData.entity) then
            coords = GetEntityCoords(targetData.entity)
        else
            coords = GetEntityCoords(ped)
        end
        poleId = findClosestPole(coords)
    end

    TriggerServerEvent(resourceName .. ':server:ThrowMoney', {
        targetType = targetData and targetData.targetType or 'pole',
        poleId = poleId,
        zoneId = targetData and targetData.zoneId or nil,
        amount = selectedAmount
    })

    isSelectingTip = false
end

local function registerDanceZoneTargets()
    for _, zone in ipairs(danceZones) do
        if zone.coords then
            local zoneOptions = {
                {
                    icon = 'fas fa-user-check',
                    label = locale('shift_start'),
                    distance = 2.5,
                    canInteract = function()
                        return canStartShiftTarget(zone.id)
                    end,
                    onSelect = function()
                        startShift(zone.id)
                    end
                }
            }

            local animationIndices = getAnimationIndicesForZone(zone)
            for _, animationIndex in ipairs(animationIndices) do
                local animation = animationList[animationIndex]
                if animation then
                    zoneOptions[#zoneOptions + 1] = {
                        icon = animation.icon or 'fas fa-person-running',
                        label = getAnimationDisplayLabel(animationIndex, animation),
                        distance = animation.distance or 2.5,
                        canInteract = function()
                            return not isDancing and currentShiftZoneId == zone.id and canDanceTargetZone(zone.id)
                        end,
                        onSelect = function()
                            startZoneDance(animationIndex, zone)
                        end
                    }
                end
            end

            zoneOptions[#zoneOptions + 1] = {
                icon = 'fas fa-user-slash',
                label = locale('shift_end'),
                distance = 2.5,
                canInteract = function()
                    return not isDancing and currentShiftZoneId == zone.id
                end,
                onSelect = function()
                    endShift(zone.id)
                end
            }

            zoneOptions[#zoneOptions + 1] = {
                icon = Config.LeanIcon,
                label = locale('tip_text'),
                distance = 2.5,
                canInteract = function()
                    return hasTipTargetForZone(zone.id)
                        and (zoneHasPlayerTipTarget(zone.id) or not zoneHasPedTipTarget(zone.id))
                end,
                onSelect = function()
                    startMobileTip({
                        targetType = 'zone',
                        zoneId = zone.id,
                        coords = zone.coords
                    })
                end
            }

            danceZoneTargets[zone.id] = oxTarget:addSphereZone({
                coords = zone.coords,
                radius = zone.radius or 4.0,
                debug = debugEnabled,
                drawSprite = Config.TargetSprites,
                options = zoneOptions
            })
        end
    end
end

local function poleHasPedTipTarget(poleId)
    for _, pole in ipairs(poles) do
        if pole.id == poleId then
            local pedCfg = pole.ped
            return pedCfg and pedCfg.enabled and pedCfg.wash and pedCfg.wash.enabled or false
        end
    end

    return false
end

zoneHasPedTipTarget = function(zoneId)
    if not zoneId then
        return false
    end

    for _, pole in ipairs(poles) do
        if (pole.zoneId or pole.id) == zoneId then
            local pedCfg = pole.ped
            if pedCfg and pedCfg.enabled and pedCfg.wash and pedCfg.wash.enabled then
                return true
            end
        end
    end

    return false
end

local function buildPoleTargetOptions(targetFactory)
    local options = {}
    for index, animation in ipairs(animationList) do
        options[#options + 1] = {
            icon = animation.icon or 'fas fa-person-running',
            label = getAnimationDisplayLabel(index, animation),
            distance = animation.distance or 2.0,
            canInteract = function(entity, distance, coords, name, bone)
                return canDanceTargetPole(resolvePoleIdFromTargetData({
                    entity = entity,
                    coords = coords
                }))
            end,
            onSelect = targetFactory(index, false)
        }
    end

    if #options == 0 then
        options[1] = {
            icon = 'fas fa-person-running',
            label = getAnimationDisplayLabel(1),
            distance = 2.0,
            canInteract = function(entity, distance, coords, name, bone)
                return canDanceTargetPole(resolvePoleIdFromTargetData({
                    entity = entity,
                    coords = coords
                }))
            end,
            onSelect = targetFactory(nil, false)
        }
    end

    options[#options + 1] = {
        icon = Config.LeanIcon,
        label = locale('tip_text'),
        distance = 2.0,
        canInteract = function(entity, distance, coords, name, bone)
            local poleId = resolvePoleIdFromTargetData({
                entity = entity,
                coords = coords
            })
            if poleHasPedTipTarget(poleId) then
                return false
            end
            if poleHasZoneTarget(poleId) then
                return false
            end

            return hasTipTargetForPole(poleId)
        end,
        onSelect = targetFactory(nil, true)
    }

    return options
end

local function registerPoleTargets()
    local models = {}
    for model in pairs(Config.PoleProps or {}) do
        models[#models + 1] = model
    end

    if #models > 0 then
        local modelOptions = buildPoleTargetOptions(function(index, isTip)
            return function(data)
                if isTip then
                    startMobileTip({
                        targetType = 'pole',
                        coords = data and data.coords or nil,
                        entity = data and data.entity or nil
                    })
                    return
                end

                startPoleDance(index, data)
            end
        end)

        oxTarget:addModel(models, modelOptions)
        poleModels = models
        poleOptions = modelOptions
    end

    for _, pole in ipairs(poles) do
        if pole.coords then
            local zoneOptions = {}
            local animationIndices = getAnimationIndicesForPole(pole)
            for _, animationIndex in ipairs(animationIndices) do
                local animation = animationList[animationIndex]
                if animation then
                    zoneOptions[#zoneOptions + 1] = {
                        icon = animation.icon or 'fas fa-person-running',
                        label = getAnimationDisplayLabel(animationIndex, animation),
                        distance = animation.distance or 2.0,
                        canInteract = function()
                            return canDanceTargetPole(pole.id)
                        end,
                        onSelect = function()
                            startPoleDance(animationIndex, {
                                poleId = pole.id,
                                coords = pole.coords,
                                heading = pole.heading
                            })
                        end
                    }
                end
            end

            poleZones[pole.id] = oxTarget:addSphereZone({
                coords = pole.coords,
                radius = pole.radius or 1.1,
                debug = debugEnabled,
                drawSprite = Config.TargetSprites,
                options = zoneOptions
            })
        end
    end
end

local function getPedAnimationIndices(pole, pedCfg)
    if pedCfg and type(pedCfg.animations) == 'table' and #pedCfg.animations > 0 then
        return pedCfg.animations
    end
    return getAnimationIndicesForPole(pole)
end

local function applyPedAppearance(ped, pedCfg)
    if not ped or not DoesEntityExist(ped) then return end

    -- Force deterministic baseline so all clients see the same model variation.
    SetPedDefaultComponentVariation(ped)
    ClearAllPedProps(ped)

    if not pedCfg or type(pedCfg) ~= 'table' then return end

    if type(pedCfg.components) == 'table' then
        for _, component in ipairs(pedCfg.components) do
            if type(component) == 'table' then
                local compId = tonumber(component.id or component.componentId)
                local drawable = tonumber(component.drawable or component.drawableId) or 0
                local texture = tonumber(component.texture or component.textureId) or 0
                local palette = tonumber(component.palette or component.paletteId) or 0

                if compId then
                    SetPedComponentVariation(ped, compId, drawable, texture, palette)
                end
            end
        end
    end

    if type(pedCfg.props) == 'table' then
        for _, prop in ipairs(pedCfg.props) do
            if type(prop) == 'table' then
                local propId = tonumber(prop.id or prop.propId)
                if propId then
                    local drawable = tonumber(prop.drawable or prop.drawableId)
                    local texture = tonumber(prop.texture or prop.textureId) or 0
                    if drawable and drawable >= 0 then
                        SetPedPropIndex(ped, propId, drawable, texture, true)
                    else
                        ClearPedProp(ped, propId)
                    end
                end
            end
        end
    end
end

local function spawnPolePed(pole)
    local pedCfg = pole.ped
    if not pedCfg or not pedCfg.enabled then return end
    local coords = pole.coords
    if not coords then return end

    if pedHandles[pole.id] then
        if DoesEntityExist(pedHandles[pole.id]) then
            DeleteEntity(pedHandles[pole.id])
        end
        pedHandles[pole.id] = nil
    end

    if pedCycles[pole.id] then
        pedCycles[pole.id].active = false
        pedCycles[pole.id] = nil
    end

    local model = pedCfg.model or 's_f_y_stripper_01'
    local modelHash = type(model) == 'string' and joaat(model) or model
    if not modelHash then return end

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(10)
    end

    local pedHeading = pedCfg.heading
    if pedHeading == nil then
        pedHeading = pole.heading
    end
    if pedHeading == nil then
        pedHeading = 0.0
    end

    local ped = CreatePed(4, modelHash, coords.x, coords.y, coords.z - 1.0, pedHeading, false, false)
    if not DoesEntityExist(ped) then return end

    SetEntityHeading(ped, pedHeading)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, pedCfg.freeze ~= false)
    SetPedCanRagdoll(ped, false)
    SetEntityProofs(ped, true, true, true, true, true, true, true, true, true)
    SetPedHearingRange(ped, 0.0)
    SetPedSeeingRange(ped, 0.0)
    SetPedAlertness(ped, 0)
    applyPedAppearance(ped, pedCfg)

    local animationIndices = getPedAnimationIndices(pole, pedCfg)
    local firstAnimation = animationList[animationIndices[1] or 0]
    if firstAnimation then
        playPedAnimation(ped, firstAnimation)
    end

    pedHandles[pole.id] = ped
    SetModelAsNoLongerNeeded(modelHash)

    if pedCfg.wash and pedCfg.wash.enabled then
        local zoneId = pole.zoneId or pole.id
        pedTargets[pole.id] = oxTarget:addLocalEntity(ped, {
            {
                icon = pedCfg.wash.icon or Config.LeanIcon,
                label = pedCfg.wash.label or locale('tip_text'),
                distance = pedCfg.wash.distance or 2.0,
                canInteract = function()
                    return not zoneHasPlayerTipTarget(zoneId)
                end,
                onSelect = function()
                    if DoesEntityExist(ped) then
                        startMobileTip({
                            targetType = 'ped',
                            poleId = pole.id,
                            entity = ped
                        })
                    end
                end
            }
        })
    end

    local cycleCfg = pedCfg.cycle or {}
    if cycleCfg.enabled and #animationIndices > 1 then
        local interval = math.max(1, tonumber(cycleCfg.interval) or 30)
        pedCycles[pole.id] = { active = true }
        local cycleData = pedCycles[pole.id]
        CreateThread(function()
            local current = 1
            while cycleData.active do
                Wait(interval * 1000)
                if not cycleData.active then break end
                if not DoesEntityExist(ped) then break end
                current = current % #animationIndices + 1
                local anim = animationList[animationIndices[current]]
                if anim then
                    playPedAnimation(ped, anim)
                end
            end
            cycleData.active = false
        end)
    end
end

local function resolveGroundZ(x, y, z)
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 3.0, false)
    if found then
        return groundZ
    end

    return z
end

local function storeAttachedTipProp(ped, prop)
    if not ped or not prop then return end
    activeTipProps.attached[ped] = activeTipProps.attached[ped] or {}
    activeTipProps.attached[ped][#activeTipProps.attached[ped] + 1] = prop
end

local function removeDroppedTipPropEntry(ped, cashProp)
    local props = activeTipProps.dropped[ped]
    if not props then return end

    for i = #props, 1, -1 do
        if props[i] == cashProp then
            table.remove(props, i)
        end
    end

    if #props == 0 then
        activeTipProps.dropped[ped] = nil
    end
end

local function storeDroppedTipProp(ped, prop)
    if not ped or not prop then return end

    local tipConfig = Config.Tip or {}
    local maxDropped = math.max(1, math.floor(tonumber(tipConfig.maxDroppedProps) or 8))

    activeTipProps.dropped[ped] = activeTipProps.dropped[ped] or {}
    local dropped = activeTipProps.dropped[ped]

    while #dropped >= maxDropped do
        local oldest = table.remove(dropped, 1)
        if oldest and DoesEntityExist(oldest) then
            DeleteObject(oldest)
        end
    end

    dropped[#dropped + 1] = prop
end

local function releaseTipPropToFloor(ped, cashProp, landingCoords)
    if not cashProp or not DoesEntityExist(cashProp) then return end

    DetachEntity(cashProp, true, true)
    SetEntityCollision(cashProp, true, true)
    SetEntityDynamic(cashProp, true)
    ActivatePhysics(cashProp)
    FreezeEntityPosition(cashProp, false)

    local tipConfig = Config.Tip or {}
    local dropCfg = tipConfig.drop or {}
    local coords = landingCoords or GetEntityCoords(cashProp)
    local groundZ = resolveGroundZ(coords.x, coords.y, coords.z)
    local startHeight = tonumber(dropCfg.height) or 0.85
    local speed = tonumber(dropCfg.speed) or 3.0
    local upward = tonumber(dropCfg.upward) or 0.55
    local velocity = dropCfg.velocity or {}
    local startCoords = GetEntityCoords(cashProp)
    local dx = coords.x - startCoords.x
    local dy = coords.y - startCoords.y
    local distance = math.sqrt((dx * dx) + (dy * dy))
    if distance < 0.001 then
        distance = 1.0
    end

    SetEntityCoords(cashProp, startCoords.x, startCoords.y, math.max(startCoords.z, groundZ + startHeight), false, false, false, false)
    SetEntityVelocity(
        cashProp,
        (dx / distance) * speed + (tonumber(velocity.x) or 0.0),
        (dy / distance) * speed + (tonumber(velocity.y) or 0.0),
        upward + (tonumber(velocity.z) or -0.15)
    )

    storeDroppedTipProp(ped, cashProp)
end

local function cleanupAttachedTipPropsFromPed(ped, deleteDetached)
    local props = activeTipProps.attached[ped]
    if not props then return end

    for i = #props, 1, -1 do
        local obj = props[i]
        if DoesEntityExist(obj) then
            local attached = IsEntityAttachedToEntity(obj, ped)
            if attached or deleteDetached then
                DetachEntity(obj, true, true)
                DeleteObject(obj)
            end
        end
        props[i] = nil
    end

    activeTipProps.attached[ped] = nil
end

local function cleanupDroppedTipPropsFromPed(ped)
    local props = activeTipProps.dropped[ped]
    if not props then return end

    for i = #props, 1, -1 do
        local obj = props[i]
        if DoesEntityExist(obj) then
            DeleteObject(obj)
        end
        props[i] = nil
    end

    activeTipProps.dropped[ped] = nil
end

local function cleanupAllTipProps()
    for ped, _ in pairs(activeTipProps.attached) do
        cleanupAttachedTipPropsFromPed(ped, true)
    end

    for ped, _ in pairs(activeTipProps.dropped) do
        cleanupDroppedTipPropsFromPed(ped)
    end
end

local function resolveTipAnimationConfig(tipConfig)
    local animation = tipConfig.anim
    if type(animation) == 'table' then
        return animation.dict, animation.clip or animation.anim
    end

    return tipConfig.dict, animation
end

local function resolveTipPropConfig(tipConfig)
    local prop = tipConfig.prop
    if type(prop) == 'table' then
        local pos = prop.pos or vec3(0.12, 0.028, 0.001)
        local rot = prop.rot or vec3(300.0, 180.0, 20.0)
        return prop.model, prop.bone or 18905, {
            x = pos.x or 0.12,
            y = pos.y or 0.028,
            z = pos.z or 0.001,
            rx = rot.x or 300.0,
            ry = rot.y or 180.0,
            rz = rot.z or 20.0
        }
    end

    return prop, tipConfig.bone or 18905, tipConfig.attach or {}
end

local function resolveTipParticleConfig(tipConfig)
    if type(tipConfig.ptfx) == 'table' then
        local placement = tipConfig.ptfx.placement or {}
        local offset = placement[1] or vec3(0.0, 0.0, 0.0)
        local rotation = placement[2] or vec3(0.0, 0.0, 0.0)
        local releaseDelay = math.max(0, tonumber(tipConfig.releaseDelay) or 0)
        local sequenceEndDelay = math.max(releaseDelay, tonumber(tipConfig.sequenceEndDelay) or releaseDelay)
        local particleDelay = 150

        return {
            hand = {
                asset = tipConfig.ptfx.asset or 'core',
                effect = tipConfig.ptfx.name or 'ent_brk_banknotes',
                bone = tipConfig.ptfx.bone,
                delay = particleDelay,
                duration = math.max(900, sequenceEndDelay - particleDelay),
                looped = true,
                offset = { x = offset.x or 0.0, y = offset.y or 0.0, z = offset.z or 0.0 },
                rotation = { x = rotation.x or 0.0, y = rotation.y or 180.0, z = rotation.z or 0.0 },
                scale = tipConfig.ptfx.scale or 1.0,
                attachToProp = true
            }
        }
    end

    return tipConfig.particle or {}
end

local function stopTipPtfxLoop()
    if tipPtfxTool.handle then
        StopParticleFxLooped(tipPtfxTool.handle, false)
        RemoveParticleFx(tipPtfxTool.handle, false)
        tipPtfxTool.handle = nil
    end

    if tipPtfxTool.asset then
        RemoveNamedPtfxAsset(tipPtfxTool.asset)
        tipPtfxTool.asset = nil
    end
end

local function stopTipPtfxTool()
    stopTipPtfxLoop()

    local ped = PlayerPedId()
    if ped and DoesEntityExist(ped) then
        ClearPedSecondaryTask(ped)
        ClearPedTasks(ped)
    end

    if tipPtfxTool.prop and DoesEntityExist(tipPtfxTool.prop) then
        DetachEntity(tipPtfxTool.prop, true, true)
        DeleteObject(tipPtfxTool.prop)
    end

    tipPtfxTool.active = false
    tipPtfxTool.prop = nil
    stopUi()
end

local function refreshTipPtfxToolFx()
    stopTipPtfxLoop()

    if not tipPtfxTool.active or not tipPtfxTool.prop or not DoesEntityExist(tipPtfxTool.prop) then
        return
    end

    local tipConfig = Config.Tip or {}
    local ptfx = tipConfig.ptfx or {}
    local asset = ptfx.asset or 'core'
    local effect = ptfx.name or 'ent_brk_banknotes'

    RequestNamedPtfxAsset(asset)
    while not HasNamedPtfxAssetLoaded(asset) do
        Wait(10)
    end

    UseParticleFxAssetNextCall(asset)
    tipPtfxTool.handle = StartParticleFxLoopedOnEntity(
        effect,
        tipPtfxTool.prop,
        tipPtfxTool.offset.x,
        tipPtfxTool.offset.y,
        tipPtfxTool.offset.z,
        tipPtfxTool.rotation.x,
        tipPtfxTool.rotation.y,
        tipPtfxTool.rotation.z,
        ptfx.scale or 1.0,
        false,
        false,
        false
    )
    tipPtfxTool.asset = asset
end

local function formatTipPtfxPlacement()
    return ("placement = {\n    vec3(%.3f, %.3f, %.3f),\n    vec3(%.3f, %.3f, %.3f)\n}"):format(
        tipPtfxTool.offset.x,
        tipPtfxTool.offset.y,
        tipPtfxTool.offset.z,
        tipPtfxTool.rotation.x,
        tipPtfxTool.rotation.y,
        tipPtfxTool.rotation.z
    )
end

local function showTipPtfxToolUi()
    if not tipPtfxTool.active then return end

    local text = ("%s\n%s\n%s\n%s"):format(
        locale('tip_ptfx_tool_started'),
        ('Offset xyz: %.3f %.3f %.3f'):format(tipPtfxTool.offset.x, tipPtfxTool.offset.y, tipPtfxTool.offset.z),
        ('Rot xyz: %.1f %.1f %.1f'):format(tipPtfxTool.rotation.x, tipPtfxTool.rotation.y, tipPtfxTool.rotation.z),
        locale('tip_ptfx_tool_controls')
    )

    lib.showTextUI(text, { position = promptPosition })
end

local function saveTipPtfxToolPlacement()
    local output = formatTipPtfxPlacement()

    if lib and lib.setClipboard then
        lib.setClipboard(output)
        Config.Notify(locale('tip_ptfx_tool_saved', output), 'success')
    else
        print(('[%s] %s'):format(resourceName, output))
        Config.Notify(locale('tip_ptfx_tool_saved_fallback', output), 'success')
    end

    stopTipPtfxTool()
end

local function startTipPtfxTool()
    if tipPtfxTool.active then
        stopTipPtfxTool()
        return
    end

    if placementTool and placementTool.active then
        stopPlacementTool()
    end

    local tipConfig = Config.Tip or {}
    local dict, anim = resolveTipAnimationConfig(tipConfig)
    local propName, propBone, attach = resolveTipPropConfig(tipConfig)
    local ptfxPlacement = ((tipConfig.ptfx or {}).placement) or {}
    local offset = ptfxPlacement[1] or vec3(0.0, 0.0, 0.0)
    local rotation = ptfxPlacement[2] or vec3(0.0, 180.0, 0.0)
    local ped = PlayerPedId()

    if not ped or not DoesEntityExist(ped) then return end
    if not propName then
        Config.Notify(locale('tip_ptfx_tool_missing_prop'), 'error')
        return
    end

    local model = GetHashKey(propName)
    if not model or model == 0 then
        Config.Notify(locale('tip_ptfx_tool_missing_prop'), 'error')
        return
    end

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(10)
    end

    if dict and anim then
        loadAnimDict(dict)
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
    end

    local prop = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
    SetModelAsNoLongerNeeded(model)
    if not prop or not DoesEntityExist(prop) then
        Config.Notify(locale('tip_ptfx_tool_missing_prop'), 'error')
        return
    end

    AttachEntityToEntity(
        prop,
        ped,
        GetPedBoneIndex(ped, propBone or 18905),
        attach.x or 0.0,
        attach.y or 0.0,
        attach.z or 0.0,
        attach.rx or 0.0,
        attach.ry or 0.0,
        attach.rz or 0.0,
        true,
        true,
        false,
        true,
        1,
        true
    )

    tipPtfxTool.active = true
    tipPtfxTool.prop = prop
    tipPtfxTool.offset = vec3(offset.x or 0.0, offset.y or 0.0, offset.z or 0.0)
    tipPtfxTool.rotation = vec3(rotation.x or 0.0, rotation.y or 180.0, rotation.z or 0.0)

    refreshTipPtfxToolFx()
    showTipPtfxToolUi()
    Config.Notify(locale('tip_ptfx_tool_started'), 'inform')

    CreateThread(function()
        local moveStep = DEBUG_TOOL_VERTICAL_STEP
        local fastMultiplier = DEBUG_TOOL_FAST_MULTIPLIER
        local verticalStep = DEBUG_TOOL_VERTICAL_STEP
        local rotationStep = DEBUG_TOOL_HEADING_STEP

        while tipPtfxTool.active do
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 36, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 172, true)
            DisableControlAction(0, 173, true)
            DisableControlAction(0, 174, true)
            DisableControlAction(0, 175, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 177, true)
            DisableControlAction(0, 191, true)
            DisablePlayerFiring(PlayerId(), true)

            local speed = IsDisabledControlPressed(0, 21) and fastMultiplier or 1.0
            local changed = false

            if IsDisabledControlPressed(0, 32) then tipPtfxTool.offset = vec3(tipPtfxTool.offset.x, tipPtfxTool.offset.y + (moveStep * speed), tipPtfxTool.offset.z); changed = true end
            if IsDisabledControlPressed(0, 33) then tipPtfxTool.offset = vec3(tipPtfxTool.offset.x, tipPtfxTool.offset.y - (moveStep * speed), tipPtfxTool.offset.z); changed = true end
            if IsDisabledControlPressed(0, 34) then tipPtfxTool.offset = vec3(tipPtfxTool.offset.x - (moveStep * speed), tipPtfxTool.offset.y, tipPtfxTool.offset.z); changed = true end
            if IsDisabledControlPressed(0, 35) then tipPtfxTool.offset = vec3(tipPtfxTool.offset.x + (moveStep * speed), tipPtfxTool.offset.y, tipPtfxTool.offset.z); changed = true end
            if IsDisabledControlPressed(0, 22) then tipPtfxTool.offset = vec3(tipPtfxTool.offset.x, tipPtfxTool.offset.y, tipPtfxTool.offset.z + (verticalStep * speed)); changed = true end
            if IsDisabledControlPressed(0, 36) then tipPtfxTool.offset = vec3(tipPtfxTool.offset.x, tipPtfxTool.offset.y, tipPtfxTool.offset.z - (verticalStep * speed)); changed = true end
            if IsDisabledControlPressed(0, 172) then tipPtfxTool.rotation = vec3(tipPtfxTool.rotation.x + (rotationStep * speed), tipPtfxTool.rotation.y, tipPtfxTool.rotation.z); changed = true end
            if IsDisabledControlPressed(0, 173) then tipPtfxTool.rotation = vec3(tipPtfxTool.rotation.x - (rotationStep * speed), tipPtfxTool.rotation.y, tipPtfxTool.rotation.z); changed = true end
            if IsDisabledControlPressed(0, 174) then tipPtfxTool.rotation = vec3(tipPtfxTool.rotation.x, tipPtfxTool.rotation.y, tipPtfxTool.rotation.z - (rotationStep * speed)); changed = true end
            if IsDisabledControlPressed(0, 175) then tipPtfxTool.rotation = vec3(tipPtfxTool.rotation.x, tipPtfxTool.rotation.y, tipPtfxTool.rotation.z + (rotationStep * speed)); changed = true end
            if IsDisabledControlPressed(0, 44) then tipPtfxTool.rotation = vec3(tipPtfxTool.rotation.x, tipPtfxTool.rotation.y - (rotationStep * speed), tipPtfxTool.rotation.z); changed = true end
            if IsDisabledControlPressed(0, 38) then tipPtfxTool.rotation = vec3(tipPtfxTool.rotation.x, tipPtfxTool.rotation.y + (rotationStep * speed), tipPtfxTool.rotation.z); changed = true end

            if changed then
                refreshTipPtfxToolFx()
                showTipPtfxToolUi()
            end

            if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201) then
                saveTipPtfxToolPlacement()
                break
            end

            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 202) then
                Config.Notify(locale('tip_ptfx_tool_cancelled'), 'inform')
                stopTipPtfxTool()
                break
            end

            Wait(0)
        end
    end)
end

local function playSyncedTipFxOnPed(pedEntity, landingCoords)
    if not pedEntity or not DoesEntityExist(pedEntity) then return end

    local tipConfig = Config.Tip or {}
    local cashProp
    local propName, propBone, attach = resolveTipPropConfig(tipConfig)

    if propName then
        local model = GetHashKey(propName)
        if model and model ~= 0 then
            if not HasModelLoaded(model) then
                RequestModel(model)
                local timeout = GetGameTimer() + 2000
                while not HasModelLoaded(model) and GetGameTimer() < timeout do
                    Wait(10)
                end
            end

            if HasModelLoaded(model) then
                cashProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
                if DoesEntityExist(cashProp) then
                    AttachEntityToEntity(
                        cashProp,
                        pedEntity,
                        GetPedBoneIndex(pedEntity, propBone or 18905),
                        attach.x or 0.12,
                        attach.y or 0.028,
                        attach.z or 0.001,
                        attach.rx or 300.0,
                        attach.ry or 180.0,
                        attach.rz or 20.0,
                        true,
                        true,
                        false,
                        true,
                        1,
                        true
                    )
                    storeAttachedTipProp(pedEntity, cashProp)
                end
                SetModelAsNoLongerNeeded(model)
            end
        end
    end

    CreateThread(function()
        local particles = resolveTipParticleConfig(tipConfig)

        local function playParticle(particleCfg, useTargetCoords)
            if type(particleCfg) ~= 'table' then return end

            local delay = math.max(0, particleCfg.delay or 0)
            if delay > 0 then
                Wait(delay)
            end

            local asset = particleCfg.asset or 'core'
            local effect = particleCfg.effect or 'ent_brk_banknotes'
            local handle

            if DoesEntityExist(pedEntity) and effect then
                RequestNamedPtfxAsset(asset)
                while not HasNamedPtfxAssetLoaded(asset) do
                    Wait(10)
                end
                UseParticleFxAssetNextCall(asset)
                local ox = (particleCfg.offset and particleCfg.offset.x) or 0.0
                local oy = (particleCfg.offset and particleCfg.offset.y) or 0.0
                local oz = (particleCfg.offset and particleCfg.offset.z) or 0.0
                local rx = (particleCfg.rotation and particleCfg.rotation.x) or 0.0
                local ry = (particleCfg.rotation and particleCfg.rotation.y) or 0.0
                local rz = (particleCfg.rotation and particleCfg.rotation.z) or 0.0
                local scale = particleCfg.scale or 1.0
                local bone = tonumber(particleCfg.bone)
                local attachToProp = particleCfg.attachToProp and cashProp and DoesEntityExist(cashProp)

                if useTargetCoords and landingCoords then
                    if particleCfg.looped then
                        handle = StartParticleFxLoopedAtCoord(effect, landingCoords.x + ox, landingCoords.y + oy, landingCoords.z + oz, rx, ry, rz, scale, false, false, false, false)
                    else
                        StartParticleFxNonLoopedAtCoord(effect, landingCoords.x + ox, landingCoords.y + oy, landingCoords.z + oz, rx, ry, rz, scale, false, false, false)
                    end
                elseif attachToProp then
                    if particleCfg.looped then
                        handle = StartParticleFxLoopedOnEntity(effect, cashProp, ox, oy, oz, rx, ry, rz, scale, false, false, false)
                    else
                        StartParticleFxNonLoopedOnEntity(effect, cashProp, ox, oy, oz, rx, ry, rz, scale, false, false, false)
                    end
                elseif bone then
                    if particleCfg.looped then
                        handle = StartParticleFxLoopedOnPedBone(effect, pedEntity, ox, oy, oz, rx, ry, rz, bone, scale, false, false, false)
                    else
                        StartParticleFxNonLoopedOnPedBone(effect, pedEntity, ox, oy, oz, rx, ry, rz, bone, scale, false, false, false)
                    end
                elseif particleCfg.looped then
                    handle = StartParticleFxLoopedOnEntity(effect, pedEntity, ox, oy, oz, rx, ry, rz, scale, false, false, false)
                else
                    StartParticleFxNonLoopedOnEntity(effect, pedEntity, ox, oy, oz, rx, ry, rz, scale, false, false, false)
                end
            end

            local duration = math.max(0, particleCfg.duration or particleCfg.cleanup or 3000)
            if duration > 0 then
                Wait(duration)
            end

            if handle then
                StopParticleFxLooped(handle, false)
                RemoveParticleFx(handle, false)
            end

            if asset then
                RemoveNamedPtfxAsset(asset)
            end
        end

        CreateThread(function()
            playParticle(particles.hand, false)
        end)

        CreateThread(function()
            playParticle(particles.target, true)
        end)

        local sequenceEndDelay = math.max(
            math.max(0, tonumber(tipConfig.releaseDelay) or 0),
            tonumber(tipConfig.sequenceEndDelay) or 0
        )
        if sequenceEndDelay > 0 then
            Wait(sequenceEndDelay)
        end

        if cashProp and DoesEntityExist(cashProp) then
            local tipConfig = Config.Tip or {}
            local dropCfg = tipConfig.drop or {}
            local finalCoords = landingCoords

            if not finalCoords then
                local pedCoords = GetEntityCoords(pedEntity)
                local forward = GetEntityForwardVector(pedEntity)
                local forwardDistance = tonumber(dropCfg.forward) or 0.75
                finalCoords = vector3(
                    pedCoords.x + (forward.x * forwardDistance),
                    pedCoords.y + (forward.y * forwardDistance),
                    pedCoords.z
                )
            end

            releaseTipPropToFloor(pedEntity, cashProp, finalCoords)
            cleanupAttachedTipPropsFromPed(pedEntity, false)

            local lifetime = math.max(1000, tonumber(tipConfig.floorLifetime) or 12000)
            SetTimeout(lifetime, function()
                if DoesEntityExist(cashProp) then
                    DeleteObject(cashProp)
                end

                removeDroppedTipPropEntry(pedEntity, cashProp)
            end)
        end
    end)
end

CreateThread(function()
    buildPoleMap()
    buildDanceZoneMap()
    refreshCurrentPlayerJobName()
    registerDanceZoneTargets()
    registerPoleTargets()

    for _, pole in ipairs(poles) do
        spawnPolePed(pole)
    end
end)

RegisterNetEvent('esx:setJob', function(job)
    setCurrentPlayerJobName(job)
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    setCurrentPlayerJobName(job)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    refreshCurrentPlayerJobName()
end)

RegisterNetEvent('qbx_core:client:onJobUpdate', function(job)
    setCurrentPlayerJobName(job)
end)

RegisterNetEvent('qbx_core:client:playerLoaded', function()
    refreshCurrentPlayerJobName()
end)

if AddStateBagChangeHandler then
    AddStateBagChangeHandler('job', nil, function(bagName, _, value)
        local localBagName = ('player:%s'):format(GetPlayerServerId(PlayerId()))
        if bagName == localBagName then
            setCurrentPlayerJobName(value)
        end
    end)

    AddStateBagChangeHandler('qbx:job', nil, function(bagName, _, value)
        local localBagName = ('player:%s'):format(GetPlayerServerId(PlayerId()))
        if bagName == localBagName then
            setCurrentPlayerJobName(value)
        end
    end)
end

CreateThread(function()
    if not lib or not lib.callback or not lib.callback.await then
        return
    end

    local states = awaitServerCallback(resourceName .. ':getActivePoleStates')
    if type(states) == 'table' then
        activePoleStates = states
    end

    local zoneStates = awaitServerCallback(resourceName .. ':getActiveZoneStates')
    if type(zoneStates) == 'table' then
        activeZoneStates = zoneStates
    end
end)

RegisterCommand('polepedtool', function(_, args)
    if not Config.Debug then
        return
    end

    local allowed = lib.callback.await(resourceName .. ':canUseAdminTool', false)
    if not allowed then
        Config.Notify(locale('admin_tool_denied'), 'error')
        return
    end

    if placementTool.active and (not args[1] or args[1] == 'stop' or args[1] == 'cancel') then
        Config.Notify(locale('admin_tool_cancelled'), 'inform')
        stopPlacementTool()
        return
    end

    local animationIndex = tonumber(args[1]) or placementTool.animationIndex or 1
    startPlacementTool(animationIndex)
end, false)

RegisterCommand('tipptfx', function()
    if not Config.Debug then
        return
    end

    if not lib or not lib.callback or not lib.callback.await then
        Config.Notify(locale('admin_tool_denied'), 'error')
        return
    end

    local allowed = lib.callback.await(resourceName .. ':canUseAdminTool', false)
    if not allowed then
        Config.Notify(locale('admin_tool_denied'), 'error')
        return
    end

    startTipPtfxTool()
end, false)

RegisterNetEvent(resourceName .. ':client:Notify', function(message, type)
    Config.Notify(message, type)
end)

RegisterNetEvent(resourceName .. ':client:PlayAnimation', function(animName, targetCoords)
    Config.PlayAnimation(animName, targetCoords)
end)

RegisterNetEvent(resourceName .. ':client:PlayTipFxOnPlayer', function(serverId, landingCoords)
    local targetServerId = tonumber(serverId)
    if not targetServerId then return end
    if targetServerId == GetPlayerServerId(PlayerId()) then return end

    local player = GetPlayerFromServerId(targetServerId)
    if player == -1 then return end

    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    local tipConfig = Config.Tip or {}
    local dict, anim = resolveTipAnimationConfig(tipConfig)
    if dict and anim and not IsEntityPlayingAnim(ped, dict, anim, 3) then
        loadAnimDict(dict)
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
    end

    playSyncedTipFxOnPed(ped, landingCoords)
end)

RegisterNetEvent(resourceName .. ':client:SyncActivePoles', function(states)
    activePoleStates = type(states) == 'table' and states or {}
end)

RegisterNetEvent(resourceName .. ':client:SyncActiveZones', function(states)
    activeZoneStates = type(states) == 'table' and states or {}
end)

local function clearTipPropsFromPed(ped)
    if not ped or not DoesEntityExist(ped) then return end
    cleanupAttachedTipPropsFromPed(ped, false)
end

RegisterNetEvent(resourceName .. ':client:StopTipAnimation', function()
    local ped = PlayerPedId()
    if not ped or not DoesEntityExist(ped) then return end

    local tip = Config.Tip or {}
    local dict, anim = resolveTipAnimationConfig(tip)

    if GetResourceState('rpemotes') == 'started' then
        pcall(function()
            exports.rpemotes:EmoteCancel()
        end)
    end

    if GetResourceState('rpemotes-reborn') == 'started' then
        pcall(function()
            exports['rpemotes-reborn']:EmoteCancel()
        end)
    end

    if GetResourceState('dpemotes') == 'started' then
        TriggerEvent('animations:client:EmoteCommandStart', { 'c' })
    end

    if dict and anim and IsEntityPlayingAnim(ped, dict, anim, 3) then
        StopAnimTask(ped, dict, anim, 2.0)
    end

    ClearPedSecondaryTask(ped)
    ClearPedTasks(ped)
    clearTipPropsFromPed(ped)

    CreateThread(function()
        Wait(250)
        clearTipPropsFromPed(ped)
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= resourceName then return end

    local placement = placementTool or { active = false }

    if isDancing then
        cleanupPoleDance()
    end

    if placement.active then
        stopPlacementTool()
    end

    if tipPtfxTool and tipPtfxTool.active then
        stopTipPtfxTool()
    end

    cleanupAllTipProps()

    if next(poleModels) and next(poleOptions) then
        oxTarget:removeModel(poleModels, poleOptions)
    end

    for id, zone in pairs(poleZones) do
        oxTarget:removeZone(zone)
        poleZones[id] = nil
    end

    for id, zone in pairs(danceZoneTargets) do
        oxTarget:removeZone(zone)
        danceZoneTargets[id] = nil
    end

    for id, ped in pairs(pedHandles) do
        if pedCycles[id] then
            pedCycles[id].active = false
            pedCycles[id] = nil
        end

        if pedTargets[id] then
            oxTarget:removeLocalEntity(ped)
            pedTargets[id] = nil
        end
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
        pedHandles[id] = nil
    end

    stopUi()
end)









