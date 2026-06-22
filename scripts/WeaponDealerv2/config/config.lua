Config = {}

-- Core
Config.Debug = false
Config.Locale = 'en'

Config.Framework = {
    Name = 'qbox' -- qbox, qb, esx
}

-- Permissions
Config.Job = {
    Name = 'police',
    RequireDuty = false,
    Grades = {
        Scan = 1,
        Order = 1,
        TestWeapon = 1,
        PickupAssist = 1
    }
}

-- Locations
Config.Stores = {
    {
        id = 'ammumation_vespucci',
        label = 'Ammu-Nation Vespucci',
        salesDesk = {
            coords = vec4(16.2693, -1103.1971, 29.8022, 253.3773),
            size = vec3(1.5, 1.5, 1.5)
        },
        pickup = {
            coords = vec4(26.2187, -1091.5106, 29.8008, 145.7787),
            size = vec3(1.5, 1.5, 1.5)
        },
        assembly = {
            Enabled = true,
            coords = vec4(26.0856, -1087.7504, 28.8012, 341.6511),
            size = vec3(1.6, 1.6, 1.8),
            prop = 'gr_prop_gr_bench_01b',
            propFallbacks = {
                'gr_prop_gr_bench_04b',
                'gr_prop_gr_bench_03a',
                'prop_tool_bench02'
            },
            propOffset = vec3(0.0, 0.0, 0.0),
            stash = 'weapondealer_ammumation_vespucci_parts',
            stashLabel = 'Ammu-Nation Vespucci Parts Storage',
            stashSlots = 75,
            stashWeight = 250000
        },
        orderStations = {
            {
                id = 'vespucci_order_1',
                coords = vec4(16.3710, -1101.0657, 28.9923, 159.9966),
                size = vec3(1.5, 1.5, 1.5),
                preview = {
                    coords = vec4(16.3710, -1101.0657, 28.9923, 159.9966),
                    offset = vec3(0.0, 0.0, 0.85)
                }
            },
            {
                id = 'vespucci_order_2',
                coords = vec4(15.2256, -1104.7246, 28.99027, 340.8484),
                size = vec3(1.5, 1.5, 1.5),
                preview = {
                    coords = vec4(15.2256, -1104.7246, 28.99027, 340.8484),
                    offset = vec3(0.0, 0.0, 0.85)
                }
            },
            {
                id = 'vespucci_order_4',
                coords = vec4(16.7527, -1104.4996, 28.9927, 79.7829),
                size = vec3(1.5, 1.5, 1.5),
                preview = {
                    coords = vec4(16.7527, -1104.4996, 28.9927, 79.7829),
                    offset = vec3(0.0, 0.0, 0.85)
                }
            }
        },
        storeZone = {
            type = 'poly',
            coords = vec3(13.7051, -1098.0336, 32.0),
            minZ = 27.0,
            maxZ = 37.0,
            points = {
                vec2(19.8420, -1113.9689),
                vec2(-1.4548, -1106.5267),
                vec2(8.2368, -1081.8430),
                vec2(28.1984, -1089.6448)
            }
        }
    }
}

-- Identity and license verification
Config.Documents = {
    IdCardItem = 'id_card',
    WeaponLicenseItem = 'weaponlicense',
    ScanStepDelay = {
        Min = 250,
        Max = 650
    },
    LicenseCheckDelay = {
        Min = 3,
        Max = 7
    },
    VerificationSession = {
        DurationSeconds = 600,
        ClearOnUiClose = false,
        RequireEmployeeInStore = true,
        RequireBuyerInStore = true
    }
}

Config.ConsentTablet = {
    Enabled = true,
    Prop = 'prop_cs_tablet',
    Bone = 28422,
    Offset = vec3(0.0, -0.03, 0.0),
    Rotation = vec3(20.0, -90.0, 0.0),
    Anim = {
        Dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base',
        Name = 'base',
        Flag = 49
    }
}


Config.TerminalTablet = Config.ConsentTablet

