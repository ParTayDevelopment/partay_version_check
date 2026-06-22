-- Drop these entries into ox_inventory/data/items.lua.
-- Weapon item definitions such as WEAPON_PISTOL usually live in ox_inventory/data/weapons.lua.

['id_card'] = {
    label = 'Government ID',
    weight = 10,
    stack = false,
    close = true,
    description = 'Government-issued identification card.'
},

['weaponlicense'] = {
    label = 'Weapons License',
    weight = 10,
    stack = false,
    close = true,
    description = 'Official license authorizing legal firearm ownership.'
},

['weapon_receipt'] = {
    label = 'Firearm Order Receipt',
    weight = 10,
    stack = false,
    close = true,
    description = 'Receipt for a legal firearm order.'
},

['ammo-9'] = {
    label = '9mm Ammunition',
    weight = 4,
    stack = true,
    close = true
},

['ammo-22'] = {
    label = '.22 LR Ammunition',
    weight = 2,
    stack = true,
    close = true
},

['ammo-40'] = {
    label = '.40 S&W Ammunition',
    weight = 5,
    stack = true,
    close = true
},

['ammo-45'] = {
    label = '.45 ACP Ammunition',
    weight = 5,
    stack = true,
    close = true
},

['ammo-10'] = {
    label = '10mm Ammunition',
    weight = 5,
    stack = true,
    close = true
},

['ammo-57x28'] = {
    label = '5.7x28mm Ammunition',
    weight = 4,
    stack = true,
    close = true
},

['ammo-rifle'] = {
    label = 'Rifle Ammunition',
    weight = 6,
    stack = true,
    close = true
},

['WEAPON_KNIFE'] = {
    label = 'Utility Knife',
    weight = 400,
    stack = false,
    close = true
},

['WEAPON_BAT'] = {
    label = 'Wooden Bat',
    weight = 900,
    stack = false,
    close = true
},

['WEAPON_HAMMER'] = {
    label = 'Hammer',
    weight = 650,
    stack = false,
    close = true
},

['WEAPON_CROWBAR'] = {
    label = 'Crowbar',
    weight = 850,
    stack = false,
    close = true
},

['WEAPON_KNUCKLE'] = {
    label = 'Brass Knuckles',
    weight = 300,
    stack = false,
    close = true
},

['at_flashlight'] = {
    label = 'Weapon Flashlight',
    weight = 250,
    stack = true,
    close = true
},

['at_suppressor_light'] = {
    label = 'Light Suppressor',
    weight = 450,
    stack = true,
    close = true
},

['at_clip_extended_pistol'] = {
    label = 'Extended Pistol Magazine',
    weight = 250,
    stack = true,
    close = true
},

['at_clip_extended_smg'] = {
    label = 'Extended SMG Magazine',
    weight = 350,
    stack = true,
    close = true
},

['at_suppressor_heavy'] = {
    label = 'Heavy Suppressor',
    weight = 650,
    stack = true,
    close = true
},

['at_grip'] = {
    label = 'Weapon Grip',
    weight = 300,
    stack = true,
    close = true
},

['at_scope_medium'] = {
    label = 'Medium Scope',
    weight = 500,
    stack = true,
    close = true
},

['at_clip_extended_rifle'] = {
    label = 'Extended Rifle Magazine',
    weight = 450,
    stack = true,
    close = true
},

['tacticalextendedmag2'] = {
    label = 'Extended Magazine',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag2` },
        usetime = 2500
    }
},

['tacticaldrummag2'] = {
    label = 'Drum Magazine',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag3` },
        usetime = 2500
    }
},

['utgwindowedmag'] = {
    label = '33 Round Windowed Magazine',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag9` },
        usetime = 2500
    }
},

['tacticalextendedmag3'] = {
    label = '35 Round Magazine Red',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag10` },
        usetime = 2500
    }
},

['tacticalextendedmag4'] = {
    label = '35 Round Magazine Gold',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag11` },
        usetime = 2500
    }
},

['klanevectormag'] = {
    label = '40 Round Magazine',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag4` },
        usetime = 2500
    }
},

['klanevectormagw'] = {
    label = '40 Round Magazine White',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag5` },
        usetime = 2500
    }
},

['tacticalextendedmagclear'] = {
    label = 'Clear Pistol Mag',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag6` },
        usetime = 2500
    }
},

