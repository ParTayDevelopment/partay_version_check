-- [[ ParTay Keys - Core Server Logic ]] --

ActiveHeists = {}
PendingSales = {}
PendingLocksmithServices = {}
ConfirmedLocksmithServices = {}
PendingLocksmithInvoices = {}
ActiveLocksmithJobs = {}
LocksmithHeldKeys = {}
ActiveLocksmithStockOrders = {}
ActiveLocksmithShopPickups = {}
ActiveLocksmithShopOrderCollections = ActiveLocksmithShopOrderCollections or {}
local NpcVehicleRobberyCooldowns = {}
local locksmithServiceNames = {
    copy = 'Copy',
    recover = 'Recover',
    rekey = 'ReKey',
    upgrade = 'KeyTiers'
}

local LOCKED = 2
local UNLOCKED = 1

if lib and lib.locale then
    lib.locale()
end

local function T(localeKey, vars)
    if type(locale) ~= 'function' then return localeKey end

    local ok, value = pcall(locale, localeKey, vars)
    return ok and value or localeKey
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

-- Expected response can be plain text "1.0.0", JSON like {"version":"1.0.0","url":"https://github.com/..."},
-- or the raw fxmanifest.lua from the public release repository.
local VERSION_CHECK_URL = 'https://raw.githubusercontent.com/ParTayDevelopment/partay_version_check/main/versions/partay_keys.json'
local VERSION_CHECK_PROJECT_URL = 'https://github.com/ParTayDevelopment/partay_resources/tree/main/partay_keys'
local VERSION_CHECK_CURRENT_VERSION = '1.0.0'

local function GetVehicleRegistrationForOwner(plate, citizenId)
    plate = TrimPlate(plate)
    if not plate or plate == '' or not citizenId then return nil end
    local storage = GetVehicleStorage()
    local rows = MySQL.Sync.fetchAll(('SELECT * FROM %s WHERE plate = ? AND %s = ? LIMIT 1'):format(storage.tableSql, storage.ownerSql), {plate, citizenId})
    return rows and rows[1] or nil
end

local function GetPlayerDistanceToEntity(src, entity)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not entity or entity == 0 then return 999999.0 end
    return #(GetEntityCoords(ped) - GetEntityCoords(entity))
end

local function IsVehicleEmpty(vehicle)
    if not vehicle or vehicle == 0 then return false end

    local driverOk, driver = pcall(GetPedInVehicleSeat, vehicle, -1)
    if driverOk and driver and driver ~= 0 then
        return false
    end

    local passengersOk, passengers = pcall(GetVehicleNumberOfPassengers, vehicle)
    if passengersOk and tonumber(passengers) and tonumber(passengers) > 0 then
        return false
    end

    return true
end

local function IsPlayerPedEntity(entity)
    if not entity or entity == 0 then return false end

    for _, playerId in ipairs(GetPlayers()) do
        local playerPed = GetPlayerPed(tonumber(playerId))
        if playerPed and playerPed ~= 0 and playerPed == entity then
            return true
        end
    end

    return false
end

local function IsNpcVehicleRobberyEnabled()
    local robbery = Config.Heist and Config.Heist.NPCVehicles and Config.Heist.NPCVehicles.Robbery
    return robbery and robbery.Enabled == true and robbery.GunpointEnabled == true, robbery
end

local function DebugNpcRobberyServer(message)
    if not Config or not Config.DebugMode then return end
    print(('^5[ParTay Keys Debug]^3 NPC Robbery SV: %s^0'):format(tostring(message)))
end

local function IsLocksmithEnabled()
    return Config.PlayerJobs
        and Config.PlayerJobs.Locksmith
        and Config.PlayerJobs.Locksmith.Enabled == true
end

local function GetLocksmithSelfServiceDefaults()
    return Config.PlayerJobDefaults
        and Config.PlayerJobDefaults.Locksmith
        and Config.PlayerJobDefaults.Locksmith.SelfService
        or {}
end

local function GetLocksmithDefaultServiceFee(serviceAction)
    local fees = GetLocksmithSelfServiceDefaults().ServiceFees or {}
    if serviceAction == 'copy' then return tonumber(fees.Copy) or 0 end
    if serviceAction == 'recover' then return tonumber(fees.Recover) or 0 end
    if serviceAction == 'rekey' then return tonumber(fees.ReKey) or 0 end
    return 0
end

local function IsLocksmithKeyTierServiceEnabled()
    local selfService = GetLocksmithSelfServiceDefaults()

    return IsLocksmithEnabled()
        and selfService.EnableKeyTierServices ~= false
end

local function GetLocksmithPlayerRunConfig()
    local playerRun = Config.PlayerJobs and Config.PlayerJobs.Locksmith
    if not playerRun or playerRun.Enabled ~= true then return nil end

    return playerRun
end

local function NormalizeJobName(value)
    return tostring(value or ''):lower():gsub('^%s*(.-)%s*$', '%1')
end

local function JobMatches(job, configuredJobName)
    local target = NormalizeJobName(configuredJobName)
    if target == '' or not job then return false end

    return NormalizeJobName(job.name) == target or NormalizeJobName(job.label) == target
end

local locksmithRuntimeJobCache = {
    active = {},
    all = {},
    loaded = false
}

