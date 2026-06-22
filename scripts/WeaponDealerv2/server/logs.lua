Server = Server or {}
Server.Logs = {}

function Server.Logs.Write(action, message, data)
    data = data or {}

    if Config.Logging.Console then
        print(('[%s] %s: %s %s'):format(WD.Resource, action, message, json.encode(data)))
    end

    MySQL.insert('INSERT INTO weapon_sales_logs (action, message, data) VALUES (?, ?, ?)', {
        action,
        message,
        json.encode(data)
    })

    if Config.Logging.Discord.Enabled and Config.Logging.Discord.Webhook ~= '' then
        PerformHttpRequest(Config.Logging.Discord.Webhook, function() end, 'POST', json.encode({
            username = 'Weapon Dealer',
            embeds = {
                {
                    title = action,
                    description = message,
                    color = 3447003,
                    fields = {
                        { name = 'Data', value = ('```json\n%s\n```'):format(json.encode(data)), inline = false }
                    }
                }
            }
        }), { ['Content-Type'] = 'application/json' })
    end
end

function Server.Logs.Blocked(source, action, reason, data)
    data = data or {}
    data.source = source
    data.reason = reason

    Server.Logs.Write('blocked_' .. action, reason, data)
end
