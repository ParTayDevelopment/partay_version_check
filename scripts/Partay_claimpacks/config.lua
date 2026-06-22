Config = {}
Config.Locale = 'en'
Config.Debug = false

-- Framework override, set to 'auto' to detect. Options: 'auto','esx','qbcore','qbox'
Config.Framework = 'auto'

-- Gender source for restrictions: 'auto' uses framework and ped model fallback.
-- Use 'ped' if your clothing menu swaps the freemode model without updating framework data.
-- Use 'framework' to trust player data only.
Config.GenderSource = 'auto'


-- Discord role / guild config
-- For safety, allow reading from convars set in server.cfg:
-- setr PARTAY_CLAIMPACKS_BOT_TOKEN "Bot TOKEN_HERE"
-- setr PARTAY_CLAIMPACKS_GUILD_ID "123456789012345678"
Config.Discord = {
  UseBadger = false,
  BotTokenConvar = 'PARTAY_CLAIMPACKS_BOT_TOKEN',
  GuildIdConvar = 'PARTAY_CLAIMPACKS_GUILD_ID',
  CacheSeconds = 60
}



-- Ped streaming (spawn/despawn peds dynamically to save resources)
Config.PedStreaming = {
  Enabled = true,
  SpawnDistance = 30.0,    -- meters to spawn the ped
  DespawnDistance = 60.0,  -- meters to despawn (add hysteresis)
  CheckInterval = 1000      -- milliseconds between distance checks
}
-- Zones/Timing
Config.DefaultZoneRadius = 3.0
Config.CheckInterval = 250
Config.RequireStay = false

-- Notifications
Config.Notify = {
  Position = 'top'
}

-- Currency item used when rewards have a `money = <amount>` cost
Config.CurrencyItem = 'money'


Config.GrantToInventory = true
Config.DenyIfFull = true

