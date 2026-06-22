-- ==========================================
-- [[ KEY TIERS ]]
-- ==========================================

Config.KeyTiers = {
    basic = {
        Item = Config.Items.BasicVehicleKey,
        BlankItem = Config.Items.LocksmithBlankBasicKey,
        Label = 'Basic Vehicle Key',
        UpgradeLabel = 'Basic Key System',
        UpgradePrice = 250,
        Capabilities = {
            lock = true,
            unlock = true,
            toggle = true
        }
    },
    smart = {
        Item = Config.Items.SmartVehicleKey,
        BlankItem = Config.Items.LocksmithBlankSmartKey,
        Label = 'Smart Vehicle Key',
        UpgradeLabel = 'Smart Key System',
        UpgradePrice = 750,
        Capabilities = {
            lock = true,
            unlock = true,
            toggle = true,
            nui = true,
            trunk = true,
            alarm = true,
            headlights = true,
            info = true
        }
    },
    advanced = {
        Item = Config.Items.AdvancedSmartVehicleKey,
        BlankItem = Config.Items.LocksmithBlankAdvancedKey,
        Label = 'Advanced Smart Vehicle Key',
        UpgradeLabel = 'Advanced Smart Key System',
        UpgradePrice = 1500,
        Capabilities = {
            lock = true,
            unlock = true,
            toggle = true,
            nui = true,
            trunk = true,
            alarm = true,
            headlights = true,
            info = true,
            remote_engine = true,
            proximity = true
        },
        Proximity = {
            UnlockDistance = 4.0,
            LockDistance = 8.0
        }
    },
    oled = {
        Item = Config.Items.OLEDVehicleKey,
        BlankItem = Config.Items.LocksmithBlankOLEDKey,
        Label = 'OLED Vehicle Key',
        UpgradeLabel = 'OLED Key System',
        UpgradePrice = 3000,
        Capabilities = {
            lock = true,
            unlock = true,
            toggle = true,
            nui = true,
            trunk = true,
            alarm = true,
            headlights = true,
            info = true,
            remote_engine = true,
            oled = true,
            proximity = true,
            valet = true
        },
        Proximity = {
            UnlockDistance = 4.0,
            LockDistance = 8.0
        },
        Valet = {
            MaxDistance = 50.0
        }
    }
}

Config.KeyTierOrder = { 'basic', 'smart', 'advanced', 'oled' }
Config.DefaultKeyTier = 'smart'

-- GTA vehicle class defaults. Model overrides below can force a tier for specific custom vehicles.
Config.VehicleClassKeyTiers = {
    [0] = 'basic',     -- Compacts
    [1] = 'basic',     -- Sedans
    [2] = 'smart',     -- SUVs
    [3] = 'smart',     -- Coupes
    [4] = 'smart',     -- Muscle
    [5] = 'smart',     -- Sports Classics
    [6] = 'advanced',  -- Sports
    [7] = 'advanced',  -- Super
    [8] = 'basic',     -- Motorcycles
    [9] = 'smart',     -- Off-road
    [10] = 'basic',    -- Industrial
    [11] = 'basic',    -- Utility
    [12] = 'basic',    -- Vans
    [13] = 'basic',    -- Cycles
    [14] = 'smart',    -- Boats
    [15] = 'advanced', -- Helicopters
    [16] = 'advanced', -- Planes
    [17] = 'basic',    -- Service
    [18] = 'smart',    -- Emergency
    [19] = 'advanced', -- Military
    [20] = 'basic',    -- Commercial
    [21] = 'advanced'  -- Trains
}

Config.VehicleModelKeyTiers = {}
