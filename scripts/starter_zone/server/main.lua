local function dbg(...)
    if Config.Debug then print('[starter_zone]', ...) end
end

local actionLocks = {}

local function withActionLock(src, key, cb)
    src = tonumber(src)
    if not src then return false, 'Starter action could not identify your player session. Please reconnect if this continues.' end

    local lockKey = ('%s:%s'):format(src, key)
    if actionLocks[lockKey] then
        return false, 'Please wait for your current starter action to finish before trying again.'
    end

    actionLocks[lockKey] = true
    local results = { pcall(cb) }
    actionLocks[lockKey] = nil

    if not results[1] then
        print(('[starter_zone] %s failed for %s: %s'):format(key, src, results[2]))
        return false, 'Starter action failed unexpectedly. Please try again once, then open a Discord ticket if it continues.'
    end

    return table.unpack(results, 2)
end

local function getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function hasFrameworkPermission(src)
    src = tonumber(src) or 0
    if src == 0 then return true end

    for _, permission in ipairs(Config.AdminPermissions or {}) do
        local qbxOk, qbxAllowed = pcall(function()
            return exports.qbx_core:HasPermission(src, permission)
        end)
        if qbxOk and qbxAllowed then return true end

        local qbOk, qbAllowed = pcall(function()
            local core = exports.qbx_core:GetCoreObject()
            return core and core.Functions and core.Functions.HasPermission(src, permission)
        end)
        if qbOk and qbAllowed then return true end
    end

    return false
end

local function requireAdmin(src)
    if hasFrameworkPermission(src) then return true end
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'No Love Lost',
        description = 'You do not have permission to use this starter admin command.',
        type = 'error',
        position = 'top'
    })
    return false
end

local function notify(src, description, notifyType)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'No Love Lost',
        description = description,
        type = notifyType or 'inform',
        position = 'top'
    })
end

local function canCarryInventoryItem(src, item, amount)
    local ok, result = pcall(function()
        return exports.ox_inventory:CanCarryItem(src, item, amount)
    end)

    if ok then return result == true end

    -- Some ox_inventory builds do not expose CanCarryItem. AddItem still validates capacity.
    if Config.Debug then
        print(('[starter_zone] ox_inventory CanCarryItem unavailable, falling back to AddItem validation: %s'):format(result))
    end

    return true
end

local function addInventoryItem(src, item, amount, metadata)
    local ok, result = pcall(function()
        return exports.ox_inventory:AddItem(src, item, amount, metadata)
    end)

    return ok and result ~= false, result
end

local function removeInventoryItem(src, item, amount, metadata)
    local ok, result = pcall(function()
        return exports.ox_inventory:RemoveItem(src, item, amount, metadata)
    end)

    return ok and result ~= false
end

local function rollbackInventoryItems(src, items)
    for i = #items, 1, -1 do
        local data = items[i]
        removeInventoryItem(src, data.item, data.amount, data.metadata)
    end
end

local function setPlayerJob(Player, jobName, grade)
    local ok, result = pcall(function()
        return Player.Functions.SetJob(jobName, grade)
    end)

    return ok and result ~= false
end

local function defaultStarter()
    return {
        released = false,
        playtime = 0,
        bikeRideDistance = 0.0,
        lastBikeRideUpdate = 0,
        lastBikeRideCoords = nil,
        lastStarterVehiclePlate = nil,
        lastStarterVehicleModel = nil,
        pendingStarterVehicleSpawn = false,
        lastPlaytimeTick = os.time(),
        claimedStarterKit = false,
        bonusClaimed = false,
        bonusItem = nil,
        firstShiftJob = nil,
        selectedStarterJob = nil,
        claimedStarterJobItems = false,
        forceIdReplacement = false,
        tasks = {
            identity = true, -- multichar/appearance already completed before starter zone
            id_card = false,
            starter_kit = false,
            starter_job = false,
            first_shift = false,
            bike_ride = false
        }
    }
end

local function mergeStarter(existing)
    local starter = existing or {}
    local def = defaultStarter()
    starter.released = starter.released or false
    starter.playtime = starter.playtime or 0
    starter.bikeRideDistance = tonumber(starter.bikeRideDistance) or 0.0
    starter.lastBikeRideUpdate = tonumber(starter.lastBikeRideUpdate) or 0
    starter.lastBikeRideCoords = type(starter.lastBikeRideCoords) == 'table' and starter.lastBikeRideCoords or nil
    starter.lastStarterVehiclePlate = starter.lastStarterVehiclePlate or nil
    starter.lastStarterVehicleModel = starter.lastStarterVehicleModel or nil
    starter.pendingStarterVehicleSpawn = starter.pendingStarterVehicleSpawn or false
    starter.lastPlaytimeTick = starter.lastPlaytimeTick or os.time()
    starter.claimedStarterKit = starter.claimedStarterKit or false
    starter.bonusClaimed = starter.bonusClaimed or false
    starter.bonusItem = starter.bonusItem or nil
    starter.firstShiftJob = starter.firstShiftJob or nil
    starter.selectedStarterJob = starter.selectedStarterJob or nil
    starter.claimedStarterJobItems = starter.claimedStarterJobItems or false
    starter.forceIdReplacement = starter.forceIdReplacement or false
    starter.tasks = starter.tasks or {}
    for k, v in pairs(def.tasks) do
        if starter.tasks[k] == nil then starter.tasks[k] = v end
    end
    return starter
end

local function getBikeRideRequiredMeters()
    local miles = Config.BikeRide and Config.BikeRide.milesRequired or 10.0
    return miles * 1609.344
end

