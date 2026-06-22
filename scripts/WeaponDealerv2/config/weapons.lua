Config.Weapons = {
    {
        item = 'WEAPON_PISTOL',
        label = 'Pistol',
        ammo = 'ammo-9',
        image = 'WEAPON_PISTOL.png',
        previewModel = 'w_pi_pistol',
        description = 'Compact civilian sidearm approved for licensed defensive carry and range testing.',
        price = 4000,
        waitSeconds = 15 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        -- Optional buyer-side job lock. Leave disabled/nil for normal civilian sales.
        -- jobRequirement = {
        --     enabled = true,
        --     requireDuty = false,
        --     jobs = {
        --         police = 0,
        --         security = 1
        --     }
        -- },
        testable = true,
        packages = {
            {
                id = 'standard',
                label = 'Standard',
                price = 0,
                attachments = {}
            },
            {
                id = 'tactical_light',
                label = 'Tactical Light Package',
                price = 500,
                attachments = { 'flashlight' }
            }
        },
        attachments = {
            {
                id = 'flashlight',
                label = 'Pistol Flashlight',
                item = 'at_flashlight',
                price = 500,
                description = 'Rail-mounted tactical light.'
            },
            {
                id = 'suppressor',
                label = 'Pistol Suppressor',
                item = 'at_suppressor_light',
                price = 2200,
                description = 'Threaded suppressor attachment.'
            }
        }
    },
    {
        item = 'WEAPON_COMBATPISTOL',
        label = 'Combat Pistol',
        ammo = 'ammo-9',
        image = 'WEAPON_COMBATPISTOL.png',
        previewModel = 'w_pi_combatpistol',
        description = 'Duty-grade semi-automatic pistol requiring verified licensing and registration.',
        price = 6250,
        waitSeconds = 20 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        testable = true,
        packages = {
            {
                id = 'standard',
                label = 'Standard',
                price = 0,
                attachments = {}
            },
            {
                id = 'duty',
                label = 'Duty Package',
                price = 1200,
                attachments = { 'flashlight', 'extended_mag' }
            }
        },
        attachments = {
            {
                id = 'flashlight',
                label = 'Pistol Flashlight',
                item = 'at_flashlight',
                price = 500,
                description = 'Rail-mounted tactical light.'
            },
            {
                id = 'extended_mag',
                label = 'Extended Magazine',
                item = 'at_clip_extended_pistol',
                price = 850,
                description = 'Extended pistol magazine.'
            },
            {
                id = 'suppressor',
                label = 'Pistol Suppressor',
                item = 'at_suppressor_light',
                price = 2200,
                description = 'Threaded suppressor attachment.'
            }
        }
    },
    {
        item = 'WEAPON_SMG',
        label = 'SMG',
        ammo = 'ammo-9',
        image = 'WEAPON_SMG.png',
        previewModel = 'w_sb_smg',
        description = 'Restricted compact automatic platform with extended processing and employee approval requirements.',
        price = 19500,
        waitSeconds = 45 * 60,
        license = 'weaponlicense',
        minGrade = 2,
        testable = false,
        packages = {
            {
                id = 'standard',
                label = 'Standard',
                price = 0,
                attachments = {}
            },
            {
                id = 'tactical',
                label = 'Tactical Package',
                price = 1600,
                attachments = { 'flashlight', 'extended_mag' }
            }
        },
        attachments = {
            {
                id = 'flashlight',
                label = 'SMG Flashlight',
                item = 'at_flashlight',
                price = 500,
                description = 'Rail-mounted tactical light.'
            },
            {
                id = 'extended_mag',
                label = 'Extended Magazine',
                item = 'at_clip_extended_smg',
                price = 1100,
                description = 'Extended SMG magazine.'
            },
            {
                id = 'suppressor',
                label = 'SMG Suppressor',
                item = 'at_suppressor_heavy',
                price = 2500,
                description = 'Heavy threaded suppressor attachment.'
            }
        }
    },
    {
        item = 'WEAPON_FN502T',
        label = 'FN 502 Tactical',
        ammo = 'ammo-22',
        image = 'WEAPON_FN502T.png',
        description = 'Premium rimfire tactical pistol with a threaded-profile build and optic-ready civilian configuration.',
        price = 8500,
        waitSeconds = 25 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'tactical_light', label = 'Tactical Light Package', price = 500, attachments = { 'flashlight' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        item = 'WEAPON_G17G3P80',
        label = 'G17 Gen 3 P80',
        ammo = 'ammo-9',
        image = 'WEAPON_G17G3P80.png',
        description = 'Premium polymer-frame 9mm sidearm built for licensed civilian ownership and registry tracking.',
        price = 9500,
        waitSeconds = 28 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} }
        },
        attachments = {}
    },
    {
        item = 'WEAPON_PSAP8019',
        label = 'PSA P80 G19',
        ammo = 'ammo-9',
        image = 'WEAPON_PSAP8019.png',
        description = 'Compact custom 9mm P80-style pistol with upgraded fitment and legal registry processing.',
        price = 10500,
        waitSeconds = 30 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} }
        },
        attachments = {}
    },
    {
        item = 'WEAPON_KG43X',
        label = 'Kavorka G43X',
        ammo = 'ammo-9',
        image = 'WEAPON_KG43X.png',
        description = 'Slimline premium 9mm carry pistol with custom finishing and enhanced component fitment.',
        price = 11000,
        waitSeconds = 32 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'duty', label = 'Duty Package', price = 1200, attachments = { 'flashlight', 'extended_mag' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'extended_mag', label = 'Extended Magazine', item = 'at_clip_extended_pistol', price = 850, description = 'Extended pistol magazine.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        item = 'WEAPON_PSADHALFNHALF',
        label = 'PSA Custom 19/26',
        ammo = 'ammo-9',
        image = 'WEAPON_PSADHALFNHALF.png',
        description = 'Hybrid compact 9mm custom pistol configured for licensed carry and controlled store assembly.',
        price = 11500,
        waitSeconds = 33 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'duty', label = 'Duty Package', price = 1200, attachments = { 'flashlight', 'extended_mag' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'extended_mag', label = 'Extended Magazine', item = 'at_clip_extended_pistol', price = 850, description = 'Extended pistol magazine.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        item = 'WEAPON_SD40T',
        label = 'S&W SD40 Tan',
        ammo = 'ammo-40',
        image = 'WEAPON_SD40T.png',
        description = 'Premium .40 caliber tan sidearm with upgraded slide finishing and registry-compliant sale processing.',
        price = 12000,
        waitSeconds = 35 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'duty', label = 'Duty Package', price = 1200, attachments = { 'flashlight', 'extended_mag' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'extended_mag', label = 'Extended Magazine', item = 'at_clip_extended_pistol', price = 850, description = 'Extended pistol magazine.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        item = 'WEAPON_G45CAMO',
        label = 'Glock 45 Camo',
        ammo = 'ammo-9',
        image = 'WEAPON_G45CAMO.png',
        description = 'Limited camo-finished 9mm sidearm with premium components and serialized legal registration.',
        price = 12500,
        waitSeconds = 36 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'extended_mag', label = 'Extended Magazine Package', price = 1200, attachments = { 'extended_mag' } },
            { id = 'cosmetic_grip', label = 'Cosmetic Grip Package', price = 500, attachments = { 'black_grip' } },
            { id = 'premium_mag', label = 'Premium Magazine Package', price = 2200, attachments = { 'forty_round_mag' } }
        },
        attachments = {
            { id = 'extended_mag', label = 'Extended Magazine', item = 'tacticalextendedmag2', price = 1200, description = 'Extended magazine compatible with this custom platform.' },
            { id = 'drum_mag', label = 'Drum Magazine', item = 'tacticaldrummag2', price = 2800, description = 'High-capacity drum magazine.' },
            { id = 'windowed_mag', label = '33 Round Windowed Magazine', item = 'utgwindowedmag', price = 1500, description = 'Windowed extended magazine.' },
            { id = 'red_mag', label = '35 Round Magazine Red', item = 'tacticalextendedmag3', price = 1600, description = 'Red 35-round magazine.' },
            { id = 'gold_mag', label = '35 Round Magazine Gold', item = 'tacticalextendedmag4', price = 1800, description = 'Gold 35-round magazine.' },
            { id = 'forty_round_mag', label = '40 Round Magazine', item = 'klanevectormag', price = 2200, description = '40-round extended magazine.' },
            { id = 'white_forty_round_mag', label = '40 Round Magazine White', item = 'klanevectormagw', price = 2300, description = 'White 40-round extended magazine.' },
            { id = 'clear_mag', label = 'Clear Pistol Mag', item = 'tacticalextendedmagclear', price = 1600, description = 'Clear extended pistol magazine.' },
            { id = 'tan_mag', label = 'Extended Magazine Tan', item = 'tacticalextendedmagtan', price = 1600, description = 'Tan extended magazine.' },
            { id = 'tan_forty_round_mag', label = '40 Round Magazine Tan', item = 'klanevectormagt', price = 2300, description = 'Tan 40-round extended magazine.' },
            { id = 'camo_grip', label = 'Camo Pistol Grip', item = 'at_camogript', price = 450, description = 'Camo grip finish.' },
            { id = 'pink_camo_grip', label = 'Pink Camo Pistol Grip', item = 'at_camogripp', price = 500, description = 'Pink camo grip finish.' },
            { id = 'goon_tape_green', label = 'Goon Tape Green', item = 'at_goontapet', price = 350, description = 'Green grip tape.' },
            { id = 'goon_tape_black', label = 'Goon Tape Black', item = 'at_goontapeb', price = 350, description = 'Black grip tape.' },
            { id = 'rubber_bands', label = 'Rubber Bands', item = 'at_rubberbands', price = 300, description = 'Rubberized grip wrap.' },
            { id = 'dark_green_grip', label = 'Dark Green Pistol Grip', item = 'at_darkgreenpistolgrip', price = 450, description = 'Dark green grip finish.' },
            { id = 'tan_grip', label = 'Tan Pistol Grip', item = 'at_tanpistolgrip', price = 450, description = 'Tan grip finish.' },
            { id = 'black_grip', label = 'Black Pistol Grip', item = 'at_blackpistolgrip', price = 450, description = 'Black grip finish.' },
            { id = 'hogue_grip', label = 'Hogue Pistol Grip', item = 'at_hoguepistolgrip', price = 550, description = 'Hogue-style grip.' },
            { id = 'tan_hogue_grip', label = 'Tan Hogue Pistol Grip', item = 'at_hoguepistolgript', price = 600, description = 'Tan Hogue-style grip.' },
            { id = 'green_hogue_grip', label = 'Green Hogue Pistol Grip', item = 'at_hoguepistolgripg', price = 600, description = 'Green Hogue-style grip.' },
            { id = 'green_grip', label = 'Green Pistol Grip', item = 'at_greenpistolgrip', price = 450, description = 'Green grip finish.' },
            { id = 'blue_grip', label = 'Blue Pistol Grip', item = 'at_bluepistolgrip', price = 450, description = 'Blue grip finish.' },
            { id = 'red_grip', label = 'Red Pistol Grip', item = 'at_redpistolgrip', price = 450, description = 'Red grip finish.' },
            { id = 'gray_grip', label = 'Gray Pistol Grip', item = 'at_graypistolgrip', price = 450, description = 'Gray grip finish.' },
            { id = 'pink_grip', label = 'Pink Pistol Grip', item = 'at_pinkpistolgrip', price = 450, description = 'Pink grip finish.' },
            { id = 'purple_grip', label = 'Purple Pistol Grip', item = 'at_purplepistolgrip', price = 450, description = 'Purple grip finish.' }
        }
    },
    {
        item = 'WEAPON_G19XCOYOTE',
        label = 'G19X Coyote',
        ammo = 'ammo-9',
        image = 'WEAPON_G19XCOYOTE.png',
        description = 'Coyote-finished premium 9mm sidearm with improved handling and store-controlled assembly.',
        price = 12500,
        waitSeconds = 36 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'duty', label = 'Duty Package', price = 1200, attachments = { 'flashlight', 'extended_mag' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'extended_mag', label = 'Extended Magazine', item = 'at_clip_extended_pistol', price = 850, description = 'Extended pistol magazine.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        item = 'WEAPON_G45AV',
        label = 'G45 American Variant',
        ammo = 'ammo-9',
        image = 'WEAPON_G45AV.png',
        description = 'American-variant premium 9mm pistol with upgraded finish, serialized sale record, and delayed clearance.',
        price = 13000,
        waitSeconds = 38 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'duty', label = 'Duty Package', price = 1200, attachments = { 'flashlight', 'extended_mag' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'extended_mag', label = 'Extended Magazine', item = 'at_clip_extended_pistol', price = 850, description = 'Extended pistol magazine.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        item = 'WEAPON_P320CS',
        label = 'Custom P320 Sig',
        ammo = 'ammo-9',
        image = 'WEAPON_P320CS.png',
        description = 'Premium custom P320-style 9mm pistol with precision slide work and enhanced internal components.',
        price = 13500,
        waitSeconds = 40 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'duty', label = 'Duty Package', price = 1200, attachments = { 'flashlight', 'extended_mag' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'extended_mag', label = 'Extended Magazine', item = 'at_clip_extended_pistol', price = 850, description = 'Extended pistol magazine.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        item = 'WEAPON_CMP92',
        label = 'M&P 9 2.0 Custom',
        ammo = 'ammo-9',
        image = 'WEAPON_CMP92.png',
        description = 'Custom M&P 9 2.0 style sidearm with premium machining, upgraded internals, and legal registry workflow.',
        price = 13500,
        waitSeconds = 40 * 60,
        license = 'weaponlicense',
        minGrade = 1,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'duty', label = 'Duty Package', price = 1200, attachments = { 'flashlight', 'extended_mag' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'extended_mag', label = 'Extended Magazine', item = 'at_clip_extended_pistol', price = 850, description = 'Extended pistol magazine.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        item = 'WEAPON_PSADG20',
        label = 'G45 Gen 5',
        ammo = 'ammo-10',
        image = 'WEAPON_PSADG20.png',
        description = 'Premium 10mm-capable G45-style pistol requiring specialty caliber components and enhanced clearance.',
        price = 15000,
        waitSeconds = 45 * 60,
        license = 'weaponlicense',
        minGrade = 2,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'duty', label = 'Duty Package', price = 1200, attachments = { 'flashlight', 'extended_mag' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'extended_mag', label = 'Extended Magazine', item = 'at_clip_extended_pistol', price = 850, description = 'Extended pistol magazine.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        item = 'WEAPON_PSAFN57',
        label = 'Rock FN57',
        ammo = 'ammo-57x28',
        image = 'WEAPON_PSAFN57.png',
        description = 'Specialty 5.7x28 premium pistol with rare-caliber components and extended legal processing.',
        price = 17500,
        waitSeconds = 50 * 60,
        license = 'weaponlicense',
        minGrade = 2,
        category = 'pistol',
        legalClass = 'sidearm',
        packages = {
            { id = 'standard', label = 'Standard', price = 0, attachments = {} },
            { id = 'duty', label = 'Duty Package', price = 1200, attachments = { 'flashlight', 'extended_mag' } }
        },
        attachments = {
            { id = 'flashlight', label = 'Pistol Flashlight', item = 'at_flashlight', price = 500, description = 'Rail-mounted tactical light.' },
            { id = 'extended_mag', label = 'Extended Magazine', item = 'at_clip_extended_pistol', price = 850, description = 'Extended pistol magazine.' },
            { id = 'suppressor', label = 'Pistol Suppressor', item = 'at_suppressor_light', price = 2200, description = 'Threaded suppressor attachment.' }
        }
    },
    {
        enabled = false,
        item = 'WEAPON_CARBINERIFLE',
        label = 'Carbine Rifle',
        ammo = 'ammo-rifle',
        image = 'WEAPON_CARBINERIFLE.png',
        previewModel = 'w_ar_carbinerifle',
        description = 'Registered long gun processed under enhanced review for qualified license holders.',
        price = 85000,
        waitSeconds = 120 * 60,
        license = 'weaponlicense',
        minGrade = 3,
        testable = false,
        packages = {
            {
                id = 'standard',
                label = 'Standard',
                price = 0,
                attachments = {}
            },
            {
                id = 'patrol',
                label = 'Patrol Rifle Package',
                price = 7000,
                attachments = { 'flashlight', 'grip', 'optic' }
            }
        },
        attachments = {
            {
                id = 'flashlight',
                label = 'Rifle Flashlight',
                item = 'at_flashlight',
                price = 1200,
                description = 'Rail-mounted tactical light.'
            },
            {
                id = 'grip',
                label = 'Foregrip',
                item = 'at_grip',
                price = 2200,
                description = 'Stabilizing foregrip.'
            },
            {
                id = 'optic',
                label = 'Rifle Optic',
                item = 'at_scope_medium',
                price = 4200,
                description = 'Medium range rifle optic.'
            },
            {
                id = 'extended_mag',
                label = 'Extended Magazine',
                item = 'at_clip_extended_rifle',
                price = 3200,
                description = 'Extended rifle magazine.'
            }
        }
    }
}