-- Example locations:
-- Restriction keys per location:
--   allowedJobs = { 'police', 'ambulance' } or nil
--   allowedDiscordRoles = { '123456789012345678', '987654321098765432' } or nil
--   gender = 'male' | 'female' | nil
--   requireTimeSeconds = number | nil
--   oneTime = true|false (true recommended for single-use rewards)
--   cooldownSeconds = number | nil (players must wait this many seconds between claims)
--   roleCaps = { ['roleId'] = maxClaims, ... } -- global per-role limits for this location
--   ped.animation = { dict='anim_dict', clip='anim_name', flag=1 } or { scenario='WORLD_HUMAN_COP_IDLES', freezePosition=false }
--   reward = { { name='water', count=5 }, ... } or single { name='repairkit', count=1 }
Config.Locations = {
  --[[{
    id = 'starter_pack_1',
    label = 'Starter Pack',
    ped = {
      model = 'cs_bankman',
      coords = vec3(-268.9, -956.2, 30.22),
      heading = 205.0,
      animation = {
        dict = 'amb@world_human_cheering@male_a',
        clip = 'base',
        flag = 1
      }
    },
    target = {
      icon = 'fa-solid fa-gift',
      label = 'Claim Starter Pack'
    },
    blip = {
      enabled = true,
      sprite = 280,
      color = 2,
      scale = 0.8,
      shortRange = true,
      label = 'Starter Pack'
    },
    zoneRadius = 3.0,
    oneTime = true,
    requireTimeSeconds = 0,
    cooldownSeconds = 604800,    -- 7 days
    gender = nil,
    allowedJobs = nil,
    allowedDiscordRoles = nil,
    reward = {
      { name = 'water', count = 5 },
      { name = 'sandwich', count = 5 },
      { name = 'phone', count = 1 }
    }
  },
  {
    id = 'police_kit',
    label = 'LEO Kit',
    ped = {
      model = 's_m_y_cop_01',
      coords = vec3(437.2320, -978.2048, 29.6896),
      heading = 178.2607,
      animation = {
        scenario = 'WORLD_HUMAN_COP_IDLES',
        freezePosition = false
      }
    },
    target = {
      icon = 'fa-solid fa-shield',
      label = 'Claim Duty Kit'
    },
    blip = {
      enabled = true,
      sprite = 60,
      color = 38,
      scale = 0.9,
      shortRange = false,
      label = 'LEO Claim'
    },
    zoneRadius = 2.5,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 21600,     -- 6 hours between claims
    gender = nil,
    allowedJobs = { 'police' },
    allowedDiscordRoles = { '112233445566778899' },
    roleCaps = {
      ['112233445566778899'] = 100 -- first 100 officers with this Discord role
    },
    reward = {
      { name = 'bandage', count = 3 },
      { name = 'repairkit', count = 1 }
    }
  },]]
  {
    id = 'ladies_night',
    label = 'Female Starter Pack',
    ped = {
      model = 'a_f_y_business_04',
      coords = vec3(-4850.9302, -1962.2000, 19.1342),
      heading = 270.2790,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-heart',
      label = 'Claim Female Starter Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Female Starter Pack'
    },
    zoneRadius = 2.0,
    oneTime = true,
    requireTimeSeconds = 0,
    cooldownSeconds = nil,
    gender = 'female',
    allowedJobs = nil,
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'fsp', count = 1, money = 100 }, -- costs 100 money item
      { name = 'fsp', count = 1 }
    }
  },
  {
    id = 'trapsnakcs_plug',
    label = 'TrapSnacks Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-4300.3237, -2209.4517, 24.3648),
      heading = 270.0534,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 14400,
    gender = nil,
    allowedJobs = "trapsnacks",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'trapsnacks', count = 5000, money = 375000 }
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'jackpot_plug',
    label = 'Jackpot Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-4036.92, -1267.29, 18.34),
      heading = 270.0534,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 14400,
    gender = nil,
    allowedJobs = "jackpot",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'jackpot', count = 5000, money = 375000 }
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'g6_plug',
    label = 'G6 Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-4259.6553, -1764.7061, 15.8395),
      heading = 357.4042,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 14400,
    gender = nil,
    allowedJobs = "g6",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'g6pill', count = 5000, money = 375000 }
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'pinkx_plug',
    label = 'X Pill Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-3989.7068, -1916.2175, 24.7887),
      heading = 72.6974,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 14400,
    gender = nil,
    allowedJobs = "pinkx",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'pinkx', count = 5000, money = 375000 }
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'icebox_plug',
    label = 'Icebox Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-4862.6636, -1896.3033, 19.1183),
      heading = 176.3271,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = nil,
    allowedJobs = "icebox",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'kozy_pearls', count = 1500, money = 112500 },
      { name = 'kozy_rosary', count = 1500, money = 112500 },
      { name = 'kozy_cuban', count = 1500, money = 112500 },
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'foot_plug',
    label = 'Foot Fetish Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-4901.8286, -1984.1141, 19.0034),
      heading = 316.5718,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = nil,
    allowedJobs = "foot",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'jordan_11s', count = 1500, money = 112500 }
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'cap_plug',
    label = 'Pior Caps Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-4920.9863, -1924.7061, 18.9758),
      heading = 176.0861,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = nil,
    allowedJobs = "pior",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'gucci_cap', count = 1500, money = 112500 },
      { name = 'burberry_cap', count = 1500, money = 112500 },
      { name = 'ferragamo_cap', count = 1500, money = 112500 },
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'salon_plug',
    label = 'Salon Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-3589.2795, -1656.4204, 30.2774),
      heading = 124.1960,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = nil,
    allowedJobs = "salon",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'locexten', count = 1500, money = 112500 },
      { name = 'layered_wig', count = 1500, money = 112500 },
      { name = 'headband_wig', count = 1500, money = 112500 },
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'barbershop_plug',
    label = 'Barbershop Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-3566.6670, -1213.1759, 22.4984),
      heading = 270.6278,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = nil,
    allowedJobs = "barbershop",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'female_bonnet', count = 1500, money = 112500 },
      { name = 'durag_neon', count = 1500, money = 112500 },
      { name = 'durag_wrappedseam', count = 1500, money = 112500 },
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'ipeach_plug',
    label = 'iPeach Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-4864.3481, -1978.3030, 19.0003),
      heading = 4.2035,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = nil,
    allowedJobs = "ipeach",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'vcamera', count = 1500, money = 112500 },
      { name = 'dji', count = 1500, money = 112500 },
      { name = 'metaglasses', count = 1500, money = 112500 },
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'ammu2_plug',
    label = 'Dutch Guns Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-3987.5339, -1067.5779, 30.7322),
      heading = 103.3356,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = nil,
    allowedJobs = "ammu2",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'plastic', count = 1000, money = 275000 },
      { name = 'steel', count = 1000, money = 275000 },
      { name = 'metal', count = 1000, money = 275000 },
      { name = 'metalscrap', count = 1000, money = 275000 },
      { name = 'WEAPON_HAMMER', count = 10, money = 100000 },
      { name = 'copper', count = 1000, money = 275000 },
      { name = 'aluminium', count = 1000, money = 275000 },
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'ammu_plug',
    label = 'Ammunation Plug',
    ped = {
      model = 'g_m_importexport_01',
      coords = vec3(-4541.2324, -1333.8539, 23.9950),
      heading = 321.5762,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-pills',
      label = 'Claim your Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = nil,
    allowedJobs = "ammu",
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'plastic', count = 1000, money = 275000 },
      { name = 'steel', count = 1000, money = 275000 },
      { name = 'metal', count = 1000, money = 275000 },
      { name = 'metalscrap', count = 1000, money = 275000 },
      { name = 'WEAPON_HAMMER', count = 10, money = 100000 },
      { name = 'copper', count = 1000, money = 275000 },
      { name = 'aluminium', count = 1000, money = 275000 },
      --{ name = 'velvet_material', count = 1 }
    }
  }
   
  --[[{
    id = 'crafting_male_night',
    label = 'Male Crafting Plug',
    ped = {
      model = 'u_m_m_markfost',
      coords = vec3(-4857.3750, -1942.1212, 19.1340),
      heading = 93.6431,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-heart',
      label = 'Claim your crafting Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = 'male',
    allowedJobs = nil,
    allowedDiscordRoles = nil,
    reward = {
      { name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      --{ name = 'female_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'leather_materials', count = 100, money = 5 }, -- costs 100 money item
      { name = 'shoe_foam', count = 100, money = 5 }, -- costs 100 money item
      { name = 'clothe_materials', count = 100, money = 5 }, -- costs 100 money item
      { name = 'sewing_kits', count = 100, money = 5 }, -- costs 100 money item
      { name = 'silk_material', count = 100, money = 5 }, -- costs 100 money item
      { name = 'velvet_material', count = 100, money = 5 }, -- costs 100 money item
      { name = 'silk_material', count = 100, money = 5 }, -- costs 100 money item
      --{ name = 'acrylic_powder', count = 100, money = 5 } -- costs 100 money item
      --{ name = 'velvet_material', count = 1 }
    }
  },
  {
    id = 'crafting_ladies_night',
    label = 'Female Crafting Plug',
    ped = {
      model = 'a_f_y_business_04',
      coords = vec3(-4857.9561, -1934.1783, 19.1340),
      heading = 93.6431,
      animation = {
        dict = 'amb@world_human_stand_mobile@female@text@base',
        clip = 'base',
        flag = 1,
        playbackRate = 1.0
      }
    },
    target = {
      icon = 'fa-solid fa-heart',
      label = 'Claim your crafting Pack'
    },
    blip = {
      enabled = false,
      sprite = 280,
      color = 48,
      scale = 0.8,
      shortRange = true,
      label = 'Cafting Pack'
    },
    zoneRadius = 2.0,
    oneTime = false,
    requireTimeSeconds = 0,
    cooldownSeconds = 7200,
    gender = 'female',
    allowedJobs = nil,
    allowedDiscordRoles = nil,
    reward = {
      --{ name = 'crafting_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'female_bench', count = 1, money = 50000 }, -- costs 100 money item
      { name = 'leather_materials', count = 100, money = 5 }, -- costs 100 money item
      --{ name = 'shoe_foam', count = 100, money = 5 }, -- costs 100 money item
      --{ name = 'clothe_materials', count = 100, money = 5 }, -- costs 100 money item
      { name = 'sewing_kits', count = 100, money = 5 }, -- costs 100 money item
      { name = 'silk_material', count = 100, money = 5 }, -- costs 100 money item
      { name = 'nail_tips', count = 100, money = 5 }, -- costs 100 money item
      { name = 'hair_bundle', count = 100, money = 5 }, -- costs 100 money item
      { name = 'acrylic_powder', count = 100, money = 5 } -- costs 100 money item
      --{ name = 'velvet_material', count = 1 }
    }
  }]]
}

-- Storage backend preference: 'oxmysql' or 'json'
Config.Storage = 'oxmysql'   -- oxmysql is required; no fallback















