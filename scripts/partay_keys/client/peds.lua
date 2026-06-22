-- [[ ParTay Keys - Service Peds & Garbage Collection ]] --

local spawnedPeds = {}
local spawnedBlips = {}
local spawnedLocksmithLocations = {}
local spawnedLocksmithZones = {}
local spawnedLocksmithSigns = {}
local spawnedLocksmithOrderPickups = {}
local collectingLocksmithOrderPickups = {}
local activeSetupPlacement = nil
local locksmithSignThreadActive = false
local setupPlacementHelpVisible = false
local setupPlacementHelpText = nil
local OpenLocksmithSetupMenu
local currentServiceMenuAllowsVehicles = false

local function TrimPlate(plate)
    return plate and tostring(plate):gsub('^%s*(.-)%s*$', '%1') or nil
end

local function GetVehicleDisplayName(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return locale('label_vehicle') end

    local label = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
    if not label or label == '' or label == 'NULL' then
        label = locale('label_vehicle')
    end

    return label
end

local function GetNearbyLocksmithVehicles()
    local ped = cache.ped or PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicles = {}

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local distance = #(coords - GetEntityCoords(vehicle))
            if distance <= 12.0 then
                vehicles[#vehicles + 1] = {
                    vehicle = vehicle,
                    plate = TrimPlate(GetVehicleNumberPlateText(vehicle)),
                    label = GetVehicleDisplayName(vehicle),
                    distance = distance
                }
            end
        end
    end

    table.sort(vehicles, function(a, b)
        return (a.distance or 999.0) < (b.distance or 999.0)
    end)

    return vehicles
end

local itemDescriptions = {
    basic_car_alarm = 'Entry-level alarm hardware for core theft and damage response.',
    car_alarm = 'Standard alarm package with balanced theft and panic response.',
    advanced_car_alarm = 'Premium alarm hardware prepared for expanded smart security features.',
    gps_tracker = 'Basic tracker hardware for wide-radius vehicle recovery.',
    standard_gps_tracker = 'Improved tracker hardware with tighter pings and better signal resolution.',
    advanced_gps_tracker = 'Premium tracker hardware prepared for expanded smart tracking features.',
    gps_tablet = 'Tablet receiver for viewing and managing installed GPS trackers.',
    signal_finder = 'Handheld scanner for finding hidden trackers on nearby vehicles.',
    lockpick = 'A simple entry tool for low-security vehicle locks.',
    wiring_kit = 'A bypass kit used during vehicle ignition work.',
    electronic_decoder = 'Decoder hardware used with a blank fob to clone vulnerable keys.',
    blank_key = 'Unprogrammed key fob stock for decoder work.',
    sale_contract = 'Paperwork used to transfer a stolen vehicle through a blackmarket sale.',
    basic_vehicle_key = 'Traditional key system with lock and unlock access only.',
    smart_vehicle_key = 'Remote fob system with expanded vehicle controls.',
    advanced_smart_vehicle_key = 'Enhanced smart key with remote engine support.',
    oled_vehicle_key = 'Premium display key system prepared for expanded remote features.'
}

local function GetItemDescription(itemName, fallback)
    return itemDescriptions[itemName] or fallback or 'Specialty item supplied by this service.'
end

local function BuildShopItems(items, priceOverrides)
    local payload = {}
    priceOverrides = priceOverrides or {}

    for _, shopItem in ipairs(items or {}) do
        local itemName = shopItem.item
        if itemName and itemName ~= '' then
            payload[#payload + 1] = {
                item = itemName,
                label = shopItem.label or itemName,
                price = tonumber(priceOverrides[itemName]) or tonumber(shopItem.price) or 0,
                description = shopItem.description or GetItemDescription(itemName),
                image = shopItem.image or ('assets/%s.png'):format(itemName)
            }
        end
    end

    return payload
end

local function GetLocksmithSelfServiceDefaults()
    return Config.PlayerJobDefaults
        and Config.PlayerJobDefaults.Locksmith
        and Config.PlayerJobDefaults.Locksmith.SelfService
        or {}
end

local function GetLocksmithPlayerRunConfig()
    return Config.PlayerJobs and Config.PlayerJobs.Locksmith or { Enabled = false }
end

local function GetLocksmithDefaultServiceFee(serviceAction)
    local fees = GetLocksmithSelfServiceDefaults().ServiceFees or {}
    if serviceAction == 'copy' then return tonumber(fees.Copy) or 0 end
    if serviceAction == 'recover' then return tonumber(fees.Recover) or 0 end
    if serviceAction == 'rekey' then return tonumber(fees.ReKey) or 0 end
    return 0
end

local function GetServicePedData()
    return lib.callback.await('partay_keys:server:GetServicePedData', false) or {}
end

local function BuildKeyTierOptions(priceOverrides)
    local options = {}
    priceOverrides = priceOverrides or {}

    for rank, tier in ipairs(Config.KeyTierOrder or {}) do
        local tierConfig = Config.KeyTiers and Config.KeyTiers[tier]
        if tierConfig then
            local itemName = tierConfig.Item
            options[#options + 1] = {
                tier = tier,
                rank = rank,
                label = tierConfig.UpgradeLabel or tierConfig.Label or tier,
                price = tonumber(priceOverrides[tier]) or tonumber(tierConfig.UpgradePrice) or 0,
                description = tierConfig.Description or GetItemDescription(itemName, 'Upgrade and re-key this vehicle to a new key system.'),
                image = itemName and ('assets/%s.png'):format(itemName) or nil
            }
        end
    end

    return options
end

local function BuildOwnedNearbyVehicles()
    local vehicles = GetNearbyLocksmithVehicles()
    local candidates = {}

    for _, data in ipairs(vehicles) do
        if data.plate and data.plate ~= '' then
            candidates[#candidates + 1] = {
                plate = data.plate,
                label = data.label,
                distance = data.distance or 0.0,
                netId = VehToNet(data.vehicle)
            }
        end
    end

    return lib.callback.await('partay_keys:server:GetLocksmithServiceVehicles', false, candidates) or {}
end

local function PlayConfiguredAnimation(animationKey, durationOverride)
    local anim = Animations and Animations[animationKey]
    if not anim or not anim.dict or not anim.name then
        Wait(durationOverride or 1000)
        return
    end

    local ped = cache.ped or PlayerPedId()
    lib.requestAnimDict(anim.dict, 1000)
    TaskPlayAnim(ped, anim.dict, anim.name, 4.0, 4.0, durationOverride or anim.duration or -1, anim.flags or 49, 0, false, false, false)
    Wait(math.max(500, tonumber(durationOverride or anim.duration) or 1000))
    ClearPedTasks(ped)
end

local function StartConfiguredAnimation(animationKey, ped)
    local anim = Animations and Animations[animationKey]
    if not anim or not anim.dict or not anim.name then return false end

    ped = ped or cache.ped or PlayerPedId()
    lib.requestAnimDict(anim.dict, 1000)
    TaskPlayAnim(ped, anim.dict, anim.name, 4.0, 4.0, -1, anim.flags or 49, 0, false, false, false)
    return true
end

local function PlayPedConfiguredAnimation(ped, animationKey, durationOverride)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    local anim = Animations and Animations[animationKey]
    local duration = math.max(500, tonumber(durationOverride or (anim and anim.duration)) or 1000)
    if not anim or not anim.dict or not anim.name then
        Wait(duration)
        return
    end

    lib.requestAnimDict(anim.dict, 1000)
    TaskPlayAnim(ped, anim.dict, anim.name, 4.0, 4.0, durationOverride or anim.duration or -1, anim.flags or 49, 0, false, false, false)
    Wait(duration)
    ClearPedTasks(ped)
end

local function MoveToVehicleBone(vehicle, boneName, timeoutMs)
    local ped = cache.ped or PlayerPedId()
    local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
    if boneIndex == -1 then return false end

    local coords = GetWorldPositionOfEntityBone(vehicle, boneIndex)
    TaskGoStraightToCoord(ped, coords.x, coords.y, coords.z, 1.0, timeoutMs or 2500, GetEntityHeading(vehicle), 0.25)

    local started = GetGameTimer()
    while GetGameTimer() - started < (timeoutMs or 2500) do
        if #(GetEntityCoords(ped) - coords) <= 1.0 then
            ClearPedTasks(ped)
            TaskTurnPedToFaceEntity(ped, vehicle, 600)
            Wait(650)
            return true
        end
        Wait(50)
    end

    ClearPedTasks(ped)
    return false
end

local function PlayLocksmithVehicleWork(data)
    if type(data) ~= 'table' then return false end

    local vehicle = tonumber(data.netId) and NetToVeh(tonumber(data.netId)) or 0
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        Notify(locale('label_locksmith'), locale('error_locksmith_vehicle_too_far'), 'error')
        return false
    end

    local workflow = GetLocksmithPlayerRunConfig().Workflow or {}
    local doorDuration = math.floor((tonumber(workflow.DoorWorkSeconds) or 3.5) * 1000)
    local needsDoorWork = false
    for _, service in ipairs(data.services or {}) do
        if service.action == 'rekey' or service.action == 'upgrade' then
            needsDoorWork = true
            break
        end
    end

    if not needsDoorWork then
        PartayKeysShowHandPropOnce('tablet', 2500)
        PlayConfiguredAnimation('TabletHold', 2500)
        return true
    end

    local doorTargets = {
        { bone = 'door_dside_f', index = 0 },
        { bone = 'door_pside_f', index = 1 },
        { bone = 'door_dside_r', index = 2 },
        { bone = 'door_pside_r', index = 3 }
    }

    local workedAnyDoor = false
    for _, target in ipairs(doorTargets) do
        if GetEntityBoneIndexByName(vehicle, target.bone) ~= -1 and MoveToVehicleBone(vehicle, target.bone, 2500) then
            workedAnyDoor = true
            SetVehicleDoorOpen(vehicle, target.index, false, false)
            PlayConfiguredAnimation('LocksmithDoorWork', doorDuration)
            SetVehicleDoorShut(vehicle, target.index, false)
        end
    end

    if not workedAnyDoor then
        PlayConfiguredAnimation('LocksmithDoorWork', doorDuration)
    end

    return true
end

local function OpenPartayServiceMenu(serviceType, defaultSection, forcedMode, sourceMode)
    local serviceConfig = serviceType == 'blackmarket' and (GetServicePedData().blackmarket or {}) or GetLocksmithPlayerRunConfig()
    if not serviceConfig then return end
    if serviceType ~= 'locksmith' and serviceConfig.enabled ~= true then return end
    if serviceType == 'locksmith' and serviceConfig.Enabled ~= true then return end
    local locksmithAccess = nil

    if serviceType == 'locksmith' then
        locksmithAccess = lib.callback.await('partay_keys:server:GetLocksmithAccess', false) or {}
        local playerRunEnabled = serviceConfig.Enabled == true
        local allowPublicRegister = defaultSection == 'shop'
            and sourceMode == 'register'
            and playerRunEnabled
            and forcedMode ~= 'owner'
            and locksmithAccess.isEmployee ~= true
            and locksmithAccess.reason ~= 'shop_closed'

        if forcedMode ~= 'owner' and locksmithAccess.allowed ~= true and not allowPublicRegister then
            local messageKey = locksmithAccess.reason == 'staff_online' and 'error_locksmith_staff_online'
                or locksmithAccess.reason == 'staff_required' and 'error_locksmith_staff_required'
                or 'error_locksmith_unavailable'
            Notify(locale('label_locksmith'), locale(messageKey), 'error')
            return
        end
    end

    if PartayKeysIsActiveItemUi and PartayKeysIsActiveItemUi() then
        PartayKeysCloseItemUi()
    end

    currentServiceMenuAllowsVehicles = false

    local payload = {
        action = 'openServiceMenu',
        token = PartayKeysCreateNuiToken('service_menu'),
        service = serviceType,
        defaultSection = defaultSection or 'shop',
        sourceMode = sourceMode
    }

    if serviceType == 'blackmarket' then
        payload.title = locale('ui_blackmarket_title')
        payload.subtitle = locale('ui_blackmarket_subtitle')
        payload.shopTitle = locale('ui_blackmarket_shop_title')
        payload.shopDescription = locale('ui_blackmarket_shop_description')
        payload.currencyLabel = locale('label_dirty_money')
        payload.paymentOptions = {
            { value = 'black_money', label = locale('label_dirty_money') }
        }
        payload.shopItems = BuildShopItems(serviceConfig.items)
    else
        local activePrices = lib.callback.await('partay_keys:server:GetLocksmithPrices', false) or {}
        local playerRunEnabled = serviceConfig.Enabled == true
        local allowVehicleServices = sourceMode == 'register'
            or sourceMode == 'employee_tablet'
            or sourceMode == 'owner_tablet'
        currentServiceMenuAllowsVehicles = allowVehicleServices
        local isRegisterCustomer = defaultSection == 'shop'
            and sourceMode == 'register'
            and playerRunEnabled
            and locksmithAccess.isEmployee ~= true
            and forcedMode ~= 'owner'
            and locksmithAccess.reason ~= 'shop_closed'
        local isPedShop = defaultSection == 'shop' and sourceMode == 'ped'
        local selfServiceDefaults = GetLocksmithSelfServiceDefaults()
        local allowShop = selfServiceDefaults.EnableShop ~= false and (isRegisterCustomer or isPedShop)

        payload.title = locale('ui_locksmith_title')
        payload.subtitle = locale('ui_locksmith_subtitle')
        payload.shopTitle = locale('ui_locksmith_shop_title')
        payload.shopDescription = locale('ui_locksmith_shop_description')
        payload.currencyLabel = locale('label_cash_bank')
        payload.employeeMode = locksmithAccess and locksmithAccess.isEmployee == true
        payload.ownerMode = forcedMode == 'owner'
        payload.customerOrderMode = isRegisterCustomer
        payload.paymentOptions = {
            { value = 'cash', label = locale('label_cash') },
            { value = 'bank', label = locale('label_bank') }
        }
        payload.shopEnabled = allowShop
        payload.shopItems = allowShop and BuildShopItems(selfServiceDefaults.Items, activePrices.shop) or {}
        payload.vehicleServicesEnabled = allowVehicleServices
        payload.vehicles = allowVehicleServices and BuildOwnedNearbyVehicles() or {}
        payload.activeJob = allowVehicleServices and payload.employeeMode and lib.callback.await('partay_keys:server:GetActiveLocksmithJob', false) or nil
        if sourceMode == 'stock' and locksmithAccess and locksmithAccess.isOwner == true then
            payload.ownerMode = true
        end
        if sourceMode == 'stock' then
            payload.businessDefaultTab = 'stock'
            payload.stockMode = true
        end
        payload.businessData = payload.ownerMode and lib.callback.await('partay_keys:server:GetLocksmithBusinessData', false)
            or payload.employeeMode and lib.callback.await('partay_keys:server:GetLocksmithEmployeeBusinessData', false)
            or nil
        payload.serviceFees = allowVehicleServices and {
            copy = activePrices.services and tonumber(activePrices.services.copy) or GetLocksmithDefaultServiceFee('copy'),
            recover = activePrices.services and tonumber(activePrices.services.recover) or GetLocksmithDefaultServiceFee('recover'),
            rekey = activePrices.services and tonumber(activePrices.services.rekey) or GetLocksmithDefaultServiceFee('rekey')
        } or {}
        payload.keyTiers = allowVehicleServices and selfServiceDefaults.EnableKeyTierServices ~= false and BuildKeyTierOptions(activePrices.tiers) or {}
    end

    PartayKeysShowHandProp('tablet')
    PartayKeysSetActiveItemUi('service_menu')
    PartayKeysOpenNui(false, true)
    SendNUIMessage(payload)
end

local function OpenLocksmithWorkbenchMenu()
    local business = lib.callback.await('partay_keys:server:GetLocksmithWorkbenchData', false) or {}
    if business.allowed ~= true then
        Notify(locale('label_locksmith'), locale(business.reason or 'error_locksmith_workbench_unavailable'), 'error')
        return
    end

    if PartayKeysIsActiveItemUi and PartayKeysIsActiveItemUi() then
        PartayKeysCloseItemUi()
    end

    currentServiceMenuAllowsVehicles = false

    PartayKeysShowHandProp('tablet')
    PartayKeysSetActiveItemUi('service_menu')
    PartayKeysOpenNui(false, true)
    SendNUIMessage({
        action = 'openServiceMenu',
        token = PartayKeysCreateNuiToken('service_menu'),
        service = 'locksmith',
        title = locale('ui_locksmith_workstation_title'),
        subtitle = locale('ui_locksmith_workstation_subtitle'),
        defaultSection = 'business',
        workstationMode = true,
        ownerMode = true,
        employeeMode = false,
        shopEnabled = false,
        shopItems = {},
        vehicles = {},
        serviceFees = {},
        keyTiers = {},
        paymentOptions = {},
        businessData = business
    })
end

local function MakeLocksmithGaragePlate(prefix)
    prefix = tostring(prefix or 'LOCK'):upper():gsub('[^A-Z0-9]', ''):sub(1, 4)
    if prefix == '' then prefix = 'LOCK' end
    return ('%s%04d'):format(prefix, math.random(0, 9999))
end

local function SpawnLocksmithGarageVehicle(vehicleConfig, garageData)
    if type(vehicleConfig) ~= 'table' or not vehicleConfig.model then return end
    local spawn = garageData and garageData.spawn
    if not spawn then
        Notify(locale('label_locksmith'), locale('error_locksmith_garage_spawn_missing'), 'error')
        return
    end

    local model = vehicleConfig.model
    local modelHash = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelValid(modelHash) or not IsModelInCdimage(modelHash) then
        Notify(locale('label_locksmith'), locale('error_locksmith_garage_vehicle_invalid'), 'error')
        return
    end

    lib.requestModel(modelHash, 5000)
    local vehicle = CreateVehicle(modelHash, spawn.x, spawn.y, spawn.z, spawn.w or 0.0, true, false)
    if not vehicle or vehicle == 0 then
        Notify(locale('label_locksmith'), locale('error_locksmith_garage_spawn_failed'), 'error')
        return
    end

    local plate = MakeLocksmithGaragePlate(garageData.platePrefix)
    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleDoorsLocked(vehicle, 1)
    SetModelAsNoLongerNeeded(modelHash)

    local netId = VehToNet(vehicle)
    SetNetworkIdCanMigrate(netId, true)
    TriggerServerEvent('partay_keys:server:RegisterLocksmithGarageVehicle', netId, vehicleConfig.model, vehicleConfig.label, plate)
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
end

local function StoreLocksmithGarageVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        local coords = GetEntityCoords(ped)
        vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 8.0, 0, 70)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        Notify(locale('label_locksmith'), locale('error_locksmith_garage_vehicle_missing'), 'error')
        return
    end

    TriggerServerEvent('partay_keys:server:StoreLocksmithGarageVehicle', VehToNet(vehicle))