local function IsActiveDbValue(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    if tonumber(value) ~= nil then return tonumber(value) == 1 end
    value = tostring(value):lower():gsub('^%s*(.-)%s*$', '%1')
    return value == 'true' or value == 'yes' or value == 'on'
end

local function RefreshLocksmithRuntimeJobCache(reason)
    local allJobs, activeJobs, allSeen, activeSeen = {}, {}, {}, {}

    local ok, rows = pcall(function()
        return MySQL.Sync.fetchAll([[
            SELECT location_name, job_name, MAX(CASE WHEN active = 1 THEN 1 ELSE 0 END) AS active
            FROM partay_locksmith_locations
            WHERE shop_type = 'player_owned' AND job_name IS NOT NULL AND job_name <> ''
            GROUP BY location_name, job_name
        ]], {}) or {}
    end)

    if ok then
        for _, row in ipairs(rows or {}) do
            local jobName = tostring(row.job_name or ''):gsub('^%s*(.-)%s*$', '%1')
            local normalized = NormalizeJobName(jobName)
            if normalized ~= '' then
                if not allSeen[normalized] then
                    allSeen[normalized] = true
                    allJobs[#allJobs + 1] = jobName
                end

                if IsActiveDbValue(row.active) and not activeSeen[normalized] then
                    activeSeen[normalized] = true
                    activeJobs[#activeJobs + 1] = jobName
                end
            end
        end
    elseif Config.DebugMode then
        print(('[ParTay Keys Debug] Locksmith job cache refresh failed%s.'):format(reason and (' during ' .. tostring(reason)) or ''))
    end

    locksmithRuntimeJobCache.active = activeJobs
    locksmithRuntimeJobCache.all = allJobs
    locksmithRuntimeJobCache.loaded = ok == true

    if Config.DebugMode then
        print(('[ParTay Keys Debug] Locksmith job cache refreshed%s: active=%s all=%s'):format(
            reason and (' (' .. tostring(reason) .. ')') or '',
            json.encode(activeJobs),
            json.encode(allJobs)
        ))
    end
end

local function GetLocksmithRuntimeJobNames(includeDrafts)
    if locksmithRuntimeJobCache.loaded ~= true then
        RefreshLocksmithRuntimeJobCache('lazy_load')
    end

    local source = includeDrafts == true and locksmithRuntimeJobCache.all or locksmithRuntimeJobCache.active
    local jobs = {}
    for index, jobName in ipairs(source or {}) do
        jobs[index] = jobName
    end

    return jobs
end

local function IsPlayerLocksmithEmployee(src)
    local playerRun = GetLocksmithPlayerRunConfig()
    if not playerRun then return false end

    local job = Bridge.GetPlayerJob(src)
    if not job or not job.name then return false end

    for _, jobName in ipairs(GetLocksmithRuntimeJobNames(false)) do
        if JobMatches(job, jobName) and (playerRun.RequireDuty == false or job.onduty ~= false) then
            return true
        end
    end

    if Config.DebugMode then
        print(('[ParTay Keys Debug] Locksmith employee check failed: src=%s job=%s label=%s onduty=%s activeJobs=%s allJobs=%s requireDuty=%s'):format(
            tostring(src),
            tostring(job.name),
            tostring(job.label),
            tostring(job.onduty),
            json.encode(GetLocksmithRuntimeJobNames(false)),
            json.encode(GetLocksmithRuntimeJobNames(true)),
            tostring(playerRun.RequireDuty ~= false)
        ))
    end

    return false
end

local function CountOnlineLocksmithEmployees()
    local playerRun = GetLocksmithPlayerRunConfig()
    if not playerRun then return 0 end

    return Bridge.CountOnlineJobs(GetLocksmithRuntimeJobNames(false), playerRun.RequireDuty ~= false)
end

local function GetJobGradeLevel(job)
    if not job then return 0 end

    if job.gradeLevel ~= nil then
        return tonumber(job.gradeLevel) or 0
    end

    local grade = job.grade
    if type(grade) == 'table' then
        grade = grade.level or grade.grade or grade.name
    end

    return tonumber(grade) or 0
end

local function GetJobGradeName(job)
    if not job then return nil end
    if job.gradeName then return tostring(job.gradeName):lower() end

    local grade = job.grade
    if type(grade) == 'table' and grade.name then
        return tostring(grade.name):lower()
    end

    if type(grade) == 'string' then
        return grade:lower()
    end

    return nil
end

local GetLocksmithStockingConfig
local GetLocksmithPrice
local GetLocksmithBusinessLocationName
local GetLocksmithBusinessSetting
local ResolveLocksmithGarageMode

local function GetLocksmithServicePermissionDefaults()
    return Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.ServicePermissions or {}
end

local function GetLocksmithServiceRule(serviceName, locationName)
    local defaults = GetLocksmithServicePermissionDefaults()[serviceName] or { Enabled = true, MinGrade = 0 }
    locationName = GetLocksmithBusinessLocationName and GetLocksmithBusinessLocationName(locationName) or nil

    local enabled = defaults.Enabled ~= false
    local minGrade = tonumber(defaults.MinGrade) or 0
    if GetLocksmithBusinessSetting and locationName then
        minGrade = tonumber(GetLocksmithBusinessSetting(('permission_Service%s_min_grade'):format(serviceName), minGrade, locationName)) or minGrade
    end

    return {
        Enabled = enabled,
        MinGrade = minGrade,
        Label = defaults.Label or serviceName
    }
end

local function CanEmployeePerformLocksmithService(src, serviceName)
    local playerRun = GetLocksmithPlayerRunConfig()
    if not playerRun then return false, 'disabled' end

    local job = Bridge.GetPlayerJob(src)
    if not job then return false, 'job' end

    local validJob = false
    for _, jobName in ipairs(GetLocksmithRuntimeJobNames(false)) do
        if JobMatches(job, jobName) then
            validJob = true
            break
        end
    end

    if not validJob then return false, 'job' end
    if playerRun.RequireDuty ~= false and job.onduty == false then return false, 'duty' end

    local rule = GetLocksmithServiceRule(serviceName, src)
    if rule.Enabled == false then return false, 'service_disabled' end
    if GetJobGradeLevel(job) < (tonumber(rule.MinGrade) or 0) then return false, 'grade' end

    return true, 'employee'
end

local function GetLocksmithBusinessConfig()
    local playerRun = GetLocksmithPlayerRunConfig()
    local business = playerRun and playerRun.Business
    if not business or business.Enabled ~= true then return nil end
    return business
end

local function NormalizeLocksmithLocationName(locationName)
    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    return locationName ~= '' and locationName or 'Main Locksmith'
end

local function GetLocksmithJobLocationName(srcOrJob, includeDrafts)
    local job = type(srcOrJob) == 'number' and Bridge.GetPlayerJob(srcOrJob) or srcOrJob
    if not job or not job.name then return nil end

    local rows = {}
    pcall(function()
        local query = [[
            SELECT DISTINCT location_name, job_name, active
            FROM partay_locksmith_locations
            WHERE shop_type = 'player_owned' AND job_name IS NOT NULL AND job_name <> ''
        ]]
        if includeDrafts ~= true then
            query = query .. ' AND active = 1'
        end
        query = query .. ' ORDER BY active DESC, location_name ASC'
        rows = MySQL.Sync.fetchAll(query, {}) or {}
    end)

    for _, row in ipairs(rows or {}) do
        if JobMatches(job, row.job_name) then
            return NormalizeLocksmithLocationName(row.location_name)
        end
    end

    return nil
end

GetLocksmithBusinessLocationName = function(srcOrLocation, includeDrafts)
    if type(srcOrLocation) == 'string' and srcOrLocation ~= '' then
        return NormalizeLocksmithLocationName(srcOrLocation)
    end

    return GetLocksmithJobLocationName(srcOrLocation, includeDrafts) or 'Main Locksmith'
end

GetLocksmithBusinessSetting = function(key, fallback, locationName)
    locationName = GetLocksmithBusinessLocationName(locationName)
    local value = nil
    pcall(function()
        value = MySQL.Sync.fetchScalar('SELECT setting_value FROM partay_locksmith_settings WHERE location_name = ? AND setting_key = ? LIMIT 1', { locationName, key })
    end)
    if value == nil or value == '' then return fallback end
    return value
end

local function SetLocksmithBusinessSetting(key, value, src, locationName)
    locationName = GetLocksmithBusinessLocationName(locationName or src, true)
    MySQL.Sync.execute([[
        INSERT INTO partay_locksmith_settings (location_name, setting_key, setting_value, updated_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            setting_value = VALUES(setting_value),
            updated_by = VALUES(updated_by),
            updated_at = CURRENT_TIMESTAMP
    ]], { locationName, key, tostring(value or ''), src and Bridge.GetCitizenID(src) or nil })
end

local function GetLocksmithGlobalBusinessSetting(key, fallback)
    return GetLocksmithBusinessSetting(key, fallback, '__global')
end

local function SetLocksmithGlobalBusinessSetting(key, value, src)
    SetLocksmithBusinessSetting(key, value, src, '__global')
end

local function GetLocksmithStaffDefaults()
    local defaults = Config.PlayerJobDefaults
        and Config.PlayerJobDefaults.Locksmith
        and Config.PlayerJobDefaults.Locksmith.StaffDefaults
        or {}

    local minGrade = math.max(0, math.floor(tonumber(GetLocksmithGlobalBusinessSetting('staff_min_employee_grade', defaults.MinEmployeeGrade or 0)) or 0))
    local maxGrade = math.max(minGrade, math.floor(tonumber(GetLocksmithGlobalBusinessSetting('staff_max_employee_grade', defaults.MaxEmployeeGrade or 4)) or 4))
    local defaultHireGrade = math.max(minGrade, math.min(maxGrade, math.floor(tonumber(GetLocksmithGlobalBusinessSetting('staff_default_hire_grade', defaults.DefaultHireGrade or minGrade)) or minGrade)))
    local fireGrade = math.max(0, math.floor(tonumber(GetLocksmithGlobalBusinessSetting('staff_fire_grade', defaults.FireGrade or 0)) or 0))

    return {
        defaultHireGrade = defaultHireGrade,
        minEmployeeGrade = minGrade,
        maxEmployeeGrade = maxGrade,
        fireJob = tostring(GetLocksmithGlobalBusinessSetting('staff_fire_job', defaults.FireJob or 'unemployed') or 'unemployed'),
        fireGrade = fireGrade
    }
end

local SortLocksmithSupplierContracts

local function GetDefaultLocksmithSupplierContracts()
    local business = Config.PlayerJobs and Config.PlayerJobs.Locksmith and Config.PlayerJobs.Locksmith.Business
    local stocking = business and business.Stocking or {}
    local contracts = stocking and stocking.SupplierContracts or {}
    local defaults = {}

    for contractId, contract in pairs(contracts) do
        contractId = tostring(contractId or ''):gsub('^%s*(.-)%s*$', '%1')
        if contractId ~= '' then
            defaults[#defaults + 1] = {
                id = contractId,
                label = contract.Label or contractId,
                description = contract.Description or '',
                priceMultiplier = tonumber(contract.PriceMultiplier) or 1.0,
                delayMultiplier = tonumber(contract.DelayMultiplier) or 1.0,
                enabled = contract.Enabled ~= false
            }
        end
    end

    SortLocksmithSupplierContracts(defaults)
    return defaults
end

SortLocksmithSupplierContracts = function(contracts)
    local priority = {
        budget = 1,
        standard = 2,
        premium = 3
    }
    table.sort(contracts, function(a, b)
        local aId = tostring(a and a.id or '')
        local bId = tostring(b and b.id or '')
        local aPriority = priority[aId] or 1000
        local bPriority = priority[bId] or 1000
        if aPriority ~= bPriority then
            return aPriority < bPriority
        end
        return aId < bId
    end)
end

local function NormalizeLocksmithSupplierContract(contract)
    if type(contract) ~= 'table' then return nil end

    local contractId = tostring(contract.id or contract.contractId or ''):lower():gsub('[^%w_%-]', '_'):gsub('^_+', ''):gsub('_+$', '')
    if contractId == '' then return nil end

    local priceMultiplier = tonumber(contract.priceMultiplier or contract.PriceMultiplier) or 1.0
    local delayMultiplier = tonumber(contract.delayMultiplier or contract.DelayMultiplier) or 1.0
    priceMultiplier = math.max(0.1, math.min(priceMultiplier, 10.0))
    delayMultiplier = math.max(0.1, math.min(delayMultiplier, 10.0))

    return {
        id = contractId:sub(1, 40),
        label = tostring(contract.label or contract.Label or contractId):gsub('^%s*(.-)%s*$', '%1'):sub(1, 80),
        description = tostring(contract.description or contract.Description or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, 180),
        priceMultiplier = priceMultiplier,
        delayMultiplier = delayMultiplier,
        enabled = contract.enabled ~= false and contract.Enabled ~= false
    }
end

local function GetEditableLocksmithSupplierContracts()
    local raw = GetLocksmithGlobalBusinessSetting('supplier_contracts_json', nil)
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            local contracts = {}
            local seen = {}
            for _, contract in ipairs(decoded) do
                local normalized = NormalizeLocksmithSupplierContract(contract)
                if normalized and not seen[normalized.id] then
                    contracts[#contracts + 1] = normalized
                    seen[normalized.id] = true
                end
            end
            if #contracts > 0 then
                SortLocksmithSupplierContracts(contracts)
                return contracts
            end
        end
    end

    return GetDefaultLocksmithSupplierContracts()
end

local function GetServicePedDefaults(name)
    return Config.ServicePedDefaults and Config.ServicePedDefaults[name] or {}
end

local function ToBool(value, default)
    if type(value) == 'boolean' then return value end
    local normalized = tostring(value or ''):lower()
    if normalized == 'true' or normalized == '1' or normalized == 'yes' or normalized == 'on' then return true end
    if normalized == 'false' or normalized == '0' or normalized == 'no' or normalized == 'off' then return false end
    return default == true
end

local function DecodeSettingsCoords(rawCoords, fallback)
    if type(rawCoords) == 'table' then return rawCoords end
    if type(rawCoords) == 'string' and rawCoords ~= '' then
        local ok, decoded = pcall(json.decode, rawCoords)
        if ok and type(decoded) == 'table' then return decoded end
    end
    return fallback
end

local function EncodeSettingsCoords(coords)
    if type(coords) ~= 'table' then return '' end
    return json.encode({
        x = tonumber(coords.x) or 0.0,
        y = tonumber(coords.y) or 0.0,
        z = tonumber(coords.z) or 0.0,
        w = tonumber(coords.w) or 0.0
    })
end

local function GetBlackmarketSettingsPayload()
    local defaults = GetServicePedDefaults('Blackmarket')
    local blipDefaults = defaults.Blip or {}
    local defaultCoords = defaults.Coords and {
        x = defaults.Coords.x,
        y = defaults.Coords.y,
        z = defaults.Coords.z,
        w = defaults.Coords.w
    } or nil
    local coords = DecodeSettingsCoords(GetLocksmithGlobalBusinessSetting('blackmarket_coords', nil), defaultCoords)
    local items = {}

    for _, item in ipairs(defaults.Items or {}) do
        local itemName = tostring(item.item or '')
        local price = tonumber(GetLocksmithGlobalBusinessSetting(('blackmarket_item_price_%s'):format(itemName), item.price or 0)) or tonumber(item.price) or 0
        items[#items + 1] = {
            item = itemName,
            label = item.label or itemName,
            price = price,
            defaultPrice = tonumber(item.price) or 0
        }
    end

    return {
        enabled = ToBool(GetLocksmithGlobalBusinessSetting('blackmarket_enabled', defaults.Enabled ~= false and 'true' or 'false'), defaults.Enabled ~= false),
        model = tostring(GetLocksmithGlobalBusinessSetting('blackmarket_model', defaults.Model or 's_m_y_dealer_01') or 's_m_y_dealer_01'),
        coords = coords,
        showOnMap = ToBool(GetLocksmithGlobalBusinessSetting('blackmarket_show_on_map', defaults.ShowOnMap ~= false and 'true' or 'false'), defaults.ShowOnMap ~= false),
        blip = {
            label = tostring(GetLocksmithGlobalBusinessSetting('blackmarket_blip_label', blipDefaults.Label or 'Blackmarket') or 'Blackmarket'),
            sprite = math.max(0, math.floor(tonumber(GetLocksmithGlobalBusinessSetting('blackmarket_blip_sprite', blipDefaults.Sprite or 378)) or 378)),
            color = math.max(0, math.floor(tonumber(GetLocksmithGlobalBusinessSetting('blackmarket_blip_color', blipDefaults.Color or 1)) or 1)),
            scale = tonumber(GetLocksmithGlobalBusinessSetting('blackmarket_blip_scale', blipDefaults.Scale or 0.75)) or 0.75
        },
        currency = tostring(GetLocksmithGlobalBusinessSetting('blackmarket_currency', defaults.Currency or 'black_money') or 'black_money'),
        items = items
    }
end

local function GetWarehousePickupSettingsPayload()
    local stocking = GetLocksmithStockingConfig() or {}
    local pickupLocations = stocking.PickupLocations or {}
    local defaultCoords = pickupLocations[1] and {
        x = pickupLocations[1].x,
        y = pickupLocations[1].y,
        z = pickupLocations[1].z,
        w = pickupLocations[1].w or 0.0
    } or nil
    local coords = DecodeSettingsCoords(GetLocksmithGlobalBusinessSetting('warehouse_pickup_coords', nil), defaultCoords)

    return {
        enabled = ToBool(GetLocksmithGlobalBusinessSetting('warehouse_pickup_enabled', coords and 'true' or 'false'), coords ~= nil),
        coords = coords,
        spawnPed = ToBool(GetLocksmithGlobalBusinessSetting('warehouse_pickup_spawn_ped', 'false'), false),
        pedModel = tostring(GetLocksmithGlobalBusinessSetting('warehouse_pickup_ped_model', GetLocksmithStockingProp('WarehousePed', 's_m_m_warehouse_01')) or GetLocksmithStockingProp('WarehousePed', 's_m_m_warehouse_01')),
        showOnMap = ToBool(GetLocksmithGlobalBusinessSetting('warehouse_pickup_show_on_map', 'false'), false),
        blip = {
            label = tostring(GetLocksmithGlobalBusinessSetting('warehouse_pickup_blip_label', 'Locksmith Warehouse') or 'Locksmith Warehouse'),
            sprite = math.max(0, math.floor(tonumber(GetLocksmithGlobalBusinessSetting('warehouse_pickup_blip_sprite', 473)) or 473)),
            color = math.max(0, math.floor(tonumber(GetLocksmithGlobalBusinessSetting('warehouse_pickup_blip_color', 5)) or 5)),
            scale = tonumber(GetLocksmithGlobalBusinessSetting('warehouse_pickup_blip_scale', 0.75)) or 0.75
        }
    }
end

local function GetLocksmithShopStatus(locationName)
    local business = GetLocksmithBusinessConfig() or {}
    local defaultStatus = business.DefaultShopStatus or 'open'
    local status = GetLocksmithBusinessSetting('shop_status', defaultStatus, locationName)
    status = tostring(status or defaultStatus):lower()
    if status ~= 'open' and status ~= 'on_call' and status ~= 'closed' then
        status = defaultStatus
    end
    return status
end

local function GetLocksmithOnCallContact(locationName)
    local business = GetLocksmithBusinessConfig() or {}
    return GetLocksmithBusinessSetting('on_call_contact', business.DefaultOnCallContact or '', locationName)
end

local function GetLocksmithSupplierContract(locationName)
    local stocking = GetLocksmithStockingConfig()
    local contracts = stocking and stocking.SupplierContracts or {}
    local defaultContract = stocking and stocking.DefaultSupplierContract or 'standard'
    local contractId = tostring(GetLocksmithBusinessSetting('supplier_contract', defaultContract, locationName) or defaultContract)
    if not contracts[contractId] then contractId = defaultContract end
    if not contracts[contractId] then contractId = next(contracts) end
    return contractId, contracts[contractId] or { Label = contractId or 'Standard Supplier', PriceMultiplier = 1.0, DelayMultiplier = 1.0 }
end

local function GetLocksmithPaymentSettings(locationName)
    local playerRun = GetLocksmithPlayerRunConfig() or {}
    local defaults = playerRun.Payment or {}
    local payment = {}
    for key, value in pairs(defaults) do
        payment[key] = value
    end

    local maxPercent = math.max(0, math.min(100, tonumber(payment.MaxCommissionPercent) or 100))
    local defaultPercent = math.max(0, math.min(maxPercent, tonumber(payment.EmployeeCommissionPercent) or 0))
    local configuredPercent = tonumber(GetLocksmithBusinessSetting('employee_commission_percent', defaultPercent, locationName))
    payment.EmployeeCommissionPercent = math.max(0, math.min(maxPercent, configuredPercent or defaultPercent))
    return payment
end

local function GetLocksmithCommissionAmount(total, payment)
    total = math.max(0, math.floor(tonumber(total) or 0))
    payment = payment or {}
    local percent = math.max(0, math.min(tonumber(payment.EmployeeCommissionPercent) or 0, tonumber(payment.MaxCommissionPercent) or 100))
    if percent <= 0 or total <= 0 then return 0 end

    local amount = math.floor(total * percent / 100)
    local maxAmount = tonumber(payment.MaxCommissionPerInvoice) or 0
    if maxAmount > 0 then amount = math.min(amount, maxAmount) end
    return math.max(0, amount)
end

local function IsPlayerLocksmithOwner(src)
    local business = GetLocksmithBusinessConfig()
    if not business then return false end

    local job = Bridge.GetPlayerJob(src)
    if not job or not job.name then return false end

    local validJob = false
    for _, jobName in ipairs(GetLocksmithRuntimeJobNames(true)) do
        if JobMatches(job, jobName) then
            validJob = true
            break
        end
    end

    if not validJob then
        if Config.DebugMode then
            print(('[ParTay Keys Debug] Locksmith owner check failed: job=%s label=%s grade=%s gradeName=%s isboss=%s configured=%s'):format(
                tostring(job.name),
                tostring(job.label),
                tostring(GetJobGradeLevel(job)),
                tostring(GetJobGradeName(job)),
                tostring(job.isboss),
                json.encode(GetLocksmithRuntimeJobNames(true))
            ))
        end
        return false
    end

    local gradeName = GetJobGradeName(job)
    if job.isboss == true or gradeName == 'owner' or gradeName == 'boss' then return true end
    if GetJobGradeLevel(job) < (tonumber(business.OwnerMinGrade) or 0) then
        if Config.DebugMode then
            print(('[ParTay Keys Debug] Locksmith owner grade failed: job=%s label=%s grade=%s gradeName=%s isboss=%s required=%s'):format(
                tostring(job.name),
                tostring(job.label),
                tostring(GetJobGradeLevel(job)),
                tostring(gradeName),
                tostring(job.isboss),
                tostring(business.OwnerMinGrade)
            ))
        end
        return false
    end
    return true
end

local locksmithManagementPermissionOrder = {
    'ServiceShop',
    'ServiceCopy',
    'ServiceRecover',
    'ServiceReKey',
    'ServiceKeyTiers',
    'ServiceGarage',
    'Payroll',
    'Candidates',
    'Reports',
    'AppointmentSchedule',
    'AppointmentComplete',
    'AppointmentCancel',
    'AppointmentReminder'
}

local locksmithManagementPermissionDefaults = {
    ServiceShop = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.ServicePermissions and Config.PlayerJobDefaults.Locksmith.ServicePermissions.Shop or {},
    ServiceCopy = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.ServicePermissions and Config.PlayerJobDefaults.Locksmith.ServicePermissions.Copy or {},
    ServiceRecover = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.ServicePermissions and Config.PlayerJobDefaults.Locksmith.ServicePermissions.Recover or {},
    ServiceReKey = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.ServicePermissions and Config.PlayerJobDefaults.Locksmith.ServicePermissions.ReKey or {},
    ServiceKeyTiers = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.ServicePermissions and Config.PlayerJobDefaults.Locksmith.ServicePermissions.KeyTiers or {},
    ServiceGarage = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.ServicePermissions and Config.PlayerJobDefaults.Locksmith.ServicePermissions.Garage or {}
}

local function GetLocksmithManagementPermissionDefinitions(locationName)
    locationName = GetLocksmithBusinessLocationName(locationName)
    local internalManagement = Config.PlayerJobDefaults
        and Config.PlayerJobDefaults.Locksmith
        and Config.PlayerJobDefaults.Locksmith.ManagementPermissions
        or {}
    local definitions = {}

    for _, key in ipairs(locksmithManagementPermissionOrder) do
        local defaults = locksmithManagementPermissionDefaults[key] or internalManagement[key] or {}
        local enabled = defaults.Enabled ~= false
        local fallbackGrade = tonumber(defaults.MinGrade) or 0
        local storedGrade = GetLocksmithBusinessSetting(('permission_%s_min_grade'):format(key), fallbackGrade, locationName)

        definitions[#definitions + 1] = {
            key = key,
            label = defaults.Label or key,
            enabled = enabled,
            minGrade = math.max(0, math.floor(tonumber(storedGrade) or fallbackGrade))
        }
    end

    return definitions
end

local function HasLocksmithManagementPermission(src, permissionKey, locationName)
    if IsPlayerLocksmithOwner(src) then return true end
    if not IsPlayerLocksmithEmployee(src) then return false end

    local job = Bridge.GetPlayerJob(src)
    local grade = GetJobGradeLevel(job)
    for _, definition in ipairs(GetLocksmithManagementPermissionDefinitions(locationName or src)) do
        if definition.key == permissionKey then
            return definition.enabled == true and grade >= (tonumber(definition.minGrade) or 0)
        end
    end

    return false
end

local function BuildLocksmithManagementPermissionsPayload(src, locationName)
    locationName = GetLocksmithBusinessLocationName(locationName or src, true)
    local definitions = GetLocksmithManagementPermissionDefinitions(locationName)
    local allowed = {}

    for _, definition in ipairs(definitions) do
        allowed[definition.key] = HasLocksmithManagementPermission(src, definition.key, locationName)
    end

    return {
        canConfigure = IsPlayerLocksmithOwner(src),
        definitions = definitions,
        allowed = allowed
    }
end

local function IsPlayerLocksmithJobMember(src)
    local playerRun = GetLocksmithPlayerRunConfig()
    if not playerRun then return false end

    local job = Bridge.GetPlayerJob(src)
    if not job or not job.name then return false end

    for _, jobName in ipairs(GetLocksmithRuntimeJobNames(true)) do
        if JobMatches(job, jobName) then return true end
    end

    return false
end

local function GetLocksmithSocietyAccount(srcOrJob)
    local jobName = nil
    if type(srcOrJob) == 'number' then
        local job = Bridge.GetPlayerJob(srcOrJob)
        if job and job.name then
            for _, configuredJob in ipairs(GetLocksmithRuntimeJobNames(true)) do
                if JobMatches(job, configuredJob) then
                    jobName = job.name
                    break
                end
            end
        end
    else
        jobName = srcOrJob
    end

    jobName = tostring(jobName or GetLocksmithRuntimeJobNames(true)[1] or ''):gsub('^%s*(.-)%s*$', '%1')
    return jobName ~= '' and jobName or 'locksmith'
end

local function IsPlayerPartayAdmin(src)
    if IsPlayerAceAllowed(src, 'command.car') then return true end

    if type(Config.AdminGroup) == 'table' then
        for _, group in ipairs(Config.AdminGroup) do
            if IsPlayerAceAllowed(src, group) then return true end
        end
    elseif IsPlayerAceAllowed(src, Config.AdminGroup or 'group.admin') then
        return true
    end

    return false
end

local function GetLocksmithSetupConfig()
    local business = GetLocksmithBusinessConfig()
    if not business then return nil end

    local defaults = Config.PlayerJobDefaults
        and Config.PlayerJobDefaults.Locksmith
        or {}
    local setupDefaults = defaults.Setup or {}

    return {
        Enabled = Config.LocksmithSetupEnabled == true,
        AdminCommand = Config.LocksmithSetupAdminCommand or 'locksmithadmin',
        OwnerCommand = Config.LocksmithSetupOwnerCommand or 'locksmithowner',
        Command = Config.LocksmithSetupAdminCommand or 'locksmithadmin',
        Permission = Config.LocksmithSetupPermission,
        TargetDistance = tonumber(setupDefaults.TargetDistance) or 2.0,
        AllowExistingMloProps = setupDefaults.AllowExistingMloProps == true,
        StockMethods = defaults.SetupStockMethods or {},
        Points = defaults.SetupPoints or {}
    }
end

local function IsPlayerLocksmithSetupAdmin(src, setup)
    local permission = setup and setup.Permission or {}
    local acePermission = permission.AcePermission

    if acePermission and acePermission ~= '' and IsPlayerAceAllowed(src, acePermission) then
        return true
    end

    if permission.AllowCommandCar ~= false and IsPlayerAceAllowed(src, 'command.car') then
        return true
    end

    local groups = permission.Groups
    if groups == nil then
        groups = Config.AdminGroup
    end

    if type(groups) == 'table' then
        for _, group in ipairs(groups) do
            if IsPlayerAceAllowed(src, group) then return true end
        end
    elseif groups and IsPlayerAceAllowed(src, groups) then
        return true
    end

    return IsPlayerPartayAdmin(src)
end

local ownerSetupPointTypes = {
    workbench = true,
    management = true,
    timeclock = true,
    register = true,
    customer_pickup = true,
    stock = true,
    status_sign = true,
    garage = true,
    vehicle_spawn = true,
    delivery_spawn = true,
    delivery_dropoff = true
}

local function GetLocksmithSetupAccess(src, setup, requestedMode)
    local job = Bridge.GetPlayerJob(src)
    local jobName = job and job.name or nil
    local isAdmin = setup and setup.Enabled == true and IsPlayerLocksmithSetupAdmin(src, setup) == true
    local isOwner = setup and setup.Enabled == true and IsPlayerLocksmithOwner(src) == true
    requestedMode = tostring(requestedMode or ''):lower()
    if requestedMode == 'owner' then
        isAdmin = false
    elseif requestedMode == 'admin' then
        isOwner = false
    end

    return {
        allowed = isAdmin or isOwner,
        admin = isAdmin,
        owner = isOwner and not isAdmin,
        ownerJob = isOwner and jobName or nil
    }
end

local function CanLocksmithSetupAccessPoint(access, pointType)
    if access and access.admin then return true end
    return access and access.owner and ownerSetupPointTypes[tostring(pointType or '')] == true
end

local function GetLocksmithLocationJobName(locationName)
    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then return nil end

    local rows = MySQL.Sync.fetchAll([[
        SELECT job_name
        FROM partay_locksmith_locations
        WHERE location_name = ? AND shop_type = 'player_owned'
        LIMIT 1
    ]], { locationName }) or {}

    return rows[1] and rows[1].job_name or nil
end

local function CanLocksmithSetupAccessLocation(access, locationName)
    if access and access.admin then return true end
    if not access or not access.owner then return false end

    local ownerJob = tostring(access.ownerJob or '')
    if ownerJob == '' then return false end

    local locationJob = tostring(GetLocksmithLocationJobName(locationName) or '')
    return locationJob ~= '' and locationJob == ownerJob
end

local function LocksmithPointSupportsFramework(pointConfig)
    if type(pointConfig) ~= 'table' then return false end
    if type(pointConfig.Frameworks) ~= 'table' then return true end

    local framework = Bridge.GetFramework and Bridge.GetFramework() or 'standalone'
    return pointConfig.Frameworks[tostring(framework or ''):lower()] == true
end

local function LocksmithPointSupportsGarageMode(pointConfig)
    if type(pointConfig) ~= 'table' or not pointConfig.RequiresGarageMode then return true end
    if not ResolveLocksmithGarageMode then return true end
    local mode = ResolveLocksmithGarageMode()
    return tostring(pointConfig.RequiresGarageMode) == tostring(mode or '')
end

local function NormalizeLocksmithPointType(pointType)
    pointType = tostring(pointType or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    local setup = GetLocksmithSetupConfig()
    local points = setup and setup.Points or {}
    if points[pointType] and LocksmithPointSupportsFramework(points[pointType]) and LocksmithPointSupportsGarageMode(points[pointType]) then return pointType, points[pointType] end
    return nil, nil
end

local function HumanizeIdentifier(value)
    value = tostring(value or ''):gsub('^%s*(.-)%s*$', '%1')
    if value == '' then return nil end

    value = value:gsub('_', ' '):gsub('%s+', ' ')
    return value:gsub('(%a)([%w]*)', function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

local function ResolveDisplayLabel(rawLabel, fallbackLabel, identifier)
    rawLabel = tostring(rawLabel or ''):gsub('^%s*(.-)%s*$', '%1')
    identifier = tostring(identifier or ''):gsub('^%s*(.-)%s*$', '%1')

    if rawLabel == '' or rawLabel == identifier then
        return fallbackLabel or HumanizeIdentifier(identifier) or identifier
    end

    return rawLabel
end

local function DecodeLocksmithCoords(rawCoords)
    local decoded = type(rawCoords) == 'table' and rawCoords or nil
    if type(rawCoords) == 'string' and rawCoords ~= '' then
        local ok, result = pcall(json.decode, rawCoords)
        if ok and type(result) == 'table' then decoded = result end
    end

    if type(decoded) ~= 'table' then return nil end
    local x, y, z = tonumber(decoded.x), tonumber(decoded.y), tonumber(decoded.z)
    if not x or not y or not z then return nil end

    return vector4(x, y, z, tonumber(decoded.w) or tonumber(decoded.heading) or 0.0)
end

local function DecodeJsonObject(rawValue)
    if type(rawValue) == 'table' then return rawValue end
    if type(rawValue) ~= 'string' or rawValue == '' then return {} end

    local ok, decoded = pcall(json.decode, rawValue)
    return ok and type(decoded) == 'table' and decoded or {}
end

local function IsTruthyDbValue(value, default)
    if value == nil then return default == true end
    if value == true then return true end
    if value == false then return false end
    if tonumber(value) ~= nil then return tonumber(value) ~= 0 end
    value = tostring(value):lower():gsub('^%s*(.-)%s*$', '%1')
    if value == 'false' or value == 'no' or value == 'off' or value == '0' then return false end
    if value == 'true' or value == 'yes' or value == 'on' or value == '1' then return true end
    return default == true
end

local function NormalizeLocksmithLocationBlip(blip, locationName)
    blip = type(blip) == 'table' and blip or {}
    locationName = tostring(locationName or 'Locksmith'):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then locationName = 'Locksmith' end

    local coords = type(blip.coords) == 'table' and blip.coords or nil
    if coords then
        coords = {
            x = tonumber(coords.x) or 0.0,
            y = tonumber(coords.y) or 0.0,
            z = tonumber(coords.z) or 0.0,
            w = tonumber(coords.w) or tonumber(coords.heading) or 0.0
        }
    end

    return {
        enabled = ToBool(blip.enabled, false),
        label = tostring(blip.label or locationName):gsub('^%s*(.-)%s*$', '%1'):sub(1, 40),
        sprite = math.max(0, math.floor(tonumber(blip.sprite) or 402)),
        color = math.max(0, math.floor(tonumber(blip.color) or 2)),
        scale = math.max(0.1, tonumber(blip.scale) or 0.75),
        shortRange = ToBool(blip.shortRange, true),
        coords = coords
    }
end

local function GetLocksmithLocationBlipSettings(locationName)
    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then return NormalizeLocksmithLocationBlip(nil, 'Locksmith') end

    local rows = MySQL.Sync.fetchAll([[
        SELECT stock_settings
        FROM partay_locksmith_locations
        WHERE location_name = ?
        ORDER BY id ASC
    ]], { locationName }) or {}

    for _, row in ipairs(rows) do
        local settings = DecodeJsonObject(row.stock_settings)
        if type(settings.locationBlip) == 'table' then
            return NormalizeLocksmithLocationBlip(settings.locationBlip, locationName)
        end
    end

    return NormalizeLocksmithLocationBlip(nil, locationName)
end

GetLocksmithStockingConfig = function()
    local business = GetLocksmithBusinessConfig()
    local stocking = business and business.Stocking
    if not stocking or stocking.Enabled == false then return nil end

    local effective = {}
    for key, value in pairs(stocking) do
        effective[key] = value
    end

    local contracts = {}
    for _, contract in ipairs(GetEditableLocksmithSupplierContracts()) do
        if contract.enabled ~= false then
            contracts[contract.id] = {
                Label = contract.label,
                Description = contract.description,
                PriceMultiplier = contract.priceMultiplier,
                DelayMultiplier = contract.delayMultiplier,
                Enabled = true
            }
        end
    end
    if next(contracts) then
        effective.SupplierContracts = contracts
        if not contracts[effective.DefaultSupplierContract] then
            effective.DefaultSupplierContract = next(contracts)
        end
    end

    return effective
end

local function NormalizeStockMethod(method)
    method = tostring(method or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    local setup = GetLocksmithSetupConfig()
    local methods = setup and setup.StockMethods or {}

    if method ~= '' and methods[method] and methods[method].Enabled ~= false then
        return method, methods[method]
    end

    local fallback = 'auto'
    if methods[fallback] and methods[fallback].Enabled ~= false then
        return fallback, methods[fallback]
    end

    return 'auto', { Label = 'Automatic Insert', Description = 'Stock inserts immediately.' }
end

local function GetLocksmithStockMethodConfig(method)
    method = tostring(method or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    local setup = GetLocksmithSetupConfig()
    local methods = setup and setup.StockMethods or {}
    if method ~= '' and methods[method] and methods[method].Enabled ~= false then
        return method, methods[method]
    end
    return nil, nil
end

local function NormalizeLocksmithShopType(shopType)
    shopType = tostring(shopType or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    if shopType == 'self_service' or shopType == 'self-service' or shopType == 'selfservice' then
        return 'self_service'
    end

    return 'player_owned'
end

local function LocksmithPointSupportsShopType(pointType, shopType)
    shopType = NormalizeLocksmithShopType(shopType)
    pointType = tostring(pointType or ''):lower()

    if shopType == 'self_service' then
        return pointType == 'fallback_ped'
    end

    return pointType ~= 'fallback_ped'
end

local function GetLocksmithShopTypeDefinitions()
    return {
        {
            type = 'player_owned',
            label = 'Player Owned',
            description = 'Full business setup with employee access, workbench, management, register, stock, and optional garage points.'
        },
        {
            type = 'self_service',
            label = 'Self Service',
            description = 'Simple NPC clerk setup for automated customer service without player-owned business points.'
        }
    }
end

local function GetLocksmithLocationShopType(locationName)
    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then return 'player_owned' end

    local shopType = nil
    pcall(function()
        shopType = MySQL.Sync.fetchScalar(
            'SELECT shop_type FROM partay_locksmith_locations WHERE location_name = ? ORDER BY id ASC LIMIT 1',
            { locationName }
        )
    end)

    return NormalizeLocksmithShopType(shopType)
end

local function BuildLocksmithLocation(row)
    if type(row) ~= 'table' then return nil end
    local pointType, pointConfig = NormalizeLocksmithPointType(row.point_type or row.type)
    local coords = DecodeLocksmithCoords(row.coords)
    if not pointType or not coords then return nil end

    local shopType = NormalizeLocksmithShopType(row.shop_type or row.shopType)
    if not LocksmithPointSupportsShopType(pointType, shopType) then return nil end
    local rawStockMethod = tostring(row.stock_method or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    local active = row.active == true or tonumber(row.active) == 1
    local stockMethod, stockMethodConfig = nil, nil
    if active or rawStockMethod ~= '' then
        stockMethod, stockMethodConfig = NormalizeStockMethod(rawStockMethod)
    else
        stockMethod = ''
        stockMethodConfig = {}
    end
    local stockSettings = DecodeJsonObject(row.stock_settings)
    local coordOnly = pointConfig.CoordOnly == true

    return {
        id = tonumber(row.id),
        type = pointType,
        label = ResolveDisplayLabel(row.label, pointConfig.Label, pointType),
        locationName = row.location_name or row.locationName or 'Main Locksmith',
        shopType = shopType,
        jobName = row.job_name or row.jobName or nil,
        model = coordOnly and nil or (row.model or pointConfig.Model),
        icon = pointConfig.Icon,
        isPed = pointConfig.IsPed == true,
        coordOnly = coordOnly,
        targetable = pointConfig.Targetable ~= false,
        spawnProp = coordOnly and false or IsTruthyDbValue(row.spawn_prop, pointConfig.SpawnProp ~= false),
        coords = { x = coords.x, y = coords.y, z = coords.z, w = coords.w or 0.0 },
        distance = tonumber(row.target_distance) or tonumber((GetLocksmithSetupConfig() or {}).TargetDistance) or 2.0,
        active = active,
        stockMethod = stockMethod,
        stockMethodLabel = stockMethodConfig.Label or stockMethod,
        stockSettings = stockSettings,
        locationBlip = NormalizeLocksmithLocationBlip(stockSettings.locationBlip, row.location_name or row.locationName),
        shopStatus = GetLocksmithShopStatus(row.location_name or row.locationName),
        onCallContact = GetLocksmithOnCallContact(row.location_name or row.locationName)
    }
end

local function GetConfiguredLocksmithLocations(includeDrafts, access)
    local locations = {}
    pcall(function()
        local query = 'SELECT id, location_name, shop_type, job_name, point_type, label, model, coords, target_distance, active, spawn_prop, stock_method, stock_settings FROM partay_locksmith_locations'
        if includeDrafts ~= true then
            query = query .. ' WHERE active = 1'
        end
        query = query .. ' ORDER BY location_name ASC, id ASC'
        local rows = MySQL.Sync.fetchAll(query, {}) or {}
        for _, row in ipairs(rows) do
            local location = BuildLocksmithLocation(row)
            if location and (not access or access.admin or (access.owner and tostring(location.jobName or '') == tostring(access.ownerJob or ''))) then
                locations[#locations + 1] = location
            end
        end
    end)
    return locations
end

local function GetActiveLocksmithLocations()
    local locations = GetConfiguredLocksmithLocations(false)

    local business = GetLocksmithBusinessConfig()
    local workbench = business and business.Workbench
    if workbench and workbench.Enabled == true and workbench.Coords then
        local hasPlacedWorkbench = false
        for _, location in ipairs(locations) do
            if location.type == 'workbench' then
                hasPlacedWorkbench = true
                break
            end
        end

        if not hasPlacedWorkbench then
            locations[#locations + 1] = {
                id = 'config_workbench',
                type = 'workbench',
                label = T('target_use_locksmith_workbench'),
                model = workbench.Model or GetLocksmithSetupProp('Workbench', 'prop_tool_bench02'),
                icon = 'fas fa-screwdriver-wrench',
                coords = { x = workbench.Coords.x, y = workbench.Coords.y, z = workbench.Coords.z, w = workbench.Coords.w or 0.0 },
                distance = tonumber(workbench.TargetDistance) or 2.0,
                stockMethod = NormalizeStockMethod()
            }
        end
    end

    return locations
end

local function GetLocksmithLocationBlipCoord(locations, locationName, blip)
    if blip and type(blip.coords) == 'table' then
        return blip.coords
    end

    local preferred = {
        self_service = { 'fallback_ped' },
        player_owned = { 'management', 'register', 'workbench', 'stock' }
    }

    local fallback = nil
    for _, location in ipairs(locations or {}) do
        if location.locationName == locationName then
            fallback = fallback or location.coords
            for _, pointType in ipairs(preferred[location.shopType] or preferred.player_owned) do
                if location.type == pointType and location.coords then
                    return location.coords
                end
            end
        end
    end

    return fallback
end

local function GetLocksmithLocationBlipsPayload()
    local locations = GetConfiguredLocksmithLocations(false)
    local grouped = {}
    local payload = {}

    for _, location in ipairs(locations) do
        local locationName = location.locationName or 'Main Locksmith'
        if not grouped[locationName] then
            grouped[locationName] = true
            local blip = GetLocksmithLocationBlipSettings(locationName)
            if blip.enabled == true then
                local coords = GetLocksmithLocationBlipCoord(locations, locationName, blip)
                if coords then
                    payload[#payload + 1] = {
                        locationName = locationName,
                        coords = coords,
                        blip = blip
                    }
                end
            end
        end
    end

    return payload
end

local function GetLocksmithFallbackPedState()
    local playerRun = GetLocksmithPlayerRunConfig()
    if not playerRun then
        return {
            enabled = true,
            visible = true,
            hasPlaced = false,
            shopStatus = GetLocksmithShopStatus(),
            onlineEmployees = 0,
            minimumOnline = 0
        }
    end

    local minimumOnline = math.max(1, tonumber(playerRun.MinimumOnline) or 1)
    local onlineEmployees = CountOnlineLocksmithEmployees()
    local hasPlaced = false
    local anyOpenSelfService = false

    for _, location in ipairs(GetConfiguredLocksmithLocations(false)) do
        if location.type == 'fallback_ped' and location.shopType == 'self_service' then
            hasPlaced = true
            if GetLocksmithShopStatus(location.locationName) ~= 'closed' then
                anyOpenSelfService = true
                break
            end
        end
    end

    local visible = hasPlaced and anyOpenSelfService

    return {
        enabled = true,
        visible = visible,
        hasPlaced = hasPlaced,
        shopStatus = anyOpenSelfService and 'open' or 'closed',
        onlineEmployees = onlineEmployees,
        minimumOnline = minimumOnline
    }
end

local function GetLocksmithPointDefinitions(access)
    local setup = GetLocksmithSetupConfig()
    local definitions = {}
    for pointType, pointConfig in pairs((setup and setup.Points) or {}) do
        if LocksmithPointSupportsFramework(pointConfig) and LocksmithPointSupportsGarageMode(pointConfig) and CanLocksmithSetupAccessPoint(access or { admin = true }, pointType) then
            local shopTypes = {}
            if pointType == 'fallback_ped' then
                shopTypes.self_service = true
            else
                shopTypes.player_owned = true
            end
            definitions[#definitions + 1] = {
                type = pointType,
                label = pointConfig.Label or pointType,
                description = pointConfig.Description or '',
                routeDescription = pointConfig.RouteDescription or '',
                model = pointConfig.Model,
                icon = pointConfig.Icon,
                required = pointConfig.Required ~= false,
                requiresWith = pointConfig.RequiresWith,
                requiresStockMethod = pointConfig.RequiresStockMethod,
                subPointOf = pointConfig.SubPointOf,
                vehiclePreview = pointConfig.VehiclePreview == true,
                requiresGarageMode = pointConfig.RequiresGarageMode,
                shopTypes = shopTypes,
                isPed = pointConfig.IsPed == true,
                coordOnly = pointConfig.CoordOnly == true,
                targetable = pointConfig.Targetable ~= false,
                allowExistingProp = setup.AllowExistingMloProps == true and pointConfig.AllowExistingProp ~= false and pointConfig.IsPed ~= true,
                spawnPropDefault = pointConfig.SpawnProp ~= false
            }
        end
    end
    table.sort(definitions, function(a, b) return tostring(a.type) < tostring(b.type) end)
    return definitions
end

local function GetLocksmithStockMethodDefinitions()
    local setup = GetLocksmithSetupConfig()
    local definitions = {}
    for method, methodConfig in pairs((setup and setup.StockMethods) or {}) do
        if methodConfig.Enabled ~= false then
            definitions[#definitions + 1] = {
                method = method,
                label = methodConfig.Label or method,
                description = methodConfig.Description or ''
            }
        end
    end
    table.sort(definitions, function(a, b) return tostring(a.method) < tostring(b.method) end)
    return definitions
end

local function HasCompleteLocksmithLocation(locationName, shopType, stockMethod)
    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then return false end

    shopType = NormalizeLocksmithShopType(shopType or GetLocksmithLocationShopType(locationName))
    stockMethod = tostring(stockMethod or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    local setup = GetLocksmithSetupConfig()
    for pointType, pointConfig in pairs((setup and setup.Points) or {}) do
        if LocksmithPointSupportsShopType(pointType, shopType) and LocksmithPointSupportsFramework(pointConfig) and LocksmithPointSupportsGarageMode(pointConfig) then
            local requiresStockMethod = tostring(pointConfig.RequiresStockMethod or ''):lower():gsub('^%s*(.-)%s*$', '%1')
            local stockMethodMatches = requiresStockMethod == '' or requiresStockMethod == stockMethod

            if stockMethodMatches and pointConfig.Required ~= false then
                local count = tonumber(MySQL.Sync.fetchScalar(
                    'SELECT COUNT(*) FROM partay_locksmith_locations WHERE location_name = ? AND point_type = ? AND shop_type = ?',
                    { locationName, pointType, shopType }
                )) or 0
                if count < 1 then return false end
            end

            if stockMethodMatches and pointConfig.RequiresWith then
                local parentType = tostring(pointConfig.RequiresWith)
                local parentCount = tonumber(MySQL.Sync.fetchScalar(
                    'SELECT COUNT(*) FROM partay_locksmith_locations WHERE location_name = ? AND point_type = ? AND shop_type = ?',
                    { locationName, parentType, shopType }
                )) or 0
                if parentCount > 0 then
                    local count = tonumber(MySQL.Sync.fetchScalar(
                        'SELECT COUNT(*) FROM partay_locksmith_locations WHERE location_name = ? AND point_type = ? AND shop_type = ?',
                        { locationName, pointType, shopType }
                    )) or 0
                    if count < 1 then return false end
                end
            end
        end
    end
    return true
end

local function IsPlayerNearLocksmithLocation(src, allowedTypes, distance, requiredShopType)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local allowed = {}
    if type(allowedTypes) == 'table' then
        for _, pointType in ipairs(allowedTypes) do
            allowed[tostring(pointType)] = true
        end
    elseif allowedTypes then
        allowed[tostring(allowedTypes)] = true
    end

    local coords = GetEntityCoords(ped)
    local maxDistance = tonumber(distance) or 10.0
    requiredShopType = requiredShopType and NormalizeLocksmithShopType(requiredShopType) or nil
    for _, location in ipairs(GetActiveLocksmithLocations()) do
        if (not requiredShopType or location.shopType == requiredShopType) and (next(allowed) == nil or allowed[location.type]) then
            local loc = location.coords
            if loc and #(coords - vector3(loc.x, loc.y, loc.z)) <= maxDistance then
                return true, location
            end
        end
    end

    return false
end

local function CanUseLocksmithWorkbench(src)
    local business = GetLocksmithBusinessConfig()
    local workbench = business and business.Workbench
    if not business or not workbench or workbench.Enabled ~= true then
        return false, 'error_locksmith_workbench_unavailable'
    end

    local nearWorkbench = IsPlayerNearLocksmithLocation(src, { 'workbench' }, (tonumber(workbench.TargetDistance) or 2.0) + 2.0)
    if not nearWorkbench then
        return false, 'error_locksmith_workbench_too_far'
    end

    if IsPlayerLocksmithOwner(src) then
        return true, 'owner'
    end

    if workbench.OwnerOnly == true then
        return false, 'error_locksmith_owner_required'
    end

    local allowed, reason = CanEmployeePerformLocksmithService(src, 'Shop')
    if not allowed then
        return false, reason == 'grade' and 'error_locksmith_grade_required' or 'error_locksmith_employee_required'
    end

    local job = Bridge.GetPlayerJob(src)
    if GetJobGradeLevel(job) < (tonumber(workbench.CraftMinGrade) or 0) then
        return false, 'error_locksmith_grade_required'
    end

    return true, 'employee'
end

local function GetLocksmithGarageConfig()
    local business = GetLocksmithBusinessConfig()
    local garage = business and business.Garage
    if not garage or garage.Enabled ~= true then return nil end
    return garage
end

local BuildLocksmithGarageName

ResolveLocksmithGarageMode = function()
    local garage = GetLocksmithGarageConfig()
    if not garage then return 'disabled', 'none' end

    local configuredMode = tostring(garage.Mode or 'standalone'):lower()
    if configuredMode == 'disabled' then return 'disabled', 'none' end

    local provider = GetGarageProvider and GetGarageProvider() or 'none'
    if configuredMode == 'provider' then
        return 'provider', provider ~= '' and provider or 'none'
    end

    if configuredMode == 'auto' and provider ~= 'none' and provider ~= 'disabled' and provider ~= '' then
        return 'provider', provider
    end

    if Config.DebugMode then
        print(('[ParTay Keys Debug] Locksmith garage resolved standalone: mode=%s detectedProvider=%s'):format(
            tostring(configuredMode),
            tostring(provider)
        ))
    end

    return 'standalone', provider ~= '' and provider or 'none'
end

local function BuildLocksmithGarageSetupPayload(locationName)
    local garage = GetLocksmithGarageConfig() or {}
    local mode, provider = ResolveLocksmithGarageMode()
    local location = locationName and {
        locationName = locationName
    } or nil

    return {
        enabled = garage.Enabled == true,
        mode = mode,
        provider = provider,
        providerGarageName = BuildLocksmithGarageName(location),
        providerGarageType = garage.ProviderGarageType or 'job',
        vehiclePreviewModel = (garage.Vehicles and garage.Vehicles[1] and garage.Vehicles[1].model) or GetLocksmithSetupProp('GarageVehiclePreview', 'speedo')
    }
end

local function CanUseLocksmithGarage(src)
    local garage = GetLocksmithGarageConfig()
    if not garage then return false, 'error_locksmith_garage_unavailable' end

    local allowed, reason = CanEmployeePerformLocksmithService(src, 'Garage')
    if not allowed then
        return false, reason == 'grade' and 'error_locksmith_grade_required' or 'error_locksmith_employee_required'
    end

    if garage.RequireDuty ~= false then
        local job = Bridge.GetPlayerJob(src)
        if job and job.onduty == false then
            return false, 'error_locksmith_employee_required'
        end
    end

    local near, location = IsPlayerNearLocksmithLocation(src, { 'garage' }, (tonumber(garage.TargetDistance) or 3.0) + 2.0)
    if not near then
        return false, 'error_locksmith_garage_too_far'
    end

    return true, 'employee', location
end

BuildLocksmithGarageName = function(location)
    local garage = GetLocksmithGarageConfig() or {}
    local prefix = tostring(garage.ProviderGarageNamePrefix or 'partay_locksmith')
    local locationName = tostring(location and location.locationName or 'main'):lower():gsub('[^%w_]+', '_')
    return ('%s_%s'):format(prefix, locationName)
end

local function MakeLocksmithGaragePlate()
    local prefix = tostring((GetLocksmithGarageConfig() or {}).PlatePrefix or 'LOCK'):upper():gsub('[^A-Z0-9]', ''):sub(1, 4)
    if prefix == '' then prefix = 'LOCK' end
    return ('%s%04d'):format(prefix, math.random(0, 9999))
end

local function GetPrimaryLocksmithJob()
    return GetLocksmithRuntimeJobNames(true)[1] or ''
end

local GetLocksmithLocationPoint

local function IsRemovedLocksmithRecipe(recipe)
    if type(recipe) ~= 'table' then return false end
    return recipe.id == 'blank_keys' or recipe.produces == Config.Items.LocksmithBlankBasicKey
end

local function NormalizeLocksmithRecipe(recipe)
    if type(recipe) ~= 'table' then return nil end

    local id = tostring(recipe.id or ''):lower():gsub('%s+', '_'):gsub('[^%w_%-]', ''):sub(1, 60)
    local label = tostring(recipe.label or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, 80)
    local produces = tostring(recipe.produces or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, 80)
    local image = tostring(recipe.image or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, 120)
    local amount = math.max(1, math.min(999, math.floor(tonumber(recipe.amount) or 1)))
    local enabled = recipe.enabled ~= false
    local components = {}

    if id == '' or produces == '' then return nil, 'identity' end
    if label == '' then label = id end

    for _, component in ipairs(recipe.components or {}) do
        local item = tostring(component.item or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, 80)
        local componentLabel = tostring(component.label or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, 80)
        local componentAmount = math.max(1, math.min(999, math.floor(tonumber(component.amount) or 1)))
        if item ~= '' then
            components[#components + 1] = {
                item = item,
                label = componentLabel ~= '' and componentLabel or item,
                amount = componentAmount
            }
        end
    end

    if #components < 1 then return nil, 'components' end

    local normalized = {
        id = id,
        label = label,
        produces = produces,
        image = image,
        amount = amount,
        enabled = enabled,
        components = components
    }
    if IsRemovedLocksmithRecipe(normalized) then return nil, 'removed' end
    return normalized
end

local function ValidateLocksmithRecipeItems(recipe)
    if type(recipe) ~= 'table' then return false, nil end

    local exists, verified = Bridge.ItemExists(recipe.produces)
    if verified and not exists then return false, recipe.produces end

    for _, component in ipairs(recipe.components or {}) do
        exists, verified = Bridge.ItemExists(component.item)
        if verified and not exists then return false, component.item end
    end

    return true, nil
end

local function BuildLocksmithItemLookupPayload()
    local definitions = Bridge.GetItemDefinitions and Bridge.GetItemDefinitions() or nil
    local items = {}

    if type(definitions) == 'table' then
        for name, item in pairs(definitions) do
            local itemName = tostring(name or ''):gsub('^%s*(.-)%s*$', '%1')
            if itemName ~= '' then
                local label = itemName
                if type(item) == 'table' then
                    label = tostring(item.label or item.name or itemName)
                end
                items[#items + 1] = {
                    name = itemName,
                    label = label ~= '' and label or itemName
                }
            end
        end
    end

    table.sort(items, function(a, b)
        return tostring(a.label or a.name):lower() < tostring(b.label or b.name):lower()
    end)

    return {
        available = #items > 0,
        items = items
    }
end

local function GetDefaultLocksmithRecipes()
    local recipes = {}
    local defaults = PartayKeys_GetDefaultLocksmithRecipes and PartayKeys_GetDefaultLocksmithRecipes() or {}
    for _, recipe in ipairs(defaults) do
        local normalized = NormalizeLocksmithRecipe(recipe)
        if normalized then recipes[#recipes + 1] = normalized end
    end
    return recipes
end

local function GetLocksmithRecipes()
    local raw = GetLocksmithGlobalBusinessSetting('locksmith_recipes_json', nil)
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            local recipes = {}
            local seen = {}
            for _, recipe in ipairs(decoded) do
                local normalized = NormalizeLocksmithRecipe(recipe)
                if normalized and not seen[normalized.id] then
                    recipes[#recipes + 1] = normalized
                    seen[normalized.id] = true
                end
            end
            if #recipes > 0 then return recipes end
        end
    end

    return GetDefaultLocksmithRecipes()
end

local function BuildLocksmithRecipeSetupPayload()
    local lookup = BuildLocksmithItemLookupPayload()
    return {
        recipes = GetLocksmithRecipes(),
        defaults = GetDefaultLocksmithRecipes(),
        itemLookupAvailable = lookup.available,
        itemOptions = lookup.items
    }
end

local function GetLocksmithRecipe(recipeId)
    for _, recipe in ipairs(GetLocksmithRecipes()) do
        if recipe.enabled ~= false and recipe.id == recipeId then return recipe end
    end
    return nil
end

local function HasLocksmithRecipeForItem(itemName)
    for _, recipe in ipairs(GetLocksmithRecipes()) do
        if recipe.enabled ~= false and recipe.produces == itemName then return true end
    end
    return false
end

local function AddLocksmithLog(action, message, actorId, targetId, locationName)
    locationName = GetLocksmithBusinessLocationName(locationName or actorId, true)
    local actorName = actorId and GetPlayerName(actorId) or nil
    local targetName = targetId and GetPlayerName(targetId) or nil
    pcall(function()
        MySQL.Async.execute([[
            INSERT INTO partay_locksmith_logs (location_name, action, message, actor_id, actor_name, target_id, target_name)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], {
            locationName,
            tostring(action or 'event'),
            tostring(message or ''),
            actorId and Bridge.GetCitizenID(actorId) or nil,
            actorName,
            targetId and Bridge.GetCitizenID(targetId) or nil,
            targetName
        })
    end)
end

local function RecordLocksmithInvoice(invoice)
    if type(invoice) ~= 'table' or not invoice.id then return end
    pcall(function()
        MySQL.Async.execute([[
            INSERT INTO partay_locksmith_invoices
                (invoice_id, location_name, employee_id, employee_name, customer_id, customer_name, plate, status, total, services)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                location_name = VALUES(location_name),
                employee_name = VALUES(employee_name),
                customer_name = VALUES(customer_name),
                plate = VALUES(plate),
                status = VALUES(status),
                total = VALUES(total),
                services = VALUES(services)
        ]], {
            invoice.id,
            GetLocksmithBusinessLocationName(invoice.locationName or invoice.employeeId, true),
            invoice.employeeCitizenId or (invoice.employeeId and Bridge.GetCitizenID(invoice.employeeId)) or nil,
            invoice.employeeName or (invoice.employeeId and GetPlayerName(invoice.employeeId)) or nil,
            invoice.customerCitizenId or (invoice.customerId and Bridge.GetCitizenID(invoice.customerId)) or nil,
            invoice.customerName or (invoice.customerId and GetPlayerName(invoice.customerId)) or nil,
            invoice.plate,
            invoice.status or 'pending',
            tonumber(invoice.total) or 0,
            json.encode(invoice.services or {})
        })
    end)
end

local function UpdateLocksmithInvoiceStatus(invoiceId, status, paymentMethod, societyDeposit)
    if not invoiceId then return end
    pcall(function()
        MySQL.Async.execute([[
            UPDATE partay_locksmith_invoices
            SET status = ?, payment_method = ?, society_deposit = ?, updated_at = CURRENT_TIMESTAMP
            WHERE invoice_id = ?
        ]], { status, paymentMethod, societyDeposit or 0, invoiceId })
    end)
end

LocksmithStockStashes = LocksmithStockStashes or {}

function GetLocksmithStockStorageId(locationName)
    locationName = GetLocksmithBusinessLocationName(locationName)
    local safeName = tostring(locationName or 'main'):lower():gsub('[^%w_%-]', '_'):gsub('_+', '_'):sub(1, 48)
    if safeName == '' then safeName = 'main' end
    return ('partay_keys_locksmith_stock_%s'):format(safeName), locationName
end

function EnsureLocksmithStockStorage(locationName)
    local storageId, resolvedLocation = GetLocksmithStockStorageId(locationName)
    if GetResourceState('ox_inventory') ~= 'started' then
        return nil, resolvedLocation
    end

    if not LocksmithStockStashes[storageId] then
        local ok = pcall(function()
            exports.ox_inventory:RegisterStash(storageId, ('%s Stock'):format(resolvedLocation), 80, 250000, false)
        end)
        LocksmithStockStashes[storageId] = ok == true
    end

    return LocksmithStockStashes[storageId] and storageId or nil, resolvedLocation
end

function GetLocksmithStockDbMap(locationName)
    locationName = GetLocksmithBusinessLocationName(locationName)
    local rows = MySQL.Sync.fetchAll('SELECT item_name, quantity FROM partay_locksmith_stock WHERE location_name = ?', { locationName }) or {}
    local stock = {}
    for _, row in ipairs(rows) do
        stock[row.item_name] = tonumber(row.quantity) or 0
    end
    return stock
end

function MirrorLocksmithStockDbAdd(locationName, itemName, amount)
    MySQL.Sync.execute([[
        INSERT INTO partay_locksmith_stock (location_name, item_name, quantity)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE quantity = quantity + VALUES(quantity), updated_at = CURRENT_TIMESTAMP
    ]], { locationName, itemName, amount })
end

function MirrorLocksmithStockDbRemove(locationName, itemName, amount)
    MySQL.Sync.execute('UPDATE partay_locksmith_stock SET quantity = GREATEST(quantity - ?, 0), updated_at = CURRENT_TIMESTAMP WHERE location_name = ? AND item_name = ?', {
        amount,
        locationName,
        itemName
    })
end

function GetInventoryItemMap(inventoryId)
    local stock = {}
    if not inventoryId then return stock end

    local ok, items = pcall(function()
        return exports.ox_inventory:GetInventoryItems(inventoryId)
    end)
    if not ok or type(items) ~= 'table' then return stock end

    for _, item in pairs(items) do
        local itemName = item and (item.name or item.item)
        if itemName then
            stock[itemName] = (stock[itemName] or 0) + (tonumber(item.count or item.amount or item.quantity) or 0)
        end
    end

    return stock
end

function GetLocksmithStockMap(locationName)
    local storageId, resolvedLocation = EnsureLocksmithStockStorage(locationName)
    if not storageId then
        return GetLocksmithStockDbMap(resolvedLocation)
    end

    local stock = GetInventoryItemMap(storageId)
    return stock
end

function AddLocksmithStock(itemName, amount, locationName)
    local storageId, resolvedLocation = EnsureLocksmithStockStorage(locationName)
    itemName = tostring(itemName or '')
    amount = math.floor(tonumber(amount) or 0)
    if itemName == '' or amount <= 0 then return false end

    if storageId then
        local ok, result = pcall(function()
            return exports.ox_inventory:AddItem(storageId, itemName, amount)
        end)
        if not ok or result == false then return false end
    end

    MirrorLocksmithStockDbAdd(resolvedLocation, itemName, amount)
    return true
end

function ConsumeLocksmithStock(requirements, locationName)
    local storageId, resolvedLocation = EnsureLocksmithStockStorage(locationName)
    requirements = requirements or {}
    if #requirements < 1 then return true end

    local stock = GetLocksmithStockMap(resolvedLocation)
    for _, requirement in ipairs(requirements) do
        local itemName = requirement.item
        local amount = math.floor(tonumber(requirement.amount) or 0)
        if itemName and amount > 0 and (stock[itemName] or 0) < amount then
            return false, itemName
        end
    end

    for _, requirement in ipairs(requirements) do
        local itemName = requirement.item
        local amount = math.floor(tonumber(requirement.amount) or 0)
        if itemName and amount > 0 then
            if storageId then
                local ok, result = pcall(function()
                    return exports.ox_inventory:RemoveItem(storageId, itemName, amount)
                end)
                if not ok or result == false then return false, itemName end
            end
            MirrorLocksmithStockDbRemove(resolvedLocation, itemName, amount)
        end
    end

    return true
end

function HasLocksmithStock(requirements, locationName)
    locationName = GetLocksmithBusinessLocationName(locationName)
    requirements = requirements or {}
    if #requirements < 1 then return true end

    local stock = GetLocksmithStockMap(locationName)
    for _, requirement in ipairs(requirements) do
        local itemName = requirement.item
        local amount = math.floor(tonumber(requirement.amount) or 0)
        if itemName and amount > 0 and (stock[itemName] or 0) < amount then
            return false, itemName
        end
    end

    return true
end

function CountPlayerInventoryItem(src, itemName)
    local total = 0
    for _, item in pairs(Bridge.GetInventoryItems(src) or {}) do
        local name = item and (item.name or item.item)
        if name == itemName then
            total = total + (tonumber(item.count or item.amount or item.quantity) or 0)
        end
    end
    return total
end

local function GetLocksmithShopOrderRows(limit, locationName)
    locationName = locationName and GetLocksmithBusinessLocationName(locationName) or nil
    local params = {}
    local where = "WHERE status IN ('pending', 'filled')"
    if locationName then
        where = where .. ' AND location_name = ?'
        params[#params + 1] = locationName
    end
    params[#params + 1] = tonumber(limit) or 30

    return MySQL.Sync.fetchAll([[
        SELECT order_id, location_name, item_name, label, quantity, total, status, customer_id, customer_name, employee_id, employee_name, pickup_coords, created_at, updated_at
        FROM partay_locksmith_shop_orders
        ]] .. where .. [[
        ORDER BY id DESC
        LIMIT ?
    ]], params) or {}
end

local function ShouldSendLocksmithFallbackNotify()
    local phone = Config and Config.Integrations and Config.Integrations.Phone or {}
    return phone.FallbackNotify ~= false
end

local function SendLocksmithPhoneMessage(targetSrc, message, metadata)
    if type(PartayKeys_SendLocksmithPhoneMessage) ~= 'function' or not targetSrc then return false end

    local ok, sent = pcall(PartayKeys_SendLocksmithPhoneMessage, targetSrc, {
        title = T('label_locksmith'),
        message = message,
        type = 'info',
        category = 'locksmith',
        metadata = metadata or {}
    })

    if not ok then
        if Config.DebugMode then
            print(('[ParTay Keys Debug] Locksmith phone send failed: %s'):format(tostring(sent)))
        end
        return false
    end

    return sent == true
end

local function NotifyOnlineLocksmithEmployees(messageKey, vars, notifyOwners)
    local message = T(messageKey, vars)
    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        if targetSrc and (IsPlayerLocksmithEmployee(targetSrc) or (notifyOwners and IsPlayerLocksmithOwner(targetSrc))) then
            SendLocksmithPhoneMessage(targetSrc, message, {
                audience = 'locksmith_staff',
                messageKey = messageKey,
                vars = vars
            })
            if ShouldSendLocksmithFallbackNotify() then
                Notify(targetSrc, T('label_locksmith'), message, 'info')
            end
        end
    end
end

local function RefreshLocksmithBusinessForStaff()
    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        if targetSrc and (IsPlayerLocksmithEmployee(targetSrc) or IsPlayerLocksmithOwner(targetSrc)) then
            TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', targetSrc)
        end
    end
end

local function BuildLocksmithShopOrderPickupCoords(src, locationName)
    local pickupPoint = GetLocksmithLocationPoint(locationName, 'customer_pickup')
    if pickupPoint and pickupPoint.coords then
        return pickupPoint.coords
    end

    local registerPoint = GetLocksmithLocationPoint(locationName, 'register')
    if registerPoint and registerPoint.coords then
        return registerPoint.coords
    end

    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        return { x = coords.x, y = coords.y, z = coords.z, w = heading }
    end

    return nil
end

local function DecodeLocksmithShopOrder(row)
    if type(row) ~= 'table' then return nil end
    local coords = DecodeLocksmithCoords(row.pickup_coords)
    return {
        orderId = row.order_id,
        locationName = row.location_name,
        item = row.item_name,
        label = row.label or row.item_name,
        quantity = tonumber(row.quantity) or 1,
        total = tonumber(row.total) or 0,
        status = row.status or 'pending',
        customerId = row.customer_id,
        customerName = row.customer_name,
        employeeId = row.employee_id,
        employeeName = row.employee_name,
        pickupCoords = coords and { x = coords.x, y = coords.y, z = coords.z, w = coords.w or 0.0 } or nil
    }
end

local function GetLocksmithOrderItem(itemName)
    local stocking = GetLocksmithStockingConfig()
    itemName = tostring(itemName or '')
    for _, entry in ipairs((stocking and stocking.OrderItems) or {}) do
        if entry.item == itemName then return entry end
    end
    return nil
end

local function DecodeLocksmithStockOrderItems(rawItems, fallbackItem, fallbackLabel, fallbackQuantity)
    local decoded = rawItems
    if type(decoded) == 'string' and decoded ~= '' then
        local ok, parsed = pcall(json.decode, decoded)
        decoded = ok and parsed or nil
    end

    local items = {}
    if type(decoded) == 'table' then
        for _, entry in ipairs(decoded) do
            local itemName = tostring(entry.item or entry.item_name or '')
            local quantity = math.max(1, math.floor(tonumber(entry.quantity) or 1))
            if itemName ~= '' then
                items[#items + 1] = {
                    item = itemName,
                    label = entry.label or entry.Label or itemName,
                    quantity = quantity,
                    unitPrice = tonumber(entry.unitPrice or entry.unit_price) or 0,
                    total = tonumber(entry.total) or 0
                }
            end
        end
    end

    if #items < 1 and fallbackItem then
        items[1] = {
            item = fallbackItem,
            label = fallbackLabel or fallbackItem,
            quantity = math.max(1, math.floor(tonumber(fallbackQuantity) or 1))
        }
    end

    return items
end

local function GetLocksmithStockOrderRows(limit)
    return MySQL.Sync.fetchAll([[
        SELECT order_id, location_name, stock_method, item_name, label, quantity, total, order_items, status, pickup_coords, ready_at, created_at, completed_at
        FROM partay_locksmith_stock_orders
        ORDER BY id DESC
        LIMIT ?
    ]], { tonumber(limit) or 25 }) or {}
end

local locksmithAppointmentSchemaReady = false

local function EnsureLocksmithAppointmentSchema()
    if locksmithAppointmentSchemaReady then return end

    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `partay_locksmith_appointments` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `appointment_id` VARCHAR(80) NOT NULL,
            `customer_id` VARCHAR(50) DEFAULT NULL,
            `customer_name` VARCHAR(100) DEFAULT NULL,
            `contact_name` VARCHAR(100) DEFAULT NULL,
            `contact_phone` VARCHAR(80) DEFAULT NULL,
            `contact_email` VARCHAR(120) DEFAULT NULL,
            `plate` VARCHAR(20) DEFAULT NULL,
            `message` VARCHAR(255) DEFAULT NULL,
            `status` VARCHAR(30) NOT NULL DEFAULT 'pending',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `expires_at` TIMESTAMP NULL DEFAULT NULL,
            `accepted_by` VARCHAR(50) DEFAULT NULL,
            `accepted_by_name` VARCHAR(100) DEFAULT NULL,
            `scheduled_for` VARCHAR(80) DEFAULT NULL,
            `scheduled_date` VARCHAR(40) DEFAULT NULL,
            `scheduled_time` VARCHAR(40) DEFAULT NULL,
            `schedule_note` VARCHAR(255) DEFAULT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `idx_partay_locksmith_appointment_id` (`appointment_id`),
            INDEX `idx_partay_locksmith_appointment_status` (`status`)
        )
    ]])

    local columns = {
        contact_name = 'VARCHAR(100) DEFAULT NULL',
        contact_phone = 'VARCHAR(80) DEFAULT NULL',
        contact_email = 'VARCHAR(120) DEFAULT NULL',
        scheduled_for = 'VARCHAR(80) DEFAULT NULL',
        scheduled_date = 'VARCHAR(40) DEFAULT NULL',
        scheduled_time = 'VARCHAR(40) DEFAULT NULL',
        schedule_note = 'VARCHAR(255) DEFAULT NULL'
    }

    for columnName, definition in pairs(columns) do
        local exists = MySQL.Sync.fetchScalar([[
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'partay_locksmith_appointments'
              AND COLUMN_NAME = ?
        ]], { columnName })

        if not tonumber(exists) or tonumber(exists) <= 0 then
            MySQL.Sync.execute(('ALTER TABLE partay_locksmith_appointments ADD COLUMN %s %s'):format(QuoteSqlIdentifier(columnName), definition))
        end
    end

    locksmithAppointmentSchemaReady = true
end

local function GetLocksmithAppointmentRows(limit)
    EnsureLocksmithAppointmentSchema()

    return MySQL.Sync.fetchAll([[
        SELECT appointment_id, customer_name, contact_name, contact_phone, contact_email, plate, message, status, created_at, expires_at, accepted_by_name, scheduled_for, scheduled_date, scheduled_time, schedule_note
        FROM partay_locksmith_appointments
        WHERE status IN ('pending', 'confirmed', 'scheduled', 'open', 'accepted')
        ORDER BY id DESC
        LIMIT ?
    ]], { tonumber(limit) or 20 }) or {}
end

local function BuildLocksmithStockingPayload(locationName)
    locationName = GetLocksmithBusinessLocationName(locationName)
    local stocking = GetLocksmithStockingConfig() or {}
    local activeContractId, activeContract = GetLocksmithSupplierContract(locationName)
    local priceMultiplier = tonumber(activeContract.PriceMultiplier) or 1.0
    local supplierContracts = {}
    for contractId, contract in pairs(stocking.SupplierContracts or {}) do
        supplierContracts[#supplierContracts + 1] = {
            id = contractId,
            label = contract.Label or contractId,
            description = contract.Description or '',
            priceMultiplier = tonumber(contract.PriceMultiplier) or 1.0,
            delayMultiplier = tonumber(contract.DelayMultiplier) or 1.0,
            active = contractId == activeContractId
        }
    end
    SortLocksmithSupplierContracts(supplierContracts)

    local orderItems = {}
    for _, entry in ipairs(stocking.OrderItems or {}) do
        local basePrice = tonumber(entry.price) or 0
        local activeBasePrice = GetLocksmithPrice(('order:%s'):format(tostring(entry.item)), basePrice, nil, locationName)
        orderItems[#orderItems + 1] = {
            item = entry.item,
            label = entry.label or entry.item,
            basePrice = basePrice,
            activeBasePrice = activeBasePrice,
            price = math.floor((activeBasePrice * priceMultiplier) + 0.5),
            image = entry.image or (entry.item and ('assets/%s.png'):format(entry.item)) or nil
        }
    end

    local societyAccount = GetLocksmithSocietyAccount()

    return {
        enabled = stocking.Enabled ~= false,
        societyAccount = societyAccount,
        societyBalance = Bridge.GetSocietyMoney and Bridge.GetSocietyMoney(societyAccount) or nil,
        maxOrderQuantity = tonumber(stocking.MaxOrderQuantity) or 50,
        activeSupplierContract = activeContractId,
        activeSupplierLabel = activeContract.Label or activeContractId,
        supplierContracts = supplierContracts,
        editableSupplierContracts = GetEditableLocksmithSupplierContracts(),
        defaultSupplierContracts = GetDefaultLocksmithSupplierContracts(),
        orderItems = orderItems,
        orders = GetLocksmithStockOrderRows(20)
    }
end

local function GetLocksmithLocationProfile(locationName)
    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then return nil end

    local rows = MySQL.Sync.fetchAll([[
        SELECT location_name, shop_type, job_name, stock_method, stock_settings
        FROM partay_locksmith_locations
        WHERE location_name = ?
        LIMIT 1
    ]], { locationName }) or {}

    if not rows[1] then return nil end
    local method, methodConfig = NormalizeStockMethod(rows[1].stock_method)
    return {
        locationName = rows[1].location_name,
        shopType = NormalizeLocksmithShopType(rows[1].shop_type),
        jobName = rows[1].job_name,
        stockMethod = method,
        stockMethodLabel = methodConfig.Label or method,
        stockSettings = DecodeJsonObject(rows[1].stock_settings)
    }
end

GetLocksmithLocationPoint = function(locationName, pointType)
    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    pointType = tostring(pointType or ''):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' or pointType == '' then return nil end

    for _, location in ipairs(GetActiveLocksmithLocations()) do
        if location.locationName == locationName and location.type == pointType then
            return location
        end
    end

    return nil
end

local function GetNearestLocksmithStockLocation(src)
    local near, location = IsPlayerNearLocksmithLocation(src, { 'stock', 'management', 'register', 'workbench' }, 12.0)
    if near and location then
        return GetLocksmithLocationProfile(location.locationName) or {
            locationName = location.locationName,
            jobName = location.jobName,
            stockMethod = location.stockMethod or select(1, NormalizeStockMethod()),
            stockMethodLabel = location.stockMethodLabel
        }
    end

    local locations = GetActiveLocksmithLocations()
    if locations[1] then
        return GetLocksmithLocationProfile(locations[1].locationName) or {
            locationName = locations[1].locationName,
            jobName = locations[1].jobName,
            stockMethod = locations[1].stockMethod or select(1, NormalizeStockMethod()),
            stockMethodLabel = locations[1].stockMethodLabel
        }
    end

    return {
        locationName = 'Main Locksmith',
        stockMethod = select(1, NormalizeStockMethod())
    }
end

local function EncodeStockPickupCoords(coords)
    if not coords then return nil end
    return json.encode({ x = coords.x, y = coords.y, z = coords.z, w = coords.w or 0.0 })
end

local function GetConfiguredPickupCoords()
    local pickup = GetWarehousePickupSettingsPayload()
    local coords = pickup.enabled ~= false and pickup.coords or nil
    if not coords then return nil end
    return { x = coords.x, y = coords.y, z = coords.z, w = coords.w or 0.0 }
end

local function GetLocksmithStockRequirementsForServices(services)
    local business = GetLocksmithBusinessConfig()
    if not business or business.ConsumeStockForJobs ~= true then return {} end

    local defaults = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith or {}
    local merged = {}
    for _, service in ipairs(services or {}) do
        local configured = defaults.ServiceStock and defaults.ServiceStock[service.action]
        local requirements = {}
        if configured == 'tier_blank' then
            local _, tierConfig = PartayKeys_GetKeyTierConfig(service.tier or Config.DefaultKeyTier)
            if tierConfig and tierConfig.BlankItem then
                requirements = { { item = tierConfig.BlankItem, amount = 1 } }
            end
        elseif type(configured) == 'table' then
            requirements = configured
        end

        for _, requirement in ipairs(requirements) do
            if requirement.item and tonumber(requirement.amount) and tonumber(requirement.amount) > 0 then
                merged[requirement.item] = (merged[requirement.item] or 0) + tonumber(requirement.amount)
            end
        end
    end

    local requirements = {}
    for itemName, amount in pairs(merged) do
        requirements[#requirements + 1] = { item = itemName, amount = amount }
    end
    return requirements
end

local function EmployeeHasRequiredLocksmithTools(src, services)
    local defaults = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith or {}
    local requiredTools = defaults.RequiredTools or {}
    for _, service in ipairs(services or {}) do
        local tool = requiredTools[service.serviceName]
        if tool and tool ~= '' and not Bridge.HasInventoryItem(src, tool, 1) then
            return false, tool
        end
    end

    return true
end

local function CanUseLocksmithService(src)
    local playerRun = GetLocksmithPlayerRunConfig()
    if not playerRun then return true, 'npc' end

    if GetLocksmithShopStatus() ~= 'closed' and IsPlayerNearLocksmithLocation(src, { 'fallback_ped' }, 10.0, 'self_service') then
        return true, 'self_service'
    end

    if IsPlayerLocksmithEmployee(src) then
        return true, 'employee'
    end

    if IsPlayerLocksmithOwner(src) then
        return true, 'owner'
    end

    local shopStatus = GetLocksmithShopStatus()
    if shopStatus == 'closed' then
        return false, 'shop_closed'
    end

    local minimumOnline = math.max(1, tonumber(playerRun.MinimumOnline) or 1)
    local onlineEmployees = CountOnlineLocksmithEmployees()

    if onlineEmployees >= minimumOnline then
        return false, 'staff_online'
    end

    return false, 'staff_required'
end

local function GetLocksmithAccessError(reason)
    if reason == 'staff_online' then return 'error_locksmith_staff_online' end
    if reason == 'shop_closed' then return 'error_locksmith_shop_closed' end
    return 'error_locksmith_staff_required'
end

local function GetKeyTierRank(tier)
    for rank, configuredTier in ipairs(Config.KeyTierOrder or {}) do
        if configuredTier == tier then
            return rank
        end
    end

    return 0
end

local function IsPlayerNearLocksmith(src, distance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    if IsPlayerNearLocksmithLocation(src, { 'workbench', 'management', 'register', 'stock', 'fallback_ped' }, distance or 10.0) then
        return true
    end

    return false
end

local function FindOnlineOwnerNearEmployee(ownerCitizenId, employeeSrc, range)
    if not ownerCitizenId or not employeeSrc then return nil end

    local employeePed = GetPlayerPed(employeeSrc)
    if not employeePed or employeePed == 0 then return nil end

    local employeeCoords = GetEntityCoords(employeePed)
    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        if targetSrc and Bridge.GetCitizenID(targetSrc) == ownerCitizenId then
            local targetPed = GetPlayerPed(targetSrc)
            if targetPed and targetPed ~= 0 and #(employeeCoords - GetEntityCoords(targetPed)) <= (range or 6.0) then
                return targetSrc
            end
        end
    end

    return nil
end

local function FindOnlinePlayerByCitizenId(citizenId)
    if not citizenId then return nil end
    citizenId = tostring(citizenId)
    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        local targetCitizenId = targetSrc and Bridge.GetCitizenID(targetSrc)
        if targetCitizenId and tostring(targetCitizenId) == citizenId then
            return targetSrc
        end
    end
    return nil
end

local function GetLocksmithPriceLimits()
    return Config.LocksmithPriceLimits or {}
end

local function GetLocksmithPriceLimit(priceKey, defaultPrice)
    local limits = GetLocksmithPriceLimits()
    local fallback = limits.Default or {}
    local minValue = tonumber(fallback.Min) or 0
    local maxValue = tonumber(fallback.Max) or math.max(tonumber(defaultPrice) or 0, 100000)
    local category, name = tostring(priceKey or ''):match('^([^:]+):(.+)$')
    local scoped

    if category == 'service' then
        local serviceLimitKeys = {
            copy = 'Copy',
            recover = 'Recover',
            rekey = 'ReKey'
        }
        scoped = limits.Services and limits.Services[serviceLimitKeys[name] or name]
    elseif category == 'tier' then
        scoped = limits.KeyTiers and limits.KeyTiers[name]
    elseif category == 'shop' then
        scoped = limits.Shop and limits.Shop[name]
    elseif category == 'order' then
        scoped = limits.Orders and limits.Orders[name]
    end

    if scoped then
        minValue = tonumber(scoped.Min) or minValue
        maxValue = tonumber(scoped.Max) or maxValue
    end

    if maxValue < minValue then
        maxValue = minValue
    end

    return minValue, maxValue
end

local function ClampLocksmithPrice(priceKey, price, defaultPrice)
    local minValue, maxValue = GetLocksmithPriceLimit(priceKey, defaultPrice)
    price = math.floor(tonumber(price) or tonumber(defaultPrice) or 0)
    return math.max(minValue, math.min(maxValue, price)), minValue, maxValue
end

local function GetLocksmithPriceOverrides(locationName)
    locationName = GetLocksmithBusinessLocationName(locationName)
    local ok, rows = pcall(function()
        return MySQL.Sync.fetchAll('SELECT price_key, price FROM partay_locksmith_prices WHERE location_name = ?', { locationName }) or {}
    end)
    if not ok or type(rows) ~= 'table' then return {} end

    local overrides = {}
    for _, row in ipairs(rows) do
        overrides[tostring(row.price_key or '')] = tonumber(row.price)
    end
    return overrides
end

GetLocksmithPrice = function(priceKey, defaultPrice, overrides, locationName)
    overrides = overrides or GetLocksmithPriceOverrides(locationName)
    local override = overrides[tostring(priceKey or '')]
    local clamped = ClampLocksmithPrice(priceKey, override ~= nil and override or defaultPrice, defaultPrice)
    return clamped
end

local function AddLocksmithPriceEntry(payload, category, id, label, defaultPrice, overrides)
    local priceKey = ('%s:%s'):format(category, id)
    local current, minValue, maxValue = GetLocksmithPrice(priceKey, defaultPrice, overrides)
    local entry = {
        key = priceKey,
        category = category,
        id = id,
        label = label or id,
        default = tonumber(defaultPrice) or 0,
        current = current,
        min = minValue,
        max = maxValue
    }

    payload.entries[#payload.entries + 1] = entry
    if category == 'service' then
        payload.services[id] = current
    elseif category == 'tier' then
        payload.tiers[id] = current
    elseif category == 'shop' then
        payload.shop[id] = current
    elseif category == 'order' then
        payload.orders[id] = current
    end
end

local function BuildLocksmithPricePayload(locationName)
    locationName = GetLocksmithBusinessLocationName(locationName)
    local payload = {
        entries = {},
        services = {},
        tiers = {},
        shop = {},
        orders = {}
    }
    local selfService = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.SelfService or {}
    local overrides = GetLocksmithPriceOverrides(locationName)

    AddLocksmithPriceEntry(payload, 'service', 'copy', 'Physical Key Copy', GetLocksmithDefaultServiceFee('copy'), overrides)
    AddLocksmithPriceEntry(payload, 'service', 'recover', 'Vehicle Recovery', GetLocksmithDefaultServiceFee('recover'), overrides)
    AddLocksmithPriceEntry(payload, 'service', 'rekey', 'Vehicle Re-Key', GetLocksmithDefaultServiceFee('rekey'), overrides)

    for _, tier in ipairs(Config.KeyTierOrder or {}) do
        local tierConfig = Config.KeyTiers and Config.KeyTiers[tier]
        if tierConfig then
            AddLocksmithPriceEntry(payload, 'tier', tier, tierConfig.UpgradeLabel or tierConfig.Label or tier, tonumber(tierConfig.UpgradePrice) or 0, overrides)
        end
    end

    for _, shopItem in ipairs(selfService.Items or {}) do
        if shopItem.item then
            AddLocksmithPriceEntry(payload, 'shop', shopItem.item, shopItem.label or shopItem.item, tonumber(shopItem.price) or 0, overrides)
        end
    end

    local stocking = GetLocksmithStockingConfig() or {}
    for _, orderItem in ipairs(stocking.OrderItems or {}) do
        if orderItem.item then
            AddLocksmithPriceEntry(payload, 'order', orderItem.item, orderItem.label or orderItem.item, tonumber(orderItem.price) or 0, overrides)
        end
    end

    return payload
end

local function GetLocksmithServiceFee(serviceAction, keyTier, locationName)
    if serviceAction == 'copy' then
        return GetLocksmithPrice('service:copy', GetLocksmithDefaultServiceFee('copy'), nil, locationName)
    elseif serviceAction == 'recover' then
        return GetLocksmithPrice('service:recover', GetLocksmithDefaultServiceFee('recover'), nil, locationName)
    elseif serviceAction == 'rekey' then
        return GetLocksmithPrice('service:rekey', GetLocksmithDefaultServiceFee('rekey'), nil, locationName)
    elseif serviceAction == 'upgrade' then
        local _, tierConfig = PartayKeys_GetKeyTierConfig(keyTier)
        return tierConfig and GetLocksmithPrice(('tier:%s'):format(tostring(keyTier)), tonumber(tierConfig.UpgradePrice) or 0, nil, locationName) or 0
    end

    return 0
end

local function GetLocksmithWorkflowConfig()
    local playerRun = GetLocksmithPlayerRunConfig()
    return playerRun and playerRun.Workflow or {}
end

local function MakeLocksmithRecordId(prefix)
    return ('%s:%s:%s'):format(prefix, GetGameTimer(), math.random(100000, 999999))
end

local function BuildLocksmithHeldKeyId(citizenId, plate)
    plate = TrimPlate(plate)
    if not citizenId or not plate or plate == '' then return nil end
    return ('%s:%s'):format(citizenId, plate)
end

local function IsLocksmithKeyHeld(src, plate)
    local workflow = GetLocksmithWorkflowConfig()
    if workflow.HoldCustomerKeysUntilPaid == false then return false end

    local citizenId = Bridge.GetCitizenID(src)
    local heldId = BuildLocksmithHeldKeyId(citizenId, plate)
    local held = heldId and LocksmithHeldKeys[heldId]
    if not held then return false end

    local job = ActiveLocksmithJobs[held.jobId]
    if not job or job.customerId ~= src or job.status == 'paid' or job.expiresAt < os.time() then
        LocksmithHeldKeys[heldId] = nil
        if job and job.expiresAt < os.time() then
            ActiveLocksmithJobs[held.jobId] = nil
        end
        return false
    end

    return true
end

local function ReleaseLocksmithHeldKeys(job)
    if not job or not job.customerCitizenId then return end

    local heldId = BuildLocksmithHeldKeyId(job.customerCitizenId, job.plate)
    if heldId then
        LocksmithHeldKeys[heldId] = nil
    end
end

local function NormalizeLocksmithServiceRequest(rawService)
    if type(rawService) ~= 'table' then return nil end

    local action = tostring(rawService.action or '')
    local serviceName = locksmithServiceNames and locksmithServiceNames[action] or nil
    if not serviceName then return nil end

    local service = {
        action = action,
        serviceName = serviceName
    }

    if action == 'upgrade' then
        local tier, tierConfig = PartayKeys_GetKeyTierConfig(rawService.tier)
        if not tier or not tierConfig then return nil end
        service.tier = tier
        service.tierLabel = tierConfig.UpgradeLabel or tierConfig.Label or tier
    end

    service.fee = GetLocksmithServiceFee(action, service.tier)
    return service
end

local function NormalizeLocksmithServices(data)
    local rawServices = {}
    if type(data.services) == 'table' then
        rawServices = data.services
    elseif data.action then
        rawServices = { data }
    end

    local normalized = {}
    local seen = {}
    for _, rawService in ipairs(rawServices) do
        local service = NormalizeLocksmithServiceRequest(rawService)
        if service then
            local key = service.action == 'upgrade' and ('upgrade:' .. tostring(service.tier)) or service.action
            if not seen[key] then
                seen[key] = true
                normalized[#normalized + 1] = service
            end
        end
    end

    return normalized
end

local function GetLocksmithInvoiceTotal(services, locationName)
    local total = 0
    for _, service in ipairs(services or {}) do
        total = total + (tonumber(service.fee) or 0)
    end
    return total
end

local function ValidateLocksmithEmployeeJob(src, customerId, plate, netId, services)
    if not customerId or customerId == src or not GetPlayerName(customerId) then
        return false, 'error_locksmith_invalid_customer_service'
    end

    if type(services) ~= 'table' or #services < 1 then
        return false, 'error_locksmith_invalid_customer_service'
    end

    for _, service in ipairs(services) do
        local allowed, reason = CanEmployeePerformLocksmithService(src, service.serviceName)
        if not allowed then
            return false, reason == 'grade' and 'error_locksmith_grade_required' or 'error_locksmith_employee_required'
        end
    end

    local hasTools, missingTool = EmployeeHasRequiredLocksmithTools(src, services)
    if not hasTools then
        return false, 'error_locksmith_missing_tool', nil, nil, nil, missingTool
    end

    local locksmithJobs = GetLocksmithRuntimeJobNames(false)
    local customerRange = tonumber(playerRun.CustomerRange) or 6.0
    local vehicleRange = tonumber(playerRun.VehicleRange) or 14.0
    local employeePed = GetPlayerPed(src)
    local customerPed = GetPlayerPed(customerId)
    if not employeePed or employeePed == 0 or not customerPed or customerPed == 0
        or #(GetEntityCoords(employeePed) - GetEntityCoords(customerPed)) > customerRange then
        return false, 'error_locksmith_customer_too_far'
    end

    local veh = tonumber(netId) and NetworkGetEntityFromNetworkId(tonumber(netId)) or 0
    if not plate or plate == '' or not veh or veh == 0 or GetPlayerDistanceToEntity(src, veh) > vehicleRange then
        return false, 'error_locksmith_vehicle_too_far'
    end

    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then
        return false, 'error_locksmith_vehicle_mismatch'
    end

    local customerCitizenId = Bridge.GetCitizenID(customerId)
    local registration = customerCitizenId and GetVehicleRegistrationForOwner(plate, customerCitizenId) or nil
    if not registration then
        return false, 'error_locksmith_customer_not_owner'
    end

    local ownerColumn = GetOwnerColumn()
    local activeTier = GetActiveKeyTierFromDB(plate, registration[ownerColumn] or customerCitizenId)
    for _, service in ipairs(services) do
        if service.action == 'copy' or service.action == 'rekey' then
            service.tier = activeTier
            local _, tierConfig = PartayKeys_GetKeyTierConfig(activeTier)
            service.tierLabel = tierConfig and (tierConfig.UpgradeLabel or tierConfig.Label or activeTier) or activeTier
        end
    end

    return true, nil, veh, customerCitizenId, registration
end

local function PayLocksmithEmployeeCommission(confirmedService, fee, label)
    if not confirmedService or not confirmedService.employeeId or not GetPlayerName(confirmedService.employeeId) then return end
    if confirmedService.commissionPaid == true then return end

    local payment = GetLocksmithPaymentSettings(confirmedService.locationName)
    local amount = GetLocksmithCommissionAmount(fee, payment)
    if amount <= 0 then return end

    local account = payment.EmployeeCommissionAccount or 'cash'
    if payment.PaySource == 'society' then
        local society = GetLocksmithSocietyAccount(confirmedService.employeeId)
        if not Bridge.RemoveSocietyMoney or not Bridge.RemoveSocietyMoney(society, amount) then
            Notify(confirmedService.employeeId, T('label_locksmith'), T('error_locksmith_payroll_source_failed'), 'error')
            return
        end
    end

    if Bridge.AddCurrency(confirmedService.employeeId, account, amount) then
        Notify(confirmedService.employeeId, T('label_locksmith'), T('success_locksmith_commission_paid', {
            amount = amount,
            service = label or 'service'
        }), 'success')
    end
end

local function ConsumeConfirmedLocksmithService(src, action, plate)
    local pending = ConfirmedLocksmithServices[src]
    if not pending then return nil end

    local now = os.time()
    if pending.expiresAt < now then
        ConfirmedLocksmithServices[src] = nil
        return nil
    end

    if type(pending.services) == 'table' then
        for index, service in ipairs(pending.services) do
            if service.action == action and TrimPlate(pending.plate) == TrimPlate(plate) then
                local confirmed = {
                    employeeId = pending.employeeId,
                    action = service.action,
                    plate = pending.plate,
                    tier = service.tier,
                    netId = pending.netId,
                    paid = pending.paid == true,
                    invoiceId = pending.invoiceId,
                    jobId = pending.jobId,
                    locationName = pending.locationName,
                    commissionPaid = pending.commissionPaid == true,
                    commissionAmount = pending.commissionAmount,
                    expiresAt = pending.expiresAt
                }

                table.remove(pending.services, index)
                if #pending.services < 1 then
                    ConfirmedLocksmithServices[src] = nil
                end
                return confirmed
            end
        end

        return nil
    end

    if pending.action ~= action or TrimPlate(pending.plate) ~= TrimPlate(plate) then
        ConfirmedLocksmithServices[src] = nil
        return nil
    end

    ConfirmedLocksmithServices[src] = nil
    return pending
end

local function RemovePhysicalVehicleKeys(src, plate, keyVersion)
    plate = TrimPlate(plate)
    keyVersion = tonumber(keyVersion)
    if not plate or plate == '' or not keyVersion then return 0 end

    local removed = 0
    local items = GetInventoryItems(src)
    for _, item in pairs(items) do
        local itemName = item.name or item.item
        local metadata = item.metadata or item.info
        local metadataPlate = metadata and TrimPlate(metadata.plate)
        local metadataVersion = metadata and tonumber(metadata.key_version)

        if PartayKeys_IsKeyItem(itemName) and metadataPlate == plate and metadataVersion == keyVersion then
            if Bridge.RemoveInventoryItem(src, itemName, 1, metadata, item.slot) then
                removed = removed + 1
            end
        end
    end

    return removed
end

local function SyncLiveVehiclePossession(plate, possessionId, originalOwnerId, isStolen)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return end

    for _, veh in ipairs(GetAllVehicles()) do
        if TrimPlate(GetVehicleNumberPlateText(veh)) == plate then
            Entity(veh).state:set('possession_id', possessionId, true)
            Entity(veh).state:set('isStolen', isStolen == true, true)
            Entity(veh).state:set('original_owner_id', originalOwnerId or possessionId, true)
            return
        end
    end
end

local function FindLiveVehicleByPlate(plate)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return 0 end

    for _, veh in ipairs(GetAllVehicles()) do
        if TrimPlate(GetVehicleNumberPlateText(veh)) == plate then
            return veh
        end
    end

    return 0
end

local function HasLockpickTool(src)
    if Config.Items.Lockpick and not Bridge.HasInventoryItem(src, Config.Items.Lockpick, 1) then return false end
    return true
end

local function GetVehicleKeyVersionFromDB(plate)
    local registration = GetVehicleRegistration(plate)
    if registration and registration.key_version then
        return tonumber(registration.key_version) or 1
    end
    return 1
end

local function GetActiveKeyTierFromDB(plate, holderId)
    plate = TrimPlate(plate)
    if not plate or plate == '' or not holderId then return Config.DefaultKeyTier or 'smart' end

    local row = MySQL.Sync.fetchAll([[
        SELECT metadata FROM partay_vehicle_keys
        WHERE plate = ? AND holder_id = ? AND revoked_at IS NULL
        ORDER BY issued_at DESC, id DESC
        LIMIT 1
    ]], { plate, holderId })
    row = row and row[1]

    if row and row.metadata and row.metadata ~= '' then
        local ok, decoded = pcall(json.decode, row.metadata)
        if ok and type(decoded) == 'table' and decoded.key_tier then
            return PartayKeys_GetKeyTierFromMetadata(decoded)
        end
    end

    return Config.DefaultKeyTier or 'smart'
end

local function EncodeMetadata(metadata)
    if type(metadata) ~= 'table' then return nil end

    local ok, encoded = pcall(json.encode, metadata)
    return ok and encoded or nil
end

local function GetOnlineCharacterNameByCitizenId(citizenId)
    if not citizenId or citizenId == '' then return nil end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src and Bridge.GetCitizenID(src) == citizenId then
            return Bridge.GetCharacterName and Bridge.GetCharacterName(src) or GetPlayerName(src)
        end
    end

    return nil
end

local function WarnMetadata(message)
    if Bridge and Bridge.WarnMetadata then
        Bridge.WarnMetadata(message)
    elseif Config and Config.DebugMode then
        print(('^5[ParTay Keys Debug]^3 Metadata Warning: %s^0'):format(message))
    end
end

function PartayKeys_RecordVehicleKey(data)
    if type(data) ~= 'table' then return false end

    local plate = data.plate and data.plate:gsub('^%s*(.-)%s*$', '%1')
    local holderId = data.holder_id
    if not plate or plate == '' or not holderId or holderId == '' then return false end

    local keyVersion = tonumber(data.key_version) or GetVehicleKeyVersionFromDB(plate)
    local keyType = data.key_type or 'owner'
    local keyTier = data.key_tier or (type(data.metadata) == 'table' and data.metadata.key_tier) or Config.DefaultKeyTier or 'smart'
    local possessionId = data.possession_id or holderId
    local ownerId = data.owner_id
    local issuedBy = data.issued_by
    local holderName = data.holder_name or GetOnlineCharacterNameByCitizenId(holderId)
    local ownerName = data.owner_name or GetOnlineCharacterNameByCitizenId(ownerId)
    local issuedByName = data.issued_by_name or GetOnlineCharacterNameByCitizenId(issuedBy)
    local metadataTable = type(data.metadata) == 'table' and data.metadata or {}
    metadataTable.key_tier = metadataTable.key_tier or keyTier
    local metadata = EncodeMetadata(metadataTable)

    local existingId = MySQL.Sync.fetchScalar([[
        SELECT id FROM partay_vehicle_keys
        WHERE plate = ? AND holder_id = ? AND key_type = ? AND key_version = ? AND revoked_at IS NULL
        LIMIT 1
    ]], { plate, holderId, keyType, keyVersion })

    if existingId then
        MySQL.Async.execute([[
            UPDATE partay_vehicle_keys
            SET owner_id = ?, owner_name = ?, holder_name = ?, possession_id = ?, issued_by = ?, issued_by_name = ?, metadata = ?
            WHERE id = ?
        ]], { ownerId, ownerName, holderName, possessionId, issuedBy, issuedByName, metadata, existingId })
        return true
    end

    MySQL.Async.execute([[
        INSERT INTO partay_vehicle_keys
            (plate, owner_id, owner_name, holder_id, holder_name, key_type, key_version, possession_id, issued_by, issued_by_name, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { plate, ownerId, ownerName, holderId, holderName, keyType, keyVersion, possessionId, issuedBy, issuedByName, metadata })
    return true
end

function PartayKeys_RevokeVehicleKeys(plate, reason, keepHolderId, keepVersion)
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    if not plate or plate == '' then return false end

    local query = 'UPDATE partay_vehicle_keys SET revoked_at = NOW(), revoked_reason = ? WHERE plate = ? AND revoked_at IS NULL'
    local params = { reason or 'revoked', plate }

    if keepHolderId and keepVersion then
        query = query .. ' AND NOT (holder_id = ? AND key_version = ?)'
        params[#params + 1] = keepHolderId
        params[#params + 1] = tonumber(keepVersion) or keepVersion
    end

    MySQL.Async.execute(query, params)
    return true
end

function PartayKeys_GetActiveKeysForHolder(holderId)
    if not holderId or holderId == '' then return {} end

    return MySQL.Sync.fetchAll([[
        SELECT id, plate, owner_id, owner_name, holder_id, holder_name, key_type, key_version, possession_id, issued_by, issued_by_name, issued_at, metadata
        FROM partay_vehicle_keys
        WHERE holder_id = ? AND revoked_at IS NULL
        ORDER BY issued_at DESC, id DESC
    ]], { holderId }) or {}
end

function PartayKeys_GetSharedKeysByOwner(ownerId)
    if not ownerId or ownerId == '' then return {} end

    return MySQL.Sync.fetchAll([[
        SELECT id, plate, owner_id, owner_name, holder_id, holder_name, key_type, key_version, possession_id, issued_by, issued_by_name, issued_at, metadata
        FROM partay_vehicle_keys
        WHERE owner_id = ? AND holder_id <> ? AND key_type = 'shared' AND revoked_at IS NULL
        ORDER BY issued_at DESC, id DESC
    ]], { ownerId, ownerId }) or {}
end

function PartayKeys_CountActiveSharedKeys(plate, ownerId)
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    if not plate or plate == '' then return 0 end

    return tonumber(MySQL.Sync.fetchScalar([[
        SELECT COUNT(*) FROM partay_vehicle_keys
        WHERE plate = ? AND owner_id = ? AND key_type = 'shared' AND revoked_at IS NULL
    ]], { plate, ownerId })) or 0
end

function PartayKeys_GetActiveKeyholders(plate, ownerId)
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    if not plate or plate == '' or not ownerId or ownerId == '' then return {} end

    return MySQL.Sync.fetchAll([[
        SELECT id, holder_id, holder_name, key_type, key_version, issued_at
        FROM partay_vehicle_keys
        WHERE plate = ? AND owner_id = ? AND holder_id <> ? AND revoked_at IS NULL
        ORDER BY key_type ASC, issued_at DESC, id DESC
    ]], { plate, ownerId, ownerId }) or {}
end

local function GetKeyMetadataFromInventory(src, plate, possession_id)
    plate = TrimPlate(plate)
    local items = GetInventoryItems(src)
    for _, item in pairs(items) do
        local itemName = item.name or item.item
        if PartayKeys_IsKeyItem(itemName) then
            local metadata = item.metadata or item.info
            local metadataPlate = metadata and TrimPlate(metadata.plate)
            if metadata and metadataPlate == plate then
                metadata.key_tier = PartayKeys_GetKeyTierFromMetadata(metadata, itemName)
                metadata.key_item = itemName
                return metadata
            elseif not metadata then
                WarnMetadata(('Player %s has vehicle key item "%s" without metadata. Vehicle access checks require a metadata-capable inventory item.'):format(tostring(src), tostring(itemName)))
            elseif plate and not metadata.plate then
                WarnMetadata(('Player %s has vehicle key item "%s" with incomplete metadata. Missing plate value.'):format(tostring(src), tostring(itemName)))
            end
        end
    end
    return nil
end

local function GetUsableItemMetadata(item, data, inventory, slot)
    local metadata = item and (item.metadata or item.info) or data and (data.metadata or data.info)

    if (not metadata or type(metadata) ~= 'table') and type(inventory) == 'table' and slot then
        local slotData = inventory.items and inventory.items[slot]
        metadata = slotData and (slotData.metadata or slotData.info)
    end

    return type(metadata) == 'table' and metadata or {}
end

local function WarnIfVehicleKeyMetadataMissing(src, metadata, context)
    if type(metadata) ~= 'table' or not metadata.plate then
        WarnMetadata(('Vehicle key item was used without plate metadata%s. Check that the configured inventory and item definition support metadata.'):format(
            context and (' via ' .. context) or ''
        ))
    end
end

function PartayKeys_PlayerHasVehicleAccess(src, plate, possession_id, key_version)
    plate = TrimPlate(plate)
    if not plate or plate == '' then return false end

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then return false end

    if IsLocksmithKeyHeld(src, plate) then return false end

    local registration = GetVehicleRegistration(plate)
    if not registration then
        if Config.RequirePhysicalKey then
            return possession_id and possession_id == citizenId and key_version == 'temporary_npc'
        end

        return possession_id and possession_id == citizenId
    end

    if Config.RequirePhysicalKey then
        local metadata = GetKeyMetadataFromInventory(src, plate, possession_id)
        if not metadata then return false end
        return tonumber(metadata.key_version) == GetVehicleKeyVersionFromDB(plate)
    end

    local ownerColumn = GetOwnerColumn()
    local registeredOwnerId = registration[ownerColumn]
    local registeredPossessionId = registration.possession_id

    if registeredOwnerId == citizenId then return true end
    if registeredPossessionId and registeredPossessionId == citizenId then return true end

    local metadata = GetKeyMetadataFromInventory(src, plate, possession_id)
    if metadata then
        return tonumber(metadata.key_version) == GetVehicleKeyVersionFromDB(plate)
    end

    return false
end

lib.callback.register('partay_keys:server:HasIgnitionAccess', function(src, netId, plate)
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    plate = TrimPlate(plate)
    if veh == 0 or not plate or plate == '' then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 8.0 then return false end
    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then return false end

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then return false end
    if Entity(veh).state.hotwiredBy == citizenId then return true end

    local registration = GetVehicleRegistration(plate)
    local possessionId = Entity(veh).state.possession_id
    local keyVersion = registration and tonumber(registration.key_version) or GetVehicleKeyVersionFromDB(plate)

    if registration and registration.possession_id and registration.possession_id ~= '' and registration.possession_id ~= possessionId then
        possessionId = registration.possession_id
        Entity(veh).state:set('possession_id', possessionId, true)
    end

    return PartayKeys_PlayerHasVehicleAccess(src, plate, possessionId, keyVersion)
end)

local function CountPlayerKeys(src, plate)
    local count = 0
    local items = GetInventoryItems(src)
    for _, item in pairs(items) do
        local itemName = item.name or item.item
        if PartayKeys_IsKeyItem(itemName) then
            local metadata = item.metadata or item.info
            if metadata and metadata.plate == plate then
                count = count + 1
            end
        end
    end
    return count
end

-- [[ Zero-Trust Server Authority & Auto-Assert ]] --
AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end

    local function TableExists(tableName)
        local exists = MySQL.Sync.fetchScalar([[
            SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = ?
        ]], {tableName})

        return tonumber(exists) and tonumber(exists) > 0
    end

    local function ColumnExists(tableName, columnName)
        local exists = MySQL.Sync.fetchScalar([[
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = ?
              AND COLUMN_NAME = ?
        ]], {tableName, columnName})

        return tonumber(exists) and tonumber(exists) > 0
    end

    local function AddColumnIfMissing(tableName, columnName, definition)
        if ColumnExists(tableName, columnName) then return end
        MySQL.Sync.execute(('ALTER TABLE %s ADD COLUMN %s %s'):format(QuoteSqlIdentifier(tableName), QuoteSqlIdentifier(columnName), definition))
    end

    local function BackfillPossessionId(tableName)
        if tableName == 'owned_vehicles' then
            MySQL.Sync.execute([[
                UPDATE owned_vehicles
                SET possession_id = owner
                WHERE possession_id IS NULL AND owner IS NOT NULL
            ]])
        else
            MySQL.Sync.execute([[
                UPDATE player_vehicles
                SET possession_id = citizenid
                WHERE possession_id IS NULL AND citizenid IS NOT NULL
            ]])
        end
    end

    local function AssertVehicleTable(tableName)
        if not TableExists(tableName) then
            if Config.DebugMode then print(('^5[ParTay Keys Debug]^3 Skipping database assert for %s (table does not exist).^0'):format(tableName)) end
            return false
        end

        if ColumnExists(tableName, 'possesion_id') and not ColumnExists(tableName, 'possession_id') then
            MySQL.Sync.execute(('ALTER TABLE %s CHANGE COLUMN `possesion_id` `possession_id` VARCHAR(50) DEFAULT NULL'):format(QuoteSqlIdentifier(tableName)))
            exports.partay_keys:SendAuditLog('Database Repair', ('Renamed malformed possession column for %s.'):format(tableName), 'warning')
        end

        AddColumnIfMissing(tableName, 'possession_id', 'VARCHAR(50) DEFAULT NULL')
        AddColumnIfMissing(tableName, 'shared_keys', 'LONGTEXT NULL')
        AddColumnIfMissing(tableName, 'key_version', 'INT(11) DEFAULT 1')
        AddColumnIfMissing(tableName, 'has_alarm', 'TINYINT(1) DEFAULT 0')
        AddColumnIfMissing(tableName, 'alarm_tier', "VARCHAR(40) DEFAULT NULL")
        AddColumnIfMissing(tableName, 'has_tracker', 'TINYINT(1) DEFAULT 0')
        AddColumnIfMissing(tableName, 'gps_tier', "VARCHAR(40) DEFAULT NULL")
        AddColumnIfMissing(tableName, 'tracker_owner_id', 'VARCHAR(50) DEFAULT NULL')
        AddColumnIfMissing(tableName, 'has_valet_module', 'TINYINT(1) DEFAULT 0')
        BackfillPossessionId(tableName)

        return true
    end

    CreateThread(function()
        local fw = Bridge.GetFramework()
        local tableName = (fw == 'esx') and 'owned_vehicles' or 'player_vehicles'
        if AssertVehicleTable(tableName) then
            exports.partay_keys:SendAuditLog('Database Assert', ('Auto-Assert successfully verified database columns for %s.'):format(tableName), 'info')
            if Config.DebugMode then print(('^5[ParTay Keys Debug]^2 Hybrid Auto-Assert Database Injection Complete for %s.^0'):format(tableName)) end
        end

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_vehicle_trackers` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `plate` VARCHAR(20) NOT NULL,
                `tracker_owner_id` VARCHAR(50) DEFAULT NULL,
                `tracker_tier` VARCHAR(40) DEFAULT NULL,
                `note` VARCHAR(255) DEFAULT NULL,
                `installed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                INDEX `idx_partay_trackers_plate` (`plate`),
                INDEX `idx_partay_trackers_owner` (`tracker_owner_id`)
            )
        ]])
        AddColumnIfMissing('partay_vehicle_trackers', 'tracker_tier', "VARCHAR(40) DEFAULT NULL")
        AddColumnIfMissing('partay_vehicle_trackers', 'note', 'VARCHAR(255) DEFAULT NULL')

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_vehicle_keys` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `plate` VARCHAR(20) NOT NULL,
                `owner_id` VARCHAR(50) DEFAULT NULL,
                `owner_name` VARCHAR(100) DEFAULT NULL,
                `holder_id` VARCHAR(50) NOT NULL,
                `holder_name` VARCHAR(100) DEFAULT NULL,
                `key_type` VARCHAR(30) NOT NULL DEFAULT 'owner',
                `key_version` INT(11) NOT NULL DEFAULT 1,
                `possession_id` VARCHAR(50) DEFAULT NULL,
                `issued_by` VARCHAR(50) DEFAULT NULL,
                `issued_by_name` VARCHAR(100) DEFAULT NULL,
                `issued_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `revoked_at` TIMESTAMP NULL DEFAULT NULL,
                `revoked_reason` VARCHAR(80) DEFAULT NULL,
                `last_used_at` TIMESTAMP NULL DEFAULT NULL,
                `metadata` LONGTEXT NULL,
                PRIMARY KEY (`id`),
                INDEX `idx_partay_keys_holder` (`holder_id`),
                INDEX `idx_partay_keys_plate` (`plate`),
                INDEX `idx_partay_keys_owner` (`owner_id`),
                INDEX `idx_partay_keys_revoked` (`revoked_at`)
            )
        ]])
        AddColumnIfMissing('partay_vehicle_keys', 'owner_id', 'VARCHAR(50) DEFAULT NULL')
        AddColumnIfMissing('partay_vehicle_keys', 'owner_name', 'VARCHAR(100) DEFAULT NULL')
        AddColumnIfMissing('partay_vehicle_keys', 'holder_name', 'VARCHAR(100) DEFAULT NULL')
        AddColumnIfMissing('partay_vehicle_keys', 'key_type', "VARCHAR(30) NOT NULL DEFAULT 'owner'")
        AddColumnIfMissing('partay_vehicle_keys', 'key_version', 'INT(11) NOT NULL DEFAULT 1')
        AddColumnIfMissing('partay_vehicle_keys', 'possession_id', 'VARCHAR(50) DEFAULT NULL')
        AddColumnIfMissing('partay_vehicle_keys', 'issued_by', 'VARCHAR(50) DEFAULT NULL')
        AddColumnIfMissing('partay_vehicle_keys', 'issued_by_name', 'VARCHAR(100) DEFAULT NULL')
        AddColumnIfMissing('partay_vehicle_keys', 'revoked_at', 'TIMESTAMP NULL DEFAULT NULL')
        AddColumnIfMissing('partay_vehicle_keys', 'revoked_reason', 'VARCHAR(80) DEFAULT NULL')
        AddColumnIfMissing('partay_vehicle_keys', 'last_used_at', 'TIMESTAMP NULL DEFAULT NULL')
        AddColumnIfMissing('partay_vehicle_keys', 'metadata', 'LONGTEXT NULL')

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_locksmith_stock` (
                `location_name` VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith',
                `item_name` VARCHAR(80) NOT NULL,
                `quantity` INT NOT NULL DEFAULT 0,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`location_name`, `item_name`)
            )
        ]])
        AddColumnIfMissing('partay_locksmith_stock', 'location_name', "VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith'")
        pcall(function()
            MySQL.Sync.execute('ALTER TABLE partay_locksmith_stock DROP PRIMARY KEY')
        end)
        pcall(function()
            MySQL.Sync.execute('ALTER TABLE partay_locksmith_stock ADD PRIMARY KEY (`location_name`, `item_name`)')
        end)

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_locksmith_locations` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `location_name` VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith',
                `shop_type` VARCHAR(30) NOT NULL DEFAULT 'player_owned',
                `job_name` VARCHAR(80) DEFAULT NULL,
                `point_type` VARCHAR(40) NOT NULL,
                `label` VARCHAR(120) DEFAULT NULL,
                `model` VARCHAR(80) DEFAULT NULL,
                `coords` LONGTEXT NOT NULL,
                `target_distance` FLOAT NOT NULL DEFAULT 2.0,
                `active` TINYINT(1) NOT NULL DEFAULT 0,
                `spawn_prop` TINYINT(1) NOT NULL DEFAULT 1,
                `created_by` VARCHAR(50) DEFAULT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `idx_partay_locksmith_location_named_type` (`location_name`, `point_type`)
            )
        ]])
        AddColumnIfMissing('partay_locksmith_locations', 'location_name', "VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith'")
        AddColumnIfMissing('partay_locksmith_locations', 'shop_type', "VARCHAR(30) NOT NULL DEFAULT 'player_owned'")
        AddColumnIfMissing('partay_locksmith_locations', 'job_name', 'VARCHAR(80) DEFAULT NULL')
        AddColumnIfMissing('partay_locksmith_locations', 'active', 'TINYINT(1) NOT NULL DEFAULT 0')
        AddColumnIfMissing('partay_locksmith_locations', 'spawn_prop', 'TINYINT(1) NOT NULL DEFAULT 1')
        AddColumnIfMissing('partay_locksmith_locations', 'stock_method', "VARCHAR(30) NOT NULL DEFAULT 'auto'")
        AddColumnIfMissing('partay_locksmith_locations', 'stock_settings', 'LONGTEXT NULL')
        pcall(function()
            MySQL.Sync.execute('ALTER TABLE partay_locksmith_locations DROP INDEX idx_partay_locksmith_location_type')
        end)
        pcall(function()
            MySQL.Sync.execute('ALTER TABLE partay_locksmith_locations ADD UNIQUE KEY idx_partay_locksmith_location_named_type (location_name, point_type)')
        end)
        RefreshLocksmithRuntimeJobCache('resource_start')

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_locksmith_prices` (
                `location_name` VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith',
                `price_key` VARCHAR(120) NOT NULL,
                `price` INT NOT NULL DEFAULT 0,
                `updated_by` VARCHAR(50) DEFAULT NULL,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`location_name`, `price_key`)
            )
        ]])
        AddColumnIfMissing('partay_locksmith_prices', 'location_name', "VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith'")
        pcall(function()
            MySQL.Sync.execute('ALTER TABLE partay_locksmith_prices DROP PRIMARY KEY')
        end)
        pcall(function()
            MySQL.Sync.execute('ALTER TABLE partay_locksmith_prices ADD PRIMARY KEY (`location_name`, `price_key`)')
        end)

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_locksmith_settings` (
                `location_name` VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith',
                `setting_key` VARCHAR(80) NOT NULL,
                `setting_value` VARCHAR(255) DEFAULT NULL,
                `updated_by` VARCHAR(50) DEFAULT NULL,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`location_name`, `setting_key`)
            )
        ]])
        AddColumnIfMissing('partay_locksmith_settings', 'location_name', "VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith'")
        pcall(function()
            MySQL.Sync.execute('ALTER TABLE partay_locksmith_settings DROP PRIMARY KEY')
        end)
        pcall(function()
            MySQL.Sync.execute('ALTER TABLE partay_locksmith_settings ADD PRIMARY KEY (`location_name`, `setting_key`)')
        end)

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_locksmith_stock_orders` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `order_id` VARCHAR(80) NOT NULL,
                `location_name` VARCHAR(80) DEFAULT NULL,
                `stock_method` VARCHAR(30) NOT NULL DEFAULT 'auto',
                `item_name` VARCHAR(80) NOT NULL,
                `label` VARCHAR(120) DEFAULT NULL,
                `quantity` INT NOT NULL DEFAULT 1,
                `total` INT NOT NULL DEFAULT 0,
                `order_items` LONGTEXT NULL,
                `status` VARCHAR(30) NOT NULL DEFAULT 'pending',
                `ordered_by` VARCHAR(50) DEFAULT NULL,
                `ordered_by_name` VARCHAR(100) DEFAULT NULL,
                `pickup_coords` LONGTEXT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `ready_at` TIMESTAMP NULL DEFAULT NULL,
                `completed_at` TIMESTAMP NULL DEFAULT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `idx_partay_locksmith_stock_order_id` (`order_id`),
                INDEX `idx_partay_locksmith_stock_order_status` (`status`),
                INDEX `idx_partay_locksmith_stock_order_location` (`location_name`)
            )
        ]])
        AddColumnIfMissing('partay_locksmith_stock_orders', 'order_items', 'LONGTEXT NULL')

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_locksmith_shop_orders` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `order_id` VARCHAR(80) NOT NULL,
                `location_name` VARCHAR(80) DEFAULT NULL,
                `item_name` VARCHAR(80) NOT NULL,
                `label` VARCHAR(120) DEFAULT NULL,
                `quantity` INT NOT NULL DEFAULT 1,
                `total` INT NOT NULL DEFAULT 0,
                `status` VARCHAR(30) NOT NULL DEFAULT 'pending',
                `customer_id` VARCHAR(50) DEFAULT NULL,
                `customer_name` VARCHAR(100) DEFAULT NULL,
                `employee_id` VARCHAR(50) DEFAULT NULL,
                `employee_name` VARCHAR(100) DEFAULT NULL,
                `payment_method` VARCHAR(30) DEFAULT NULL,
                `pickup_coords` LONGTEXT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `idx_partay_locksmith_shop_order_id` (`order_id`),
                INDEX `idx_partay_locksmith_shop_order_status` (`status`),
                INDEX `idx_partay_locksmith_shop_order_customer` (`customer_id`),
                INDEX `idx_partay_locksmith_shop_order_location` (`location_name`)
            )
        ]])

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_locksmith_appointments` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `appointment_id` VARCHAR(80) NOT NULL,
                `customer_id` VARCHAR(50) DEFAULT NULL,
                `customer_name` VARCHAR(100) DEFAULT NULL,
                `contact_name` VARCHAR(100) DEFAULT NULL,
                `contact_phone` VARCHAR(80) DEFAULT NULL,
                `contact_email` VARCHAR(120) DEFAULT NULL,
                `plate` VARCHAR(20) DEFAULT NULL,
                `message` VARCHAR(255) DEFAULT NULL,
                `status` VARCHAR(30) NOT NULL DEFAULT 'pending',
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `expires_at` TIMESTAMP NULL DEFAULT NULL,
                `accepted_by` VARCHAR(50) DEFAULT NULL,
                `accepted_by_name` VARCHAR(100) DEFAULT NULL,
                `scheduled_for` VARCHAR(80) DEFAULT NULL,
                `scheduled_date` VARCHAR(40) DEFAULT NULL,
                `scheduled_time` VARCHAR(40) DEFAULT NULL,
                `schedule_note` VARCHAR(255) DEFAULT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `idx_partay_locksmith_appointment_id` (`appointment_id`),
                INDEX `idx_partay_locksmith_appointment_status` (`status`)
            )
        ]])
        AddColumnIfMissing('partay_locksmith_appointments', 'contact_name', 'VARCHAR(100) DEFAULT NULL')
        AddColumnIfMissing('partay_locksmith_appointments', 'contact_phone', 'VARCHAR(80) DEFAULT NULL')
        AddColumnIfMissing('partay_locksmith_appointments', 'contact_email', 'VARCHAR(120) DEFAULT NULL')
        AddColumnIfMissing('partay_locksmith_appointments', 'scheduled_for', 'VARCHAR(80) DEFAULT NULL')
        AddColumnIfMissing('partay_locksmith_appointments', 'scheduled_date', 'VARCHAR(40) DEFAULT NULL')
        AddColumnIfMissing('partay_locksmith_appointments', 'scheduled_time', 'VARCHAR(40) DEFAULT NULL')
        AddColumnIfMissing('partay_locksmith_appointments', 'schedule_note', 'VARCHAR(255) DEFAULT NULL')

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_locksmith_invoices` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `invoice_id` VARCHAR(80) NOT NULL,
                `location_name` VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith',
                `employee_id` VARCHAR(50) DEFAULT NULL,
                `employee_name` VARCHAR(100) DEFAULT NULL,
                `customer_id` VARCHAR(50) DEFAULT NULL,
                `customer_name` VARCHAR(100) DEFAULT NULL,
                `plate` VARCHAR(20) DEFAULT NULL,
                `status` VARCHAR(30) NOT NULL DEFAULT 'pending',
                `total` INT NOT NULL DEFAULT 0,
                `services` LONGTEXT NULL,
                `payment_method` VARCHAR(30) DEFAULT NULL,
                `society_deposit` INT NOT NULL DEFAULT 0,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `idx_partay_locksmith_invoice_id` (`invoice_id`),
                INDEX `idx_partay_locksmith_invoice_status` (`status`),
                INDEX `idx_partay_locksmith_invoice_location` (`location_name`),
                INDEX `idx_partay_locksmith_invoice_employee` (`employee_id`),
                INDEX `idx_partay_locksmith_invoice_customer` (`customer_id`)
            )
        ]])
        AddColumnIfMissing('partay_locksmith_invoices', 'location_name', "VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith'")

        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `partay_locksmith_logs` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `location_name` VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith',
                `action` VARCHAR(80) NOT NULL,
                `message` VARCHAR(255) DEFAULT NULL,
                `actor_id` VARCHAR(50) DEFAULT NULL,
                `actor_name` VARCHAR(100) DEFAULT NULL,
                `target_id` VARCHAR(50) DEFAULT NULL,
                `target_name` VARCHAR(100) DEFAULT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                INDEX `idx_partay_locksmith_logs_location` (`location_name`),
                INDEX `idx_partay_locksmith_logs_action` (`action`),
                INDEX `idx_partay_locksmith_logs_actor` (`actor_id`),
                INDEX `idx_partay_locksmith_logs_target` (`target_id`)
            )
        ]])
        AddColumnIfMissing('partay_locksmith_logs', 'location_name', "VARCHAR(80) NOT NULL DEFAULT 'Main Locksmith'")

        local retentionDays = math.floor(tonumber(Config.KeyHistoryRetentionDays) or 30)
        if retentionDays > 0 then
            MySQL.Async.execute(('DELETE FROM partay_vehicle_keys WHERE revoked_at IS NOT NULL AND revoked_at < (NOW() - INTERVAL %d DAY)'):format(retentionDays))
        end
    end)