['tacticalextendedmagtan'] = {
    label = 'Extended Magazine Tan',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag7` },
        usetime = 2500
    }
},

['klanevectormagt'] = {
    label = '40 Round Magazine Tan',
    type = 'magazine',
    weight = 280,
    stack = true,
    close = true,
    client = {
        component = { `g17g4gmag8` },
        usetime = 2500
    }
},

['at_camogript'] = {
    label = 'Camo Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `camogrip`, `camogrip2`, `camogrip3` },
        usetime = 2500
    }
},

['at_camogripp'] = {
    label = 'Pink Camo Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `camogript`, `camogript2`, `camogript3` },
        usetime = 2500
    }
},

['at_goontapet'] = {
    label = 'Goon Tape Green',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `goontape`, `goontape2`, `goontape3` },
        usetime = 2500
    }
},

['at_goontapeb'] = {
    label = 'Goon Tape Black',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `goontapeb`, `goontapeb3` },
        usetime = 2500
    }
},

['at_rubberbands'] = {
    label = 'Rubber Bands',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `rbandz`, `rbandz2`, `rbandz3` },
        usetime = 2500
    }
},

['at_darkgreenpistolgrip'] = {
    label = 'Dark Green Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `dgreengrip`, `dgreengrip2`, `dgreengrip3` },
        usetime = 2500
    }
},

['at_tanpistolgrip'] = {
    label = 'Tan Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `tangrip`, `tangrip3` },
        usetime = 2500
    }
},

['at_blackpistolgrip'] = {
    label = 'Black Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `blackgrip`, `blackgrip2`, `blackgrip3` },
        usetime = 2500
    }
},

['at_hoguepistolgrip'] = {
    label = 'Hogue Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `hoguegrip`, `hoguegrip2`, `hoguegrip3` },
        usetime = 2500
    }
},

['at_hoguepistolgript'] = {
    label = 'Tan Hogue Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `hoguegriptan`, `hoguegriptan2`, `hoguegriptan3` },
        usetime = 2500
    }
},

['at_hoguepistolgripg'] = {
    label = 'Green Hogue Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `hoguegripgreen`, `hoguegripgreen2`, `hoguegripgreen3` },
        usetime = 2500
    }
},

['at_greenpistolgrip'] = {
    label = 'Green Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `greengrip`, `greengrip2`, `greengrip3` },
        usetime = 2500
    }
},

['at_bluepistolgrip'] = {
    label = 'Blue Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `bluegrip`, `bluegrip2`, `bluegrip3` },
        usetime = 2500
    }
},

['at_redpistolgrip'] = {
    label = 'Red Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `redgrip`, `redgrip2`, `redgrip3` },
        usetime = 2500
    }
},

['at_graypistolgrip'] = {
    label = 'Gray Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `graygrip`, `graygrip2`, `graygrip3` },
        usetime = 2500
    }
},

['at_pinkpistolgrip'] = {
    label = 'Pink Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `pinkgrip`, `pinkgrip2`, `pinkgrip3` },
        usetime = 2500
    }
},

['at_purplepistolgrip'] = {
    label = 'Purple Pistol Grip',
    type = 'grip',
    weight = 120,
    stack = true,
    close = true,
    client = {
        component = { `purplegrip`, `purplegrip2`, `purplegrip3` },
        usetime = 2500
    }
},

['pistol_frame'] = {
    label = 'Pistol Frame',
    weight = 900,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['pistol_barrel'] = {
    label = 'Pistol Barrel',
    weight = 450,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['pistol_slide'] = {
    label = 'Pistol Slide',
    weight = 550,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['reinforced_slide'] = {
    label = 'Reinforced Slide',
    weight = 700,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['trigger_assembly'] = {
    label = 'Trigger Assembly',
    weight = 250,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['weapon_spring_kit'] = {
    label = 'Weapon Spring Kit',
    weight = 150,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['premium_pistol_frame'] = {
    label = 'Premium Pistol Frame',
    weight = 950,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['match_pistol_barrel'] = {
    label = 'Match Pistol Barrel',
    weight = 500,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['rimfire_barrel'] = {
    label = 'Rimfire Barrel',
    weight = 350,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['large_caliber_barrel'] = {
    label = 'Large Caliber Barrel',
    weight = 600,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['custom_pistol_slide'] = {
    label = 'Custom Pistol Slide',
    weight = 650,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['reinforced_custom_slide'] = {
    label = 'Reinforced Custom Slide',
    weight = 760,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['precision_trigger'] = {
    label = 'Precision Trigger',
    weight = 220,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['enhanced_spring_kit'] = {
    label = 'Enhanced Spring Kit',
    weight = 180,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['custom_pistol_finish'] = {
    label = 'Custom Pistol Finish',
    weight = 200,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['specialty_caliber_kit'] = {
    label = 'Specialty Caliber Kit',
    weight = 350,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['five_seven_barrel'] = {
    label = '5.7 Barrel',
    weight = 500,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['five_seven_slide'] = {
    label = '5.7 Slide',
    weight = 700,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['smg_receiver'] = {
    label = 'SMG Receiver',
    weight = 1200,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['smg_barrel'] = {
    label = 'SMG Barrel',
    weight = 700,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['bolt_carrier'] = {
    label = 'Bolt Carrier',
    weight = 600,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['trigger_group'] = {
    label = 'Trigger Group',
    weight = 350,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['magwell_assembly'] = {
    label = 'Magwell Assembly',
    weight = 400,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['rifle_receiver'] = {
    label = 'Rifle Receiver',
    weight = 1600,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['rifle_barrel'] = {
    label = 'Rifle Barrel',
    weight = 1200,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},

['stock_assembly'] = {
    label = 'Stock Assembly',
    weight = 850,
    stack = true,
    close = true,
    client = { image = 'WEAPON_PISTOL.png' }
},
