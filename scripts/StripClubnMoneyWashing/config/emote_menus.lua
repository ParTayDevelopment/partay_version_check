-- Emote menu support configuration
Config.EmoteMenus = {
    priority = { 'rpemotes', 'rpemotes-reborn', 'dpemotes', 'custom' },
    handlers = {
        ['rpemotes'] = {
            call = function(anim)
                if GetResourceState('rpemotes') ~= 'started' then return false end
                local success = pcall(function()
                    exports.rpemotes:EmoteCommandStart(anim)
                end)
                return success
            end
        },
        ['rpemotes-reborn'] = {
            call = function(anim)
                if GetResourceState('rpemotes-reborn') ~= 'started' then return false end
                local success = pcall(function()
                    exports['rpemotes-reborn']:EmoteCommandStart(anim)
                end)
                return success
            end
        },
        ['dpemotes'] = {
            call = function(anim)
                if GetResourceState('dpemotes') ~= 'started' then return false end
                TriggerEvent('animations:client:EmoteCommandStart', { anim })
                return true
            end
        },
        ['custom'] = {
            enabled = false,
            call = function(anim)
                -- Example: TriggerEvent('my_custom_emotes:play', anim)
                return false
            end
        }
    }
}
