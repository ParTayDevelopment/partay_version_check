local insideZone = true
local lastWarn = 0
local lastSafeCoords = nil
local lastSafeHeading = nil
local releaseMarked = false
local greeterPed = nil
local jobCounselorPed = nil
local greeterAvailable = false
local greeterOpenedThisVisit = false
local greeterOpenedUi = false
local starterBlip = nil
local starterVehicleBlip = nil
local starterVehicleEntity = nil
local playerReady = false
local playerReadyToken = 0
local starterActive = false
local nuiOpen = false
local currentUiTab = 'checklist'
local currentUiMode = 'starter'
local closeCitizenUi
local deleteGreeterPed
local deleteJobCounselorPed
local deleteStarterBlip
local deleteStarterVehicleBlip

local function notify(description, notifyType)
    lib.notify({
        title = 'No Love Lost',
        description = description,
        type = notifyType or 'inform',
        position = 'top'
    })
end

local function hasLoadedPlayerData()
    local ok, data = pcall(function()
        return exports.qbx_core:GetPlayerData()
    end)

    return ok and type(data) == 'table' and data.citizenid ~= nil
end

local function markPlayerNotReady()
    playerReadyToken += 1
    playerReady = false
    starterActive = false
    greeterAvailable = false
    greeterOpenedThisVisit = false
    greeterOpenedUi = false

    if nuiOpen then
        closeCitizenUi()
    end

    deleteGreeterPed()
    deleteJobCounselorPed()
    deleteStarterBlip()
    deleteStarterVehicleBlip()
end

local function markPlayerReady()
    playerReadyToken += 1
    local token = playerReadyToken

    CreateThread(function()
        Wait(Config.PlayerLoadedActivationDelay or 5000)
        if token ~= playerReadyToken then return end
        if not hasLoadedPlayerData() then return end

        playerReady = true
        starterActive = false
    end)
end

local function waitUntilPlayerReady()
    while not playerReady do
        Wait(500)
    end
end

local function setStarterJobWaypoint(waypoint)
    if type(waypoint) ~= 'table' or not waypoint.x or not waypoint.y then return end

    SetNewWaypoint(waypoint.x + 0.0, waypoint.y + 0.0)
end

local function fmtTime(seconds)
    seconds = tonumber(seconds) or 0
    local mins = math.floor(seconds / 60)
    return ('%s min'):format(mins)
end

local function fmtMiles(meters)
    return ('%.1f mi'):format((tonumber(meters) or 0.0) / 1609.344)
end

local function taskPrefix(passed)
    return passed and 'Complete' or 'Pending'
end

local validStarterTabs = {
    checklist = true,
    starter = true,
    jobs = true,
    cityinfo = true
}

local function sortByLabel(a, b)
    return (a.label or a.item or a.name) < (b.label or b.item or b.name)
end

local function getDefaultStarterUiTab()
    local tab = Config.DefaultStarterUiTab or 'checklist'
    return validStarterTabs[tab] and tab or 'checklist'
end

local function getStarterJobs()
    local jobs = {}
    for jobName, data in pairs(Config.AllowedStarterJobs) do
        jobs[#jobs + 1] = {
            name = jobName,
            label = data.label or jobName,
            icon = data.icon or '&#128188;',
            description = data.description or 'Allowed starter job for new citizens.',
            locked = data.locked == true,
            lockedDescription = data.lockedDescription or 'Unlocks after your new citizen clearance is complete.',
            stats = data.stats or {}
        }
    end
    table.sort(jobs, sortByLabel)
    return jobs
end

local function sendCitizenUiPayload(tab, mode)
    if not playerReady then
        notify('Starter services will be available after your character finishes loading into the city.', 'inform')
        return false
    end

    local status = lib.callback.await('starter_zone:getStatus', false)
    if not status then
        notify('Could not load your New Citizen Checklist. Please try again in a moment or open a Discord ticket if it continues.', 'error')
        return false
    end

    if status.released then
        notify('Your new citizen clearance is complete. Starter services are closed for this character.', 'inform')
        return false
    end

    SendNUIMessage({
        action = 'setData',
        tab = tab or 'checklist',
        mode = mode or 'starter',
        status = status,
        profile = status.starterKit and status.starterKit.profile or 'default',
        profileLabel = status.starterKit and status.starterKit.label or 'Starter Pack',
        theme = status.starterKit and status.starterKit.theme or 'default',
        items = status.starterKit and status.starterKit.items or {},
        vehicles = status.starterKit and status.starterKit.vehicles or {},
        bonus = status.starterKit and status.starterKit.bonus or nil,
        budget = status.starterKit and status.starterKit.budget or 0,
        jobs = getStarterJobs(),
        maxChoices = status.starterKit and status.starterKit.maxChoices or 6,
        requiredItem = status.starterKit and status.starterKit.requiredItem or nil,
        requiredItemLabel = status.starterKit and status.starterKit.requiredItemLabel or nil,
        requirements = Config.Requirements,
        setJobFromMenu = Config.SetJobFromMenu
    })

    return true