end)

-- [[ Heist Minigame Token Generation ]] --
RegisterNetEvent('partay_keys:server:RequestHeistToken', function(plate, netId)
    local src = source
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    if not Config.Heist.EnableLockpicking then
        Notify(src, T('label_vehicle_theft'), T('error_lockpicking_disabled'), 'error')
        return false
    end

    local policeAllowed, policeOnline, policeRequired = MeetsPoliceRequirement('Lockpick')
    if not policeAllowed then
        Notify(src, T('label_vehicle_theft'), T('error_lockpick_police_required', { required = policeRequired, current = policeOnline }), 'error')
        return false
    end

    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or GetPlayerDistanceToEntity(src, veh) > 5.0 then
        Notify(src, T('label_vehicle_theft'), T('error_lockpick_too_far'), 'error')
        return false
    end
    if GetVehicleNumberPlateText(veh):gsub('^%s*(.-)%s*$', '%1') ~= plate then
        Notify(src, T('label_vehicle_theft'), T('error_lockpick_verify_failed'), 'error')
        return false
    end
    if not HasDoorLockStep(veh) then
        Notify(src, T('label_vehicle_theft'), T('info_lockpick_not_required'), 'info')
        return false
    end

    if not HasLockpickTool(src) then
        Notify(src, T('label_vehicle_theft'), T('error_need_lockpick'), 'error')
        return false
    end

    local token = math.random(100000, 999999)
    ActiveHeists[src] = { token = token, plate = plate, netId = netId, heistType = 'lockpick', startTime = os.time() }
    
    exports.partay_keys:SendAuditLog('Heist Initiated', ('Player %s requested minigame token for vehicle %s'):format(src, plate), 'info')
    TriggerClientEvent('partay_keys:client:StartMinigame', src, token, 'lockpick')
end)