end

local function OpenLocksmithGarageMenu()
    local garageData = lib.callback.await('partay_keys:server:GetLocksmithGarageData', false) or {}
    if garageData.allowed ~= true then
        Notify(locale('label_locksmith'), locale(garageData.reason or 'error_locksmith_garage_unavailable'), 'error')
        return
    end

    local options = {}
    if garageData.mode == 'standalone' then
        for _, vehicle in ipairs(garageData.vehicles or {}) do
            options[#options + 1] = {
                title = vehicle.label or vehicle.model or locale('label_locksmith_garage_vehicle'),
                description = vehicle.model and tostring(vehicle.model) or nil,
                icon = 'car',
                onSelect = function()
                    SpawnLocksmithGarageVehicle(vehicle, garageData)
                end
            }
        end

        options[#options + 1] = {
            title = locale('label_locksmith_garage_store'),
            description = locale('info_locksmith_garage_store'),
            icon = 'warehouse',
            onSelect = StoreLocksmithGarageVehicle
        }
    else
        options[#options + 1] = {
            title = locale('label_locksmith_garage_provider'),
            description = locale('info_locksmith_garage_provider', {
                provider = garageData.provider or 'none',
                name = garageData.providerGarageName or 'partay_locksmith',
                type = garageData.providerGarageType or 'job'
            }),
            icon = 'warehouse',
            disabled = true
        }
    end

    lib.registerContext({
        id = 'partay_locksmith_garage_menu',
        title = locale('label_locksmith_garage'),
        options = options
    })
    lib.showContext('partay_locksmith_garage_menu')
end

local function OpenLocksmithManagementPoint()
    local business = lib.callback.await('partay_keys:server:GetLocksmithBusinessData', false) or {}
    if business.allowed ~= true then
        Notify(locale('label_locksmith'), locale('error_locksmith_owner_required'), 'error')
        return
    end

    OpenPartayServiceMenu('locksmith', 'business', 'owner', 'management')
end

RegisterCommand(GetLocksmithPlayerRunConfig().EmployeeTabletCommand or 'locksmithtablet', function()
    local access = lib.callback.await('partay_keys:server:GetLocksmithAccess', false) or {}
    if access.isEmployee ~= true then
        Notify(locale('label_locksmith'), locale('error_locksmith_employee_required'), 'error')
        return
    end

    OpenPartayServiceMenu('locksmith', 'vehicles', nil, 'employee_tablet')
end, false)

local appointmentCommand = GetLocksmithPlayerRunConfig().Appointments
    and GetLocksmithPlayerRunConfig().Appointments.Command
    or 'locksmithrequest'

RegisterCommand(appointmentCommand, function()
    local appointments = GetLocksmithPlayerRunConfig().Appointments

    if not appointments or appointments.Enabled == false then
        Notify(locale('label_locksmith'), locale('error_locksmith_appointments_unavailable'), 'error')
        return
    end

    local input = lib.inputDialog(locale('label_locksmith'), {
        { type = 'input', label = locale('input_plate'), description = locale('input_appointment_plate_description'), required = false },
        { type = 'input', label = locale('input_appointment_phone'), description = locale('input_appointment_phone_description'), required = false },
        { type = 'input', label = locale('input_appointment_date'), description = locale('input_appointment_date_description'), required = false },
        { type = 'input', label = locale('input_appointment_time'), description = locale('input_appointment_time_description'), required = false },
        { type = 'textarea', label = locale('input_request_notes'), description = locale('input_appointment_notes_description'), required = false, max = 255 }
    })
    if not input then return end

    TriggerServerEvent('partay_keys:server:RequestLocksmithAppointment', input[1], input[5], {
        phone = input[2],
        date = input[3],
        time = input[4]
    })
end, false)

local setupAdminCommand = Config.LocksmithSetupAdminCommand or 'locksmithadmin'
local setupOwnerCommand = Config.LocksmithSetupOwnerCommand or 'locksmithowner'
local activeLocksmithSetupMode = 'admin'

local function StopLocksmithSetupPlacement()
    if activeSetupPlacement and activeSetupPlacement.object and DoesEntityExist(activeSetupPlacement.object) then
        DeleteEntity(activeSetupPlacement.object)
    end

    if activeSetupPlacement and activeSetupPlacement.selectedEntity and DoesEntityExist(activeSetupPlacement.selectedEntity) then
        SetEntityDrawOutline(activeSetupPlacement.selectedEntity, false)
    end

    activeSetupPlacement = nil
    if setupPlacementHelpVisible and lib and lib.hideTextUI then
        lib.hideTextUI()
    end
    setupPlacementHelpVisible = false
    setupPlacementHelpText = nil
end

local function ShowLocksmithSetupPlacementHelp(text)
    text = text or locale('info_locksmith_setup_place_controls')
    if lib and lib.showTextUI then
        if setupPlacementHelpVisible and setupPlacementHelpText ~= text and lib.hideTextUI then
            lib.hideTextUI()
            setupPlacementHelpVisible = false
        end
        if not setupPlacementHelpVisible then
            lib.showTextUI(text)
            setupPlacementHelpVisible = true
            setupPlacementHelpText = text
        end
        return
    end

    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, 1)
end

local function DrawLocksmithRouteMarker(coords, r, g, b, labelScale)
    if not coords then return end
    DrawMarker(2, coords.x, coords.y, coords.z + 0.22, 0.0, 0.0, 0.0, 0.0, 0.0, coords.w or 0.0, labelScale or 0.3, labelScale or 0.3, labelScale or 0.3, r, g, b, 190, false, true, 2, false, nil, nil, false)
end

local function DrawLocksmithRouteLine(a, b, r, g, bl)
    if not a or not b then return end
    DrawLine(a.x, a.y, a.z + 0.15, b.x, b.y, b.z + 0.15, r, g, bl, 210)
end

local function FindLocksmithSetupPoint(setupData, locationName, pointType)
    for _, location in ipairs((setupData and setupData.locations) or {}) do
        if location.locationName == locationName and location.type == pointType then
            return location
        end
    end
    return nil
end