local function isRideVehicleAllowed(model)
    if not Config.BikeRide or type(Config.BikeRide.vehicles) ~= 'table' then return false end

    local modelHash = type(model) == 'number' and model or joaat(model)
    for _, vehicleModel in ipairs(Config.BikeRide.vehicles) do
        if modelHash == joaat(vehicleModel) then
            return true
        end
    end

    return false
end

local function isPointInsidePolygon(coords, points)
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
    if not Config.Zone or not Config.Zone.enabled then return true end

    if Config.Zone.type == 'north_line' then
        local boundary = Config.Zone.northBoundary or {}
        return isSouthOfLine(coords, boundary.west, boundary.east)
    end

    if Config.Zone.type == 'polygon' then
        return isPointInsidePolygon(coords, Config.Zone.points)
    end

    return #(coords - Config.Zone.center) <= Config.Zone.radius
end

local function getStarter(src)
    local Player = getPlayer(src)
    if not Player then return nil, nil end
    local starter = mergeStarter(Player.PlayerData.metadata[Config.MetadataKey])
    return Player, starter
end

local function saveStarter(Player, starter)
    Player.Functions.SetMetaData(Config.MetadataKey, starter)
end

local function hasCsLicense(src, item)
    if GetResourceState(Config.License.resource) ~= 'started' then
        return false
    end
    local ok, result = pcall(function()
        return exports[Config.License.resource]:CheckID(src, item)
    end)
    return ok and result == true
end

local function getCharacterName(Player, src)
    local charinfo = Player.PlayerData.charinfo
    if charinfo then
        local fullName = ('%s %s'):format(charinfo.firstname or '', charinfo.lastname or ''):gsub('^%s*(.-)%s*$', '%1')
        if fullName ~= '' then return fullName end
    end
    return GetPlayerName(src)
end

local function normalizeGender(gender)
    if gender == nil then return nil end
    local value = type(gender) == 'string' and gender:lower() or gender

    if value == 0 or value == '0' or value == 'm' or value == 'male' then return 'male' end
    if value == 1 or value == '1' or value == 'f' or value == 'female' then return 'female' end
end

local function getAppearanceGender(citizenid)
    if GetResourceState('illenium-appearance') ~= 'started' then return nil end

    local ok, row = pcall(function()
        return MySQL.single.await('SELECT model, skin FROM playerskins WHERE citizenid = ? AND active = 1 LIMIT 1', { citizenid })
    end)
    if not ok or not row then return nil end

    local model = row.model
    if (not model or model == '') and row.skin then
        local decoded = json.decode(row.skin)
        model = decoded and decoded.model
    end

    if type(model) ~= 'string' then return nil end
    model = model:lower()
    if model:find('mp_m_freemode_01', 1, true) then return 'male' end
    if model:find('mp_f_freemode_01', 1, true) then return 'female' end
end

local function getStarterProfile(Player)
    local fallbackKey = Config.StarterKit.fallbackProfile or 'default'
    local profiles = Config.StarterKit.profiles or {}
    local charinfo = Player.PlayerData.charinfo or {}
    local gender = normalizeGender(charinfo.gender) or getAppearanceGender(Player.PlayerData.citizenid) or fallbackKey
    local profileKey = profiles[gender] and gender or fallbackKey
    local profile = profiles[profileKey] or {}

    return profileKey, profile
end

local function getStarterKitPayload(Player)
    local profileKey, profile = getStarterProfile(Player)
    local maxChoices = profile.maxChoices or 6
    local items = {}
    local vehicles = {}
    local bonus = nil

    for _, data in ipairs(profile.items or {}) do
        items[#items + 1] = {
            item = data.item,
            label = data.label or data.item,
            cost = data.cost or 0,
            maxQuantity = data.maxQuantity or maxChoices,
            amount = data.amount or 1,
            image = ('nui://ox_inventory/web/images/%s.png'):format(data.item)
        }
    end

    if Config.StarterKit.allowVehicle then
        for _, data in ipairs(profile.vehicles or {}) do
            vehicles[#vehicles + 1] = {
                model = data.model,
                label = data.label or data.model,
                cost = data.cost or 0,
                countsAsChoices = data.countsAsChoices or 1
            }
        end
    end

    if profile.bonus and profile.bonus.enabled then
        local bonusItems = {}
        for _, data in ipairs(profile.bonus.items or {}) do
            bonusItems[#bonusItems + 1] = {
                item = data.item,
                label = data.label or data.item,
                amount = data.amount or 1,
                image = ('nui://ox_inventory/web/images/%s.png'):format(data.item)
            }
        end

        bonus = {
            enabled = #bonusItems > 0,
            label = profile.bonus.label or 'Welcome Bonus',
            items = bonusItems
        }
    end

    return {
        profile = profileKey,
        label = profile.label or 'Starter Pack',
        theme = profile.theme or (profileKey == 'female' and 'female' or 'default'),
        budget = profile.budget or 0,
        maxChoices = maxChoices,
        items = items,
        vehicles = vehicles,
        bonus = bonus,
        requiredItem = Config.StarterKit.requiredItem,
        requiredItemLabel = Config.StarterKit.requiredItemLabel or Config.StarterKit.requiredItem
    }
end

