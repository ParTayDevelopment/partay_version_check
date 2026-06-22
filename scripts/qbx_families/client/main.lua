local menuOpen = false
local currentData
local activeEventZone
local activeEventZoneId
local activePropEvent
local spawnedEventProps = {}
local draftEventProps = {}
local placingEventPoints = false
local placingEventProp = false
local familyGizmoEnabled = false
local familyGizmoDone = false
local familyGizmoCancelled = false
local familyGizmoCursor = false
local familyGizmoEntity
local familyGizmoMode = 'Translate'
local familyGizmoSpace = 'World'
local tabletProp

local tabletAnim = {
    dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base',
    clip = 'base',
    prop = `prop_cs_tablet`,
    bone = 60309,
    position = vector3(0.03, 0.002, -0.02),
    rotation = vector3(10.0, 160.0, 0.0)
}

local function isDebugEnabled(scope)
    if Config.Debug == true then return true end
    if type(Config.Debug) == 'table' and Config.Debug.enabled == true then return true end
    if scope == 'eventZonePlacement' then
        if type(Config.Debug) == 'table' and Config.Debug.eventZonePlacement == true then return true end
        return Config.Events and Config.Events.debugPlacement == true
    end

    return false
end

local function debugLog(scope, message, ...)
    if not isDebugEnabled(scope) then return end

    if select('#', ...) > 0 then
        message = message:format(...)
    end

    print(('[qbx_families:%s] %s'):format(scope, message))
end

local function normalizeAxis(x, y, z)
    local length = math.sqrt((x * x) + (y * y) + (z * z))
    if length == 0.0 then return 0.0, 0.0, 0.0 end

    return x / length, y / length, z / length
end

local function createMatrixBuffer()
    local buffer = {
        blob = string.blob(64)
    }

    function buffer:setFloat(offset, value)
        self.blob = self.blob:blob_pack(offset + 1, '<f', value)
        return self
    end

    function buffer:getFloat(offset)
        return self.blob:blob_unpack(offset + 1, '<f')
    end

    function buffer:getBuffer()
        return self.blob
    end

    return buffer
end

local function makeEntityMatrix(entity)
    local forward, right, up, position = GetEntityMatrix(entity)
    local buffer = createMatrixBuffer()

    buffer:setFloat(0, right.x):setFloat(4, right.y):setFloat(8, right.z):setFloat(12, 0.0)
    buffer:setFloat(16, forward.x):setFloat(20, forward.y):setFloat(24, forward.z):setFloat(28, 0.0)
    buffer:setFloat(32, up.x):setFloat(36, up.y):setFloat(40, up.z):setFloat(44, 0.0)
    buffer:setFloat(48, position.x):setFloat(52, position.y):setFloat(56, position.z):setFloat(60, 1.0)

    return buffer
end

local function applyEntityMatrix(entity, buffer)
    local forwardX, forwardY, forwardZ = buffer:getFloat(16), buffer:getFloat(20), buffer:getFloat(24)
    local rightX, rightY, rightZ = buffer:getFloat(0), buffer:getFloat(4), buffer:getFloat(8)
    local upX, upY, upZ = buffer:getFloat(32), buffer:getFloat(36), buffer:getFloat(40)
    local positionX, positionY, positionZ = buffer:getFloat(48), buffer:getFloat(52), buffer:getFloat(56)

    forwardX, forwardY, forwardZ = normalizeAxis(forwardX, forwardY, forwardZ)
    rightX, rightY, rightZ = normalizeAxis(rightX, rightY, rightZ)
    upX, upY, upZ = normalizeAxis(upX, upY, upZ)

    SetEntityMatrix(
        entity,
        forwardX, forwardY, forwardZ,
        rightX, rightY, rightZ,
        upX, upY, upZ,
        positionX, positionY, positionZ
    )
end

local function formatVector(coords)
    return ('%.2f, %.2f, %.2f'):format(coords.x, coords.y, coords.z)
end

lib.addKeybind({
    name = 'qbx_families_gizmo_select',
    description = 'Family event gizmo select',
    defaultMapper = 'MOUSE_BUTTON',
    defaultKey = 'MOUSE_LEFT',
    onPressed = function()
        if not familyGizmoEnabled then return end
        ExecuteCommand('+gizmoSelect')
    end,
    onReleased = function()
        if not familyGizmoEnabled then return end
        ExecuteCommand('-gizmoSelect')
    end
})