local function GetLocksmithRoutePreview(locationName, pointType)
    local setupData = lib.callback.await('partay_keys:server:GetLocksmithSetupData', false, activeLocksmithSetupMode) or {}
    local startPoint = FindLocksmithSetupPoint(setupData, locationName, pointType)
    local routeSource = startPoint
    local endPoint = nil
    local endCoords = nil

    if pointType == 'delivery_spawn' then
        endPoint = FindLocksmithSetupPoint(setupData, locationName, 'delivery_dropoff')
    elseif pointType == 'delivery_dropoff' then
        endPoint = startPoint
        startPoint = FindLocksmithSetupPoint(setupData, locationName, 'delivery_spawn')
    end

    local route = {}
    local savedRoute = routeSource and routeSource.stockSettings and routeSource.stockSettings.route
    if type(savedRoute) == 'table' then
        for _, point in ipairs(savedRoute) do
            local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
            if x and y and z then
                route[#route + 1] = { x = x, y = y, z = z, w = tonumber(point.w) or 0.0 }
            end
        end
    end

    local savedEnd = routeSource and routeSource.stockSettings and routeSource.stockSettings.routeEnd
    if type(savedEnd) == 'table' then
        local x, y, z = tonumber(savedEnd.x), tonumber(savedEnd.y), tonumber(savedEnd.z)
        if x and y and z then
            endCoords = { x = x, y = y, z = z, w = tonumber(savedEnd.w) or 0.0 }
        end
    end

    return {
        startCoords = startPoint and startPoint.coords or nil,
        endCoords = endCoords or (endPoint and endPoint.coords or nil),
        route = route
    }
end

local function GetLocksmithRouteHelpText(pointType)
    local key = ('info_locksmith_setup_route_%s'):format(tostring(pointType or ''):lower())
    local routeText = locale(key)
    if not routeText or routeText == key then
        routeText = locale('info_locksmith_setup_route_generic')
    end
    local controlsKey = 'info_locksmith_setup_route_controls'
    local controlsText = locale(controlsKey)
    if not controlsText or controlsText == controlsKey then
        controlsText = '%{route} Green=start, yellow=saved route, white=current, red=end. [E/Enter] Add waypoint  |  [G] Set end point  |  [Backspace] Finish'
    end
    return (controlsText:gsub('%%{route}', routeText))
end

local function DrawLocksmithRoutePreview(preview, candidate)
    if type(preview) ~= 'table' then return end

    local previous = preview.startCoords
    DrawLocksmithRouteMarker(preview.startCoords, 52, 211, 153, 0.36)

    for _, point in ipairs(preview.route or {}) do
        DrawLocksmithRouteMarker(point, 248, 201, 113, 0.28)
        DrawLocksmithRouteLine(previous, point, 248, 201, 113)
        previous = point
    end

    if candidate then
        DrawLocksmithRouteMarker(candidate, 255, 255, 255, 0.32)
        DrawLocksmithRouteLine(previous, candidate, 255, 255, 255)
        previous = candidate
    end

    DrawLocksmithRouteMarker(preview.endCoords, 248, 113, 113, 0.36)
    DrawLocksmithRouteLine(previous, preview.endCoords, 248, 113, 113)
end

local function DrawLocksmithPlacementRing(center, radius, zOffset, r, g, b, axis)
    if not center then return end

    local previous = nil
    local segments = 40
    for i = 0, segments do
        local angle = (i / segments) * math.pi * 2.0
        local x, y, z = center.x, center.y, center.z + zOffset

        if axis == 'x' then
            y = y + (math.cos(angle) * radius)
            z = z + (math.sin(angle) * radius)
        elseif axis == 'y' then
            x = x + (math.cos(angle) * radius)
            z = z + (math.sin(angle) * radius)
        else
            x = x + (math.cos(angle) * radius)
            y = y + (math.sin(angle) * radius)
        end

        if previous then
            DrawLine(previous.x, previous.y, previous.z, x, y, z, r, g, b, 190)
        end

        previous = vector3(x, y, z)
    end
end

local function DrawLocksmithPlacementAxis(startCoords, direction, length, r, g, b)
    local finish = startCoords + (direction * length)
    DrawLine(startCoords.x, startCoords.y, startCoords.z, finish.x, finish.y, finish.z, r, g, b, 230)
    DrawMarker(2, finish.x, finish.y, finish.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.13, 0.13, 0.13, r, g, b, 210, false, true, 2, false, nil, nil, false)
end

local function DrawLocksmithPlacementGizmo(coords, heading)
    if not coords then return end

    local center = vector3(coords.x, coords.y, coords.z + 0.45)
    local radians = math.rad(heading or 0.0)
    local forward = vector3(-math.sin(radians), math.cos(radians), 0.0)
    local right = vector3(math.cos(radians), math.sin(radians), 0.0)
    local up = vector3(0.0, 0.0, 1.0)

    DrawLocksmithPlacementAxis(center, forward, 0.85, 52, 211, 153)
    DrawLocksmithPlacementAxis(center, right, 0.85, 88, 214, 255)
    DrawLocksmithPlacementAxis(center, up, 0.65, 248, 201, 113)
    DrawLocksmithPlacementRing(center, 0.62, 0.0, 248, 201, 113, 'z')
    DrawLocksmithPlacementRing(center, 0.48, 0.0, 88, 214, 255, 'x')
end

local function SaveLocksmithSetupPlacement()
    if not activeSetupPlacement then return end

    local entity = activeSetupPlacement.object
    if (not entity or entity == 0 or not DoesEntityExist(entity)) and activeSetupPlacement.selectedEntity and DoesEntityExist(activeSetupPlacement.selectedEntity) then
        entity = activeSetupPlacement.selectedEntity
    end

    local finalCoords = entity and DoesEntityExist(entity) and GetEntityCoords(entity) or activeSetupPlacement.coords
    local finalHeading = entity and DoesEntityExist(entity) and GetEntityHeading(entity) or activeSetupPlacement.heading
    local finalZ = finalCoords.z
    if activeSetupPlacement.isPedPoint then
        finalZ = finalZ + 1.0
    end

    TriggerServerEvent('partay_keys:server:SaveLocksmithSetupPoint', {
        locationName = activeSetupPlacement.locationName,
        shopType = activeSetupPlacement.shopType,
        jobName = activeSetupPlacement.jobName,
        pointType = activeSetupPlacement.pointType,
        setupMode = activeLocksmithSetupMode,
        spawnProp = activeSetupPlacement.spawnProp,
        coords = {
            x = finalCoords.x,
            y = finalCoords.y,
            z = finalZ,
            w = finalHeading
        }
    })
end

local function StartLocksmithObjectGizmoPlacement(object)
    if not object or object == 0 or not DoesEntityExist(object) then return false end
    if GetResourceState('object_gizmo') ~= 'started' then return false end

    local placement = activeSetupPlacement
    local cancelled = false
    local finished = false

    ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_gizmo_controls'))

    CreateThread(function()
        while activeSetupPlacement == placement and not finished do
            DisableControlAction(0, 177, true)
            DisableControlAction(0, 202, true)

            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 202) then
                cancelled = true
                finished = true
                StopLocksmithSetupPlacement()
                Wait(150)
                OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                return
            end

            ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_gizmo_controls'))
            Wait(0)
        end
    end)

    local ok, result = pcall(function()
        return exports['object_gizmo']:useGizmo(object)
    end)
    finished = true

    if cancelled or activeSetupPlacement ~= placement then
        return true
    end

    if not ok then
        if Config.DebugMode then
            print(('[ParTay Keys Debug] object_gizmo placement failed, using fallback controls: %s'):format(tostring(result)))
        end
        return false
    end

    if result == false then
        StopLocksmithSetupPlacement()
        Wait(150)
        OpenLocksmithSetupMenu(activeLocksmithSetupMode)
        return true
    end

    SaveLocksmithSetupPlacement()
    StopLocksmithSetupPlacement()
    Wait(250)
    OpenLocksmithSetupMenu(activeLocksmithSetupMode)
    return true
end

local function RotationToDirection(rotation)
    local adjustedRotation = {
        x = math.rad(rotation.x),
        y = math.rad(rotation.y),
        z = math.rad(rotation.z)
    }

    return vector3(
        -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.sin(adjustedRotation.x)
    )
end

local function RaycastLocksmithSetupProp(maxDistance)
    local cameraCoords = GetGameplayCamCoord()
    local direction = RotationToDirection(GetGameplayCamRot(2))
    local destination = cameraCoords + (direction * (tonumber(maxDistance) or 8.0))
    local rayHandle = StartShapeTestRay(
        cameraCoords.x, cameraCoords.y, cameraCoords.z,
        destination.x, destination.y, destination.z,
        -1,
        PlayerPedId(),
        0
    )
    local _, hit, endCoords, _, entity = GetShapeTestResult(rayHandle)
    return hit == 1, endCoords, entity
end

local function IsSelectableLocksmithSetupProp(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if entity == PlayerPedId() then return false end
    if IsEntityAPed(entity) or IsEntityAVehicle(entity) then return false end
    return true
end

local function StartLocksmithMloPropSelection()
    ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_select_prop_controls'))

    CreateThread(function()
        while activeSetupPlacement and activeSetupPlacement.spawnProp == false do
            local hit, endCoords, entity = RaycastLocksmithSetupProp(10.0)
            local selected = IsSelectableLocksmithSetupProp(entity) and entity or nil

            if activeSetupPlacement.selectedEntity and activeSetupPlacement.selectedEntity ~= selected and DoesEntityExist(activeSetupPlacement.selectedEntity) then
                SetEntityDrawOutline(activeSetupPlacement.selectedEntity, false)
            end

            activeSetupPlacement.selectedEntity = selected
            if selected then
                SetEntityDrawOutline(selected, true)
                local selectedCoords = GetEntityCoords(selected)
                activeSetupPlacement.coords = selectedCoords
                activeSetupPlacement.heading = GetEntityHeading(selected)
                DrawMarker(2, selectedCoords.x, selectedCoords.y, selectedCoords.z + 0.45, 0.0, 0.0, 0.0, 0.0, 0.0, activeSetupPlacement.heading, 0.32, 0.32, 0.32, 88, 214, 255, 185, false, true, 2, false, nil, nil, false)
            elseif hit and endCoords then
                DrawMarker(2, endCoords.x, endCoords.y, endCoords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.24, 0.24, 0.24, 248, 113, 113, 155, false, true, 2, false, nil, nil, false)
            end

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            if IsControlJustPressed(0, 38) or IsControlJustPressed(0, 191) then
                if not activeSetupPlacement.selectedEntity then
                    Notify(locale('label_locksmith'), locale('error_locksmith_setup_no_prop_selected'), 'error')
                else
                    SaveLocksmithSetupPlacement()
                    StopLocksmithSetupPlacement()
                    Wait(250)
                    OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                    return
                end
            elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 202) then
                StopLocksmithSetupPlacement()
                Wait(150)
                OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                return
            end

            ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_select_prop_controls'))
            Wait(0)
        end
    end)
end