end

local function openCitizenUi(tab, mode)
    if not sendCitizenUiPayload(tab or 'checklist', mode) then return end
    nuiOpen = true
    currentUiTab = tab or 'checklist'
    currentUiMode = mode or 'starter'
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'show',
        tab = tab or 'checklist',
        mode = mode or 'starter'
    })
end

closeCitizenUi = function()
    nuiOpen = false
    currentUiTab = 'checklist'
    currentUiMode = 'starter'
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
end

local function requestModel(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        print(('[starter_zone] Invalid greeter NPC model: %s'):format(model))
        return nil
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            print(('[starter_zone] Timed out loading greeter NPC model: %s'):format(model))
            return nil
        end
        Wait(50)
    end

    return hash
end

local function requestAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then
            print(('[starter_zone] Timed out loading greeter NPC anim dict: %s'):format(dict))
            return false
        end
        Wait(50)
    end

    return true
end

deleteGreeterPed = function()
    if greeterPed and DoesEntityExist(greeterPed) then
        DeleteEntity(greeterPed)
    end

    greeterPed = nil
    greeterAvailable = false
    greeterOpenedThisVisit = false
    greeterOpenedUi = false
end

deleteJobCounselorPed = function()
    if jobCounselorPed and DoesEntityExist(jobCounselorPed) then
        if GetResourceState('ox_target') == 'started' then
            pcall(function()
                exports.ox_target:removeLocalEntity(jobCounselorPed)
            end)
        end

        DeleteEntity(jobCounselorPed)
    end

    jobCounselorPed = nil
end

local function applyGreeterIdle()
    local greeter = Config.GreeterNpc
    if not greeter or not greeterPed or not DoesEntityExist(greeterPed) then return end

    ClearPedTasksImmediately(greeterPed)
    ClearPedSecondaryTask(greeterPed)

    if greeter.idleScenario then
        TaskStartScenarioInPlace(greeterPed, greeter.idleScenario, 0, true)
        return
    end

    if not greeter.anim or not requestAnimDict(greeter.anim.dict) then
        TaskStandStill(greeterPed, -1)
        return
    end

    TaskPlayAnim(
        greeterPed,
        greeter.anim.dict,
        greeter.anim.name,
        4.0,
        4.0,
        -1,
        greeter.anim.flag or 1,
        0.0,
        false,
        false,
        false
    )
end

local function setupGreeterPed(ped, coords)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityHeading(ped, coords.w or 0.0)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityProofs(ped, true, true, true, true, true, true, true, true)
    SetEntityCanBeDamaged(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedSuffersCriticalHits(ped, false)
    SetPedCanEvasiveDive(ped, false)
    SetPedCanBeTargetted(ped, false)
    SetPedKeepTask(ped, true)
    SetPedAlertness(ped, 0)
    SetPedSeeingRange(ped, 0.0)
    SetPedHearingRange(ped, 0.0)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    DisablePedPainAudio(ped, true)
    StopPedSpeaking(ped, true)
    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
end

local function spawnGreeterPed()
    local greeter = Config.GreeterNpc
    if not greeter or not greeter.enabled or greeterPed then return end

    local model = requestModel(greeter.model or 'a_m_y_business_02')
    if not model then return end

    local coords = greeter.coords
    greeterPed = CreatePed(0, model, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)

    if not DoesEntityExist(greeterPed) then
        greeterPed = nil
        return
    end

    setupGreeterPed(greeterPed, coords)
    applyGreeterIdle()
end

local function openJobCounselor()
    TriggerEvent('starter_zone:client:openJobs', true)
end

local function applyJobCounselorIdle()
    local counselor = Config.JobCounselor
    if not counselor or not jobCounselorPed or not DoesEntityExist(jobCounselorPed) then return end

    ClearPedTasksImmediately(jobCounselorPed)
    ClearPedSecondaryTask(jobCounselorPed)

    if counselor.idleScenario == 'PROP_HUMAN_SEAT_CHAIR' then
        local coords = counselor.coords
        TaskStartScenarioAtPosition(
            jobCounselorPed,
            counselor.idleScenario,
            coords.x,
            coords.y,
            coords.z,
            coords.w or 0.0,
            0,
            true,
            true
        )
    elseif counselor.idleScenario then
        TaskStartScenarioInPlace(jobCounselorPed, counselor.idleScenario, 0, true)
    else
        TaskStandStill(jobCounselorPed, -1)
    end
end

local function spawnJobCounselorPed()
    local counselor = Config.JobCounselor
    if not counselor or not counselor.enabled or jobCounselorPed then return end

    local model = requestModel(counselor.model or 'a_f_y_business_02')
    if not model then return end

    local coords = counselor.coords
    jobCounselorPed = CreatePed(0, model, coords.x, coords.y, coords.z, coords.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)

    if not DoesEntityExist(jobCounselorPed) then
        jobCounselorPed = nil
        return
    end

    setupGreeterPed(jobCounselorPed, coords)
    SetPedCanBeTargetted(jobCounselorPed, true)
    applyJobCounselorIdle()

    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(jobCounselorPed, {{
            label = counselor.targetLabel or 'Speak With Job Counselor',
            icon = 'fa-solid fa-briefcase',
            distance = 2.0,
            onSelect = openJobCounselor
        }})
    end
end

local function isConfiguredRideVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if not Config.BikeRide or type(Config.BikeRide.vehicles) ~= 'table' then return false end

    local model = GetEntityModel(vehicle)
    for _, vehicleModel in ipairs(Config.BikeRide.vehicles) do
        if model == joaat(vehicleModel) then
            return true
        end
    end

    return false
end

deleteStarterBlip = function()
    if starterBlip and DoesBlipExist(starterBlip) then
        RemoveBlip(starterBlip)
    end

    starterBlip = nil
end

deleteStarterVehicleBlip = function()
    if starterVehicleBlip and DoesBlipExist(starterVehicleBlip) then
        SetBlipRoute(starterVehicleBlip, false)
        RemoveBlip(starterVehicleBlip)
    end

    starterVehicleBlip = nil
    starterVehicleEntity = nil
end

local function ensureStarterBlip()
    local blipConfig = Config.StarterBlip
    if not blipConfig or not blipConfig.enabled or starterBlip then return end

    local coords = blipConfig.coords or vec3(Config.GreeterNpc.coords.x, Config.GreeterNpc.coords.y, Config.GreeterNpc.coords.z)
    starterBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(starterBlip, blipConfig.sprite or 280)
    SetBlipColour(starterBlip, blipConfig.color or 2)
    SetBlipScale(starterBlip, blipConfig.scale or 0.85)
    SetBlipAsShortRange(starterBlip, blipConfig.shortRange == true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipConfig.label or 'No Love Lost New Citizen Helper')
    EndTextCommandSetBlipName(starterBlip)
end

local function isSpawnPointClear(coords)
    if IsPositionOccupied(coords.x, coords.y, coords.z, 2.8, false, true, true, false, false, 0, false) then
        return false
    end

    local nearbyVehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 3.0, 0, 71)
    return nearbyVehicle == 0
end

local function findStarterVehicleSpawn()
    local pickup = Config.StarterVehiclePickup
    local base = pickup.coords
    local baseCoords = vec3(base.x, base.y, base.z)

    if isSpawnPointClear(baseCoords) then
        return base
    end

    local searchRadius = pickup.searchRadius or 18.0
    local searchStep = pickup.searchStep or 4.0
    local heading = base.w or 0.0

    for radius = searchStep, searchRadius, searchStep do
        for angle = 0, 315, 45 do
            local radians = math.rad(angle)
            local coords = vec3(
                base.x + math.cos(radians) * radius,
                base.y + math.sin(radians) * radius,
                base.z
            )

            local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
            if found then
                coords = vec3(coords.x, coords.y, groundZ)
            end

            if isSpawnPointClear(coords) then
                return vec4(coords.x, coords.y, coords.z, heading)
            end
        end
    end
end

local function createStarterVehicleBlip(vehicle, label)
    local blipConfig = Config.StarterVehiclePickup and Config.StarterVehiclePickup.blip or {}
    if not blipConfig.enabled then return end

    deleteStarterVehicleBlip()

    starterVehicleEntity = vehicle
    starterVehicleBlip = AddBlipForEntity(vehicle)
    SetBlipSprite(starterVehicleBlip, blipConfig.sprite or 225)
    SetBlipColour(starterVehicleBlip, blipConfig.color or 2)
    SetBlipScale(starterVehicleBlip, blipConfig.scale or 0.85)
    SetBlipAsShortRange(starterVehicleBlip, false)
    SetBlipRoute(starterVehicleBlip, blipConfig.route == true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or blipConfig.label or 'Your Starter Vehicle')
    EndTextCommandSetBlipName(starterVehicleBlip)
end

local function setStarterVehicleFuel(vehicle, amount)
    amount = tonumber(amount) or 25.0
    SetVehicleFuelLevel(vehicle, amount)

    local fuelResource = Config.StarterVehiclePickup and Config.StarterVehiclePickup.fuelResource
    if fuelResource and GetResourceState(fuelResource) == 'started' then
        pcall(function()
            exports[fuelResource]:SetFuel(vehicle, amount)
        end)
        pcall(function()
            exports[fuelResource]:SetVehicleFuel(vehicle, amount)
        end)
    end
end

local function spawnStarterVehicle(data)
    local pickup = Config.StarterVehiclePickup
    if not pickup or not pickup.spawnOnClaim then return end
    if not data or type(data.model) ~= 'string' or type(data.plate) ~= 'string' then return end

    local spawn = findStarterVehicleSpawn()
    if not spawn then
        return notify('Your starter vehicle could not be placed because the pickup area is blocked. Move nearby vehicles or open a Discord ticket for staff assistance.', 'error')
    end

    local model = requestModel(data.model)
    if not model then
        return notify('Your starter vehicle model could not be loaded. Open a Discord ticket and include the starter vehicle name so staff can check the configuration.', 'error')
    end

    local validated, message = lib.callback.await('starter_zone:validateStarterVehicleSpawn', false, {
        model = data.model,
        plate = data.plate
    })
    if not validated then
        SetModelAsNoLongerNeeded(model)
        return notify(message or 'Starter vehicle spawn was not authorized. Please reopen the starter menu or contact staff if this continues.', 'error')
    end

    local vehicle = CreateVehicle(model, spawn.x, spawn.y, spawn.z, spawn.w or 0.0, true, true)
    SetModelAsNoLongerNeeded(model)

    if not DoesEntityExist(vehicle) then
        return notify('Your starter vehicle could not be spawned at the pickup point. Move nearby vehicles or open a Discord ticket if the area is clear.', 'error')
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNumberPlateText(vehicle, data.plate)
    SetVehicleDirtLevel(vehicle, 0.0)
    setStarterVehicleFuel(vehicle, pickup.fuel or 25.0)
    SetVehicleEngineHealth(vehicle, pickup.engineHealth or 1000.0)
    SetVehicleBodyHealth(vehicle, pickup.bodyHealth or 1000.0)

    if pickup.spawnLocked then
        SetVehicleDoorsLocked(vehicle, 2)
        SetVehicleDoorsLockedForAllPlayers(vehicle, true)
        SetVehicleNeedsToBeHotwired(vehicle, false)
    end

    if pickup.keys and pickup.keys.enabled then
        local keyResource = pickup.keys.resource or 'wasabi_carlock'
        if pickup.keys.clientExport and GetResourceState(keyResource) == 'started' then
            pcall(function()
                exports[keyResource][pickup.keys.clientExport](data.plate)
            end)
        end

        if pickup.keys.clientEvent then
            TriggerEvent(pickup.keys.clientEvent, data.plate)
        end
    end

    TriggerServerEvent('starter_zone:server:starterVehicleSpawned', data.plate)
    createStarterVehicleBlip(vehicle, data.label or (pickup.blip and pickup.blip.label))
    notify(('Your starter vehicle is ready nearby. Plate: %s. Follow the vehicle blip and keep this plate for staff support if needed.'):format(data.plate), 'success')
end

local function openChecklist()
    openCitizenUi(getDefaultStarterUiTab())
end

local function openOxChecklist()
    local status = lib.callback.await('starter_zone:getStatus', false)
    if not status then return notify('Could not load your New Citizen Checklist. Please try again in a moment or open a Discord ticket if it continues.', 'error') end

    local options = {
        {
            title = ('%s: Identity Established'):format(taskPrefix(status.checks.identity)),
            description = 'Completed during multicharacter creation.',
            icon = 'user-check',
            disabled = true
        },
        {
            title = ('%s: Register Official ID'):format(taskPrefix(status.checks.id_card)),
            description = 'Register your official ID and 30-day driver license through cs_license.',
            icon = 'id-card',
            event = 'starter_zone:client:registerId'
        },
        {
            title = ('%s: Choose Starter Essentials'):format(taskPrefix(status.checks.starter_kit)),
            description = ('Choose %s starter items.'):format(status.starterKit and status.starterKit.maxChoices or 6),
            icon = 'box-open',
            event = 'starter_zone:client:openKitWarning'
        },
        {
            title = ('%s: Go to Job Center'):format(taskPrefix(status.checks.starter_job)),
            description = status.checks.starter_job and ('Current job: %s. You can return to the Job Center to change city jobs.'):format(status.job) or 'Go to the Job Center and speak with the counselor to get a job.',
            icon = 'briefcase',
            disabled = not status.checks.starter_job
        },
        {
            title = ('%s: Ride a Bike'):format(taskPrefix(status.checks.bike_ride)),
            description = ('%s / %s required on an approved bike.'):format(fmtMiles(status.bikeRideDistance), fmtMiles(status.requiredBikeRideDistance)),
            icon = 'bicycle',
            disabled = true
        },
        {
            title = ('%s: Save Money in Bank'):format(taskPrefix(status.checks.bank)),
            description = ('$%s / $%s required'):format(status.bank, status.requiredBank),
            icon = 'building-columns',
            disabled = true
        },
        {
            title = ('%s: Stay Active'):format(taskPrefix(status.checks.playtime)),
            description = ('%s / %s required'):format(fmtTime(status.playtime), fmtTime(status.requiredPlaytime)),
            icon = 'clock',
            disabled = true
        }
    }

    if status.canLeave then
        options[#options + 1] = {
            title = 'Clearance Complete',
            description = 'You are cleared to leave the city.',
            icon = 'circle-check',
            disabled = true
        }
    else
        options[#options + 1] = {
            title = 'Not Cleared Yet',
            description = 'Finish all required tasks before leaving.',
            icon = 'triangle-exclamation',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'starter_zone_checklist',
        title = 'No Love Lost Checklist',
        options = options
    })
    lib.showContext('starter_zone_checklist')
