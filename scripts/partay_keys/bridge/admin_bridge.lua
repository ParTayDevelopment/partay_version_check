-- [[ Server-Side Admin Spawn Interceptor ]] --
-- Natively listens to framework spawn events to grant temporary access.

if not IsDuplicityVersion() then return end

local function TrimPlate(plate)
    return plate and plate:gsub('^%s*(.-)%s*$', '%1') or nil
end

local function GrantAdminTemporaryAccess(src, netId)
    Wait(1000) -- Allow network sync buffer
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return end
    
    local plate = TrimPlate(GetVehicleNumberPlateText(veh))
    if not plate or plate == '' then return end

    local possessionId = Bridge.GetCitizenID(src) or ('ADMIN_' .. math.random(10000, 99999))

    Entity(veh).state:set('possession_id', possessionId, true)
    Entity(veh).state:set('isStolen', false, true)

    Notify(src, 'Admin Override', 'Temporary vehicle access granted. Use /givekeys [id] to assign ownership.', 'success')

    exports.partay_keys:SendAuditLog('Admin Spawn Access', ('Admin %s received temporary access for spawned vehicle [%s]'):format(GetPlayerName(src), plate), 'info')
end

-- 1. txAdmin Native Hook
AddEventHandler('txAdmin:events:spawnedVehicle', function(eventData)
    if type(eventData) ~= 'table' or not eventData.netid or not eventData.author then return end
    GrantAdminTemporaryAccess(eventData.author, eventData.netid)
end)

-- Explicit admin spawn hooks. Dealership seating is handled by the purchase bridge,
-- not by client seat detection, so these only react to actual spawn events.
RegisterNetEvent('QBCore:Server:SpawnVehicle', function(netId)
    local src = source
    if IsPlayerAceAllowed(src, 'command.car') or IsPlayerAceAllowed(src, 'group.admin') then
        TriggerEvent('partay_keys:server:RequestAdminSpawnAccess', netId, src)
    end
end)

RegisterNetEvent('qbx_core:server:spawnVehicle', function(netId)
    local src = source
    if IsPlayerAceAllowed(src, 'command.car') or IsPlayerAceAllowed(src, 'group.admin') then
        TriggerEvent('partay_keys:server:RequestAdminSpawnAccess', netId, src)
    end
end)
