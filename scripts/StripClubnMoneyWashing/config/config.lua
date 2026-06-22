Config = {}

--[[
    Framework + inventory configuration
    mode:           'auto', 'esx', 'qb', 'qbox', or 'standalone'
    inventory:      'auto' to prefer ox_inventory when available, otherwise specify 'ox'
    transactionReason: optional reason string passed to framework money handlers where supported
]]
Config.Framework = {
    mode = 'auto',
    inventory = 'auto',
    transactionReason = 'club_dancer_payout'
}

-- General settings
Config.Debug                    = false                     -- Enable to visualise target zones and debug prints
Config.LoopDances               = true                      -- Loop pole dance animations
Config.TargetSprites            = false                     -- Draw sprites for ox_target zones
Config.PromptPosition           = 'left-center'             -- ox_lib text UI anchor position
Config.LeanIcon                 = 'fas fa-money-bill-wave'  -- Icon used for lean/tip target options
Config.TipOptions = {                                       -- Slider configuration for tip selection
    default = 150,                                          -- Starting value for the slider
    min = 50,                                               -- Minimum allowed tip
    max = 5000,                                             -- Maximum allowed tip
    step = 50,                                              -- Step size between values
    title = 'Select tip amount',                           -- Title shown on the slider dialog
    label = 'Amount'                                       -- Label shown next to the slider
}
Config.SocietyCut               = 20                        -- Baseline tax percentage (used if level data missing)
Config.DancerCut                = 25                        -- Percentage of the tax that goes to the active dancer
Config.WashingWaitTime          = 4                         -- Seconds to wait before returning clean money
Config.TipSyncRadius            = 25.0                      -- Nearby player radius for synced tip prop/ptfx

-- XP and progression
Config.Experience = {
    tip = 2,                                               -- XP gained when tipping with clean money
    wash = 5                                               -- XP gained when washing dirty money
}

-- Money wash levels (ascending by xp). "taxRate" replaces Config.SocietyCut at that level.
Config.Levels = {
    { xp = 0,    name = 'Rookie Cleaner',        taxRate = 20 },
    { xp = 2500,  name = 'Stage Regular',         taxRate = 19 },
    { xp = 6000,  name = 'Backroom Associate',    taxRate = 18 },
    { xp = 10000, name = 'Trusted Washer',        taxRate = 17 },
    { xp = 15000, name = 'Club Insider',         taxRate = 16 },
    { xp = 21000, name = 'Money Maestro',         taxRate = 15 },
    { xp = 28000, name = 'Nightlife Financier',   taxRate = 14 },
    { xp = 36000, name = 'City Launderer',        taxRate = 13 },
    { xp = 45000, name = 'Executive Cleaner',     taxRate = 12 },
    { xp = 55000, name = 'Underworld Treasurer',  taxRate = 10 }
}

-- Society payout behaviour
Config.Society = {
    enabled = false,
    accountPrefix = 'society_',
    fallback = { job = 'unicorn', account = 'society_unicorn' },
    pedShare = 'society'
}

