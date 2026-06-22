local lastGrowl = {}

local function isPlayerHungryOrThirsty(source)
    local playerState = Player(source).state
    local hunger = playerState.hunger or 100
    local thirst = playerState.thirst or 100

    return hunger < Config.HungerThreshold or thirst < Config.ThirstThreshold
end

RegisterNetEvent('pm_growlsound:notifyNearbyPlayers', function()
    local sourcePlayer = source
    local now = GetGameTimer()

    if lastGrowl[sourcePlayer] and now - lastGrowl[sourcePlayer] < Config.Cooldown then return end
    if not isPlayerHungryOrThirsty(sourcePlayer) then return end

    local sourcePed = GetPlayerPed(sourcePlayer)
    if not sourcePed or sourcePed == 0 then return end

    local sourceCoords = GetEntityCoords(sourcePed)
    lastGrowl[sourcePlayer] = now

    for _, playerId in ipairs(GetPlayers()) do
        local targetPed = GetPlayerPed(playerId)

        if targetPed and targetPed ~= 0 then
            local targetCoords = GetEntityCoords(targetPed)

            if #(sourceCoords - targetCoords) <= Config.SoundRange then
                TriggerClientEvent('pm_growlsound:playSound', playerId)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastGrowl[source] = nil
end)
