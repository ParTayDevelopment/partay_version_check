-- Add this client-side inside wk_wars2x where RADAR is available.
-- The radar detector resource validates job/vehicle server-side before using the signal.

local sentXmit = false

CreateThread(function()
    while true do
        Wait(500)

        local ped = PlayerPedId()
        local status = IsPedInAnyVehicle(ped, false) and RADAR and RADAR:IsEitherAntennaOn() or false

        if sentXmit ~= status then
            sentXmit = status
            TriggerServerEvent('detector:xmit:wk', status)
        end
    end
end)
