Config = {}

Config.Debug = false

-- Commands
Config.Commands = {
    menu = 'starter',
    adminRelease = 'starterrelease',
    adminReset = 'starterreset',
    adminStatus = 'starterstatus'
}

-- Framework permissions allowed to use starter admin commands.
-- Qbox/QBCore commonly use groups like 'admin' and 'god'.
Config.AdminPermissions = {
    'admin',
    'god'
}

-- Default NUI tab for generic starter UI opens such as /starter and greeter auto-open.
-- Valid tabs: 'cityinfo', 'checklist', 'starter', 'jobs'
Config.DefaultStarterUiTab = 'cityinfo'

-- Allows configured admins to leave the starter zone without completing all onboarding tasks.
-- This does not hide the greeter/blip and does not automatically complete starter metadata.
Config.AdminBypassStarterClearance = true

-- Wait this long after the framework says the selected character loaded before starter-zone
-- prompts, greeter logic, and boundary enforcement begin. This prevents multicharacter screens
-- and first-time creation flows from being treated like an active spawned player.
Config.PlayerLoadedActivationDelay = 5000

-- Main requirements. Change these whenever you want.
Config.Requirements = {
    bank = 20000,
    playtimeMinutes = 45,
    requireIdentityEstablished = true,
    requireIdCard = true,
    requireStarterKit = true,
    requireStarterJob = true,
    requireBikeRide = true
}

-- Starter ride requirement. Distance is tracked server-side in starter metadata.
-- Add or remove model names here to control exactly which vehicles count.
Config.BikeRide = {
    milesRequired = 3.0,
    trackOnlyInsideStarterZone = true,
    clientSampleInterval = 1000,
    serverUpdateInterval = 10000,
    maxServerIncrementMeters = 500.0,
    vehicles = {
        'bmx',
        'cruiser',
        'fixter',
        'scorcher',
        'tribike',
        'tribike2',
        'tribike3'
    }
}

-- Zone settings. Players must stay inside this starter boundary until cleared.
-- Boundary checks use x/y only; z is ignored.
Config.Zone = {
    enabled = true,
    type = 'north_line', -- 'north_line', 'polygon', or 'radius'

    -- Teleport destination when an uncleared player leaves the allowed city area.
    teleportBack = vec4(-1032.8386, -2733.7729, 20.3566, 126.0787),

    -- Used only if type = 'radius'.
    center = vec3(3416.0417, -264.5396, 20.2225),
    radius = 150.0,

    -- Used when type = 'north_line'. Players must stay south of this line.
    northBoundary = {
        west = vec3(-3346.3992, 2690.2290, 98.9889),
        east = vec3(3533.7188, 2672.3184, 162.2827)
    },

    -- Used when type = 'polygon'. These are your starter-zone border points.
    points = {
        vec3(3416.0417, -264.5396, 20.2225),
        vec3(1551.5286, 806.6864, 188.2129),
        vec3(534.1197, 1352.6371, 327.6216),
        vec3(-3270.8469, 1378.8151, 10.2955),
        vec3(-934.2855, 7696.5229, 333.5409),
        vec3(4997.3608, 6783.1221, 467.8485)
    },

    -- Lower interval makes the boundary feel like a rubberband instead of a delayed teleport.
    checkInterval = 500,
    warningCooldown = 7000,

    -- true = send player back to their last valid in-zone position.
    -- false = always send player to teleportBack.
    rubberbandToLastSafe = true
}

-- NPC / interaction spots. Requires ox_target if useTarget = true.
Config.Interactions = {
    useTarget = false, -- false = marker + E key. true = ox_target box zones.
    markerDistance = 15.0,
    interactDistance = 2.0,
    points = {}
}

-- Onboarding greeter NPC. Only unreleased starter-zone players can see/use it.
Config.GreeterNpc = {
    enabled = true,
    model = 'a_m_y_business_02',
    coords = vec4(-1104.2035, -2802.3804, 16.7606, 234.0191),
    autoOpenDistance = 3.0,
    autoCloseDistance = 4.5,
    statusRefreshInterval = 15000,
    idleScenario = 'WORLD_HUMAN_CLIPBOARD'
}

