local airlineId

local function dbg(...)
    if Config.Debug then
        print('[ParTay Airlines]', ...)
    end
end

local function notify(src, description, notifyType)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'ParTay Airlines',
        description = description,
        type = notifyType or 'inform'
    })
end

local function getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function getCitizenId(src)
    local player = getPlayer(src)
    return player and player.PlayerData.citizenid
end

local function getFullName(player)
    local charinfo = player.PlayerData.charinfo or {}
    return ('%s %s'):format(charinfo.firstname or 'Unknown', charinfo.lastname or 'Passenger')
end

local function getJob(player)
    return player and player.PlayerData and player.PlayerData.job or {}
end

local function getJobGrade(player)
    local job = getJob(player)
    return job.grade and (job.grade.level or job.grade.grade or 0) or 0
end

local function hasAirlineJob(src, minimumGrade)
    local player = getPlayer(src)
    local job = getJob(player)

    return job.name == Config.JobName and (job.onduty ~= false) and getJobGrade(player) >= (minimumGrade or 0)
end

local syncedNavigationWaypoints = {}

local function navigationResource()
    local resource = Config.Navigation and Config.Navigation.resource or 'sleepless_waypoints'
    if GetResourceState(resource) ~= 'started' then return nil end
    return resource
end

local function normalizeWaypointData(data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return nil end

    data.coords = vec3(data.coords.x or data.coords[1] or 0.0, data.coords.y or data.coords[2] or 0.0, data.coords.z or data.coords[3] or 0.0)
    return data
end

local function removeSyncedWaypoint(owner, key)
    local resource = navigationResource()
    local ownerKey = ('%s:%s'):format(owner, key)
    local waypointId = syncedNavigationWaypoints[ownerKey]
    if not waypointId then return end

    if resource then
        pcall(function()
            exports[resource]:remove(waypointId)
        end)
    end

    syncedNavigationWaypoints[ownerKey] = nil
end

RegisterNetEvent('partay_airlines:server:setNavigationWaypoint', function(key, data, targets)
    local src = source
    local resource = navigationResource()
    if not resource or type(key) ~= 'string' or type(targets) ~= 'table' then return end

    data = normalizeWaypointData(data)
    if not data then return end

    removeSyncedWaypoint(src, key)

    local cleanTargets = {}
    for _, target in ipairs(targets) do
        local serverId = tonumber(target)
        if serverId and serverId > 0 and serverId ~= src then
            cleanTargets[#cleanTargets + 1] = serverId
        end
    end
    if #cleanTargets == 0 then return end

    local ok, waypointId = pcall(function()
        return exports[resource]:create(cleanTargets, data)
    end)

    if ok and waypointId then
        syncedNavigationWaypoints[('%s:%s'):format(src, key)] = waypointId
    end
end)

RegisterNetEvent('partay_airlines:server:clearNavigationWaypoint', function(key)
    if type(key) ~= 'string' then return end
    removeSyncedWaypoint(source, key)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local prefix = ('%s:'):format(src)

    for ownerKey in pairs(syncedNavigationWaypoints) do
        if ownerKey:sub(1, #prefix) == prefix then
            local key = ownerKey:sub(#prefix + 1)
            removeSyncedWaypoint(src, key)
        end
    end
end)

local function hasRequiredTicketJob(player, ticketClass)
    local classConfig = Config.TicketClasses[ticketClass]
    if not classConfig or not classConfig.requiredJobs then return true end

    local job = getJob(player)
    return classConfig.requiredJobs[job.name] == true
end

local function encode(data)
    return json.encode(data or {})
end

local function decode(value, fallback)
    if not value or value == '' then return fallback or {} end
    local ok, data = pcall(json.decode, value)
    if not ok or type(data) ~= 'table' then return fallback or {} end
    return data
end

local function manifestTemplate()
    return {
        ticketed = {},
        checkedIn = {},
        customsCleared = {},
        boarded = {},
        completed = {},
        noShows = {},
        refunded = {},
        removed = {}
    }
end

local function normalizeManifest(flight)
    local manifest = decode(flight.manifest, manifestTemplate())
    manifest.ticketed = manifest.ticketed or {}
    manifest.checkedIn = manifest.checkedIn or {}
    manifest.customsCleared = manifest.customsCleared or {}
    manifest.boarded = manifest.boarded or {}
    manifest.completed = manifest.completed or {}
    manifest.noShows = manifest.noShows or {}
    manifest.refunded = manifest.refunded or {}
    manifest.removed = manifest.removed or {}
    return manifest
end

local function countMap(map)
    local count = 0
    for _, value in pairs(map or {}) do
        if value then count = count + 1 end
    end
    return count
end

local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end

    return false
end

local function routeRequirement(route, requirement)
    return route and route.requirements and route.requirements[requirement] == true
end

local function getPassportItem(src, citizenid)
    local passports = exports.ox_inventory:Search(src, 'slots', Config.PassportItem) or {}
    for _, item in pairs(passports) do
        local metadata = item.metadata or {}
        local owner = metadata.citizenid or metadata.owner or metadata.ownerCitizenId
        local expiresAt = tonumber(metadata.expiresAt or metadata.expiry or metadata.expires)

        if (not owner or owner == citizenid) and (not expiresAt or os.time() <= expiresAt) then
            return item
        end
    end

    return nil
end

local function hasValidPassport(src, citizenid)
    return getPassportItem(src, citizenid) ~= nil
end

local function getRoute(routeId)
    return Config.Routes[routeId]
end

local function getAircraft(model)
    return Config.Aircraft[model]
end

local function getFlight(flightId)
    return MySQL.single.await('SELECT * FROM partay_airline_flights WHERE id = ?', { flightId })
end

local function saveManifest(flightId, manifest)
    MySQL.update.await('UPDATE partay_airline_flights SET manifest = ? WHERE id = ?', { encode(manifest), flightId })
end

local function setFlightStatus(flightId, status)
    MySQL.update.await('UPDATE partay_airline_flights SET status = ? WHERE id = ?', { status, flightId })
end

local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `partay_airlines` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(80) NOT NULL,
            `code` VARCHAR(12) NOT NULL,
            `owner_citizenid` VARCHAR(64) DEFAULT NULL,
            `balance` INT NOT NULL DEFAULT 0,
            `reputation` INT NOT NULL DEFAULT 50,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_partay_airlines_code` (`code`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `partay_airline_flights` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `flight_number` VARCHAR(20) NOT NULL,
            `airline_id` INT NOT NULL,
            `pilot_citizenid` VARCHAR(64) DEFAULT NULL,
            `aircraft_net_id` INT DEFAULT NULL,
            `aircraft_model` VARCHAR(40) DEFAULT NULL,
            `route_id` VARCHAR(80) NOT NULL,
            `departure_airport` VARCHAR(80) NOT NULL,
            `arrival_airport` VARCHAR(80) NOT NULL,
            `gate` VARCHAR(20) NOT NULL,
            `status` VARCHAR(32) NOT NULL DEFAULT 'scheduled',
            `departure_time` INT NOT NULL,
            `started_at` INT DEFAULT NULL,
            `landed_at` INT DEFAULT NULL,
            `completed_at` INT DEFAULT NULL,
            `ticket_revenue` INT NOT NULL DEFAULT 0,
            `pilot_payout` INT NOT NULL DEFAULT 0,
            `airline_profit` INT NOT NULL DEFAULT 0,
            `flight_score` INT NOT NULL DEFAULT 0,
            `manifest` LONGTEXT DEFAULT NULL,
            `route_progress` INT NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_partay_airline_flights_number` (`flight_number`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `partay_airline_tickets` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `flight_id` INT NOT NULL,
            `flight_number` VARCHAR(20) NOT NULL,
            `citizenid` VARCHAR(64) NOT NULL,
            `passenger_name` VARCHAR(100) NOT NULL,
            `ticket_class` VARCHAR(32) NOT NULL,
            `seat` VARCHAR(8) NOT NULL,
            `gate` VARCHAR(20) NOT NULL,
            `price` INT NOT NULL DEFAULT 0,
            `status` VARCHAR(32) NOT NULL DEFAULT 'ticketed',
            `metadata` LONGTEXT DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_partay_airline_tickets_flight` (`flight_id`),
            KEY `idx_partay_airline_tickets_citizenid` (`citizenid`)
        )
    ]])
end

local function ensureAirline()
    local row = MySQL.single.await('SELECT id FROM partay_airlines WHERE code = ?', { Config.Airline.code })
    if row then
        airlineId = row.id
        return
    end

    airlineId = MySQL.insert.await(
        'INSERT INTO partay_airlines (name, code, balance, reputation) VALUES (?, ?, ?, ?)',
        { Config.Airline.name, Config.Airline.code, Config.Airline.startingBalance, Config.Airline.startingReputation }
    )
end

local function generateFlightNumber()
    for _ = 1, 20 do
        local number = ('%s%s'):format(Config.FlightNumbers.prefix, math.random(Config.FlightNumbers.min, Config.FlightNumbers.max))
        local exists = MySQL.scalar.await('SELECT id FROM partay_airline_flights WHERE flight_number = ?', { number })
        if not exists then return number end
    end

    return ('%s%s'):format(Config.FlightNumbers.prefix, os.time())
end

local function getSeat(manifest, aircraft)
    local seatNumber = countMap(manifest.ticketed) + 1
    if seatNumber > aircraft.seats then return nil end
    return tostring(seatNumber) .. 'A'
end

local function publicFlight(row)
    local route = getRoute(row.route_id)
    local aircraft = row.aircraft_model and getAircraft(row.aircraft_model)
    local manifest = normalizeManifest(row)

    return {
        id = row.id,
        flightNumber = row.flight_number,
        airline = Config.Airline.name,
        routeId = row.route_id,
        routeLabel = route and route.label or row.route_id,
        departure = row.departure_airport,
        arrival = row.arrival_airport,
        gate = row.gate,
        status = row.status,
        departureTime = row.departure_time,
        aircraftNetId = row.aircraft_net_id,
        aircraftModel = row.aircraft_model,
        aircraftLabel = aircraft and aircraft.label or 'Unassigned',
        routeProgress = row.route_progress or 0,
        seats = aircraft and aircraft.seats or 0,
        seatsAvailable = aircraft and math.max(aircraft.seats - countMap(manifest.ticketed), 0) or 0,
        ticketed = countMap(manifest.ticketed),
        boarded = countMap(manifest.boarded),
        completed = countMap(manifest.completed),
        customsCleared = countMap(manifest.customsCleared),
        pilotAssigned = row.pilot_citizenid ~= nil,
        routeType = route and route.routeType or 'domestic',
        requirements = route and route.requirements or {},
        prices = route and route.basePrice and Config.TicketClasses or {}
    }
end

local function getActiveFlights()
    local rows = MySQL.query.await([[
        SELECT * FROM partay_airline_flights
        WHERE status IN ('scheduled', 'awaiting_pilot', 'boarding_soon', 'boarding', 'final_call', 'boarding_closed', 'taxiing', 'taxi_hold', 'takeoff_hold', 'takeoff_cleared', 'in_air', 'approach', 'landed', 'deboarding', 'delayed')
        ORDER BY departure_time ASC
        LIMIT 50
    ]])

    local flights = {}
    for _, row in ipairs(rows or {}) do
        flights[#flights + 1] = publicFlight(row)
    end

    return flights
end

lib.callback.register('partay_airlines:server:getFlights', function()
    return getActiveFlights()
end)

lib.callback.register('partay_airlines:server:getRoutes', function(source)
    if not hasAirlineJob(source, Config.StaffGrades.createFlight) then return {} end

    local routes = {}
    for routeId, route in pairs(Config.Routes) do
        routes[#routes + 1] = {
            id = routeId,
            label = route.label,
            gate = route.gate,
            basePrice = route.basePrice,
            allowedAircraft = route.allowedAircraft
        }
    end

    return routes
end)

lib.callback.register('partay_airlines:server:getDispatchData', function(source)
    local player = getPlayer(source)
    if not player then return nil end

    local grade = getJobGrade(player)
    local job = getJob(player)
    local permissions = {
        createFlight = hasAirlineJob(source, Config.StaffGrades.createFlight),
        claimFlight = hasAirlineJob(source, Config.StaffGrades.claimFlight),
        operateBoarding = hasAirlineJob(source, Config.StaffGrades.operateBoarding),
        cancelFlight = hasAirlineJob(source, Config.StaffGrades.cancelFlight)
    }

    local routes = {}
    for routeId, route in pairs(Config.Routes or {}) do
        routes[#routes + 1] = {
            id = routeId,
            label = route.label,
            departure = route.departure,
            arrival = route.arrival,
            gate = route.gate,
            basePrice = route.basePrice,
            expectedTime = route.expectedTime,
            allowedAircraft = route.allowedAircraft,
            allowedTicketClasses = route.allowedTicketClasses,
            requirements = route.requirements or {},
            routeType = route.routeType or 'domestic'
        }
    end

    local aircraft = {}
    for model, data in pairs(Config.Aircraft or {}) do
        aircraft[#aircraft + 1] = {
            model = model,
            label = data.label,
            seats = data.seats,
            classes = data.classes,
            fuelCost = data.fuelCost,
            maintenanceCost = data.maintenanceCost
        }
    end

    local currentFlight
    local citizenid = getCitizenId(source)
    if citizenid then
        local row = MySQL.single.await([[
            SELECT * FROM partay_airline_flights
            WHERE pilot_citizenid = ? AND status IN ('boarding_soon', 'boarding', 'final_call', 'boarding_closed', 'taxiing', 'taxi_hold', 'takeoff_hold', 'takeoff_cleared', 'in_air', 'approach', 'landed', 'deboarding', 'delayed')
            ORDER BY id DESC
            LIMIT 1
        ]], { citizenid })
        currentFlight = row and publicFlight(row) or nil
    end

    return {
        airline = Config.Airline,
        job = {
            name = job.name,
            label = job.label,
            grade = grade,
            onduty = job.onduty ~= false
        },
        permissions = permissions,
        staffGrades = Config.StaffGrades,
        flights = getActiveFlights(),
        routes = routes,
        aircraft = aircraft,
        airports = Config.Airports,
        locations = Config.Locations,
        currentFlight = currentFlight,
        now = os.time()
    }
end)

lib.callback.register('partay_airlines:server:createFlight', function(source, data)
    if not hasAirlineJob(source, Config.StaffGrades.createFlight) then
        return false, 'You are not cleared to create flights.'
    end

    local route = getRoute(data.routeId)
    local aircraft = getAircraft(data.aircraftModel)

    if not route then return false, 'Invalid route.' end
    if not aircraft or not contains(route.allowedAircraft, data.aircraftModel) then return false, 'That aircraft is not allowed on this route.' end

    local departureMinutes = tonumber(data.departureMinutes) or 15
    departureMinutes = math.max(departureMinutes, 1)

    local flightNumber = generateFlightNumber()
    local flightId = MySQL.insert.await([[
        INSERT INTO partay_airline_flights
        (flight_number, airline_id, aircraft_model, route_id, departure_airport, arrival_airport, gate, status, departure_time, manifest)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'awaiting_pilot', ?, ?)
    ]], {
        flightNumber,
        airlineId,
        data.aircraftModel,
        data.routeId,
        route.departure,
        route.arrival,
        route.gate,
        os.time() + departureMinutes * 60,
        encode(manifestTemplate())
    })

    notify(source, ('Created flight %s.'):format(flightNumber), 'success')
    return true, flightId
end)

lib.callback.register('partay_airlines:server:claimFlight', function(source, flightId, aircraftNetId, aircraftModel)
    if not hasAirlineJob(source, Config.StaffGrades.claimFlight) then
        return false, 'You need to be on duty with No Love Lost Airlines.'
    end

    local flight = getFlight(flightId)
    if not flight then return false, 'Flight not found.' end
    if flight.pilot_citizenid then return false, 'This flight already has a pilot.' end
    if flight.status == 'cancelled' or flight.status == 'completed' or flight.status == 'failed' then return false, 'This flight is not claimable.' end

    local route = getRoute(flight.route_id)
    if not route or not contains(route.allowedAircraft, aircraftModel) then
        return false, 'Your current aircraft is not approved for this route.'
    end

    local citizenid = getCitizenId(source)
    MySQL.update.await([[
        UPDATE partay_airline_flights
        SET pilot_citizenid = ?, aircraft_net_id = ?, aircraft_model = ?, status = 'boarding_soon'
        WHERE id = ?
    ]], { citizenid, aircraftNetId, aircraftModel, flightId })

    notify(source, ('Claimed flight %s.'):format(flight.flight_number), 'success')
    return true
end)

lib.callback.register('partay_airlines:server:setFlightStatus', function(source, flightId, status)
    local allowed = {
        boarding = Config.StaffGrades.operateBoarding,
        final_call = Config.StaffGrades.operateBoarding,
        boarding_closed = Config.StaffGrades.operateBoarding,
        taxiing = Config.StaffGrades.operateBoarding,
        taxi_hold = Config.StaffGrades.operateBoarding,
        takeoff_hold = Config.StaffGrades.operateBoarding,
        takeoff_cleared = Config.StaffGrades.operateBoarding,
        delayed = Config.StaffGrades.operateBoarding,
        cancelled = Config.StaffGrades.cancelFlight
    }

    if not allowed[status] or not hasAirlineJob(source, allowed[status]) then
        return false, 'You are not cleared for that action.'
    end

    local flight = getFlight(flightId)
    if not flight then return false, 'Flight not found.' end

    if status == 'cancelled' then
        MySQL.update.await('UPDATE partay_airline_tickets SET status = ? WHERE flight_id = ?', { 'cancelled', flightId })
    end

    setFlightStatus(flightId, status)
    return true
end)

lib.callback.register('partay_airlines:server:setPilotFlightStatus', function(source, flightId, status)
    local flight = getFlight(flightId)
    local citizenid = getCitizenId(source)
    if not flight or flight.pilot_citizenid ~= citizenid then return false, 'You are not the pilot of this flight.' end

    local transitions = {
        taxiing = {
            boarding_soon = true,
            boarding = true,
            final_call = true,
            boarding_closed = true,
            delayed = true,
            taxiing = true,
            taxi_hold = true
        },
        taxi_hold = {
            taxiing = true,
            taxi_hold = true
        },
        takeoff_hold = {
            taxi_hold = true,
            takeoff_hold = true
        },
        takeoff_cleared = {
            takeoff_hold = true,
            takeoff_cleared = true
        }
    }

    if not transitions[status] or not transitions[status][flight.status] then
        return false, ('Flight is not ready for %s from %s.'):format(status, flight.status or 'unknown')
    end

    setFlightStatus(flightId, status)
    return true
end)

lib.callback.register('partay_airlines:server:buyTicket', function(source, flightId, ticketClass)
    local player = getPlayer(source)
    if not player then return false, 'Player not found.' end

    local classConfig = Config.TicketClasses[ticketClass]
    local flight = getFlight(flightId)
    if not classConfig then return false, 'Invalid ticket class.' end
    if not flight then return false, 'Flight not found.' end
    if flight.status ~= 'awaiting_pilot' and flight.status ~= 'boarding_soon' and flight.status ~= 'scheduled' and flight.status ~= 'boarding' and flight.status ~= 'final_call' and flight.status ~= 'delayed' then
        return false, 'Tickets are closed for this flight.'
    end

    local route = getRoute(flight.route_id)
    local aircraft = getAircraft(flight.aircraft_model)
    if not route or not aircraft then return false, 'Flight is missing route or aircraft config.' end
    if not route.allowedTicketClasses[ticketClass] or not aircraft.classes[ticketClass] then return false, 'That ticket class is not available on this flight.' end
    if not hasRequiredTicketJob(player, ticketClass) then return false, 'You do not have clearance for that ticket class.' end
    if routeRequirement(route, 'passport') and not hasValidPassport(source, player.PlayerData.citizenid) then
        return false, 'This international flight requires a valid passport.'
    end

    local citizenid = player.PlayerData.citizenid
    local existing = MySQL.scalar.await([[
        SELECT id FROM partay_airline_tickets
        WHERE flight_id = ? AND citizenid = ? AND status IN ('ticketed', 'checked_in', 'boarded')
    ]], { flightId, citizenid })
    if existing then return false, 'You already have a ticket for this flight.' end

    local manifest = normalizeManifest(flight)
    local seat = getSeat(manifest, aircraft)
    if not seat then return false, 'This flight is sold out.' end

    local price = math.floor(route.basePrice * classConfig.priceMultiplier)
    if price > 0 and not player.Functions.RemoveMoney(Config.MoneyAccount, price, 'partay-airlines-ticket') then
        return false, 'You cannot afford this ticket.'
    end

    local passengerName = getFullName(player)
    local metadata = {
        flightId = flight.id,
        flightNumber = flight.flight_number,
        airline = Config.Airline.name,
        passengerName = passengerName,
        citizenid = citizenid,
        departure = flight.departure_airport,
        destination = flight.arrival_airport,
        gate = flight.gate,
        seat = seat,
        ticketClass = ticketClass,
        routeType = route.routeType or 'domestic',
        requiresPassport = routeRequirement(route, 'passport'),
        requiresCustoms = routeRequirement(route, 'customsClearance'),
        boardingTime = math.max(flight.departure_time - 900, os.time()),
        departureTime = flight.departure_time,
        expiresAt = flight.departure_time + 7200,
        price = price
    }

    local added = exports.ox_inventory:AddItem(source, Config.BoardingPassItem, 1, metadata)
    if not added then
        if price > 0 then player.Functions.AddMoney(Config.MoneyAccount, price, 'partay-airlines-ticket-refund') end
        return false, 'Your inventory could not hold the boarding pass.'
    end

    MySQL.insert.await([[
        INSERT INTO partay_airline_tickets
        (flight_id, flight_number, citizenid, passenger_name, ticket_class, seat, gate, price, status, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'ticketed', ?)
    ]], { flight.id, flight.flight_number, citizenid, passengerName, ticketClass, seat, flight.gate, price, encode(metadata) })

    manifest.ticketed[citizenid] = true
    saveManifest(flight.id, manifest)
    MySQL.update.await('UPDATE partay_airline_flights SET ticket_revenue = ticket_revenue + ? WHERE id = ?', { price, flight.id })

    for _, item in ipairs(classConfig.freeItems or {}) do
        exports.ox_inventory:AddItem(source, item.name, item.count or 1)
    end

    notify(source, ('Purchased boarding pass for %s.'):format(flight.flight_number), 'success')
    return true
end)

lib.callback.register('partay_airlines:server:clearCustoms', function(source, flightId)
    local player = getPlayer(source)
    if not player then return false, 'Player not found.' end

    local flight = getFlight(flightId)
    if not flight then return false, 'Flight not found.' end

    local route = getRoute(flight.route_id)
    if not routeRequirement(route, 'customsClearance') then
        return false, 'This flight does not require customs clearance.'
    end

    local citizenid = player.PlayerData.citizenid
    if routeRequirement(route, 'passport') and not hasValidPassport(source, citizenid) then
        return false, 'Customs denied: valid passport required.'
    end

    local ticket = MySQL.single.await([[
        SELECT * FROM partay_airline_tickets
        WHERE flight_id = ? AND citizenid = ? AND status IN ('ticketed', 'checked_in')
        ORDER BY id DESC
        LIMIT 1
    ]], { flightId, citizenid })

    if not ticket then return false, 'No valid ticket found for this flight.' end

    local manifest = normalizeManifest(flight)
    manifest.checkedIn[citizenid] = true
    manifest.customsCleared[citizenid] = true
    saveManifest(flight.id, manifest)
    MySQL.update.await('UPDATE partay_airline_tickets SET status = ? WHERE id = ?', { 'checked_in', ticket.id })

    return true, ('Customs cleared for %s.'):format(flight.flight_number)
end)

lib.callback.register('partay_airlines:server:boardFlight', function(source, flightId, gate)
    local player = getPlayer(source)
    if not player then return false, 'Player not found.' end

    local citizenid = player.PlayerData.citizenid
    local flight = getFlight(flightId)
    if not flight then return false, 'Flight not found.' end
    if flight.gate ~= gate then return false, 'Wrong gate.' end
    if flight.status ~= 'boarding' and flight.status ~= 'final_call' then return false, 'This flight is not boarding.' end

    local ticket = MySQL.single.await([[
        SELECT * FROM partay_airline_tickets
        WHERE flight_id = ? AND citizenid = ? AND status IN ('ticketed', 'checked_in')
        ORDER BY id DESC
        LIMIT 1
    ]], { flightId, citizenid })

    if not ticket then return false, 'No valid boarding pass found for this flight.' end

    local metadata = decode(ticket.metadata, {})
    if metadata.expiresAt and os.time() > metadata.expiresAt then return false, 'Boarding pass expired.' end
    if metadata.citizenid ~= citizenid or metadata.flightId ~= flight.id or metadata.gate ~= gate then return false, 'Boarding pass does not match this gate.' end

    local manifest = normalizeManifest(flight)
    if manifest.boarded[citizenid] then return false, 'You are already boarded.' end

    local route = getRoute(flight.route_id)
    if routeRequirement(route, 'passport') and not hasValidPassport(source, citizenid) then
        return false, 'Boarding denied: valid passport required.'
    end
    if routeRequirement(route, 'customsClearance') and not manifest.customsCleared[citizenid] then
        return false, 'Boarding denied: clear international customs first.'
    end

    manifest.checkedIn[citizenid] = true
    manifest.boarded[citizenid] = true
    saveManifest(flight.id, manifest)
    MySQL.update.await('UPDATE partay_airline_tickets SET status = ? WHERE id = ?', { 'boarded', ticket.id })

    notify(source, ('Boarded flight %s. Seat %s.'):format(flight.flight_number, ticket.seat), 'success')
    return true, {
        aircraftNetId = flight.aircraft_net_id,
        seat = ticket.seat,
        flightNumber = flight.flight_number
    }
end)

lib.callback.register('partay_airlines:server:getPilotFlight', function(source)
    local citizenid = getCitizenId(source)
    if not citizenid then return nil end

    local row = MySQL.single.await([[
        SELECT * FROM partay_airline_flights
        WHERE pilot_citizenid = ? AND status IN ('boarding_soon', 'boarding', 'final_call', 'boarding_closed', 'taxiing', 'taxi_hold', 'takeoff_hold', 'takeoff_cleared', 'in_air', 'approach', 'landed', 'deboarding', 'delayed')
        ORDER BY id DESC
        LIMIT 1
    ]], { citizenid })

    return row and publicFlight(row) or nil
end)

lib.callback.register('partay_airlines:server:markTakeoff', function(source, flightId)
    local flight = getFlight(flightId)
    local citizenid = getCitizenId(source)
    if not flight or flight.pilot_citizenid ~= citizenid then return false end
    if flight.status ~= 'takeoff_cleared' then return false end

    MySQL.update.await('UPDATE partay_airline_flights SET status = ?, started_at = ? WHERE id = ?', { 'in_air', os.time(), flightId })
    return true
end)

lib.callback.register('partay_airlines:server:markApproach', function(source, flightId)
    local flight = getFlight(flightId)
    local citizenid = getCitizenId(source)
    if not flight or flight.pilot_citizenid ~= citizenid then return false end
    if flight.status ~= 'in_air' then return false end

    MySQL.update.await('UPDATE partay_airline_flights SET status = ? WHERE id = ?', { 'approach', flightId })
    return true
end)

lib.callback.register('partay_airlines:server:markLanded', function(source, flightId)
    local flight = getFlight(flightId)
    local citizenid = getCitizenId(source)
    if not flight or flight.pilot_citizenid ~= citizenid then return false end
    if flight.status ~= 'in_air' and flight.status ~= 'approach' and flight.status ~= 'takeoff_cleared' then return false end

    MySQL.update.await('UPDATE partay_airline_flights SET status = ?, landed_at = ? WHERE id = ?', { 'deboarding', os.time(), flightId })
    return true
end)

lib.callback.register('partay_airlines:server:markDeboarded', function(source, flightId)
    local player = getPlayer(source)
    local flight = getFlight(flightId)
    if not player or not flight then return false, 'Flight not found.' end
    if flight.status ~= 'deboarding' and flight.status ~= 'landed' then return false, 'This flight is not deboarding.' end

    local citizenid = player.PlayerData.citizenid
    local manifest = normalizeManifest(flight)
    if not manifest.boarded[citizenid] then return false, 'You were not boarded on this flight.' end
    if manifest.completed[citizenid] then return false, 'You already completed this flight.' end

    manifest.completed[citizenid] = true
    saveManifest(flight.id, manifest)
    MySQL.update.await('UPDATE partay_airline_tickets SET status = ? WHERE flight_id = ? AND citizenid = ?', { 'completed', flight.id, citizenid })

    return true, 'Travel completed.'
end)

local function calculateScore(flight, manifest, route)
    local score = 0

    if countMap(manifest.boarded) > 0 then score = score + 20 end
    if flight.started_at then score = score + 25 end
    if flight.landed_at then score = score + 30 end
    if countMap(manifest.completed) == countMap(manifest.boarded) then score = score + 20 end

    return math.min(score, 100)
end

lib.callback.register('partay_airlines:server:completeFlight', function(source, flightId)
    local flight = getFlight(flightId)
    local citizenid = getCitizenId(source)
    if not flight or flight.pilot_citizenid ~= citizenid then return false, 'You are not the pilot of this flight.' end
    if flight.status ~= 'deboarding' then return false, 'Passengers must deboard before completion.' end

    local route = getRoute(flight.route_id)
    local aircraft = getAircraft(flight.aircraft_model)
    if not route or not aircraft then return false, 'Missing route or aircraft config.' end

    local manifest = normalizeManifest(flight)
    local completedCount = countMap(manifest.completed)
    if completedCount <= 0 then return false, 'No completed passengers. No payout.' end

    local score = calculateScore(flight, manifest, route)
    local completedTickets = MySQL.query.await('SELECT ticket_class, price FROM partay_airline_tickets WHERE flight_id = ? AND status = ?', { flightId, 'completed' }) or {}
    local pilotPay = route.payout.pilotBase
    local revenue = 0

    for _, ticket in ipairs(completedTickets) do
        local class = Config.TicketClasses[ticket.ticket_class] or Config.TicketClasses.basic
        pilotPay = pilotPay + math.floor((ticket.price or 0) * 0.15 * (class.pilotPayoutMultiplier or 1.0))
        revenue = revenue + (ticket.price or 0)
    end

    pilotPay = math.floor(pilotPay * (score / 100))
    local airlineProfit = math.max(math.floor(revenue * route.payout.airlineMultiplier) - aircraft.fuelCost - aircraft.maintenanceCost, 0)

    local pilot = getPlayer(source)
    pilot.Functions.AddMoney(Config.MoneyAccount, pilotPay, 'partay-airlines-pilot-payout')

    MySQL.update.await([[
        UPDATE partay_airline_flights
        SET status = 'completed', completed_at = ?, pilot_payout = ?, airline_profit = ?, flight_score = ?
        WHERE id = ?
    ]], { os.time(), pilotPay, airlineProfit, score, flightId })

    MySQL.update.await('UPDATE partay_airlines SET balance = balance + ?, reputation = LEAST(reputation + 1, 100) WHERE id = ?', { airlineProfit, airlineId })

    return true, {
        completedPassengers = completedCount,
        pilotPayout = pilotPay,
        airlineProfit = airlineProfit,
        score = score
    }
end)

RegisterNetEvent('partay_airlines:server:failFlight', function(flightId, reason)
    local src = source
    local flight = getFlight(flightId)
    local citizenid = getCitizenId(src)
    if not flight or flight.pilot_citizenid ~= citizenid then return end
    if flight.status == 'completed' or flight.status == 'failed' or flight.status == 'cancelled' then return end

    MySQL.update.await('UPDATE partay_airline_flights SET status = ?, flight_score = ? WHERE id = ?', { 'failed', 0, flightId })
    MySQL.update.await('UPDATE partay_airlines SET reputation = GREATEST(reputation - 3, 0) WHERE id = ?', { airlineId })
    notify(src, ('Flight failed: %s'):format(reason or 'unknown issue'), 'error')
end)

exports.qbx_core:CreateUseableItem(Config.BoardingPassItem, function(source, item)
    TriggerClientEvent('partay_airlines:client:showBoardingPass', source, item and item.metadata or {})
end)

if Config.DispatchTablet and Config.DispatchTablet.item then
    exports.qbx_core:CreateUseableItem(Config.DispatchTablet.item, function(source, item)
        if not hasAirlineJob(source, Config.StaffGrades.claimFlight) then
            notify(source, 'You need to be on duty with No Love Lost Airlines to use this tablet.', 'error')
            return
        end

        TriggerClientEvent('partay_airlines:client:openTablet', source)
    end)
end

CreateThread(function()
    math.randomseed(os.time())

    if Config.Database.autoCreateTables then
        createTables()
    end

    ensureAirline()
    dbg(('Ready. Airline ID: %s'):format(airlineId))
end)
