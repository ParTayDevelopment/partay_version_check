Config = {}

Config.Debug = false
Config.JobName = 'nolovelostairlines'
Config.BoardingPassItem = 'boarding_pass'
Config.PassportItem = 'passport'
Config.MoneyAccount = 'bank'

Config.Database = {
    autoCreateTables = true
}

Config.Airline = {
    name = 'No Love Lost Airways',
    code = 'NLL',
    startingBalance = 0,
    startingReputation = 50
}

Config.StaffGrades = {
    createFlight = 1,
    claimFlight = 0,
    operateBoarding = 0,
    cancelFlight = 2
}

Config.ZoneCreator = {
    command = 'airzone',
    defaultThickness = 35.0,
    defaultRadius = 40.0,
    defaultBoxLength = 70.0,
    defaultBoxWidth = 25.0,
    ghostAlpha = 120,
    defaultBoardingRadius = 28.0,
    raycastDistance = 900.0
}

Config.Creator = {
    command = 'aircreator',
    requireAirlineJob = true,
    minimumGrade = 2,
    acePermission = 'command.aircreator',
    qbxPermissions = { 'god', 'admin' },
    amznPermission = 'adminmenu',
    textUiPosition = 'right-center',
    noclipSpeed = 1.8,
    noclipFastSpeed = 7.0,
    raycastMarkerSize = 0.35,
    defaultBlip = {
        enabled = true,
        sprite = 90,
        color = 3,
        scale = 0.85
    }
}

Config.ATC = {
    radioCommand = 'airradio',
    radioKey = 'Z',
    intentReminderSeconds = 35,
    intentReminderEscalateAfter = 2,
    intentMinimumAirborneAltitude = 30.0,
    holdShortSeconds = 5,
    landingConfirmSeconds = 3,
    takeoffConfirmAltitude = 30.0,
    landingConfirmAltitude = 12.0,
    landingConfirmSpeed = 45.0,
    touchdownConfirmSpeed = 85.0,
    frequencies = {
        lsia = {
            tower = '118.100',
            ground = '121.900'
        },
        sandy = {
            tower = '122.800'
        },
        grapeseed = {
            tower = '122.700'
        },
        cayo = {
            tower = '118.500'
        },
        zancudo = {
            tower = '126.200'
        }
    }
}

Config.DispatchTablet = {
    enabled = true,
    nuiAction = 'businessTabletOpen',
    item = 'pilot_tablet'   -- ox_inventory item that opens the tablet anywhere
}

Config.Airspace = {
    useVolumes = true,
    allowRadiusFallback = false
}