-- Starter job counselor. Players target this NPC directly to open the Job Center.
Config.JobCounselor = {
    enabled = true,
    model = 'a_f_y_business_02',
    coords = vec4(-247.2946, -911.1521, 31.8097, 159.9585),
    idleScenario = 'PROP_HUMAN_SEAT_CHAIR',
    targetLabel = 'Speak With Job Counselor',
    requireSeated = false,
    autoStandAfterSelection = false,
    seats = {}
}

-- Map blip shown only to unreleased players who can still use /starter.
Config.StarterBlip = {
    enabled = true,
    label = 'No Love Lost New Citizen Helper',
    coords = vec3(-1032.8386, -2733.7729, 20.3566),
    sprite = 280,
    color = 2,
    scale = 0.85,
    shortRange = false
}

-- cs_license settings. Use item/license names from your cs_license config.
Config.License = {
    resource = 'cs_license',
    idCardItem = 'id_card',
    expireDays = false,
    addItem = true,
    driverLicenseItem = 'driver_license',
    driverLicenseExpireDays = 30,
    giveDriverLicenseWithId = true,

    -- First official ID is free for onboarding. After the ID task is complete,
    -- using the ID option again becomes a paid replacement/reissue.
    firstFree = true,
    replacementFee = 250,
    replacementAccount = 'bank' -- 'bank' or 'cash'
}

