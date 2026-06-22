-- Server-Side Execution Only
if not IsDuplicityVersion() then return end

-- [[ The Sale Interceptor ]] --
local DEFAULT_DEALERSHIP_PROVIDERS = {
    qbx = {
        Resource = { 'qbx_vehiclesales', 'qbx_vehicleshop' },
        Events = {
            'qbx_vehicleshop:buyVehicle',
            'qbx_vehicleshop:purchaseVehicle',
            'qbx_vehicleshop:server:buyVehicle',
            'qbx_vehicleshop:server:purchaseVehicle',
            'qbx_vehicleshop:server:financeVehicle',
            'qbx_vehiclesales:server:purchaseVehicle'
        }
    },
    qb = {
        Resource = 'qb-vehicleshop',
        Events = {
            'qb-vehicleshop:server:buyShowroomVehicle',
            'qb-vehicleshop:server:buyVehicle',
            'qb-vehicleshop:server:purchaseVehicle',
            'qb-vehicleshop:server:financeVehicle'
        }
    },
    esx = {
        Resource = 'esx_vehicleshop',
        Events = {
            'esx_vehicleshop:buyVehicle',
            'esx_vehicleshop:purchaseVehicle',
            'esx_vehicleshop:setVehicleOwned',
            'esx_vehicleshop:server:buyVehicle',
            'esx_vehicleshop:server:purchaseVehicle'
        }
    },
    jg = {
        Resource = { 'jg-dealerships', 'jg_dealership' },
        Events = {
            'jg_dealership:BuyVehicle',
            'jg_dealership:PurchaseVehicle',
            'jg_dealership:server:BuyVehicle',
            'jg_dealership:server:PurchaseVehicle',
            'jg-dealerships:server:purchase-vehicle:config',
            'jg-dealerships:server:purchase-vehicle',
            'jg-dealerships:server:purchaseVehicle'
        }
    }
}

local function TrimPlate(plate)
    return plate and plate:gsub('^%s*(.-)%s*$', '%1') or nil
end

local function GetDealershipConfig()
    return Config.Integrations and Config.Integrations.Dealership or {}
end

local function DetectDealershipProviders()
    local cfg = GetDealershipConfig()
    local selected = cfg.Provider or 'auto'

    if selected == 'disabled' then return {} end
    if selected ~= 'auto' then return { selected } end

    return { 'qbx', 'qb', 'esx', 'jg' }
end

local function IsResourceStarted(resourceName)
    if type(resourceName) == 'table' then
        for _, name in ipairs(resourceName) do
            if GetResourceState(name) == 'started' then return true end
        end
        return false
    end

    return type(resourceName) == 'string' and resourceName ~= '' and GetResourceState(resourceName) == 'started'
end