end

RegisterCommand(Config.Commands.menu, openChecklist, false)
RegisterNetEvent('starter_zone:client:openChecklist', openChecklist)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', markPlayerReady)
RegisterNetEvent('qbx_core:client:playerLoggedIn', markPlayerReady)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', markPlayerNotReady)
RegisterNetEvent('qbx_core:client:playerLoggedOut', markPlayerNotReady)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    CreateThread(function()
        Wait(1500)
        if hasLoadedPlayerData() then
            markPlayerReady()
        end
    end)
end)

RegisterNUICallback('close', function(_, cb)
    closeCitizenUi()
    greeterOpenedUi = false
    cb({ ok = true })
end)

RegisterNUICallback('ready', function(_, cb)
    if nuiOpen then
        sendCitizenUiPayload(currentUiTab, currentUiMode)
    end
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(data, cb)
    local ok = sendCitizenUiPayload(data and data.tab or 'checklist')
    cb({ ok = ok == true })
end)

RegisterNUICallback('registerId', function(_, cb)
    CreateThread(function()
        local ok, msg = lib.callback.await('starter_zone:claimId', false)
        notify(msg or (ok and 'Official ID registered and checklist updated.' or 'Could not register your official ID. Try again or open a Discord ticket if it continues.'), ok and 'success' or 'error')
        sendCitizenUiPayload('checklist')
        cb({ ok = ok == true, message = msg })
    end)
end)