-- Starter kit. Players can pick maxChoices from this list one time per character.
Config.StarterKit = {
    allowDuplicateChoices = false,
    allowVehicle = true,
    vehicleGarage = 'Legion Square',
    vehiclePlatePrefix = 'NLL',
    fallbackProfile = 'default',
    requiredItem = 'phone',
    requiredItemLabel = 'Phone',
    -- Optional item amount controls how many inventory items are granted per one UI selection.
    -- Cost, maxQuantity, and starter slot usage still use the player's selected quantity.
    profiles = {
        default = {
            label = 'Standard Starter Pack',
            budget = 4000,
            maxChoices = 6,
            items = {
                { item = 'phone', label = 'Phone', cost = 800, maxQuantity = 1 },
                { item = 'water', label = 'Water', cost = 75, maxQuantity = 6 },
                { item = 'burger', label = 'Burger', cost = 125, maxQuantity = 6 },
                { item = 'bandage', label = 'Bandage', cost = 150, maxQuantity = 6 },
                { item = 'radio', label = 'Radio', cost = 600, maxQuantity = 1 },
                { item = 'repairkit', label = 'Repair Kit', cost = 450, maxQuantity = 2 },
                { item = 'lockpick', label = 'Lockpick', cost = 300, maxQuantity = 2 },
                { item = 'fishingrod', label = 'Fishing Rod', cost = 500, maxQuantity = 1 },
                { item = 'flashlight', label = 'Flashlight', cost = 150, maxQuantity = 1 },
                { item = 'backpack1', label = 'Small Backpack', cost = 900, maxQuantity = 1 },
                { item = 'sandwich', label = 'Sandwich', cost = 125, maxQuantity = 6 },
                { item = 'coffee', label = 'Coffee', cost = 100, maxQuantity = 6 },
                { item = 'toolkit', label = 'Toolkit', cost = 650, maxQuantity = 1 },
                { item = 'cleaningkit', label = 'Cleaning Kit', cost = 250, maxQuantity = 2 },
                { item = 'notepad', label = 'Notepad', cost = 75, maxQuantity = 1 }
            },
            vehicles = {
                { model = 'blista', label = 'Blista Compact', cost = 2500, countsAsChoices = 1 },
                { model = 'panto', label = 'Panto', cost = 2000, countsAsChoices = 1 },
                { model = 'asea', label = 'Asea', cost = 3000, countsAsChoices = 1 }
            }
        },
        male = {
            label = 'Male Starter Pack',
            budget = 2500,
            maxChoices = 6,
            items = {
                { item = 'phone', label = 'Phone', cost = 1000, maxQuantity = 1 },
                { item = 'bmx', label = 'BMX Bike', cost = 600, maxQuantity = 1 },
                { item = 'repairkit', label = 'Repair Kit', cost = 450, maxQuantity = 2 },
                { item = 'djs_bowl_buffalochicken', label = 'Buffalo Chicken Bowl', cost = 35, maxQuantity = 5 },
                { item = 'djs_togo_kungpaochicken', label = 'Kungpao Chicken', cost = 35, maxQuantity = 5 },
                { item = 'djs_wings_louisianarub', label = 'Wings louisiana rub', cost = 35, maxQuantity = 5 },
                { item = 'djs_cheeseburger_double', label = 'Double Cheeseburger', cost = 35, maxQuantity = 5 },
                { item = 'djs_milkshake_strawberry', label = 'Strawberry Milkshake', cost = 35, maxQuantity = 5 },
                { item = 'djs_bite_cherryicee', label = 'Cherry Icee', cost = 35, maxQuantity = 5 },
                { item = 'djs_prop_glasschocolatemilk', label = 'Glass of Chocolate Milk', cost = 35, maxQuantity = 5 },
                { item = 'djs_icecreamcookie_chocolatechunk', label = 'Ice Cream Chocolate Chunk Cookie', cost = 35, maxQuantity = 5 },
                { item = 'djs_bowl_oreo', label = 'Oreo Bowl', cost = 35, maxQuantity = 5 },
                { item = 'djs_plate_lobster', label = 'Plate Of Lobster', cost = 35, maxQuantity = 5 },
                { item = 'midori_12', label = '24 Pack Beer', cost = 65, maxQuantity = 5 },
                { item = 'devkit_rackwoods_sweet', label = 'Rackwoods Sweet', cost = 15, maxQuantity = 5 },
                { item = 'georgia_pie', label = 'Georgia Pie', cost = 35, maxQuantity = 5 },
                { item = 'midori_12', label = '24 Pack Beer', cost = 65, maxQuantity = 5 },
                { item = 'WEAPON_DESTROYER2', label = 'Paintball Gun', cost = 650, maxQuantity = 2 },
                { item = 'ammo-pball', label = 'Paintball Ammo', cost = 5, maxQuantity = 6, amount = 50 },
                { item = 'outfit_bag', label = 'Outfitbag', cost = 900, maxQuantity = 1 },
                { item = 'lockpick', label = 'Lockpick', cost = 300, maxQuantity = 2 },
                { item = 'bandage', label = 'Bandage', cost = 150, maxQuantity = 6 },
                { item = 'water', label = 'Water', cost = 75, maxQuantity = 6 },
                { item = 'illegal_tablet', label = 'Illegal Tablet', cost = 2400, maxQuantity = 1 },
                { item = 'burger', label = 'Burger', cost = 125, maxQuantity = 6 },
                { item = 'backpack1', label = 'Small Backpack', cost = 900, maxQuantity = 1 }
            },
            vehicles = {
                { model = 'blista', label = 'Blista Compact', cost = 2500, countsAsChoices = 1 },
                { model = 'asea', label = 'Asea', cost = 3000, countsAsChoices = 1 }
            }
        },
        female = {
            label = 'Female Starter Pack',
            theme = 'female',
            budget = 5000,
            maxChoices = 10,
            bonus = {
                enabled = true,
                label = 'Welcome Bonus',
                items = {
                    { item = 'layered_wig', label = 'MovieStar wig', amount = 100 },
                    { item = 'baby_oil', label = 'Baby Oil', amount = 100 },
                    { item = 'pink_rose', label = 'Pink Rose', amount = 2 },
                    { item = 'money', label = 'Bunch of cash', amount = 1500 },
                    { item = 'cleaningkit', label = 'Cleaning Kit', amount = 1 }
                }
            },
            items = {
                { item = 'phone', label = 'Phone', cost = 1000, maxQuantity = 1 },
                { item = 'baddie_cam', label = 'Only Cam', cost = 1800, maxQuantity = 1 },
                { item = 'djs_bowl_buffalochicken', label = 'Buffalo Chicken Bowl', cost = 35, maxQuantity = 5 },
                { item = 'djs_togo_kungpaochicken', label = 'Kungpao Chicken', cost = 35, maxQuantity = 5 },
                { item = 'djs_wings_louisianarub', label = 'Wings louisiana rub', cost = 35, maxQuantity = 5 },
                { item = 'djs_cheeseburger_double', label = 'Double Cheeseburger', cost = 35, maxQuantity = 5 },
                { item = 'djs_milkshake_strawberry', label = 'Strawberry Milkshake', cost = 35, maxQuantity = 5 },
                { item = 'djs_bite_cherryicee', label = 'Cherry Icee', cost = 35, maxQuantity = 5 },
                { item = 'djs_prop_glasschocolatemilk', label = 'Glass of Chocolate Milk', cost = 35, maxQuantity = 5 },
                { item = 'djs_icecreamcookie_chocolatechunk', label = 'Ice Cream Chocolate Chunk Cookie', cost = 35, maxQuantity = 5 },
                { item = 'djs_bowl_oreo', label = 'Oreo Bowl', cost = 35, maxQuantity = 5 },
                { item = 'djs_plate_lobster', label = 'Plate Of Lobster', cost = 35, maxQuantity = 5 },
                { item = 'midori_12', label = '24 Pack Beer', cost = 65, maxQuantity = 5 },
                { item = 'devkit_rackwoods_sweet', label = 'Rackwoods Sweet', cost = 15, maxQuantity = 5 },
                { item = 'georgia_pie', label = 'Georgia Pie', cost = 35, maxQuantity = 5 },
                { item = 'bandage', label = 'Bandage', cost = 150, maxQuantity = 6 },
                { item = 'WEAPON_DESTROYER2', label = 'Paintball Gun', cost = 650, maxQuantity = 2 },
                { item = 'ammo-pball', label = 'Paintball Ammo', cost = 5, maxQuantity = 6, amount = 50 },
                { item = 'bmx', label = 'BMX Bike', cost = 600, maxQuantity = 1 },
                { item = 'illegal_tablet', label = 'Illegal Tablet', cost = 2400, maxQuantity = 1 },
                { item = 'cleaningkit', label = 'Cleaning Kit', cost = 250, maxQuantity = 2 },
                { item = 'outfit_bag', label = 'Outfitbag', cost = 900, maxQuantity = 1 },
                { item = 'water', label = 'Water', cost = 15, maxQuantity = 6 }
            },
            vehicles = {
                { model = 'panto', label = 'Panto', cost = 2000, countsAsChoices = 1 },
                { model = 'blista', label = 'Blista Compact', cost = 2500, countsAsChoices = 1 }
            }
        }
    }
}