lib.addKeybind({
    name = 'qbx_families_gizmo_translate',
    description = 'Family event gizmo translate mode',
    defaultKey = 'W',
    onPressed = function()
        if not familyGizmoEnabled then return end
        familyGizmoMode = 'Translate'
        ExecuteCommand('+gizmoTranslation')
    end,
    onReleased = function()
        if not familyGizmoEnabled then return end
        ExecuteCommand('-gizmoTranslation')
    end
})

lib.addKeybind({
    name = 'qbx_families_gizmo_rotate',
    description = 'Family event gizmo rotate mode',
    defaultKey = 'R',
    onPressed = function()
        if not familyGizmoEnabled then return end
        familyGizmoMode = 'Rotate'
        ExecuteCommand('+gizmoRotation')
    end,
    onReleased = function()
        if not familyGizmoEnabled then return end
        ExecuteCommand('-gizmoRotation')
    end
})

lib.addKeybind({
    name = 'qbx_families_gizmo_space',
    description = 'Family event gizmo world or relative space',
    defaultKey = 'Q',
    onPressed = function()
        if not familyGizmoEnabled then return end
        familyGizmoSpace = familyGizmoSpace == 'World' and 'Relative' or 'World'
        ExecuteCommand('+gizmoLocal')
    end,
    onReleased = function()
        if not familyGizmoEnabled then return end
        ExecuteCommand('-gizmoLocal')
    end
})

lib.addKeybind({
    name = 'qbx_families_gizmo_cursor',
    description = 'Family event gizmo cursor toggle',
    defaultKey = 'G',
    onPressed = function()
        if not familyGizmoEnabled then return end

        if familyGizmoCursor then
            LeaveCursorMode()
            familyGizmoCursor = false
        else
            EnterCursorMode()
            familyGizmoCursor = true
        end
    end
})

lib.addKeybind({
    name = 'qbx_families_gizmo_ground',
    description = 'Family event gizmo snap to ground',
    defaultKey = 'LMENU',
    onPressed = function()
        if not familyGizmoEnabled or not familyGizmoEntity or not DoesEntityExist(familyGizmoEntity) then return end

        if PlaceObjectOnGroundProperly_2 then
            PlaceObjectOnGroundProperly_2(familyGizmoEntity)
        else
            PlaceObjectOnGroundProperly(familyGizmoEntity)
        end
    end
})

lib.addKeybind({
    name = 'qbx_families_gizmo_done',
    description = 'Family event gizmo save placement',
    defaultKey = 'RETURN',
    onReleased = function()
        if not familyGizmoEnabled then return end
        familyGizmoDone = true
    end
})

lib.addKeybind({
    name = 'qbx_families_gizmo_cancel',
    description = 'Family event gizmo cancel placement',
    defaultKey = 'X',
    onReleased = function()
        if not familyGizmoEnabled then return end
        familyGizmoCancelled = true
        familyGizmoDone = true
    end
})

