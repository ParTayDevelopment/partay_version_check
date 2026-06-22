local detectorVisible = false
local detectorInstalled = false
local muted = false
local volume = GetResourceKvpInt('radar_detector_volume')
local currentVehicle = 0
local currentPlate = nil
local moveMode = false
local lastAlert = 0

if volume <= 0 then volume = Config.DefaultVolume end

local function getDefaultUiSettings()
    return {
        detector = {
            left = Config.UI.defaultPosition.left,
            top = Config.UI.defaultPosition.top
        }
    }
end

local function notify(message, notifyType)
    lib.notify({
        title = Config.Item.label,
        description = message,
        type = notifyType or 'inform',
        position = Config.Notifications.position
    })
end

local function getPlate(vehicle)
    if vehicle == 0 then return nil end
    return RadarDetector.TrimPlate(GetVehicleNumberPlateText(vehicle))
end

lib.callback.register('RadarDetector:client:getVehicleClass', function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then return nil end

    return GetVehicleClass(vehicle)
end)

local function sendDisplay(action, extra)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local speed = 0

    if vehicle ~= 0 then
        local multiplier = Config.SpeedUnits == 'KMH' and 3.6 or 2.236936
        speed = math.floor(GetEntitySpeed(vehicle) * multiplier + 0.5)
    end

    local data = {
        action = action,
        speed = speed,
        units = Config.SpeedUnits
    }

    for key, value in pairs(extra or {}) do
        data[key] = value
    end

    SendNUIMessage(data)
end

local function playSound(soundName)
    if muted or not soundName then return end

    SendNUIMessage({
        transactionType = 'playSound',
        transactionFile = soundName,
        transactionVolume = RadarDetector.Clamp(volume, 1, 100) / 100
    })
end

local function openDetector(startup)
    if not detectorInstalled then return end

    detectorVisible = true
    sendDisplay('open')

    local saved = GetResourceKvpString('radar_detector_ui')
    if saved then
        local ok, decoded = pcall(json.decode, saved)
        if ok and decoded then
            SendNUIMessage({ _type = 'loadUiSettings', data = decoded })
        else
            DeleteResourceKvp('radar_detector_ui')
            SendNUIMessage({ _type = 'setUiDefaults', data = getDefaultUiSettings() })
        end
    else
        SendNUIMessage({ _type = 'setUiDefaults', data = getDefaultUiSettings() })
    end

    if startup then playSound(Config.Detector.sounds.startup) end
end

local function requestRemoval()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        notify(RadarDetector.Locale('install_no_vehicle'), 'error')
        return
    end

    if Config.Install.requireDriverSeat and GetPedInVehicleSeat(GetVehiclePedIsIn(ped, false), -1) ~= ped then
        notify(RadarDetector.Locale('remove_not_driver'), 'error')
        return
    end

    local completed = lib.progressCircle({
        duration = Config.Install.removeTime,
        label = RadarDetector.Locale('remove_started'),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    })

    if completed then
        TriggerServerEvent('RadarDetector:server:remove')
    end
end

local function closeDetector()
    detectorVisible = false
    sendDisplay('close')
end

local function imageForStrength(strength)
    strength = RadarDetector.Clamp(strength, 1, 5)
    local suffix = 'F'

    if Config.Detector.imageSet == 'R7' then
        return ('images/R7/%s%s.png'):format(strength, suffix)
    end

    return ('images/%s%s.png'):format(strength, suffix)
end

RegisterNetEvent('RadarDetector:client:installed', function(plate)
    currentPlate = plate
    detectorInstalled = true
    notify(RadarDetector.Locale('detector_online'), 'success')
    openDetector(true)
end)

RegisterNetEvent('RadarDetector:client:removed', function()
    detectorInstalled = false
    closeDetector()
end)

