Config = {}
Config.Debug = false
-- Framework autodetect. Set to 'auto' to detect ESX/QB/QBX at runtime,
-- or force with one of: 'esx' | 'qb' | 'qbx'
Config.Framework = 'qbx'

-- Language for notifications and UI text
-- Supported: 'en' (English), 'es' (Español)
Config.Locale = 'en'

Config.Commands = {
    player = {
        hustle = 'dealer',
        leaderboard = 'dealerleaderboard',
        hotspots = 'traphotspots',
        cancel = 'trapcancel'
    }
}

-- External XP integration (optional)
-- Configure an export or event to award XP in another leveling system
-- Default example integrates with pickle_crafting: AddPlayerXP(source, "networking", 1000)
Config.ExternalXP = {
    enabled = false,
    -- Common fields (used if you don't provide a custom args() below)
    skill = 'wholesale',   -- set to a skill that exists in your XP system
    xp = 250,              -- XP to award per successful sale
    identifierMode = 'source', -- 'source' | 'citizenid' | 'license' | 'license2'

    -- Use an export
    export = {
        resource = 'pickle_xp',    -- e.g. 'pickle_xp' or 'pickle_crafting'
        method = 'AddPlayerXP',    -- exported function name
        -- args can be a function to build dynamic args per sale
        -- function(source, info) -> returns array of args
        -- info = { item, label, quantity, total }
        -- If not provided, we default to { identifier, skill, xp }
        args = nil
    },
    -- Or alternatively specify a server event to trigger (leave nil if using export)
    -- event = 'my_xp_system:addXP' -- signature: (source, info)
}


Config.Database = {
    autoMigrate = true
}


-- Selling location rules:
-- defaultMode = 'anywhere': items without their own zones can sell anywhere.
-- defaultMode = 'zones': items without their own zones must use Config.Zones.
-- Add `zones = { { coords = vector3(...), maxRange = 50.0 } }` inside an item to lock only that item to those zones.
Config.Selling = {
    defaultMode = 'anywhere'
}

-- enforceZone: legacy setting. New setups should use Config.Selling.defaultMode above.
-- sellCooldownMs: per-player cooldown on server sale event to prevent spam
Config.Server = {
    enforceZone = false,
    sellCooldownMs = 2000,
    perItemCooldownMs = 15000, -- per player, per item
    leaderboardCacheMs = 5000, -- cache leaderboard results to reduce DB spam
    hourlyCap = {               -- 0 disables caps
        perPlayerSales = 500,   -- max successful sales per player per hour
        serverSales = 0         -- optional server-wide cap per hour
    }
}

-- Callback rate limits (ms)
Config.RateLimits = Config.RateLimits or {
    getLevelMs = 500,
    getUnclaimedMs = 1000,
    claimRewardsMs = 2000,
    getLeaderboardMs = 2000,
    getAvailableDrugMs = 300,
}

-- Reward presentation + vehicle integration
-- notify: when true, shows a notification on successful reward grants
-- vehicle.handlerEvent: keep nil to use the built-in adapter router
--   To integrate JG Advanced Garages, leave this nil and set Config.Garage.system = 'jg' below
Config.Rewards = {
    notify = true,
    vehicle = {
        handlerEvent = nil -- optional override; e.g. 'my_garage:server:addLevelVehicle'
    }
}

-- Garage integration adapter
-- system: 'jg' | 'qbox' | 'qb' | 'esx' | 'custom'
Config.Garage = {
    system = 'jg',
    -- If your JG resource has a custom name, set it here (e.g. 'jg_advancedgarages')
    -- resourceName = 'jg-advancedgarages',
    defaultGarage = 'Grove Street',    -- customize to your server
    defaultState = 'stored' -- or 'out'
}

-- Optional item requirement to use /hustle
-- If enabled, the player must have at least one of the items in `items`
-- Set `any = true` to require any one; set to false to require all listed items
Config.HustleRequirement = {
    enabled = false,
    items = { 'sell_phone' }, -- add 'test' here if you want to allow a test item: { 'trap_phone', 'test' }
    any = true,
    label = 'Sidekick' -- used in the notification text
}

Config.DrugList = {

    -- Civ Items
    ['jordan_1s'] = {
        label = 'Jordan 1',
        quantity = {min = 1, max = 8},
        price = {min = 150, max = 150},
        leveladd = 6, -- This value represents the amount of level points added when selling this item
        prop = 'prop_ld_shoe_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['jordan_3s'] = {
        label = 'Jordan 3',
        quantity = {min = 1, max = 8},
        price = {min = 250, max = 250},
        leveladd = 12, -- This value represents the amount of level points added when selling this item
        prop = 'prop_ld_shoe_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['jordan_11s'] = {
        label = 'Jordan 11s',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 20, -- This value represents the amount of level points added when selling this item
        prop = 'prop_ld_shoe_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['console_xbox'] = {
        label = 'Refurbished Xbox',
        quantity = {min = 1, max = 8},
        price = {min = 100, max = 125},
        leveladd = 20, -- This value represents the amount of level points added when selling this item
        prop = 'prop_ld_shoe_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['gaming_laptop'] = {
        label = 'Refurbished Gaming Laptop',
        quantity = {min = 1, max = 8},
        price = {min = 100, max = 125},
        leveladd = 20, -- This value represents the amount of level points added when selling this item
        prop = 'prop_ld_shoe_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['console_ps5'] = {
        label = 'Refurbished Ps5',
        quantity = {min = 1, max = 8},
        price = {min = 100, max = 125},
        leveladd = 20, -- This value represents the amount of level points added when selling this item
        prop = 'prop_ld_shoe_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['yankee_no_brim'] = {
        label = 'Yankee No Brim',
        quantity = {min = 1, max = 8},
        price = {min = 150, max = 150},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_ld_shoe_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['sf_hat'] = {
        label = 'SF Hat',
        quantity = {min = 1, max = 8},
        price = {min = 250, max = 250},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_ld_shoe_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['atl_braves_hat'] = {
        label = 'ATL Braves Hat',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['durag_cotton'] = {
        label = 'Cotton Durag',
        quantity = {min = 1, max = 8},
        price = {min = 150, max = 150},
        leveladd = 27, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['durag_silky'] = {
        label = 'Silky Durag',
        quantity = {min = 1, max = 8},
        price = {min = 250, max = 250},
        leveladd = 20, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['durag_velvet'] = {
        label = 'Velvet Durag',
        quantity = {min = 1, max = 8},
        price = {min = 275, max = 275},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    --barbershop
    ['durag_neon'] = {
        label = 'Neon Durag',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['durag_wrappedseam'] = {
        label = 'Wrappedseam Durag',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['female_bonnet'] = {
        label = 'Female Bonnet',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    --icebox
    ['kozy_pearls'] = {
        label = 'Kozy Pearls',
        quantity = {min = 1, max = 8},
        price = {min = 200, max = 200},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'v_ret_ps_box_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['kozy_rosary'] = {
        label = 'Kozy Rosary',
        quantity = {min = 1, max = 8},
        price = {min = 300, max = 300},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'v_ret_ps_box_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['kozy_cuban'] = {
        label = 'Kozy Cuban',
        quantity = {min = 1, max = 8},
        price = {min = 400, max = 400},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'v_ret_ps_box_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    --ipeach
    ['metaglasses'] = {
        label = 'Meta Glasses',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['dji'] = {
        label = 'DJI',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['vcamera'] = {
        label = 'Vlogging Camera',
        quantity = { min = 1, max = 8 },
        price = { min = 350, max = 350 },
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)

        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item', -- 'money' or 'item'
            name = 'money' -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },

        -- Optional dispatch per item
        dispatch = {
            enabled = true,
            chance = 10,
            message = 'Street deal reported',
            code = '10-66'
        },

        -- Optional per-item buyer denial chance. Overrides Config.Buyer.denialChance.
        buyer = {
            denialChance = 15
        },

        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        allowedPedModels = { nil },

        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' },

        -- Optional: lock this item to specific sell zones.
        -- Remove/comment this block to let it follow Config.Selling.defaultMode.
        zones = {
            { coords = vector3(-3684.3054, -1578.5535, 27.6123), maxRange = 50.0 },
            { coords = vector3(-4453.4141, -1752.0941, 14.6699), maxRange = 50.0 }
        }
    },
    -- Pior
    ['gucci_cap'] = {
        label = 'Gucci Cap',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['burberry_cap'] = {
        label = 'Burberry cap',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['ferragamo_cap'] = {
        label = 'Ferragamo cap',
        quantity = {min = 1, max = 8},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cap_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },



    -- Female Items
    ['wig_straight'] = {
        label = 'Straight Wig',
        quantity = {min = 1, max = 8},
        price = {min = 175, max = 175},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cs_shopping_bag', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { 'a_f_y_hipster_01',
  'a_f_y_bevhills_01',
  'a_f_y_business_01',
  'a_f_y_soucent_01' },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },

    ['wig_body'] = {
        label = 'Body wig',
        quantity = {min = 1, max = 8},
        price = {min = 275, max = 275},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cs_shopping_bag', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { 'a_f_y_hipster_01',
  'a_f_y_bevhills_01',
  'a_f_y_business_01',
  'a_f_y_soucent_01' },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },

    ['wig_curly'] = {
        label = 'Curly Wig',
        quantity = {min = 1, max = 8},
        price = {min = 375, max = 375},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cs_shopping_bag', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { 'a_f_y_hipster_01',
  'a_f_y_bevhills_01',
  'a_f_y_business_01',
  'a_f_y_soucent_01' },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },

    ['duck_nails'] = {
        label = 'Duck Nails',
        quantity = {min = 1, max = 8},
        price = {min = 175, max = 175},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cs_shopping_bag', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { 'a_f_y_hipster_01',
  'a_f_y_bevhills_01',
  'a_f_y_business_01',
  'a_f_y_soucent_01' },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },

    ['coffin_nails'] = {
        label = 'Coffin Nails',
        quantity = {min = 1, max = 8},
        price = {min = 275, max = 275},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cs_shopping_bag', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { 'a_f_y_hipster_01',
            'a_f_y_bevhills_01',
            'a_f_y_business_01',
            'a_f_y_soucent_01' },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },

    ['square_nails'] = {
        label = 'Square Nails',
        quantity = {min = 1, max = 8},
        price = {min = 300, max = 300},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cs_shopping_bag', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { 'a_f_y_hipster_01',
            'a_f_y_bevhills_01',
            'a_f_y_business_01',
            'a_f_y_soucent_01' },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },

    
    ['layered_wig'] = {
        label = 'Layered Wig',
        quantity = {min = 1, max = 10},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cs_shopping_bag', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { 'a_f_y_hipster_01',
            'a_f_y_bevhills_01',
            'a_f_y_business_01',
            'a_f_y_soucent_01' },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },

    ['headband_wig'] = {
        label = 'Headband Wig',
        quantity = {min = 1, max = 10},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cs_shopping_bag', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { 'a_f_y_hipster_01',
            'a_f_y_bevhills_01',
            'a_f_y_business_01',
            'a_f_y_soucent_01' },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },
    ['locexten'] = {
        label = 'Loc Extensions',
        quantity = {min = 1, max = 10},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_cs_shopping_bag', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { 'a_f_y_hipster_01',
            'a_f_y_bevhills_01',
            'a_f_y_business_01',
            'a_f_y_soucent_01' },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01', 'mp_m_freemode_01' }
    },

    -- Drugs
    ['trapsnacks'] = {
        label = 'Trapsnacks',
        quantity = {min = 1, max = 12},
        price = {min = 475, max = 500},
        leveladd = 8, -- This value represents the amount of level points added when selling this item
        prop = 'prop_meth_bag_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'black_money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 25, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['trap_rock'] = {
        label = 'Trap Rock',
        quantity = {min = 1, max = 12},
        price = {min = 300, max = 325},
        leveladd = 8, -- This value represents the amount of level points added when selling this item
        prop = 'prop_meth_bag_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'black_money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 25, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['jackpot'] = {
        label = 'Jackpot',
        quantity = {min = 1, max = 12},
        price = {min = 475, max = 500},
        leveladd = 8, -- This value represents the amount of level points added when selling this item
        prop = 'prop_meth_bag_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'black_money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 25, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['g6pill'] = {
        label = 'G6 Pill',
        quantity = {min = 1, max = 12},
        price = {min = 475, max = 500},
        leveladd = 8, -- This value represents the amount of level points added when selling this item
        prop = 'prop_meth_bag_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'black_money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 25, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },
    ['trimmed_weed'] = {
        label = 'Trap Packs',
        quantity = {min = 1, max = 12},
        price = {min = 350, max = 350},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_meth_bag_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'black_money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 50, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['cocainepackage'] = {
        label = 'Cocaine Package',
        quantity = {min = 1, max = 12},
        price = {min = 650, max = 700},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'bkr_prop_coke_doll', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'black_money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 50, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['pinkx'] = {
        label = 'Pink X',
        quantity = {min = 1, max = 12},
        price = {min = 650, max = 700},
        leveladd = 7, -- This value represents the amount of level points added when selling this item
        prop = 'prop_meth_bag_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'black_money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 50, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },

    --[[['jordan1_dior'] = {
        label = 'Christian Dior Size 9.5',
        quantity = {min = 1, max = 2},
        price = {min = 2000, max = 4800},
        leveladd = 200, -- This value represents the amount of level points added when selling this item
        prop = 'prop_ld_shoe_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 50, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01' }
    },
    ['dolph_chain'] = {
        label = 'Custom Fake Chain',
        quantity = {min = 1, max = 12},
        price = {min = 50, max = 100},
        leveladd = 200, -- This value represents the amount of level points added when selling this item
        prop = 'p_stretch_necklace_s', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'yellow-diamond'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 50, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01' }
    },

    ['yellow-diamond'] = {
        label = 'Yellow Diamonds',
        quantity = {min = 1, max = 30},
        price = {min = 50, max = 100},
        leveladd = 200, -- This value represents the amount of level points added when selling this item
        prop = 'sf_prop_sf_jewel_01a', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 50, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01' }
    },

    ['coke_small_brick'] = {
        label = 'Small Coke Brick',
        quantity = {min = 1, max = 12},
        price = {min = 400, max = 500},
        leveladd = 200, -- This value represents the amount of level points added when selling this item
        prop = 'bkr_prop_coke_cutblock_01', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'black_money'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 50, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['handbag_leather'] = {
        label = 'Handbang Leather',
        quantity = {min = 10, max = 15},
        price = {min = 1, max = 1},
        leveladd = 250, -- This value represents the amount of level points added when selling this item
        prop = 'w_am_brfcase', -- item exchange prop model (player hands it to buyer)
        -- payout controls how the player is paid for this item
        -- type: 'money' pays via framework account (qbx/qb: cash/bank; esx: cash/bank/black_money)
        -- type: 'item' pays an inventory item with the configured name
        payout = {
            type = 'item',   -- 'money' or 'item'
            name = 'bowling_bag'     -- when type='money': 'cash'|'bank'|'black_money'; when type='item': item name (e.g. 'markedbills')
        },
        -- Optional: restrict which buyer models can purchase this item
        -- Use model names or hashes. Leave nil/empty to allow any from Config.pedlist
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        --allowedPedModels = { 'mp_f_freemode_01', 'a_f_y_hipster_02' }
        -- Optional seller restriction: only players using these ped models can sell this item
        -- Example: restrict to female freemode only => { 'mp_f_freemode_01' }
        -- You can also set a single string like 'mp_f_freemode_01'
        -- Leave nil/empty to allow all player models
        allowedSellerModels = { 'mp_f_freemode_01' }
    },

    -- Bootleg street hustle items
    ['bootleg_dvd'] = {
        label = 'Bootleg DVD',
        quantity = { min = 1, max = 5 },
        price = { min = 5, max = 15 },
        leveladd = 3,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['bootleg_cd'] = {
        label = 'Bootleg CD',
        quantity = { min = 1, max = 5 },
        price = { min = 3, max = 10 },
        leveladd = 3,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['bootleg_game'] = {
        label = 'Bootleg Video Game',
        quantity = { min = 1, max = 3 },
        price = { min = 10, max = 25 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_j_sneakers'] = {
        label = 'Fake Js',
        quantity = { min = 1, max = 2 },
        price = { min = 25, max = 60 },
        leveladd = 5,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_y_sneakers'] = {
        label = 'Fake Yees',
        quantity = { min = 1, max = 2 },
        price = { min = 30, max = 70 },
        leveladd = 5,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_n_sneakers'] = {
        label = 'Fake Zikes',
        quantity = { min = 1, max = 2 },
        price = { min = 20, max = 45 },
        leveladd = 5,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_af_sneakers'] = {
        label = 'Fake Forces',
        quantity = { min = 1, max = 2 },
        price = { min = 20, max = 40 },
        leveladd = 5,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_g_belt'] = {
        label = 'Fake Belt',
        quantity = { min = 1, max = 3 },
        price = { min = 15, max = 35 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_lv_bag'] = {
        label = 'Fake Bag',
        quantity = { min = 1, max = 2 },
        price = { min = 30, max = 75 },
        leveladd = 5,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_designer_shirt'] = {
        label = 'Fake Designer Shirt',
        quantity = { min = 1, max = 3 },
        price = { min = 10, max = 25 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_designer_hat'] = {
        label = 'Fake Designer Hat',
        quantity = { min = 1, max = 3 },
        price = { min = 8, max = 20 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_designer_glasses'] = {
        label = 'Fake Designer Shades',
        quantity = { min = 1, max = 4 },
        price = { min = 5, max = 15 },
        leveladd = 3,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_gold_chain'] = {
        label = 'Fake Gold Chain',
        quantity = { min = 1, max = 2 },
        price = { min = 15, max = 40 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_watch'] = {
        label = 'Fake Watch',
        quantity = { min = 1, max = 2 },
        price = { min = 25, max = 60 },
        leveladd = 5,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_earrings'] = {
        label = 'Fake Earrings',
        quantity = { min = 1, max = 3 },
        price = { min = 10, max = 25 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_bracelet'] = {
        label = 'Fake Gold Bracelet',
        quantity = { min = 1, max = 3 },
        price = { min = 12, max = 30 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_airpods'] = {
        label = 'AirNods',
        quantity = { min = 1, max = 3 },
        price = { min = 10, max = 25 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_beats'] = {
        label = 'Heats Headphones',
        quantity = { min = 1, max = 2 },
        price = { min = 15, max = 35 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['bootleg_charger'] = {
        label = 'Bootleg Charger',
        quantity = { min = 1, max = 5 },
        price = { min = 3, max = 8 },
        leveladd = 3,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_phone'] = {
        label = 'tPhone',
        quantity = { min = 1, max = 2 },
        price = { min = 15, max = 35 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_tablet'] = {
        label = 'iPed',
        quantity = { min = 1, max = 2 },
        price = { min = 15, max = 35 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_cologne'] = {
        label = 'Fake Cologne',
        quantity = { min = 1, max = 3 },
        price = { min = 8, max = 20 },
        leveladd = 3,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_perfume'] = {
        label = 'Fake Perfume',
        quantity = { min = 1, max = 3 },
        price = { min = 8, max = 20 },
        leveladd = 3,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['bootleg_jersey'] = {
        label = 'Bootleg Jersey',
        quantity = { min = 1, max = 2 },
        price = { min = 12, max = 30 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['fake_wallet'] = {
        label = 'Fake Designer Wallet',
        quantity = { min = 1, max = 3 },
        price = { min = 10, max = 25 },
        leveladd = 4,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    ['loose_cigs'] = {
        label = 'Loose Cigarettes',
        quantity = { min = 1, max = 10 },
        price = { min = 1, max = 3 },
        leveladd = 2,
        prop = 'prop_ld_shoe_01',
        payout = { type = 'item', name = 'money' },
        dispatch = { enabled = true, chance = 10, message = 'Street deal reported', code = '10-66' },
        allowedPedModels = { nil },
        allowedSellerModels = { 'mp_m_freemode_01', 'mp_f_freemode_01' }
    },

    -- Examples below demonstrate per-item prop control for the handoff animation.
    -- Adjust labels/economy to your server’s balance.
    --[[['weed_packaged'] = {
        label = 'Weed (Packaged)',
        quantity = { min = 1, max = 3 },
        price = { min = 75, max = 125 },
        leveladd = 20,
        prop = 'prop_weed_bottle',
        payout = { type = 'money', name = 'cash' },
        -- Optional per-item dispatch override
        -- dispatch = { enabled = false, chance = 0, message = 'Street deal reported', code = '10-66' }
    },

    ['meth_packaged'] = {
        label = 'Meth (Packaged)',
        quantity = { min = 1, max = 2 },
        price = { min = 150, max = 250 },
        leveladd = 30,
        prop = 'prop_syringe_01',
        payout = { type = 'money', name = 'cash' },
        dispatch = { enabled = true, chance = 35 } -- example per-item override
    },

    ['cocaine_packaged'] = {
        label = 'Cocaine (Packaged)',
        quantity = { min = 1, max = 2 },
        price = { min = 200, max = 300 },
        leveladd = 40,
        prop = 'prop_meth_bag_01',
        payout = { type = 'money', name = 'cash' },
        dispatch = { enabled = true, chance = 40 }
    },

    ['lean'] = {
        label = 'Lean',
        quantity = { min = 1, max = 2 },
        price = { min = 100, max = 180 },
        leveladd = 25,
        prop = 'prop_syringe_01',
        payout = { type = 'money', name = 'cash' },
        dispatch = { enabled = true, chance = 45 }
    },

    ['molly'] = {
        label = 'Molly',
        quantity = { min = 1, max = 3 },
        price = { min = 120, max = 200 },
        leveladd = 25,
        prop = 'prop_meth_bag_01',
        payout = { type = 'money', name = 'cash' },
        dispatch = { enabled = true, chance = 30 }
    },

    ['perc'] = {
        label = 'Percocet',
        quantity = { min = 1, max = 3 },
        price = { min = 90, max = 160 },
        leveladd = 20,
        prop = 'prop_meth_bag_01',
        payout = { type = 'money', name = 'cash' },
        dispatch = { enabled = true, chance = 30 }
    },]]

}



-- Default prop to use if a specific item entry does not define `prop` above
-- You can set this to any valid model name (string) or a hash.
Config.ItemPropFallback = 'prop_meth_bag_01'

-- Dispatch integration and notifications when a sale occurs
-- Systems supported: 'cd' (cd_dispatch), 'ps' (ps-dispatch), 'lb' (lb-tablet), 'basic' (notify police online), 'none'
Config.Dispatch = {
    enabled = true,          -- master switch
    system = 'cd',           -- 'cd' | 'ps' | 'lb' | 'basic' | 'none'
    chance = 30,             -- percent chance to alert on a sale (overridden per item if set)
    jobs = { 'police', 'sheriff', 'bcso', 'sasp', 'lspd', 'ranger' }, -- who gets alerts

    -- Common message defaults (can be overridden per item via Config.DrugList[item].dispatch)
    -- Placeholders: {item}/{label}, {street}, {zone}
    title = 'Drug Deal In Progress',
    message = 'Possible sale of {label} near {street} ({zone}).',
    code = '10-66',
    includeCodeInTitle = true, -- when true, prefixes {code} to the title unless already present

    -- cd_dispatch specific settings
    cd = {
        blipTime = 75,       -- seconds blip persists
        radius = 85.0,
        sprite = 51,
        color = 1,
        scale = 1.2,
        -- Per-department style overrides (optional)
        -- Each entry can specify sprite/color/scale/radius
        styles = {
            police = { sprite = 51, color = 3 },   -- blue
            lspd   = { sprite = 51, color = 3 },   -- blue
            sheriff= { sprite = 51, color = 5 },   -- yellow/gold
            bcso   = { sprite = 51, color = 5 },
            sasp   = { sprite = 51, color = 29 },  -- SAHP style
            ranger = { sprite = 51, color = 2 }    -- green
        }
    },

    -- ps-dispatch integration is highly configurable across versions.
    -- If your server uses a custom wrapper, specify event or use exports in your fork.
    ps = {
        -- example fallbacks; adapt to your ps-dispatch
        event = nil,         -- e.g. 'ps-dispatch:server:Notify'
    },

    -- lb-tablet integration varies per fork; provide your server event if needed.
    lb = {
        event = 'lb-tablet:server:sendDispatch',         -- e.g. 'lb-tablet:server:sendDispatch'
    },

    -- basic notifier (used when system = 'basic' or as fallback)
    basic = {
        blip = true,         -- show a temporary radius blip to police
        blipTime = 45,       -- seconds
        radius = 85.0,
        color = 1,
        alpha = 175
    }
}

-- Leveling controls
-- Controls how many level points are awarded after each sale
-- Uses the per-item `leveladd` from Config.DrugList[...] and applies these multipliers
Config.Leveling = {
    baseMultiplier = 1,       -- always applied
    hotspotMultiplier = 2,    -- applied when within a hotspot zone
    useHotspotMultiplier = false -- set false to ignore hotspot bonus
}

-- Buyer NPC behavior
-- Control how fast the buyer walks/runs toward the player
-- Typical values: 1.0 (walk), 1.5 (brisk), 2.0 (run)
Config.Buyer = {
    speed = 1.5,
    stopDistance = 1.8, -- how close buyer gets before stopping near the player
    denialChance = 15 -- percent chance the buyer declines the deal
}

-- Reward options
-- If you use vehicle rewards, set a handler to add/store the vehicle in your garage system.
-- The handler should be a server event you implement elsewhere, signature:
-- AddEventHandler('myVehicleHandler', function(source, model, data) ... end)

Config.maxDisplayedInLeaderBoard = 5
Config.levels = {
    [1] = { points = 1000, percentmore = 10, lable = 'Risk Taker',
        reward = { type = 'money', account = 'cash', amount = 25000 }
    },

    [2] = { points = 2000, percentmore = 20, lable = 'Finessor',
        reward = { type = 'money', account = 'cash', amount = 50000 }
    },

    [3] = { points = 3200, percentmore = 30, lable = 'Hustler',
        reward = { type = 'item', name = 'trimmed_weed', amount = 20 }
    },

    [4] = { points = 4800, percentmore = 40, lable = 'Bag Chaser',
        reward = { type = 'money', account = 'cash', amount = 100000 }
    },

    [5] = { points = 6500, percentmore = 50, lable = 'Neighborhood Plug',
        reward = { type = 'vehicle', model = 'buccaneer' }
    },

    [6] = { points = 8500, percentmore = 60, lable = 'Street Supplier',
        reward = { type = 'item', name = 'trimmed_weed', amount = 40 }
    },

    [7] = { points = 11000, percentmore = 70, lable = 'Corner Boss',
        reward = { type = 'money', account = 'cash', amount = 200000 }
    },

    [8] = { points = 14000, percentmore = 80, lable = 'Block Controller',
        reward = { type = 'item', name = 'durag_silky', amount = 5 }
    },

    [9] = { points = 18000, percentmore = 90, lable = 'Supply Chain',
        reward = { type = 'money', account = 'cash', amount = 300000 }
    },

    [10] = { points = 23000, percentmore = 100, lable = 'City Plug',
        reward = { type = 'vehicle', model = 'schafter3' }
    },

    [11] = { points = 29000, percentmore = 110, lable = 'Wholesale King',
        reward = { type = 'item', name = 'jordan_11s', amount = 2 }
    },

    [12] = { points = 36000, percentmore = 120, lable = 'Distribution Lord',
        reward = { type = 'money', account = 'cash', amount = 500000 }
    },

    [13] = { points = 44000, percentmore = 130, lable = 'Market Controller',
        reward = { type = 'item', name = 'atl_braves_hat', amount = 3 }
    },

    [14] = { points = 53000, percentmore = 140, lable = 'Underworld Exec',
        reward = { type = 'money', account = 'cash', amount = 750000 }
    },

    [15] = { points = 65000, percentmore = 150, lable = 'Street Legend',
        reward = { type = 'vehicle', model = 'buffalo2' }
    },

    [16] = { points = 80000, percentmore = 160, lable = 'Trap General',
        reward = { type = 'money', account = 'cash', amount = 250000 }
    },

    [17] = { points = 98000, percentmore = 170, lable = 'Kingpin Associate',
        reward = { type = 'item', name = 'cocainepackage', amount = 10 }
    },

    [18] = { points = 120000, percentmore = 180, lable = 'Area Overlord',
        reward = { type = 'vehicle', model = 'baller4' }
    },

    [19] = { points = 145000, percentmore = 190, lable = 'Cartel Affiliate',
        reward = { type = 'money', account = 'cash', amount = 250000 }
    },

    [20] = { points = 175000, percentmore = 200, lable = 'Street Mogul',
        reward = { type = 'vehicle', model = 'jugular' }
    },

    [21] = { points = 210000, percentmore = 210, lable = 'Black Market Tycoon',
        reward = { type = 'item', name = 'pinkx', amount = 25 }
    },

    [22] = { points = 250000, percentmore = 220, lable = 'Underworld Mogul',
        reward = { type = 'money', account = 'cash', amount = 250000 }
    },

    [23] = { points = 300000, percentmore = 230, lable = 'Global Supplier',
        reward = { type = 'vehicle', model = 'toros' }
    },

    [24] = { points = 360000, percentmore = 240, lable = 'Shadow Executive',
        reward = { type = 'money', account = 'cash', amount = 250000 }
    },

    [25] = { points = 450000, percentmore = 250, lable = 'The Untouchable',
        reward = { type = 'vehicle', model = 'xls2' }
    },

}

Config.Zones = {

    --Bodega GasStation
    { coords = vector3(-3684.3054, -1578.5535, 27.6123), maxRange = 50.0 },
    --Grove
    { coords = vector3(-4453.4141, -1752.0941, 14.6699), maxRange = 50.0 },
    --Grove Gas
    { coords = vector3(-4621.7983, -1745.2939, 20.2056), maxRange = 50.0 },
    -- Bike Park
    { coords = vector3(-4644.7651, -1870.8438, 19.9619), maxRange = 50.0 },
    -- Car Wash
    { coords = vector3(-4287.4028, -1777.4739, 16.8824), maxRange = 50.0 },
    -- Motel
    { coords = vector3(-4103.5142, -1951.6129, 24.1761), maxRange = 50.0 },
    -- A Block
    { coords = vector3(-4210.1152, -1663.9561, 18.4050), maxRange = 50.0 },
    -- B Block
    { coords = vector3(-4281.8994, -1674.5725, 15.0689), maxRange = 50.0 },
    -- C Block
    { coords = vector3(-4349.3306, -1638.7477, 14.0189), maxRange = 50.0 },
    -- D Block
    { coords = vector3(-4438.9946, -1604.4406, 16.8027), maxRange = 50.0 },
    -- Random Parking Lot
    { coords = vector3(-4214.6587, -1560.2581, 18.7724), maxRange = 50.0 },
    -- North Middle Mall Lot
    { coords = vector3(-4904.3472, -1795.6555, 20.1013), maxRange = 50.0 },
    -- North End Mall Lot
    { coords = vector3(-4985.0054, -1795.7137, 20.1012), maxRange = 50.0 },
    -- Back of Mall
    { coords = vector3(-4992.5894, -1947.9410, 20.1012), maxRange = 50.0 },
    -- South End Mall Lot
    { coords = vector3(-4968.7202, -2112.6333, 20.1012), maxRange = 50.0 },
    -- South Middle Mall Lot
    { coords = vector3(-4884.4150, -2112.5657, 20.1012), maxRange = 50.0 },
    -- 90sBloodz
    { coords = vector3(-4250.3477, -2128.3389, 25.4189), maxRange = 50.0 },
    -- EastSide 162
    { coords = vector3(-4039.1096, -1808.1833, 25.0016), maxRange = 50.0 },
    -- Nawfside Park
    { coords = vector3(-4057.5947, -1198.9781, 26.0177), maxRange = 50.0 },
    -- 1300 Bloodbath
    { coords = vector3(-4327.7192, -1427.5680, 15.8340), maxRange = 50.0 },
    -- KTM
    { coords = vector3(-4694.8418, -1992.9508, 18.2355), maxRange = 50.0 },

}


Config.pedlist = {
    [1] = 'g_f_y_families_01',
    [2] = 'g_m_y_ballaeast_01',
    [3] = 'g_f_y_ballas_01',
    [4] = 'g_m_y_ballaorig_01',
    [5] = 'g_m_y_ballaorig_01',
    [6] = 'g_f_y_vagos_01',
    [7] = 'g_m_y_ballasout_01',
    [8] = 'g_m_y_famca_01',
    [9] = 'g_m_y_famdnf_01'
}


Config.Offsets = {
    [1] = {x = 0.0, y = 5.0},
    [2] = {x = 0.0, y = -5.0},
    [3] = {x = 5.0, y = 0.0},
    [4] = {x = -5.0, y = 0.0},
    [5] = {x = 5.0, y = 5.0},
    [6] = {x = -5.0, y = 5.0},
    [7] = {x = 5.0, y = -5.0},
    [8] = {x = -5.0, y = -5.0},
    [9] = {x = 0.0, y = 15.0},
    [10] = {x = 0.0, y = -15.0},
    [11] = {x = 5.0, y = 0.0},
    [12] = {x = -5.0, y = 0.0},
    [13] = {x = 5.0, y = 5.0},
    [14] = {x = -5.0, y = 15.0},
    [15] = {x = 15.0, y = -5.0},
    [16] = {x = -5.0, y = -5.0},
    [17] = {x = 0.0, y = 10.0},
    [18] = {x = 0.0, y = -10.0},
    [19] = {x = 10.0, y = 0.0},
    [20] = {x = -10.0, y = 0.0},
    [21] = {x = 10.0, y = 10.0},
    [22] = {x = -10.0, y = 10.0},
    [23] = {x = 10.0, y = -10.0},
    [24] = {x = -10.0, y = -10.0}
}