local function getStatus(src)
    local Player, starter = getStarter(src)
    if not Player then return nil end
    local dirty = false

    -- Auto-sync ID task from cs_license if already registered, unless admin reset requires a fresh replacement flow.
    if Config.Requirements.requireIdCard and not starter.forceIdReplacement and hasCsLicense(src, Config.License.idCardItem) then
        if starter.tasks.id_card ~= true then
            starter.tasks.id_card = true
            dirty = true
        end
    end

    local bank = Player.Functions.GetMoney('bank') or 0
    local job = Player.PlayerData.job and Player.PlayerData.job.name or 'unemployed'

    if Config.AllowedStarterJobs[job] and Config.AllowedStarterJobs[job].locked ~= true and starter.tasks.starter_job ~= true then
        starter.tasks.starter_job = true
        dirty = true
    end

    if (starter.bikeRideDistance or 0.0) >= getBikeRideRequiredMeters() and starter.tasks.bike_ride ~= true then
        starter.tasks.bike_ride = true
        dirty = true
    end

    if dirty then
        saveStarter(Player, starter)
    end

    local checks = {
        identity = not Config.Requirements.requireIdentityEstablished or starter.tasks.identity == true,
        id_card = not Config.Requirements.requireIdCard or starter.tasks.id_card == true,
        starter_kit = not Config.Requirements.requireStarterKit or starter.tasks.starter_kit == true,
        starter_job = not Config.Requirements.requireStarterJob or starter.tasks.starter_job == true,
        bike_ride = not Config.Requirements.requireBikeRide or starter.tasks.bike_ride == true,
        bank = bank >= Config.Requirements.bank,
        playtime = (starter.playtime or 0) >= (Config.Requirements.playtimeMinutes * 60)
    }

    local tasksComplete = true
    for _, passed in pairs(checks) do
        if not passed then tasksComplete = false break end
    end

    local adminBypass = Config.AdminBypassStarterClearance == true and hasFrameworkPermission(src) == true

    return {
        starter = starter,
        checks = checks,
        canLeave = tasksComplete or starter.released == true or adminBypass,
        tasksComplete = tasksComplete,
        adminBypass = adminBypass,
        bank = bank,
        requiredBank = Config.Requirements.bank,
        playtime = starter.playtime or 0,
        requiredPlaytime = Config.Requirements.playtimeMinutes * 60,
        bikeRideDistance = starter.bikeRideDistance or 0.0,
        requiredBikeRideDistance = getBikeRideRequiredMeters(),
        bikeRideMilesRequired = Config.BikeRide and Config.BikeRide.milesRequired or 10.0,
        job = job,
        playerName = getCharacterName(Player, src),
        playerId = src,
        starterKit = getStarterKitPayload(Player),
        released = starter.released == true
    }
end

lib.callback.register('starter_zone:getStatus', function(source)
    return getStatus(source)
end)

lib.callback.register('starter_zone:canLeave', function(source)
    local status = getStatus(source)
    return status and status.canLeave == true, status
end)

lib.callback.register('starter_zone:markReleased', function(source)
    return withActionLock(source, 'markReleased', function()
    local Player, starter = getStarter(source)
    if not Player then return false, 'Your character data could not be found. Please reconnect or contact staff if this continues.' end
    if starter.released then return true, 'Starter clearance is already complete for this character.' end

    local status = getStatus(source)
    if not status or not status.canLeave then
        return false, 'You are not cleared to leave yet. Finish every required checklist item before leaving the city.'
    end

    if status.adminBypass and not status.tasksComplete then
        return true, 'Admin starter clearance bypass is active for this character.'
    end

    starter.released = true
    saveStarter(Player, starter)
    return true, 'New citizen clearance complete. You may now leave the city.'
    end)
end)

local function removeMoney(Player, account, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end

    local current = Player.Functions.GetMoney(account) or 0
    if current < amount then return false end

    local ok, result = pcall(function()
        return Player.Functions.RemoveMoney(account, amount, reason or 'starter-zone-payment')
    end)

    -- Some framework versions do not return true/false from RemoveMoney.
    if ok and result ~= false then return true end
    return false
end

local function formatLicenseDate(timestamp)
    return os.date('%B %d, %Y', timestamp or os.time())
end

local function getLicenseDates(expireDays)
    local issueDate = formatLicenseDate(os.time())
    local expireDate = false

    expireDays = tonumber(expireDays)
    if expireDays and expireDays > 0 then
        expireDate = formatLicenseDate(os.time() + (expireDays * 86400))
    end

    return issueDate, expireDate
end

local function decodeLicenseList(rawLicenses)
    if type(rawLicenses) ~= 'string' or rawLicenses == '' then return {} end

    local ok, decoded = pcall(json.decode, rawLicenses)
    if not ok or type(decoded) ~= 'table' then return {} end

    return decoded
end

local function getCsLicenseRow(identifier)
    if not identifier then return nil end

    local ok, row = pcall(function()
        return MySQL.single.await('SELECT identifier, playerName, licenses FROM license_granted WHERE identifier = ? LIMIT 1', { identifier })
    end)

    if ok then return row end

    if Config.Debug then
        print(('[starter_zone] Could not read cs_license row for %s: %s'):format(identifier, row))
    end
end

local function upsertCsLicenseRow(identifier, playerName, licenses)
    local encoded = json.encode(licenses or {})
    local ok, result = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO license_granted (identifier, playerName, licenses)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE playerName = VALUES(playerName), licenses = VALUES(licenses)
        ]], { identifier, playerName, encoded })
    end)

    return ok and result ~= false, result
end

local function addCsLicenseItem(src, Player, item, issueDate, expireDate)
    if Config.License.addItem ~= true then return true end
    if GetResourceState('ox_inventory') ~= 'started' then return true end

    local charinfo = Player.PlayerData.charinfo or {}
    local metadata = {
        checkCard = 'codestudio',
        license = item,
        isPublic = true,
        firstname = charinfo.firstname,
        lastname = charinfo.lastname,
        birthdate = charinfo.birthdate,
        gender = normalizeGender(charinfo.gender) or charinfo.gender,
        nationality = charinfo.nationality,
        citizenid = Player.PlayerData.citizenid,
        issueDate = issueDate,
        expireDate = expireDate,
        description = ('Name: %s'):format(getCharacterName(Player, src))
    }

    local ok, result = pcall(function()
        return exports.ox_inventory:AddItem(src, item, 1, metadata)
    end)

    return ok and result ~= false
end