Config.Assembly = {
    Enabled = true,
    Grade = 1,
    CraftTimeSeconds = 12,
    ProgressLabel = 'Assembling registered firearm order...',
    Animation = {
        Dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
        Name = 'machinic_loop_mechandplayer',
        Flag = 49
    },
    Recipes = {
        WEAPON_PISTOL = {
            { item = 'pistol_frame', label = 'Pistol Frame', count = 1 },
            { item = 'pistol_barrel', label = 'Pistol Barrel', count = 1 },
            { item = 'pistol_slide', label = 'Pistol Slide', count = 1 },
            { item = 'trigger_assembly', label = 'Trigger Assembly', count = 1 },
            { item = 'weapon_spring_kit', label = 'Spring Kit', count = 1 }
        },
        WEAPON_COMBATPISTOL = {
            { item = 'pistol_frame', label = 'Pistol Frame', count = 1 },
            { item = 'pistol_barrel', label = 'Pistol Barrel', count = 1 },
            { item = 'reinforced_slide', label = 'Reinforced Slide', count = 1 },
            { item = 'trigger_assembly', label = 'Trigger Assembly', count = 1 },
            { item = 'weapon_spring_kit', label = 'Spring Kit', count = 1 }
        },
        WEAPON_FN502T = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'rimfire_barrel', label = 'Rimfire Barrel', count = 1 },
            { item = 'pistol_slide', label = 'Pistol Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'enhanced_spring_kit', label = 'Enhanced Spring Kit', count = 1 }
        },
        WEAPON_G17G3P80 = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'match_pistol_barrel', label = 'Match Pistol Barrel', count = 1 },
            { item = 'custom_pistol_slide', label = 'Custom Pistol Slide', count = 1 },
            { item = 'trigger_assembly', label = 'Trigger Assembly', count = 1 },
            { item = 'weapon_spring_kit', label = 'Spring Kit', count = 1 }
        },
        WEAPON_PSAP8019 = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'match_pistol_barrel', label = 'Match Pistol Barrel', count = 1 },
            { item = 'custom_pistol_slide', label = 'Custom Pistol Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'weapon_spring_kit', label = 'Spring Kit', count = 1 }
        },
        WEAPON_KG43X = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'match_pistol_barrel', label = 'Match Pistol Barrel', count = 1 },
            { item = 'custom_pistol_slide', label = 'Custom Pistol Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'enhanced_spring_kit', label = 'Enhanced Spring Kit', count = 1 }
        },
        WEAPON_PSADHALFNHALF = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'match_pistol_barrel', label = 'Match Pistol Barrel', count = 1 },
            { item = 'custom_pistol_slide', label = 'Custom Pistol Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'enhanced_spring_kit', label = 'Enhanced Spring Kit', count = 1 }
        },
        WEAPON_SD40T = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'large_caliber_barrel', label = 'Large Caliber Barrel', count = 1 },
            { item = 'custom_pistol_slide', label = 'Custom Pistol Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'enhanced_spring_kit', label = 'Enhanced Spring Kit', count = 1 }
        },
        WEAPON_G45CAMO = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'match_pistol_barrel', label = 'Match Pistol Barrel', count = 1 },
            { item = 'reinforced_custom_slide', label = 'Reinforced Custom Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'custom_pistol_finish', label = 'Custom Pistol Finish', count = 1 }
        },
        WEAPON_G19XCOYOTE = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'match_pistol_barrel', label = 'Match Pistol Barrel', count = 1 },
            { item = 'reinforced_custom_slide', label = 'Reinforced Custom Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'custom_pistol_finish', label = 'Custom Pistol Finish', count = 1 }
        },
        WEAPON_G45AV = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'match_pistol_barrel', label = 'Match Pistol Barrel', count = 1 },
            { item = 'reinforced_custom_slide', label = 'Reinforced Custom Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'custom_pistol_finish', label = 'Custom Pistol Finish', count = 1 }
        },
        WEAPON_P320CS = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'match_pistol_barrel', label = 'Match Pistol Barrel', count = 1 },
            { item = 'reinforced_custom_slide', label = 'Reinforced Custom Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'custom_pistol_finish', label = 'Custom Pistol Finish', count = 1 }
        },
        WEAPON_CMP92 = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'match_pistol_barrel', label = 'Match Pistol Barrel', count = 1 },
            { item = 'reinforced_custom_slide', label = 'Reinforced Custom Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'custom_pistol_finish', label = 'Custom Pistol Finish', count = 1 }
        },
        WEAPON_PSADG20 = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'large_caliber_barrel', label = 'Large Caliber Barrel', count = 1 },
            { item = 'reinforced_custom_slide', label = 'Reinforced Custom Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'specialty_caliber_kit', label = 'Specialty Caliber Kit', count = 1 }
        },
        WEAPON_PSAFN57 = {
            { item = 'premium_pistol_frame', label = 'Premium Pistol Frame', count = 1 },
            { item = 'five_seven_barrel', label = '5.7 Barrel', count = 1 },
            { item = 'five_seven_slide', label = '5.7 Slide', count = 1 },
            { item = 'precision_trigger', label = 'Precision Trigger', count = 1 },
            { item = 'specialty_caliber_kit', label = 'Specialty Caliber Kit', count = 1 }
        },
        WEAPON_SMG = {
            { item = 'smg_receiver', label = 'SMG Receiver', count = 1 },
            { item = 'smg_barrel', label = 'SMG Barrel', count = 1 },
            { item = 'bolt_carrier', label = 'Bolt Carrier', count = 1 },
            { item = 'trigger_group', label = 'Trigger Group', count = 1 },
            { item = 'magwell_assembly', label = 'Magwell Assembly', count = 1 }
        },
        WEAPON_CARBINERIFLE = {
            { item = 'rifle_receiver', label = 'Rifle Receiver', count = 1 },
            { item = 'rifle_barrel', label = 'Rifle Barrel', count = 1 },
            { item = 'bolt_carrier', label = 'Bolt Carrier', count = 1 },
            { item = 'trigger_group', label = 'Trigger Group', count = 1 },
            { item = 'stock_assembly', label = 'Stock Assembly', count = 1 }
        }
    }
}

