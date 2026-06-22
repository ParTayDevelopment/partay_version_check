
Config = {}

-- Framework selection
-- Options: 'auto' | 'esx' | 'qb' | 'qbox' | 'standalone'
-- - auto: detect ESX first, then QBCore/Qbox
-- - esx: force ESX integration; falls back to standalone if not running
-- - qb: force QBCore/Qbox integration (prefers qb-core, then qbx-core)
-- - qbox: force Qbox (qbx-core) integration
-- - standalone: disable framework integration (items-only checks)
Config.Framework           = 'auto'

Config.Debug                = true     -- Enable visible polyzones for debugging/configuring | Default: false
Config.DebugAccess          = false    -- Print access decisions (job/items/wristband/denials) to F8 console
Config.MinusOneZForEntries  = true      -- Minus 1 in the Z axis for entry coords (prevents floating when using unmodified coords) | Default: true
Config.FreezeOnReject       = false     -- Temporarily freeze the player if entry is denied | Default: false
Config.FreezeTime           = 800       -- Time (ms) before unfreezing the player (if Config.FreezeTime is true) | Default: 800
Config.WristBandTime        = 3600       -- Time (s) after using an item for entry, before they are checked for an item again when re-entering | Default: 300
Config.RequireItemEvenWithJob = false   -- If true and a zone has items configured, require one even if job is allowed
Config.BuilderAutoCloseOnExport = true  -- After a successful Export, auto-close the movement overlay; use /rzmenu to edit further