local function mergeCsLicense(src, Player, item, expireDays, addItem)
    local identifier = Player.PlayerData.citizenid
    if not identifier then return false, 'Your character ID could not be found.' end

    local row = getCsLicenseRow(identifier)
    local licenses = decodeLicenseList(row and row.licenses)
    local issueDate, expireDate = getLicenseDates(expireDays)
    local found = false

    for _, licenseData in ipairs(licenses) do
        if type(licenseData) == 'table' and licenseData.license == item then
            licenseData.isPublic = true
            licenseData.issueDate = licenseData.issueDate or issueDate
            licenseData.expireDate = expireDate
            found = true
            break
        end
    end

    if not found then
        licenses[#licenses + 1] = {
            isPublic = true,
            expireDate = expireDate,
            license = item,
            issueDate = issueDate
        }
    end

    local saved, err = upsertCsLicenseRow(identifier, getCharacterName(Player, src), licenses)
    if not saved then
        print(('[starter_zone] Failed to merge cs_license %s for %s: %s'):format(item, identifier, err))
        return false, 'Could not update your license records. Open a Discord ticket so staff can check cs_license.'
    end

    if addItem and not addCsLicenseItem(src, Player, item, issueDate, expireDate) then
        return false, ('Your %s was registered, but the physical card could not be added to your inventory. Free up space and contact staff.'):format(item)
    end

    return true
end

lib.callback.register('starter_zone:claimId', function(source)
    return withActionLock(source, 'claimId', function()
    local Player, starter = getStarter(source)
    if not Player then return false, 'Your character data could not be found. Please reconnect or contact staff if this continues.' end
    if starter.released then return false, 'Starter services are closed because your new citizen clearance is already complete.' end

    if GetResourceState(Config.License.resource) ~= 'started' then
        return false, 'The license system is currently unavailable, so your official ID cannot be issued. Please open a Discord ticket for staff assistance.'
    end

    local alreadyCompleted = starter.tasks.id_card == true
    local alreadyRegistered = hasCsLicense(source, Config.License.idCardItem)

    -- If the license exists from another script/admin action, sync checklist without charging unless reset requires replacement.
    if alreadyRegistered and not alreadyCompleted and not starter.forceIdReplacement then
        if Config.License.giveDriverLicenseWithId then
            local hasDriverLicense = hasCsLicense(source, Config.License.driverLicenseItem)
            local mergedDriver, mergeDriverErr = mergeCsLicense(source, Player, Config.License.driverLicenseItem, Config.License.driverLicenseExpireDays, Config.License.addItem and not hasDriverLicense)
            if not mergedDriver then return false, mergeDriverErr end
        end

        starter.tasks.id_card = true
        saveStarter(Player, starter)
        return true, 'Official ID found in your records. Your New Citizen Checklist has been updated.'
    end

    -- First onboarding ID is free. Re-using this option after completion is a paid replacement.
    if alreadyCompleted or starter.forceIdReplacement then
        local fee = tonumber(Config.License.replacementFee) or 0
        local account = Config.License.replacementAccount or 'bank'

        if fee > 0 then
            if (Player.Functions.GetMoney(account) or 0) < fee then
                return false, ('You need $%s in your %s account to replace your official ID.'):format(fee, account)
            end

            if not removeMoney(Player, account, fee, 'official-id-replacement') then
                return false, 'The ID replacement fee could not be charged. Confirm your account balance and try again.'
            end
        end
    end

    local existingLicenseRow = getCsLicenseRow(Player.PlayerData.citizenid)
    if existingLicenseRow then
        local mergedId, mergeIdErr = mergeCsLicense(source, Player, Config.License.idCardItem, Config.License.expireDays, Config.License.addItem)
        if not mergedId then return false, mergeIdErr end
    else
        local ok, err = pcall(function()
            exports[Config.License.resource]:RegisterCard(source, Config.License.idCardItem, Config.License.expireDays, Config.License.addItem)
        end)

        if not ok then
            print('[starter_zone] cs_license RegisterCard failed:', err)
            return false, 'Could not register your official ID documents. Open a Discord ticket so staff can check the license system.'
        end
    end

    if Config.License.giveDriverLicenseWithId then
        local mergedDriver, mergeDriverErr = mergeCsLicense(source, Player, Config.License.driverLicenseItem, Config.License.driverLicenseExpireDays, Config.License.addItem)
        if not mergedDriver then return false, mergeDriverErr end
    end

    starter.tasks.id_card = true
    starter.forceIdReplacement = false
    saveStarter(Player, starter)

    if alreadyCompleted or alreadyRegistered then
        local fee = tonumber(Config.License.replacementFee) or 0
        return true, fee > 0 and ('Replacement official ID and driver license issued. Replacement fee charged: $%s.'):format(fee) or 'Replacement official ID and driver license issued.'
    end

    return true, 'Your official ID and 30-day driver license have been issued for free.'
    end)
end)

local function getStarterItem(profile, item)
    for _, data in ipairs(profile.items or {}) do
        if data.item == item then return data end
    end
end

local function getStarterVehicle(profile, model)
    if not Config.StarterKit.allowVehicle then return nil end
    for _, data in ipairs(profile.vehicles or {}) do
        if data.model == model then return data end
    end
end

local function randomPlate()
    local prefix = Config.StarterKit.vehiclePlatePrefix or 'NLL'

    for _ = 1, 25 do
        local plate = ('%s%s'):format(prefix, math.random(10000, 99999)):sub(1, 8)
        local exists = MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE plate = ?', { plate })
        if not exists then return plate end
    end

    return nil
end

