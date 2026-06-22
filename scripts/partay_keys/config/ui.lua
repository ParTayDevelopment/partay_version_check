-- ==========================================
-- [[ UI & NOTIFICATIONS ]]
-- ==========================================
-- Notification providers: 'ox_lib', 'qb-core', 'qbx_core', 'esx', 'okokNotify', 'mythic', 'wasabi', 'custom'
-- ox_lib is still required for menus, callbacks, input dialogs, and NUI support.

Config.Notifications = {
    -- Uses Config.NotificationProvider from config.lua unless overridden here.
    Provider = Config.NotificationProvider or 'ox_lib',

    -- Default notification duration in milliseconds.
    Duration = 3500,

    -- Position is provider-dependent; ox_lib supports values like 'top-right', 'top', and 'bottom'.
    Position = 'top',

    Providers = {
        ox_lib = {},
        qb_core = {},
        qbx_core = {},
        esx = {},
        okokNotify = {},
        mythic = {},
        wasabi = {},
        custom = {}
    }
}

-- Optional custom hooks, used only when Config.Notifications.Provider = 'custom'.
-- Client: Config.CustomNotify = function(title, description, type) end
-- Server: Config.CustomNotifyServer = function(target, title, description, type) end

-- Runtime alias for older wrapper references.
Config.NotificationType = Config.Notifications.Provider