local function DetectRunningDealershipProviders()
    local cfg = GetDealershipConfig()
    local selected = cfg.Provider or 'auto'
    if selected == 'disabled' then return {} end
    if selected ~= 'auto' then return { selected } end

    local providers = {}
    for _, provider in ipairs({ 'qbx', 'qb', 'esx', 'jg' }) do
        local providerCfg = (cfg.Providers or DEFAULT_DEALERSHIP_PROVIDERS)[provider]
        if providerCfg and IsResourceStarted(providerCfg.Resource) then
            providers[#providers + 1] = provider
        end
    end

    if cfg.Custom and IsResourceStarted(cfg.Custom.Resource) then
        providers[#providers + 1] = 'custom'
    end

    return providers
end

local function GetDealershipEvents()
    local cfg = GetDealershipConfig()
    local events = {}
    local seen = {}

    local function addEvent(eventName)
        if type(eventName) ~= 'string' or eventName == '' or seen[eventName] then return end
        seen[eventName] = true
        events[#events + 1] = eventName
    end

    for _, provider in ipairs(DetectDealershipProviders()) do
        local providerCfg = provider == 'custom' and cfg.Custom or ((cfg.Providers or DEFAULT_DEALERSHIP_PROVIDERS)[provider])
        for _, eventName in ipairs((providerCfg and providerCfg.Events) or {}) do
            addEvent(eventName)
        end
    end

    for _, eventName in ipairs((cfg.Custom and cfg.Custom.Events) or {}) do
        addEvent(eventName)
    end

    return events
end

local function QuoteIdentifier(identifier)
    identifier = tostring(identifier or '')
    if not identifier:match('^[%w_]+$') then
        error(('ERR_DB_IDENTIFIER - Unsafe dealership SQL identifier requested: %s'):format(identifier))
    end

    return ('`%s`'):format(identifier)
end

function Bridge.CanVehicleBeSold(plate)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return false end

    local tableName = (Bridge.GetFramework() == 'esx') and 'owned_vehicles' or 'player_vehicles'
    local ownerColumn = (Bridge.GetFramework() == 'esx') and 'owner' or 'citizenid'
    local row = MySQL.Sync.fetchAll(('SELECT %s, possession_id FROM %s WHERE plate = ? LIMIT 1'):format(QuoteIdentifier(ownerColumn), QuoteIdentifier(tableName)), {plate})
    row = row and row[1]
    if not row then return true end

    return row.possession_id == nil or row.possession_id == '' or row.possession_id == row[ownerColumn]
end

function CanVehicleBeSold(plate)
    return Bridge.CanVehicleBeSold(plate)
end

exports('CanVehicleBeSold', CanVehicleBeSold)

local function ParseDealershipPurchaseArgs(args)
    local plate, model, buyer

    local function tryFields(data)
        if not data or type(data) ~= 'table' then return end
        buyer = buyer or data.source or data.src or data.playerId or data.player or data.buyer or data.buyerId or data.target or data.targetId
        plate = plate or data.plate or data.plateText or data.plate_number or data.plateNumber or data.vehicle_plate or data.registration or data.vehiclePlate
        model = model or data.model or data.vehicle or data.name or data.vehicleModel or data.modelName or data.veh or data.displayName or data.label

        if data.props and type(data.props) == 'table' then
            plate = plate or data.props.plate
            model = model or data.props.model
        end
        if data.vehicleProps and type(data.vehicleProps) == 'table' then
            plate = plate or data.vehicleProps.plate
            model = model or data.vehicleProps.model
        end
        if data.vehicleData and type(data.vehicleData) == 'table' then
            tryFields(data.vehicleData)
        end
        if data.vehicleInfo and type(data.vehicleInfo) == 'table' then
            tryFields(data.vehicleInfo)
        end
    end

    if type(args[1]) == 'table' then
        tryFields(args[1])
        if not plate or not model then
            for _, arg in ipairs(args[1]) do
                if type(arg) == 'table' then
                    tryFields(arg)
                end
            end
        end
    elseif type(args[1]) == 'string' then
        plate = args[1]
        model = tostring(args[2] or '')
    elseif type(args[1]) == 'number' then
        buyer = args[1]
        if type(args[2]) == 'string' then
            plate = args[2]
            model = tostring(args[3] or '')
        elseif type(args[2]) == 'table' then
            tryFields(args[2])
        end
    end

    if not plate or not buyer then
        for _, arg in ipairs(args) do
            if type(arg) == 'table' then
                tryFields(arg)
            elseif not plate and type(arg) == 'string' then
                plate = arg
            elseif not buyer and type(arg) == 'number' then
                buyer = arg
            end
        end
    end

    return tonumber(buyer), TrimPlate(plate), model
end

local function HandleDealershipPurchase(src, ...)
    local buyer, plate, model = ParseDealershipPurchaseArgs({...})
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then
        src = buyer
    end

    if Config.DebugMode then
        print(('[ParTay Keys Debug] Dealership purchase event from %s -> plate=%s model=%s payload=%s'):format(
            tostring(src), tostring(plate), tostring(model), json.encode({...})
        ))
    end
    if not src or not plate or plate == '' then return end
    TriggerEvent('partay_keys:server:RegisterVehiclePurchaseFromBridge', src, plate, model)
end

local function RegisterDealershipEvent(eventName)
    RegisterNetEvent(eventName, function(...)
        HandleDealershipPurchase(source, ...)
    end)
end

local registeredEvents = GetDealershipEvents()
for _, eventName in ipairs(registeredEvents) do
    RegisterDealershipEvent(eventName)
end

function GetDealershipProvider()
    local runningProviders = DetectRunningDealershipProviders()
    if #runningProviders > 0 then
        return table.concat(runningProviders, ',')
    end

    return 'none'
end

exports('GetDealershipProvider', GetDealershipProvider)

function GetRegisteredDealershipEvents()
    return registeredEvents
end

exports('GetRegisteredDealershipEvents', GetRegisteredDealershipEvents)

CreateThread(function()
    Wait(1000)
    if Config.DebugMode then
        print(('[ParTay Keys Debug] Dealership provider selected: %s; events: %s'):format(
            GetDealershipProvider(),
            table.concat(registeredEvents, ', ')
        ))
    end
end)
