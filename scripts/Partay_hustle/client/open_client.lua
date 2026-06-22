-- Partay_hustle garage integration (editable)
-- This file is intentionally left open for you to connect vehicle rewards
-- to your garage system. We provide ready-to-use hooks for several systems.
-- Pick ONE section below, uncomment, and adjust if needed.
--
-- All handlers receive a single table `p` with fields:
--   p.owner (identifier), p.source (player id), p.model, p.plate,
--   p.garage (string), p.state ('out'|'stored'), p.props (table|nil)
--
-- Notes:
-- - jg-advanced garages: consult https://docs.jgscripts.com/advanced-garages/introduction
-- - qbox garage: integrate with your qbox vehicles/garages resource
-- - qb-garage: integrate with your qb-vehicles or qb-garages data path
-- - esx_garage: usually requires inserting into owned_vehicles or calling its API
--
-- By default, we register no-ops that simply warn in server console.

local function warn(pfx)
    print(('[Partay_hustle] %s handler not configured. Edit open_client.lua to enable.'):format(pfx))
end

-- UNIVERSAL custom hook
AddEventHandler('Partay_hustle:garage:custom:add', function(p)
    warn('custom')
end)

local function findJgResource()
    local candidates = {
        'jg-advancedgarages',
        'jg_advancedgarages',
        'jg-advanced-garages',
        'jg-advancedgarage',
        'jg_advanced_garages',
    }
    for _, name in ipairs(candidates) do
        if GetResourceState(name) == 'started' then return name end
    end
    return nil
end

AddEventHandler('Partay_hustle:garage:jg:add', function(p)
    local res = findJgResource()
    if not res then
        return warn('jg')
    end
    -- Expected signature for JG Advanced Garages (QB/ESX variants may differ slightly):
    --   AddOwnedVehicle(identifier, model, plate, props, garage, state)
    if Config.Debug then
        print(('[Partay_hustle] JG add -> res=%s owner=%s model=%s plate=%s garage=%s state=%s')
            :format(res, tostring(p.owner), tostring(p.model), tostring(p.plate), tostring(p.garage), tostring(p.state)))
    end
    local ok, err = pcall(function()
        exports[res]:AddOwnedVehicle(p.owner, p.model, p.plate, p.props or {}, p.garage, p.state)
    end)
    if not ok then
        print(('[Partay_hustle] JG add vehicle failed: %s'):format(err or 'unknown error'))
        return
    end
    TriggerClientEvent('Partay_hustle:client:notify', p.source, 'success', ('Garage added: %s [%s]'):format(p.model, p.plate))
end)

-- Qbox hook
-- Uncomment and adapt according to your qbox vehicles API.
-- AddEventHandler('Partay_hustle:garage:qbox:add', function(p)
--     if GetResourceState('qbx_vehicles') ~= 'started' and GetResourceState('qbx_vehicleshop') ~= 'started' then return warn('qbox') end
--     -- Example placeholder; replace with correct call for your setup
--     -- exports['qbx_vehicles']:AddOwnedVehicle(p.owner, p.model, p.plate, p.props, p.garage, p.state)
--     TriggerClientEvent('Partay_hustle:client:notify', p.source, 'success', ('Garage added: %s [%s]'):format(p.model, p.plate))
-- end)

-- QB-Core hook
-- Uncomment and adapt according to your qb vehicles/garages.
-- AddEventHandler('Partay_hustle:garage:qb:add', function(p)
--     if GetResourceState('qb-garages') ~= 'started' and GetResourceState('qb-vehicleshop') ~= 'started' then return warn('qb') end
--     -- Example placeholder; replace with correct call/insertion for your setup
--     -- TriggerEvent('qb-vehicles:server:addOwnedVehicle', p.owner, p.model, p.plate, p.props, p.garage, p.state)
--     TriggerClientEvent('Partay_hustle:client:notify', p.source, 'success', ('Garage added: %s [%s]'):format(p.model, p.plate))
-- end)

-- ESX hook
-- Uncomment and adapt according to your esx_garage.
-- AddEventHandler('Partay_hustle:garage:esx:add', function(p)
--     if GetResourceState('esx_garage') ~= 'started' and GetResourceState('esx_vehicleshop') ~= 'started' then return warn('esx') end
--     -- Example placeholder; replace with correct AddOwnedVehicle API or DB insert
--     -- TriggerEvent('esx_garage:addOwnedVehicle', p.owner, p.model, p.plate, p.props, p.garage, p.state)
--     TriggerClientEvent('Partay_hustle:client:notify', p.source, 'success', ('Garage added: %s [%s]'):format(p.model, p.plate))
-- end)