Config.AirspaceVolumes = {
    {
        id = 'lsia_tower_core',
        label = 'LSIA Tower Core',
        class = 'D',
        facility = 'LSIA Tower',
        airport = 'lsia',
        frequency = '118.100',
        floor = 0.0,
        ceiling = 550.0,
        priority = 10,
        polygon = {
            vec2(-2645.0, -3756.2),
            vec2(-805.0, -4158.8),
            vec2(690.0, -2951.2),
            vec2(460.0, -1283.8),
            vec2(-1495.0, -1053.8),
            vec2(-3105.0, -2146.2)
        }
    },
    {
        id = 'lsia_class_b_shelf_1',
        label = 'LSIA Class B Shelf 1',
        class = 'B',
        facility = 'LSIA Approach',
        airport = 'lsia',
        frequency = '124.200',
        floor = 550.0,
        ceiling = 850.0,
        priority = 20,
        polygon = {
            vec2(-3716.2, -4987.5),
            vec2(-783.8, -5562.5),
            vec2(1746.3, -3435.0),
            vec2(1343.8, -560.0),
            vec2(-1703.8, -215.0),
            vec2(-4636.2, -1940.0)
        }
    },
    {
        id = 'lsia_class_b_shelf_2',
        label = 'LSIA Class B Shelf 2',
        class = 'B',
        facility = 'LSIA Approach',
        airport = 'lsia',
        frequency = '124.200',
        floor = 850.0,
        ceiling = 2850.0,
        priority = 30,
        polygon = {
            vec2(-5771.2, -6466.2),
            vec2(-538.8, -7616.2),
            vec2(3773.8, -4223.8),
            vec2(3083.8, 951.2),
            vec2(-2091.2, 1468.7),
            vec2(-6806.2, -1463.8)
        }
    },
    {
        id = 'lsia_class_b_shelf_3',
        label = 'LSIA Class B Shelf 3',
        class = 'B',
        facility = 'LSIA Approach',
        airport = 'lsia',
        frequency = '124.200',
        floor = 2850.0,
        ceiling = 5350.0,
        priority = 40,
        polygon = {
            vec2(-8510.0, -8305.0),
            vec2(-115.0, -9340.0),
            vec2(6210.0, -4970.0),
            vec2(5175.0, 2850.0),
            vec2(-2760.0, 3425.0),
            vec2(-9200.0, -1060.0)
        }
    },
    {
        id = 'sandy_tower',
        label = 'Sandy Tower',
        class = 'D',
        facility = 'Sandy Tower',
        airport = 'sandy',
        frequency = '122.800',
        floor = 0.0,
        ceiling = 400.0,
        priority = 10,
        polygon = {
            vec2(850.0, 2600.0),
            vec2(2150.0, 2550.0),
            vec2(2550.0, 3450.0),
            vec2(1750.0, 4100.0),
            vec2(650.0, 3600.0)
        }
    },
    {
        id = 'sandy_shelf_1',
        label = 'Sandy Shelf 1',
        class = 'D',
        facility = 'Sandy Tower',
        airport = 'sandy',
        frequency = '122.800',
        floor = 400.0,
        ceiling = 700.0,
        priority = 20,
        polygon = {
            vec2(665.0, 2435.0),
            vec2(2290.0, 2372.5),
            vec2(2790.0, 3497.5),
            vec2(1790.0, 4310.0),
            vec2(415.0, 3685.0)
        }
    },
    {
        id = 'sandy_shelf_2',
        label = 'Sandy Shelf 2',
        class = 'D',
        facility = 'Sandy Tower',
        airport = 'sandy',
        frequency = '122.800',
        floor = 700.0,
        ceiling = 1700.0,
        priority = 30,
        polygon = {
            vec2(443.0, 2237.0),
            vec2(2458.0, 2159.5),
            vec2(3078.0, 3554.5),
            vec2(1838.0, 4562.0),
            vec2(133.0, 3787.0)
        }
    },
    {
        id = 'grapeseed_tower',
        label = 'Grapeseed Tower',
        class = 'D',
        facility = 'Grapeseed Tower',
        airport = 'grapeseed',
        frequency = '122.700',
        floor = 0.0,
        ceiling = 350.0,
        priority = 10,
        polygon = {
            vec2(1700.0, 4400.0),
            vec2(2450.0, 4300.0),
            vec2(2650.0, 5050.0),
            vec2(2050.0, 5350.0),
            vec2(1550.0, 5000.0)
        }
    },
    {
        id = 'grapeseed_shelf_1',
        label = 'Grapeseed Shelf 1',
        class = 'D',
        facility = 'Grapeseed Tower',
        airport = 'grapeseed',
        frequency = '122.700',
        floor = 350.0,
        ceiling = 650.0,
        priority = 20,
        polygon = {
            vec2(1605.0, 4295.0),
            vec2(2542.5, 4170.0),
            vec2(2792.5, 5107.5),
            vec2(2042.5, 5482.5),
            vec2(1417.5, 5045.0)
        }
    },
    {
        id = 'grapeseed_shelf_2',
        label = 'Grapeseed Shelf 2',
        class = 'D',
        facility = 'Grapeseed Tower',
        airport = 'grapeseed',
        frequency = '122.700',
        floor = 650.0,
        ceiling = 1500.0,
        priority = 30,
        polygon = {
            vec2(1491.0, 4169.0),
            vec2(2653.5, 4014.0),
            vec2(2963.5, 5176.5),
            vec2(2033.5, 5641.5),
            vec2(1258.5, 5099.0)
        }
    },
    {
        id = 'north_county_approach',
        label = 'North County Approach',
        class = 'E',
        facility = 'North County Approach',
        airport = 'sandy',
        frequency = '124.800',
        floor = 1500.0,
        ceiling = 4500.0,
        priority = 50,
        polygon = {
            vec2(-1600.0, 1800.0),
            vec2(3700.0, 1600.0),
            vec2(3800.0, 6500.0),
            vec2(-1200.0, 7000.0)
        }
    },
    {
        id = 'cayo_tower',
        label = 'Cayo Tower',
        class = 'D',
        facility = 'Cayo Tower',
        airport = 'cayo',
        frequency = '118.500',
        floor = 0.0,
        ceiling = 1500.0,
        priority = 10,
        polygon = {
            vec2(3500.0, -5600.0),
            vec2(5600.0, -5600.0),
            vec2(6000.0, -4050.0),
            vec2(4300.0, -3300.0),
            vec2(3100.0, -4200.0)
        }
    },
    {
        id = 'cayo_approach',
        label = 'Cayo Approach',
        class = 'E',
        facility = 'Cayo Approach',
        airport = 'cayo',
        frequency = '124.500',
        floor = 1500.0,
        ceiling = 4500.0,
        priority = 50,
        polygon = {
            vec2(2200.0, -7000.0),
            vec2(7000.0, -7000.0),
            vec2(7200.0, -2500.0),
            vec2(3100.0, -2100.0),
            vec2(1800.0, -4200.0)
        }
    },
    {
        id = 'san_andreas_center',
        label = 'San Andreas Center',
        class = 'E',
        facility = 'San Andreas Center',
        frequency = '128.700',
        floor = 4500.0,
        ceiling = 7500.0,
        priority = 100,
        polygon = {
            vec2(-9000.0, -9000.0),
            vec2(9000.0, -9000.0),
            vec2(9000.0, 9000.0),
            vec2(-9000.0, 9000.0)
        }
    }
}