local function ValidateHotwireRequest(src, netId, plate)
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    plate = TrimPlate(plate)
    if veh == 0 or not plate or plate == '' then
        Notify(src, T('label_hotwire'), T('error_hotwire_no_vehicle'), 'error')
        return false
    end
    if GetPlayerDistanceToEntity(src, veh) > 5.0 then
        Notify(src, T('label_hotwire'), T('error_hotwire_too_far'), 'error')
        return false
    end
    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then
        Notify(src, T('label_hotwire'), T('error_hotwire_verify_failed'), 'error')
        return false
    end

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then
        Notify(src, T('label_hotwire'), T('error_character_unavailable'), 'error')
        return false
    end

    if not RequiresHotwire(veh) then
        Entity(veh).state:set('hotwiredBy', citizenId, true)
        Notify(src, T('label_hotwire'), T('info_hotwire_not_required'), 'info')
        return false
    end

    if not HasSatisfiedLockStep(veh, citizenId) then
        TriggerInstalledAlarm(veh, false)
        Notify(src, T('label_hotwire'), T('error_hotwire_lockpick_first'), 'error')
        return false
    end

    if Config.Items.WiringKit and not Bridge.HasInventoryItem(src, Config.Items.WiringKit, 1) then
        Notify(src, T('label_hotwire'), T('error_need_wiring_kit'), 'error')
        return false
    end

    return true, veh, citizenId, plate
end

function PartayKeys_CompleteHotwire(src, netId, plate)
    local valid, veh, citizenId = ValidateHotwireRequest(src, netId, plate)
    if not valid then return false end

    if Config.Items.WiringKit and not Bridge.RemoveInventoryItem(src, Config.Items.WiringKit, 1) then
        Notify(src, T('label_hotwire'), T('error_use_wiring_kit_failed'), 'error')
        return false
    end

    Entity(veh).state:set('possession_id', citizenId, true)
    Entity(veh).state:set('hotwiredBy', citizenId, true)
    Entity(veh).state:set('isStolen', true, true)

    SetVehicleDoorsLocked(veh, UNLOCKED)
    Entity(veh).state:set('lockState', UNLOCKED, true)

    if Config.RequirePhysicalKey then
        Notify(src, T('label_hotwire'), T('success_hotwire_decode_required'), 'success')
    else
        Notify(src, T('label_hotwire'), T('success_temporary_access'), 'success')
    end

    exports.partay_keys:SendAuditLog('Vehicle Hotwired', ('Player %s hotwired vehicle %s'):format(src, plate), 'info')
    return true
end

RegisterNetEvent('partay_keys:server:RequestHotwire', function(netId, plate)
    local src = source
    if not Config.Heist.EnableHotwiring then
        Notify(src, T('label_hotwire'), T('error_hotwiring_disabled'), 'error')
        return false
    end

    local valid, _veh, _citizenId, cleanPlate = ValidateHotwireRequest(src, netId, plate)
    if not valid then return end

    local token = math.random(100000, 999999)
    ActiveHeists[src] = { token = token, plate = cleanPlate, netId = netId, heistType = 'hotwire', startTime = os.time() }

    exports.partay_keys:SendAuditLog('Hotwire Initiated', ('Player %s requested hotwire token for vehicle %s'):format(src, cleanPlate), 'info')
    TriggerClientEvent('partay_keys:client:StartMinigame', src, token, 'hotwire')
end)

RegisterNetEvent('partay_keys:server:RobNpcVehicleKeys', function(netId, plate)
    local src = source
    local enabled, robbery = IsNpcVehicleRobberyEnabled()
    DebugNpcRobberyServer(('request src=%s netId=%s plate=%s enabled=%s'):format(tostring(src), tostring(netId), tostring(plate), tostring(enabled)))
    if not enabled then return end

    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    plate = TrimPlate(plate)
    if veh == 0 or not DoesEntityExist(veh) or not plate or plate == '' then
        DebugNpcRobberyServer(('reject invalid vehicle src=%s veh=%s plate=%s'):format(tostring(src), tostring(veh), tostring(plate)))
        Notify(src, T('label_vehicle_robbery'), T('error_robbery_vehicle_unavailable'), 'error')
        return
    end

    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then
        DebugNpcRobberyServer(('reject plate mismatch src=%s vehPlate=%s plate=%s'):format(tostring(src), tostring(GetVehicleNumberPlateText(veh)), tostring(plate)))
        Notify(src, T('label_vehicle_robbery'), T('error_robbery_verify_failed'), 'error')
        return
    end

    local maxDistance = tonumber(robbery.MaxDistance) or 12.0
    if GetPlayerDistanceToEntity(src, veh) > maxDistance + 1.0 then
        DebugNpcRobberyServer(('reject distance src=%s dist=%s max=%s'):format(tostring(src), tostring(GetPlayerDistanceToEntity(src, veh)), tostring(maxDistance)))
        Notify(src, T('label_vehicle_robbery'), T('error_robbery_too_far'), 'error')
        return
    end

    if GetVehicleRegistration(plate) then
        DebugNpcRobberyServer(('reject registered vehicle src=%s plate=%s'):format(tostring(src), tostring(plate)))
        Notify(src, T('label_vehicle_robbery'), T('error_robbery_registered_vehicle'), 'error')
        return
    end

    local driverOk, driver = pcall(GetPedInVehicleSeat, veh, -1)
    if not driverOk or not driver or driver == 0 or not DoesEntityExist(driver) then
        DebugNpcRobberyServer(('reject no driver src=%s driverOk=%s driver=%s'):format(tostring(src), tostring(driverOk), tostring(driver)))
        Notify(src, T('label_vehicle_robbery'), T('error_robbery_no_driver'), 'error')
        return
    end

    if IsPlayerPedEntity(driver) then
        DebugNpcRobberyServer(('reject player driver src=%s driver=%s plate=%s'):format(tostring(src), tostring(driver), tostring(plate)))
        exports.partay_keys:SendAuditLog('Exploit Attempt', ('Player %s attempted NPC robbery against a player driver on %s'):format(src, plate), 'exploit')
        return
    end

    local cooldown = tonumber(robbery.Cooldown) or 8000
    local now = os.time() * 1000
    local cooldownKey = ('%s:%s'):format(src, plate)
    if NpcVehicleRobberyCooldowns[cooldownKey] and now - NpcVehicleRobberyCooldowns[cooldownKey] < cooldown then
        DebugNpcRobberyServer(('reject cooldown src=%s plate=%s remaining=%s'):format(tostring(src), tostring(plate), tostring(cooldown - (now - NpcVehicleRobberyCooldowns[cooldownKey]))))
        return
    end
    NpcVehicleRobberyCooldowns[cooldownKey] = now

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then
        DebugNpcRobberyServer(('reject no citizen src=%s'):format(tostring(src)))
        Notify(src, T('label_vehicle_robbery'), T('error_character_unavailable'), 'error')
        return
    end

    Entity(veh).state:set('possession_id', citizenId, true)
    Entity(veh).state:set('hotwiredBy', citizenId, true)
    Entity(veh).state:set('isStolen', true, true)
    Entity(veh).state:set('npcRobberyKeysGranted', citizenId, true)
    Entity(veh).state:set('lockState', UNLOCKED, true)
    SetVehicleDoorsLocked(veh, UNLOCKED)

    DebugNpcRobberyServer(('grant src=%s citizen=%s plate=%s veh=%s driver=%s'):format(tostring(src), tostring(citizenId), tostring(plate), tostring(veh), tostring(driver)))
    Notify(src, T('label_vehicle_robbery'), T('success_robbery_keys_surrendered'), 'success')
    exports.partay_keys:SendAuditLog('NPC Vehicle Robbery', ('Player %s robbed temporary keys for NPC vehicle %s'):format(src, plate), 'info')
    TriggerClientEvent('partay_keys:client:NpcVehicleRobberyComplete', src, netId)
end)