local function giveVehicleRegistration(src, Player, plate, model)
    local registration = Config.VehicleRegistration
    if not registration or not registration.enabled then return end
    if not plate or not model then return end

    local resource = registration.resource or 'm-Insurance'
    if GetResourceState(resource) ~= 'started' then
        print(('[starter_zone] %s is not started; vehicle registration was not granted for plate %s.'):format(resource, plate))
        return
    end

    local identifier = Player.PlayerData and Player.PlayerData.citizenid
    if not identifier then
        print(('[starter_zone] Could not grant vehicle registration for plate %s because citizenid was missing.'):format(plate))
        return
    end

    local ok, err = pcall(function()
        exports[resource]:GiveCarRegistration(src, plate, model, tonumber(registration.expireMonths) or 1, identifier)
    end)

    if not ok then
        print(('[starter_zone] Failed to grant vehicle registration for plate %s: %s'):format(plate, err))
    end
end

local function giveStarterVehicle(src, Player, vehicleData)
    local plate = randomPlate()
    if not plate then return false, 'Could not generate a starter vehicle plate. Please try again or open a Discord ticket if this continues.' end

    local model = vehicleData.model
    local hash = joaat(model)
    local mods = json.encode({
        model = hash,
        plate = plate
    })

    local ok, insertId = pcall(function()
        return MySQL.insert.await([[
        INSERT INTO player_vehicles
            (license, citizenid, vehicle, hash, mods, plate, garage, state, garage_id, in_garage, fuel, engine, body, job_vehicle, gang_vehicle)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            Player.PlayerData.license,
            Player.PlayerData.citizenid,
            model,
            hash,
            mods,
            plate,
            Config.StarterKit.vehicleGarage,
            1,
            Config.StarterKit.vehicleGarage,
            1,
            Config.StarterVehiclePickup and Config.StarterVehiclePickup.fuel or 25.0,
            1000,
            1000,
            0,
            0
        })
    end)

    if not ok or not insertId then
        ok, insertId = pcall(function()
            return MySQL.insert.await([[
                INSERT INTO player_vehicles
                    (citizenid, vehicle, hash, mods, plate, garage_id, in_garage, fuel, engine, body, job_vehicle, gang_vehicle)
                VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                Player.PlayerData.citizenid,
                model,
                hash,
                mods,
                plate,
                Config.StarterKit.vehicleGarage,
                1,
                Config.StarterVehiclePickup and Config.StarterVehiclePickup.fuel or 25.0,
                1000,
                1000,
                0,
                0
            })
        end)
    end

    if not ok or not insertId then return false, 'Could not register your starter vehicle in the garage database. Open a Discord ticket for staff assistance.' end
    giveVehicleRegistration(src, Player, plate, model)
    return true, plate
end

local function giveStarterVehicleKeys(src, plate)
    local keyConfig = Config.StarterVehiclePickup and Config.StarterVehiclePickup.keys
    if not keyConfig or not keyConfig.enabled or not plate then return end

    local resource = keyConfig.resource or 'wasabi_carlock'
    if GetResourceState(resource) ~= 'started' then
        print(('[starter_zone] %s is not started; starter vehicle keys were not granted for plate %s.'):format(resource, plate))
        return
    end

    if keyConfig.serverExport then
        local ok, result = pcall(function()
            return exports[resource][keyConfig.serverExport](src, plate)
        end)
        if ok and result ~= false then return end

        ok, result = pcall(function()
            return exports[resource][keyConfig.serverExport](plate)
        end)
        if ok and result ~= false then return end
    end

    if keyConfig.serverEvent then
        TriggerEvent(keyConfig.serverEvent, src, plate)
        return
    end

    if keyConfig.clientEvent then
        TriggerClientEvent(keyConfig.clientEvent, src, plate)
    end
end

local function rollStarterBonus(profile)
    local bonus = profile.bonus
    if not bonus or not bonus.enabled or type(bonus.items) ~= 'table' or #bonus.items < 1 then return nil end

    local index = math.random(1, #bonus.items)
    local data = bonus.items[index]
    if not data or not data.item then return nil end

    return {
        item = data.item,
        label = data.label or data.item,
        amount = data.amount or 1,
        image = ('nui://ox_inventory/web/images/%s.png'):format(data.item)
    }
end

lib.callback.register('starter_zone:claimKit', function(source, selected)
    return withActionLock(source, 'claimKit', function()
    local Player, starter = getStarter(source)
    if not Player then return false, 'Your character data could not be found. Please reconnect or contact staff if this continues.' end
    if starter.released then return false, 'Starter services are closed because your new citizen clearance is already complete.' end
    if starter.claimedStarterKit then return false, 'You already claimed your starter essentials for this character.' end
    if type(selected) ~= 'table' then return false, 'Your starter essentials selection was invalid. Reopen the menu and try again.' end

    local _, profile = getStarterProfile(Player)
    local maxChoices = profile.maxChoices or 6
    local budget = profile.budget or 0

    local count = 0
    local totalCost = 0
    local seen = {}
    local toGive = {}
    local selectedItems = selected.items or selected
    local selectedVehicle = selected.vehicle
    local vehicleToGive = nil
    local bonusItem = rollStarterBonus(profile)
    local requiredItem = Config.StarterKit.requiredItem
    local requiredItemLabel = Config.StarterKit.requiredItemLabel or requiredItem

    if type(selectedItems) ~= 'table' then return false, 'Your starter item selection was invalid. Reopen the menu and try again.' end
    if #selectedItems > math.max(20, maxChoices * 2) then return false, 'Too many starter item selections were submitted. Reopen the menu and choose within the starter pack limit.' end

    for _, selection in ipairs(selectedItems) do
        local itemName = type(selection) == 'table' and selection.item or selection
        local quantity = type(selection) == 'table' and tonumber(selection.quantity) or 1

        if type(itemName) ~= 'string' then return false, 'One selected starter item was invalid. Reopen the menu and try again.' end
        if not quantity or quantity < 1 or quantity % 1 ~= 0 then return false, 'One starter item had an invalid quantity. Reopen the menu and try again.' end
        if seen[itemName] and not Config.StarterKit.allowDuplicateChoices then
            return false, 'Duplicate starter item selected. Remove the duplicate and try again.'
        end
        seen[itemName] = true

        local itemData = getStarterItem(profile, itemName)
        if not itemData then return false, ('That starter item is not available: %s. Reopen the menu and choose listed items only.'):format(itemName) end
        if quantity > (itemData.maxQuantity or maxChoices) then
            return false, ('You can only choose %s %s for this starter pack.'):format(itemData.maxQuantity or maxChoices, itemData.label or itemData.item)
        end

        count += quantity
        totalCost += (tonumber(itemData.cost) or 0) * quantity
        if count > maxChoices then
            return false, ('Your starter pack is limited to %s total selections. Remove an item before adding another.'):format(maxChoices)
        end
        local grantAmount = tonumber(itemData.amount) or 1
        if grantAmount < 1 or grantAmount % 1 ~= 0 then
            return false, ('Starter item %s has an invalid grant amount. Open a Discord ticket so staff can correct the item configuration.'):format(itemData.label or itemData.item)
        end

        toGive[#toGive + 1] = {
            item = itemData.item,
            label = itemData.label or itemData.item,
            quantity = quantity * grantAmount,
            selections = quantity
        }
    end

    if requiredItem and requiredItem ~= '' and not seen[requiredItem] then
        return false, ('You must choose a %s before claiming your starter essentials. Use it to request airport taxi transportation.'):format(requiredItemLabel)
    end

    if selectedVehicle then
        if type(selectedVehicle) ~= 'string' then return false, 'Your starter vehicle selection was invalid. Reopen the menu and try again.' end
        local vehicleData = getStarterVehicle(profile, selectedVehicle)
        if not vehicleData then return false, 'That starter vehicle is not available for your starter pack.' end

        local vehicleChoices = tonumber(vehicleData.countsAsChoices) or 1
        count += vehicleChoices
        totalCost += tonumber(vehicleData.cost) or 0
        if count > maxChoices then
            return false, ('The selected vehicle puts your starter pack over the %s selection limit.'):format(maxChoices)
        end

        vehicleToGive = vehicleData
    end

    if count < 1 then return false, 'Choose at least one starter item or vehicle before claiming your starter essentials.' end
    if totalCost > budget then
        return false, ('Your starter pack total is $%s, but your starter budget is $%s. Remove an item or vehicle and try again.'):format(totalCost, budget)
    end

    for _, itemData in ipairs(toGive) do
        local canCarry = canCarryInventoryItem(source, itemData.item, itemData.quantity)
        if not canCarry then
            return false, ('You do not have enough inventory space for %sx %s. Free up space, then claim your starter essentials again.'):format(itemData.quantity, itemData.label or itemData.item)
        end
    end

    if bonusItem then
        local canCarryBonus = canCarryInventoryItem(source, bonusItem.item, bonusItem.amount)
        if not canCarryBonus then
            return false, ('You do not have enough inventory space for your bonus item: %s. Free up space, then claim your starter essentials again.'):format(bonusItem.label or bonusItem.item)
        end
    end

    local grantedItems = {}
    for _, itemData in ipairs(toGive) do
        local ok, err = addInventoryItem(source, itemData.item, itemData.quantity)
        if not ok then
            rollbackInventoryItems(source, grantedItems)
            return false, ('Could not add %s to your inventory. Check your inventory space and open a Discord ticket if the item is missing from the server.'):format(itemData.label or itemData.item)
        end
        grantedItems[#grantedItems + 1] = { item = itemData.item, amount = itemData.quantity }
    end

    if bonusItem then
        local ok, err = addInventoryItem(source, bonusItem.item, bonusItem.amount)
        if not ok then
            rollbackInventoryItems(source, grantedItems)
            return false, ('Could not add bonus item %s to your inventory. Check your inventory space and open a Discord ticket if this continues.'):format(bonusItem.label or bonusItem.item)
        end
        grantedItems[#grantedItems + 1] = { item = bonusItem.item, amount = bonusItem.amount }
        starter.bonusClaimed = true
        starter.bonusItem = bonusItem.item
    end

    local vehiclePlate = nil
    local spawnedVehicleData = nil
    if vehicleToGive then
        if GetResourceState('jg-advancedgarages') ~= 'started' then
            rollbackInventoryItems(source, grantedItems)
            return false, 'Vehicle registration is temporarily unavailable because the garage system is offline. Please open a Discord ticket for staff assistance.'
        end

        local ok, resultOrMessage = giveStarterVehicle(source, Player, vehicleToGive)
        if not ok then
            rollbackInventoryItems(source, grantedItems)
            return false, resultOrMessage
        end
        vehiclePlate = resultOrMessage
        spawnedVehicleData = {
            model = vehicleToGive.model,
            label = vehicleToGive.label or vehicleToGive.model,
            plate = vehiclePlate
        }
    end

    starter.claimedStarterKit = true
    starter.tasks.starter_kit = true
    starter.lastStarterVehiclePlate = vehiclePlate
    starter.lastStarterVehicleModel = vehicleToGive and vehicleToGive.model or nil
    starter.pendingStarterVehicleSpawn = vehiclePlate ~= nil and Config.StarterVehiclePickup and Config.StarterVehiclePickup.spawnOnClaim == true
    saveStarter(Player, starter)

    if vehiclePlate then
        giveStarterVehicleKeys(source, vehiclePlate)
        local vehicleWillSpawn = Config.StarterVehiclePickup and Config.StarterVehiclePickup.spawnOnClaim and spawnedVehicleData ~= nil
        if vehicleWillSpawn then
            TriggerClientEvent('starter_zone:client:spawnStarterVehicle', source, spawnedVehicleData)
        end

        local vehicleMessage = vehicleWillSpawn
            and ('Starter essentials claimed. Your starter vehicle is being prepared nearby with plate %s.'):format(vehiclePlate)
            or ('Starter essentials claimed. Your starter vehicle has been registered with plate %s. Check the configured starter garage or contact staff if you cannot locate it.'):format(vehiclePlate)

        return true, vehicleMessage, bonusItem, vehicleWillSpawn == true
    end

    return true, 'Starter essentials claimed and added to your inventory.', bonusItem
    end)
end)

lib.callback.register('starter_zone:validateStarterVehicleSpawn', function(source, data)
    return withActionLock(source, 'validateStarterVehicleSpawn', function()
    if type(data) ~= 'table' then return false, 'Starter vehicle spawn request was invalid. Reopen the starter menu or contact staff if this continues.' end
    if type(data.plate) ~= 'string' or type(data.model) ~= 'string' then return false, 'Starter vehicle spawn request was missing vehicle details. Reopen the starter menu or contact staff if this continues.' end

    local Player, starter = getStarter(source)
    if not Player then return false, 'Your character data could not be found. Please reconnect or contact staff if this continues.' end
    if starter.released then return false, 'Starter services are closed because your new citizen clearance is already complete.' end
    if starter.pendingStarterVehicleSpawn ~= true then return false, 'No starter vehicle is currently waiting to spawn for this character.' end
    if starter.lastStarterVehiclePlate ~= data.plate or starter.lastStarterVehicleModel ~= data.model then
        return false, 'Starter vehicle spawn validation failed. Reopen the starter menu or open a Discord ticket if this continues.'
    end

    starter.pendingStarterVehicleSpawn = false
    saveStarter(Player, starter)
    return true
    end)
end)

lib.callback.register('starter_zone:setStarterJob', function(source, jobName)
    return withActionLock(source, 'setStarterJob', function()
    local Player, starter = getStarter(source)
    if not Player then return false, 'Your character data could not be found. Please reconnect or contact staff if this continues.' end
    if starter.released then return false, 'Starter services are closed because your new citizen clearance is already complete.' end
    local jobData = Config.AllowedStarterJobs[jobName]
    if not jobData then return false, 'That job is not available. Reopen the Job Center menu and choose one of the listed city jobs.' end
    if jobData.locked then
        return false, jobData.lockedDescription or 'That job unlocks after your new citizen clearance is complete.'
    end
    local starterItems = {}
    if not starter.claimedStarterJobItems then
        for _, data in ipairs(jobData.starterItems or {}) do
            local itemName = data.item
            local amount = tonumber(data.amount) or 1
            if type(itemName) ~= 'string' or amount < 1 or amount % 1 ~= 0 then
                return false, 'This job has an invalid item setup. Open a Discord ticket so staff can correct the job configuration.'
            end

            starterItems[#starterItems + 1] = {
                item = itemName,
                amount = amount,
                label = data.label or itemName
            }
        end

        for _, data in ipairs(starterItems) do
            local canCarry = canCarryInventoryItem(source, data.item, data.amount)
            if not canCarry then
                return false, ('You do not have enough inventory space for %sx %s. Free up space, then select your job again.'):format(data.amount, data.label)
            end
        end
    end

    local grantedItems = {}
    for _, data in ipairs(starterItems) do
        local ok = addInventoryItem(source, data.item, data.amount)
        if not ok then
            rollbackInventoryItems(source, grantedItems)
            return false, ('Could not add job item %s to your inventory. Check your inventory space and open a Discord ticket if this continues.'):format(data.label)
        end
        grantedItems[#grantedItems + 1] = { item = data.item, amount = data.amount }
    end

    if Config.SetJobFromMenu and not setPlayerJob(Player, jobName, Config.DefaultJobGrade) then
        rollbackInventoryItems(source, grantedItems)
        return false, 'Could not assign your job. Please try again once, then open a Discord ticket if it continues.'
    end

    starter.tasks.starter_job = true
    starter.selectedStarterJob = jobName
    starter.claimedStarterJobItems = true
    saveStarter(Player, starter)

    local waypoint = nil
    if jobData.waypoint then
        waypoint = {
            x = jobData.waypoint.x,
            y = jobData.waypoint.y,
            z = jobData.waypoint.z,
            label = jobData.label or jobName
        }
    end

    if waypoint then
        return true, ('Job selected: %s. Your GPS has been set to the first work location.'):format(jobData.label or jobName), waypoint
    end

    return true, ('Job selected: %s. Check your map or job instructions for the first work location.'):format(jobData.label or jobName), waypoint
    end)
end)

exports('CompleteStarterShift', function(source, jobName)
    source = tonumber(source)
    if not source or not jobName then return false end
    if not Config.AllowedStarterJobs[jobName] then return false end

    local Player, starter = getStarter(source)
    if not Player then return false end
    if starter.released then return false end
    if starter.selectedStarterJob ~= jobName then return false end

    local currentJob = Player.PlayerData.job and Player.PlayerData.job.name
    if Config.SetJobFromMenu and currentJob ~= jobName then return false end

    starter.tasks.first_shift = true
    starter.firstShiftJob = jobName
    saveStarter(Player, starter)
    notify(source, ('First work shift completed for %s. Your New Citizen Checklist has been updated.'):format(Config.AllowedStarterJobs[jobName].label or jobName), 'success')
    return true
end)

RegisterNetEvent('starter_zone:server:completeShift', function(jobName)
    -- Optional event hook. Prefer the server export above from job scripts.
    if not Config.AllowClientCompleteShiftEvent then return end
    local src = source
    if not Config.AllowedStarterJobs[jobName] then return end
    exports.starter_zone:CompleteStarterShift(src, jobName)
end)

RegisterNetEvent('starter_zone:server:addBikeRideDistance', function(distanceMeters)
    if not Config.BikeRide or not Config.Requirements.requireBikeRide then return end

    local src = source
    local distance = tonumber(distanceMeters)
    if not distance or distance <= 0.0 then return end

    local Player, starter = getStarter(src)
    if not Player or starter.released then return end

    local now = os.time()
    local minInterval = math.max(1, math.floor((Config.BikeRide.serverUpdateInterval or 10000) / 1000) - 1)
    if (starter.lastBikeRideUpdate or 0) > 0 and now - starter.lastBikeRideUpdate < minInterval then
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
    if not isRideVehicleAllowed(GetEntityModel(vehicle)) then return end

    local coords = GetEntityCoords(ped)
    if Config.BikeRide.trackOnlyInsideStarterZone and not isInsideStarterZone(coords) then return end

    local maxIncrement = Config.BikeRide.maxServerIncrementMeters or 500.0
    local lastCoords = starter.lastBikeRideCoords
    starter.lastBikeRideCoords = { x = coords.x, y = coords.y, z = coords.z }

    if not lastCoords then
        starter.lastBikeRideUpdate = now
        saveStarter(Player, starter)
        return
    end

    local serverDelta = #(coords - vec3(lastCoords.x or coords.x, lastCoords.y or coords.y, lastCoords.z or coords.z))
    if serverDelta <= 0.25 or serverDelta > maxIncrement then
        starter.lastBikeRideUpdate = now
        saveStarter(Player, starter)
        return
    end

    distance = math.min(distance, serverDelta * 1.25, maxIncrement)

    starter.bikeRideDistance = math.min((starter.bikeRideDistance or 0.0) + distance, getBikeRideRequiredMeters())
    starter.lastBikeRideUpdate = now

    if starter.bikeRideDistance >= getBikeRideRequiredMeters() then
        starter.tasks.bike_ride = true
    end

    saveStarter(Player, starter)
end)

RegisterNetEvent('starter_zone:server:starterVehicleSpawned', function(plate)
    local src = source
    if type(plate) ~= 'string' then return end

    local Player, starter = getStarter(src)
    if not Player or starter.released then return end
    if starter.lastStarterVehiclePlate ~= plate then return end
    if starter.pendingStarterVehicleSpawn == true then return end

    local ok = pcall(function()
        MySQL.update.await('UPDATE player_vehicles SET state = 0, in_garage = 0 WHERE citizenid = ? AND plate = ?', {
            Player.PlayerData.citizenid,
            plate
        })
    end)

    if not ok then
        pcall(function()
            MySQL.update.await('UPDATE player_vehicles SET in_garage = 0 WHERE citizenid = ? AND plate = ?', {
                Player.PlayerData.citizenid,
                plate
            })
        end)
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        for _, src in ipairs(GetPlayers()) do
            src = tonumber(src)
            local Player, starter = getStarter(src)
            if Player and starter and not starter.released then
                starter.playtime = (starter.playtime or 0) + 60
                starter.lastPlaytimeTick = os.time()
                saveStarter(Player, starter)
            end
        end
    end
end)

AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local Player, starter = getStarter(src)
    if not Player then return end
    starter.tasks.identity = true
    saveStarter(Player, starter)
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local Player, starter = getStarter(src)
    if not Player then return end
    starter.tasks.identity = true
    saveStarter(Player, starter)
end)

lib.addCommand(Config.Commands.adminRelease, {
    help = 'Release a player from starter zone',
    params = {{ name = 'id', type = 'playerId', help = 'Player ID' }}
}, function(source, args)
    if not requireAdmin(source) then return end
    local Player, starter = getStarter(args.id)
    if not Player then return notify(source, 'Player was not found. Confirm the server ID and try again.', 'error') end
    starter.released = true
    saveStarter(Player, starter)
    notify(args.id, 'Staff released your character from starter clearance. You may now leave the city.', 'success')
    notify(source, ('Player %s was released from starter clearance.'):format(args.id), 'success')
end)

lib.addCommand(Config.Commands.adminReset, {
    help = 'Reset starter progress for a player',
    params = {{ name = 'id', type = 'playerId', help = 'Player ID' }}
}, function(source, args)
    if not requireAdmin(source) then return end
    local Player = getPlayer(args.id)
    if not Player then return notify(source, 'Player was not found. Confirm the server ID and try again.', 'error') end
    local starter = defaultStarter()
    starter.forceIdReplacement = true
    Player.Functions.SetMetaData(Config.MetadataKey, starter)
    notify(args.id, 'Your starter progress was reset by staff. Reopen the starter menu to complete onboarding again.', 'inform')
    notify(source, ('Starter progress was reset for player %s.'):format(args.id), 'success')
end)

lib.addCommand(Config.Commands.adminStatus, {
    help = 'Check starter progress for a player',
    params = {{ name = 'id', type = 'playerId', help = 'Player ID' }}
}, function(source, args)
    if not requireAdmin(source) then return end
    local status = getStatus(args.id)
    if not status then return notify(source, 'Player was not found. Confirm the server ID and try again.', 'error') end
    notify(source, ('Job: %s | Bike: %.1f/%.1f mi | Bank: %s/%s | Playtime: %sm/%sm | Can leave: %s'):format(
        status.job,
        (status.bikeRideDistance or 0.0) / 1609.344,
        (status.requiredBikeRideDistance or 0.0) / 1609.344,
        status.bank,
        status.requiredBank,
        math.floor(status.playtime / 60),
        math.floor(status.requiredPlaytime / 60),
        tostring(status.canLeave)
    ), 'inform')
end)