Config.PartsOrdering = {
    Enabled = true,
    Grade = 1,
    SocietyGrade = 2,
    PersonalGrade = 1,
    DeliverySeconds = 1800,
    MaxCartItems = 20,
    MaxPackagesPerItem = 10,
    DefaultImage = 'WEAPON_PISTOL.png',
    ExpeditedShipping = {
        Enabled = true,
        Percent = 7,
        RemainingSeconds = 30
    },
    PaymentSources = {
        society = true,
        bank = true,
        cash = true
    },
    Catalog = {
        pistol_frame = { label = 'Pistol Frame', price = 4500, pack = 5 },
        pistol_barrel = { label = 'Pistol Barrel', price = 3250, pack = 5 },
        pistol_slide = { label = 'Pistol Slide', price = 3750, pack = 5 },
        reinforced_slide = { label = 'Reinforced Slide', price = 12250, pack = 5 },
        trigger_assembly = { label = 'Trigger Assembly', price = 2000, pack = 5 },
        weapon_spring_kit = { label = 'Spring Kit', price = 1500, pack = 5 },
        premium_pistol_frame = { label = 'Premium Pistol Frame', price = 12500, pack = 5 },
        match_pistol_barrel = { label = 'Match Pistol Barrel', price = 10000, pack = 5 },
        rimfire_barrel = { label = 'Rimfire Barrel', price = 5000, pack = 5 },
        large_caliber_barrel = { label = 'Large Caliber Barrel', price = 13500, pack = 5 },
        custom_pistol_slide = { label = 'Custom Pistol Slide', price = 11250, pack = 5 },
        reinforced_custom_slide = { label = 'Reinforced Custom Slide', price = 16500, pack = 5 },
        precision_trigger = { label = 'Precision Trigger', price = 6000, pack = 5 },
        enhanced_spring_kit = { label = 'Enhanced Spring Kit', price = 4000, pack = 5 },
        custom_pistol_finish = { label = 'Custom Pistol Finish', price = 5000, pack = 5 },
        specialty_caliber_kit = { label = 'Specialty Caliber Kit', price = 9000, pack = 5 },
        five_seven_barrel = { label = '5.7 Barrel', price = 17500, pack = 5 },
        five_seven_slide = { label = '5.7 Slide', price = 20000, pack = 5 },
        smg_receiver = { label = 'SMG Receiver', price = 15000, pack = 3 },
        smg_barrel = { label = 'SMG Barrel', price = 10500, pack = 3 },
        bolt_carrier = { label = 'Bolt Carrier', price = 7500, pack = 3 },
        trigger_group = { label = 'Trigger Group', price = 5550, pack = 3 },
        magwell_assembly = { label = 'Magwell Assembly', price = 5400, pack = 3 },
        rifle_receiver = { enabled = false, label = 'Rifle Receiver', price = 1200, pack = 2 },
        rifle_barrel = { enabled = false, label = 'Rifle Barrel', price = 950, pack = 2 },
        stock_assembly = { enabled = false, label = 'Stock Assembly', price = 650, pack = 2 }
    }
}

Config.PartsStorage = {
    DepositGrade = 1,
    WithdrawGrade = 1
}

-- Ordering
Config.OrderLimits = {
    FirstTimeMaxWeapons = 1,
    ReturningMaxWeapons = 2
}

Config.TradeIn = {
    Enabled = true,
    RequireVerification = true,
    RecentWindowDays = 14,
    OwnedRecentPercent = 120,
    OwnedExpiredPercent = 70,
    UnownedPercent = 25,
    MaxCreditPercent = 100,
    AllowUnregistered = true
}

Config.Receipts = {
    Enabled = true,
    Item = 'weapon_receipt',
    Count = 1,
    Required = false
}

