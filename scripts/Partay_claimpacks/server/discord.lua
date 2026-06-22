local Discord = _G.PartayDiscord or {}
_G.PartayDiscord = Discord

local ConfigDiscord = Config.Discord or {}
local useBadger = ConfigDiscord.UseBadger ~= false
local cacheTtl = math.max(1, (ConfigDiscord.CacheSeconds or 60)) * 1000
local cache = {}

local function resourceActive(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local function getDiscordId(source)
    if GetPlayerIdentifierByType then
        local discord = GetPlayerIdentifierByType(source, 'discord')
        if discord and discord ~= '' then
            return discord:gsub('discord:', '')
        end
    end

    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:find('discord:', 1, true) then
            return identifier:gsub('discord:', '')
        end
    end
    return nil
end

local function cacheKey(discordId, roleId)
    return ('%s:%s'):format(discordId, roleId)
end

local function readCache(discordId, roleId)
    local key = cacheKey(discordId, roleId)
    local entry = cache[key]
    if not entry then return end
    if entry.expires > GetGameTimer() then
        return entry.value
    end
    cache[key] = nil
end

local function writeCache(discordId, roleId, value)
    local key = cacheKey(discordId, roleId)
    cache[key] = {
        value = value,
        expires = GetGameTimer() + cacheTtl
    }
end

local function checkBadger(source, roleId)
    if not useBadger then return nil end
    if not resourceActive('Badger_Discord_API') then return nil end

    local ok, result = pcall(function()
        return exports['Badger_Discord_API']:CheckDiscordRole(source, roleId)
    end)

    if not ok then
        if Config.Debug then
            print(('[Partay_claimpacks] Badger_Discord_API check failed: %s'):format(result))
        end
        return nil
    end

    return result == true
end

local function checkHttp(discordId, roleId)
    local tokenConvar = ConfigDiscord.BotTokenConvar or ''
    local guildConvar = ConfigDiscord.GuildIdConvar or ''
    local botToken = tokenConvar ~= '' and GetConvar(tokenConvar, '') or ''
    local guildId = guildConvar ~= '' and GetConvar(guildConvar, '') or ''

    if botToken == '' or guildId == '' then
        if Config.Debug then
            print('[Partay_claimpacks] Discord fallback skipped (missing bot token or guild id).')
        end
        return false
    end

    local cached = readCache(discordId, roleId)
    if cached ~= nil then
        return cached
    end

    local url = ('https://discord.com/api/v10/guilds/%s/members/%s'):format(guildId, discordId)
    local finished = false
    local hasRole = false

    PerformHttpRequest(url, function(status, body)
        if status == 200 and body then
            local data = json.decode(body)
            local roles = data and data.roles or {}
            if roles then
                for _, value in ipairs(roles) do
                    if value == roleId then
                        hasRole = true
                        break
                    end
                end
            end
        else
            if Config.Debug then
                print(('[Partay_claimpacks] Discord HTTP check failed. status=%s body=%s'):format(status, body or ''))
            end
        end
        finished = true
    end, 'GET', '', {
        ['Authorization'] = ('Bot %s'):format(botToken),
        ['Content-Type'] = 'application/json'
    })

    local timeout = GetGameTimer() + 8000
    while not finished and GetGameTimer() < timeout do
        Citizen.Wait(100)
    end

    if not finished then
        if Config.Debug then
            print('[Partay_claimpacks] Discord HTTP check timed out.')
        end
        hasRole = false
    end

    writeCache(discordId, roleId, hasRole)
    return hasRole
end

function Discord.HasDiscordRole(source, roleId)
    if not roleId then return true end

    local discordId = getDiscordId(source)
    if not discordId then
        if Config.Debug then
            print(('[Partay_claimpacks] Player %s has no discord identifier; denying role %s'):format(source, roleId))
        end
        return false
    end

    local cached = readCache(discordId, roleId)
    if cached ~= nil then
        return cached
    end

    local badgerResult = checkBadger(source, roleId)
    if badgerResult ~= nil then
        writeCache(discordId, roleId, badgerResult)
        return badgerResult
    end

    return checkHttp(discordId, roleId)
end

function Discord.HasAnyRole(source, roles)
    if not roles then return true end
    if type(roles) ~= 'table' then
        roles = { roles }
    end

    for key, value in pairs(roles) do
        local roleId = type(key) == 'number' and value or key
        if type(roleId) == 'string' and Discord.HasDiscordRole(source, roleId) then
            return true
        end
    end

    return false
end

Discord.GetDiscordId = getDiscordId

return Discord