local function StartLocksmithStandSpotPlacement(data)
    data = type(data) == 'table' and data or {}
    local locationName = tostring(data.locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    local pointType = tostring(data.pointType or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    local shopType = tostring(data.shopType or 'player_owned'):lower():gsub('^%s*(.-)%s*$', '%1')
    local jobName = tostring(data.jobName or ''):gsub('^%s*(.-)%s*$', '%1')
    local stockMethod = tostring(data.stockMethod or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' or pointType == '' then
        Notify(locale('label_locksmith'), locale('error_locksmith_setup_invalid_location'), 'error')
        return
    end

    SendNUIMessage({ action = 'closeUI' })
    PartayKeysCloseNui(true)
    ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_stand_spot_controls'))

    CreateThread(function()
        while true do
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            DrawMarker(2, coords.x, coords.y, coords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, GetEntityHeading(ped), 0.32, 0.32, 0.32, 88, 214, 255, 185, false, true, 2, false, nil, nil, false)

            if IsControlJustPressed(0, 38) or IsControlJustPressed(0, 191) then
                TriggerServerEvent('partay_keys:server:SaveLocksmithSetupStandSpot', {
                    locationName = locationName,
                    pointType = pointType,
                    setupMode = activeLocksmithSetupMode,
                    coords = {
                        x = coords.x,
                        y = coords.y,
                        z = coords.z,
                        w = GetEntityHeading(ped)
                    }
                })
                if setupPlacementHelpVisible and lib and lib.hideTextUI then
                    lib.hideTextUI()
                end
                setupPlacementHelpVisible = false
                Wait(250)
                OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                return
            elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 202) then
                if setupPlacementHelpVisible and lib and lib.hideTextUI then
                    lib.hideTextUI()
                end
                setupPlacementHelpVisible = false
                Wait(150)
                OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                return
            end

            ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_stand_spot_controls'))
            Wait(0)
        end
    end)
end

local function StartLocksmithRoutePointPlacement(data)
    data = type(data) == 'table' and data or {}
    local locationName = tostring(data.locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    local pointType = tostring(data.pointType or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' or pointType == '' then
        Notify(locale('label_locksmith'), locale('error_locksmith_setup_invalid_location'), 'error')
        return
    end

    SendNUIMessage({ action = 'closeUI' })
    PartayKeysCloseNui(true)
    local routeHelp = GetLocksmithRouteHelpText(pointType)
    ShowLocksmithSetupPlacementHelp(routeHelp)
    local preview = GetLocksmithRoutePreview(locationName, pointType)

    CreateThread(function()
        while true do
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local candidate = {
                x = coords.x,
                y = coords.y,
                z = coords.z,
                w = GetEntityHeading(ped)
            }
            DrawLocksmithRoutePreview(preview, candidate)

            if IsControlJustPressed(0, 38) or IsControlJustPressed(0, 191) then
                TriggerServerEvent('partay_keys:server:AddLocksmithSetupRoutePoint', {
                    locationName = locationName,
                    pointType = pointType,
                    setupMode = activeLocksmithSetupMode,
                    coords = candidate
                })
                preview.route = preview.route or {}
                preview.route[#preview.route + 1] = candidate
                Wait(250)
            elseif IsControlJustPressed(0, 47) then
                TriggerServerEvent('partay_keys:server:SetLocksmithSetupRouteEndPoint', {
                    locationName = locationName,
                    shopType = shopType,
                    jobName = jobName,
                    stockMethod = stockMethod,
                    pointType = pointType,
                    setupMode = activeLocksmithSetupMode,
                    coords = candidate
                })
                preview.endCoords = candidate
                Wait(250)
            elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 202) then
                if setupPlacementHelpVisible and lib and lib.hideTextUI then
                    lib.hideTextUI()
                end
                setupPlacementHelpVisible = false
                Wait(150)
                OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                return
            end

            ShowLocksmithSetupPlacementHelp(routeHelp)
            Wait(0)
        end
    end)
end

OpenLocksmithSetupMenu = function(mode)
    mode = tostring(mode or activeLocksmithSetupMode or 'admin'):lower()
    if mode ~= 'owner' then mode = 'admin' end
    activeLocksmithSetupMode = mode

    local setupData = lib.callback.await('partay_keys:server:GetLocksmithSetupData', false, mode) or {}
    if setupData.allowed ~= true then
        Notify(locale('label_locksmith'), locale('error_locksmith_setup_no_permission'), 'error')
        return
    end

    if PartayKeysIsActiveItemUi and PartayKeysIsActiveItemUi() then
        PartayKeysCloseItemUi()
    end

    PartayKeysShowHandProp('tablet')
    PartayKeysSetActiveItemUi('locksmith_setup')
    PartayKeysOpenNui(false, true)
    SendNUIMessage({
        action = 'openLocksmithSetup',
        token = PartayKeysCreateNuiToken('locksmith_setup'),
        setup = setupData
    })
end

local function StartLocksmithSetupPlacement(data)
    data = type(data) == 'table' and data or {}
    local pointType = tostring(data.pointType or ''):lower()
    local locationName = tostring(data.locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    local shopType = tostring(data.shopType or 'player_owned'):lower():gsub('^%s*(.-)%s*$', '%1')
    local jobName = tostring(data.jobName or ''):gsub('^%s*(.-)%s*$', '%1')
    local modelName = tostring(data.model or GetLocksmithSetupProp('Workbench', 'prop_tool_bench02'))
    local spawnProp = data.spawnProp ~= false
    local isPedPoint = data.isPed == true or pointType == 'fallback_ped'
    local coordOnly = data.coordOnly == true
    local vehiclePreview = data.vehiclePreview == true or pointType == 'vehicle_spawn'

    if pointType == '' or locationName == '' then
        Notify(locale('label_locksmith'), locale('error_locksmith_setup_invalid_location'), 'error')
        return
    end

    StopLocksmithSetupPlacement()
    SendNUIMessage({ action = 'closeUI' })
    PartayKeysCloseNui(true)

    local ped = PlayerPedId()
    if coordOnly then
        spawnProp = false
    end
    if vehiclePreview then
        spawnProp = false
    end
    local coords = coordOnly and GetEntityCoords(ped) or GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.0)
    local object = nil
    if spawnProp or vehiclePreview then
        local model = joaat(modelName)
        RequestModel(model)
        local deadline = GetGameTimer() + 5000
        while not HasModelLoaded(model) and GetGameTimer() < deadline do
            Wait(10)
        end

        if not HasModelLoaded(model) then
            Notify(locale('label_locksmith'), locale('error_locksmith_setup_invalid_point'), 'error')
            return
        end

        if isPedPoint then
            object = CreatePed(4, model, coords.x, coords.y, coords.z, GetEntityHeading(ped), false, false)
            SetBlockingOfNonTemporaryEvents(object, true)
        elseif vehiclePreview then
            object = CreateVehicle(model, coords.x, coords.y, coords.z, GetEntityHeading(ped), false, false)
            SetVehicleOnGroundProperly(object)
            SetVehicleDoorsLocked(object, 2)
        else
            object = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
        end
        SetEntityCollision(object, false, false)
        SetEntityAlpha(object, 180, false)
        SetEntityHeading(object, GetEntityHeading(ped))
        FreezeEntityPosition(object, true)
        SetEntityInvincible(object, true)
        SetModelAsNoLongerNeeded(model)
    end

    activeSetupPlacement = {
        object = object,
        pointType = pointType,
        locationName = locationName,
        shopType = shopType,
        jobName = jobName,
        model = modelName,
        spawnProp = spawnProp,
        isPedPoint = isPedPoint,
        coordOnly = coordOnly,
        vehiclePreview = vehiclePreview,
        heading = GetEntityHeading(ped),
        headingOffset = 0.0,
        followPlayer = true,
        followDistance = 1.35,
        zOffset = 0.0,
        coords = coords
    }

    if coordOnly then
        ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_coord_controls'))

        CreateThread(function()
            while activeSetupPlacement and activeSetupPlacement.coordOnly == true do
                local placementPed = PlayerPedId()
                local pedCoords = GetEntityCoords(placementPed)
                activeSetupPlacement.coords = pedCoords
                activeSetupPlacement.heading = GetEntityHeading(placementPed)

                DrawMarker(2, pedCoords.x, pedCoords.y, pedCoords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, activeSetupPlacement.heading, 0.35, 0.35, 0.35, 88, 214, 255, 185, false, true, 2, false, nil, nil, false)

                if IsControlJustPressed(0, 38) or IsControlJustPressed(0, 191) then
                    SaveLocksmithSetupPlacement()
                    StopLocksmithSetupPlacement()
                    Wait(250)
                    OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                    return
                elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 202) then
                    StopLocksmithSetupPlacement()
                    Wait(150)
                    OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                    return
                end

                ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_coord_controls'))
                Wait(0)
            end
        end)
        return
    end

    if not spawnProp and not vehiclePreview then
        StartLocksmithMloPropSelection()
        return
    end

    if StartLocksmithObjectGizmoPlacement(object) then
        return
    end

    ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_place_controls'))

    CreateThread(function()
        while activeSetupPlacement and activeSetupPlacement.object == object do
            local placementPed = PlayerPedId()
            if activeSetupPlacement.followPlayer then
                local followCoords = GetOffsetFromEntityInWorldCoords(placementPed, 0.0, activeSetupPlacement.followDistance or 1.35, activeSetupPlacement.zOffset or 0.0)
                activeSetupPlacement.coords = followCoords
                activeSetupPlacement.heading = (GetEntityHeading(placementPed) + (activeSetupPlacement.headingOffset or 0.0)) % 360.0
            end

            local preview = activeSetupPlacement.coords
            if object then
                SetEntityCoordsNoOffset(object, preview.x, preview.y, preview.z, false, false, false)
                SetEntityHeading(object, activeSetupPlacement.heading)
            else
                DrawMarker(2, preview.x, preview.y, preview.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, activeSetupPlacement.heading, 0.35, 0.35, 0.35, 88, 214, 255, 185, false, true, 2, false, nil, nil, false)
            end
            DrawLocksmithPlacementGizmo(preview, activeSetupPlacement.heading)

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            local camForward = RotationToDirection(GetGameplayCamRot(2))
            local forward = vector3(camForward.x, camForward.y, 0.0)
            local length = math.sqrt((forward.x * forward.x) + (forward.y * forward.y))
            if length < 0.01 then
                forward = vector3(0.0, 1.0, 0.0)
            else
                forward = vector3(forward.x / length, forward.y / length, 0.0)
            end
            local right = vector3(forward.y, -forward.x, 0.0)
            local fineTune = IsControlPressed(0, 36)
            local fastTune = IsControlPressed(0, 21)
            local moveStep = 0.035
            local rotateStep = 5.0
            local heightStep = 0.05

            if fineTune then
                moveStep = 0.008
                rotateStep = 1.0
                heightStep = 0.01
            elseif fastTune then
                moveStep = 0.08
                rotateStep = 10.0
                heightStep = 0.1
            end

            if activeSetupPlacement.followPlayer then
                if IsControlPressed(0, 172) then
                    activeSetupPlacement.zOffset = (activeSetupPlacement.zOffset or 0.0) + heightStep
                elseif IsControlPressed(0, 173) then
                    activeSetupPlacement.zOffset = (activeSetupPlacement.zOffset or 0.0) - heightStep
                end

                if IsControlJustPressed(0, 174) then
                    activeSetupPlacement.headingOffset = (activeSetupPlacement.headingOffset or 0.0) - rotateStep
                elseif IsControlJustPressed(0, 175) then
                    activeSetupPlacement.headingOffset = (activeSetupPlacement.headingOffset or 0.0) + rotateStep
                end
            else
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)

                if IsDisabledControlPressed(0, 32) then
                    activeSetupPlacement.coords = activeSetupPlacement.coords + (forward * moveStep)
                elseif IsDisabledControlPressed(0, 33) then
                    activeSetupPlacement.coords = activeSetupPlacement.coords - (forward * moveStep)
                end

                if IsDisabledControlPressed(0, 35) then
                    activeSetupPlacement.coords = activeSetupPlacement.coords + (right * moveStep)
                elseif IsDisabledControlPressed(0, 34) then
                    activeSetupPlacement.coords = activeSetupPlacement.coords - (right * moveStep)
                end

                if IsControlJustPressed(0, 174) then
                    activeSetupPlacement.heading = activeSetupPlacement.heading - rotateStep
                elseif IsControlJustPressed(0, 175) then
                    activeSetupPlacement.heading = activeSetupPlacement.heading + rotateStep
                elseif IsControlJustPressed(0, 172) then
                    activeSetupPlacement.coords = activeSetupPlacement.coords + vector3(0.0, 0.0, heightStep)
                elseif IsControlJustPressed(0, 173) then
                    activeSetupPlacement.coords = activeSetupPlacement.coords - vector3(0.0, 0.0, heightStep)
                end
            end

            if IsControlJustPressed(0, 47) then
                activeSetupPlacement.followPlayer = not activeSetupPlacement.followPlayer
            elseif IsControlJustPressed(0, 191) then
                SaveLocksmithSetupPlacement()
                StopLocksmithSetupPlacement()
                Wait(250)
                OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                return
            elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 202) then
                StopLocksmithSetupPlacement()
                Wait(150)
                OpenLocksmithSetupMenu(activeLocksmithSetupMode)
                return
            end

            ShowLocksmithSetupPlacementHelp(locale('info_locksmith_setup_place_controls'))
            Wait(0)
        end
    end)
end

RegisterCommand(setupAdminCommand, function()
    OpenLocksmithSetupMenu('admin')
end, false)

RegisterCommand(setupOwnerCommand, function()
    OpenLocksmithSetupMenu('owner')
end, false)

RegisterNetEvent('partay_keys:client:UseLocksmithTabletItem', function(itemName)
    if itemName == Config.Items.LocksmithOwnerTablet then
        local business = lib.callback.await('partay_keys:server:GetLocksmithBusinessData', false) or {}
        if business.allowed ~= true then
            Notify(locale('label_locksmith'), locale('error_locksmith_owner_required'), 'error')
            return
        end

        OpenPartayServiceMenu('locksmith', 'business', 'owner', 'owner_tablet')
        return
    end

    local access = lib.callback.await('partay_keys:server:GetLocksmithAccess', false) or {}
    if access.isEmployee ~= true then
        Notify(locale('label_locksmith'), locale('error_locksmith_employee_required'), 'error')
        return
    end

    OpenPartayServiceMenu('locksmith', 'vehicles', nil, 'employee_tablet')
end)

RegisterNetEvent('partay_keys:client:RefreshLocksmithBusiness', function()
    local business = lib.callback.await('partay_keys:server:GetLocksmithBusinessData', false) or {}
    if business.allowed ~= true then
        business = lib.callback.await('partay_keys:server:GetLocksmithEmployeeBusinessData', false) or business
    end
    SendNUIMessage({
        action = 'locksmithBusinessData',
        businessData = business
    })
end)

RegisterNetEvent('partay_keys:client:RefreshLocksmithWorkbench', function()
    local business = lib.callback.await('partay_keys:server:GetLocksmithWorkbenchData', false) or {}
    SendNUIMessage({
        action = 'locksmithBusinessData',
        businessData = business
    })
end)

local function GetLocksmithStockLocation(locationName)
    local locations = lib.callback.await('partay_keys:server:GetLocksmithLocations', false) or {}
    local fallback = nil

    for _, location in ipairs(locations) do
        if location.type == 'stock' then
            fallback = fallback or location
            if not locationName or location.locationName == locationName then
                return location
            end
        end
    end

    return fallback
end

local function GetLocksmithStockingProp(key, fallback)
    local props = Props and Props.Locksmith and Props.Locksmith.Stocking or {}
    local value = props[key]
    if type(value) == 'table' then
        return value.Model or value.model or fallback
    end
    return value or fallback
end

local function GetLocksmithSetupProp(key, fallback)
    local props = Props and Props.Locksmith and Props.Locksmith.Setup or {}
    return props[key] or fallback
end

local function GetLocksmithStockBoxProp()
    local props = Props and Props.Locksmith and Props.Locksmith.Stocking or {}
    local box = props.StockBox
    if type(box) ~= 'table' then
        box = { Model = box or 'prop_cardbordbox_04a' }
    end

    return {
        Model = box.Model or box.model or 'prop_cardbordbox_04a',
        Bone = box.Bone or box.bone or 28422,
        Pos = box.Pos or box.pos or vector3(0.0, -0.03, -0.08),
        Rot = box.Rot or box.rot or vector3(5.0, 0.0, 0.0),
        Animation = box.Animation or box.animation or 'LocksmithStockBox'
    }
end

local function AttachLocksmithStockBox(box, ped)
    if not box or box == 0 or not DoesEntityExist(box) then return end
    ped = ped or PlayerPedId()
    local config = GetLocksmithStockBoxProp()
    local pos = config.Pos or vector3(0.0, -0.03, -0.08)
    local rot = config.Rot or vector3(5.0, 0.0, 0.0)
    AttachEntityToEntity(box, ped, GetPedBoneIndex(ped, config.Bone or 28422), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
end

local function LoadStockModel(modelName)
    local model = type(modelName) == 'number' and modelName or joaat(modelName or GetLocksmithStockingProp('StockBox', 'prop_cardbordbox_04a'))
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do
        Wait(10)
    end
    return HasModelLoaded(model) and model or nil
end

local function DeleteIfExists(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

local function GetClosestLocksmithServicePed(maxDistance)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closestPed, closestDistance
    local candidates = {}

    for _, ped in ipairs(spawnedPeds) do
        candidates[#candidates + 1] = ped
    end

    for _, entity in ipairs(spawnedLocksmithLocations) do
        candidates[#candidates + 1] = entity
    end

    for _, entity in ipairs(candidates) do
        if entity and entity ~= 0 and entity ~= playerPed and DoesEntityExist(entity) and IsEntityAPed(entity) then
            local distance = #(playerCoords - GetEntityCoords(entity))
            if distance <= (tonumber(maxDistance) or 25.0) and (not closestDistance or distance < closestDistance) then
                closestPed = entity
                closestDistance = distance
            end
        end
    end

    return closestPed
end

local function GetNearestLocksmithStockCoords(maxDistance)
    local locations = lib.callback.await('partay_keys:server:GetLocksmithLocations', false) or {}
    local playerCoords = GetEntityCoords(PlayerPedId())
    local closest, closestDistance
    local fallback, fallbackDistance

    for _, location in ipairs(locations) do
        local coords = location.coords
        if coords then
            local point = vector3(coords.x, coords.y, coords.z)
            local distance = #(playerCoords - point)
            if location.type == 'stock' then
                if distance <= (tonumber(maxDistance) or 60.0) and (not closestDistance or distance < closestDistance) then
                    closest = coords
                    closestDistance = distance
                end
            elseif location.type == 'register' or location.type == 'management' or location.type == 'fallback_ped' then
                if distance <= (tonumber(maxDistance) or 60.0) and (not fallbackDistance or distance < fallbackDistance) then
                    fallback = coords
                    fallbackDistance = distance
                end
            end
        end
    end

    return closest or fallback
end

local function LoadServicePedModel(sourcePed)
    local model = sourcePed and sourcePed ~= 0 and DoesEntityExist(sourcePed) and GetEntityModel(sourcePed)
        or GetHashKey('s_m_y_xmech_01')

    if not IsModelValid(model) or not IsModelInCdimage(model) then
        model = GetHashKey('s_m_y_xmech_01')
    end

    lib.requestModel(model, 5000)
    return model
end

local function SpawnTemporaryLocksmithWorker(coords, heading, sourcePed)
    local model = LoadServicePedModel(sourcePed)
    local worker = CreatePed(4, model, coords.x, coords.y, coords.z, heading or 0.0, false, false)
    SetBlockingOfNonTemporaryEvents(worker, true)
    SetEntityInvincible(worker, true)
    SetModelAsNoLongerNeeded(model)
    return worker
end

local function MovePedToCoords(ped, coords, timeoutMs, heading)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not coords then return false end

    TaskGoStraightToCoord(ped, coords.x, coords.y, coords.z, 1.0, timeoutMs or 3500, heading or 0.0, 0.25)

    local started = GetGameTimer()
    while GetGameTimer() - started < (timeoutMs or 3500) do
        if #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= 1.0 then
            ClearPedTasks(ped)
            return true
        end
        Wait(50)
    end

    ClearPedTasks(ped)
    return false
end

local function MovePedToVehicleBone(ped, vehicle, boneName, timeoutMs)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
    if boneIndex == -1 then return false end

    local coords = GetWorldPositionOfEntityBone(vehicle, boneIndex)
    if MovePedToCoords(ped, coords, timeoutMs or 2500, GetEntityHeading(vehicle)) then
        TaskTurnPedToFaceEntity(ped, vehicle, 600)
        Wait(650)
        return true
    end

    return false
end

local function PlayLocksmithNpcStockHandoff()
    local servicePed = GetClosestLocksmithServicePed(35.0)
    local startCoords
    local startHeading = 0.0

    if servicePed and DoesEntityExist(servicePed) then
        startCoords = GetEntityCoords(servicePed)
        startHeading = GetEntityHeading(servicePed)
    else
        return false
    end

    local stockCoords = GetNearestLocksmithStockCoords(60.0)
    if not stockCoords then
        stockCoords = { x = startCoords.x, y = startCoords.y, z = startCoords.z, w = startHeading }
    end

    local playerPed = PlayerPedId()
    local returnCoords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 1.0, 0.0)
    local worker = SpawnTemporaryLocksmithWorker(startCoords, startHeading, servicePed)
    local box

    if not worker or worker == 0 or not DoesEntityExist(worker) then return false end

    MovePedToCoords(worker, stockCoords, 3500, stockCoords.w or startHeading)
    PlayPedConfiguredAnimation(worker, 'LocksmithStockBox', 900)

    local boxModel = LoadStockModel(GetLocksmithStockingProp('StockBox', 'prop_cardbordbox_04a'))
    if boxModel then
        local workerCoords = GetEntityCoords(worker)
        box = CreateObject(boxModel, workerCoords.x, workerCoords.y, workerCoords.z + 0.2, false, false, false)
        AttachLocksmithStockBox(box, worker)
        SetModelAsNoLongerNeeded(boxModel)
        StartConfiguredAnimation((GetLocksmithStockBoxProp()).Animation or 'LocksmithStockBox', worker)
    end

    MovePedToCoords(worker, returnCoords, 4500, GetEntityHeading(playerPed))
    TaskTurnPedToFaceEntity(worker, playerPed, 600)
    TaskTurnPedToFaceEntity(playerPed, worker, 600)
    Wait(650)
    PlayPedConfiguredAnimation(worker, 'NpcKeyGive', 1200)
    PlayConfiguredAnimation('NpcKeyReceive', 1200)

    DeleteIfExists(box)
    DeleteIfExists(worker)
    return true
end

local function PlayLocksmithNpcVehicleWork(data)
    if type(data) ~= 'table' then return false end

    local vehicle = tonumber(data.netId) and NetToVeh(tonumber(data.netId)) or 0
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local action = data.action
    local needsDoorWork = action == 'rekey' or action == 'upgrade'
    for _, service in ipairs(data.services or {}) do
        if service.action == 'rekey' or service.action == 'upgrade' then
            needsDoorWork = true
            break
        end
    end

    local servicePed = GetClosestLocksmithServicePed(80.0)
    local spawnCoords = GetOffsetFromEntityInWorldCoords(vehicle, -2.0, -2.0, 0.0)
    local worker = SpawnTemporaryLocksmithWorker(spawnCoords, GetEntityHeading(vehicle), servicePed)
    if not worker or worker == 0 or not DoesEntityExist(worker) then return false end

    if not needsDoorWork then
        MovePedToVehicleBone(worker, vehicle, 'bonnet', 2500)
        PlayPedConfiguredAnimation(worker, 'LocksmithDoorWork', 1800)
        DeleteIfExists(worker)
        return true
    end

    local workflow = GetLocksmithPlayerRunConfig().Workflow or {}
    local doorDuration = math.floor((tonumber(workflow.DoorWorkSeconds) or 3.5) * 1000)
    local doorTargets = {
        { bone = 'door_dside_f', index = 0 },
        { bone = 'door_pside_f', index = 1 },
        { bone = 'door_dside_r', index = 2 },
        { bone = 'door_pside_r', index = 3 }
    }

    local workedAnyDoor = false
    for _, target in ipairs(doorTargets) do
        if GetEntityBoneIndexByName(vehicle, target.bone) ~= -1 and MovePedToVehicleBone(worker, vehicle, target.bone, 3000) then
            workedAnyDoor = true
            SetVehicleDoorOpen(vehicle, target.index, false, false)
            PlayPedConfiguredAnimation(worker, 'LocksmithDoorWork', doorDuration)
            SetVehicleDoorShut(vehicle, target.index, false)
        end
    end

    if not workedAnyDoor then
        PlayPedConfiguredAnimation(worker, 'LocksmithDoorWork', doorDuration)
    end

    DeleteIfExists(worker)
    return true
end

local function CarryStockBoxTo(coords, order)
    local ped = PlayerPedId()
    local boxModel = LoadStockModel(order.boxModel or GetLocksmithStockingProp('StockBox', 'prop_cardbordbox_04a'))
    if not boxModel then return false end

    local pedCoords = GetEntityCoords(ped)
    local box = CreateObject(boxModel, pedCoords.x, pedCoords.y, pedCoords.z + 0.2, true, true, false)
    AttachLocksmithStockBox(box, ped)
    SetModelAsNoLongerNeeded(boxModel)
    StartConfiguredAnimation((GetLocksmithStockBoxProp()).Animation or 'LocksmithStockBox', ped)

    Notify(locale('label_locksmith'), locale('info_locksmith_stock_carry_box'), 'info')
    local deadline = GetGameTimer() + 120000
    while DoesEntityExist(box) and GetGameTimer() < deadline do
        local current = GetEntityCoords(ped)
        DrawMarker(2, coords.x, coords.y, coords.z + 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.35, 0.35, 0.35, 88, 214, 255, 180, false, true, 2, false, nil, nil, false)
        if #(current - vector3(coords.x, coords.y, coords.z)) <= 2.0 then
            PlayConfiguredAnimation('LocksmithStockBox', math.floor((tonumber(order.carryBoxSeconds) or 3.0) * 1000))
            DeleteIfExists(box)
            ClearPedTasks(ped)
            return true
        end
        Wait(0)
    end

    DeleteIfExists(box)
    ClearPedTasks(ped)
    return false
end

local function WaitForLocksmithPackageTarget(entity, optionName, label, timeoutMs, canInteract, onSelect)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

    local selected = false
    local name = ('partay_keys_%s_%s'):format(optionName or 'stock_package', entity)
    exports.ox_target:addLocalEntity(entity, {
        {
            name = name,
            icon = 'fas fa-box',
            label = label,
            distance = 2.2,
            canInteract = canInteract,
            onSelect = function()
                if selected then return end
                selected = true
                if onSelect then onSelect() end
            end
        }
    })

    local deadline = GetGameTimer() + (tonumber(timeoutMs) or 180000)
    while DoesEntityExist(entity) and not selected and GetGameTimer() < deadline do
        Wait(250)
    end

    pcall(function()
        exports.ox_target:removeLocalEntity(entity, name)
    end)

    return selected
end

local function NormalizeLocksmithRoute(route)
    local normalized = {}
    if type(route) ~= 'table' then return normalized end

    for _, point in ipairs(route) do
        local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
        if x and y and z then
            normalized[#normalized + 1] = {
                x = x,
                y = y,
                z = z,
                w = tonumber(point.w) or 0.0
            }
        end
    end

    return normalized
end

local function DriveEntityThroughLocksmithRoute(driver, vehicle, route, finalCoords, finalHeading)
    if not driver or driver == 0 or not DoesEntityExist(driver) or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local points = NormalizeLocksmithRoute(route)
    if finalCoords then
        points[#points + 1] = {
            x = finalCoords.x,
            y = finalCoords.y,
            z = finalCoords.z,
            w = finalCoords.w or finalHeading or 0.0
        }
    end

    if #points == 0 then return false end

    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedKeepTask(driver, true)
    for _, point in ipairs(points) do
        TaskVehicleDriveToCoordLongrange(driver, vehicle, point.x, point.y, point.z, 12.0, 786603, 4.0)
        local deadline = GetGameTimer() + 45000
        while DoesEntityExist(driver) and DoesEntityExist(vehicle) and GetGameTimer() < deadline do
            if #(GetEntityCoords(vehicle) - vector3(point.x, point.y, point.z)) <= 5.0 then
                break
            end
            Wait(250)
        end
    end

    ClearPedTasks(driver)
    SetVehicleHandbrake(vehicle, true)
    if finalHeading then SetEntityHeading(vehicle, finalHeading) end
    return true
end

local function WalkPedThroughLocksmithRoute(ped, route, finalCoords, finalHeading)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false
    end

    local points = NormalizeLocksmithRoute(route)
    if finalCoords then
        points[#points + 1] = {
            x = finalCoords.x,
            y = finalCoords.y,
            z = finalCoords.z,
            w = finalCoords.w or finalHeading or 0.0
        }
    end

    if #points == 0 then return false end

    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    for _, point in ipairs(points) do
        TaskFollowNavMeshToCoord(ped, point.x, point.y, point.z, 1.2, 45000, 0.7, false, point.w or 0.0)
        local deadline = GetGameTimer() + 45000
        while DoesEntityExist(ped) and GetGameTimer() < deadline do
            if #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) <= 1.1 then
                break
            end
            Wait(250)
        end
    end

    ClearPedTasks(ped)
    if finalHeading then SetEntityHeading(ped, finalHeading) end
    return true
end

local function GetLocksmithStockOrderWaitMs(order)
    if type(order) ~= 'table' then return 0 end

    local waitSeconds = tonumber(order.waitSeconds)
    if waitSeconds then
        return math.max(0, math.floor(waitSeconds * 1000))
    end

    local readyAt = tonumber(order.readyAt)
    local serverNow = tonumber(order.serverNow)
    if readyAt and serverNow then
        return math.max(0, math.floor((readyAt - serverNow) * 1000))
    end

    return 0
end

local function StartDeliveryStockOrder(order, stockLocation)
    local coords = stockLocation and stockLocation.coords
    local dropoff = order.deliveryDropoffCoords or coords
    if not coords and not dropoff then
        Notify(locale('label_locksmith'), locale('error_locksmith_stock_location_missing'), 'error')
        return
    end

    local waitMs = GetLocksmithStockOrderWaitMs(order)
    if waitMs > 0 then
        Notify(locale('label_locksmith'), locale('info_locksmith_stock_delivery_ordered', { seconds = math.ceil(waitMs / 1000) }), 'info')
        Wait(waitMs)
    end

    local truck, driver, box
    local truckModel = LoadStockModel(order.truckModel or GetLocksmithStockingProp('DeliveryTruck', 'boxville2'))
    local pedModel = LoadStockModel(order.pedModel or GetLocksmithStockingProp('DeliveryPed', 's_m_m_dockwork_01'))
    local boxModel = LoadStockModel(order.boxModel or GetLocksmithStockingProp('StockBox', 'prop_cardbordbox_04a'))
    local offset = order.deliverySpawnOffset or { x = 0.0, y = -8.0, z = 0.0, w = 0.0 }
    local spawnCoords = order.deliverySpawnCoords
    local spawn = spawnCoords and vector3(spawnCoords.x, spawnCoords.y, spawnCoords.z)
        or vector3(coords.x + (offset.x or 0.0), coords.y + (offset.y or -8.0), coords.z + (offset.z or 0.0))
    local heading = (spawnCoords and spawnCoords.w) or (coords and coords.w) or offset.w or 0.0

    if truckModel then
        truck = CreateVehicle(truckModel, spawn.x, spawn.y, spawn.z, heading, true, false)
        SetVehicleOnGroundProperly(truck)
        SetVehicleDoorsLocked(truck, 2)
        SetModelAsNoLongerNeeded(truckModel)
    end

    if pedModel and truck and DoesEntityExist(truck) then
        driver = CreatePedInsideVehicle(truck, 4, pedModel, -1, true, false)
        SetBlockingOfNonTemporaryEvents(driver, true)
        SetModelAsNoLongerNeeded(pedModel)
    end

    local boxCoords = spawn
    local deliveryRoute = NormalizeLocksmithRoute(order.deliveryRoute or {})
    local deliveryPedRoute = NormalizeLocksmithRoute(order.deliveryPedRoute or {})
    local deliveryRouteEnd = NormalizeLocksmithRoute(order.deliveryRouteEnd and { order.deliveryRouteEnd } or {})[1]
    local deliveryPedRouteEnd = NormalizeLocksmithRoute(order.deliveryPedRouteEnd and { order.deliveryPedRouteEnd } or {})[1]
    local truckStop = deliveryRouteEnd or deliveryPedRoute[1] or dropoff
    local driverDropoff = deliveryPedRouteEnd or dropoff
    if driver and truck and driverDropoff then
        local arrived = DriveEntityThroughLocksmithRoute(driver, truck, deliveryRoute, truckStop, truckStop and truckStop.w or heading)
        if arrived then
            TaskLeaveVehicle(driver, truck, 0)
            local leaveDeadline = GetGameTimer() + 8000
            while DoesEntityExist(driver) and IsPedInVehicle(driver, truck, false) and GetGameTimer() < leaveDeadline do
                Wait(250)
            end

            if WalkPedThroughLocksmithRoute(driver, deliveryPedRoute, driverDropoff, driverDropoff.w or heading) then
                boxCoords = vector3(driverDropoff.x, driverDropoff.y, driverDropoff.z)
            elseif truckStop then
                boxCoords = vector3(truckStop.x, truckStop.y, truckStop.z)
            end
        end
    end

    if boxModel then
        box = CreateObject(boxModel, boxCoords.x, boxCoords.y - 1.4, boxCoords.z + 0.2, true, true, false)
        PlaceObjectOnGroundProperly(box)
        SetModelAsNoLongerNeeded(boxModel)
    end

    Notify(locale('label_locksmith'), locale('info_locksmith_stock_delivery_arrived'), 'info')
    local accepted = false
    if box then
        WaitForLocksmithPackageTarget(
            box,
            ('stock_delivery_%s'):format(order.id or GetGameTimer()),
            locale('label_locksmith_stock_pickup_box'),
            180000,
            function(entity)
                return #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(entity)) <= 2.4
            end,
            function()
                DeleteIfExists(box)
                accepted = CarryStockBoxTo(dropoff, order)
            end
        )
    end

    DeleteIfExists(box)
    DeleteIfExists(driver)
    DeleteIfExists(truck)

    if accepted then
        TriggerServerEvent('partay_keys:server:CompleteLocksmithStockOrder', order.id)
    else
        Notify(locale('label_locksmith'), locale('error_locksmith_stock_order_abandoned'), 'error')
    end
end

local function StartPickupStockOrder(order, stockLocation)
    local stockCoords = stockLocation and stockLocation.coords
    local pickup = order.pickupCoords
    if not stockCoords or not pickup then
        Notify(locale('label_locksmith'), locale('error_locksmith_stock_location_missing'), 'error')
        return
    end

    local waitMs = GetLocksmithStockOrderWaitMs(order)
    if waitMs > 0 then
        Notify(locale('label_locksmith'), locale('info_locksmith_stock_pickup_ordered', { seconds = math.ceil(waitMs / 1000) }), 'info')
        Wait(waitMs)
    end

    SetNewWaypoint(pickup.x, pickup.y)
    Notify(locale('label_locksmith'), locale('info_locksmith_stock_pickup_ready'), 'info')

    local boxModel = LoadStockModel(order.boxModel or GetLocksmithStockingProp('StockBox', 'prop_cardbordbox_04a'))
    if not boxModel then return end
    local box = CreateObject(boxModel, pickup.x, pickup.y, pickup.z + 0.2, true, true, false)
    PlaceObjectOnGroundProperly(box)
    SetModelAsNoLongerNeeded(boxModel)

    local loadedVehicle = nil
    WaitForLocksmithPackageTarget(
        box,
        ('stock_pickup_load_%s'):format(order.id or GetGameTimer()),
        locale('label_locksmith_stock_load_box'),
        900000,
        function(entity)
            local ped = PlayerPedId()
            local boxCoords = GetEntityCoords(entity)
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle == 0 then
                vehicle = GetClosestVehicle(boxCoords.x, boxCoords.y, boxCoords.z, 8.0, 0, 70)
            end
            return vehicle and vehicle ~= 0 and #(GetEntityCoords(ped) - boxCoords) <= 2.4
        end,
        function(entity)
            local ped = PlayerPedId()
            local boxCoords = GetEntityCoords(entity)
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle == 0 then
                vehicle = GetClosestVehicle(boxCoords.x, boxCoords.y, boxCoords.z, 8.0, 0, 70)
            end
            if vehicle and vehicle ~= 0 then
                PlayConfiguredAnimation('LocksmithStockBox', math.floor((tonumber(order.carryBoxSeconds) or 3.0) * 1000))
                AttachEntityToEntity(box, vehicle, 0, 0.0, -2.2, 0.55, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
                loadedVehicle = vehicle
                SetNewWaypoint(stockCoords.x, stockCoords.y)
                Notify(locale('label_locksmith'), locale('info_locksmith_stock_return_to_shop'), 'info')
            else
                Notify(locale('label_locksmith'), locale('error_locksmith_stock_vehicle_required'), 'error')
            end
        end
    )

    if not loadedVehicle or not DoesEntityExist(box) then
        DeleteIfExists(box)
        Notify(locale('label_locksmith'), locale('error_locksmith_stock_order_abandoned'), 'error')
        return
    end

    local unloaded = false
    WaitForLocksmithPackageTarget(
        box,
        ('stock_pickup_unload_%s'):format(order.id or GetGameTimer()),
        locale('label_locksmith_stock_unload_box'),
        900000,
        function()
            return #(GetEntityCoords(PlayerPedId()) - vector3(stockCoords.x, stockCoords.y, stockCoords.z)) <= 4.0
        end,
        function()
            DetachEntity(box, true, true)
            DeleteIfExists(box)
            if CarryStockBoxTo(stockCoords, order) then
                TriggerServerEvent('partay_keys:server:CompleteLocksmithStockOrder', order.id)
                unloaded = true
            end
        end
    )
    if unloaded then
        return
    end

    DeleteIfExists(box)
    Notify(locale('label_locksmith'), locale('error_locksmith_stock_order_abandoned'), 'error')
end

RegisterNetEvent('partay_keys:client:StartLocksmithStockOrder', function(order)
    if type(order) ~= 'table' or not order.id then return end
    CreateThread(function()
        local stockLocation = GetLocksmithStockLocation(order.locationName)
        if order.stockMethod == 'delivery' then
            StartDeliveryStockOrder(order, stockLocation)
        elseif order.stockMethod == 'pickup' then
            StartPickupStockOrder(order, stockLocation)
        end
    end)
end)

local function ClearLocksmithOrderPickup(orderId)
    local pickup = spawnedLocksmithOrderPickups[orderId]
    if not pickup then return end

    if pickup.zoneId then
        exports.ox_target:removeZone(pickup.zoneId)
    end
    if pickup.object and DoesEntityExist(pickup.object) then
        DeleteEntity(pickup.object)
    end
    spawnedLocksmithOrderPickups[orderId] = nil
    collectingLocksmithOrderPickups[orderId] = nil
end

RegisterNetEvent('partay_keys:client:CreateLocksmithShopPickup', function(order)
    if type(order) ~= 'table' or not order.orderId or not order.pickupCoords then return end
    ClearLocksmithOrderPickup(order.orderId)

    local coords = order.pickupCoords
    local model = GetHashKey(order.pickupModel or GetLocksmithStockingProp('CustomerOrderPickup', 'prop_cs_cardbox_01'))
    local object = nil
    if IsModelValid(model) and IsModelInCdimage(model) then
        lib.requestModel(model, 5000)
        object = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(object, coords.w or 0.0)
        PlaceObjectOnGroundProperly(object)
        FreezeEntityPosition(object, true)
        SetModelAsNoLongerNeeded(model)
    end

    local targetOption = {
        name = ('partay_locksmith_shop_pickup_%s'):format(order.orderId),
        icon = 'fas fa-box-open',
        label = locale('label_locksmith_shop_pickup'),
        distance = 2.0,
        onSelect = function()
            if collectingLocksmithOrderPickups[order.orderId] then return end
            collectingLocksmithOrderPickups[order.orderId] = true

            local ok, result = pcall(function()
                return lib.callback.await('partay_keys:server:CollectLocksmithShopOrder', false, order.orderId)
            end)

            if ok and result and result.ok == true then
                ClearLocksmithOrderPickup(order.orderId)
                return
            end

            collectingLocksmithOrderPickups[order.orderId] = nil
            if Config.DebugMode then
                print(('[ParTay Keys Debug] Locksmith shop order pickup failed: %s'):format(tostring(ok and result and result.reason or result)))
            end
        end
    }

    if object then
        exports.ox_target:addLocalEntity(object, { targetOption })
        spawnedLocksmithOrderPickups[order.orderId] = { object = object }
    else
        local zoneId = exports.ox_target:addSphereZone({
            coords = vector3(coords.x, coords.y, coords.z),
            radius = 0.9,
            debug = Config.DebugMode == true,
            options = { targetOption }
        })
        spawnedLocksmithOrderPickups[order.orderId] = { zoneId = zoneId }
    end
end)

local function CreatePedBlip(key, data)
    if data.ShowOnMap ~= true or not data.Coords then return end

    local blipConfig = data.Blip or {}
    local blip = AddBlipForCoord(data.Coords.x, data.Coords.y, data.Coords.z)
    SetBlipSprite(blip, blipConfig.Sprite or 280)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipConfig.Scale or 0.75)
    SetBlipColour(blip, blipConfig.Color or 0)
    SetBlipAsShortRange(blip, blipConfig.ShortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipConfig.Label or key)
    EndTextCommandSetBlipName(blip)

    spawnedBlips[#spawnedBlips + 1] = blip
end

local function ClearServicePeds()
    for _, ped in ipairs(spawnedPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    spawnedPeds = {}

    for _, blip in ipairs(spawnedBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    spawnedBlips = {}
end

local function SpawnServicePeds()
    ClearServicePeds()

    local servicePedData = GetServicePedData()
    local blackmarket = servicePedData.blackmarket or {}
    local warehousePickup = servicePedData.warehousePickup or {}
    local locationBlips = servicePedData.locationBlips or {}
    local servicePeds = {}
    if blackmarket.enabled == true then
        servicePeds.Blackmarket = {
            Model = blackmarket.model,
            Coords = blackmarket.coords,
            SpawnPed = true,
            ShowOnMap = blackmarket.showOnMap,
            Blip = {
                Label = blackmarket.blip and blackmarket.blip.label or 'Blackmarket',
                Sprite = blackmarket.blip and blackmarket.blip.sprite or 378,
                Color = blackmarket.blip and blackmarket.blip.color or 1,
                Scale = blackmarket.blip and blackmarket.blip.scale or 0.75
            }
        }
    end
    if warehousePickup.enabled == true and warehousePickup.coords then
        servicePeds.WarehousePickup = {
            Model = warehousePickup.pedModel,
            Coords = warehousePickup.coords,
            SpawnPed = warehousePickup.spawnPed == true,
            ShowOnMap = warehousePickup.showOnMap,
            Blip = {
                Label = warehousePickup.blip and warehousePickup.blip.label or 'Locksmith Warehouse',
                Sprite = warehousePickup.blip and warehousePickup.blip.sprite or 473,
                Color = warehousePickup.blip and warehousePickup.blip.color or 5,
                Scale = warehousePickup.blip and warehousePickup.blip.scale or 0.75
            }
        }
    end

    for _, entry in ipairs(locationBlips) do
        local blip = entry.blip or {}
        if entry.coords and blip.enabled == true then
            servicePeds[('LocksmithLocation:%s'):format(entry.locationName or 'Shop')] = {
                Coords = entry.coords,
                SpawnPed = false,
                ShowOnMap = true,
                Blip = {
                    Label = blip.label or entry.locationName or 'Locksmith',
                    Sprite = blip.sprite or 402,
                    Color = blip.color or 2,
                    Scale = blip.scale or 0.75,
                    ShortRange = blip.shortRange ~= false
                }
            }
        end
    end

    for key, data in pairs(servicePeds) do
        local shouldSpawn = data.Coords ~= nil

        if shouldSpawn then
            if data.ShowOnMap == true then
                CreatePedBlip(key, data)
            end

            if data.SpawnPed ~= false then
                local model = data.Model
                if type(model) == 'string' then
                    model = GetHashKey(model)
                end

                if not IsModelValid(model) or not IsModelInCdimage(model) then
                    print(('[partay_keys] Invalid ped model configured for %s: %s'):format(key, tostring(data.Model)))
                else
                    -- 1. Safely load the model from the config
                    lib.requestModel(model, 5000)

                    -- 2. Spawn the ped
                    local ped = CreatePed(4, model, data.Coords.x, data.Coords.y, data.Coords.z - 1.0, data.Coords.w, false, false)

                    -- 3. Secure the ped (No dying, no moving, no reacting)
                    SetEntityInvincible(ped, true)
                    FreezeEntityPosition(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    SetModelAsNoLongerNeeded(model)

                    -- 4. Store the entity ID for Garbage Collection
                    table.insert(spawnedPeds, ped)

                    -- 5. Attach ox_target interactions
                    if key == 'Blackmarket' then
                        exports.ox_target:addLocalEntity(ped, {
                            {
                                name = 'partay_blackmarket',
                                icon = 'fas fa-user-secret',
                                label = locale('target_access_blackmarket'),
                                onSelect = function()
                                    OpenPartayServiceMenu('blackmarket', 'shop')
                                end
                            }
                        })
                    end
                end
            end
        end
    end
end

local function ClearLocksmithLocations()
    for _, object in ipairs(spawnedLocksmithLocations) do
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end
    spawnedLocksmithLocations = {}

    for _, zoneId in ipairs(spawnedLocksmithZones) do
        exports.ox_target:removeZone(zoneId)
    end
    spawnedLocksmithZones = {}

    spawnedLocksmithSigns = {}
end

local function GetLocksmithLocationAction(pointType)
    if pointType == 'management' then
        return OpenLocksmithManagementPoint
    elseif pointType == 'timeclock' then
        return function()
            TriggerServerEvent('partay_keys:server:ToggleLocksmithDuty')
        end
    elseif pointType == 'register' then
        return function()
            OpenPartayServiceMenu('locksmith', 'shop', nil, 'register')
        end
    elseif pointType == 'garage' then
        return OpenLocksmithGarageMenu
    elseif pointType == 'status_sign' then
        return function()
            OpenPartayServiceMenu('locksmith', 'business', 'owner', 'status_sign')
        end
    elseif pointType == 'fallback_ped' then
        return function()
            OpenPartayServiceMenu('locksmith', 'shop', nil, 'ped')
        end
    elseif pointType == 'stock' then
        return function()
            OpenPartayServiceMenu('locksmith', 'business', nil, 'stock')
        end
    elseif pointType == 'workbench' then
        return OpenLocksmithWorkbenchMenu
    end

    return nil
end

local function MoveToLocksmithStandSpot(location)
    local standSpot = location and location.stockSettings and location.stockSettings.standSpot
    if type(standSpot) ~= 'table' then return true end

    local x, y, z = tonumber(standSpot.x), tonumber(standSpot.y), tonumber(standSpot.z)
    if not x or not y or not z then return true end

    local ped = PlayerPedId()
    local target = vector3(x, y, z)
    if #(GetEntityCoords(ped) - target) > 0.65 then
        TaskGoStraightToCoord(ped, x, y, z, 1.0, 4000, tonumber(standSpot.w) or GetEntityHeading(ped), 0.2)
        local started = GetGameTimer()
        while GetGameTimer() - started < 4000 do
            if #(GetEntityCoords(ped) - target) <= 0.65 then break end
            Wait(50)
        end
        ClearPedTasks(ped)
    end

    if tonumber(standSpot.w) then
        SetEntityHeading(ped, tonumber(standSpot.w))
    elseif location.coords then
        TaskTurnPedToFaceCoord(ped, location.coords.x, location.coords.y, location.coords.z, 600)
        Wait(650)
    end

    return true
end

local function RunLocksmithLocationAction(location)
    MoveToLocksmithStandSpot(location)
    local action = GetLocksmithLocationAction(location and location.type)
    if action then action() end
end

local function DrawLocksmithSignText(coords, lines)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()

    local text = table.concat(lines, '\n')
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function EnsureLocksmithSignThread()
    if locksmithSignThreadActive then return end
    locksmithSignThreadActive = true

    CreateThread(function()
        while #spawnedLocksmithSigns > 0 do
            local sleep = 750
            local ped = PlayerPedId()
            local pedCoords = GetEntityCoords(ped)

            for _, sign in ipairs(spawnedLocksmithSigns) do
                local coords = sign.coords
                if coords then
                    local dist = #(pedCoords - vector3(coords.x, coords.y, coords.z))
                    if dist <= 15.0 then
                        sleep = 0
                        local status = tostring(sign.shopStatus or 'open'):upper():gsub('_', ' ')
                        local lines = { 'LOCKSMITH', status }
                        if sign.shopStatus == 'on_call' and sign.onCallContact and sign.onCallContact ~= '' then
                            lines[#lines + 1] = ('CALL %s'):format(sign.onCallContact)
                        end
                        DrawLocksmithSignText(vector3(coords.x, coords.y, coords.z + 1.15), lines)
                    end
                end
            end

            Wait(sleep)
        end

        locksmithSignThreadActive = false
    end)
end

local function SpawnLocksmithLocations()
    ClearLocksmithLocations()

    local fallbackState = lib.callback.await('partay_keys:server:GetLocksmithFallbackPedState', false) or {}
    local locations = lib.callback.await('partay_keys:server:GetLocksmithLocations', false) or {}
    for _, location in ipairs(locations) do
        local coords = location.coords
        local shouldSpawn = coords ~= nil
        if location.type == 'fallback_ped' and fallbackState.visible == false then
            shouldSpawn = false
        end

        if shouldSpawn then
            local spawnProp = location.spawnProp ~= false
            local object = nil
            local canUsePoint = true

            if spawnProp then
                local model = location.model or GetLocksmithSetupProp('Workbench', 'prop_tool_bench02')
                if type(model) == 'string' then
                    model = GetHashKey(model)
                end

                if not IsModelValid(model) or not IsModelInCdimage(model) then
                    print(('[partay_keys] Invalid locksmith location model configured: %s'):format(tostring(location.model)))
                    canUsePoint = false
                else
                    lib.requestModel(model, 5000)
                    if location.isPed == true or location.type == 'fallback_ped' then
                        object = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, false)
                        SetBlockingOfNonTemporaryEvents(object, true)
                    else
                        object = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
                        SetEntityHeading(object, coords.w or 0.0)
                    end
                    FreezeEntityPosition(object, true)
                    SetEntityInvincible(object, true)
                    SetModelAsNoLongerNeeded(model)
                    spawnedLocksmithLocations[#spawnedLocksmithLocations + 1] = object
                end
            end

            if canUsePoint and location.type == 'status_sign' then
                spawnedLocksmithSigns[#spawnedLocksmithSigns + 1] = {
                    coords = coords,
                    shopStatus = location.shopStatus,
                    onCallContact = location.onCallContact
                }
                EnsureLocksmithSignThread()
            end

            if canUsePoint and location.targetable ~= false then
                local targetOption = {
                    name = ('partay_locksmith_%s_%s'):format(tostring(location.type or 'point'), tostring(location.id or #spawnedLocksmithLocations)),
                    icon = location.icon or 'fas fa-key',
                    label = location.label or locale('target_use_locksmith_point'),
                    distance = tonumber(location.distance) or 2.0,
                    onSelect = function()
                        RunLocksmithLocationAction(location)
                    end
                }

                if object then
                    exports.ox_target:addLocalEntity(object, {
                        targetOption
                    })
                else
                    local zoneId = exports.ox_target:addSphereZone({
                        coords = vector3(coords.x, coords.y, coords.z),
                        radius = math.max(0.6, tonumber(location.distance) or 2.0),
                        debug = Config.DebugMode == true,
                        options = { targetOption }
                    })
                    spawnedLocksmithZones[#spawnedLocksmithZones + 1] = zoneId
                end
            end
        end
    end
end

-- Initialize peds when player loads in or script starts
CreateThread(function()
    SpawnServicePeds()
    SpawnLocksmithLocations()
end)

RegisterNetEvent('partay_keys:client:RefreshLocksmithLocations', function()
    SpawnServicePeds()
    SpawnLocksmithLocations()
end)

RegisterNetEvent('partay_keys:client:RefreshLocksmithSetup', function()
    if PartayKeysIsActiveItemUi and PartayKeysIsActiveItemUi('locksmith_setup') then
        OpenLocksmithSetupMenu(activeLocksmithSetupMode)
    end
end)

-- [[ THE GARBAGE COLLECTOR (CRITICAL FOR LIVE REstarts) ]] --
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        ClearServicePeds()
        ClearLocksmithLocations()
        for orderId in pairs(spawnedLocksmithOrderPickups) do
            ClearLocksmithOrderPickup(orderId)
        end
        StopLocksmithSetupPlacement()
    end
end)

RegisterNUICallback('serviceShopPurchase', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    local serviceType = data.service == 'blackmarket' and 'blackmarket' or 'locksmith'
    local quantity = math.floor(tonumber(data.quantity) or 1)
    quantity = math.max(1, math.min(quantity, 99))

    if serviceType == 'blackmarket' then
        TriggerServerEvent('partay_keys:server:BuyBlackmarketItem', data.item, tonumber(data.price) or 0, quantity)
    else
        local paymentMethod = data.paymentMethod == 'bank' and 'bank' or 'cash'
        PlayLocksmithNpcStockHandoff()
        TriggerServerEvent('partay_keys:server:BuyLocksmithItem', data.item, tonumber(data.price) or 0, paymentMethod, quantity)
    end

    cb('ok')
end)

RegisterNUICallback('serviceVehicleAction', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    if not currentServiceMenuAllowsVehicles then
        Notify(locale('label_locksmith'), locale('error_locksmith_vehicle_services_unavailable'), 'error')
        cb('error')
        return
    end

    local paymentMethod = data.paymentMethod == 'bank' and 'bank' or 'cash'
    local action = data.action
    local customerId = tonumber(data.customerId)

    if customerId and customerId > 0 then
        TriggerServerEvent('partay_keys:server:CreateLocksmithInvoice', {
            customerId = customerId,
            action = action,
            plate = data.plate,
            tier = data.tier,
            netId = tonumber(data.netId) or 0
        })
        cb('ok')
        return
    end

    if action == 'recover' then
        PlayLocksmithNpcVehicleWork({ action = action, netId = tonumber(data.netId) or 0, plate = data.plate })
        TriggerServerEvent('partay_keys:server:RecoverVehicle', tonumber(data.netId) or 0, data.plate, paymentMethod)
    elseif action == 'copy' then
        PlayLocksmithNpcStockHandoff()
        TriggerServerEvent('partay_keys:server:CreatePhysicalKeyCopy', data.plate, paymentMethod)
    elseif action == 'rekey' then
        PlayLocksmithNpcVehicleWork({ action = action, netId = tonumber(data.netId) or 0, plate = data.plate })
        TriggerServerEvent('partay_keys:server:ReKeyVehicle', data.plate, paymentMethod)
    elseif action == 'upgrade' then
        PlayLocksmithNpcVehicleWork({ action = action, netId = tonumber(data.netId) or 0, plate = data.plate, tier = data.tier })
        TriggerServerEvent('partay_keys:server:UpgradeKeySystem', data.plate, data.tier, paymentMethod)
    end

    cb('ok')
end)

RegisterNUICallback('locksmithSendInvoice', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:CreateLocksmithInvoice', {
        customerId = tonumber(data.customerId),
        plate = data.plate,
        netId = tonumber(data.netId) or 0,
        services = data.services
    })
    cb('ok')
end)

RegisterNUICallback('locksmithPerformJob', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    if PlayLocksmithVehicleWork(data) then
        TriggerServerEvent('partay_keys:server:CompleteLocksmithJobWork', data.id)
    end
    cb('ok')
end)

RegisterNUICallback('locksmithRequestPayment', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    PartayKeysShowHandPropOnce('terminal', 2500)
    TriggerServerEvent('partay_keys:server:RequestLocksmithJobPayment', data.id)
    cb('ok')
end)

RegisterNUICallback('locksmithBuildStock', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    local craftSeconds = tonumber(data.craftSeconds) or 5.0
    Notify(locale('label_locksmith'), locale('info_locksmith_crafting_stock'), 'info')
    PlayConfiguredAnimation('LocksmithWorkbench', math.floor(craftSeconds * 1000))
    TriggerServerEvent('partay_keys:server:BuildLocksmithStock', data.recipeId, tonumber(data.quantity) or 1)
    cb('ok')
end)

RegisterNUICallback('locksmithOrderStock', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:OrderLocksmithStock', {
        locationName = data.locationName,
        items = data.items or {
            { item = data.item, quantity = tonumber(data.quantity) or 1 }
        }
    })
    cb('ok')
end)

RegisterNUICallback('locksmithOpenStockStorage', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    local storage = lib.callback.await('partay_keys:server:GetLocksmithStockStorage', false, data.locationName) or {}
    if storage.allowed ~= true or storage.inventory ~= 'ox' or not storage.storageId then
        Notify(locale('label_locksmith'), locale(storage.reason or 'error_inventory_unavailable'), 'error')
        cb('error')
        return
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeUI' })
    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:openInventory('stash', storage.storageId)
    else
        Notify(locale('label_locksmith'), locale('error_inventory_unavailable'), 'error')
    end
    cb('ok')
end)

RegisterNUICallback('locksmithFillShopOrder', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:FillLocksmithShopOrder', data.orderId)
    cb('ok')
end)

RegisterNUICallback('locksmithResumeStockOrder', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:ResumeLocksmithStockOrder', data.orderId)
    cb('ok')
end)

RegisterNUICallback('locksmithManageEmployee', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:ManageLocksmithEmployee', data.actionType, tonumber(data.targetId))
    cb('ok')
end)

RegisterNUICallback('locksmithSetPrice', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetLocksmithPrice', data.priceKey, tonumber(data.price))
    cb('ok')
end)

RegisterNUICallback('locksmithMoveSocietyFunds', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:MoveLocksmithSocietyFunds', data.actionType, tonumber(data.amount), data.paymentMethod)
    cb('ok')
end)

RegisterNUICallback('locksmithSetShopStatus', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetLocksmithShopStatus', data.status)
    cb('ok')
end)

RegisterNUICallback('locksmithSetOnCallContact', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetLocksmithOnCallContact', data.contact)
    cb('ok')
end)

RegisterNUICallback('locksmithSetSupplierContract', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetLocksmithSupplierContract', data.contractId)
    cb('ok')
end)

RegisterNUICallback('locksmithSetCommission', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetLocksmithCommission', tonumber(data.percent))
    cb('ok')
end)

RegisterNUICallback('locksmithPayEmployee', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:PayLocksmithEmployee', tonumber(data.targetId), tonumber(data.amount))
    cb('ok')
end)

RegisterNUICallback('locksmithSetManagementPermission', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetLocksmithManagementPermission', data.permissionKey, tonumber(data.minGrade))
    cb('ok')
end)

RegisterNUICallback('locksmithManageAppointment', function(data, cb)
    if not PartayKeysValidateNuiToken('service_menu', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    local ok, result = pcall(function()
        return lib.callback.await('partay_keys:server:ManageLocksmithAppointment', false, data.appointmentId, data.actionType, data.scheduleData)
    end)

    if not ok or not result or result.ok ~= true then
        if Config.DebugMode then
            print(('[ParTay Keys Debug] Locksmith appointment action failed: %s'):format(tostring(ok and result and result.reason or result)))
        end
        cb('error')
        return
    end

    cb('ok')
end)

RegisterNUICallback('locksmithSetupPlacePoint', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    StartLocksmithSetupPlacement(data)
    cb('ok')
end)

RegisterNUICallback('locksmithSetupClearPoint', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:ClearLocksmithSetupPoint', data.locationName, data.pointType or 'all', activeLocksmithSetupMode)
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSaveStockMethod', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SaveLocksmithSetupStockMethod', data.locationName, data.stockMethod, activeLocksmithSetupMode)
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSaveLocationBlip', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SaveLocksmithLocationBlip', {
        locationName = data.locationName,
        blip = data.blip,
        setupMode = activeLocksmithSetupMode
    })
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSetLocationBlipPosition', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local blip = type(data.blip) == 'table' and data.blip or {}
    blip.coords = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = GetEntityHeading(ped)
    }
    TriggerServerEvent('partay_keys:server:SaveLocksmithLocationBlip', {
        locationName = data.locationName,
        blip = blip,
        setupMode = activeLocksmithSetupMode
    })
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSetStandSpot', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    StartLocksmithStandSpotPlacement(data)
    cb('ok')
end)

RegisterNUICallback('locksmithSetupAddRoutePoint', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    StartLocksmithRoutePointPlacement(data)
    cb('ok')
end)

RegisterNUICallback('locksmithSetupClearRoute', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:ClearLocksmithSetupRoute', data.locationName, data.pointType, activeLocksmithSetupMode)
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSaveSupplierContracts', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetGlobalLocksmithSupplierContracts', data.contracts)
    cb('ok')
end)

RegisterNUICallback('locksmithSetupResetSupplierContracts', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:ResetGlobalLocksmithSupplierContracts')
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSetOrderPrice', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetLocksmithSetupOrderPrice', data.priceKey, tonumber(data.price))
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSetStaffDefaults', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetLocksmithSetupStaffDefaults', {
        defaultHireGrade = tonumber(data.defaultHireGrade),
        minEmployeeGrade = tonumber(data.minEmployeeGrade),
        maxEmployeeGrade = tonumber(data.maxEmployeeGrade),
        fireJob = data.fireJob,
        fireGrade = tonumber(data.fireGrade)
    })
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSetBlackmarketSettings', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetGlobalBlackmarketSettings', {
        enabled = data.enabled == true,
        model = data.model,
        currency = data.currency,
        showOnMap = data.showOnMap == true,
        blip = data.blip,
        coords = data.coords,
        items = data.items
    })
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSetBlackmarketPosition', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    TriggerServerEvent('partay_keys:server:SetGlobalBlackmarketSettings', {
        coords = {
            x = coords.x,
            y = coords.y,
            z = coords.z,
            w = GetEntityHeading(ped)
        }
    })
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSetWarehousePickupSettings', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetGlobalWarehousePickupSettings', {
        enabled = data.enabled == true,
        spawnPed = data.spawnPed == true,
        pedModel = data.pedModel,
        showOnMap = data.showOnMap == true,
        blip = data.blip,
        coords = data.coords
    })
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSetWarehousePickupPosition', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    TriggerServerEvent('partay_keys:server:SetGlobalWarehousePickupSettings', {
        coords = {
            x = coords.x,
            y = coords.y,
            z = coords.z,
            w = GetEntityHeading(ped)
        }
    })
    cb('ok')
