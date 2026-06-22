-- [[ Dual-Channel Audit Logging System ]] --

function SendAuditLog(title, message, logType)
    -- 1. Console Debugging
    if Config.DebugMode then
        print(('^3[ParTay Keys Debug] ^0[%s]: %s'):format(title, message))
    end

    -- 2. Discord Webhook
    if Config.Logging.DiscordWebhook and Config.Logging.DiscordWebhook ~= '' then
        local embed = {
            {
                ["title"] = title,
                ["description"] = message,
                ["color"] = logType == 'exploit' and 16711680 or 65280, -- Red for exploit, Green for standard
                ["footer"] = { ["text"] = "ParTay Studios - Audit Log" }
            }
        }
        PerformHttpRequest(Config.Logging.DiscordWebhook, function(err, text, headers) end, 'POST', json.encode({username = "ParTay Keys", embeds = embed}), { ['Content-Type'] = 'application/json' })
    end

    -- 3. FiveManage Telemetry
    if Config.Logging.FiveManage and Config.Logging.FiveManage.Enabled and Config.Logging.FiveManage.API_Key ~= '' then
        PerformHttpRequest('https://api.fivemanage.com/api/logs', function(err, text, headers) end, 'POST', json.encode({
            level = logType == 'exploit' and 'error' or 'info',
            message = ('[%s] %s'):format(title, message)
        }), {
            ['Content-Type'] = 'application/json',
            ['Authorization'] = 'Bearer ' .. Config.Logging.FiveManage.API_Key
        })
    end
end

exports('SendAuditLog', SendAuditLog)