RegisterNetEvent('RadarDetector:client:vehicleStatus', function(installed)
    detectorInstalled = installed == true

    if detectorInstalled then
        openDetector(true)
    else
        closeDetector()
    end
end)

RegisterNetEvent('RadarDetector:client:radarAlert', function(data)
    if not detectorInstalled or not detectorVisible then return end

    if not data or not data.active then
        sendDisplay('detect', { signal = Config.Detector.defaultImage })
        return
    end

    local gameTime = GetGameTimer()
    local strength = data.strength or 1
    sendDisplay('detect', { signal = imageForStrength(strength) })

    if gameTime - lastAlert >= Config.Detector.alertCooldownMs then
        lastAlert = gameTime
        playSound(Config.Detector.sounds.kaBand)
    end
end)

RegisterCommand(Config.Command, function(_, args)
    local subcommand = (args[1] or 'help'):lower()

    if subcommand == 'show' then
        openDetector(false)
        return
    end

    if subcommand == 'hide' then
        closeDetector()
        notify(RadarDetector.Locale('detector_offline'), 'inform')
        return
    end

    if subcommand == 'move' then
        if not Config.UI.allowPlayerMove then return end
        if not detectorVisible then openDetector(false) end
        moveMode = true
        SetNuiFocus(true, true)
        notify(RadarDetector.Locale('detector_move'), 'inform')
        return
    end

    if subcommand == 'reset' then
        DeleteResourceKvp('radar_detector_ui')
        SendNUIMessage({ _type = 'setUiDefaults', data = getDefaultUiSettings() })
        if not detectorVisible then openDetector(false) end
        notify(RadarDetector.Locale('detector_reset'), 'success')
        return
    end

    if subcommand == 'mute' then
        muted = not muted
        SendNUIMessage({ transactionType = 'stop' })
        notify(RadarDetector.Locale(muted and 'detector_muted' or 'detector_unmuted'), 'inform')
        return
    end

    if subcommand == 'vol' or subcommand == 'volume' then
        volume = RadarDetector.Clamp(args[2], 1, 100)
        SetResourceKvpInt('radar_detector_volume', volume)
        SendNUIMessage({
            transactionType = 'vol',
            transactionVolume = volume / 100
        })
        notify(RadarDetector.Locale('detector_volume', volume), 'success')
        return
    end

    if subcommand == 'remove' then
        requestRemoval()
        return
    end

    notify(RadarDetector.Locale('command_help', Config.Command), 'inform')
end, false)

RegisterNUICallback('close', function(_, cb)
    moveMode = false
    SetNuiFocus(false, false)
    cb(true)
end)

RegisterNUICallback('mute', function(_, cb)
    ExecuteCommand(Config.Command .. ' mute')
    cb(true)
end)

RegisterNUICallback('saveUiData', function(data, cb)
    if moveMode and data then
        SetResourceKvp('radar_detector_ui', json.encode(data))
    end

    moveMode = false
    SetNuiFocus(false, false)
    cb(true)
end)

CreateThread(function()
    while true do
        Wait(1000)

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= currentVehicle then
            currentVehicle = vehicle
            currentPlate = getPlate(vehicle)

            if vehicle ~= 0 and currentPlate then
                TriggerServerEvent('RadarDetector:server:checkVehicle', VehToNet(vehicle))
            else
                detectorInstalled = false
                closeDetector()
            end
        end

        if detectorVisible then
            sendDisplay('speed')
        end
    end
end)

CreateThread(function()
    if not Config.Target.enabled then return end
    if GetResourceState(Config.Target.resource) ~= 'started' then return end

    exports.ox_target:addGlobalVehicle({
        {
            name = 'radar_detector_remove',
            label = 'Remove radar detector',
            icon = 'fa-solid fa-satellite-dish',
            distance = 2.0,
            canInteract = function(entity)
                return Entity(entity).state.radarDetectorInstalled == true
            end,
            onSelect = function()
                requestRemoval()
            end
        }
    })
end)