-- Locale/language (for ox_lib locales in locales/*.json)
-- Supported examples: 'en', 'es', 'fr', 'ar'
Config.Locale              = 'en'

Config.Notify = function(msg, type)     -- Custom client-side notification function
    TriggerEvent("ox_lib:notify", {
        title = "Restricted Zone",
        description = msg,
        type = type
    })
end

-- Builder access control (who can open the in-game zone builder)
-- Any of these can grant access: ACE or job rules.
-- jobs map:
--   jobName = true                -> any grade of this job
--   jobName = number              -> minimum numeric grade/level required
--   jobName = { min = N }         -> minimum numeric grade/level required
--   jobName = { grades = {"boss","chief"} } -> allow listed grade names
--   jobName = { min = N, grades = {...} }    -> either condition passes
Config.BuilderAccess = {
    -- ACE disabled; only job-based access is used
    ace = false,
    jobs = {
        -- SPECIFIC JOB ONLY (edit to your target job)
        -- Example: allow school staff (min grade 1 or specific grade names)
        school = { min = 1, grades = { 'director', 'teacher' } },
    }
}

-- Builder command configuration
Config.BuilderCommand = 'rz'          -- Command name to open the builder

Config.Zones = {
    ["Example Zone 1"] = {
        entries = {
            vector4(-4699.8135, -1606.8185, 22.1363, 28.8113),
            vector4(-4708.6641, -1612.5114, 22.1363, 28.6278),
        },
        points = {
            vector2(-4698.3560, -1602.4143),
            vector2(-4712.7217, -1610.7047),
            vector2(-4715.3447, -1608.7612),
            vector2(-4699.7563, -1599.5359),
        },
        minZ = 21.1921,
        maxZ = 24.1921,
        jobs = { "police" },
        items = { "skate_ticket" },
        removeItem = true,
    },

    ["Example Zone 2"] = {
        entries = {
            vector4(-3987.8123, -1751.0035, 25.2120, 355.3788),
        },
        points = {
            vector2(-3963.8689, -1745.7391),
            vector2(-3995.2441, -1745.3409),
            vector2(-4000.2485, -1740.0175),
            vector2(-4062.9995, -1739.2950),
            vector2(-4060.5208, -1607.7386),
            vector2(-3961.4519, -1609.6185),
        },
        minZ = 22.3516,
        maxZ = 26.3516,
        jobs = { "police", "ambulance" },
        items = { "student_id" },
        removeItem = false,
    },

    ["Airport Check in"] = {
        entries = {
            vector4(-1064.1104, -2796.8167, 21.5313, 145.1433),
            vector4(-1078.4507, -2839.4573, 21.5311, 234.6497),
        },
        points = {
            vector2(-1071.00, -2796.31),
            vector2(-1060.34, -2802.52),
            vector2(-1028.61, -2820.79),
            vector2(-1044.73, -2848.67),
            vector2(-1050.80, -2842.44),
            vector2(-1055.65, -2849.42),

            vector2(-1053.60, -2850.53),
            vector2(-1056.40, -2855.48),
            vector2(-1076.50, -2843.63),
            vector2(-1073.21, -2839.04),
            vector2(-1059.90, -2846.85),

            vector2(-1059.90, -2846.85),
            vector2(-1056.94, -2841.58),
            vector2(-1087.13, -2824.22),
        },
        minZ = 19.36,
        maxZ = 23.36,
        jobs = { "police", "ambulance", "nolovelostairlines" },
        items = { "plane_ticket" },
        removeItem = false,
    },

    ["Airport exit"] = {
        entries = {
            vector4(-1111.1122, -2776.3423, 16.7606, 47.1028),
            vector4(-1114.5358, -2761.5642, 16.7608, 229.9437),
            vector4(-1117.0670, -2791.3069, 16.7606, 50.8482),
            vector4(-1119.9635, -2803.1523, 16.7606, 53.2623),
        },
        points = {
            vector2(-1111.34, -2770.42),
            vector2(-1134.34, -2810.86),
            vector2(-1142.42, -2806.17),
            vector2(-1120.14, -2767.51),
            vector2(-1118.15, -2767.66),
            vector2(-1117.79, -2766.73),
        },
        minZ = 14.59,
        maxZ = 19.36,
        jobs = { "police", "ambulance", "nolovelostairlines" },
        items = { "id_card" },
        removeItem = false,
    },

    ["Airport Arrival"] = {
        entries = {
            vector4(-1073.9655, -2843.0537, 15.0563, 153.1588),
            vector4(-1080.0880, -2854.8184, 15.0563, 328.8939),
        },
        points = {
            
            vector2(-1072.15, -2846.13),
            vector2(-1074.60, -2852.54),
            vector2(-1085.84, -2851.01),
            vector2(-1078.12, -2842.95),
        },
        minZ = 13.59,
        maxZ = 19.36,
        jobs = { "police", "ambulance", "nolovelostairlines" },
        items = { "plane_ticket" },
        removeItem = true,
    },

    ["Airport Arrival v2"] = {
        entries = {
            vector4(-1060.9100, -2832.3789, 15.0563, 230.6331),
            vector4(-1055.8453, -2843.3496, 15.6349, 312.4209),
        },
        points = {
            
            vector2(-1058.11, -2831.82),
            vector2(-1057.26, -2832.46),
            vector2(-1056.32, -2830.87),
            vector2(-1052.97, -2833.61),
            

            vector2(-1056.13, -2839.49),
            vector2(-1059.96, -2837.36),
            vector2(-1059.96, -2835.14),
        },
        minZ = 12.59,
        maxZ = 17.36,
        jobs = { "police", "ambulance", "nolovelostairlines" },
        items = { "plane_ticket" },
        removeItem = true,
    },

    ["Movie theather"] = {
        entries = {
            vector4(-3122.2688, -1500.9663, 26.4655, 278.4714),
        },
        points = {
            vector2(-3118.7168, -1500.9325),
            vector2(-3119.3137, -1491.3834),
            vector2(-3114.0303, -1490.6144),
            vector2(-3112.9202, -1500.3505),
        },
        minZ = 22.3516,
        maxZ = 35.3516,
        jobs = { "police", "ambulance" },
        items = { "movie_ticket" },
        removeItem = true,
    },

    ["Example Zone 5"] = {
        entries = {
            vector4(1033.7634, 131.7348, 81.3946, 357.2422),
            vector4(1018.4953, 138.9920, 80.9967, 348.3166),
        },
        points = {
            vector2(1016.9422, 144.0642),
            vector2(1019.3984, 148.7917),
            vector2(1041.7629, 135.1804),
            vector2(1038.7168, 130.3544),
        },
        minZ = 79.924,
        maxZ = 82.924,
        jobs = { "police", "ambulance" },
        items = { "bowling_pass" },
        removeItem = true,
    },

    ["Magic City Club"] = {
        entries = {
            vector4(1134.8448, -290.3401, 68.3595, 53.5665),
        },
        points = {
            vector2(1130.0133, -287.9676),
            vector2(1126.5641, -292.0268),
            vector2(1125.4476, -291.1671),
            vector2(1128.4735, -286.7885),
        },
        minZ = 65.1926,
        maxZ = 72.64,
        jobs = { "police", "ambulance", "stripclub", "magic" },
        items = { "club_ticket"},
        removeItem = true,
    },

    ["Magic City Club VIP"] = {
        entries = {
            vector4(1134.8448, -290.3401, 68.3595, 53.5665),
        },
        points = {
            vector2(1097.39, -293.36),
            vector2(1096.97, -294.10),
            vector2(1103.74, -298.68),
            vector2(1100.85, -302.71),
            vector2(1083.06, -290.79),
            vector2(1085.77, -286.55),
            vector2(1093.07, -291.47),
            vector2(1093.65, -290.66),
        },
        minZ = 59.77,
        maxZ = 63.77,
        jobs = { "police", "ambulance", "stripclub", "magic" },
        items = { "club_ticket_vip"},
        removeItem = true,
    },

    ["Palace Club"] = {
        entries = {
            vector4(369.5589, 249.3503, 103.1933, 162.6300),
        },
        points = {
            vector2(371.4941, 243.6508),
            vector2(368.3019, 238.2268),
            vector2(364.0707, 239.6715),
            vector2(366.1418, 245.3854),
        },
        minZ = 100.6905,
        maxZ = 105.6905,
        jobs = { "police", "ambulance", "bouncer", "palace" },
        items = { "club_ticket"},
        removeItem = true,
    },

    ["Club VIP"] = {
        entries = {
            vector4(-3234.4585, -1724.3781, 34.8426, 84.0448),
            vector4(-3234.6743, -1734.2338, 34.8539, 88.0023),
        },
        points = {
            vector2(-3236.6870, -1718.1656),
            vector2(-3236.8232, -1724.9358),
            vector2(-3237.5364, -1724.9126),
            vector2(-3238.1892, -1733.3831),

            vector2(-3237.5391, -1733.6216),
            vector2(-3237.1111, -1740.6036),
            vector2(-3243.1416, -1740.1835),
            vector2(-3241.5659, -1717.8202),
        },
        minZ = 30.6,
        maxZ = 37.64,
        jobs = { "police", "ambulance", "bouncer", "magic" },
        items = { "vip_ticket"},
        removeItem = true,
    },
}
