Config = {}

Config.ResourceName = 'RadarDetector'

Config.Framework = 'qbox' -- qbox, qbcore, esx, standalone
Config.Inventory = 'ox_inventory'
Config.Target = {
    enabled = true,
    resource = 'ox_target'
}

Config.Locale = 'en'

Config.Item = {
    name = 'radar_detector',
    label = 'Radar Detector',
    removeOnInstall = true,
    returnOnRemove = true,
    metadata = {
        model = 'R8',
        serialPrefix = 'RD',
        condition = 100
    }
}

Config.Command = 'detector'
Config.SpeedUnits = 'MPH' -- MPH or KMH
Config.DefaultVolume = 20 -- 1-100

Config.UI = {
    defaultPosition = {
        left = '2%',
        top = '6%'
    },
    allowPlayerMove = true
}

Config.Install = {
    requireDriverSeat = true,
    installTime = 8000,
    removeTime = 6000,
    allowAnyVehicle = true,
    allowedVehicleClasses = {}, -- empty allows all
    blockedVehicleClasses = { 13, 14, 15, 16, 21 }, -- cycles, boats, helis, planes, trains
    requireOwnership = false, -- left false because you asked for install on any vehicle
    cooldownMs = 2500
}

Config.Persistence = {
    enabled = true,
    tableName = 'radar_detector_vehicles'
}

Config.Detector = {
    range = 650.0,
    alertCooldownMs = 2200,
    defaultImage = 'images/DefaultState.png',
    laserImage = 'images/Laser.png',
    imageSet = 'R8', -- R8 uses root images/sounds, R7 uses images/R7
    sounds = {
        startup = 'SelfTest',
        kaBand = 'KABand',
        laser = 'RedlineLaser'
    }
}

Config.Radars = {
    wk_wars2x = {
        enabled = true,
        eventName = 'detector:xmit:wk',
        requireVehicle = true,
        requireAllowedJob = true,
        allowedJobs = {
            police = 0,
            sheriff = 0,
            state = 0
        }
    }
}

Config.Logging = {
    enabled = false,
    webhook = '',
    logInstalls = true,
    logRemovals = true,
    logBlockedAttempts = true
}

Config.Notifications = {
    position = 'top'
}
