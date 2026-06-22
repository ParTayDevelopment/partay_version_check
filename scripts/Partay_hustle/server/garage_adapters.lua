-- Partay_hustle garage adapters
-- This file provides a single event to grant a vehicle reward.
-- It delegates to your chosen garage system or a custom handler in open_client.lua.

local function getFramework()
    local fw = (Config.Framework or 'qbx')
    if fw == 'qb' or fw == 'qbx' or fw == 'esx' then return fw end
    return 'qbx'
end

-- Helper: fetch a sensible default identifier per framework
local function getIdentifier(source)
    if getFramework() == 'esx' then
        local xPlayer = GetPlayer(source)
        return xPlayer and xPlayer.identifier or nil
    else
        local Player = GetPlayer(source)
        return Player and Player.PlayerData and Player.PlayerData.citizenid or nil
    end
end

-- Prefer license2: then license: as a raw identifier string
local function getLicenseIdentifier(source)
    local ids = GetPlayerIdentifiers(source) or {}
    local lic2, lic
    for _, id in ipairs(ids) do
        if type(id) == 'string' then
            if id:sub(1,9) == 'license2:' then lic2 = id end
            if id:sub(1,8) == 'license:' then lic = id end
        end
    end
    return lic2 or lic or nil
end

-- Generate a simple plate (you may replace via config or adapter)
local function defaultPlate()
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local plate = ''
    for i = 1, 8 do
        local idx = math.random(1, #chars)
        plate = plate .. string.sub(chars, idx, idx)
    end
    return plate
end

-- Core routing event. Do NOT remove.
-- Listen for this event in open_client.lua for custom systems.
-- Public helper that tries to grant a vehicle immediately and returns boolean
function PartayHustle_GiveVehicle(source, model, reward)
    local sys = (Config.Garage and Config.Garage.system) or 'custom'
    local plate = (Config.Garage and Config.Garage.plate and type(Config.Garage.plate) == 'function')
        and Config.Garage.plate() or defaultPlate()
    local ownerId = getIdentifier(source)

    if not ownerId then
        print('[Partay_hustle] Could not resolve player identifier for garage add.')
        return false
    end

    -- Normalized payload across adapters
    local payload = {
        owner = ownerId,
        source = source,
        model = model,
        plate = plate,
        garage = (Config.Garage and Config.Garage.defaultGarage) or 'A',
        state = (Config.Garage and Config.Garage.defaultState) or 'out', -- or 'stored'
        props = reward and reward.props or {}, -- optional vehicle props
        metadata = reward and reward.metadata or nil,
    }

    -- Direct adapters (return boolean) where possible
    if sys == 'jg' then
        -- JG Advanced Garages reads from your framework's owned vehicles table.
        -- On QB/QBX this is commonly `player_vehicles`. Insert a row directly.
        local function hasCol(tbl, col)
            local done, present = false, false
            MySQL.query('SHOW COLUMNS FROM '..tbl..' LIKE ?', { col }, function(res)
                present = (res and res[1]) and true or false
                done = true
            end)
            while not done do Wait(0) end
            return present
        end

        local tableName = 'player_vehicles'
        -- Basic required columns
        local cols = { 'citizenid', 'plate', 'vehicle' }
        local includeGarage = hasCol(tableName, 'garage')
        local includeState = hasCol(tableName, 'state')
        local includeHash = hasCol(tableName, 'hash')
        local includeLicense = hasCol(tableName, 'license')

        if includeGarage then table.insert(cols, 'garage') end
        if includeState then table.insert(cols, 'state') end
        if includeHash then table.insert(cols, 'hash') end
        if includeLicense then table.insert(cols, 'license') end

        -- vehicle column expects model string for your schema
        local vehicleValue = tostring(payload.model)
        local values = { payload.owner, payload.plate, vehicleValue }
        if includeGarage then table.insert(values, payload.garage) end
        if includeState then
            local stateVal = payload.state
            -- Some schemas use 0/1 for out/stored; if numeric expected, map here
            if type(stateVal) == 'string' then
                local lowered = stateVal:lower()
                if lowered == 'stored' then stateVal = 1 elseif lowered == 'out' then stateVal = 0 end
            end
            table.insert(values, stateVal)
        end
        if includeHash then
            local hash = GetHashKey and GetHashKey(payload.model) or payload.model
            table.insert(values, tostring(hash))
        end
        if includeLicense then
            local lic = getLicenseIdentifier(source)
            table.insert(values, lic or '')
        end

        local placeholders = ''
        for i = 1, #cols do
            placeholders = placeholders .. (i == 1 and '?' or ',?')
        end
        local sql = ('INSERT INTO %s (%s) VALUES (%s)'):format(tableName, table.concat(cols, ','), placeholders)

        local inserted, ok = false, false
        MySQL.insert(sql, values, function(id)
            inserted = true
            ok = (id and id > 0) and true or true -- some schemas may not return id; treat no error as ok
        end)
        while not inserted do Wait(0) end
        return ok
    end

    -- For other systems, emit events (non-blocking) and optimistically return true
    if sys == 'qbox' then
        TriggerEvent('Partay_hustle:garage:qbox:add', payload)
        return true
    elseif sys == 'qb' then
        TriggerEvent('Partay_hustle:garage:qb:add', payload)
        return true
    elseif sys == 'esx' then
        TriggerEvent('Partay_hustle:garage:esx:add', payload)
        return true
    else
        TriggerEvent('Partay_hustle:garage:custom:add', payload)
        return true
    end
end

AddEventHandler('Partay_hustle:garage:giveVehicle', function(source, model, reward)
    PartayHustle_GiveVehicle(source, model, reward)
end)