RegisterNUICallback('claimKit', function(data, cb)
    CreateThread(function()
        local selected = {
            items = data and data.items or {},
            vehicle = data and data.vehicle or nil
        }
        local ok, msg, bonus, vehiclePending = lib.callback.await('starter_zone:claimKit', false, selected)
        if not (ok and vehiclePending) then
            notify(msg or (ok and 'Starter essentials claimed and added to your inventory.' or 'Could not claim your starter essentials. Check your inventory space and try again.'), ok and 'success' or 'error')
        end
        sendCitizenUiPayload('starter')
        cb({ ok = ok == true, message = msg, bonus = bonus })
    end)
end)

RegisterNUICallback('selectJob', function(data, cb)
    CreateThread(function()
        local jobName = data and data.job
        local ok, msg, waypoint = lib.callback.await('starter_zone:setStarterJob', false, jobName)
        notify(msg or (ok and 'Job selected and checklist updated.' or 'Could not select your job. Check your inventory space and try again.'), ok and 'success' or 'error')
        if ok then
            setStarterJobWaypoint(waypoint)
        end
        sendCitizenUiPayload('jobs', currentUiMode)
        cb({ ok = ok == true, message = msg })
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    deleteGreeterPed()
    deleteJobCounselorPed()
    deleteStarterBlip()
    deleteStarterVehicleBlip()
end)

RegisterNetEvent('starter_zone:client:spawnStarterVehicle', function(data)
    CreateThread(function()
        spawnStarterVehicle(data)
    end)
end)

RegisterNetEvent('starter_zone:client:registerId', function()
    local status = lib.callback.await('starter_zone:getStatus', false)
    if status and status.released then
        return notify('Your new citizen clearance is complete. Starter services are closed for this character.', 'inform')
    end

    local ok, msg = lib.callback.await('starter_zone:claimId', false)
    notify(msg or (ok and 'Official ID registered and checklist updated.' or 'Could not register your official ID. Try again or open a Discord ticket if it continues.'), ok and 'success' or 'error')
    openChecklist()
end)

RegisterNetEvent('starter_zone:client:openKitWarning', function()
    local status = lib.callback.await('starter_zone:getStatus', false)
    if status and status.released then
        return notify('Your new citizen clearance is complete. Starter services are closed for this character.', 'inform')
    end

    if status and status.starter and status.starter.claimedStarterKit then
        TriggerEvent('starter_zone:client:openKit')
        return
    end

    lib.registerContext({
        id = 'starter_zone_kit_warning',
        title = 'Before You Choose',
        menu = 'starter_zone_checklist',
        options = {
            {
                title = 'Starter Pack Rules',
                description = 'Your starter pack is based on your character profile, so male and female characters may see different item options. Stay within your starter budget and choice limit. Some starter items may not be obtainable again after onboarding.',
                icon = 'triangle-exclamation',
                disabled = true
            },
            {
                title = 'I Understand, View Starter Pack',
                description = 'Continue to the starter essentials selection.',
                icon = 'box-open',
                event = 'starter_zone:client:openKit'
            },
            {
                title = 'Go Back',
                description = 'Return to the new citizen checklist.',
                icon = 'arrow-left',
                onSelect = openOxChecklist
            }
        }
    })
    lib.showContext('starter_zone_kit_warning')
end)

RegisterNetEvent('starter_zone:client:openKit', function()
    local status = lib.callback.await('starter_zone:getStatus', false)
    if status and status.released then
        return notify('Your new citizen clearance is complete. Starter services are closed for this character.', 'inform')
    end

    local starterKit = status and status.starterKit
    if not starterKit then return notify('Could not load your starter essentials. Please reopen the menu or open a Discord ticket if it continues.', 'error') end

    local inputRows = {}
    for _, data in ipairs(starterKit.items or {}) do
        inputRows[#inputRows + 1] = {
            type = 'checkbox',
            label = ('%s ($%s each)'):format(data.label or data.item, data.cost or 0),
            checked = false
        }
    end

    local input = lib.inputDialog(('Choose Starter Essentials (%s max)'):format(starterKit.maxChoices or 6), inputRows)
    if not input then return end

    local selected = {}
    for index, checked in ipairs(input) do
        if checked then
            selected[#selected + 1] = {
                item = starterKit.items[index].item,
                quantity = 1
            }
        end
    end

    if #selected > (starterKit.maxChoices or 6) then
        return notify(('Your starter pack is limited to %s total selections. Remove an item before adding another.'):format(starterKit.maxChoices or 6), 'error')
    end

    local ok, msg = lib.callback.await('starter_zone:claimKit', false, {
        items = selected
    })
    notify(msg or (ok and 'Starter essentials claimed and added to your inventory.' or 'Could not claim your starter essentials. Check your inventory space and try again.'), ok and 'success' or 'error')
    openChecklist()
end)

RegisterNetEvent('starter_zone:client:openJobsWarning', function()
    TriggerEvent('starter_zone:client:openJobs')
end)

RegisterNetEvent('starter_zone:client:openJobs', function()
    openCitizenUi('jobs', 'jobcenter')
end)


local function isPointInsidePolygon(coords, points)
    if not points or #points < 3 then return true end

    local inside = false
    local j = #points

    for i = 1, #points do
        local xi, yi = points[i].x, points[i].y
        local xj, yj = points[j].x, points[j].y

        local intersects = ((yi > coords.y) ~= (yj > coords.y)) and
            (coords.x < (xj - xi) * (coords.y - yi) / ((yj - yi) + 0.000001) + xi)

        if intersects then inside = not inside end
        j = i
    end

    return inside
end

local function isSouthOfLine(coords, westPoint, eastPoint)
    if not westPoint or not eastPoint then return true end

    local lineY = westPoint.y + ((eastPoint.y - westPoint.y) * ((coords.x - westPoint.x) / ((eastPoint.x - westPoint.x) + 0.000001)))
    return coords.y <= lineY
end

local function isInsideStarterZone(coords)
    if Config.Zone.type == 'north_line' then
        local boundary = Config.Zone.northBoundary or {}
        return isSouthOfLine(coords, boundary.west, boundary.east)
    end

    if Config.Zone.type == 'polygon' then
        return isPointInsidePolygon(coords, Config.Zone.points)
    end

    return #(coords - Config.Zone.center) <= Config.Zone.radius
end

local function requestEntityControl(entity, timeout)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end

    NetworkRequestControlOfEntity(entity)
    local deadline = GetGameTimer() + (timeout or 500)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end

    return NetworkHasControlOfEntity(entity)
end

local function stopEntityMovement(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    if IsEntityAVehicle(entity) then
        SetVehicleForwardSpeed(entity, 0.0)
        SetVehicleHandbrake(entity, true)
    end
end

local function rubberbandBack(ped, coords, heading)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not coords then return end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local isDriver = vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped

    if isDriver and requestEntityControl(vehicle, 600) then
        FreezeEntityPosition(vehicle, true)
        stopEntityMovement(vehicle)
        SetEntityCoordsNoOffset(vehicle, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(vehicle, heading or GetEntityHeading(vehicle))
        SetVehicleOnGroundProperly(vehicle)
        Wait(100)
        stopEntityMovement(vehicle)
        FreezeEntityPosition(vehicle, false)
        SetVehicleHandbrake(vehicle, false)
        return
    end

    FreezeEntityPosition(ped, true)
    stopEntityMovement(ped)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, heading or 0.0)
    Wait(100)
    FreezeEntityPosition(ped, false)
end

local function drawText3d(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextCentre(1)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    if Config.Interactions.useTarget then return end

    while true do
        if not playerReady then
            Wait(1000)
        elseif not starterActive then
            Wait(1500)
        else
            local sleep = 1000
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            for key, point in pairs(Config.Interactions.points) do
                local dist = #(coords - point.coords)
                if dist <= Config.Interactions.markerDistance then
                    sleep = 0
                    DrawMarker(2, point.coords.x, point.coords.y, point.coords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.25, 0.25, 255, 255, 255, 150, false, true, 2, nil, nil, false)
                    if dist <= Config.Interactions.interactDistance then
                        drawText3d(point.coords + vec3(0, 0, 0.45), ('[E] %s'):format(point.label))
                        if IsControlJustPressed(0, 38) then
                            if key == 'idDesk' then
                                TriggerEvent('starter_zone:client:registerId')
                            elseif key == 'kitDesk' then
                                TriggerEvent('starter_zone:client:openKitWarning')
                            elseif key == 'jobDesk' then
                                notify('Jobs are handled at the Job Center. Speak with the counselor to get or change a job.', 'inform')
                            else
                                openChecklist()
                            end
                        end
                    end
                end
            end

            Wait(sleep)
        end
    end
end)

CreateThread(function()
    if not Config.Interactions.useTarget then return end
    waitUntilPlayerReady()

    if GetResourceState('ox_target') ~= 'started' then
        print('[starter_zone] Config.Interactions.useTarget is true but ox_target is not started.')
        return
    end

    for key, point in pairs(Config.Interactions.points) do
        exports.ox_target:addBoxZone({
            coords = point.coords,
            size = vec3(1.5, 1.5, 2.0),
            rotation = 0,
            debug = Config.Debug,
            options = {{
                label = point.label,
                icon = point.icon,
                onSelect = function()
                    if key == 'idDesk' then
                        TriggerEvent('starter_zone:client:registerId')
                    elseif key == 'kitDesk' then
                        TriggerEvent('starter_zone:client:openKitWarning')
                    elseif key == 'jobDesk' then
                        notify('Jobs are handled at the Job Center. Speak with the counselor to get or change a job.', 'inform')
                    else
                        openChecklist()
                    end
                end
            }}
        })
    end
end)

CreateThread(function()
    local greeter = Config.GreeterNpc
    local counselor = Config.JobCounselor
    local rideConfig = Config.BikeRide
    if (not greeter or not greeter.enabled)
        and (not counselor or not counselor.enabled)
        and (not Config.StarterBlip or not Config.StarterBlip.enabled)
        and (not rideConfig or not rideConfig.milesRequired)
        and (not Config.Zone or not Config.Zone.enabled)
        and (not Config.Interactions or not Config.Interactions.points)
    then
        return
    end

    while true do
            if not playerReady then
                greeterAvailable = false
                if greeterOpenedUi and nuiOpen then
                    closeCitizenUi()
                end
                deleteGreeterPed()
                deleteJobCounselorPed()
                deleteStarterBlip()
                Wait(1000)
        else
            local status = lib.callback.await('starter_zone:getStatus', false)
            starterActive = status and not status.released
            greeterAvailable = starterActive

            if starterActive then
                spawnGreeterPed()
                spawnJobCounselorPed()
                ensureStarterBlip()
            else
                if greeterOpenedUi and nuiOpen then
                    closeCitizenUi()
                end
                deleteGreeterPed()
                deleteJobCounselorPed()
                deleteStarterBlip()
            end

            Wait(starterActive and ((greeter and greeter.statusRefreshInterval) or 15000) or 60000)
        end
    end
end)

CreateThread(function()
    local greeter = Config.GreeterNpc
    if not greeter or not greeter.enabled then return end

    while true do
        local sleep = 1000
        if not playerReady then
            greeterOpenedThisVisit = false
            greeterOpenedUi = false
            Wait(sleep)
        elseif not starterActive then
            greeterOpenedThisVisit = false
            greeterOpenedUi = false
            Wait(1500)
        else
            if greeterAvailable and greeterPed and DoesEntityExist(greeterPed) then
                local playerPed = PlayerPedId()
                local playerCoords = GetEntityCoords(playerPed)
                local npcCoords = vec3(greeter.coords.x, greeter.coords.y, greeter.coords.z)
                local dist = #(playerCoords - npcCoords)

                if greeter.idleScenario then
                    if not IsPedUsingScenario(greeterPed, greeter.idleScenario) then
                        applyGreeterIdle()
                    end
                elseif greeter.anim and not IsEntityPlayingAnim(greeterPed, greeter.anim.dict, greeter.anim.name, 3) then
                    applyGreeterIdle()
                end

                if dist <= (greeter.autoOpenDistance or 3.0) then
                    sleep = 250
                    if not greeterOpenedThisVisit and not nuiOpen then
                        greeterOpenedThisVisit = true
                        openCitizenUi(getDefaultStarterUiTab())
                        greeterOpenedUi = nuiOpen
                    end
                elseif dist >= (greeter.autoCloseDistance or 4.5) then
                    if greeterOpenedUi and nuiOpen then
                        closeCitizenUi()
                    end

                    greeterOpenedThisVisit = false
                    greeterOpenedUi = false
                else
                    sleep = 500
                end
            end

            Wait(sleep)
        end
    end
end)

CreateThread(function()
    local rideConfig = Config.BikeRide
    if not rideConfig or not rideConfig.milesRequired then return end

    local pendingDistance = 0.0
    local lastCoords = nil
    local lastServerUpdate = GetGameTimer()
    local sampleInterval = rideConfig.clientSampleInterval or 1000
    local serverUpdateInterval = rideConfig.serverUpdateInterval or 10000

    while true do
        Wait(sampleInterval)

        if not playerReady or not starterActive then
            pendingDistance = 0.0
            lastCoords = nil
            goto continue
        end

        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= playerPed or not isConfiguredRideVehicle(vehicle) then
            lastCoords = nil
            goto continue
        end

        local coords = GetEntityCoords(playerPed)
        if rideConfig.trackOnlyInsideStarterZone and not isInsideStarterZone(coords) then
            lastCoords = nil
            goto continue
        end

        if lastCoords then
            local traveled = #(coords - lastCoords)
            if traveled > 0.25 and traveled < 150.0 then
                pendingDistance = pendingDistance + traveled
            end
        end
        lastCoords = coords

        if pendingDistance > 0.0 and GetGameTimer() - lastServerUpdate >= serverUpdateInterval then
            TriggerServerEvent('starter_zone:server:addBikeRideDistance', pendingDistance)
            pendingDistance = 0.0
            lastServerUpdate = GetGameTimer()

            if nuiOpen then
                sendCitizenUiPayload('checklist')
            end
        end

        ::continue::
    end
end)

CreateThread(function()
    while true do
        local sleep = 1500
        if not playerReady then
            Wait(sleep)
        elseif not starterActive then
            Wait(sleep)
        else
            if starterVehicleEntity and DoesEntityExist(starterVehicleEntity) then
                local playerPed = PlayerPedId()
                if GetVehiclePedIsIn(playerPed, false) == starterVehicleEntity and GetPedInVehicleSeat(starterVehicleEntity, -1) == playerPed then
                    deleteStarterVehicleBlip()
                else
                    sleep = 500
                end
            elseif starterVehicleBlip then
                deleteStarterVehicleBlip()
            end

            Wait(sleep)
        end
    end
end)

CreateThread(function()
    if not Config.Zone.enabled then return end
    while true do
        if not playerReady or not starterActive then
            Wait(1500)
        else
            Wait(Config.Zone.checkInterval)
            local ped = PlayerPedId()
            if not DoesEntityExist(ped) then goto continue end

            local coords = GetEntityCoords(ped)

            if isInsideStarterZone(coords) then
                insideZone = true
                lastSafeCoords = coords
                lastSafeHeading = GetEntityHeading(ped)
            else
                local canLeave, status = lib.callback.await('starter_zone:canLeave', false)
                if not canLeave then
                    local now = GetGameTimer()
                    if now - lastWarn > Config.Zone.warningCooldown then
                        lastWarn = now
                        notify('You are not cleared to leave the city yet. Complete your New Citizen Checklist, starter job, bank balance, and playtime requirements before leaving.', 'error')
                    end

                    local tp = Config.Zone.teleportBack
                    local backCoords = Config.Zone.rubberbandToLastSafe and lastSafeCoords or vec3(tp.x, tp.y, tp.z)
                    local backHeading = Config.Zone.rubberbandToLastSafe and lastSafeHeading or (tp.w or 0.0)

                    -- Instant rubberband back inside the border. No screen fade, so it feels like a boundary pushback.
                    rubberbandBack(ped, backCoords, backHeading)
                else
                    insideZone = false
                    if status and status.adminBypass and not status.tasksComplete then
                        goto continue
                    end

                    if status and not status.released and not releaseMarked then
                        releaseMarked = true
                        local ok, msg = lib.callback.await('starter_zone:markReleased', false)
                        notify(msg or (ok and 'New citizen clearance complete. You may now leave the city.' or 'Could not finalize your starter clearance. Try again or open a Discord ticket if it continues.'), ok and 'success' or 'error')
                        if nuiOpen then closeCitizenUi() end
                        deleteGreeterPed()
                        deleteStarterBlip()
                        starterActive = false
                        greeterAvailable = false
                    end
                end
            end

            ::continue::
        end
    end
end)

CreateThread(function()
    waitUntilPlayerReady()
    Wait(2500)
    local status = lib.callback.await('starter_zone:getStatus', false)
    if status and status.released then return end
    notify(('Use /%s to review your No Love Lost checklist, starter essentials, job assignment, and city departure requirements.'):format(Config.Commands.menu), 'inform')
end)
