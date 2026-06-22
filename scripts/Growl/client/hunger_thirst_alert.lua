local function playStomachGrowl()
    SendNUIMessage({
        transactionType = 'playSound',
        transactionFile = Config.SoundPath,
        transactionVolume = Config.volume,
    })
end


RegisterNetEvent('pm_growlsound:playSound')
AddEventHandler('pm_growlsound:playSound', function()
    playStomachGrowl()
end)

CreateThread(function()
    while true do
        Wait(Config.CheckInterval)

        local hunger = LocalPlayer.state.hunger or 100
        local thirst = LocalPlayer.state.thirst or 100

        if hunger < Config.HungerThreshold or thirst < Config.ThirstThreshold then
            TriggerServerEvent('pm_growlsound:notifyNearbyPlayers')
        end
    end
end)