-- Tipping visuals and prop timing
Config.Tip = {
    name     = 'makeitrain',
    anim     = {
        dict = 'anim@mp_player_intupperraining_cash',
        clip = 'idle_a'
    },
    prop     = {
        bone  = 60309,
        model = 'prop_anim_cash_pile_01',
        pos   = vec3(0.0, 0.0, 0.0),
        rot   = vec3(180.0, 0.0, 70.0)
    },
    ptfx     = {
        asset = 'scr_xs_celebration',
        name  = 'scr_xs_money_rain',
        bone  = 60309,
        placement = {
            vec3(0.0, 0.08, 0.0),
            vec3(98.0, 180.0, 5.0)
        }
    },
    releaseDelay = 2600,
    sequenceEndDelay = 4000,
    floorLifetime = 12000,
    maxDroppedProps = 8,
    drop = {
        height = 0.85,
        forward = 0.75,
        speed = 3.0,
        upward = 0.55,
        velocity = { x = 0.0, y = 0.0, z = -0.15 }
    }
}
-- Global animation definitions that can be referenced by players and peds
Config.Animations = {
    -- 1
    {
        id = 'pole_routine_a',
        label = 'Pole Routine A',
        dict = 'mini@strip_club@pole_dance@pole_dance1',
        anim = 'pd_dance_01',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 2
    {
        id = 'pole_routine_b',
        label = 'Pole Routine B',
        dict = 'mini@strip_club@pole_dance@pole_dance2',
        anim = 'pd_dance_02',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 3
    {
        id = 'pole_routine_c',
        label = 'Pole Routine C',
        dict = 'mini@strip_club@pole_dance@pole_dance3',
        anim = 'pd_dance_03',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 4
    {
        id = 'twerking_2',
        label = 'Twerking #2',
        dict = 'divined@drillb2@new',
        anim = 'splitstwerk2',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 5
    {
        id = 'hoe_twerk',
        label = 'Hoe Twerk',
        dict = 'gway@freakhoe1_4',
        anim = 'freakhoe4_clip',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 6
    {
        id = 'bounce_that_ass_5',
        label = 'BOUNCE THAT ASS 5',
        dict = 'gta6twerk5@lanisha',
        anim = 'lanisha',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 7
    {
        id = 'player_club',
        label = 'Player Club',
        dict = 'gway@pc',
        anim = 'gway',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 8
    {
        id = 'player_club_2',
        label = 'Player Club 2',
        dict = 'gway@pc2',
        anim = 'gway',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 9
    {
        id = 'player_club_3',
        label = 'Player Club 3',
        dict = 'gway@pc3',
        anim = 'gway',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 10
    {
        id = 'twerk_it_1',
        label = 'Twerk it',
        dict = 'satocmods@twerkaa01',
        anim = 'satocmods@twerkaa01clip',
        scene = true,
        icon = 'fas fa-person-running'
    },
    -- 11
    {
        id = 'twerk_it_2',
        label = 'Twerk it 2',
        dict = 'satocmods@throwdat03',
        anim = 'satocmods@throwdatclip',
        scene = true,
        icon = 'fas fa-person-running'
    }
}

Config.PoleProps = {
    ['prop_strip_pole_01'] = true,
}

-- Club layout
Config.ClubZones = {
    {
        id = 'vu_main_stage',
        label = 'Vanilla Unicorn Main Stage',
        society = { job = 'stripclub', account = 'society_stripclub' },
        poleDanceAreaDefaults = {
            enabled = true,
            radius = 3.0,
            animations = { 4, 5, 6, 12, 13 }
        },
        poles = {
            {
                id = 'vu_center',
                label = 'Vanilla Unicorn',
                coords = vector3(1102.9336, -285.9913, 61.6543),
                radius = 1.1,
                animations = { 1, 2, 3, 9, 10, 11 },
                danceArea = {
                    radius = 3.0
                },
                ped = {
                    enabled = false,
                    model = 's_f_y_stripper_01',
                    heading = 160.0,
                    freeze = true,
                    animations = { 1, 2, 3 },
                    cycle = {
                        enabled = true,
                        interval = 30
                    },
                    wash = {
                        enabled = true,
                        icon = 'fas fa-hand-holding-usd',
                        label = 'Tip the dancer',
                        distance = 5.0
                    }
                }
            },
            {
                id = 'vu_custom_1',
                label = 'Vanilla Unicorn Custom 1',
                coords = vector3(1106.8737, -280.6657, 61.6543),
                radius = 1.1,
                animations = { 1, 2, 3, 9, 10, 11 },
                danceArea = {
                    radius = 3.0
                },
                ped = {
                    enabled = true,
                    model = 's_f_y_stripper_01',
                    heading = 98.7812,
                    freeze = true,
                    animations = { 2, 1, 3 },
                    cycle = {
                        enabled = true,
                        interval = 30
                    },
                    wash = {
                        enabled = true,
                        icon = 'fas fa-hand-holding-usd',
                        label = 'Tip the dancer',
                        distance = 5.0
                    }
                }
            },
            {
                id = 'vu_custom_4',
                label = 'Vanilla Unicorn Custom 1',
                coords = vector3(1097.4098, -282.5045, 61.8243),
                radius = 1.1,
                animations = { 1, 2, 3, 9, 10, 11 },
                danceArea = {
                    radius = 3.0
                },
                ped = {
                    enabled = false,
                    model = 's_f_y_stripper_01',
                    heading = 138.9866,
                    freeze = true,
                    animations = { 2, 1, 3 },
                    cycle = {
                        enabled = true,
                        interval = 30
                    },
                    wash = {
                        enabled = true,
                        icon = 'fas fa-hand-holding-usd',
                        label = 'Tip the dancer',
                        distance = 5.0
                    }
                }
            },
            {
                id = 'vu_custom_5',
                label = 'Vanilla Unicorn Custom 1',
                coords = vector3(1091.5162, -274.5473, 62.9180),
                radius = 1.1,
                animations = { 1, 2, 3, 9, 10, 11 },
                danceArea = {
                    radius = 3.0
                },
                ped = {
                    enabled = false,
                    model = 's_f_y_stripper_01',
                    heading = 138.9866,
                    freeze = true,
                    animations = { 2, 1, 3 },
                    cycle = {
                        enabled = true,
                        interval = 30
                    },
                    wash = {
                        enabled = true,
                        icon = 'fas fa-hand-holding-usd',
                        label = 'Tip the dancer',
                        distance = 5.0
                    }
                }
            },
            {
                id = 'vu_custom_6',
                label = 'Vanilla Unicorn Custom 1',
                coords = vector3(1087.2172, -280.9144, 62.9180),
                radius = 1.1,
                animations = { 1, 2, 3, 9, 10, 11 },
                danceArea = {
                    radius = 3.0
                },
                ped = {
                    enabled = false,
                    model = 's_f_y_stripper_01',
                    heading = 138.9866,
                    freeze = true,
                    animations = { 2, 1, 3 },
                    cycle = {
                        enabled = true,
                        interval = 30
                    },
                    wash = {
                        enabled = true,
                        icon = 'fas fa-hand-holding-usd',
                        label = 'Tip the dancer',
                        distance = 5.0
                    }
                }
            },
            {
                id = 'vu_custom_7',
                label = 'Vanilla Unicorn Custom 1',
                coords = vector3(1095.6099, -267.9929, 62.9180),
                radius = 1.1,
                animations = { 1, 2, 3, 9, 10, 11 },
                danceArea = {
                    radius = 3.0
                },
                ped = {
                    enabled = false,
                    model = 's_f_y_stripper_01',
                    heading = 138.9866,
                    freeze = true,
                    animations = { 2, 1, 3 },
                    cycle = {
                        enabled = true,
                        interval = 30
                    },
                    wash = {
                        enabled = true,
                        icon = 'fas fa-hand-holding-usd',
                        label = 'Tip the dancer',
                        distance = 5.0
                    }
                }
            },
            {
                id = 'vu_custom_2',
                label = 'Vanilla Unicorn Custom 2',
                coords = vector3(1100.9138, -277.4283, 61.6543),
                radius = 1.1,
                animations = { 1, 2, 3, 9, 10, 11 },
                danceArea = {
                    radius = 3.0
                },
                ped = {
                    enabled = true,
                    model = 's_f_y_stripper_01',
                    heading = 184.5134,
                    freeze = true,
                    animations = { 3, 1, 2 },
                    cycle = {
                        enabled = true,
                        interval = 30
                    },
                    wash = {
                        enabled = true,
                        icon = 'fas fa-hand-holding-usd',
                        label = 'Tip the dancer',
                        distance = 5.0
                    }
                }
            }
        }
    }
}



