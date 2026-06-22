-- [[ Automated Admin Interceptor (Client) ]] --
---@diagnostic disable: undefined-global

local adminGiveKeysCommand = Config.AdminGiveKeysCommand or 'givekeys'

RegisterCommand(adminGiveKeysCommand, function(_, args)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        Notify('Give Keys', 'You must be seated in a vehicle to use this command.', 'error')
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        Notify('Give Keys', 'Unable to determine your vehicle.', 'error')
        return
    end

    if GetPedInVehicleSeat(veh, -1) ~= ped then
        Notify('Give Keys', 'You must be in the driver seat to use /' .. adminGiveKeysCommand .. '.', 'error')
        return
    end

    local plate = GetVehicleNumberPlateText(veh)
    if not plate or plate == '' then
        Notify('Give Keys', 'This vehicle has no license plate.', 'error')
        return
    end

    local targetId = args and tonumber(args[1]) or nil
    TriggerServerEvent('partay_keys:server:RequestAdminGiveKeys', VehToNet(veh), plate, targetId)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    pcall(TriggerEvent, 'chat:addSuggestion', '/' .. adminGiveKeysCommand, 'Assign ownership of your current vehicle to yourself or a target player.', {
        { name = 'id', help = 'Optional server ID. Leave blank to assign to yourself.' }
    })
end)