Config.Navigation = {
    enabled = true,
    resource = 'sleepless_waypoints',
    showLegacyMarkers = false,
    highlightAssignedRunway = true,
    drawDistance = 2500.0,
    fadeDistance = 2100.0,
    sizes = {
        hold = 0.75,
        runway = 0.9,
        gate = 0.7
    },
    colors = {
        taxi = '#f4d35e',
        takeoff = '#ff4d4d',
        runway = '#4aa3ff',
        approach = '#65d6ff',
        gate = '#b47cff'
    }
}

Config.TicketClasses = {
    basic = {
        label = 'Basic',
        priceMultiplier = 1.0,
        boardingGroup = 40,
        pilotPayoutMultiplier = 1.0
    },
    first_class = {
        label = 'First Class',
        priceMultiplier = 1.8,
        boardingGroup = 20,
        pilotPayoutMultiplier = 1.25,
        freeItems = {
            { name = 'water', count = 1 },
            { name = 'sandwich', count = 1 }
        }
    },
    private = {
        label = 'Private',
        priceMultiplier = 3.0,
        boardingGroup = 10,
        pilotPayoutMultiplier = 1.75
    },
    government = {
        label = 'Government',
        priceMultiplier = 0.0,
        boardingGroup = 5,
        pilotPayoutMultiplier = 1.5,
        requiredJobs = { police = true, ambulance = true, doj = true, government = true, nolovelostairlines = true }
    }
}

Config.Aircraft = {
    luxor = {
        label = 'Luxor',
        seats = 8,
        classes = { basic = true, first_class = true, private = true, government = false },
        fuelCost = 500,
        maintenanceCost = 250
    },
    shamal = {
        label = 'Shamal',
        seats = 10,
        classes = { basic = true, first_class = true, private = true, government = true },
        fuelCost = 650,
        maintenanceCost = 300
    },
    nimbus = {
        label = 'Nimbus',
        seats = 8,
        classes = { basic = true, first_class = true, private = true, government = true },
        fuelCost = 700,
        maintenanceCost = 350
    },
    maverick = {
        label = 'Maverick Helicopter',
        seats = 4,
        classes = { basic = false, first_class = false, private = true, government = true },
        fuelCost = 250,
        maintenanceCost = 150
    }
}

Config.Locations = {
    ticketDesks = {
        {
            id = 'lsia_ticketing',
            label = 'LSIA Ticket Desk',
            coords = vec3(-1037.63, -2737.78, 20.17),
            radius = 1.6
        }
    },
    pilotTerminals = {
        {
            id = 'lsia_dispatch',
            label = 'NLL Pilot Dispatch',
            coords = vec3(-941.01, -2954.52, 13.95),
            radius = 1.6
        }
    },
    customsDesks = {
        {
            id = 'lsia_international_customs',
            label = 'LSIA International Customs',
            airport = 'lsia',
            coords = vec3(-1042.45, -2745.38, 20.17),
            radius = 1.8
        }
    },
    boardingGates = {
        {
            id = 'lsia_a1',
            label = 'Gate A1',
            gate = 'A1',
            airport = 'lsia',
            coords = vec3(-980.62, -2995.53, 13.95),
            radius = 3.0,
            aircraftSpawn = vec4(-977.92, -2992.56, 13.95, 59.0),
            aircraftBoardingRadius = 28.0
        }
    }
}