-- Starter vehicle pickup behavior after a player chooses a starter vehicle.
Config.StarterVehiclePickup = {
    spawnOnClaim = true,
    coords = vec4(-1034.4517, -2729.4558, 20.2781, 235.0148),
    searchRadius = 18.0,
    searchStep = 4.0,
    fuel = 25.0,
    fuelResource = 'rcore_fuel',
    engineHealth = 1000.0,
    bodyHealth = 1000.0,
    spawnLocked = true,
    blip = {
        enabled = true,
        label = 'Your Starter Vehicle',
        sprite = 225,
        color = 2,
        scale = 0.85,
        route = true
    },
    keys = {
        enabled = true,
        resource = 'wasabi_carlock',
        serverExport = 'GiveKey',
        serverEvent = nil,
        clientExport = 'GiveKey',
        clientEvent = 'wasabi_carlock:client:GiveKey'
    }
}

-- Job names MUST match qbx_core shared/jobs.lua names.
Config.AllowedStarterJobs = {
    garbage = {
        label = 'Garbage Collector',
        icon = '&#128465;',
        description = 'Collect trash routes around the city and help keep No Love Lost clean. Good starter work with steady local routes.',
        waypoint = vec3(-331.5818, -1542.0223, 26.6605),
        starterItems = {
            { item = 'garbage_tablet', amount = 1 },
            { item = 'water', amount = 2 }
        },
        stats = {
            { value = '$', label = 'Route pay' },
            { value = 'LOW', label = 'Risk' },
            { value = 'City', label = 'Area' }
        }
    },
    logistics = {
        label = 'Logistics',
        icon = '&#128230;',
        description = 'Move freight, load deliveries, and work warehouse jobs around the dockside logistics yard.',
        waypoint = vec3(-1092.431, -2103.217, 15.192),
        starterItems = {
            { item = 'water', amount = 2 }
            --{ item = 'notepad', amount = 1 }
        },
        stats = {
            { value = '$', label = 'Per job' },
            { value = 'LOW', label = 'Risk' },
            { value = 'Docks', label = 'Area' }
        }
    },
    windowcleaner = {
        label = 'Window Cleaner',
        icon = '&#129529;',
        description = 'Clean building windows around the city. Simple entry-level work with company equipment provided on site.',
        waypoint = vec3(-1243.98, -1240.71, 11.03),
        starterItems = {
            { item = 'water', amount = 2 },
            { item = 'cleaningkit', amount = 1 }
        },
        stats = {
            { value = '$', label = 'Per job' },
            { value = 'LOW', label = 'Risk' },
            { value = 'City', label = 'Area' }
        }
    },
    builder = {
        label = 'Builder',
        icon = '&#128679;',
        description = 'Join construction crews around the city for welding, concrete, and site work. Available immediately inside the city.',
        waypoint = vec3(926.47, -1560.25, 30.74),
        starterItems = {
            { item = 'water', amount = 2 },
            { item = 'bandage', amount = 1 }
        },
        stats = {
            { value = '$', label = 'Site pay' },
            { value = 'LOW', label = 'Risk' },
            { value = 'City', label = 'Area' }
        }
    },
    miner = {
        label = 'Miner',
        icon = '&#9935;',
        description = 'Extract ore and minerals from the Alamo Sea mines. High payout but physically demanding work.',
        waypoint = vec3(2445.14, 1532.14, 39.89),
        starterItems = {
            { item = 'water', amount = 2 },
            { item = 'bandage', amount = 1 }
        },
        stats = {
            { value = '$800-$1200', label = 'Per Completion' },
            { value = 'MED', label = 'Risk' },
            { value = 'Alamo', label = 'Area' }
        }
    },
    farmer = {
        label = 'Farmer',
        icon = '&#127806;',
        description = 'Work fields and farm routes outside the city once your new citizen clearance is complete.',
        locked = true,
        lockedDescription = 'Unlocks after you are cleared to leave the city.',
        waypoint = vec3(2442.43, 4975.88, 46.81),
        stats = {
            { value = '$', label = 'Harvest pay' },
            { value = 'LOW', label = 'Risk' },
            { value = 'Sandy', label = 'Area' }
        }
    },
    lumberjack = {
        label = 'Lumberjack',
        icon = '&#129683;',
        description = 'Cut and deliver timber from rural work sites after city departure clearance.',
        locked = true,
        lockedDescription = 'Unlocks after you are cleared to leave the city.',
        waypoint = vec3(-567.52, 5253.13, 70.49),
        stats = {
            { value = '$', label = 'Load pay' },
            { value = 'LOW', label = 'Risk' },
            { value = 'Rural', label = 'Area' }
        }
    },
    oilrig = {
        label = 'Oil Rig',
        icon = '&#128738;',
        description = 'Offshore and route-based oil work becomes available after starter city restrictions are lifted.',
        locked = true,
        lockedDescription = 'Unlocks after you are cleared to leave the city.',
        waypoint = vec3(1683.34, -1650.19, 112.55),
        stats = {
            { value = '$$', label = 'Contract pay' },
            { value = 'MED', label = 'Risk' },
            { value = 'Routes', label = 'Area' }
        }
    },
    trucker = {
        label = 'Trucker',
        icon = '&#128666;',
        description = 'Long-haul routes may leave city limits, so trucking unlocks after starter clearance.',
        locked = true,
        lockedDescription = 'Unlocks after you are cleared to leave the city.',
        waypoint = vec3(1196.74, -3253.68, 7.1),
        stats = {
            { value = '$$', label = 'Route pay' },
            { value = 'LOW', label = 'Risk' },
            { value = 'Routes', label = 'Area' }
        }
    }
}

-- How job selection works.
-- If true, starter_zone sets the qbx job directly when chosen.
-- If false, the menu only explains which jobs are allowed and checks current job.
Config.SetJobFromMenu = true
Config.DefaultJobGrade = 0

-- Keep false for production. Starter job scripts should call the server export
-- CompleteStarterShift(source, jobName) after their own server-side work validation.
Config.AllowClientCompleteShiftEvent = false

-- Metadata key used on the player.
Config.MetadataKey = 'starter'