local function useEntityGizmo(entity, label)
    if not entity or not DoesEntityExist(entity) then return nil end

    familyGizmoEnabled = true
    familyGizmoDone = false
    familyGizmoCancelled = false
    familyGizmoCursor = true
    familyGizmoEntity = entity
    familyGizmoMode = 'Translate'
    familyGizmoSpace = 'World'

    EnterCursorMode()
    SetEntityDrawOutline(entity, true)

    while familyGizmoEnabled and not familyGizmoDone and DoesEntityExist(entity) do
        Wait(0)

        DisablePlayerFiring(PlayerId(), true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 73, true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 200, true)

        if IsDisabledControlJustPressed(0, 73) or IsDisabledControlJustPressed(0, 200) or IsControlJustPressed(0, 73) or IsControlJustPressed(0, 200) then
            familyGizmoCancelled = true
            familyGizmoDone = true
        end

        local matrix = makeEntityMatrix(entity)
        local changed = Citizen.InvokeNative(0xEB2EDCA2, matrix:getBuffer(), 'FamilyEventGizmo', Citizen.ReturnResultAnyway())
        if changed then
            applyEntityMatrix(entity, matrix)
        end

        local coords = GetEntityCoords(entity)
        local rotation = GetEntityRotation(entity, 2)
        lib.showTextUI(('%s\nMode: %s | Space: %s\nPosition: %s\nRotation: %s\n[G] Cursor | [W] Move | [R] Rotate | [Q] World/Relative | [LALT] Ground | [ENTER] Save | [X/ESC] Cancel'):format(
            label or 'Scene Prop',
            familyGizmoMode,
            familyGizmoSpace,
            formatVector(coords),
            formatVector(rotation)
        ))
    end

    lib.hideTextUI()

    ExecuteCommand('-gizmoSelect')
    ExecuteCommand('-gizmoTranslation')
    ExecuteCommand('-gizmoRotation')
    ExecuteCommand('-gizmoLocal')

    if familyGizmoCursor then
        LeaveCursorMode()
    end

    if DoesEntityExist(entity) then
        SetEntityDrawOutline(entity, false)
    end

    local cancelled = familyGizmoCancelled
    familyGizmoEnabled = false
    familyGizmoDone = false
    familyGizmoCancelled = false
    familyGizmoCursor = false
    familyGizmoEntity = nil

    if cancelled or not DoesEntityExist(entity) then return nil end

    return {
        position = GetEntityCoords(entity),
        rotation = GetEntityRotation(entity, 2),
        heading = GetEntityHeading(entity)
    }
end

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)

    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Wait(10)
    end

    return HasAnimDictLoaded(dict)
end

local function loadModel(model)
    if HasModelLoaded(model) then return true end

    RequestModel(model)

    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(10)
    end

    return HasModelLoaded(model)
end

local function stopTabletAnimation()
    local ped = PlayerPedId()

    if tabletProp and DoesEntityExist(tabletProp) then
        DeleteEntity(tabletProp)
    end

    tabletProp = nil
    ClearPedSecondaryTask(ped)
end

local function startTabletAnimation()
    local ped = PlayerPedId()
    if tabletProp and DoesEntityExist(tabletProp) then
        if not IsEntityPlayingAnim(ped, tabletAnim.dict, tabletAnim.clip, 3) then
            TaskPlayAnim(ped, tabletAnim.dict, tabletAnim.clip, 4.0, -4.0, -1, 49, 0.0, false, false, false)
        end
        return
    end

    if not loadAnimDict(tabletAnim.dict) or not loadModel(tabletAnim.prop) then return end

    local coords = GetEntityCoords(ped)
    tabletProp = CreateObject(tabletAnim.prop, coords.x, coords.y, coords.z, true, true, false)

    AttachEntityToEntity(
        tabletProp,
        ped,
        GetPedBoneIndex(ped, tabletAnim.bone),
        tabletAnim.position.x,
        tabletAnim.position.y,
        tabletAnim.position.z,
        tabletAnim.rotation.x,
        tabletAnim.rotation.y,
        tabletAnim.rotation.z,
        true,
        true,
        false,
        true,
        1,
        true
    )

    SetModelAsNoLongerNeeded(tabletAnim.prop)
    TaskPlayAnim(ped, tabletAnim.dict, tabletAnim.clip, 4.0, -4.0, -1, 49, 0.0, false, false, false)
end

local function clearEventZone()
    if activeEventZone and activeEventZone.destroy then
        activeEventZone:destroy()
    end

    activeEventZone = nil
    activeEventZoneId = nil
end

local function clearEventProps()
    for _, object in pairs(spawnedEventProps) do
        if object and DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end

    spawnedEventProps = {}
end

local function clearDraftEventProps()
    for _, object in pairs(draftEventProps) do
        if object and DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end

    draftEventProps = {}
end

local function getAllowedEventProp(propId)
    propId = tostring(propId or '')
    for _, prop in ipairs(Config.Events.allowedProps or {}) do
        if tostring(prop.id or '') == propId then
            return prop
        end
    end
end

local function syncEventProps(event)
    if not event or event.status == 'scheduled' then
        activePropEvent = nil
        clearEventProps()
        return
    end

    activePropEvent = event
