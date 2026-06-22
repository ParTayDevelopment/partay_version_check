-- ==========================================
-- [[ AUDIT LOGGING ]]
-- ==========================================

Config.Logging = {
    -- Optional Discord audit webhook. Leave blank to disable.
    DiscordWebhook = '',

    -- Optional FiveManage audit logging. Requires a valid API key when enabled.
    FiveManage = {
        Enabled = false,
        API_Key = ''
    }
}