end)

RegisterNUICallback('locksmithSetupSaveRecipes', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:SetGlobalLocksmithRecipes', data.recipes)
    cb('ok')
end)

RegisterNUICallback('locksmithSetupResetRecipes', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:ResetGlobalLocksmithRecipes')
    cb('ok')
end)

RegisterNUICallback('locksmithSetupFinalize', function(data, cb)
    if not PartayKeysValidateNuiToken('locksmith_setup', data and data.token) then
        Notify(locale('label_service'), locale('error_invalid_service_session'), 'error')
        cb('error')
        return
    end

    TriggerServerEvent('partay_keys:server:FinalizeLocksmithSetupLocation', {
        locationName = data.locationName,
        shopType = data.shopType,
        stockMethod = data.stockMethod,
        setupMode = activeLocksmithSetupMode
    })
    cb('ok')
end)

RegisterNetEvent('partay_keys:client:ConfirmLocksmithService', function(data)
    if type(data) ~= 'table' or not data.id then return end

    local actionLabels = {
        copy = locale('label_create_physical_key_copy'),
        recover = locale('label_recover_possession'),
        rekey = locale('label_rekey_vehicle'),
        upgrade = data.tierLabel and locale('label_change_key_system_tier', { tier = data.tierLabel }) or locale('label_change_key_system')
    }

    local input = lib.inputDialog(locale('label_locksmith'), {
        {
            type = 'select',
            label = ('%s | %s | $%s'):format(actionLabels[data.action] or locale('label_vehicle_service'), data.plate or 'UNKNOWN', tostring(data.fee or 0)),
            description = locale('input_locksmith_service_payment_description', { name = data.employeeName or locale('label_locksmith') }),
            required = true,
            options = {
                { value = 'cash', label = locale('label_cash') },
                { value = 'bank', label = locale('label_bank') }
            }
        }
    })

    if not input then
        TriggerServerEvent('partay_keys:server:ConfirmLocksmithService', data.id, false)
        return
    end

    TriggerServerEvent('partay_keys:server:ConfirmLocksmithService', data.id, true, input[1])
end)