-- Clean up tokens on disconnect
AddEventHandler('playerDropped', function(reason)
    local src = source
    if ActiveHeists[src] then ActiveHeists[src] = nil end
    ConfirmedLocksmithServices[src] = nil

    for requestId, request in pairs(PendingLocksmithServices) do
        if request.employeeId == src or request.customerId == src then
            PendingLocksmithServices[requestId] = nil
        end
    end

    for invoiceId, invoice in pairs(PendingLocksmithInvoices) do
        if invoice.employeeId == src or invoice.customerId == src then
            PendingLocksmithInvoices[invoiceId] = nil
        end
    end

    for jobId, job in pairs(ActiveLocksmithJobs) do
        if job.employeeId == src or job.customerId == src then
            ReleaseLocksmithHeldKeys(job)
            ActiveLocksmithJobs[jobId] = nil
        end
    end

    local prefix = tostring(src) .. ':'
    for cooldownKey in pairs(NpcVehicleRobberyCooldowns) do
        if cooldownKey:sub(1, #prefix) == prefix then
            NpcVehicleRobberyCooldowns[cooldownKey] = nil
        end
    end
end)

-- [[ Locksmith & Re-Keying Protocol ]] --
RegisterNetEvent('partay_keys:server:ReKeyVehicle', function(plate, paymentMethod)
    local src = source
    if not plate or plate == '' then return end
    plate = plate:gsub('^%s*(.-)%s*$', '%1')
    paymentMethod = paymentMethod == 'bank' and 'bank' or 'cash'
    local confirmedService = ConsumeConfirmedLocksmithService(src, 'rekey', plate)

    if not confirmedService and Config.Heist.ReKeyRequiresLocksmith and IsLocksmithEnabled() and not IsPlayerNearLocksmith(src, 10.0) then
        Notify(src, 'Re-Key', 'Visit a locksmith to re-key this vehicle.', 'error')
        return false
    end

    local allowedLocksmith, locksmithReason = CanUseLocksmithService(src)
    if not confirmedService and Config.Heist.ReKeyRequiresLocksmith and IsLocksmithEnabled() and not allowedLocksmith then
        Notify(src, T('label_locksmith'), T(GetLocksmithAccessError(locksmithReason)), 'error')
        return false
    end

    local registration = GetVehicleRegistration(plate)
    if not registration then
        Notify(src, 'Re-Key', 'That vehicle is not registered in the system.', 'error')
        return false
    end

    local citizenId = Bridge.GetCitizenID(src)
    local ownerColumn = GetOwnerColumn()
    if registration[ownerColumn] ~= citizenId then
        Notify(src, 'Re-Key', 'You are not the registered owner of that vehicle.', 'error')
        return false
    end

    local currentVersion = tonumber(registration.key_version) or GetVehicleKeyVersionFromDB(plate)
    local nextVersion = currentVersion + 1
    local currentMetadata = GetKeyMetadataFromInventory(src, plate, registration.possession_id or citizenId)
    local keyTier = currentMetadata and PartayKeys_GetKeyTierFromMetadata(currentMetadata) or GetActiveKeyTierFromDB(plate, citizenId)
    local fee = GetLocksmithDefaultServiceFee('rekey')
    if fee > 0 and not (confirmedService and confirmedService.paid == true) then
        if not Bridge.HasCurrency(src, paymentMethod, fee) then
            Notify(src, 'Re-Key', ('You cannot afford the locksmith fee using %s.'):format(paymentMethod), 'error')
            return
        end
        Bridge.RemoveCurrency(src, paymentMethod, fee)
    end

    local storage = GetVehicleStorage()
    MySQL.Sync.execute(('UPDATE %s SET key_version = ?, shared_keys = ?, possession_id = ? WHERE plate = ? AND %s = ?'):format(storage.tableSql, storage.ownerSql), {nextVersion, '[]', citizenId, plate, citizenId})
    RemovePhysicalVehicleKeys(src, plate, currentVersion)
    SyncLiveVehiclePossession(plate, citizenId, citizenId, false)

    if PartayKeys_RevokeVehicleKeys then
        PartayKeys_RevokeVehicleKeys(plate, 'rekeyed')
    end

    if Config.RequirePhysicalKey then
        Bridge.GiveVehicleKey(src, plate, registration.vehicle or registration.model or 'Vehicle', nextVersion, citizenId, {
            key_tier = keyTier
        })
    end

    exports.partay_keys:SendAuditLog('Vehicle Re-Keyed', ('Player %s re-keyed vehicle %s to version %s and reclaimed possession'):format(src, plate, nextVersion), 'info')
    Notify(src, 'Re-Key', 'Vehicle locks have been refreshed. Old physical keys are now invalid.', 'success')
    PayLocksmithEmployeeCommission(confirmedService, fee, 're-key')
end)

RegisterNetEvent('partay_keys:server:UpgradeKeySystem', function(plate, keyTier, paymentMethod)
    local src = source
    if not plate or plate == '' then return end

    plate = TrimPlate(plate)
    keyTier = tostring(keyTier or ''):gsub('^%s*(.-)%s*$', '%1')
    paymentMethod = paymentMethod == 'bank' and 'bank' or 'cash'
    local confirmedService = ConsumeConfirmedLocksmithService(src, 'upgrade', plate)

    local normalizedTier, tierConfig = PartayKeys_GetKeyTierConfig(keyTier)
    keyTier = normalizedTier
    if not tierConfig or not tierConfig.Item then
        Notify(src, T('label_key_system'), T('error_key_system_unavailable'), 'error')
        return false
    end

    if not confirmedService and IsLocksmithKeyTierServiceEnabled() and not IsPlayerNearLocksmith(src, 10.0) then
        Notify(src, T('label_key_system'), T('error_key_system_visit_locksmith'), 'error')
        return false
    end

    local allowedLocksmith, locksmithReason = CanUseLocksmithService(src)
    if not confirmedService and IsLocksmithKeyTierServiceEnabled() and not allowedLocksmith then
        Notify(src, T('label_locksmith'), T(GetLocksmithAccessError(locksmithReason)), 'error')
        return false
    end

    local registration = GetVehicleRegistration(plate)
    if not registration then
        Notify(src, T('label_key_system'), T('error_key_system_unregistered'), 'error')
        return false
    end

    local citizenId = Bridge.GetCitizenID(src)
    local ownerColumn = GetOwnerColumn()
    if registration[ownerColumn] ~= citizenId then
        Notify(src, T('label_key_system'), T('error_key_system_not_owner'), 'error')
        return
    end

    local currentMetadata = GetKeyMetadataFromInventory(src, plate, registration.possession_id or citizenId)
    local currentTier = currentMetadata and PartayKeys_GetKeyTierFromMetadata(currentMetadata) or GetActiveKeyTierFromDB(plate, citizenId)
    if currentTier == keyTier then
        Notify(src, T('label_key_system'), T('error_key_system_current'), 'info')
        return
    end

    local currentVersion = tonumber(registration.key_version) or GetVehicleKeyVersionFromDB(plate)
    local nextVersion = currentVersion + 1
    local fee = tonumber(tierConfig.UpgradePrice) or 0
    if fee > 0 and not (confirmedService and confirmedService.paid == true) then
        if not Bridge.HasCurrency(src, paymentMethod, fee) then
            Notify(src, T('label_key_system'), T('error_key_system_cannot_afford', { payment = paymentMethod }), 'error')
            return
        end
        Bridge.RemoveCurrency(src, paymentMethod, fee)
    end

    local storage = GetVehicleStorage()
    MySQL.Sync.execute(('UPDATE %s SET key_version = ?, shared_keys = ?, possession_id = ? WHERE plate = ? AND %s = ?'):format(storage.tableSql, storage.ownerSql), {nextVersion, '[]', citizenId, plate, citizenId})
    RemovePhysicalVehicleKeys(src, plate, currentVersion)
    SyncLiveVehiclePossession(plate, citizenId, citizenId, false)

    if PartayKeys_RevokeVehicleKeys then
        PartayKeys_RevokeVehicleKeys(plate, 'key_system_changed')
    end

    if Config.RequirePhysicalKey then
        Bridge.GiveVehicleKey(src, plate, registration.vehicle or registration.model or 'Vehicle', nextVersion, citizenId, {
            key_tier = keyTier
        })
    end

    local currentRank = GetKeyTierRank(currentTier)
    local targetRank = GetKeyTierRank(keyTier)
    local actionWord = 'changed'
    if currentRank > 0 and targetRank > 0 and targetRank > currentRank then
        actionWord = 'upgraded'
    elseif currentRank > 0 and targetRank > 0 and targetRank < currentRank then
        actionWord = 'downgraded'
    end

    exports.partay_keys:SendAuditLog('Key System Changed', ('Player %s %s vehicle %s from %s to %s/version %s'):format(src, actionWord, plate, currentTier or 'unknown', keyTier, nextVersion), 'info')
    Notify(src, T('label_key_system'), T('success_key_system_changed', {
        action = actionWord,
        label = tierConfig.UpgradeLabel or tierConfig.Label or keyTier
    }), 'success')
    PayLocksmithEmployeeCommission(confirmedService, fee, actionWord)
end)

-- [[ Key Management & Usability ]] --
RegisterNetEvent('partay_keys:server:RequestKeyMenu', function()
    local src = source
    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then return end

    local function DecodeRecordMetadata(record)
        if type(record.metadata) ~= 'string' or record.metadata == '' then return {} end

        local ok, decoded = pcall(json.decode, record.metadata)
        return ok and type(decoded) == 'table' and decoded or {}
    end

    local function HasPhysicalKeyForRecord(record)
        local metadata = GetKeyMetadataFromInventory(src, record.plate, record.possession_id)
        if not metadata then return false end
        return tonumber(metadata.key_version) == tonumber(record.key_version)
    end

    local function FormatKeyLabel(label, plate)
        plate = TrimPlate(plate)
        label = label and tostring(label):gsub('^%s*(.-)%s*$', '%1') or ''
        if label == '' then
            label = T('label_vehicle')
        end

        if plate and plate ~= '' and not label:find(plate, 1, true) then
            return ('%s (%s)'):format(label, plate)
        end

        return label
    end

    local function BuildMenuRecord(record)
        local metadata = DecodeRecordMetadata(record)
        local keyTier = PartayKeys_GetKeyTierFromMetadata(metadata)
        local label = metadata.vehicle_label or metadata.brand or metadata.label or T('label_vehicle')
        return {
            id = record.id,
            plate = record.plate,
            possession_id = record.possession_id,
            key_type = record.key_type,
            key_version = record.key_version,
            holder_id = record.holder_id,
            holder_name = record.holder_name,
            owner_id = record.owner_id,
            owner_name = record.owner_name,
            issued_by = record.issued_by,
            issued_by_name = record.issued_by_name,
            has_physical = HasPhysicalKeyForRecord(record),
            key_tier = keyTier,
            label = FormatKeyLabel(label, record.plate)
        }
    end

    local menuData = {
        owned = {},
        shared = {},
        stolen = {},
        sharedOut = {}
    }

    local records = PartayKeys_GetActiveKeysForHolder and PartayKeys_GetActiveKeysForHolder(citizenId) or {}
    for _, record in ipairs(records) do
        local item = BuildMenuRecord(record)
        if record.key_type == 'owner' then
            menuData.owned[#menuData.owned + 1] = item
        elseif record.key_type == 'shared' then
            menuData.shared[#menuData.shared + 1] = item
        else
            menuData.stolen[#menuData.stolen + 1] = item
        end
    end

    local sharedOut = PartayKeys_GetSharedKeysByOwner and PartayKeys_GetSharedKeysByOwner(citizenId) or {}
    for _, record in ipairs(sharedOut) do
        menuData.sharedOut[#menuData.sharedOut + 1] = BuildMenuRecord(record)
    end

    if #menuData.owned > 0 or #menuData.shared > 0 or #menuData.stolen > 0 or #menuData.sharedOut > 0 then
        TriggerClientEvent('partay_keys:client:OpenKeyMenu', src, menuData)
        return
    end

    local keyData = {}
    local items = GetInventoryItems(src)

    for _, item in pairs(items) do
        local itemName = item.name or item.item
        if PartayKeys_IsKeyItem(itemName) then
            local metadata = item.metadata or item.info
            if metadata and metadata.plate then
                local label = metadata.vehicle_label or metadata.brand or metadata.label or 'Vehicle'
                table.insert(keyData, {
                    plate = metadata.plate,
                    possession_id = metadata.possession_id,
                    key_tier = PartayKeys_GetKeyTierFromMetadata(metadata, itemName),
                    label = FormatKeyLabel(label, metadata.plate)
                })
            end
        end
    end

    TriggerClientEvent('partay_keys:client:OpenKeyMenu', src, keyData)
end)

lib.callback.register('partay_keys:server:GetVehicleKeyholders', function(src, plate)
    local citizenId = Bridge.GetCitizenID(src)
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    if not citizenId or not plate or plate == '' then return {} end

    return PartayKeys_GetActiveKeyholders and PartayKeys_GetActiveKeyholders(plate, citizenId) or {}
end)

lib.callback.register('partay_keys:server:GetProximityKeyTargets', function(src)
    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then return {} end

    local records = PartayKeys_GetActiveKeysForHolder and PartayKeys_GetActiveKeysForHolder(citizenId) or {}
    local targets = {}
    local seen = {}

    for _, record in ipairs(records) do
        local metadata = record and record.metadata or {}
        if type(metadata) == 'string' and metadata ~= '' then
            local ok, decoded = pcall(json.decode, metadata)
            metadata = ok and type(decoded) == 'table' and decoded or {}
        elseif type(metadata) ~= 'table' then
            metadata = {}
        end
        local tier = metadata.key_tier or record.key_tier or Config.DefaultKeyTier or 'smart'
        local plate = TrimPlate(record and record.plate)
        if plate and plate ~= '' and not seen[plate] and PartayKeys_KeyTierHasCapability(tier, 'proximity') then
            seen[plate] = true
            targets[#targets + 1] = {
                plate = plate,
                tier = tier,
                unlockDistance = PartayKeys_GetKeyTierNumber(tier, 'Proximity', 'UnlockDistance', 4.0),
                lockDistance = PartayKeys_GetKeyTierNumber(tier, 'Proximity', 'LockDistance', 8.0)
            }
        end
    end

    return targets
end)

lib.callback.register('partay_keys:server:GetLocksmithAccess', function(src)
    if not IsLocksmithEnabled() then
        return { allowed = false, reason = 'unavailable' }
    end

    local allowed, mode = CanUseLocksmithService(src)
    return {
        allowed = allowed == true,
        reason = mode,
        isEmployee = IsPlayerLocksmithEmployee(src),
        isOwner = IsPlayerLocksmithOwner(src),
        onlineEmployees = CountOnlineLocksmithEmployees()
    }
end)

lib.callback.register('partay_keys:server:GetLocksmithPrices', function(src)
    return BuildLocksmithPricePayload(GetLocksmithBusinessLocationName(src))
end)

lib.callback.register('partay_keys:server:GetLocksmithServiceVehicles', function(src, vehicles)
    if type(vehicles) ~= 'table' then return {} end

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then return {} end

    local playerRun = GetLocksmithPlayerRunConfig()
    local isEmployee = playerRun and IsPlayerLocksmithEmployee(src)
    local customerRange = playerRun and tonumber(playerRun.CustomerRange) or 6.0
    local payload = {}
    local seen = {}
    local storage = GetVehicleStorage()
    local ownerColumn = storage.ownerColumn

    for _, data in ipairs(vehicles) do
        local plate = TrimPlate(type(data) == 'table' and data.plate or data)
        if plate and plate ~= '' and not seen[plate] then
            seen[plate] = true
            local rows = MySQL.Sync.fetchAll(('SELECT * FROM %s WHERE plate = ? LIMIT 1'):format(storage.tableSql), { plate })
            local registration = rows and rows[1]

            if registration then
                local ownerId = registration[ownerColumn]
                local targetSrc = ownerId and FindOnlineOwnerNearEmployee(ownerId, src, customerRange) or nil
                local canUse = false

                if isEmployee and targetSrc then
                    canUse = true
                elseif ownerId == citizenId then
                    canUse = true
                    targetSrc = src
                end

                if canUse then
                    payload[#payload + 1] = {
                        plate = plate,
                        label = type(data) == 'table' and data.label or 'Vehicle',
                        distance = type(data) == 'table' and tonumber(data.distance) or 0.0,
                        netId = type(data) == 'table' and tonumber(data.netId) or 0,
                        customerId = targetSrc,
                        customerName = targetSrc and (Bridge.GetCharacterName and Bridge.GetCharacterName(targetSrc) or GetPlayerName(targetSrc)) or nil,
                        employeeService = isEmployee and targetSrc ~= src or false,
                        currentTier = GetActiveKeyTierFromDB(plate, ownerId)
                    }
                end
            end
        end
    end

    return payload
end)

lib.callback.register('partay_keys:server:GetActiveLocksmithJob', function(src)
    for jobId, job in pairs(ActiveLocksmithJobs) do
        if job.employeeId == src then
            if job.expiresAt < os.time() then
                ReleaseLocksmithHeldKeys(job)
                ActiveLocksmithJobs[jobId] = nil
            else
                return job
            end
        end
    end

    return nil
end)

local function GetOnlineLocksmithEmployees()
    local employees = {}
    local playerRun = GetLocksmithPlayerRunConfig() or {}
    local locksmithJobs = GetLocksmithRuntimeJobNames(false)

    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        local job = targetSrc and Bridge.GetPlayerJob(targetSrc)
        if job and job.name then
            for _, jobName in ipairs(locksmithJobs) do
                if JobMatches(job, jobName) then
                    employees[#employees + 1] = {
                        source = targetSrc,
                        name = Bridge.GetCharacterName and Bridge.GetCharacterName(targetSrc) or GetPlayerName(targetSrc),
                        grade = GetJobGradeLevel(job),
                        duty = job.onduty ~= false
                    }
                    break
                end
            end
        end
    end

    return employees
end

local function GetNearbyLocksmithCandidates(src)
    local candidates = {}
    local business = GetLocksmithBusinessConfig() or {}
    local locksmithJobs = GetLocksmithRuntimeJobNames(false)
    local ownerPed = GetPlayerPed(src)
    local hireRange = tonumber(business.HireRange) or 6.0
    if not ownerPed or ownerPed == 0 then return candidates end

    local ownerCoords = GetEntityCoords(ownerPed)
    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        if targetSrc and targetSrc ~= src then
            local targetPed = GetPlayerPed(targetSrc)
            if targetPed and targetPed ~= 0 and #(ownerCoords - GetEntityCoords(targetPed)) <= hireRange then
                local job = Bridge.GetPlayerJob(targetSrc)
                local isEmployee = false
                for _, jobName in ipairs(locksmithJobs) do
                    if JobMatches(job, jobName) then isEmployee = true break end
                end
                if not isEmployee then
                    candidates[#candidates + 1] = {
                        source = targetSrc,
                        name = Bridge.GetCharacterName and Bridge.GetCharacterName(targetSrc) or GetPlayerName(targetSrc)
                    }
                end
            end
        end
    end

    return candidates
end

local function BuildLocksmithReports(locationName)
    locationName = GetLocksmithBusinessLocationName(locationName)
    return {
        paidTotal = tonumber(MySQL.Sync.fetchScalar("SELECT COALESCE(SUM(total), 0) FROM partay_locksmith_invoices WHERE location_name = ? AND status = 'paid'", { locationName })) or 0,
        pendingCount = tonumber(MySQL.Sync.fetchScalar("SELECT COUNT(*) FROM partay_locksmith_invoices WHERE location_name = ? AND status IN ('pending', 'approved')", { locationName })) or 0,
        paidCount = tonumber(MySQL.Sync.fetchScalar("SELECT COUNT(*) FROM partay_locksmith_invoices WHERE location_name = ? AND status = 'paid'", { locationName })) or 0,
        recentInvoices = MySQL.Sync.fetchAll([[
            SELECT invoice_id, employee_name, customer_name, plate, status, total, society_deposit, created_at, updated_at
            FROM partay_locksmith_invoices
            WHERE location_name = ?
            ORDER BY id DESC
            LIMIT 20
        ]], { locationName }) or {},
        recentLogs = MySQL.Sync.fetchAll([[
            SELECT action, message, actor_name, target_name, created_at
            FROM partay_locksmith_logs
            WHERE location_name = ?
            ORDER BY id DESC
            LIMIT 25
        ]], { locationName }) or {}
    }
end

lib.callback.register('partay_keys:server:GetLocksmithBusinessData', function(src)
    if not IsPlayerLocksmithOwner(src) then
        return { allowed = false }
    end

    local locationName = GetLocksmithBusinessLocationName(src, true)
    local business = GetLocksmithBusinessConfig() or {}
    local permissions = BuildLocksmithManagementPermissionsPayload(src, locationName)
    local playerRun = GetLocksmithPlayerRunConfig() or {}

    return {
        allowed = true,
        locationName = locationName,
        stock = GetLocksmithStockMap(locationName),
        stocking = BuildLocksmithStockingPayload(locationName),
        garageSetup = BuildLocksmithGarageSetupPayload(locationName),
        prices = BuildLocksmithPricePayload(locationName),
        jobs = GetLocksmithRuntimeJobNames(true),
        locations = GetActiveLocksmithLocations(),
        onlineEmployees = CountOnlineLocksmithEmployees(),
        employees = GetOnlineLocksmithEmployees(),
        candidates = GetNearbyLocksmithCandidates(src),
        reports = BuildLocksmithReports(locationName),
        shopStatus = GetLocksmithShopStatus(locationName),
        onCallContact = GetLocksmithOnCallContact(locationName),
        societyAccount = GetLocksmithSocietyAccount(src),
        societyBalance = Bridge.GetSocietyMoney and Bridge.GetSocietyMoney(GetLocksmithSocietyAccount(src)) or nil,
        payment = GetLocksmithPaymentSettings(locationName),
        permissions = permissions,
        appointments = GetLocksmithAppointmentRows(20),
        shopOrders = GetLocksmithShopOrderRows(30, locationName),
        ownerAccess = true
    }
end)

lib.callback.register('partay_keys:server:GetLocksmithEmployeeBusinessData', function(src)
    if not IsPlayerLocksmithEmployee(src) and not IsPlayerLocksmithOwner(src) then
        return { allowed = false }
    end

    local locationName = GetLocksmithBusinessLocationName(src)
    local permissions = BuildLocksmithManagementPermissionsPayload(src, locationName)
    local allowed = permissions.allowed or {}

    return {
        allowed = true,
        locationName = locationName,
        employeeView = true,
        ownerAccess = IsPlayerLocksmithOwner(src),
        permissions = permissions,
        stock = GetLocksmithStockMap(locationName),
        locations = GetActiveLocksmithLocations(),
        onlineEmployees = CountOnlineLocksmithEmployees(),
        shopStatus = GetLocksmithShopStatus(locationName),
        onCallContact = GetLocksmithOnCallContact(locationName),
        payment = GetLocksmithPaymentSettings(locationName),
        employees = allowed.Payroll and GetOnlineLocksmithEmployees() or {},
        candidates = allowed.Candidates and GetNearbyLocksmithCandidates(src) or {},
        reports = allowed.Reports and BuildLocksmithReports(locationName) or nil,
        appointments = (allowed.AppointmentSchedule or allowed.AppointmentComplete or allowed.AppointmentCancel or allowed.AppointmentReminder)
            and GetLocksmithAppointmentRows(20) or {},
        shopOrders = GetLocksmithShopOrderRows(30, locationName)
    }
end)

lib.callback.register('partay_keys:server:GetLocksmithWorkbenchData', function(src)
    local allowed, reason = CanUseLocksmithWorkbench(src)
    if not allowed then
        return { allowed = false, reason = reason }
    end

    local locationName = GetLocksmithBusinessLocationName(src)
    local business = GetLocksmithBusinessConfig() or {}
    local workbench = business.Workbench or {}
    return {
        allowed = true,
        locationName = locationName,
        workstation = true,
        craftSeconds = tonumber(workbench.CraftSeconds) or 5.0,
        stock = GetLocksmithStockMap(locationName),
        stocking = BuildLocksmithStockingPayload(locationName),
        recipes = GetLocksmithRecipes(),
        locations = GetActiveLocksmithLocations()
    }
end)

lib.callback.register('partay_keys:server:GetLocksmithGarageData', function(src)
    local allowed, reason, location = CanUseLocksmithGarage(src)
    if not allowed then
        return { allowed = false, reason = reason }
    end

    local garage = GetLocksmithGarageConfig() or {}
    local mode, provider = ResolveLocksmithGarageMode()
    local coords = location and location.coords or nil
    local spawnPoint = location and GetLocksmithLocationPoint(location.locationName, 'vehicle_spawn') or nil
    local offset = garage.SpawnOffset or vector4(0.0, -5.5, 0.0, 0.0)
    local spawn = spawnPoint and spawnPoint.coords or (coords and {
        x = coords.x + (offset.x or 0.0),
        y = coords.y + (offset.y or -5.5),
        z = coords.z + (offset.z or 0.0),
        w = (coords.w or 0.0) + (offset.w or 0.0)
    } or nil)

    return {
        allowed = true,
        mode = mode,
        provider = provider,
        providerGarageName = BuildLocksmithGarageName(location),
        providerGarageType = garage.ProviderGarageType or 'job',
        storeRadius = tonumber(garage.StoreRadius) or 8.0,
        platePrefix = garage.PlatePrefix or 'LOCK',
        spawn = spawn,
        vehicles = garage.Vehicles or {}
    }
end)

lib.callback.register('partay_keys:server:GetLocksmithLocations', function()
    return GetActiveLocksmithLocations()
end)

lib.callback.register('partay_keys:server:GetLocksmithStockStorage', function(src, locationName)
    if not IsPlayerLocksmithEmployee(src) and not IsPlayerLocksmithOwner(src) then
        return { allowed = false, reason = 'error_locksmith_employee_required' }
    end

    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then
        locationName = GetLocksmithBusinessLocationName(src, true)
    else
        locationName = GetLocksmithBusinessLocationName(locationName, true)
    end

    local storageId, resolvedLocation = EnsureLocksmithStockStorage(locationName)
    if not storageId then
        return { allowed = false, reason = 'error_inventory_unavailable' }
    end

    return {
        allowed = true,
        inventory = 'ox',
        storageId = storageId,
        label = ('%s Stock'):format(resolvedLocation)
    }
end)

lib.callback.register('partay_keys:server:GetLocksmithFallbackPedState', function()
    return GetLocksmithFallbackPedState()
end)

lib.callback.register('partay_keys:server:GetLocksmithSetupData', function(src, requestedMode)
    local setup = GetLocksmithSetupConfig()
    local access = GetLocksmithSetupAccess(src, setup, requestedMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        return { allowed = false }
    end
    local locationName = GetLocksmithBusinessLocationName(src, true)

    return {
        allowed = true,
        requestedMode = requestedMode,
        ownerSetup = access.owner == true,
        adminSetup = access.admin == true,
        canEditJobName = access.admin == true,
        points = GetLocksmithPointDefinitions(access),
        shopTypes = GetLocksmithShopTypeDefinitions(),
        stockMethods = GetLocksmithStockMethodDefinitions(),
        defaultShopType = 'player_owned',
        locations = GetConfiguredLocksmithLocations(true, access),
        stocking = BuildLocksmithStockingPayload(locationName),
        prices = BuildLocksmithPricePayload(locationName),
        staffDefaults = GetLocksmithStaffDefaults(),
        blackmarket = GetBlackmarketSettingsPayload(),
        warehousePickup = GetWarehousePickupSettingsPayload(),
        recipeSetup = BuildLocksmithRecipeSetupPayload(),
        defaultJobName = (access.owner and access.ownerJob) or '',
        targetDistance = tonumber(setup.TargetDistance) or 2.0
    }
end)

lib.callback.register('partay_keys:server:GetServicePedData', function()
    return {
        blackmarket = GetBlackmarketSettingsPayload(),
        warehousePickup = GetWarehousePickupSettingsPayload(),
        locationBlips = GetLocksmithLocationBlipsPayload()
    }
end)

lib.callback.register('partay_keys:server:IsLocksmithSetupAdmin', function(src)
    local setup = GetLocksmithSetupConfig()
    return setup and setup.Enabled == true and GetLocksmithSetupAccess(src, setup).allowed == true
end)

RegisterNetEvent('partay_keys:server:RegisterLocksmithGarageVehicle', function(netId, model, label, plate)
    local src = source
    local allowed, reason = CanUseLocksmithGarage(src)
    if not allowed then
        Notify(src, T('label_locksmith'), T(reason or 'error_locksmith_garage_unavailable'), 'error')
        return
    end

    local mode = ResolveLocksmithGarageMode()
    if mode ~= 'standalone' then
        Notify(src, T('label_locksmith'), T('error_locksmith_garage_provider_mode'), 'error')
        return
    end

    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        Notify(src, T('label_locksmith'), T('error_locksmith_garage_vehicle_missing'), 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 25.0 then
        Notify(src, T('label_locksmith'), T('error_locksmith_garage_vehicle_missing'), 'error')
        return
    end

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then
        Notify(src, T('label_locksmith'), T('error_character_unavailable'), 'error')
        return
    end

    plate = TrimPlate(plate) or MakeLocksmithGaragePlate()
    Entity(veh).state:set('possession_id', citizenId, true)
    Entity(veh).state:set('isStolen', false, true)
    Entity(veh).state:set('locksmithGarageVehicle', true, true)
    Entity(veh).state:set('locksmithGarageModel', tostring(model or ''), true)
    Entity(veh).state:set('locksmithGarageLabel', tostring(label or model or 'Service Vehicle'), true)
    Entity(veh).state:set('lockState', 1, true)
    SetVehicleDoorsLocked(veh, 1)

    Notify(src, T('label_locksmith'), T('success_locksmith_garage_vehicle_spawned', { vehicle = label or model or 'vehicle' }), 'success')
    AddLocksmithLog('garage_vehicle_spawned', ('%s spawned locksmith garage vehicle %s [%s]'):format(GetPlayerName(src), tostring(label or model), plate), src)
end)

RegisterNetEvent('partay_keys:server:StoreLocksmithGarageVehicle', function(netId)
    local src = source
    local allowed, reason = CanUseLocksmithGarage(src)
    if not allowed then
        Notify(src, T('label_locksmith'), T(reason or 'error_locksmith_garage_unavailable'), 'error')
        return
    end

    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        Notify(src, T('label_locksmith'), T('error_locksmith_garage_vehicle_missing'), 'error')
        return
    end

    if Entity(veh).state.locksmithGarageVehicle ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_garage_not_job_vehicle'), 'error')
        return
    end

    local garage = GetLocksmithGarageConfig() or {}
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > (tonumber(garage.StoreRadius) or 8.0) + 2.0 then
        Notify(src, T('label_locksmith'), T('error_locksmith_garage_vehicle_too_far'), 'error')
        return
    end

    DeleteEntity(veh)
    Notify(src, T('label_locksmith'), T('success_locksmith_garage_vehicle_stored'), 'success')
    AddLocksmithLog('garage_vehicle_stored', ('%s stored locksmith garage vehicle'):format(GetPlayerName(src)), src)
end)

RegisterNetEvent('partay_keys:server:SaveLocksmithSetupPoint', function(data)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if type(data) ~= 'table' then data = {} end
    local access = GetLocksmithSetupAccess(src, setup, data.setupMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local locationName = tostring(data.locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    local jobName = tostring(data.jobName or ''):gsub('^%s*(.-)%s*$', '%1')
    local shopType = NormalizeLocksmithShopType(data.shopType or GetLocksmithLocationShopType(locationName))
    if locationName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_location'), 'error')
        return
    end
    if access.owner and not CanLocksmithSetupAccessLocation(access, locationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end
    if access.owner then
        jobName = access.ownerJob or ''
        shopType = 'player_owned'
    elseif shopType == 'player_owned' and jobName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_job'), 'error')
        return
    elseif shopType == 'self_service' then
        jobName = ''
    end

    local normalizedType, pointConfig = NormalizeLocksmithPointType(data.pointType)
    if not normalizedType then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end
    if not LocksmithPointSupportsShopType(normalizedType, shopType) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end
    if not CanLocksmithSetupAccessPoint(access, normalizedType) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end
    local coords = DecodeLocksmithCoords(data.coords)
    if not coords then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_coords'), 'error')
        return
    end

    local distance = tonumber(setup.TargetDistance) or 2.0
    local encodedCoords = json.encode({ x = coords.x, y = coords.y, z = coords.z, w = coords.w or 0.0 })
    local spawnProp = IsTruthyDbValue(data.spawnProp, true)
    if pointConfig.CoordOnly == true or pointConfig.VehiclePreview == true then
        spawnProp = false
    elseif pointConfig.IsPed == true or setup.AllowExistingMloProps ~= true or pointConfig.AllowExistingProp == false then
        spawnProp = true
    end

    local selectedStockMethod = tostring(data.stockMethod or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    if selectedStockMethod ~= '' and not GetLocksmithStockMethodConfig(selectedStockMethod) then
        selectedStockMethod = ''
    end

    MySQL.Sync.execute([[
        INSERT INTO partay_locksmith_locations (location_name, shop_type, job_name, point_type, label, model, coords, target_distance, active, spawn_prop, stock_method, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            shop_type = VALUES(shop_type),
            job_name = VALUES(job_name),
            label = VALUES(label),
            model = VALUES(model),
            coords = VALUES(coords),
            target_distance = VALUES(target_distance),
            active = 0,
            spawn_prop = VALUES(spawn_prop),
            stock_method = VALUES(stock_method),
            created_by = VALUES(created_by),
            updated_at = CURRENT_TIMESTAMP
    ]], {
        locationName,
        shopType,
        jobName,
        normalizedType,
        pointConfig.Label or normalizedType,
        pointConfig.Model,
        encodedCoords,
        distance,
        spawnProp and 1 or 0,
        selectedStockMethod,
        Bridge.GetCitizenID(src)
    })
    MySQL.Sync.execute('UPDATE partay_locksmith_locations SET shop_type = ?, job_name = ?, stock_method = ? WHERE location_name = ? AND active = 0', {
        shopType,
        jobName,
        selectedStockMethod,
        locationName
    })

    AddLocksmithLog('location_set', ('%s %s location point set'):format(locationName, normalizedType), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_saved', { point = pointConfig.Label or normalizedType }), 'success')
    RefreshLocksmithRuntimeJobCache('location_set')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
end)

RegisterNetEvent('partay_keys:server:ClearLocksmithSetupPoint', function(locationName, pointType, setupMode)
    local src = source
    local setup = GetLocksmithSetupConfig()
    local access = GetLocksmithSetupAccess(src, setup, setupMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    pointType = tostring(pointType or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_location'), 'error')
        return
    end
    if not CanLocksmithSetupAccessLocation(access, locationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    if pointType == 'all' or pointType == '' then
        if access.owner then
            Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
            return
        end
        MySQL.Sync.execute('DELETE FROM partay_locksmith_locations WHERE location_name = ?', { locationName })
        AddLocksmithLog('location_cleared', ('%s location cleared'):format(locationName), src)
        Notify(src, T('label_locksmith'), T('success_locksmith_setup_cleared', { point = locationName }), 'success')
        RefreshLocksmithRuntimeJobCache('location_cleared')
        TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
        TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
        return
    end

    local normalizedType, pointConfig = NormalizeLocksmithPointType(pointType)
    if not normalizedType then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end
    if not CanLocksmithSetupAccessPoint(access, normalizedType) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    MySQL.Sync.execute('DELETE FROM partay_locksmith_locations WHERE location_name = ? AND point_type = ?', { locationName, normalizedType })
    AddLocksmithLog('location_cleared', ('%s %s location point cleared'):format(locationName, normalizedType), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_cleared', { point = pointConfig.Label or normalizedType }), 'success')
    RefreshLocksmithRuntimeJobCache('location_point_cleared')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
end)

RegisterNetEvent('partay_keys:server:FinalizeLocksmithSetupLocation', function(data)
    local src = source
    local setup = GetLocksmithSetupConfig()
    local requestedMode = type(data) == 'table' and data.setupMode or nil
    local access = GetLocksmithSetupAccess(src, setup, requestedMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local locationName = type(data) == 'table' and data.locationName or data
    local stockMethod = type(data) == 'table' and data.stockMethod or nil
    local shopType = NormalizeLocksmithShopType(type(data) == 'table' and data.shopType or GetLocksmithLocationShopType(locationName))
    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    if not CanLocksmithSetupAccessLocation(access, locationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end
    if access.owner then shopType = 'player_owned' end

    local normalizedStockMethod = ''
    if shopType ~= 'self_service' then
        normalizedStockMethod = GetLocksmithStockMethodConfig(stockMethod)
        if not normalizedStockMethod then
            Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_stock_method'), 'error')
            return
        end
    end
    if not HasCompleteLocksmithLocation(locationName, shopType, normalizedStockMethod) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_incomplete'), 'error')
        return
    end
    MySQL.Sync.execute('UPDATE partay_locksmith_locations SET active = 1, shop_type = ?, stock_method = ? WHERE location_name = ?', { shopType, normalizedStockMethod, locationName })
    AddLocksmithLog('location_finalized', ('%s finalized as %s with %s stock method'):format(locationName, shopType, normalizedStockMethod), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_finalized', { location = locationName }), 'success')
    RefreshLocksmithRuntimeJobCache('location_finalized')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
end)

RegisterNetEvent('partay_keys:server:SaveLocksmithSetupStockMethod', function(locationName, stockMethod, setupMode)
    local src = source
    local setup = GetLocksmithSetupConfig()
    local access = GetLocksmithSetupAccess(src, setup, setupMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_location'), 'error')
        return
    end
    if not CanLocksmithSetupAccessLocation(access, locationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local normalizedStockMethod, methodConfig = GetLocksmithStockMethodConfig(stockMethod)
    if not normalizedStockMethod then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_stock_method'), 'error')
        return
    end
    MySQL.Sync.execute('UPDATE partay_locksmith_locations SET stock_method = ?, updated_at = CURRENT_TIMESTAMP WHERE location_name = ?', {
        normalizedStockMethod,
        locationName
    })
    AddLocksmithLog('location_stock_method', ('%s stock method set to %s'):format(locationName, normalizedStockMethod), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_stock_method_saved', { method = methodConfig.Label or normalizedStockMethod }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
end)

RegisterNetEvent('partay_keys:server:SaveLocksmithLocationBlip', function(data)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if type(data) ~= 'table' then data = {} end
    local access = GetLocksmithSetupAccess(src, setup, data.setupMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local locationName = tostring(data.locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    if locationName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_location'), 'error')
        return
    end
    if not CanLocksmithSetupAccessLocation(access, locationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local rows = MySQL.Sync.fetchAll([[
        SELECT id, stock_settings
        FROM partay_locksmith_locations
        WHERE location_name = ?
        ORDER BY id ASC
        LIMIT 1
    ]], { locationName }) or {}
    if not rows[1] then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_incomplete'), 'error')
        return
    end

    local settings = DecodeJsonObject(rows[1].stock_settings)
    settings.locationBlip = NormalizeLocksmithLocationBlip(data.blip, locationName)
    MySQL.Sync.execute('UPDATE partay_locksmith_locations SET stock_settings = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?', {
        json.encode(settings),
        tonumber(rows[1].id)
    })

    AddLocksmithLog('location_blip_saved', ('%s map blip updated'):format(locationName), src, nil, locationName)
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_saved', { point = 'Map blip' }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
end)

RegisterNetEvent('partay_keys:server:SaveLocksmithSetupStandSpot', function(data)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if type(data) ~= 'table' then data = {} end
    local access = GetLocksmithSetupAccess(src, setup, data.setupMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local locationName = tostring(data.locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    local normalizedType, pointConfig = NormalizeLocksmithPointType(data.pointType)
    local coords = DecodeLocksmithCoords(data.coords)
    if locationName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_location'), 'error')
        return
    end
    if not CanLocksmithSetupAccessLocation(access, locationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end
    if not normalizedType or not coords then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end
    if not CanLocksmithSetupAccessPoint(access, normalizedType) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local rows = MySQL.Sync.fetchAll('SELECT stock_settings FROM partay_locksmith_locations WHERE location_name = ? AND point_type = ? LIMIT 1', {
        locationName,
        normalizedType
    }) or {}
    if not rows[1] then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end

    local settings = DecodeJsonObject(rows[1].stock_settings)
    settings.standSpot = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = coords.w or 0.0
    }

    MySQL.Sync.execute('UPDATE partay_locksmith_locations SET stock_settings = ?, updated_at = CURRENT_TIMESTAMP WHERE location_name = ? AND point_type = ?', {
        json.encode(settings),
        locationName,
        normalizedType
    })

    AddLocksmithLog('location_stand_spot', ('%s %s stand spot set'):format(locationName, normalizedType), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_stand_spot_saved', { point = pointConfig.Label or normalizedType }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
end)

RegisterNetEvent('partay_keys:server:AddLocksmithSetupRoutePoint', function(data)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if type(data) ~= 'table' then data = {} end
    local access = GetLocksmithSetupAccess(src, setup, data.setupMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local locationName = tostring(data.locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    local normalizedType, pointConfig = NormalizeLocksmithPointType(data.pointType)
    local coords = DecodeLocksmithCoords(data.coords)
    if locationName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_location'), 'error')
        return
    end
    if not CanLocksmithSetupAccessLocation(access, locationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end
    if not normalizedType or not coords then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end
    if not CanLocksmithSetupAccessPoint(access, normalizedType) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local rows = MySQL.Sync.fetchAll('SELECT stock_settings FROM partay_locksmith_locations WHERE location_name = ? AND point_type = ? LIMIT 1', {
        locationName,
        normalizedType
    }) or {}
    if not rows[1] then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end

    local settings = DecodeJsonObject(rows[1].stock_settings)
    settings.route = type(settings.route) == 'table' and settings.route or {}
    if #settings.route >= 24 then
        table.remove(settings.route, 1)
    end
    settings.route[#settings.route + 1] = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = coords.w or 0.0
    }

    MySQL.Sync.execute('UPDATE partay_locksmith_locations SET stock_settings = ?, updated_at = CURRENT_TIMESTAMP WHERE location_name = ? AND point_type = ?', {
        json.encode(settings),
        locationName,
        normalizedType
    })

    AddLocksmithLog('location_route_point', ('%s %s route point added'):format(locationName, normalizedType), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_route_point_saved', {
        point = pointConfig.Label or normalizedType,
        count = #settings.route
    }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
end)

RegisterNetEvent('partay_keys:server:SetLocksmithSetupRouteEndPoint', function(data)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if type(data) ~= 'table' then data = {} end
    local access = GetLocksmithSetupAccess(src, setup, data.setupMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local locationName = tostring(data.locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    local normalizedType, pointConfig = NormalizeLocksmithPointType(data.pointType)
    local coords = DecodeLocksmithCoords(data.coords)
    if locationName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_location'), 'error')
        return
    end
    if not CanLocksmithSetupAccessLocation(access, locationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end
    if not normalizedType or not coords then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end
    if not CanLocksmithSetupAccessPoint(access, normalizedType) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local rows = MySQL.Sync.fetchAll('SELECT stock_settings FROM partay_locksmith_locations WHERE location_name = ? AND point_type = ? LIMIT 1', {
        locationName,
        normalizedType
    }) or {}
    if not rows[1] then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end

    local settings = DecodeJsonObject(rows[1].stock_settings)
    settings.routeEnd = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = coords.w or 0.0
    }

    MySQL.Sync.execute('UPDATE partay_locksmith_locations SET stock_settings = ?, updated_at = CURRENT_TIMESTAMP WHERE location_name = ? AND point_type = ?', {
        json.encode(settings),
        locationName,
        normalizedType
    })

    AddLocksmithLog('location_route_end', ('%s %s route end set'):format(locationName, normalizedType), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_route_end_saved', { point = pointConfig.Label or normalizedType }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
end)

RegisterNetEvent('partay_keys:server:ClearLocksmithSetupRoute', function(locationName, pointType, setupMode)
    local src = source
    local setup = GetLocksmithSetupConfig()
    local access = GetLocksmithSetupAccess(src, setup, setupMode)
    if not setup or setup.Enabled ~= true or access.allowed ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    locationName = tostring(locationName or ''):gsub('^%s*(.-)%s*$', '%1')
    local normalizedType, pointConfig = NormalizeLocksmithPointType(pointType)
    if locationName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_location'), 'error')
        return
    end
    if not CanLocksmithSetupAccessLocation(access, locationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end
    if not normalizedType then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end
    if not CanLocksmithSetupAccessPoint(access, normalizedType) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    local rows = MySQL.Sync.fetchAll('SELECT stock_settings FROM partay_locksmith_locations WHERE location_name = ? AND point_type = ? LIMIT 1', {
        locationName,
        normalizedType
    }) or {}
    if not rows[1] then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_invalid_point'), 'error')
        return
    end

    local settings = DecodeJsonObject(rows[1].stock_settings)
    settings.route = nil
    settings.routeEnd = nil
    MySQL.Sync.execute('UPDATE partay_locksmith_locations SET stock_settings = ?, updated_at = CURRENT_TIMESTAMP WHERE location_name = ? AND point_type = ?', {
        json.encode(settings),
        locationName,
        normalizedType
    })

    AddLocksmithLog('location_route_cleared', ('%s %s route cleared'):format(locationName, normalizedType), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_route_cleared', { point = pointConfig.Label or normalizedType }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
end)

lib.callback.register('partay_keys:server:GetOwnedLocksmithVehiclePlates', function(src, plates)
    if type(plates) ~= 'table' then return {} end

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then return {} end

    local owned = {}
    local storage = GetVehicleStorage()
    local ownerColumn = storage.ownerColumn

    for _, plate in ipairs(plates) do
        plate = TrimPlate(plate)
        if plate and plate ~= '' and not owned[plate] then
            local owner = MySQL.Sync.fetchScalar(('SELECT %s FROM %s WHERE plate = ? LIMIT 1'):format(storage.ownerSql, storage.tableSql), { plate })
            if owner == citizenId then
                owned[plate] = true
            end
        end
    end

    return owned
end)

RegisterNetEvent('partay_keys:server:RequestLocksmithCustomerService', function(data)
    local src = source
    if type(data) ~= 'table' then return end

    local customerId = tonumber(data.customerId)
    local plate = TrimPlate(data.plate)
    local netId = tonumber(data.netId) or 0
    local services = NormalizeLocksmithServices(data)
    local valid, reason, _, customerCitizenId, registration = ValidateLocksmithEmployeeJob(src, customerId, plate, netId, services)
    if not valid then
        Notify(src, T('label_locksmith'), T(reason or 'error_locksmith_invalid_customer_service'), 'error')
        return
    end

    local playerRun = GetLocksmithPlayerRunConfig() or {}
    local invoiceId = MakeLocksmithRecordId('invoice')
    local invoiceSeconds = math.max(30, tonumber(playerRun.InvoiceExpiresSeconds) or 120)
    PendingLocksmithInvoices[invoiceId] = {
        id = invoiceId,
        locationName = GetLocksmithBusinessLocationName(src, true),
        employeeId = src,
        employeeCitizenId = Bridge.GetCitizenID(src),
        employeeName = Bridge.GetCharacterName and Bridge.GetCharacterName(src) or GetPlayerName(src),
        customerId = customerId,
        customerCitizenId = customerCitizenId,
        customerName = Bridge.GetCharacterName and Bridge.GetCharacterName(customerId) or GetPlayerName(customerId),
        plate = plate,
        label = registration.vehicle or registration.model or 'Vehicle',
        netId = netId,
        services = services,
        total = GetLocksmithInvoiceTotal(services, GetLocksmithBusinessLocationName(src, true)),
        status = 'pending',
        expiresAt = os.time() + invoiceSeconds
    }

    RecordLocksmithInvoice(PendingLocksmithInvoices[invoiceId])
    AddLocksmithLog('invoice_created', ('Invoice %s created for %s'):format(invoiceId, plate), src, customerId)
    TriggerClientEvent('partay_keys:client:ConfirmLocksmithInvoice', customerId, PendingLocksmithInvoices[invoiceId])
    SendLocksmithPhoneMessage(customerId, ('%s sent you a locksmith invoice for %s.'):format(PendingLocksmithInvoices[invoiceId].employeeName or 'A locksmith', plate ~= '' and plate or 'your vehicle'), {
        audience = 'customer',
        event = 'invoice_sent',
        invoiceId = invoiceId,
        plate = plate,
        total = PendingLocksmithInvoices[invoiceId].total
    })
    Notify(src, T('label_locksmith'), T('info_locksmith_invoice_sent'), 'info')
end)

RegisterNetEvent('partay_keys:server:CreateLocksmithInvoice', function(data)
    local src = source
    if type(data) ~= 'table' then return end

    local customerId = tonumber(data.customerId)
    local plate = TrimPlate(data.plate)
    local netId = tonumber(data.netId) or 0
    local services = NormalizeLocksmithServices(data)
    local valid, reason, _, customerCitizenId, registration = ValidateLocksmithEmployeeJob(src, customerId, plate, netId, services)
    if not valid then
        Notify(src, T('label_locksmith'), T(reason or 'error_locksmith_invalid_customer_service'), 'error')
        return
    end

    local playerRun = GetLocksmithPlayerRunConfig() or {}
    local invoiceId = MakeLocksmithRecordId('invoice')
    local invoiceSeconds = math.max(30, tonumber(playerRun.InvoiceExpiresSeconds) or 120)
    PendingLocksmithInvoices[invoiceId] = {
        id = invoiceId,
        locationName = GetLocksmithBusinessLocationName(src, true),
        employeeId = src,
        employeeCitizenId = Bridge.GetCitizenID(src),
        employeeName = Bridge.GetCharacterName and Bridge.GetCharacterName(src) or GetPlayerName(src),
        customerId = customerId,
        customerCitizenId = customerCitizenId,
        customerName = Bridge.GetCharacterName and Bridge.GetCharacterName(customerId) or GetPlayerName(customerId),
        plate = plate,
        label = registration.vehicle or registration.model or 'Vehicle',
        netId = netId,
        services = services,
        total = GetLocksmithInvoiceTotal(services, GetLocksmithBusinessLocationName(src, true)),
        status = 'pending',
        expiresAt = os.time() + invoiceSeconds
    }

    RecordLocksmithInvoice(PendingLocksmithInvoices[invoiceId])
    AddLocksmithLog('invoice_created', ('Invoice %s created for %s'):format(invoiceId, plate), src, customerId)
    TriggerClientEvent('partay_keys:client:ConfirmLocksmithInvoice', customerId, PendingLocksmithInvoices[invoiceId])
    SendLocksmithPhoneMessage(customerId, ('%s sent you a locksmith invoice for %s.'):format(PendingLocksmithInvoices[invoiceId].employeeName or 'A locksmith', plate ~= '' and plate or 'your vehicle'), {
        audience = 'customer',
        event = 'invoice_sent',
        invoiceId = invoiceId,
        plate = plate,
        total = PendingLocksmithInvoices[invoiceId].total
    })
    Notify(src, T('label_locksmith'), T('info_locksmith_invoice_sent'), 'info')
end)

RegisterNetEvent('partay_keys:server:ConfirmLocksmithService', function(requestId, accepted)
    local src = source
    local pending = PendingLocksmithServices[requestId] or PendingLocksmithInvoices[requestId]
    if not pending or pending.customerId ~= src or pending.expiresAt < os.time() then
        PendingLocksmithServices[requestId] = nil
        PendingLocksmithInvoices[requestId] = nil
        Notify(src, T('label_locksmith'), T('error_locksmith_service_expired'), 'error')
        return
    end

    PendingLocksmithServices[requestId] = nil
    PendingLocksmithInvoices[requestId] = nil
    local employeeId = pending.employeeId
    if accepted ~= true then
        UpdateLocksmithInvoiceStatus(requestId, 'declined')
        AddLocksmithLog('invoice_declined', ('Invoice %s declined for %s'):format(requestId, pending.plate or 'unknown'), employeeId, src)
        Notify(src, T('label_locksmith'), T('info_locksmith_service_declined'), 'info')
        if GetPlayerName(employeeId) then
            Notify(employeeId, T('label_locksmith'), T('info_locksmith_customer_declined'), 'info')
        end
        return
    end

    local services = pending.services or NormalizeLocksmithServices(pending)
    local valid, reason = ValidateLocksmithEmployeeJob(employeeId, src, pending.plate, pending.netId, services)
    if not valid then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_unavailable'), 'error')
        if GetPlayerName(employeeId) then
            Notify(employeeId, T('label_locksmith'), T(reason or 'error_locksmith_employee_unavailable'), 'error')
        end
        return
    end

    local playerRun = GetLocksmithPlayerRunConfig() or {}
    local jobId = MakeLocksmithRecordId('job')
    ActiveLocksmithJobs[jobId] = {
        id = jobId,
        locationName = pending.locationName or GetLocksmithBusinessLocationName(employeeId, true),
        employeeId = employeeId,
        employeeName = pending.employeeName,
        customerId = src,
        customerCitizenId = pending.customerCitizenId or Bridge.GetCitizenID(src),
        plate = pending.plate,
        netId = pending.netId,
        label = pending.label or 'Vehicle',
        services = services,
        total = GetLocksmithInvoiceTotal(services),
        status = 'approved',
        workComplete = false,
        paymentMethod = nil,
        expiresAt = os.time() + (math.max(5, tonumber(playerRun.ApprovedJobExpiresMinutes) or 20) * 60)
    }

    UpdateLocksmithInvoiceStatus(pending.id, 'approved')
    AddLocksmithLog('invoice_approved', ('Invoice %s approved for %s'):format(pending.id, pending.plate or 'unknown'), employeeId, src)

    local workflow = GetLocksmithWorkflowConfig()
    if workflow.HoldCustomerKeysUntilPaid ~= false then
        local heldId = BuildLocksmithHeldKeyId(ActiveLocksmithJobs[jobId].customerCitizenId, pending.plate)
        if heldId then
            LocksmithHeldKeys[heldId] = { jobId = jobId, expiresAt = ActiveLocksmithJobs[jobId].expiresAt }
        end
    end

    if GetPlayerName(employeeId) then
        TriggerClientEvent('partay_keys:client:LocksmithJobApproved', employeeId, ActiveLocksmithJobs[jobId])
        Notify(employeeId, T('label_locksmith'), T('success_locksmith_customer_accepted'), 'success')
    end

    Notify(src, T('label_locksmith'), T('success_locksmith_invoice_approved'), 'success')
end)

RegisterNetEvent('partay_keys:server:CompleteLocksmithJobWork', function(jobId)
    local src = source
    local job = ActiveLocksmithJobs[jobId]
    if not job or job.employeeId ~= src or job.expiresAt < os.time() then
        Notify(src, T('label_locksmith'), T('error_locksmith_job_expired'), 'error')
        if job then
            UpdateLocksmithInvoiceStatus(job.id, 'expired')
            ReleaseLocksmithHeldKeys(job)
            ActiveLocksmithJobs[jobId] = nil
        end
        return
    end

    job.workComplete = true
    job.status = 'work_complete'
    Notify(src, T('label_locksmith'), T('success_locksmith_work_complete'), 'success')
    if GetPlayerName(job.customerId) then
        SendLocksmithPhoneMessage(job.customerId, T('info_locksmith_ready_for_payment'), {
            audience = 'customer',
            event = 'work_ready_for_payment',
            jobId = jobId,
            invoiceId = job.id,
            plate = job.plate
        })
        Notify(job.customerId, T('label_locksmith'), T('info_locksmith_ready_for_payment'), 'info')
    end
end)

RegisterNetEvent('partay_keys:server:RequestLocksmithJobPayment', function(jobId)
    local src = source
    local job = ActiveLocksmithJobs[jobId]
    if not job or job.employeeId ~= src or job.expiresAt < os.time() then
        Notify(src, T('label_locksmith'), T('error_locksmith_job_expired'), 'error')
        if job then
            UpdateLocksmithInvoiceStatus(job.id, 'expired')
            ReleaseLocksmithHeldKeys(job)
            ActiveLocksmithJobs[jobId] = nil
        end
        return
    end

    local workflow = GetLocksmithWorkflowConfig()
    if workflow.RequireWorkBeforePayment ~= false and job.workComplete ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_work_required'), 'error')
        return
    end

    local valid, reason = ValidateLocksmithEmployeeJob(src, job.customerId, job.plate, job.netId, job.services)
    if not valid then
        Notify(src, T('label_locksmith'), T(reason or 'error_locksmith_job_expired'), 'error')
        return
    end

    TriggerClientEvent('partay_keys:client:PayLocksmithInvoice', job.customerId, {
        id = job.id,
        employeeName = job.employeeName or GetPlayerName(src),
        plate = job.plate,
        label = job.label,
        services = job.services,
        total = job.total
    })
    SendLocksmithPhoneMessage(job.customerId, ('Payment is ready for locksmith invoice %s.'):format(job.id), {
        audience = 'customer',
        event = 'payment_presented',
        jobId = jobId,
        invoiceId = job.id,
        plate = job.plate,
        total = job.total
    })
    Notify(src, T('label_locksmith'), T('info_locksmith_terminal_presented'), 'info')
end)

RegisterNetEvent('partay_keys:server:BuildLocksmithStock', function(recipeId, quantity)
    local src = source
    local allowed, reason = CanUseLocksmithWorkbench(src)
    if not allowed then
        Notify(src, T('label_locksmith'), T(reason or 'error_locksmith_workbench_unavailable'), 'error')
        return
    end

    local recipe = GetLocksmithRecipe(recipeId)
    quantity = math.max(1, math.min(math.floor(tonumber(quantity) or 1), 50))
    if not recipe or not recipe.produces then
        Notify(src, T('label_locksmith'), T('error_locksmith_recipe_invalid'), 'error')
        return
    end

    local locationName = GetLocksmithBusinessLocationName(src)
    local stock = GetLocksmithStockMap(locationName)
    local consumePlan = {}

    for _, component in ipairs(recipe.components or {}) do
        local amount = (tonumber(component.amount) or 0) * quantity
        if amount > 0 then
            local inventoryAmount = math.min(CountPlayerInventoryItem(src, component.item), amount)
            local stockAmount = amount - inventoryAmount
            if stockAmount > 0 and (tonumber(stock[component.item]) or 0) < stockAmount then
                Notify(src, T('label_locksmith'), T('error_locksmith_missing_parts'), 'error')
                return
            end

            consumePlan[#consumePlan + 1] = {
                item = component.item,
                stockAmount = stockAmount,
                inventoryAmount = inventoryAmount
            }
        end
    end

    for _, plan in ipairs(consumePlan) do
        if plan.inventoryAmount > 0 and not Bridge.RemoveInventoryItem(src, plan.item, plan.inventoryAmount) then
            Notify(src, T('label_locksmith'), T('error_locksmith_missing_parts'), 'error')
            return
        end

        if plan.stockAmount > 0 then
            local ok = ConsumeLocksmithStock({ { item = plan.item, amount = plan.stockAmount } }, locationName)
            if not ok then
                Notify(src, T('label_locksmith'), T('error_locksmith_missing_parts'), 'error')
                return
            end
        end
    end

    local produced = (tonumber(recipe.amount) or 1) * quantity
    AddLocksmithStock(recipe.produces, produced, locationName)
    Notify(src, T('label_locksmith'), T('success_locksmith_stock_built', {
        amount = produced,
        item = recipe.label or recipe.produces
    }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithWorkbench', src)
end)

RegisterNetEvent('partay_keys:server:OrderLocksmithStock', function(itemName, quantity, locationName)
    local src = source
    if not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    local stocking = GetLocksmithStockingConfig()
    if not stocking then
        Notify(src, T('label_locksmith'), T('error_locksmith_stocking_unavailable'), 'error')
        return
    end

    local requestedItems = {}
    if type(itemName) == 'table' then
        locationName = itemName.locationName or locationName
        for _, entry in ipairs(itemName.items or {}) do
            requestedItems[#requestedItems + 1] = {
                item = entry.item,
                quantity = entry.quantity
            }
        end
    else
        requestedItems[1] = { item = itemName, quantity = quantity }
    end

    local maxQuantity = tonumber(stocking.MaxOrderQuantity) or 50
    local location = GetLocksmithLocationProfile(locationName) or GetNearestLocksmithStockLocation(src)
    local resolvedLocationName = GetLocksmithBusinessLocationName(location and location.locationName or src, true)
    local stockMethod = select(1, NormalizeStockMethod(location and location.stockMethod))
    local _, supplierContract = GetLocksmithSupplierContract(resolvedLocationName)
    local priceMultiplier = tonumber(supplierContract.PriceMultiplier) or 1.0
    local delayMultiplier = tonumber(supplierContract.DelayMultiplier) or 1.0
    local orderItems = {}
    local total = 0
    local totalQuantity = 0

    for _, requested in ipairs(requestedItems) do
        local orderItem = GetLocksmithOrderItem(requested.item)
        local requestedQuantity = math.max(0, math.min(math.floor(tonumber(requested.quantity) or 0), maxQuantity))
        if orderItem and requestedQuantity > 0 then
            local activeBasePrice = GetLocksmithPrice(('order:%s'):format(tostring(orderItem.item)), tonumber(orderItem.price) or 0, nil, resolvedLocationName)
            local unitPrice = math.floor((activeBasePrice * priceMultiplier) + 0.5)
            local lineTotal = unitPrice * requestedQuantity
            orderItems[#orderItems + 1] = {
                item = orderItem.item,
                label = orderItem.label or orderItem.item,
                quantity = requestedQuantity,
                unitPrice = unitPrice,
                total = lineTotal
            }
            total = total + lineTotal
            totalQuantity = totalQuantity + requestedQuantity
        end
    end

    if #orderItems < 1 then
        Notify(src, T('label_locksmith'), T('error_shop_item_unavailable'), 'error')
        return
    end

    local societyAccount = GetLocksmithSocietyAccount(src)

    if total > 0 and (not Bridge.RemoveSocietyMoney or not Bridge.RemoveSocietyMoney(societyAccount, total)) then
        Notify(src, T('label_locksmith'), T('error_locksmith_society_cannot_afford', { account = societyAccount }), 'error')
        return
    end

    local orderId = MakeLocksmithRecordId('stock')
    local now = os.time()
    local delay = stockMethod == 'delivery' and math.floor((tonumber(stocking.DeliveryDelaySeconds) or 90) * delayMultiplier)
        or stockMethod == 'pickup' and math.floor((tonumber(stocking.PickupDelaySeconds) or 90) * delayMultiplier)
        or 0
    local pickupCoords = stockMethod == 'pickup' and GetConfiguredPickupCoords() or nil
    local deliverySpawn = stockMethod == 'delivery' and GetLocksmithLocationPoint(location and location.locationName, 'delivery_spawn') or nil
    local deliveryDropoff = stockMethod == 'delivery' and GetLocksmithLocationPoint(location and location.locationName, 'delivery_dropoff') or nil
    local status = stockMethod == 'auto' and 'completed' or 'pending'
    local summaryLabel = #orderItems == 1 and orderItems[1].label or ('Stock Cart (%s items)'):format(#orderItems)
    local summaryItem = #orderItems == 1 and orderItems[1].item or 'stock_cart'

    MySQL.Sync.execute([[
        INSERT INTO partay_locksmith_stock_orders
            (order_id, location_name, stock_method, item_name, label, quantity, total, order_items, status, ordered_by, ordered_by_name, pickup_coords, ready_at, completed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?)
    ]], {
        orderId,
        resolvedLocationName,
        stockMethod,
        summaryItem,
        summaryLabel,
        totalQuantity,
        total,
        json.encode(orderItems),
        status,
        Bridge.GetCitizenID(src),
        Bridge.GetCharacterName and Bridge.GetCharacterName(src) or GetPlayerName(src),
        EncodeStockPickupCoords(pickupCoords),
        now + delay,
        status == 'completed' and os.date('%Y-%m-%d %H:%M:%S', now) or nil
    })

    local order = {
        id = orderId,
        locationName = resolvedLocationName,
        stockMethod = stockMethod,
        item = summaryItem,
        label = summaryLabel,
        quantity = totalQuantity,
        items = orderItems,
        total = total,
        serverNow = now,
        readyAt = now + delay,
        waitSeconds = delay,
        pickupCoords = pickupCoords,
        deliverySpawnCoords = deliverySpawn and deliverySpawn.coords or nil,
        deliveryDropoffCoords = deliveryDropoff and deliveryDropoff.coords or nil,
        deliveryRoute = deliverySpawn and deliverySpawn.stockSettings and deliverySpawn.stockSettings.route or nil,
        deliveryRouteEnd = deliverySpawn and deliverySpawn.stockSettings and deliverySpawn.stockSettings.routeEnd or nil,
        deliveryPedRoute = deliveryDropoff and deliveryDropoff.stockSettings and deliveryDropoff.stockSettings.route or nil,
        deliveryPedRouteEnd = deliveryDropoff and deliveryDropoff.stockSettings and deliveryDropoff.stockSettings.routeEnd or nil,
        boxModel = stocking.BoxModel or GetLocksmithStockingProp('StockBox', 'prop_cardbordbox_04a'),
        truckModel = stocking.TruckModel or GetLocksmithStockingProp('DeliveryTruck', 'boxville2'),
        pedModel = stocking.DeliveryPedModel or GetLocksmithStockingProp('DeliveryPed', 's_m_m_dockwork_01'),
        carryBoxSeconds = tonumber(stocking.CarryBoxSeconds) or 3.0,
        deliverySpawnOffset = stocking.DeliverySpawnOffset and {
            x = stocking.DeliverySpawnOffset.x,
            y = stocking.DeliverySpawnOffset.y,
            z = stocking.DeliverySpawnOffset.z,
            w = stocking.DeliverySpawnOffset.w or 0.0
        } or nil
    }

    if stockMethod == 'auto' then
        for _, item in ipairs(orderItems) do
            AddLocksmithStock(item.item, item.quantity, resolvedLocationName)
        end
        AddLocksmithLog('stock_order_auto', ('%s item types ordered and inserted into stock'):format(#orderItems), src, nil, resolvedLocationName)
        Notify(src, T('label_locksmith'), T('success_locksmith_stock_order_auto', { amount = totalQuantity, item = summaryLabel }), 'success')
        TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
        return
    end

    ActiveLocksmithStockOrders[orderId] = order
    AddLocksmithLog(('stock_order_%s'):format(stockMethod), ('%s item types ordered for %s'):format(#orderItems, order.locationName), src, nil, resolvedLocationName)
    Notify(src, T('label_locksmith'), T(stockMethod == 'delivery' and 'info_locksmith_stock_delivery_ordered' or 'info_locksmith_stock_pickup_ordered', { seconds = delay }), 'info')
    TriggerClientEvent('partay_keys:client:StartLocksmithStockOrder', src, order)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
end)

RegisterNetEvent('partay_keys:server:CompleteLocksmithStockOrder', function(orderId)
    local src = source
    if not IsPlayerLocksmithEmployee(src) and not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_required'), 'error')
        return
    end

    local order = ActiveLocksmithStockOrders[orderId]
    if not order then
        local rows = MySQL.Sync.fetchAll([[
            SELECT order_id, location_name, item_name, label, quantity, order_items, status FROM partay_locksmith_stock_orders
            WHERE order_id = ? LIMIT 1
        ]], { orderId }) or {}
        if rows[1] and rows[1].status ~= 'completed' then
            order = {
                id = rows[1].order_id,
                locationName = rows[1].location_name,
                item = rows[1].item_name,
                label = rows[1].label or rows[1].item_name,
                quantity = tonumber(rows[1].quantity) or 1,
                items = DecodeLocksmithStockOrderItems(rows[1].order_items, rows[1].item_name, rows[1].label, rows[1].quantity)
            }
        end
    end

    if not order then
        Notify(src, T('label_locksmith'), T('error_locksmith_order_unavailable'), 'error')
        return
    end

    local orderItems = DecodeLocksmithStockOrderItems(order.items, order.item, order.label, order.quantity)
    for _, item in ipairs(orderItems) do
        AddLocksmithStock(item.item, item.quantity, order.locationName)
    end
    MySQL.Sync.execute([[
        UPDATE partay_locksmith_stock_orders
        SET status = 'completed', completed_at = CURRENT_TIMESTAMP
        WHERE order_id = ?
    ]], { orderId })
    ActiveLocksmithStockOrders[orderId] = nil

    AddLocksmithLog('stock_order_completed', ('%s item types moved into stock'):format(#orderItems), src, nil, order.locationName)
    Notify(src, T('label_locksmith'), T('success_locksmith_stock_order_completed', {
        amount = order.quantity or 1,
        item = order.label or order.item
    }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithWorkbench', src)
end)

RegisterNetEvent('partay_keys:server:ResumeLocksmithStockOrder', function(orderId)
    local src = source
    if not IsPlayerLocksmithOwner(src) and not IsPlayerLocksmithEmployee(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_required'), 'error')
        return
    end

    local rows = MySQL.Sync.fetchAll([[
        SELECT order_id, location_name, stock_method, item_name, label, quantity, total, order_items, status, pickup_coords, UNIX_TIMESTAMP(ready_at) AS ready_at
        FROM partay_locksmith_stock_orders
        WHERE order_id = ? AND status <> 'completed'
        LIMIT 1
    ]], { orderId }) or {}

    local row = rows[1]
    if not row then
        Notify(src, T('label_locksmith'), T('error_locksmith_order_unavailable'), 'error')
        return
    end

    local stocking = GetLocksmithStockingConfig() or {}
    local now = os.time()
    local pickupCoords = DecodeLocksmithCoords(row.pickup_coords)
    local deliverySpawn = row.stock_method == 'delivery' and GetLocksmithLocationPoint(row.location_name, 'delivery_spawn') or nil
    local deliveryDropoff = row.stock_method == 'delivery' and GetLocksmithLocationPoint(row.location_name, 'delivery_dropoff') or nil
    local order = {
        id = row.order_id,
        locationName = row.location_name,
        stockMethod = row.stock_method,
        item = row.item_name,
        label = row.label or row.item_name,
        quantity = tonumber(row.quantity) or 1,
        items = DecodeLocksmithStockOrderItems(row.order_items, row.item_name, row.label, row.quantity),
        total = tonumber(row.total) or 0,
        serverNow = now,
        readyAt = tonumber(row.ready_at) or now,
        waitSeconds = math.max(0, (tonumber(row.ready_at) or now) - now),
        pickupCoords = pickupCoords and { x = pickupCoords.x, y = pickupCoords.y, z = pickupCoords.z, w = pickupCoords.w or 0.0 } or nil,
        deliverySpawnCoords = deliverySpawn and deliverySpawn.coords or nil,
        deliveryDropoffCoords = deliveryDropoff and deliveryDropoff.coords or nil,
        deliveryRoute = deliverySpawn and deliverySpawn.stockSettings and deliverySpawn.stockSettings.route or nil,
        deliveryRouteEnd = deliverySpawn and deliverySpawn.stockSettings and deliverySpawn.stockSettings.routeEnd or nil,
        deliveryPedRoute = deliveryDropoff and deliveryDropoff.stockSettings and deliveryDropoff.stockSettings.route or nil,
        deliveryPedRouteEnd = deliveryDropoff and deliveryDropoff.stockSettings and deliveryDropoff.stockSettings.routeEnd or nil,
        boxModel = stocking.BoxModel or GetLocksmithStockingProp('StockBox', 'prop_cardbordbox_04a'),
        truckModel = stocking.TruckModel or GetLocksmithStockingProp('DeliveryTruck', 'boxville2'),
        pedModel = stocking.DeliveryPedModel or GetLocksmithStockingProp('DeliveryPed', 's_m_m_dockwork_01'),
        carryBoxSeconds = tonumber(stocking.CarryBoxSeconds) or 3.0,
        deliverySpawnOffset = stocking.DeliverySpawnOffset and {
            x = stocking.DeliverySpawnOffset.x,
            y = stocking.DeliverySpawnOffset.y,
            z = stocking.DeliverySpawnOffset.z,
            w = stocking.DeliverySpawnOffset.w or 0.0
        } or nil
    }

    ActiveLocksmithStockOrders[order.id] = order
    TriggerClientEvent('partay_keys:client:StartLocksmithStockOrder', src, order)
    Notify(src, T('label_locksmith'), T('info_locksmith_stock_order_resumed'), 'info')
end)

RegisterNetEvent('partay_keys:server:ManageLocksmithEmployee', function(action, targetId, grade)
    local src = source
    local business = GetLocksmithBusinessConfig()
    action = tostring(action or '')

    if not business or business.EmployeeManagement ~= true then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    if action == 'hire' then
        if not HasLocksmithManagementPermission(src, 'Candidates') then
            Notify(src, T('label_locksmith'), T('error_locksmith_management_permission'), 'error')
            return
        end
    elseif not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    targetId = tonumber(targetId)
    if not targetId or targetId == src or not GetPlayerName(targetId) then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_target_invalid'), 'error')
        return
    end

    local targetPed = GetPlayerPed(targetId)
    local ownerPed = GetPlayerPed(src)
    if not ownerPed or ownerPed == 0 or not targetPed or targetPed == 0
        or #(GetEntityCoords(ownerPed) - GetEntityCoords(targetPed)) > (tonumber(business.HireRange) or 6.0) then
        Notify(src, T('label_locksmith'), T('error_locksmith_customer_too_far'), 'error')
        return
    end

    local ownerJob = Bridge.GetPlayerJob(src)
    local jobName = ownerJob and ownerJob.name or GetPrimaryLocksmithJob()
    if not jobName or jobName == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_target_invalid'), 'error')
        return
    end

    local staffDefaults = GetLocksmithStaffDefaults()
    local minGrade = staffDefaults.minEmployeeGrade
    local maxGrade = staffDefaults.maxEmployeeGrade
    local targetJob = Bridge.GetPlayerJob(targetId)
    local currentGrade = GetJobGradeLevel(targetJob)
    local nextJob = jobName
    local nextGrade = currentGrade

    if action == 'hire' then
        nextGrade = staffDefaults.defaultHireGrade
    elseif action == 'promote' then
        nextGrade = math.min(maxGrade, currentGrade + 1)
    elseif action == 'demote' then
        nextGrade = math.max(minGrade, currentGrade - 1)
    elseif action == 'fire' then
        nextJob = staffDefaults.fireJob
        nextGrade = staffDefaults.fireGrade
    else
        Notify(src, T('label_locksmith'), T('error_locksmith_invalid_management_action'), 'error')
        return
    end

    if action ~= 'hire' and action ~= 'fire' and (not targetJob or targetJob.name ~= jobName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_target_invalid'), 'error')
        return
    end

    if Bridge.SetPlayerJob(targetId, nextJob, nextGrade) then
        local targetName = Bridge.GetCharacterName and Bridge.GetCharacterName(targetId) or GetPlayerName(targetId)
        Notify(src, T('label_locksmith'), T('success_locksmith_employee_managed', { action = action, name = targetName }), 'success')
        Notify(targetId, T('label_locksmith'), T('info_locksmith_employee_changed'), 'info')
        AddLocksmithLog(('employee_%s'):format(action), ('%s %s to %s grade %s'):format(GetPlayerName(src), action, targetName, nextGrade), src, targetId)
        TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
    else
        Notify(src, T('label_locksmith'), T('error_locksmith_management_failed'), 'error')
    end
end)

local function SaveLocksmithPriceOverride(src, priceKey, price, allowedCategories)
    local locationName = GetLocksmithBusinessLocationName(src, true)
    priceKey = tostring(priceKey or '')
    local requestedPrice = tonumber(price)
    if priceKey == '' or not requestedPrice then
        Notify(src, T('label_locksmith'), T('error_locksmith_price_invalid'), 'error')
        return false
    end

    if type(allowedCategories) == 'table' then
        local category = tostring(priceKey):match('^([^:]+):')
        if not allowedCategories[category] then
            Notify(src, T('label_locksmith'), T('error_locksmith_price_invalid'), 'error')
            return false
        end
    end

    local selectedEntry
    for _, entry in ipairs(BuildLocksmithPricePayload(locationName).entries or {}) do
        if entry.key == priceKey then
            selectedEntry = entry
            break
        end
    end

    if not selectedEntry then
        Notify(src, T('label_locksmith'), T('error_locksmith_price_invalid'), 'error')
        return false
    end

    local clamped, minValue, maxValue = ClampLocksmithPrice(priceKey, requestedPrice, selectedEntry.default)
    if clamped ~= math.floor(requestedPrice) then
        Notify(src, T('label_locksmith'), T('error_locksmith_price_range', {
            min = minValue,
            max = maxValue
        }), 'error')
        return false
    end

    MySQL.Sync.execute([[
        INSERT INTO partay_locksmith_prices (location_name, price_key, price, updated_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE price = VALUES(price), updated_by = VALUES(updated_by), updated_at = CURRENT_TIMESTAMP
    ]], { locationName, priceKey, clamped, Bridge.GetCitizenID(src) })

    AddLocksmithLog('price_updated', ('%s set to $%s'):format(selectedEntry.label or priceKey, clamped), src, nil, locationName)
    Notify(src, T('label_locksmith'), T('success_locksmith_price_updated', {
        label = selectedEntry.label or priceKey,
        price = clamped
    }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
    return true
end

RegisterNetEvent('partay_keys:server:SetLocksmithPrice', function(priceKey, price)
    local src = source
    if not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    SaveLocksmithPriceOverride(src, priceKey, price, {
        service = true,
        tier = true,
        shop = true
    })
end)

RegisterNetEvent('partay_keys:server:ToggleLocksmithDuty', function()
    local src = source
    local playerRun = GetLocksmithPlayerRunConfig()
    if not playerRun then
        Notify(src, T('label_locksmith'), T('error_locksmith_unavailable'), 'error')
        return
    end

    local job = Bridge.GetPlayerJob(src)
    if not job or not job.name then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_required'), 'error')
        return
    end

    local validJob = false
    for _, jobName in ipairs(GetLocksmithRuntimeJobNames(false)) do
        if JobMatches(job, jobName) then
            validJob = true
            break
        end
    end

    if not validJob then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_required'), 'error')
        return
    end

    local nextDuty = job.onduty == false
    if not Bridge.SetPlayerDuty or not Bridge.SetPlayerDuty(src, nextDuty) then
        Notify(src, T('label_locksmith'), T('error_locksmith_duty_unavailable'), 'error')
        return
    end

    local locationName = GetLocksmithBusinessLocationName(src, true)
    AddLocksmithLog('duty_toggle', ('%s clocked %s'):format(GetPlayerName(src), nextDuty and 'in' or 'out'), src, nil, locationName)
    Notify(src, T('label_locksmith'), T(nextDuty and 'success_locksmith_clocked_in' or 'success_locksmith_clocked_out'), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
    RefreshLocksmithBusinessForStaff()
end)

RegisterNetEvent('partay_keys:server:SetLocksmithManagementPermission', function(permissionKey, minGrade)
    local src = source
    if not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    permissionKey = tostring(permissionKey or '')
    local found = false
    local locationName = GetLocksmithBusinessLocationName(src, true)
    for _, definition in ipairs(GetLocksmithManagementPermissionDefinitions(locationName)) do
        if definition.key == permissionKey then
            found = definition.enabled == true
            break
        end
    end

    if not found then
        Notify(src, T('label_locksmith'), T('error_locksmith_invalid_management_action'), 'error')
        return
    end

    minGrade = math.max(0, math.floor(tonumber(minGrade) or 0))
    SetLocksmithBusinessSetting(('permission_%s_min_grade'):format(permissionKey), minGrade, src, locationName)
    AddLocksmithLog('management_permission_updated', ('%s min grade set to %s'):format(permissionKey, minGrade), src, nil, locationName)
    Notify(src, T('label_locksmith'), T('success_locksmith_management_permission_updated'), 'success')
    RefreshLocksmithBusinessForStaff()
end)

RegisterNetEvent('partay_keys:server:MoveLocksmithSocietyFunds', function(action, amount, paymentMethod)
    local src = source
    if not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    action = tostring(action or ''):lower()
    amount = math.floor(tonumber(amount) or 0)
    paymentMethod = paymentMethod == 'cash' and 'cash' or 'bank'
    local business = GetLocksmithBusinessConfig() or {}
    local maxTransaction = tonumber(business.SocietyMaxTransaction) or 0
    if amount <= 0 or (maxTransaction > 0 and amount > maxTransaction) then
        Notify(src, T('label_locksmith'), T('error_locksmith_society_amount_invalid'), 'error')
        return
    end

    local account = GetLocksmithSocietyAccount(src)
    if action == 'deposit' then
        if not Bridge.HasCurrency(src, paymentMethod, amount) or not Bridge.RemoveCurrency(src, paymentMethod, amount) then
            Notify(src, T('label_locksmith'), T('error_purchase_cannot_afford', { payment = paymentMethod }), 'error')
            return
        end

        if not Bridge.AddSocietyMoney or not Bridge.AddSocietyMoney(account, amount) then
            Bridge.AddCurrency(src, paymentMethod, amount)
            Notify(src, T('label_locksmith'), T('error_locksmith_society_deposit_failed'), 'error')
            return
        end

        AddLocksmithLog('society_deposit', ('%s deposited $%s to %s'):format(GetPlayerName(src), amount, account), src)
        Notify(src, T('label_locksmith'), T('success_locksmith_society_deposit', { amount = amount, account = account }), 'success')
    elseif action == 'withdraw' then
        if not Bridge.RemoveSocietyMoney or not Bridge.RemoveSocietyMoney(account, amount) then
            Notify(src, T('label_locksmith'), T('error_locksmith_society_withdraw_failed'), 'error')
            return
        end

        Bridge.AddCurrency(src, paymentMethod, amount)
        AddLocksmithLog('society_withdraw', ('%s withdrew $%s from %s'):format(GetPlayerName(src), amount, account), src)
        Notify(src, T('label_locksmith'), T('success_locksmith_society_withdraw', { amount = amount, account = account }), 'success')
    else
        Notify(src, T('label_locksmith'), T('error_locksmith_invalid_management_action'), 'error')
        return
    end

    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
end)

local function NotifyLocksmithAppointment(appointment)
    local message = ('%s requested locksmith service%s'):format(
        appointment.customerName or 'A customer',
        appointment.plate and appointment.plate ~= '' and (' for ' .. appointment.plate) or ''
    )

    local playerRun = GetLocksmithPlayerRunConfig() or {}
    local appointments = playerRun.Appointments or {}
    local notifyOffDuty = GetLocksmithShopStatus() == 'on_call' and appointments.NotifyOffDutyWhenOnCall == true

    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        if targetSrc and (IsPlayerLocksmithEmployee(targetSrc) or (notifyOffDuty and IsPlayerLocksmithJobMember(targetSrc))) then
            SendLocksmithPhoneMessage(targetSrc, message, {
                audience = 'locksmith_staff',
                event = 'appointment_requested',
                appointmentId = appointment.id,
                customerName = appointment.customerName,
                plate = appointment.plate
            })
            if ShouldSendLocksmithFallbackNotify() then
                Notify(targetSrc, T('label_locksmith'), message, 'info')
            end
        end
    end
end

local function SendLocksmithAppointmentCustomerMessage(customerId, localeKey, params, fallback)
    if not customerId or customerId == '' then return end

    local customerSrc = FindOnlinePlayerByCitizenId(customerId)
    local message = T(localeKey, params or {})
    if customerSrc then
        SendLocksmithPhoneMessage(customerSrc, message, {
            audience = 'customer',
            event = 'appointment_update',
            messageKey = localeKey,
            vars = params or {}
        })
        if ShouldSendLocksmithFallbackNotify() then
            Notify(customerSrc, T('label_locksmith'), message, 'info')
        end
    end
end

RegisterNetEvent('partay_keys:server:SetLocksmithShopStatus', function(status)
    local src = source
    if not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    status = tostring(status or ''):lower()
    if status ~= 'open' and status ~= 'on_call' and status ~= 'closed' then
        status = 'open'
    end

    local locationName = GetLocksmithBusinessLocationName(src, true)
    SetLocksmithBusinessSetting('shop_status', status, src, locationName)
    AddLocksmithLog('shop_status', ('Shop status set to %s'):format(status), src, nil, locationName)
    Notify(src, T('label_locksmith'), T('success_locksmith_shop_status_updated', { status = status }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
end)

RegisterNetEvent('partay_keys:server:SetLocksmithOnCallContact', function(contact)
    local src = source
    if not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    contact = tostring(contact or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, 80)
    local locationName = GetLocksmithBusinessLocationName(src, true)
    SetLocksmithBusinessSetting('on_call_contact', contact, src, locationName)
    AddLocksmithLog('on_call_contact', ('On-call contact updated to %s'):format(contact ~= '' and contact or 'blank'), src, nil, locationName)
    Notify(src, T('label_locksmith'), T('success_locksmith_on_call_updated'), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
end)

RegisterNetEvent('partay_keys:server:SetLocksmithSupplierContract', function(contractId)
    local src = source
    if not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    local stocking = GetLocksmithStockingConfig() or {}
    contractId = tostring(contractId or '')
    local contract = stocking.SupplierContracts and stocking.SupplierContracts[contractId]
    if not contract then
        Notify(src, T('label_locksmith'), T('error_locksmith_supplier_invalid'), 'error')
        return
    end

    local locationName = GetLocksmithBusinessLocationName(src, true)
    SetLocksmithBusinessSetting('supplier_contract', contractId, src, locationName)
    AddLocksmithLog('supplier_contract', ('Supplier contract set to %s'):format(contractId), src, nil, locationName)
    Notify(src, T('label_locksmith'), T('success_locksmith_supplier_updated', { supplier = contract.Label or contractId }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
end)

RegisterNetEvent('partay_keys:server:SetLocksmithCommission', function(percent)
    local src = source
    if not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_owner_required'), 'error')
        return
    end

    local locationName = GetLocksmithBusinessLocationName(src, true)
    local payment = GetLocksmithPaymentSettings(locationName)
    local maxPercent = math.max(0, math.min(100, tonumber(payment.MaxCommissionPercent) or 100))
    percent = math.floor(tonumber(percent) or 0)
    percent = math.max(0, math.min(maxPercent, percent))

    SetLocksmithBusinessSetting('employee_commission_percent', percent, src, locationName)
    AddLocksmithLog('commission_updated', ('Employee commission set to %s%%'):format(percent), src, nil, locationName)
    Notify(src, T('label_locksmith'), T('success_locksmith_commission_updated', { percent = percent }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
end)

RegisterNetEvent('partay_keys:server:SetGlobalLocksmithSupplierContracts', function(contracts)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if not setup or setup.Enabled ~= true or not IsPlayerLocksmithSetupAdmin(src, setup) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    contracts = type(contracts) == 'table' and contracts or {}
    local normalizedContracts = {}
    local seen = {}
    local enabledCount = 0

    for _, contract in ipairs(contracts) do
        local normalized = NormalizeLocksmithSupplierContract(contract)
        if normalized and not seen[normalized.id] then
            normalizedContracts[#normalizedContracts + 1] = normalized
            seen[normalized.id] = true
            if normalized.enabled ~= false then enabledCount = enabledCount + 1 end
        end
    end

    if #normalizedContracts < 1 or enabledCount < 1 then
        Notify(src, T('label_locksmith'), T('error_locksmith_supplier_invalid'), 'error')
        return
    end

    SortLocksmithSupplierContracts(normalizedContracts)
    SetLocksmithGlobalBusinessSetting('supplier_contracts_json', json.encode(normalizedContracts), src)
    AddLocksmithLog('setup_supplier_contracts', ('Global supplier contracts updated (%s contracts)'):format(#normalizedContracts), src, nil, '__global')
    Notify(src, T('label_locksmith'), T('success_locksmith_supplier_updated', { supplier = 'catalog' }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    RefreshLocksmithBusinessForStaff()
end)

RegisterNetEvent('partay_keys:server:ResetGlobalLocksmithSupplierContracts', function()
    local src = source
    local setup = GetLocksmithSetupConfig()
    if not setup or setup.Enabled ~= true or not IsPlayerLocksmithSetupAdmin(src, setup) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    SetLocksmithGlobalBusinessSetting('supplier_contracts_json', json.encode(GetDefaultLocksmithSupplierContracts()), src)
    AddLocksmithLog('setup_supplier_contracts_reset', 'Global supplier contracts reset to defaults', src, nil, '__global')
    Notify(src, T('label_locksmith'), T('success_locksmith_supplier_updated', { supplier = 'defaults' }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    RefreshLocksmithBusinessForStaff()
end)

RegisterNetEvent('partay_keys:server:SetLocksmithSetupOrderPrice', function(priceKey, price)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if not setup or setup.Enabled ~= true or not IsPlayerLocksmithSetupAdmin(src, setup) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    if SaveLocksmithPriceOverride(src, priceKey, price, { order = true }) then
        TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    end
end)

RegisterNetEvent('partay_keys:server:SetLocksmithSetupStaffDefaults', function(data)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if not setup or setup.Enabled ~= true or not IsPlayerLocksmithSetupAdmin(src, setup) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    data = type(data) == 'table' and data or {}
    local current = GetLocksmithStaffDefaults()
    local minGrade = math.max(0, math.floor(tonumber(data.minEmployeeGrade) or current.minEmployeeGrade or 0))
    local maxGrade = math.max(minGrade, math.floor(tonumber(data.maxEmployeeGrade) or current.maxEmployeeGrade or minGrade))
    local defaultHireGrade = math.max(minGrade, math.min(maxGrade, math.floor(tonumber(data.defaultHireGrade) or current.defaultHireGrade or minGrade)))
    local fireJob = tostring(data.fireJob or current.fireJob or 'unemployed'):gsub('^%s*(.-)%s*$', '%1')
    local fireGrade = math.max(0, math.floor(tonumber(data.fireGrade) or current.fireGrade or 0))
    if fireJob == '' then fireJob = 'unemployed' end

    SetLocksmithGlobalBusinessSetting('staff_min_employee_grade', minGrade, src)
    SetLocksmithGlobalBusinessSetting('staff_max_employee_grade', maxGrade, src)
    SetLocksmithGlobalBusinessSetting('staff_default_hire_grade', defaultHireGrade, src)
    SetLocksmithGlobalBusinessSetting('staff_fire_job', fireJob, src)
    SetLocksmithGlobalBusinessSetting('staff_fire_grade', fireGrade, src)
    AddLocksmithLog('setup_staff_defaults', ('Global staff defaults updated: hire %s, range %s-%s, fire %s:%s'):format(defaultHireGrade, minGrade, maxGrade, fireJob, fireGrade), src, nil, '__global')
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_saved', { point = 'Staff defaults' }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    RefreshLocksmithBusinessForStaff()
end)

RegisterNetEvent('partay_keys:server:SetGlobalBlackmarketSettings', function(data)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if not setup or setup.Enabled ~= true or not IsPlayerLocksmithSetupAdmin(src, setup) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    data = type(data) == 'table' and data or {}
    local current = GetBlackmarketSettingsPayload()
    local enabled = data.enabled == nil and current.enabled or (data.enabled == true or tostring(data.enabled):lower() == 'true')
    local showOnMap = data.showOnMap == nil and current.showOnMap or (data.showOnMap == true or tostring(data.showOnMap):lower() == 'true')
    local model = tostring(data.model or current.model or 's_m_y_dealer_01'):gsub('^%s*(.-)%s*$', '%1')
    local currency = tostring(data.currency or current.currency or 'black_money'):gsub('^%s*(.-)%s*$', '%1')
    local blip = type(data.blip) == 'table' and data.blip or {}
    local coords = type(data.coords) == 'table' and data.coords or current.coords

    if model == '' then model = 's_m_y_dealer_01' end
    if currency == '' then currency = 'black_money' end

    SetLocksmithGlobalBusinessSetting('blackmarket_enabled', enabled and 'true' or 'false', src)
    SetLocksmithGlobalBusinessSetting('blackmarket_model', model, src)
    SetLocksmithGlobalBusinessSetting('blackmarket_currency', currency, src)
    SetLocksmithGlobalBusinessSetting('blackmarket_show_on_map', showOnMap and 'true' or 'false', src)
    SetLocksmithGlobalBusinessSetting('blackmarket_blip_label', tostring(blip.label or current.blip.label or 'Blackmarket'):sub(1, 40), src)
    SetLocksmithGlobalBusinessSetting('blackmarket_blip_sprite', math.max(0, math.floor(tonumber(blip.sprite) or current.blip.sprite or 378)), src)
    SetLocksmithGlobalBusinessSetting('blackmarket_blip_color', math.max(0, math.floor(tonumber(blip.color) or current.blip.color or 1)), src)
    SetLocksmithGlobalBusinessSetting('blackmarket_blip_scale', math.max(0.1, tonumber(blip.scale) or current.blip.scale or 0.75), src)
    if coords then
        SetLocksmithGlobalBusinessSetting('blackmarket_coords', EncodeSettingsCoords(coords), src)
    end

    if type(data.items) == 'table' then
        for _, item in ipairs(data.items) do
            local itemName = tostring(item.item or '')
            if itemName ~= '' then
                SetLocksmithGlobalBusinessSetting(('blackmarket_item_price_%s'):format(itemName), math.max(0, math.floor(tonumber(item.price) or 0)), src)
            end
        end
    end

    AddLocksmithLog('setup_blackmarket', 'Global blackmarket settings updated', src, nil, '__global')
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_saved', { point = 'Blackmarket settings' }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
end)

RegisterNetEvent('partay_keys:server:SetGlobalWarehousePickupSettings', function(data)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if not setup or setup.Enabled ~= true or not IsPlayerLocksmithSetupAdmin(src, setup) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    data = type(data) == 'table' and data or {}
    local current = GetWarehousePickupSettingsPayload()
    local enabled = data.enabled == nil and current.enabled or (data.enabled == true or tostring(data.enabled):lower() == 'true')
    local spawnPed = data.spawnPed == nil and current.spawnPed or (data.spawnPed == true or tostring(data.spawnPed):lower() == 'true')
    local showOnMap = data.showOnMap == nil and current.showOnMap or (data.showOnMap == true or tostring(data.showOnMap):lower() == 'true')
    local pedModel = tostring(data.pedModel or current.pedModel or GetLocksmithStockingProp('WarehousePed', 's_m_m_warehouse_01')):gsub('^%s*(.-)%s*$', '%1')
    local blip = type(data.blip) == 'table' and data.blip or {}
    local coords = type(data.coords) == 'table' and data.coords or current.coords

    if pedModel == '' then pedModel = GetLocksmithStockingProp('WarehousePed', 's_m_m_warehouse_01') end

    SetLocksmithGlobalBusinessSetting('warehouse_pickup_enabled', enabled and 'true' or 'false', src)
    SetLocksmithGlobalBusinessSetting('warehouse_pickup_spawn_ped', spawnPed and 'true' or 'false', src)
    SetLocksmithGlobalBusinessSetting('warehouse_pickup_ped_model', pedModel, src)
    SetLocksmithGlobalBusinessSetting('warehouse_pickup_show_on_map', showOnMap and 'true' or 'false', src)
    SetLocksmithGlobalBusinessSetting('warehouse_pickup_blip_label', tostring(blip.label or current.blip.label or 'Locksmith Warehouse'):sub(1, 40), src)
    SetLocksmithGlobalBusinessSetting('warehouse_pickup_blip_sprite', math.max(0, math.floor(tonumber(blip.sprite) or current.blip.sprite or 473)), src)
    SetLocksmithGlobalBusinessSetting('warehouse_pickup_blip_color', math.max(0, math.floor(tonumber(blip.color) or current.blip.color or 5)), src)
    SetLocksmithGlobalBusinessSetting('warehouse_pickup_blip_scale', math.max(0.1, tonumber(blip.scale) or current.blip.scale or 0.75), src)
    if coords then
        SetLocksmithGlobalBusinessSetting('warehouse_pickup_coords', EncodeSettingsCoords(coords), src)
    end

    AddLocksmithLog('setup_warehouse_pickup', 'Global warehouse pickup settings updated', src, nil, '__global')
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_saved', { point = 'Warehouse pickup' }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    TriggerClientEvent('partay_keys:client:RefreshLocksmithLocations', -1)
end)

RegisterNetEvent('partay_keys:server:SetGlobalLocksmithRecipes', function(recipes)
    local src = source
    local setup = GetLocksmithSetupConfig()
    if not setup or setup.Enabled ~= true or not IsPlayerLocksmithSetupAdmin(src, setup) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    if type(recipes) ~= 'table' then
        Notify(src, T('label_locksmith'), T('error_locksmith_recipe_invalid'), 'error')
        return
    end

    local normalizedRecipes = {}
    local seen = {}
    for _, recipe in ipairs(recipes) do
        local normalized = NormalizeLocksmithRecipe(recipe)
        if not normalized or seen[normalized.id] then
            Notify(src, T('label_locksmith'), T('error_locksmith_recipe_invalid'), 'error')
            return
        end
        local validItems, invalidItem = ValidateLocksmithRecipeItems(normalized)
        if not validItems then
            Notify(src, T('label_locksmith'), T('error_locksmith_recipe_item_invalid', { item = invalidItem or 'unknown' }), 'error')
            return
        end

        normalizedRecipes[#normalizedRecipes + 1] = normalized
        seen[normalized.id] = true
    end

    if #normalizedRecipes < 1 then
        Notify(src, T('label_locksmith'), T('error_locksmith_recipe_invalid'), 'error')
        return
    end

    SetLocksmithGlobalBusinessSetting('locksmith_recipes_json', json.encode(normalizedRecipes), src)
    AddLocksmithLog('setup_recipes', ('Global locksmith recipes updated: %s recipes'):format(#normalizedRecipes), src, nil, '__global')
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_saved', { point = 'Recipes' }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    RefreshLocksmithBusinessForStaff()
end)

RegisterNetEvent('partay_keys:server:ResetGlobalLocksmithRecipes', function()
    local src = source
    local setup = GetLocksmithSetupConfig()
    if not setup or setup.Enabled ~= true or not IsPlayerLocksmithSetupAdmin(src, setup) then
        Notify(src, T('label_locksmith'), T('error_locksmith_setup_no_permission'), 'error')
        return
    end

    SetLocksmithGlobalBusinessSetting('locksmith_recipes_json', json.encode(GetDefaultLocksmithRecipes()), src)
    AddLocksmithLog('setup_recipes_reset', 'Global locksmith recipes reset to defaults', src, nil, '__global')
    Notify(src, T('label_locksmith'), T('success_locksmith_setup_saved', { point = 'Default recipes' }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithSetup', src)
    RefreshLocksmithBusinessForStaff()
end)

RegisterNetEvent('partay_keys:server:PayLocksmithEmployee', function(targetId, amount)
    local src = source
    if not HasLocksmithManagementPermission(src, 'Payroll') then
        Notify(src, T('label_locksmith'), T('error_locksmith_management_permission'), 'error')
        return
    end

    targetId = tonumber(targetId)
    amount = math.floor(tonumber(amount) or 0)
    local playerRun = GetLocksmithPlayerRunConfig() or {}
    local payment = playerRun.Payment or {}
    if payment.PayrollEnabled == false or amount <= 0 then
        Notify(src, T('label_locksmith'), T('error_locksmith_payroll_invalid'), 'error')
        return
    end

    local maxPayout = tonumber(payment.MaxPayrollPayout) or 0
    if maxPayout > 0 and amount > maxPayout then
        Notify(src, T('label_locksmith'), T('error_locksmith_payroll_cap', { amount = maxPayout }), 'error')
        return
    end

    if not targetId or not GetPlayerName(targetId) or not IsPlayerLocksmithEmployee(targetId) then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_target_invalid'), 'error')
        return
    end

    if payment.PaySource == 'society' then
        local business = GetLocksmithBusinessConfig() or {}
        if not Bridge.RemoveSocietyMoney or not Bridge.RemoveSocietyMoney(GetLocksmithSocietyAccount(src), amount) then
            Notify(src, T('label_locksmith'), T('error_locksmith_payroll_source_failed'), 'error')
            return
        end
    end

    local account = payment.PayrollAccount or payment.EmployeeCommissionAccount or 'bank'
    if not Bridge.AddCurrency(targetId, account, amount) then
        Notify(src, T('label_locksmith'), T('error_locksmith_payroll_failed'), 'error')
        return
    end

    AddLocksmithLog('payroll_paid', ('%s paid $%s to %s'):format(GetPlayerName(src), amount, GetPlayerName(targetId)), src, targetId)
    Notify(src, T('label_locksmith'), T('success_locksmith_payroll_paid', { amount = amount, name = GetPlayerName(targetId) }), 'success')
    Notify(targetId, T('label_locksmith'), T('success_locksmith_payroll_received', { amount = amount }), 'success')
    TriggerClientEvent('partay_keys:client:RefreshLocksmithBusiness', src)
end)

RegisterNetEvent('partay_keys:server:RequestLocksmithAppointment', function(plate, message, preferences)
    local src = source
    EnsureLocksmithAppointmentSchema()

    local playerRun = GetLocksmithPlayerRunConfig()
    local appointments = playerRun and playerRun.Appointments
    if not appointments or appointments.Enabled == false then
        Notify(src, T('label_locksmith'), T('error_locksmith_appointments_unavailable'), 'error')
        return
    end

    local citizenId = Bridge.GetCitizenID(src)
    if not citizenId then
        Notify(src, T('label_locksmith'), T('error_character_unavailable'), 'error')
        return
    end

    plate = TrimPlate(plate)
    message = tostring(message or ''):sub(1, 255)
    preferences = type(preferences) == 'table' and preferences or {}
    local function cleanPreference(value, maxLength)
        return tostring(value or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, maxLength)
    end
    local contactPhone = cleanPreference(preferences.phone or preferences.contactPhone, 80)
    local preferredDate = cleanPreference(preferences.date, 40)
    local preferredTime = cleanPreference(preferences.time, 40)
    local preferredFor = (preferredDate ~= '' and preferredTime ~= '') and (preferredDate .. ' ' .. preferredTime)
        or preferredDate ~= '' and preferredDate
        or preferredTime
    local appointmentId = MakeLocksmithRecordId('appt')
    local expiresAt = os.time() + (math.max(1, tonumber(appointments.ExpireMinutes) or 20) * 60)
    local appointment = {
        id = appointmentId,
        customerName = Bridge.GetCharacterName and Bridge.GetCharacterName(src) or GetPlayerName(src),
        plate = plate,
        message = message
    }

    MySQL.Sync.execute([[
        INSERT INTO partay_locksmith_appointments
            (appointment_id, customer_id, customer_name, contact_name, contact_phone, plate, message, status, scheduled_for, scheduled_date, scheduled_time, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, FROM_UNIXTIME(?))
    ]], {
        appointmentId,
        citizenId,
        appointment.customerName,
        appointment.customerName,
        contactPhone,
        plate,
        message,
        preferredFor,
        preferredDate,
        preferredTime,
        expiresAt
    })

    AddLocksmithLog('appointment_requested', ('Appointment %s requested by %s'):format(appointmentId, appointment.customerName), src)
    NotifyLocksmithAppointment(appointment)
    Notify(src, T('label_locksmith'), T('success_locksmith_appointment_requested'), 'success')
    RefreshLocksmithBusinessForStaff()
end)

local function ManageLocksmithAppointment(src, appointmentId, action, scheduleData)
    EnsureLocksmithAppointmentSchema()

    appointmentId = tostring(appointmentId or '')
    action = tostring(action or ''):lower()

    local permissionKey = (action == 'confirm' or action == 'schedule') and 'AppointmentSchedule'
        or action == 'complete' and 'AppointmentComplete'
        or action == 'cancel' and 'AppointmentCancel'
        or action == 'reminder' and 'AppointmentReminder'
        or nil

    if not permissionKey or not HasLocksmithManagementPermission(src, permissionKey) then
        Notify(src, T('label_locksmith'), T('error_locksmith_management_permission'), 'error')
        return false, 'permission'
    end

    local rows = MySQL.Sync.fetchAll([[
        SELECT appointment_id, customer_id, customer_name, contact_name, contact_phone, contact_email, plate, message, status, scheduled_for, scheduled_date, scheduled_time, schedule_note
        FROM partay_locksmith_appointments
        WHERE appointment_id = ?
        LIMIT 1
    ]], { appointmentId }) or {}
    local appointment = rows[1]
    if not appointment then
        Notify(src, T('label_locksmith'), T('error_locksmith_appointment_unavailable'), 'error')
        return false, 'missing'
    end

    local employeeName = Bridge.GetCharacterName and Bridge.GetCharacterName(src) or GetPlayerName(src)
    if action == 'reminder' then
        SendLocksmithAppointmentCustomerMessage(appointment.customer_id, 'info_locksmith_appointment_reminder_customer', {
            plate = appointment.plate or T('label_vehicle'),
            scheduled = appointment.scheduled_for or T('label_pending')
        })
        AddLocksmithLog('appointment_reminder', ('%s sent reminder for appointment %s'):format(employeeName, appointmentId), src, FindOnlinePlayerByCitizenId(appointment.customer_id))
        Notify(src, T('label_locksmith'), T('success_locksmith_appointment_reminder_sent'), 'success')
        RefreshLocksmithBusinessForStaff()
        return true
    end

    local nextStatus = action == 'confirm' and 'confirmed'
        or action == 'schedule' and 'scheduled'
        or action == 'complete' and 'completed'
        or action == 'cancel' and 'canceled'
        or nil
    if not nextStatus then return false, 'action' end

    scheduleData = type(scheduleData) == 'table' and scheduleData or {}
    local function cleanScheduleField(value, maxLength)
        return tostring(value or ''):gsub('^%s*(.-)%s*$', '%1'):sub(1, maxLength)
    end

    local contactName = cleanScheduleField(scheduleData.contactName, 100)
    local contactPhone = cleanScheduleField(scheduleData.contactPhone, 80)
    local contactEmail = cleanScheduleField(scheduleData.contactEmail, 120)
    local scheduledDate = cleanScheduleField(scheduleData.date, 40)
    local scheduledTime = cleanScheduleField(scheduleData.time, 40)
    local scheduleNote = cleanScheduleField(scheduleData.note, 255)
    local scheduledFor = cleanScheduleField(scheduleData.scheduledFor, 80)
    if scheduledFor == '' then
        scheduledFor = (scheduledDate ~= '' and scheduledTime ~= '') and (scheduledDate .. ' ' .. scheduledTime)
            or scheduledDate ~= '' and scheduledDate
            or scheduledTime
    end

    if action == 'schedule' and (contactName == '' or contactPhone == '') then
        Notify(src, T('label_locksmith'), T('error_locksmith_schedule_contact_required'), 'error')
        return false, 'contact'
    end

    MySQL.Sync.execute([[
        UPDATE partay_locksmith_appointments
        SET status = ?, accepted_by = ?, accepted_by_name = ?, customer_name = ?, contact_name = ?, contact_phone = ?, contact_email = ?, scheduled_for = ?, scheduled_date = ?, scheduled_time = ?, schedule_note = ?
        WHERE appointment_id = ?
    ]], {
        nextStatus,
        Bridge.GetCitizenID(src),
        employeeName,
        action == 'schedule' and contactName or appointment.customer_name,
        action == 'schedule' and contactName or appointment.contact_name,
        action == 'schedule' and contactPhone or appointment.contact_phone,
        action == 'schedule' and contactEmail or appointment.contact_email,
        action == 'schedule' and scheduledFor or appointment.scheduled_for,
        action == 'schedule' and scheduledDate or appointment.scheduled_date,
        action == 'schedule' and scheduledTime or appointment.scheduled_time,
        action == 'schedule' and scheduleNote or appointment.schedule_note,
        appointmentId
    })

    local customerLocale = action == 'confirm' and 'info_locksmith_appointment_confirmed_customer'
        or action == 'schedule' and 'info_locksmith_appointment_scheduled_customer'
        or 'info_locksmith_appointment_status_customer'
    SendLocksmithAppointmentCustomerMessage(appointment.customer_id, customerLocale, {
        status = nextStatus,
        plate = appointment.plate or T('label_vehicle'),
        scheduled = scheduledFor ~= '' and scheduledFor or (appointment.scheduled_for or T('label_pending')),
        note = scheduleNote ~= '' and scheduleNote or (appointment.schedule_note or '')
    })

    AddLocksmithLog(('appointment_%s'):format(action), ('%s set appointment %s to %s'):format(employeeName, appointmentId, nextStatus), src, FindOnlinePlayerByCitizenId(appointment.customer_id))
    Notify(src, T('label_locksmith'), T('success_locksmith_appointment_updated', { status = nextStatus }), 'success')
    RefreshLocksmithBusinessForStaff()
    return true
end

lib.callback.register('partay_keys:server:ManageLocksmithAppointment', function(src, appointmentId, action, scheduleData)
    local ok, result, reason = pcall(ManageLocksmithAppointment, src, appointmentId, action, scheduleData)
    if not ok then
        if Config.DebugMode then
            print(('[ParTay Keys Debug] Manage locksmith appointment failed: %s'):format(tostring(result)))
        end
        Notify(src, T('label_locksmith'), T('error_locksmith_management_failed'), 'error')
        return { ok = false, reason = 'exception' }
    end

    return { ok = result == true, reason = reason }
end)

RegisterNetEvent('partay_keys:server:ManageLocksmithAppointment', function(appointmentId, action, scheduleData)
    ManageLocksmithAppointment(source, appointmentId, action, scheduleData)
end)

RegisterNetEvent('partay_keys:server:PayLocksmithInvoice', function(jobId, accepted, paymentMethod)
    local src = source
    local job = ActiveLocksmithJobs[jobId]
    paymentMethod = paymentMethod == 'bank' and 'bank' or 'cash'
    if not job or job.customerId ~= src or job.expiresAt < os.time() then
        Notify(src, T('label_locksmith'), T('error_locksmith_job_expired'), 'error')
        if job then
            UpdateLocksmithInvoiceStatus(job.id, 'expired')
            ReleaseLocksmithHeldKeys(job)
            ActiveLocksmithJobs[jobId] = nil
        end
        return
    end

    if accepted ~= true then
        UpdateLocksmithInvoiceStatus(job.id, 'payment_declined')
        AddLocksmithLog('payment_declined', ('Payment declined for invoice %s'):format(job.id), job.employeeId, src)
        Notify(src, T('label_locksmith'), T('info_locksmith_payment_declined'), 'info')
        if GetPlayerName(job.employeeId) then
            Notify(job.employeeId, T('label_locksmith'), T('info_locksmith_customer_payment_declined'), 'info')
        end
        return
    end

    local locationName = GetLocksmithBusinessLocationName(job.locationName or job.employeeId, true)
    local stockRequirements = GetLocksmithStockRequirementsForServices(job.services)
    local stockOk = HasLocksmithStock(stockRequirements, locationName)
    if not stockOk then
        Notify(src, T('label_locksmith'), T('error_locksmith_stock_missing'), 'error')
        if GetPlayerName(job.employeeId) then
            Notify(job.employeeId, T('label_locksmith'), T('error_locksmith_stock_missing'), 'error')
        end
        return
    end

    if job.total > 0 then
        if not Bridge.HasCurrency(src, paymentMethod, job.total) then
            Notify(src, T('label_locksmith'), T('error_locksmith_invoice_cannot_afford'), 'error')
            if GetPlayerName(job.employeeId) then
                Notify(job.employeeId, T('label_locksmith'), T('error_locksmith_customer_cannot_afford'), 'error')
            end
            return
        end

        if not Bridge.RemoveCurrency(src, paymentMethod, job.total) then
            Notify(src, T('label_locksmith'), T('error_payment_process_failed'), 'error')
            return
        end
    end

    local business = GetLocksmithBusinessConfig() or {}
    local payment = GetLocksmithPaymentSettings(locationName)
    local commissionAmount = 0
    local commissionPaid = false
    if job.total > 0 and GetPlayerName(job.employeeId) then
        commissionAmount = GetLocksmithCommissionAmount(job.total, payment)
        if commissionAmount > 0 then
            local commissionAccount = payment.EmployeeCommissionAccount or 'cash'
            if Bridge.AddCurrency(job.employeeId, commissionAccount, commissionAmount) then
                commissionPaid = true
                Notify(job.employeeId, T('label_locksmith'), T('success_locksmith_commission_paid', {
                    amount = commissionAmount,
                    service = 'invoice'
                }), 'success')
            else
                local failedCommission = commissionAmount
                commissionAmount = 0
                if Config.DebugMode then
                    print(('^5[ParTay Keys Debug]^3 Locksmith commission failed employee=%s amount=%s^0'):format(tostring(job.employeeId), tostring(failedCommission)))
                end
            end
        end
    end

    local societyAmount = math.max(0, math.floor((tonumber(job.total) or 0) - commissionAmount))
    local societyDeposit = 0
    if business.SocietyDeposits == true and societyAmount > 0 then
        local account = GetLocksmithSocietyAccount(job.employeeId or src)
        if Bridge.AddSocietyMoney(account, societyAmount) then
            societyDeposit = societyAmount
        elseif Config.DebugMode then
            print(('^5[ParTay Keys Debug]^3 Locksmith society deposit failed account=%s amount=%s^0'):format(tostring(account), tostring(societyAmount)))
        end
    end

    stockOk = ConsumeLocksmithStock(stockRequirements, locationName)
    if not stockOk then
        Notify(src, T('label_locksmith'), T('error_locksmith_stock_missing'), 'error')
        if GetPlayerName(job.employeeId) then
            Notify(job.employeeId, T('label_locksmith'), T('error_locksmith_stock_missing'), 'error')
        end
        return
    end

    ConfirmedLocksmithServices[src] = {
        employeeId = job.employeeId,
        plate = job.plate,
        netId = job.netId,
        services = job.services,
        paid = true,
        invoiceId = job.id,
        jobId = job.id,
        locationName = locationName,
        commissionPaid = commissionPaid,
        commissionAmount = commissionAmount,
        expiresAt = os.time() + 45
    }

    ReleaseLocksmithHeldKeys(job)
    ActiveLocksmithJobs[jobId] = nil
    UpdateLocksmithInvoiceStatus(job.id, 'paid', paymentMethod, societyDeposit)
    AddLocksmithLog('invoice_paid', ('Invoice %s paid for %s'):format(job.id, job.plate or 'unknown'), job.employeeId, src)

    TriggerClientEvent('partay_keys:client:RunConfirmedLocksmithService', src, {
        services = job.services,
        plate = job.plate,
        netId = job.netId,
        paymentMethod = paymentMethod
    })

    Notify(src, T('label_locksmith'), T('success_locksmith_invoice_paid'), 'success')
    if GetPlayerName(job.employeeId) then
        Notify(job.employeeId, T('label_locksmith'), T('success_locksmith_invoice_paid_employee'), 'success')
    end
end)

RegisterNetEvent('partay_keys:server:CreatePhysicalKeyCopy', function(plate, paymentMethod)
    local src = source
    local citizenId = Bridge.GetCitizenID(src)
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    paymentMethod = paymentMethod == 'bank' and 'bank' or 'cash'
    local confirmedService = ConsumeConfirmedLocksmithService(src, 'copy', plate)
    if not confirmedService and GetLocksmithPlayerRunConfig() then
        Notify(src, T('label_locksmith'), T('error_locksmith_staff_required'), 'error')
        return
    end
    if not citizenId then
        Notify(src, 'Key Copy', 'Unable to identify your character.', 'error')
        return
    end
    if not plate or plate == '' then
        Notify(src, 'Key Copy', 'No vehicle key was selected.', 'error')
        return
    end

    local registration = GetVehicleRegistrationForOwner(plate, citizenId)
    if not registration then
        Notify(src, 'Key Copy', 'Only the registered owner can create a physical copy.', 'error')
        return
    end

    local fee = GetLocksmithServiceFee('copy')
    if fee > 0 and not (confirmedService and confirmedService.paid == true) then
        if not Bridge.HasCurrency(src, paymentMethod, fee) then
            Notify(src, 'Key Copy', ('You cannot afford the copy fee using %s.'):format(paymentMethod), 'error')
            return
        end
    end

    local keyVersion = tonumber(registration.key_version) or GetVehicleKeyVersionFromDB(plate)
    local keyTier = GetActiveKeyTierFromDB(plate, citizenId)
    if Bridge.GiveVehicleKey(src, plate, registration.vehicle or registration.model or 'Vehicle', keyVersion, citizenId, {
        key_tier = keyTier
    }) then
        if fee > 0 and not (confirmedService and confirmedService.paid == true) and not Bridge.RemoveCurrency(src, paymentMethod, fee) then
            Notify(src, 'Key Copy', 'Payment could not be processed.', 'error')
            return
        end
        Notify(src, 'Key Copy', 'Physical key copy created.', 'success')
        PayLocksmithEmployeeCommission(confirmedService, fee, 'key copy')
    else
        Notify(src, 'Key Copy', 'You already have a current physical key.', 'info')
    end
end)

RegisterNetEvent('partay_keys:server:GiveKeyCopy', function(targetId, plate, possession_id)
    local src = source
    targetId = tonumber(targetId)
    if not targetId or not plate or not possession_id or targetId == src then
        Notify(src, 'Key Share', 'Invalid key share target.', 'error')
        return
    end

    local sourcePed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetId)
    if not sourcePed or sourcePed == 0 or not targetPed or targetPed == 0 then
        Notify(src, 'Key Share', 'That player is no longer nearby.', 'error')
        return
    end

    if #(GetEntityCoords(sourcePed) - GetEntityCoords(targetPed)) > (Config.KeyHandoffRadius or 3.0) + 1.0 then
        Notify(src, 'Key Share', 'That player is too far away.', 'error')
        return
    end

    local metadata = GetKeyMetadataFromInventory(src, plate, possession_id)
    if not metadata then
        Notify(src, 'Key Share', 'You do not have that key to share.', 'error')
        return
    end

    if metadata.shared == true then
        Notify(src, 'Key Share', 'Shared keys cannot be legally copied.', 'error')
        return
    end

    local ownerId = Bridge.GetCitizenID(src)
    local targetCitizenId = Bridge.GetCitizenID(targetId)
    if not ownerId or not targetCitizenId then
        Notify(src, 'Key Share', 'Unable to verify both players.', 'error')
        return
    end
    local ownerName = Bridge.GetCharacterName and Bridge.GetCharacterName(src) or GetPlayerName(src)
    local targetName = Bridge.GetCharacterName and Bridge.GetCharacterName(targetId) or GetPlayerName(targetId)

    local currentCopies = PartayKeys_CountActiveSharedKeys and PartayKeys_CountActiveSharedKeys(plate, ownerId) or CountPlayerKeys(targetId, plate)
    if currentCopies >= (Config.SharedKeysLimit or 3) then
        Notify(src, 'Key Share', 'That player already has the maximum number of key copies for this vehicle.', 'error')
        return
    end

    local sharedMetadata = {}
    for key, value in pairs(metadata) do
        sharedMetadata[key] = value
    end
    sharedMetadata.shared = true
    sharedMetadata.shared_by = ownerId
    sharedMetadata.shared_by_name = ownerName
    sharedMetadata.key_tier = sharedMetadata.key_tier or Config.DefaultKeyTier or 'smart'

    local sharedKeyItem = PartayKeys_GetKeyItemForTier(sharedMetadata.key_tier)
    Bridge.AddInventoryItem(targetId, sharedKeyItem, 1, sharedMetadata)
    if PartayKeys_RecordVehicleKey then
        PartayKeys_RecordVehicleKey({
            plate = plate,
            owner_id = ownerId,
            owner_name = ownerName,
            holder_id = targetCitizenId,
            holder_name = targetName,
            key_type = 'shared',
            key_tier = sharedMetadata.key_tier,
            key_version = tonumber(sharedMetadata.key_version) or GetVehicleKeyVersionFromDB(plate),
            possession_id = sharedMetadata.possession_id or possession_id,
            issued_by = ownerId,
            issued_by_name = ownerName,
            metadata = sharedMetadata
        })
    end

    Notify(src, 'Key Share', 'Key successfully shared with the target player.', 'success')
    Notify(targetId, 'Key Received', ('You received a key for vehicle %s.'):format(plate), 'success')
    exports.partay_keys:SendAuditLog('Key Shared', ('Player %s shared vehicle key %s with player %s'):format(src, plate, targetId), 'info')
end)

RegisterNetEvent('partay_keys:server:FobAction', function(action, netId, actionSource)
    local src = source
    if type(action) ~= 'string' or not netId then return end
    actionSource = actionSource == 'basic_key_preanimated' and 'basic_key_preanimated'
        or actionSource == 'basic_key' and 'basic_key'
        or actionSource == 'proximity' and 'proximity'
        or 'fob'

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return end
    local distanceToVehicle = GetPlayerDistanceToEntity(src, veh)
    if action ~= 'valet' and distanceToVehicle > 25.0 then return end

    local plate = TrimPlate(GetVehicleNumberPlateText(veh))
    local possessionId = Entity(veh).state.possession_id
    local registration = GetVehicleRegistration(plate)
    local ownerColumn = GetOwnerColumn()
    local citizenId = Bridge.GetCitizenID(src)
    if registration and registration.possession_id and registration.possession_id ~= '' and registration.possession_id ~= possessionId then
        possessionId = registration.possession_id
        Entity(veh).state:set('possession_id', possessionId, true)
        Entity(veh).state:set('isStolen', possessionId ~= registration[ownerColumn], true)
        Entity(veh).state:set('original_owner_id', registration[ownerColumn], true)
    end

    local metadata = GetKeyMetadataFromInventory(src, plate, possessionId)
    local hasTemporaryNpcKey = not registration and citizenId and possessionId == citizenId
        and Entity(veh).state.npcRobberyKeysGranted == citizenId
    local keyVersion = hasTemporaryNpcKey and 'temporary_npc' or metadata and metadata.key_version
    local keyTier = hasTemporaryNpcKey and 'basic' or PartayKeys_GetKeyTierFromMetadata(metadata)
    if actionSource == 'fob' and keyTier == 'basic' and (action == 'toggle' or action == 'lock' or action == 'unlock') then
        actionSource = 'basic_key'
    end

    if not PartayKeys_PlayerHasVehicleAccess(src, plate, possessionId, keyVersion) then
        if action == 'toggle' or action == 'lock' or action == 'unlock' then
            TriggerClientEvent('partay_keys:client:TryLockedDoor', src, netId)
        else
            Notify(src, 'Access Denied', 'You do not have valid access to this vehicle.', 'error')
        end
        return
    end

    local capability = action == 'toggle' and 'toggle'
        or action == 'remote_engine' and 'remote_engine'
        or action
    if actionSource == 'proximity' and not PartayKeys_KeyTierHasCapability(keyTier, 'proximity') then
        return
    end

    if not PartayKeys_KeyTierHasCapability(keyTier, capability) then
        Notify(src, 'Key Fob', 'This key system does not support that feature.', 'error')
        return
    end

    local lockState = Entity(veh).state.lockState or GetVehicleDoorLockStatus(veh)
    local nextLockState = lockState

    if Config.DebugMode then
        print(('^5[ParTay Keys Debug]^3 FobAction - Action: %s, Current LockState: %s^0'):format(action, lockState))
    end

    if action == 'lock' then
        nextLockState = LOCKED
    elseif action == 'unlock' then
        nextLockState = UNLOCKED
    elseif action == 'toggle' then
        nextLockState = (lockState == LOCKED) and UNLOCKED or LOCKED
        if Config.DebugMode then
            print(('^5[ParTay Keys Debug]^3 Toggle - Current: %s, Next: %s^0'):format(lockState, nextLockState))
        end
    elseif action ~= 'trunk' and action ~= 'alarm' and action ~= 'headlights' and action ~= 'remote_engine' and action ~= 'valet' then
        return
    end

    local remoteHeadlights
    local remoteEngineRunning
    if action == 'lock' or action == 'unlock' or action == 'toggle' then
        Entity(veh).state:set('lockState', nextLockState, true)
        Entity(veh).state:set('alarmActive', false, true)
        SetVehicleDoorsLocked(veh, nextLockState)
        if Config.DebugMode then
            print(('^5[ParTay Keys Debug]^2 Set LockState to: %s^0'):format(nextLockState))
        end
    elseif action == 'alarm' then
        if not VehicleHasAlarm(veh, plate) then
            Notify(src, 'Vehicle Alarm', 'This vehicle does not have an alarm system installed.', 'error')
            return
        end

        TriggerInstalledAlarm(veh, true, 'FobPanic')
    elseif action == 'headlights' then
        remoteHeadlights = Entity(veh).state.remoteHeadlights == true
        remoteHeadlights = not remoteHeadlights
        Entity(veh).state:set('remoteHeadlights', remoteHeadlights, true)
    elseif action == 'remote_engine' then
        remoteEngineRunning = Entity(veh).state.remoteEngineRunning ~= true
        Entity(veh).state:set('remoteEngineRunning', remoteEngineRunning, true)
    elseif action == 'valet' then
        local maxDistance = PartayKeys_GetKeyTierNumber(keyTier, 'Valet', 'MaxDistance', 50.0)
        if distanceToVehicle > maxDistance then
            Notify(src, 'OLED Valet', ('The vehicle must be within %sm for valet mode.'):format(math.floor(maxDistance + 0.5)), 'error')
            return
        end

        if not VehicleHasValetModule(veh, plate) then
            Notify(src, 'OLED Valet', 'This vehicle needs a valet module installed first.', 'error')
            return
        end

        local driver = GetPedInVehicleSeat(veh, -1)
        if driver and driver ~= 0 then
            Notify(src, 'OLED Valet', 'Valet mode is unavailable while someone is driving.', 'error')
            return
        end

        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return end
        local targetCoords = GetEntityCoords(ped)
        Entity(veh).state:set('lockState', UNLOCKED, true)
        SetVehicleDoorsLocked(veh, UNLOCKED)
        TriggerClientEvent('partay_keys:client:StartValetDrive', src, netId, {
            x = targetCoords.x,
            y = targetCoords.y,
            z = targetCoords.z
        })
        Notify(src, 'OLED Valet', 'Valet mode engaged.', 'success')
        return
    end

    TriggerClientEvent('partay_keys:client:FobFeedback', src, action, netId, nextLockState, remoteHeadlights, remoteEngineRunning, actionSource)
end)

RegisterNetEvent('partay_keys:server:RecoverVehicle', function(netId, plate, paymentMethod)
    local src = source
    plate = TrimPlate(plate)
    paymentMethod = paymentMethod == 'bank' and 'bank' or 'cash'
    local confirmedService = ConsumeConfirmedLocksmithService(src, 'recover', plate)

    if not plate or plate == '' then
        Notify(src, 'Vehicle Recovery', 'No vehicle was selected for recovery.', 'error')
        return
    end

    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if not veh or veh == 0 then
        veh = FindLiveVehicleByPlate(plate)
    end

    if not veh or veh == 0 then
        Notify(src, 'Vehicle Recovery', 'Bring the registered vehicle close to the locksmith before recovering it.', 'error')
        return
    end

    if TrimPlate(GetVehicleNumberPlateText(veh)) ~= plate then
        Notify(src, 'Vehicle Recovery', 'The selected vehicle no longer matches the recovery record.', 'error')
        return
    end

    if GetPlayerDistanceToEntity(src, veh) > 12.0 then
        Notify(src, 'Vehicle Recovery', 'Move closer to the vehicle before recovering it.', 'error')
        return
    end

    if not confirmedService and Config.Heist.RecoveryRequiresLocksmith and IsLocksmithEnabled() and not IsPlayerNearLocksmith(src, 10.0) then
        Notify(src, 'Vehicle Recovery', 'Vehicle recovery must be completed at a locksmith.', 'error')
        return
    end

    local allowedLocksmith, locksmithReason = CanUseLocksmithService(src)
    if not confirmedService and Config.Heist.RecoveryRequiresLocksmith and IsLocksmithEnabled() and not allowedLocksmith then
        Notify(src, T('label_locksmith'), T(GetLocksmithAccessError(locksmithReason)), 'error')
        return
    end

    local citizenId = Bridge.GetCitizenID(src)
    local registration = GetVehicleRegistrationForOwner(plate, citizenId)
    if not registration then
        Notify(src, 'Vehicle Recovery', 'Only the registered owner can recover this vehicle.', 'error')
        return
    end

    if not registration.possession_id or registration.possession_id == '' or registration.possession_id == citizenId then
        Notify(src, 'Vehicle Recovery', 'This vehicle is already in your possession.', 'info')
        return
    end

    if not IsVehicleEmpty(veh) then
        Notify(src, 'Vehicle Recovery', 'The vehicle must be empty before recovery.', 'error')
        return
    end

    local fee = GetLocksmithDefaultServiceFee('recover')
    if fee > 0 and not (confirmedService and confirmedService.paid == true) then
        if not Bridge.HasCurrency(src, paymentMethod, fee) then
            Notify(src, 'Vehicle Recovery', ('You cannot afford the recovery fee using %s.'):format(paymentMethod), 'error')
            return
        end
        Bridge.RemoveCurrency(src, paymentMethod, fee)
    end

    local storage = GetVehicleStorage()
    MySQL.Sync.execute(('UPDATE %s SET possession_id = ? WHERE plate = ? AND %s = ?'):format(storage.tableSql, storage.ownerSql), {citizenId, plate, citizenId})
    SyncLiveVehiclePossession(plate, citizenId, citizenId, false)

    Notify(src, 'Vehicle Recovery', 'Vehicle recovered. Re-Key at a locksmith to invalidate stolen keys.', 'success')
    exports.partay_keys:SendAuditLog('Vehicle Recovered', ('Player %s recovered vehicle %s'):format(src, plate), 'info')
    PayLocksmithEmployeeCommission(confirmedService, fee, 'recovery')
end)

local function NormalizePurchaseQuantity(quantity)
    quantity = math.floor(tonumber(quantity) or 1)
    return math.max(1, math.min(quantity, 99))
end

RegisterNetEvent('partay_keys:server:BuyBlackmarketItem', function(itemName, price, quantity)
    local src = source
    local blackmarket = GetBlackmarketSettingsPayload()
    if blackmarket.enabled ~= true then
        Notify(src, T('label_blackmarket'), T('error_blackmarket_unavailable'), 'error')
        return
    end

    itemName = tostring(itemName or '')
    price = tonumber(price) or 0
    quantity = NormalizePurchaseQuantity(quantity)
    if itemName == '' or price < 0 then
        Notify(src, T('label_blackmarket'), T('error_invalid_purchase_request'), 'error')
        return
    end

    local ped = GetPlayerPed(src)
    local bmCoords = blackmarket.coords
    if not ped or ped == 0 or not bmCoords then
        Notify(src, T('label_blackmarket'), T('error_blackmarket_unavailable'), 'error')
        return
    end
    if #(GetEntityCoords(ped) - vector3(bmCoords.x, bmCoords.y, bmCoords.z)) > 10.0 then
        Notify(src, T('label_blackmarket'), T('error_blackmarket_too_far'), 'error')
        return
    end

    local selectedItem
    for _, shopItem in ipairs(blackmarket.items or {}) do
        if shopItem.item == itemName and tonumber(shopItem.price) == price then
            selectedItem = shopItem
            break
        end
    end

    if not selectedItem then
        Notify(src, T('label_blackmarket'), T('error_shop_item_unavailable'), 'error')
        return
    end

    local currency = blackmarket.currency or Config.Heist.BlackmarketCurrency or 'black_money'
    local totalPrice = price * quantity
    if totalPrice > 0 and not Bridge.HasCurrency(src, currency, totalPrice) then
        Notify(src, T('label_blackmarket'), T('error_insufficient_funds'), 'error')
        return
    end

    if totalPrice > 0 and not Bridge.RemoveCurrency(src, currency, totalPrice) then
        Notify(src, T('label_blackmarket'), T('error_payment_process_failed'), 'error')
        return
    end

    Bridge.AddInventoryItem(src, selectedItem.item, quantity)
    Notify(src, T('label_blackmarket'), T('success_shop_purchase', { quantity = quantity, item = selectedItem.label or selectedItem.item }), 'success')
end)

local function CanUseLocksmithShop(src)
    local selfService = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.SelfService or {}
    if selfService.EnableShop == false then
        return false, false, 'error_locksmith_shop_unavailable'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return false, false, 'error_locksmith_unavailable'
    end

    local playerRun = GetLocksmithPlayerRunConfig()
    if playerRun then
        if IsPlayerLocksmithEmployee(src) then
            return false, false, 'error_locksmith_shop_unavailable'
        end

        local _, serviceLocation = IsPlayerNearLocksmithLocation(src, { 'register', 'fallback_ped' }, 10.0)
        local serviceLocationName = serviceLocation and serviceLocation.locationName or GetLocksmithBusinessLocationName(src)
        if GetLocksmithShopStatus(serviceLocationName) == 'closed' then
            return false, false, 'error_locksmith_shop_closed'
        end

        local nearSelfService = IsPlayerNearLocksmithLocation(src, { 'fallback_ped' }, 10.0, 'self_service')
        if nearSelfService then
            return true, false, nil, 'self_service'
        end

        local nearRegister = IsPlayerNearLocksmithLocation(src, { 'register' }, 10.0)
        if not nearRegister then
            return false, false, 'error_locksmith_too_far'
        end

        return true, true, nil, 'register'
    end

    local nearFallbackPed = IsPlayerNearLocksmithLocation(src, { 'fallback_ped' }, 10.0)
    if not nearFallbackPed then
        return false, false, 'error_locksmith_too_far'
    end

    return true, false, nil, 'npc'
end

RegisterNetEvent('partay_keys:server:BuyLocksmithItem', function(itemName, price, paymentMethod, quantity)
    local src = source
    if not IsLocksmithEnabled() then
        Notify(src, T('label_locksmith'), T('error_locksmith_unavailable'), 'error')
        return
    end

    local shopAllowed, customerStaffedOrder, shopError, shopMode = CanUseLocksmithShop(src)
    if not shopAllowed then
        Notify(src, T('label_locksmith'), T(shopError or 'error_locksmith_shop_unavailable'), 'error')
        return
    end

    itemName = tostring(itemName or '')
    price = tonumber(price) or 0
    paymentMethod = paymentMethod == 'bank' and 'bank' or 'cash'
    quantity = NormalizePurchaseQuantity(quantity)
    if itemName == '' or price < 0 then
        Notify(src, T('label_locksmith'), T('error_invalid_purchase_request'), 'error')
        return
    end

    local selectedItem
    local selfService = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith and Config.PlayerJobDefaults.Locksmith.SelfService or {}
    for _, shopItem in ipairs(selfService.Items or {}) do
        if shopItem.item == itemName then
            selectedItem = shopItem
            break
        end
    end

    if not selectedItem then
        Notify(src, T('label_locksmith'), T('error_shop_item_unavailable'), 'error')
        return
    end

    local _, currentShopLocation = IsPlayerNearLocksmithLocation(src, { 'register', 'fallback_ped' }, 10.0)
    local shopLocationName = currentShopLocation and currentShopLocation.locationName or GetLocksmithBusinessLocationName(src)
    local shopProfile = GetLocksmithLocationProfile(shopLocationName)
    price = GetLocksmithPrice(('shop:%s'):format(itemName), tonumber(selectedItem.price) or 0, nil, shopLocationName)
    local totalPrice = price * quantity
    local business = GetLocksmithBusinessConfig()
    local shopStockRequired = shopMode ~= 'self_service' and not customerStaffedOrder and business and business.ConsumeStockForShop == true and HasLocksmithRecipeForItem(selectedItem.item)
    local stockRequirement = shopStockRequired and { { item = selectedItem.item, amount = quantity } } or {}
    if shopStockRequired and not HasLocksmithStock(stockRequirement, shopLocationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_stock_missing'), 'error')
        return
    end

    if totalPrice > 0 and not Bridge.HasCurrency(src, paymentMethod, totalPrice) then
        Notify(src, T('label_locksmith'), T('error_purchase_cannot_afford', { payment = paymentMethod }), 'error')
        return
    end

    if totalPrice > 0 and not Bridge.RemoveCurrency(src, paymentMethod, totalPrice) then
        Notify(src, T('label_locksmith'), T('error_payment_process_failed'), 'error')
        return
    end

    if customerStaffedOrder then
        local location = currentShopLocation or select(2, IsPlayerNearLocksmithLocation(src, { 'register' }, 10.0)) or GetNearestLocksmithStockLocation(src)
        local orderId = MakeLocksmithRecordId('shop')
        local customerCitizenId = Bridge.GetCitizenID(src)
        local customerName = Bridge.GetCharacterName and Bridge.GetCharacterName(src) or GetPlayerName(src)
        local societyDeposit = 0
        if business and business.SocietyDeposits == true and totalPrice > 0 then
            local account = GetLocksmithSocietyAccount((shopProfile and shopProfile.jobName) or src)
            if Bridge.AddSocietyMoney(account, totalPrice) then
                societyDeposit = totalPrice
            elseif Config.DebugMode then
                print(('^5[ParTay Keys Debug]^3 Locksmith shop order society deposit failed account=%s amount=%s^0'):format(tostring(account), tostring(totalPrice)))
            end
        end

        MySQL.Sync.execute([[
            INSERT INTO partay_locksmith_shop_orders
                (order_id, location_name, item_name, label, quantity, total, status, customer_id, customer_name, payment_method)
            VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)
        ]], {
            orderId,
            shopLocationName,
            selectedItem.item,
            selectedItem.label or selectedItem.item,
            quantity,
            totalPrice,
            customerCitizenId,
            customerName,
            paymentMethod
        })

        AddLocksmithLog('shop_order_created', ('Order %s created for %sx %s; society deposit $%s'):format(orderId, quantity, selectedItem.item, societyDeposit), src)
        Notify(src, T('label_locksmith'), T('success_locksmith_shop_order_created', { quantity = quantity, item = selectedItem.label or selectedItem.item }), 'success')
        NotifyOnlineLocksmithEmployees('info_locksmith_shop_order_waiting', { customer = customerName, item = selectedItem.label or selectedItem.item }, true)
        RefreshLocksmithBusinessForStaff()
        return
    end

    if shopStockRequired and not ConsumeLocksmithStock(stockRequirement, shopLocationName) then
        Notify(src, T('label_locksmith'), T('error_locksmith_stock_missing'), 'error')
        return
    end

    Bridge.AddInventoryItem(src, selectedItem.item, quantity)
    local societyDeposit = 0
    if business and business.SocietyDeposits == true and totalPrice > 0 then
        local account = GetLocksmithSocietyAccount((shopProfile and shopProfile.jobName) or src)
        if Bridge.AddSocietyMoney(account, totalPrice) then
            societyDeposit = totalPrice
        elseif Config.DebugMode then
            print(('^5[ParTay Keys Debug]^3 Locksmith shop society deposit failed account=%s amount=%s^0'):format(tostring(account), tostring(totalPrice)))
        end
    end
    AddLocksmithLog('shop_purchase', ('Purchased %sx %s for $%s; society deposit $%s'):format(quantity, selectedItem.item, totalPrice, societyDeposit), src)
    Notify(src, T('label_locksmith'), T('success_shop_purchase', { quantity = quantity, item = selectedItem.label or selectedItem.item }), 'success')
end)

RegisterNetEvent('partay_keys:server:FillLocksmithShopOrder', function(orderId)
    local src = source
    if not IsPlayerLocksmithEmployee(src) and not IsPlayerLocksmithOwner(src) then
        Notify(src, T('label_locksmith'), T('error_locksmith_employee_required'), 'error')
        return
    end

    orderId = tostring(orderId or '')
    if orderId == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_order_unavailable'), 'error')
        return
    end

    local rows = MySQL.Sync.fetchAll([[
        SELECT order_id, location_name, item_name, label, quantity, total, status, customer_id, customer_name
        FROM partay_locksmith_shop_orders
        WHERE order_id = ? LIMIT 1
    ]], { orderId }) or {}
    local row = rows[1]
    if not row or row.status ~= 'pending' then
        Notify(src, T('label_locksmith'), T('error_locksmith_order_unavailable'), 'error')
        return
    end

    local business = GetLocksmithBusinessConfig()
    local quantity = math.max(1, tonumber(row.quantity) or 1)
    local shopStockRequired = business and business.ConsumeStockForShop == true and HasLocksmithRecipeForItem(row.item_name)
    if shopStockRequired and not ConsumeLocksmithStock({ { item = row.item_name, amount = quantity } }, row.location_name) then
        Notify(src, T('label_locksmith'), T('error_locksmith_stock_missing'), 'error')
        return
    end

    local pickupCoords = BuildLocksmithShopOrderPickupCoords(src, row.location_name)
    if not pickupCoords then
        Notify(src, T('label_locksmith'), T('error_locksmith_stock_location_missing'), 'error')
        return
    end

    local employeeCitizenId = Bridge.GetCitizenID(src)
    local employeeName = Bridge.GetCharacterName and Bridge.GetCharacterName(src) or GetPlayerName(src)
    MySQL.Sync.execute([[
        UPDATE partay_locksmith_shop_orders
        SET status = 'filled', employee_id = ?, employee_name = ?, pickup_coords = ?, updated_at = CURRENT_TIMESTAMP
        WHERE order_id = ? AND status = 'pending'
    ]], {
        employeeCitizenId,
        employeeName,
        EncodeStockPickupCoords(pickupCoords),
        orderId
    })

    local order = DecodeLocksmithShopOrder({
        order_id = row.order_id,
        location_name = row.location_name,
        item_name = row.item_name,
        label = row.label,
        quantity = quantity,
        total = row.total,
        status = 'filled',
        customer_id = row.customer_id,
        customer_name = row.customer_name,
        employee_id = employeeCitizenId,
        employee_name = employeeName,
        pickup_coords = EncodeStockPickupCoords(pickupCoords)
    })

    AddLocksmithLog('shop_order_filled', ('Order %s filled by %s'):format(orderId, employeeName), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_shop_order_filled', { order = orderId }), 'success')
    local customerSrc = FindOnlinePlayerByCitizenId(row.customer_id)
    if customerSrc then
        TriggerClientEvent('partay_keys:client:CreateLocksmithShopPickup', customerSrc, order)
        SendLocksmithPhoneMessage(customerSrc, T('info_locksmith_shop_order_ready'), {
            audience = 'customer',
            event = 'shop_order_ready',
            orderId = orderId,
            item = row.item_name,
            label = row.label,
            quantity = quantity,
            locationName = row.location_name
        })
        if ShouldSendLocksmithFallbackNotify() then
            Notify(customerSrc, T('label_locksmith'), T('info_locksmith_shop_order_ready'), 'info')
        end
    end
    RefreshLocksmithBusinessForStaff()
end)

function PartayKeys_CollectLocksmithShopOrder(src, orderId)
    local citizenId = Bridge.GetCitizenID(src)
    orderId = tostring(orderId or '')
    if not citizenId or orderId == '' then
        Notify(src, T('label_locksmith'), T('error_locksmith_order_unavailable'), 'error')
        return { ok = false, reason = 'invalid' }
    end
    citizenId = tostring(citizenId)

    if ActiveLocksmithShopOrderCollections[orderId] then
        Notify(src, T('label_locksmith'), T('error_locksmith_order_unavailable'), 'error')
        return { ok = false, reason = 'busy' }
    end
    ActiveLocksmithShopOrderCollections[orderId] = true

    local rows = MySQL.Sync.fetchAll([[
        SELECT order_id, item_name, label, quantity, status, customer_id
        FROM partay_locksmith_shop_orders
        WHERE order_id = ? LIMIT 1
    ]], { orderId }) or {}
    local row = rows[1]
    local rowCustomerId = row and row.customer_id and tostring(row.customer_id) or nil
    if row and row.status == 'collected' and rowCustomerId == citizenId then
        ActiveLocksmithShopOrderCollections[orderId] = nil
        return { ok = true, alreadyCollected = true }
    end

    if not row or row.status ~= 'filled' or rowCustomerId ~= citizenId then
        ActiveLocksmithShopOrderCollections[orderId] = nil
        Notify(src, T('label_locksmith'), T('error_locksmith_order_unavailable'), 'error')
        return { ok = false, reason = 'unavailable' }
    end

    local quantity = math.max(1, tonumber(row.quantity) or 1)
    if not Bridge.AddInventoryItem(src, row.item_name, quantity) then
        ActiveLocksmithShopOrderCollections[orderId] = nil
        Notify(src, T('label_locksmith'), T('error_inventory_add_failed'), 'error')
        return { ok = false, reason = 'inventory' }
    end

    MySQL.Sync.execute([[
        UPDATE partay_locksmith_shop_orders
        SET status = 'collected', updated_at = CURRENT_TIMESTAMP
        WHERE order_id = ? AND status = 'filled'
    ]], { orderId })

    AddLocksmithLog('shop_order_collected', ('Order %s collected'):format(orderId), src)
    Notify(src, T('label_locksmith'), T('success_locksmith_shop_order_collected', { quantity = quantity, item = row.label or row.item_name }), 'success')
    RefreshLocksmithBusinessForStaff()
    ActiveLocksmithShopOrderCollections[orderId] = nil
    return { ok = true }
end

lib.callback.register('partay_keys:server:CollectLocksmithShopOrder', function(src, orderId)
    return PartayKeys_CollectLocksmithShopOrder(src, orderId)
end)

RegisterNetEvent('partay_keys:server:CollectLocksmithShopOrder', function(orderId)
    PartayKeys_CollectLocksmithShopOrder(source, orderId)
end)

RegisterNetEvent('partay_keys:server:ProposeSale', function(targetId, plate, price, netId)
    local src = source
    targetId = tonumber(targetId)
    price = tonumber(price)

    if not targetId or not plate or not price or price < 1 then
        Notify(src, T('label_blackmarket'), T('error_invalid_sale_contract'), 'error')
        return
    end

    local sellerPed = GetPlayerPed(src)
    local buyerPed = GetPlayerPed(targetId)
    if not sellerPed or sellerPed == 0 or not buyerPed or buyerPed == 0 then
        Notify(src, T('label_blackmarket'), T('error_buyer_not_nearby'), 'error')
        return
    end
    if #(GetEntityCoords(sellerPed) - GetEntityCoords(buyerPed)) > (Config.Heist.MaxSaleDistance or 5.0) + 1.0 then
        Notify(src, T('label_blackmarket'), T('error_buyer_too_far'), 'error')
        return
    end

    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or GetPlayerDistanceToEntity(src, veh) > (Config.Heist.MaxSaleDistance or 5.0) + 2.0 then
        Notify(src, T('label_blackmarket'), T('error_contract_vehicle_too_far'), 'error')
        return
    end
    if GetVehicleNumberPlateText(veh):gsub('^%s*(.-)%s*$', '%1') ~= plate:gsub('^%s*(.-)%s*$', '%1') then
        Notify(src, T('label_blackmarket'), T('error_contract_vehicle_mismatch'), 'error')
        return
    end

    local sellerCitizenId = Bridge.GetCitizenID(src)
    if not sellerCitizenId then
        Notify(src, T('label_blackmarket'), T('error_character_unavailable'), 'error')
        return
    end
    if Entity(veh).state.isStolen ~= true or Entity(veh).state.possession_id ~= sellerCitizenId then
        Notify(src, T('label_blackmarket'), T('error_contract_requires_possession'), 'error')
        return
    end

    if Config.Items.SaleContract and not Bridge.HasInventoryItem(src, Config.Items.SaleContract, 1) then
        Notify(src, T('label_blackmarket'), T('error_need_sale_contract'), 'error')
        return
    end

    if Config.Items.SaleContract and not Bridge.RemoveInventoryItem(src, Config.Items.SaleContract, 1) then
        Notify(src, T('label_blackmarket'), T('error_prepare_sale_contract'), 'error')
        return
    end

    PendingSales[targetId] = {
        seller = src,
        plate = plate,
        price = price,
        netId = netId,
        expires = os.time() + 60
    }

    TriggerClientEvent('partay_keys:client:ReceiveContract', targetId, src, plate, price)
end)

RegisterNetEvent('partay_keys:server:FinalizeSale', function(sellerId, plate)
    local src = source
    sellerId = tonumber(sellerId)
    local sale = PendingSales[src]

    if not sale or sale.seller ~= sellerId or sale.plate ~= plate or sale.expires < os.time() then
        PendingSales[src] = nil
        Notify(src, T('label_blackmarket'), T('error_sale_contract_expired'), 'error')
        return
    end

    TriggerEvent('partay_keys:server:ProcessBlackmarketSaleInternal', sale.seller, plate, src, sale.price)
    PendingSales[src] = nil
end)

local function GetInventorySource(inventory)
    if type(inventory) == 'table' then
        return inventory.id or inventory.source or inventory.owner
    end

    return inventory
end

local function DebugItemUse(message)
    if Config and Config.DebugMode then
        print(('^5[ParTay Keys Debug]^3 Item Use: %s^0'):format(tostring(message)))
    end
end

-- Ox Inventory Item Usability Hook (Opens the Fob UI)
exports('useKeyItem', function(event, item, inventory, slot, data)
    if event == 'usingItem' then
        local src = tonumber(GetInventorySource(inventory))
        local metadata = GetUsableItemMetadata(item, data, inventory, slot)
        DebugItemUse(('useKeyItem event=%s src=%s item=%s slot=%s metadataPlate=%s metadataTier=%s'):format(
            tostring(event),
            tostring(src),
            tostring(item and (item.name or item.item)),
            tostring(slot),
            tostring(metadata and metadata.plate),
            tostring(metadata and metadata.key_tier)
        ))
        WarnIfVehicleKeyMetadataMissing(src or 'unknown', metadata, 'ox export')
        if src then
            if PartayKeys_KeyTierHasCapability(PartayKeys_GetKeyTierFromMetadata(metadata, item and (item.name or item.item)), 'nui') then
                TriggerClientEvent('partay_keys:client:OpenFobUI', src, metadata, false, slot)
            else
                TriggerClientEvent('partay_keys:client:UseBasicKey', src, metadata)
            end
        end
        return false -- Don't consume the item
    end
end)

local function HandleUsableItem(itemName, event, item, inventory, slot, data)
    if event and event ~= 'usingItem' then return end

    local src = tonumber(GetInventorySource(inventory))
    if not src then return false end
    DebugItemUse(('HandleUsableItem event=%s src=%s itemName=%s rawItem=%s slot=%s dataName=%s'):format(
        tostring(event),
        tostring(src),
        tostring(itemName),
        tostring(item and (item.name or item.item)),
        tostring(slot),
        tostring(data and (data.name or data.item))
    ))

    if PartayKeys_IsKeyItem(itemName) then
        local metadata = GetUsableItemMetadata(item, data, inventory, slot)
        metadata.key_tier = PartayKeys_GetKeyTierFromMetadata(metadata, itemName)
        DebugItemUse(('Key item route src=%s itemName=%s slot=%s plate=%s tier=%s hasNui=%s'):format(
            tostring(src),
            tostring(itemName),
            tostring(slot),
            tostring(metadata and metadata.plate),
            tostring(metadata and metadata.key_tier),
            tostring(PartayKeys_KeyTierHasCapability(metadata.key_tier, 'nui'))
        ))
        WarnIfVehicleKeyMetadataMissing(src, metadata, 'framework usable item')
        if PartayKeys_KeyTierHasCapability(metadata.key_tier, 'nui') then
            TriggerClientEvent('partay_keys:client:OpenFobUI', src, metadata, false, slot)
        else
            TriggerClientEvent('partay_keys:client:UseBasicKey', src, metadata)
        end
        return false
    end

    if itemName == Config.Items.Lockpick or itemName == Config.Items.WiringKit or itemName == Config.Items.ElectronicDecoder or itemName == Config.Items.BlankKey or itemName == Config.Items.SaleContract then
        TriggerClientEvent('partay_keys:client:UseHeistItem', src, itemName)
        return false
    end

    if PartayKeys_IsAlarmItem(itemName) or PartayKeys_IsGpsTrackerItem(itemName) or itemName == Config.Items.AlarmRemovalTool or itemName == Config.Items.ValetModule or itemName == PartayKeys_GetGpsTabletItem() or itemName == PartayKeys_GetSignalFinderItem() then
        TriggerClientEvent('partay_keys:client:UseSecurityItem', src, itemName, slot)
        return false
    end

    if itemName == Config.Items.LocksmithEmployeeTablet or itemName == Config.Items.LocksmithOwnerTablet then
        TriggerClientEvent('partay_keys:client:UseLocksmithTabletItem', src, itemName, slot)
        return false
    end

    return false
end

exports('usePartayItem', function(event, item, inventory, slot, data)
    local itemName = item and (item.name or item.item) or data and (data.name or data.item)
    return HandleUsableItem(itemName, event, item, inventory, slot, data)
end)

exports('useBasicVehicleKeyItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.BasicVehicleKey, event, item, inventory, slot, data)
end)

exports('useSmartVehicleKeyItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.SmartVehicleKey, event, item, inventory, slot, data)
end)

exports('useAdvancedSmartVehicleKeyItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.AdvancedSmartVehicleKey, event, item, inventory, slot, data)
end)

exports('useOLEDVehicleKeyItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.OLEDVehicleKey, event, item, inventory, slot, data)
end)

exports('useLockpickItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.Lockpick, event, item, inventory, slot, data)
end)

exports('useHotwireItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.WiringKit, event, item, inventory, slot, data)
end)

exports('useDecoderItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.ElectronicDecoder, event, item, inventory, slot, data)
end)

exports('useBlankKeyItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.BlankKey, event, item, inventory, slot, data)
end)

exports('useSaleContractItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.SaleContract, event, item, inventory, slot, data)
end)

exports('useCarAlarmItem', function(event, item, inventory, slot, data)
    local itemName = item and (item.name or item.item) or data and (data.name or data.item) or PartayKeys_GetAlarmItem()
    return HandleUsableItem(itemName, event, item, inventory, slot, data)
end)

exports('useAlarmRemovalToolItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.AlarmRemovalTool, event, item, inventory, slot, data)
end)

exports('useGpsTrackerItem', function(event, item, inventory, slot, data)
    local itemName = item and (item.name or item.item) or data and (data.name or data.item) or PartayKeys_GetGpsTrackerItem()
    return HandleUsableItem(itemName, event, item, inventory, slot, data)
end)

exports('useGpsTabletItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(PartayKeys_GetGpsTabletItem(), event, item, inventory, slot, data)
end)

exports('useSignalFinderItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(PartayKeys_GetSignalFinderItem(), event, item, inventory, slot, data)
end)

exports('useValetModuleItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.ValetModule, event, item, inventory, slot, data)
end)

exports('useLocksmithEmployeeTabletItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.LocksmithEmployeeTablet, event, item, inventory, slot, data)
end)

exports('useLocksmithOwnerTabletItem', function(event, item, inventory, slot, data)
    return HandleUsableItem(Config.Items.LocksmithOwnerTablet, event, item, inventory, slot, data)
end)

local function RegisterFrameworkUsable(itemName)
    if not itemName or itemName == '' then return end

    local function handler(src, item)
        HandleUsableItem(itemName, 'usingItem', item or { name = itemName }, { id = src })
    end

    if GetResourceState('qbx_core') == 'started' then
        pcall(function()
            exports.qbx_core:CreateUseableItem(itemName, handler)
        end)
    elseif GetResourceState('qb-core') == 'started' then
        pcall(function()
            local core = exports['qb-core']:GetCoreObject()
            if core and core.Functions and core.Functions.CreateUseableItem then
                core.Functions.CreateUseableItem(itemName, handler)
            end
        end)
    end
end

CreateThread(function()
    Wait(1000)
    for _, keyItem in ipairs(PartayKeys_GetAllKeyItems()) do
        RegisterFrameworkUsable(keyItem)
    end
    RegisterFrameworkUsable(Config.Items.Lockpick)
    RegisterFrameworkUsable(Config.Items.WiringKit)
    RegisterFrameworkUsable(Config.Items.ElectronicDecoder)
    RegisterFrameworkUsable(Config.Items.BlankKey)
    RegisterFrameworkUsable(Config.Items.SaleContract)
    for _, alarmItem in ipairs(PartayKeys_GetAllAlarmItems()) do
        RegisterFrameworkUsable(alarmItem)
    end
    RegisterFrameworkUsable(Config.Items.AlarmRemovalTool)
    for _, trackerItem in ipairs(PartayKeys_GetAllGpsTrackerItems()) do
        RegisterFrameworkUsable(trackerItem)
    end
    RegisterFrameworkUsable(PartayKeys_GetGpsTabletItem())
    RegisterFrameworkUsable(PartayKeys_GetSignalFinderItem())
    RegisterFrameworkUsable(Config.Items.ValetModule)
    RegisterFrameworkUsable(Config.Items.LocksmithEmployeeTablet)
    RegisterFrameworkUsable(Config.Items.LocksmithOwnerTablet)
end)

local function NormalizeVersion(version)
    version = tostring(version or ''):gsub('^%s*(.-)%s*$', '%1')
    version = version:gsub('^v', '')
    return version
end

local function ParseVersionParts(version)
    version = NormalizeVersion(version)
    local parts = {}
    for part in version:gmatch('[^.%-]+') do
        parts[#parts + 1] = tonumber(part) or 0
        if #parts >= 3 then break end
    end

    while #parts < 3 do
        parts[#parts + 1] = 0
    end

    return parts
end

local function IsRemoteVersionNewer(currentVersion, remoteVersion)
    local current = ParseVersionParts(currentVersion)
    local remote = ParseVersionParts(remoteVersion)

    for index = 1, 3 do
        if remote[index] > current[index] then return true end
        if remote[index] < current[index] then return false end
    end

    return false
end

local function ParseVersionCheckResponse(body)
    body = tostring(body or ''):gsub('^%s*(.-)%s*$', '%1')
    body = body:gsub('^\239\187\191', '')
    if body == '' then return nil, nil end

    local ok, decoded = pcall(json.decode, body)
    if ok and type(decoded) == 'table' then
        return NormalizeVersion(decoded.version or decoded.latest or decoded.tag_name), decoded.url or decoded.html_url or decoded.release_url
    end

    local manifestVersion = body:match("version%s+['\"]([^'\"]+)['\"]")
    if manifestVersion then
        return NormalizeVersion(manifestVersion), VERSION_CHECK_PROJECT_URL
    end

    local firstLine = body:match('([^\r\n]+)')
    return NormalizeVersion(firstLine), nil
end

local function RunVersionCheck()
    if VERSION_CHECK_URL == '' then return end

    local currentVersion = VERSION_CHECK_CURRENT_VERSION
    PerformHttpRequest(VERSION_CHECK_URL, function(statusCode, body)
        if statusCode ~= 200 then
            if Config.DebugMode then
                print(('^5[ParTay Keys Debug]^3 Version check failed with status %s.^0'):format(tostring(statusCode)))
            end
            return
        end

        local remoteVersion, remoteUrl = ParseVersionCheckResponse(body)
        if not remoteVersion or remoteVersion == '' then
            if Config.DebugMode then
                print('^5[ParTay Keys Debug]^3 Version check response did not contain a version.^0')
            end
            return
        end

        if IsRemoteVersionNewer(currentVersion, remoteVersion) then
            print(('^5[ParTay Keys v%s]^3 Update available: ^2%s^3 is now available.^0'):format(tostring(currentVersion), tostring(remoteVersion)))
            local projectUrl = remoteUrl or VERSION_CHECK_PROJECT_URL
            if projectUrl and projectUrl ~= '' then
                print(('^5[ParTay Keys]^0 Download: ^3%s^0'):format(projectUrl))
            end
        elseif Config.DebugMode then
            print(('^5[ParTay Keys Debug]^2 Version check OK: running %s, latest %s.^0'):format(tostring(currentVersion), tostring(remoteVersion)))
        end
    end, 'GET', '', {
        ['User-Agent'] = 'partay_keys/version-check'
    })
end

-- [[ Ecosystem Initialization & Debug Readout ]] --
CreateThread(function()
    Wait(2000) -- Wait a brief moment to ensure all external resources have fully mounted
    local dependencyStates = {
        ox_lib = GetResourceState('ox_lib'),
        oxmysql = GetResourceState('oxmysql'),
        ox_target = GetResourceState('ox_target')
    }
    local framework = 'Standalone / Unknown'
    if GetResourceState('es_extended') == 'started' then framework = 'ESX'
    elseif GetResourceState('qbx_core') == 'started' then framework = 'QBX'
    elseif GetResourceState('qb-core') == 'started' then framework = 'QB-Core' end

    local inventory = 'Standalone / Unknown'
    if GetResourceState('ox_inventory') == 'started' then inventory = 'OX'
    elseif GetResourceState('qb-inventory') == 'started' then inventory = 'QB'
    elseif GetResourceState('qs-inventory') == 'started' then inventory = 'QS' end

    local garageProvider = GetGarageProvider and GetGarageProvider() or 'unknown'
    local dealershipProvider = GetDealershipProvider and GetDealershipProvider() or 'unknown'
    local dispatchProvider = PartayKeys_GetDispatchProvider and PartayKeys_GetDispatchProvider() or 'unknown'
    local hasDependencyIssue = false
    for _, state in pairs(dependencyStates) do
        if state ~= 'started' then
            hasDependencyIssue = true
            break
        end
    end

    print('^5====================================================^0')
    print('^5[ParTay Keys v1.0.0] ^2Ecosystem Initialized^0')
    print('^5[ParTay Keys v1.0.0] ^0Framework Detected: ^3' .. framework .. '^0')
    print('^5[ParTay Keys v1.0.0] ^0Inventory Detected: ^3' .. inventory .. '^0')
    print('^5[ParTay Keys v1.0.0] ^0Garage Provider: ^3' .. tostring(garageProvider) .. '^0')
    print('^5[ParTay Keys v1.0.0] ^0Dealership Provider: ^3' .. tostring(dealershipProvider ~= '' and dealershipProvider or 'none') .. '^0')
    print('^5[ParTay Keys v1.0.0] ^0Police Dispatch Provider: ^3' .. tostring(dispatchProvider ~= '' and dispatchProvider or 'none') .. '^0')
    print('^5[ParTay Keys v1.0.0] ^0Notification Engine: ^3' .. ((Config.Notifications and Config.Notifications.Provider) or Config.NotificationType or 'ox_lib') .. '^0')
    print('^5[ParTay Keys v1.0.0] ^0Minigame Engine: ^3' .. ((Config.Minigames and Config.Minigames.Provider) or Config.MinigameType or 'ox_lib') .. '^0')
    print('^5[ParTay Keys v1.0.0] ^0Physical Keys Required: ^3' .. tostring(Config.RequirePhysicalKey) .. '^0')
    print('^5[ParTay Keys v1.0.0] ^0Debug Mode: ^3' .. tostring(Config.DebugMode == true) .. '^0')
    if hasDependencyIssue then
        print(('^5[ParTay Keys v1.0.0] ^0Dependency States: ^3ox_lib=%s oxmysql=%s ox_target=%s^0'):format(
            dependencyStates.ox_lib,
            dependencyStates.oxmysql,
            dependencyStates.ox_target
        ))
    end
    print('^5====================================================^0')

    for resourceName, state in pairs(dependencyStates) do
        if state ~= 'started' then
            exports.partay_keys:SendAuditLog('ERR_DEPENDENCY_MISSING', ('Required dependency %s is %s. Resource behavior may be incomplete.'):format(resourceName, tostring(state)), 'error')
        end
    end

    if Bridge and Bridge.InventorySupportsMetadata and not Bridge.InventorySupportsMetadata() then
        WarnMetadata(('Detected inventory "%s" does not support metadata vehicle keys. Physical key items require metadata; access records will remain in the database, but key item actions may be unavailable.'):format(tostring(Bridge.GetInventory and Bridge.GetInventory() or 'unknown')))
    end

    RunVersionCheck()
end)