Config.Airports = {
    lsia = {
        label = 'Los Santos International',
        tower = 'LSIA Tower',
        taxiHold = {
            type = 'sphere',
            label = 'Taxi Hold Alpha',
            coords = vec3(-1135.0, -2875.0, 13.95),
            radius = 35.0
        },
        takeoffHold = {
            type = 'sphere',
            label = 'Runway 3 Hold Short',
            coords = vec3(-1265.0, -2525.0, 13.95),
            radius = 45.0
        },
        takeoffZone = {
            type = 'sphere',
            label = 'Runway 3 Departure Zone',
            coords = vec3(-1336.0, -2238.0, 13.9),
            radius = 450.0
        }
    },
    sandy = {
        label = 'Sandy Shores Airfield',
        tower = 'Sandy Tower',
        approachZone = {
            type = 'sphere',
            label = 'Sandy Approach',
            coords = vec3(1350.0, 3000.0, 350.0),
            radius = 900.0,
            altitudeMax = 900.0
        },
        landingZone = {
            type = 'sphere',
            label = 'Sandy Runway',
            coords = vec3(1730.0, 3310.0, 41.2),
            radius = 350.0
        },
        arrivalGate = {
            type = 'sphere',
            label = 'Sandy Ramp',
            coords = vec3(1728.0, 3295.0, 41.2),
            radius = 80.0
        }
    },
    paleto = {
        label = 'Paleto Bay',
        tower = 'Paleto Traffic',
        approachZone = {
            type = 'sphere',
            label = 'Paleto Approach',
            coords = vec3(-75.0, 6500.0, 350.0),
            radius = 900.0,
            altitudeMax = 900.0
        },
        landingZone = {
            type = 'sphere',
            label = 'Paleto Landing Zone',
            coords = vec3(-75.0, 6500.0, 32.0),
            radius = 250.0
        },
        arrivalGate = {
            type = 'sphere',
            label = 'Paleto Ramp',
            coords = vec3(-90.0, 6520.0, 32.0),
            radius = 80.0
        }
    },
    cayo = {
        label = 'Cayo Perico International',
        tower = 'Cayo Tower',
        approachZone = {
            type = 'sphere',
            label = 'Cayo Approach',
            coords = vec3(4400.0, -4550.0, 420.0),
            radius = 1000.0,
            altitudeMax = 900.0
        },
        landingZone = {
            type = 'sphere',
            label = 'Cayo Runway',
            coords = vec3(4480.0, -4520.0, 4.2),
            radius = 280.0
        },
        arrivalGate = {
            type = 'sphere',
            label = 'Cayo Terminal Ramp',
            coords = vec3(4448.0, -4485.0, 4.2),
            radius = 90.0
        }
    }
}

Config.Routes = {
    lsia_sandy = {
        label = 'LSIA to Sandy Shores Airfield',
        departure = 'lsia',
        arrival = 'sandy',
        gate = 'A1',
        basePrice = 1200,
        expectedTime = 420,
        minFlightTime = 180,
        allowedAircraft = { 'luxor', 'shamal', 'nimbus', 'maverick' },
        allowedTicketClasses = { basic = true, first_class = true, private = true, government = true },
        payout = {
            pilotBase = 850,
            airlineMultiplier = 0.65
        }
    },
    lsia_paleto = {
        label = 'LSIA to Paleto Bay',
        departure = 'lsia',
        arrival = 'paleto',
        gate = 'A1',
        basePrice = 1800,
        expectedTime = 600,
        minFlightTime = 240,
        allowedAircraft = { 'luxor', 'shamal', 'nimbus' },
        allowedTicketClasses = { basic = true, first_class = true, private = true, government = true },
        payout = {
            pilotBase = 1250,
            airlineMultiplier = 0.7
        }
    },
    lsia_cayo = {
        label = 'LSIA to Cayo Perico International',
        departure = 'lsia',
        arrival = 'cayo',
        gate = 'A1',
        basePrice = 3200,
        expectedTime = 720,
        minFlightTime = 300,
        routeType = 'international',
        requirements = {
            passport = true,
            customsClearance = true,
            noContraband = false
        },
        allowedAircraft = { 'luxor', 'shamal', 'nimbus' },
        allowedTicketClasses = { basic = true, first_class = true, private = true, government = true },
        payout = {
            pilotBase = 1900,
            airlineMultiplier = 0.72
        }
    }
}

Config.FlightNumbers = {
    prefix = 'NLL',
    min = 100,
    max = 999
}

Config.Tracking = {
    tickMs = 1500,
    takeoffAltitude = 80.0,
    takeoffSpeed = 45.0,
    approachAltitude = 900.0,
    landingAltitude = 18.0,
    landingSpeed = 25.0,
    aircraftMinimumHealth = 450.0,
    pilotAbandonSeconds = 90
}

Config.Spawning = {
    clearRadius = 8.0,
    warpPilotIntoSeat = true,
    engineOnAfterSpawn = true
}

Config.ZoneBypassJobs = {
    police = true,
    ambulance = true,
    government = true,
    nolovelostairlines = true
}