RegisterNetEvent('partay_keys:client:ConfirmLocksmithInvoice', function(data)
    if type(data) ~= 'table' or not data.id then return end

    PartayKeysShowHandPropOnce('clipboard', 4500)
    PlayConfiguredAnimation('LocksmithInvoice', 1500)

    local serviceLines = {}
    for _, service in ipairs(data.services or {}) do
        local label = service.action == 'copy' and locale('label_physical_key_copy')
            or service.action == 'recover' and locale('label_recover_possession')
            or service.action == 'rekey' and locale('label_rekey_vehicle')
            or service.action == 'upgrade' and locale('label_key_system_tier', { tier = tostring(service.tierLabel or service.tier or locale('label_change')) })
            or locale('label_vehicle_service')
        serviceLines[#serviceLines + 1] = ('%s - $%s'):format(label, tostring(service.fee or 0))
    end

    local approved = lib.alertDialog({
        header = locale('label_locksmith'),
        content = locale('dialog_locksmith_invoice_approval', {
            employee = data.employeeName or locale('label_locksmith'),
            vehicle = data.label or locale('label_vehicle'),
            plate = data.plate or 'UNKNOWN',
            services = table.concat(serviceLines, '\n'),
            total = tostring(data.total or 0)
        }),
        centered = true,
        cancel = true,
        labels = {
            confirm = locale('button_approve'),
            cancel = locale('button_reject')
        }
    })

    TriggerServerEvent('partay_keys:server:ConfirmLocksmithService', data.id, approved == 'confirm')
end)

RegisterNetEvent('partay_keys:client:LocksmithJobApproved', function(data)
    if type(data) ~= 'table' then return end
    SendNUIMessage({
        action = 'locksmithJobApproved',
        job = data
    })
end)

RegisterNetEvent('partay_keys:client:PayLocksmithInvoice', function(data)
    if type(data) ~= 'table' or not data.id then return end

    PartayKeysShowHandPropOnce('terminal', 5000)
    PlayConfiguredAnimation('LocksmithPayment', 1200)

    local input = lib.inputDialog(locale('label_locksmith'), {
        {
            type = 'select',
            label = locale('input_pay_locksmith_invoice', {
                vehicle = data.label or locale('label_vehicle'),
                plate = data.plate or 'UNKNOWN',
                total = tostring(data.total or 0)
            }),
            description = locale('input_locksmith_payment_description', { name = data.employeeName or locale('label_locksmith') }),
            required = true,
            options = {
                { value = 'cash', label = locale('label_cash') },
                { value = 'bank', label = locale('label_bank') }
            }
        }
    })

    if not input then
        TriggerServerEvent('partay_keys:server:PayLocksmithInvoice', data.id, false)
        return
    end

    TriggerServerEvent('partay_keys:server:PayLocksmithInvoice', data.id, true, input[1])
end)

RegisterNetEvent('partay_keys:client:RunConfirmedLocksmithService', function(data)
    if type(data) ~= 'table' then return end

    local services = data.services or { data }
    for _, service in ipairs(services) do
        if service.action == 'recover' then
            TriggerServerEvent('partay_keys:server:RecoverVehicle', tonumber(data.netId) or 0, data.plate, data.paymentMethod)
        elseif service.action == 'copy' then
            TriggerServerEvent('partay_keys:server:CreatePhysicalKeyCopy', data.plate, data.paymentMethod)
        elseif service.action == 'rekey' then
            TriggerServerEvent('partay_keys:server:ReKeyVehicle', data.plate, data.paymentMethod)
        elseif service.action == 'upgrade' then
            TriggerServerEvent('partay_keys:server:UpgradeKeySystem', data.plate, service.tier or data.tier, data.paymentMethod)
        end
        Wait(500)
    end
end)