Config.Payment = {
    Account = 'bank',
    AllowCashFallback = true,
    PrismTransactionHistory = true,
    Society = {
        Enabled = true,
        Resource = 'prism_banking',
        Account = 'gunstore'
    },
    EmployeeCommission = {
        Enabled = true,
        Type = 'percent', -- percent or flat
        Amount = 5
    }
}

Config.Blips = {
    Enabled = true,
    Stores = true,
    Assembly = false,
    Store = {
        Sprite = 110,
        Color = 1,
        Scale = 0.8,
        Label = 'Weapons Shop'
    },
    AssemblyStation = {
        Sprite = 566,
        Color = 2,
        Scale = 0.65,
        Label = 'Weapon Assembly'
    }
}

Config.PickupPed = {
    Enabled = true,
    Model = 's_m_y_ammucity_01',
    Coords = vec4(26.2187, -1091.5106, 28.8008, 145.7787),
    Scenario = 'WORLD_HUMAN_CLIPBOARD',
    Thanks = 'Thank you for your business.'
}

Config.DisarmZone = {
    Enabled = true,
    ExemptJobs = {
        police = true,
        ambulance = true,
        gunstore = true
    }
}

-- Optional integrations
Config.License = {
    Enabled = true,
    Resource = 'cs_license',
    WeaponLicenseItem = 'weaponlicense'
}

Config.Tablet = {
    Enabled = true,
    Resource = 'lb-tablet',
    MDT = 'police',
    Registrant = 'sellerName'
}

Config.Phone = {
    Enabled = true,
    Resource = 'lb-phone',
    OrderEmail = {
        Enabled = true,
        Sender = 'Ammu-Nation',
        Subject = 'Legal Firearm Order Confirmation'
    }
}

-- Order station previews
Config.Preview = {
    Enabled = true,
    Coords = vec4(16.6942, -1102.1113, 29.8020, 292.4817),
    Offset = vec3(0.0, 0.0, 0.85),
    RotationSpeed = 0.35
}

-- Ammo catalog
Config.Ammo = {
    Enabled = true,
    Packages = {
        ['ammo-22'] = {
            label = '.22 LR Ammunition',
            price = 90,
            count = 50,
            maxPackages = 5
        },
        ['ammo-9'] = {
            label = '9mm Ammunition',
            price = 200,
            count = 24,
            maxPackages = 5
        },
        ['ammo-40'] = {
            label = '.40 S&W Ammunition',
            price = 260,
            count = 24,
            maxPackages = 5
        },
        ['ammo-45'] = {
            label = '.45 ACP Ammunition',
            price = 300,
            count = 24,
            maxPackages = 5
        },
        ['ammo-10'] = {
            label = '10mm Ammunition',
            price = 350,
            count = 24,
            maxPackages = 4
        },
        ['ammo-57x28'] = {
            label = '5.7x28mm Ammunition',
            price = 450,
            count = 30,
            maxPackages = 4
        },
        ['ammo-rifle'] = {
            enabled = false,
            label = 'Rifle Ammunition',
            price = 450,
            count = 30,
            maxPackages = 3
        }
    }
}

-- Global weapon damage balancing
Config.WeaponDamage = {
    Enabled = true,
    RefreshSeconds = 10,
    Categories = {
        LowDamageMelee = {
            Modifier = 0.05,
            Weapons = {
                `WEAPON_KNIFE`,
                `WEAPON_BAT`,
                `WEAPON_HAMMER`,
                `WEAPON_CROWBAR`,
                `WEAPON_KNUCKLE`
            }
        }
    }
}

Config.Melee = {
    Enabled = true,
    RequiresVerification = true,
    Items = {
        {
            item = 'WEAPON_KNIFE',
            label = 'Utility Knife',
            price = 350,
            description = 'Legal utility blade sold under verified customer intake.'
        },
        {
            item = 'WEAPON_BAT',
            label = 'Wooden Bat',
            price = 250,
            description = 'Sporting bat approved for civilian purchase.'
        },
        {
            item = 'WEAPON_HAMMER',
            label = 'Hammer',
            price = 175,
            description = 'Hardware-grade hammer sold as a lawful utility tool.'
        },
        {
            item = 'WEAPON_CROWBAR',
            label = 'Crowbar',
            price = 225,
            description = 'Utility pry bar with reduced RP damage balancing.'
        },
        {
            item = 'WEAPON_KNUCKLE',
            label = 'Brass Knuckles',
            price = 300,
            description = 'Registered melee item sold only after verification.'
        }
    }
}

-- Security and logging
Config.Security = {
    MaxInteractDistance = 3.0,
    NearbyBuyerDistance = 4.0,
    ServerCooldownSeconds = 3,
    OneActiveOrder = false
}

Config.Logging = {
    Console = true,
    Discord = {
        Enabled = false,
        Webhook = ''
    }
}