end

local function updateEventProps()
    if not activePropEvent or not activePropEvent.coords then
        clearEventProps()
        return
    end

    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local center = vector3(activePropEvent.coords.x, activePropEvent.coords.y, activePropEvent.coords.z)
    local streamDistance = Config.Events.propStreamDistance or 140.0

    if #(playerCoords - center) > streamDistance then
        clearEventProps()
        return
    end

    local wanted = {}
    for index, prop in ipairs(activePropEvent.props or {}) do
        if prop.coords and prop.model then
            wanted[index] = true

            if not spawnedEventProps[index] or not DoesEntityExist(spawnedEventProps[index]) then
                local model = GetHashKey(prop.model)
                if loadModel(model) then
                    local coords = prop.coords
                    local object = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
                    if prop.rotation then
                        SetEntityRotation(object, tonumber(prop.rotation.x) or 0.0, tonumber(prop.rotation.y) or 0.0, tonumber(prop.rotation.z) or 0.0, 2, true)
                    else
                        SetEntityHeading(object, tonumber(prop.heading) or 0.0)
                    end
                    FreezeEntityPosition(object, true)
                    SetEntityInvincible(object, true)
                    SetModelAsNoLongerNeeded(model)
                    spawnedEventProps[index] = object
                end
            end
        end
    end

    for index, object in pairs(spawnedEventProps) do
        if not wanted[index] and object and DoesEntityExist(object) then
            DeleteEntity(object)
            spawnedEventProps[index] = nil
        end
    end
end

local function syncEventZone(event)
    if not event or event.status == 'scheduled' then
        clearEventZone()
        return
    end

    if activeEventZoneId == event.id then return end

    clearEventZone()

    activeEventZoneId = event.id
    if event.points and #event.points >= (Config.Events.minZonePoints or 4) then
        local points = {}
        local minZ, maxZ

        for _, point in ipairs(event.points) do
            points[#points + 1] = vector2(point.x, point.y)
            minZ = minZ and math.min(minZ, point.z) or point.z
            maxZ = maxZ and math.max(maxZ, point.z) or point.z
        end

        activeEventZone = PolyZone:Create(points, {
            name = ('qbx_family_event_%s'):format(event.id),
            minZ = (minZ or 0.0) - 4.0,
            maxZ = (maxZ or 0.0) + 8.0,
            debugPoly = Config.Events.debugZone == true
        })
    elseif event.coords then
        activeEventZone = CircleZone:Create(vector3(event.coords.x, event.coords.y, event.coords.z), event.radius, {
            name = ('qbx_family_event_%s'):format(event.id),
            useZ = false,
            debugPoly = Config.Events.debugZone == true
        })
    end
end

local function setMenuFocus(state)
    menuOpen = state
    SetNuiFocus(state, state)

    if state then
        startTabletAnimation()
    end
end

local function tabletNotify(description, notifyType)
    if menuOpen then
        SendNUIMessage({
            action = 'toast',
            description = description,
            type = notifyType or 'inform'
        })
        return
    end

    lib.notify({
        title = 'Family',
        description = description,
        type = notifyType or 'inform',
        position = 'top'
    })
end

local function setCaptureMode(state)
    if state then
        stopTabletAnimation()
    end

    SendNUIMessage({
        action = 'captureMode',
        active = state == true
    })
end

local function sendEventPoints(points)
    SendNUIMessage({
        action = 'eventZonePointsSelected',
        points = points or {}
    })
end

local function sendEventBanner(image)
    SendNUIMessage({
        action = 'eventBannerCaptured',
        bannerUrl = image
    })
end

local function sendEventProp(prop)
    SendNUIMessage({
        action = 'eventPropPlaced',
        prop = prop
    })
end

local function drawDraftZonePoints(points, currentCoords)
    local previous

    for index, point in ipairs(points or {}) do
        DrawMarker(1, point.x, point.y, point.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.25, 1.25, 0.35, 236, 82, 236, 140, false, false, 2, false, nil, nil, false)

        if previous then
            DrawLine(previous.x, previous.y, previous.z + 0.25, point.x, point.y, point.z + 0.25, 236, 82, 236, 210)
        end

        previous = point
    end

    if previous and currentCoords then
        DrawLine(previous.x, previous.y, previous.z + 0.25, currentCoords.x, currentCoords.y, currentCoords.z + 0.25, 31, 208, 195, 210)
    end

    if #(points or {}) >= 3 then
        local first = points[1]
        DrawLine(previous.x, previous.y, previous.z + 0.25, first.x, first.y, first.z + 0.25, 236, 82, 236, 160)
    end
end

local function normalizeDraftPoints(points)
    local clean = {}
    for _, point in ipairs(points or {}) do
        local x = tonumber(point.x)
        local y = tonumber(point.y)
        local z = tonumber(point.z)
        if x and y and z then
            clean[#clean + 1] = { x = x, y = y, z = z }
        end
    end

    return clean
end

local function isPointInsideDraftZone(point, polygon)
    local inside = false
    local j = #polygon

    for i = 1, #polygon do
        local pi = polygon[i]
        local pj = polygon[j]

        if ((pi.y > point.y) ~= (pj.y > point.y)) and (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) + 0.000001) + pi.x) then
            inside = not inside
        end

        j = i
    end

    return inside
