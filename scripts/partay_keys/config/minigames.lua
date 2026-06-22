-- ==========================================
-- [[ MINIGAMES ]]
-- ==========================================
-- Minigame providers: 'ox_lib', 'ps-ui', 'qb-skillbar', 'boii_ui', 'bl_ui', 'rcore', 'custom'

Config.Minigames = {
    -- Uses Config.MinigameProvider from config.lua unless overridden here.
    Provider = Config.MinigameProvider or 'ox_lib',

    Providers = {
        ox_lib = {
            -- Passed directly into ox_lib skillCheck.
            Difficulty = {'easy', 'easy', {areaSize = 60, speedMultiplier = 2}, 'hard'},
            Keys = {'w', 'a', 's', 'd'}
        },
        ps_ui = {
            -- ps-ui circle minigame settings.
            Circles = 2,
            Time = 20
        },
        qb_skillbar = {
            Duration = 7500,
            Position = 20,
            Width = 15
        },
        boii_ui = {
            Style = 'default',
            Difficulty = 3
        },
        bl_ui = {
            Iterations = 3,
            Difficulty = 50
        },
        rcore = {},
        custom = {}
    }
}

-- Optional custom hook, used only when Config.Minigames.Provider = 'custom'.
-- Client: Config.CustomMinigame = function(difficultyOverride, cb) cb(true or false) end

-- Runtime aliases for older wrapper references.
Config.MinigameType = Config.Minigames.Provider
Config.MinigameSettings = Config.Minigames.Providers.ox_lib
Config.MinigameSettings.PS = Config.Minigames.Providers.ps_ui
Config.MinigameSettings.QB = Config.Minigames.Providers.qb_skillbar
Config.MinigameSettings.BOII = Config.Minigames.Providers.boii_ui
Config.MinigameSettings.BL = Config.Minigames.Providers.bl_ui
Config.MinigameSettings.RCore = Config.Minigames.Providers.rcore