end

local function placeEventProp(propId, zonePoints)
    if placingEventProp then return end

    zonePoints = normalizeDraftPoints(zonePoints)
    if #zonePoints < (Config.Events.minZonePoints or 4) then
        tabletNotify(('Add at least %s zone points before placing props.'):format(Config.Events.minZonePoints or 4), 'error')
        return
    end

    local definition = getAllowedEventProp(propId)
    if not definition then
        tabletNotify('That prop is not configured for family events.', 'error')
        return
    end

    local model = GetHashKey(definition.model)
    if not loadModel(model) then
        tabletNotify('Could not load that prop model.', 'error')
        return
    end

    placingEventProp = true

    CreateThread(function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local forward = GetEntityForwardVector(ped)
        coords = coords + (forward * 2.2)
        local object = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)

        SetEntityHeading(object, GetEntityHeading(ped))
        FreezeEntityPosition(object, true)
        PlaceObjectOnGroundProperly(object)
        SetModelAsNoLongerNeeded(model)

        setMenuFocus(false)
        setCaptureMode(true)
        Wait(250)

        local result

        while placingEventProp do
            result = useEntityGizmo(object, definition.label or definition.id)

            if not result then
                placingEventProp = false
                setCaptureMode(false)
                setMenuFocus(true)

                if object and DoesEntityExist(object) then
                    DeleteEntity(object)
                end

                tabletNotify('Prop placement cancelled.', 'inform')
                return
            end

            local candidateCoords = result.position
            if isPointInsideDraftZone({ x = candidateCoords.x, y = candidateCoords.y }, zonePoints) then
                break
            end

            tabletNotify('Prop must be placed inside the event zone.', 'error')
            Wait(500)
        end

        placingEventProp = false
        setCaptureMode(false)
        setMenuFocus(true)

        local placedCoords = result.position
        local rotation = result.rotation
        local draftId = ('prop_%s_%s'):format(GetGameTimer(), math.random(1000, 9999))

        FreezeEntityPosition(object, true)
        draftEventProps[draftId] = object

        sendEventProp({
            draftId = draftId,
            id = tostring(definition.id),
            label = definition.label or definition.id,
            model = definition.model,
            coords = {
                x = placedCoords.x,
                y = placedCoords.y,
                z = placedCoords.z
            },
            rotation = {
                x = rotation.x,
                y = rotation.y,
                z = rotation.z
            },
            heading = result.heading
        })
    end)
end

local function addEventZonePoints(points)
    if placingEventPoints then
        debugLog('eventZonePlacement', 'ignored start request because placement is already active')
        return
    end

    placingEventPoints = true

    local originalPoints = points or {}
    points = {}

    for _, point in ipairs(originalPoints) do
        points[#points + 1] = {
            x = point.x,
            y = point.y,
            z = point.z
        }
    end

    CreateThread(function()
        debugLog('eventZonePlacement', 'starting placement with %s existing points', #points)
        setMenuFocus(false)
        setCaptureMode(true)

        local ignoreInputUntil = GetGameTimer() + 1000
        Wait(350)

        while placingEventPoints do
            Wait(0)

            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local acceptingInput = GetGameTimer() >= ignoreInputUntil

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 73, true)
            DisableControlAction(0, 191, true)

            drawDraftZonePoints(points, coords)
            DrawMarker(1, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.6, 1.6, 0.45, 31, 208, 195, 160, false, false, 2, false, nil, nil, false)

            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('Zone points: %s. Right-click add point. Enter save. X/Esc cancel.%s'):format(#points, acceptingInput and '' or ' Getting ready...'))
            EndTextCommandDisplayHelp(0, false, true, -1)

            SetTextFont(4)
            SetTextScale(0.38, 0.38)
            SetTextColour(245, 248, 242, 230)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(('Saved Points: %s'):format(#points))
            EndTextCommandDisplayText(0.82, 0.78)

            if acceptingInput and (IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 25)) then
                points[#points + 1] = {
                    x = coords.x,
                    y = coords.y,
                    z = coords.z
                }
                debugLog('eventZonePlacement', 'added point #%s at %.2f %.2f %.2f', #points, coords.x, coords.y, coords.z)
            end

            if acceptingInput and (IsDisabledControlJustPressed(0, 191) or IsControlJustPressed(0, 191)) then
                placingEventPoints = false
                setCaptureMode(false)
                setMenuFocus(true)
                sendEventPoints(points)
                debugLog('eventZonePlacement', 'saved placement with %s points', #points)
                return
            end

            if acceptingInput and (IsDisabledControlJustPressed(0, 73) or IsDisabledControlJustPressed(0, 200) or IsControlJustPressed(0, 73) or IsControlJustPressed(0, 200)) then
                local cancelControl = 200
                if IsDisabledControlJustPressed(0, 73) or IsControlJustPressed(0, 73) then
                    cancelControl = 73
                end

                placingEventPoints = false
                setCaptureMode(false)
                setMenuFocus(true)
                sendEventPoints(originalPoints)
                tabletNotify('Zone point placement cancelled.', 'inform')
                debugLog('eventZonePlacement', 'cancelled placement from control %s and restored %s original points', cancelControl, #originalPoints)
                return
            end
        end
    end)
end

local function requestBannerScreenshot()
    if GetResourceState('screenshot-basic') ~= 'started' then
        return nil
    end

    local screenshot = promise.new()

    local ok = pcall(function()
        exports['screenshot-basic']:requestScreenshot({
            encoding = Config.Events.screenshotEncoding or 'jpg',
            quality = Config.Events.screenshotQuality or 0.68
        }, function(data)
            screenshot:resolve(data)
        end)
    end)

    if not ok then return nil end

    return Citizen.Await(screenshot)
end

local function captureEventBanner()
    local previousPedCam = GetFollowPedCamViewMode()
    local previousVehicleCam = GetFollowVehicleCamViewMode()

    local function restoreCamera()
        SetFollowPedCamViewMode(previousPedCam)
        SetFollowVehicleCamViewMode(previousVehicleCam)
    end

    setMenuFocus(false)
    setCaptureMode(true)
    SetFollowPedCamViewMode(4)
    SetFollowVehicleCamViewMode(4)
    Wait(250)

    while true do
        Wait(0)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 200, true)
        DisableControlAction(0, 177, true)

        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName('Face the event scene. Right-click to capture banner. Press Backspace to cancel.')
        EndTextCommandDisplayHelp(0, false, true, -1)

        if IsDisabledControlJustPressed(0, 25) then
            setCaptureMode(false)
            Wait(250)

            local image = requestBannerScreenshot()
            restoreCamera()
            setMenuFocus(true)

            if image and image ~= '' then
                tabletNotify('Event banner captured.', 'success')
                return image
            end

            tabletNotify('Screenshot capture failed. Saving without a banner.', 'error')
            return nil
        end

        if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) then
            setCaptureMode(false)
            restoreCamera()
            setMenuFocus(true)
            tabletNotify('Banner capture skipped.', 'inform')
            return nil
        end
    end
end

local function fetchFamilyData()
    currentData = lib.callback.await('qbx_families:server:getMenuData', false)
    return currentData
end

local function sendFamilyData()
    local data = fetchFamilyData()
    if not data or not data.self then return end

    syncEventZone(data.event)
    syncEventProps(data.event)

    SendNUIMessage({
        action = 'open',
        data = data
    })

    setMenuFocus(true)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clearEventZone()
        clearEventProps()
        clearDraftEventProps()
        stopTabletAnimation()
    end
end)

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('qbx_families:server:requestActivePropScenes')

    while true do
        Wait(2000)
        updateEventProps()
    end
end)

local function closeFamilyMenu()
    SendNUIMessage({ action = 'close' })
    setMenuFocus(false)
    clearDraftEventProps()
    stopTabletAnimation()
end

local function roleOptions(roles)
    local options = {}

    for _, role in ipairs(roles or {}) do
        options[#options + 1] = {
            value = role.value,
            label = role.label
        }
    end

    return options
end

local function playerOptions(players)
    local options = {}

    for _, player in ipairs(players or {}) do
        options[#options + 1] = {
            value = player.source,
            label = ('%s (ID: %s)'):format(player.name, player.source)
        }
    end

    return options
end

local function refreshFamilyMenu(delay)
    SetTimeout(delay or 500, function()
        if menuOpen then sendFamilyData() end
    end)
end

local function donationAccountOptions(accounts)
    local options = {}

    for _, account in ipairs(accounts or {}) do
        options[#options + 1] = {
            value = account.value,
            label = account.label or account.value
        }
    end

    if #options == 0 then
        options[#options + 1] = { value = 'cash', label = 'Cash' }
    end

    return options
end

local function openFamilyMenu()
    sendFamilyData()
end

RegisterCommand(Config.Command, openFamilyMenu, false)
TriggerEvent('chat:addSuggestion', ('/%s'):format(Config.Command), 'Open your family menu')

RegisterNUICallback('close', function(_, cb)
    closeFamilyMenu()
    cb({})
end)

RegisterNUICallback('refresh', function(_, cb)
    sendFamilyData()
    cb({})
end)

RegisterNUICallback('invite', function(_, cb)
    cb({})
    if not currentData then return end

    setMenuFocus(false)

    local nearby = playerOptions(currentData.nearby)
    if #nearby == 0 then
        setMenuFocus(true)
        tabletNotify('No nearby players found.', 'error')
        return
    end

    local input = lib.inputDialog('Invite Family Member', {
        {
            type = 'select',
            label = 'Player',
            options = nearby,
            required = true
        },
        {
            type = 'select',
            label = 'Role',
            options = roleOptions(currentData.roles),
            required = true
        }
    })

    setMenuFocus(true)

    if input and input[1] and input[2] then
        TriggerServerEvent('qbx_families:server:invite', input[1], input[2])
        refreshFamilyMenu()
    end
end)

RegisterNUICallback('setRole', function(data, cb)
    cb({})
    if not currentData or not data or not data.citizenid then return end

    setMenuFocus(false)

    local input = lib.inputDialog('Change Family Role', {
        {
            type = 'select',
            label = 'Role',
            options = roleOptions(currentData.roles),
            required = true
        }
    })

    setMenuFocus(true)

    if input and input[1] then
        TriggerServerEvent('qbx_families:server:setRole', data.citizenid, input[1])
        refreshFamilyMenu()
    end
end)

RegisterNUICallback('allowance', function(data, cb)
    cb({})
    if not currentData or not data or not data.citizenid then return end

    setMenuFocus(false)

    local input = lib.inputDialog('Give Allowance', {
        {
            type = 'number',
            label = 'Amount',
            min = 1,
            max = currentData.allowanceMax,
            required = true
        }
    })

    setMenuFocus(true)

    if input and input[1] then
        TriggerServerEvent('qbx_families:server:allowance', data.citizenid, input[1])
        refreshFamilyMenu()
    end
end)

RegisterNUICallback('donateFunds', function(_, cb)
    cb({})
    if not currentData or not currentData.self or currentData.self.family == 'none' then return end

    setMenuFocus(false)

    local funds = currentData.funds or {}
    local input = lib.inputDialog('Donate Family Funds', {
        {
            type = 'number',
            label = 'Amount',
            min = funds.minDonation or 1,
            max = funds.maxDonation or 100000,
            required = true
        },
        {
            type = 'select',
            label = 'Money Type',
            options = donationAccountOptions(funds.donationAccounts),
            required = true
        }
    })

    setMenuFocus(true)

    if input and input[1] and input[2] then
        TriggerServerEvent('qbx_families:server:donateFunds', {
            amount = input[1],
            account = input[2]
        })
        refreshFamilyMenu(750)
    end
end)

RegisterNUICallback('kick', function(data, cb)
    cb({})
    if not data or not data.citizenid then return end

    setMenuFocus(false)

    local confirmed = lib.alertDialog({
        header = 'Remove Family Member',
        content = ('Remove %s from the family?'):format(data.name or 'this member'),
        centered = true,
        cancel = true
    })

    setMenuFocus(true)

    if confirmed == 'confirm' then
        TriggerServerEvent('qbx_families:server:kick', data.citizenid)
        refreshFamilyMenu()
    end
end)

RegisterNUICallback('redeem', function(data, cb)
    cb({})
    if not data or not data.rewardId then return end

    setMenuFocus(false)

    local confirmed = lib.alertDialog({
        header = 'Redeem Family Unlock',
        content = ('Redeem %s?'):format(data.label or 'this unlock'),
        centered = true,
        cancel = true
    })

    setMenuFocus(true)

    if confirmed == 'confirm' then
        TriggerServerEvent('qbx_families:server:redeemReward', data.rewardId)
        refreshFamilyMenu(750)
    end
end)

RegisterNUICallback('saveSettings', function(data, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end

    TriggerServerEvent('qbx_families:server:saveSettings', data or {})
    refreshFamilyMenu(750)
end)

RegisterNUICallback('createEventTemplate', function(_, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end
    SendNUIMessage({ action = 'createEventDraft' })
end)

RegisterNUICallback('addEventZonePoints', function(data, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end
    addEventZonePoints(data and data.points or {})
end)

RegisterNUICallback('addEventProp', function(data, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end
    if not data or not data.propId then return end
    placeEventProp(data.propId, data.points or {})
end)

RegisterNUICallback('clearDraftEventProps', function(_, cb)
    cb({})
    clearDraftEventProps()
end)

RegisterNUICallback('captureEventBanner', function(_, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end
    sendEventBanner(captureEventBanner())
end)

RegisterNUICallback('saveEventTemplate', function(data, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end

    TriggerServerEvent('qbx_families:server:createEventTemplate', data or {})
    refreshFamilyMenu(750)
end)

RegisterNUICallback('shareEventTemplate', function(data, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end

    TriggerServerEvent('qbx_families:server:shareEventTemplate', data or {})
    refreshFamilyMenu(750)
end)

RegisterNUICallback('startEvent', function(data, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end
    if not data or not data.templateId then return end

    TriggerServerEvent('qbx_families:server:startEvent', {
        templateId = data.templateId
    })
    refreshFamilyMenu(750)
end)

RegisterNUICallback('stopEvent', function(_, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end

    setMenuFocus(false)

    local confirmed = lib.alertDialog({
        header = 'Stop Family Event',
        content = 'Stop the active family event?',
        centered = true,
        cancel = true
    })

    setMenuFocus(true)

    if confirmed == 'confirm' then
        TriggerServerEvent('qbx_families:server:stopEvent')
        refreshFamilyMenu(750)
    end
end)

RegisterNetEvent('qbx_families:client:notify', function(description, notifyType)
    tabletNotify(description, notifyType)
end)

RegisterNetEvent('qbx_families:client:refreshMenu', function()
    refreshFamilyMenu(150)
end)

RegisterNetEvent('qbx_families:client:syncEventProps', function(event)
    syncEventProps(event)
    updateEventProps()
end)

RegisterNUICallback('deleteEventTemplate', function(data, cb)
    cb({})
    if not currentData or not currentData.self or not currentData.self.isHead then return end
    if not data or not data.templateId then return end

    TriggerServerEvent('qbx_families:server:deleteEventTemplate', data.templateId)
    refreshFamilyMenu(750)
end)
