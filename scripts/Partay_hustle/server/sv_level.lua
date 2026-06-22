-- Rate limit helpers for callbacks
local _cb_last = { level = {}, leaderboard = {}, unclaimed = {}, claim = {} }
local function _cbTooSoon(map, src, limit)
    local now = GetGameTimer() or 0
    local last = map[src] or 0
    if now - last < limit then return true end
    map[src] = now
    return false
end
local _cache_level = {}
local _cache_unclaimed = {}
local _cache_leaderboard = { rows = nil, at = 0 }

lib.callback.register('Partay_hustle:getLevel', function(source)
    local limit = (Config.RateLimits and Config.RateLimits.getLevelMs) or 500
    if _cbTooSoon(_cb_last.level, source, limit) then
        return _cache_level[source]
    end
    local ret, done = nil, false
    getplayerlevel(source, function(levelData)
        ret = levelData; done = true
    end)
    while not done do Wait(0) end
    _cache_level[source] = ret
    return ret
end)

-- Auto-migrate DB schema if enabled
CreateThread(function()
    if not (Config.Database and Config.Database.autoMigrate) then return end
    -- Create table if missing (matches sql.sql)
    local createSQL = [[
        CREATE TABLE IF NOT EXISTS `drug_selling_skills` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `user` VARCHAR(64) NOT NULL,
            `name` VARCHAR(64) NOT NULL,
            `levelpoints` INT NOT NULL DEFAULT 0,
            `rewarded_level` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    ]]
    MySQL.query(createSQL)

    -- Ensure unique key on `user`
    local checkIdx = [[
        SELECT COUNT(1) AS cnt
        FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'drug_selling_skills'
          AND INDEX_NAME = 'uk_user'
    ]]
    MySQL.query(checkIdx, {}, function(res)
        local cnt = (res and res[1] and tonumber(res[1].cnt)) or 0
        if cnt == 0 then
            MySQL.query('ALTER TABLE `drug_selling_skills` ADD UNIQUE KEY `uk_user` (`user`)')
        end
    end)
end)

-- Ensure DB has rewarded_level column for one-time level rewards
CreateThread(function()
    MySQL.query('SHOW COLUMNS FROM drug_selling_skills LIKE "rewarded_level"', {}, function(result)
        if not result or not result[1] then
            MySQL.query('ALTER TABLE drug_selling_skills ADD rewarded_level INT NOT NULL DEFAULT 0')
        end
    end)
end)

local function pointsToLevel(points)
    local lvl = 0
    points = tonumber(points) or 0
    for level, data in ipairs(Config.levels) do
        if points >= tonumber(data.points) then
            lvl = level
        else
            break
        end
    end
    return lvl
end

local function invalidateLeaderboardCache()
    _cache_leaderboard.rows = nil
    _cache_leaderboard.at = 0
end

local function getPlayerCharacerName(source)
    -- Always return two non-nil strings
    local function splitName(full)
        if type(full) ~= 'string' then return '', '' end
        local first, last = full:match('^(%S+)%s+(.*)$')
        if not first then return full, '' end
        return first, last
    end

    if Config.Framework == 'esx' then
        local xPlayer = GetPlayer(source)
        if xPlayer and xPlayer.get then
            local firstname = xPlayer.get('firstName') or xPlayer.get('firstname')
            local lastname = xPlayer.get('lastName') or xPlayer.get('lastname')
            if (firstname and firstname ~= '') or (lastname and lastname ~= '') then
                return tostring(firstname or ''), tostring(lastname or '')
            end
            if xPlayer.getName then
                local fn, ln = splitName(xPlayer.getName())
                return tostring(fn or ''), tostring(ln or '')
            end
        end
        local name = GetPlayerName(source) or ('Citizen '..tostring(source))
        local fn, ln = splitName(name)
        return tostring(fn or ''), tostring(ln or '')

    elseif Config.Framework == 'qb' or Config.Framework == 'qbx' then
        local Player = GetPlayer(source)
        local ci = Player and Player.PlayerData and Player.PlayerData.charinfo or nil
        local fn = ci and (ci.firstname or ci.firstName)
        local ln = ci and (ci.lastname or ci.lastName)
        if (fn and fn ~= '') or (ln and ln ~= '') then
            return tostring(fn or ''), tostring(ln or '')
        end
        local name = GetPlayerName(source) or ('Citizen '..tostring(source))
        local sfn, sln = splitName(name)
        return tostring(sfn or ''), tostring(sln or '')

    else
        -- Safe fallback: use player name
        local name = GetPlayerName(source) or ('Citizen '..tostring(source))
        local fn, ln = splitName(name)
        return tostring(fn or ''), tostring(ln or '')
    end
end

local function getUUID(source)
    if Config.Framework == 'esx' then
        local xPlayer = GetPlayer(source)
        return xPlayer.identifier
    elseif Config.Framework == 'qb' or Config.Framework == 'qbx' then
        local Player = GetPlayer(source)
        return Player.PlayerData.citizenid
    else
        -- Fallback: pick a stable identifier from player identifiers
        local ids = GetPlayerIdentifiers(source)
        local preferred = { 'license2:', 'license:', 'fivem:', 'discord:', 'steam:' }
        for _, pref in ipairs(preferred) do
            for _, id in ipairs(ids) do
                if id:sub(1, #pref) == pref then return id end
            end
        end
        return 'src:'..tostring(source)
    end
end

function getplayerlevel(source, callback)
    local first_rp_name, last_rp_name = getPlayerCharacerName(source)
    local rp_name = ((first_rp_name or '') .. ' ' .. (last_rp_name or '')):gsub('^%s+',''):gsub('%s+$','')
    local uuid = tostring(getUUID(source))

    MySQL.query('SELECT * FROM drug_selling_skills WHERE user = ?', { uuid }, function(result)
        local row = result and result[1]
        if row then
            callback(row)
            return
        end

        MySQL.insert('INSERT INTO drug_selling_skills (user, name, levelpoints, rewarded_level) VALUES (?, ?, ?, 0)', { uuid, rp_name, 0 }, function()
            MySQL.query('SELECT * FROM drug_selling_skills WHERE user = ?', { uuid }, function(result2)
                local row2 = result2 and result2[1]
                if row2 then
                    callback(row2)
                else
                    callback(nil)
                end
            end)
        end)
    end)
end

function addlevelpoints(source, addAmount)
    local first_rp_name, last_rp_name = getPlayerCharacerName(source)
    local rp_name = ((first_rp_name or '') .. ' ' .. (last_rp_name or '')):gsub('^%s+',''):gsub('%s+$','')
    local uuid = tostring(getUUID(source))
    local amt = tonumber(addAmount) or 0
    if amt == 0 then return end

    MySQL.query('SELECT levelpoints FROM drug_selling_skills WHERE user = ?', { uuid }, function(result)
        local row = result and result[1]
        local prevPoints = row and tonumber(row.levelpoints) or 0
        local prevLevel = pointsToLevel(prevPoints)
        local newPoints = prevPoints + amt

        local function afterWrite()
            invalidateLeaderboardCache()
            local newLevel = pointsToLevel(newPoints)
            if newLevel > prevLevel then
                TriggerClientEvent('Partay_hustle:client:notify', source, 'success', 'You have moved to the next level, check leaderboard to claim rewards')
            end
        end

        -- Update-first path is resilient even if unique constraints are missing.
        MySQL.update('UPDATE drug_selling_skills SET levelpoints = levelpoints + ?, name = ? WHERE user = ?', { amt, rp_name, uuid }, function(affected)
            if (tonumber(affected) or 0) > 0 then
                afterWrite()
                return
            end
            -- Fallback create row, then continue.
            MySQL.insert('INSERT INTO drug_selling_skills (user, name, levelpoints, rewarded_level) VALUES (?, ?, ?, 0)', { uuid, rp_name, amt }, function()
                afterWrite()
            end)
        end)
    end)
end
function calculateDrugPriceIncrease(playerLevelPoints)
    local percentIncrease = 0

    playerLevelPoints = tonumber(playerLevelPoints)

    for level, data in pairs(Config.levels) do
        if playerLevelPoints >= data.points then
            percentIncrease = data.percentmore
        else
            break
        end
    end
    return percentIncrease
end

local leaderBoard = {}

lib.callback.register('Partay_hustle:getLeaderboard', function(source)
    local limit = (Config.RateLimits and Config.RateLimits.getLeaderboardMs) or 2000
    local cacheMs = (Config.Server and tonumber(Config.Server.leaderboardCacheMs)) or 5000
    local now = GetGameTimer() or 0
    if _cache_leaderboard.rows and (now - (_cache_leaderboard.at or 0) < cacheMs) then
        return _cache_leaderboard.rows
    end
    if _cbTooSoon(_cb_last.leaderboard, source, limit) then
        if _cache_leaderboard.rows then return _cache_leaderboard.rows end
        if type(leaderBoard) == 'table' and #leaderBoard > 0 then return leaderBoard end
        return {}
    end
    leaderBoard = getleaderboard(5)
    _cache_leaderboard.rows = leaderBoard
    _cache_leaderboard.at = now
    return leaderBoard or {}
end)

function getleaderboard(maxRows)
    local rows = {}
    local done = false
    local n = tonumber(maxRows) or 5
    if n < 1 then n = 1 end
    if n > 250 then n = 250 end

    -- Pull a wider slice, then rank by computed level (desc) and XP (desc)
    local sql = 'SELECT `name`, `levelpoints` FROM `drug_selling_skills` WHERE `levelpoints` > 0 ORDER BY `levelpoints` DESC LIMIT 500'
    MySQL.query(sql, function(result)
        if result then
            for _, row in ipairs(result) do
                table.insert(rows, {
                    name = row.name,
                    score = tonumber(row.levelpoints) or 0,
                    level = pointsToLevel(tonumber(row.levelpoints) or 0)
                })
            end
            table.sort(rows, function(a, b)
                local al = tonumber(a.level) or 0
                local bl = tonumber(b.level) or 0
                if al ~= bl then return al > bl end
                return (tonumber(a.score) or 0) > (tonumber(b.score) or 0)
            end)
            while #rows > n do
                table.remove(rows)
            end
        end
        done = true
    end)

    while not done do Wait(0) end
    return rows
end

-- Claim system: compute unclaimed levels and grant on request
local function claimRewardsFor(source)
    local claimed = 0
    local done = false
    MySQL.query('SELECT levelpoints, rewarded_level FROM drug_selling_skills WHERE user = ?', { tostring(getUUID(source)) }, function(result)
        local row = result and result[1]
        local points = row and tonumber(row.levelpoints) or 0
        local prev = row and tonumber(row.rewarded_level) or 0
        local curr = pointsToLevel(points)
        local last = prev
        if curr > prev then
            for lvl = (prev + 1), curr do
                local cfg = Config.levels[lvl]
                if cfg and cfg.reward then
                    local ok = GrantReward(source, cfg.reward)
                    if ok then
                        claimed = claimed + 1
                        last = lvl
                    else
                        -- stop advancing if a reward fails to grant to avoid losing it
                        break
                    end
                else
                    -- no reward configured for this level; mark as claimed
                    last = lvl
                end
            end
            if last ~= prev then
                MySQL.update('UPDATE drug_selling_skills SET rewarded_level = ? WHERE user = ?', { last, tostring(getUUID(source)) })
            end
        end
        done = true
    end)
    while not done do Wait(0) end
    return claimed
end

lib.callback.register('Partay_hustle:getUnclaimedLevels', function(source)
    local limit = (Config.RateLimits and Config.RateLimits.getUnclaimedMs) or 1000
    if _cbTooSoon(_cb_last.unclaimed, source, limit) then
        return _cache_unclaimed[source]
    end
    local ret = { unclaimed = 0, current = 0, rewarded = 0 }
    local done = false
    MySQL.query('SELECT levelpoints, rewarded_level FROM drug_selling_skills WHERE user = ?', { tostring(getUUID(source)) }, function(result)
        local row = result and result[1]
        local points = row and tonumber(row.levelpoints) or 0
        local prev = row and tonumber(row.rewarded_level) or 0
        local curr = pointsToLevel(points)
        ret.current = curr
        ret.rewarded = prev
        ret.unclaimed = math.max(curr - prev, 0)
        done = true
    end)
    while not done do Wait(0) end
    _cache_unclaimed[source] = ret
    return ret
end)

lib.callback.register('Partay_hustle:claimRewards', function(source)
    local limit = (Config.RateLimits and Config.RateLimits.claimRewardsMs) or 2000
    if _cbTooSoon(_cb_last.claim, source, limit) then
        return 0
    end
    local count = claimRewardsFor(source)
    return count
end)

-- QoL/Admin Commands
--   /trapaddpoints <id> <amount>
--   /trapsetpoints <id> <points> [award]
--   /trapresetpoints <id>
--   /trapgiveitem <id> <item> <amount>
--   /trapgivemoney <id> <account> <amount>
--   /traphotspots [on|off|toggle] [id|all]
--   /trapdebug

local function adminAllowed(src)
    if src == 0 then return true end -- console
    if IsPlayerAceAllowed(src, 'partay_hustle.admin') then return true end
    return false
end

local function parseInt(v)
    local n = tonumber(v)
    if not n then return nil end
    return math.floor(n)
end

local _acmd = (Config.Commands and Config.Commands.admin) or {}
local _cmd_addpoints   = _acmd.addpoints or 'trapaddpoints'
local _cmd_setpoints   = _acmd.setpoints or 'trapsetpoints'
local _cmd_resetpoints = _acmd.resetpoints or 'trapresetpoints'
local _cmd_giveitem    = _acmd.giveitem or 'trapgiveitem'
local _cmd_givemoney   = _acmd.givemoney or 'trapgivemoney'
local _cmd_hotspots    = _acmd.hotspots or 'traphotspots'
local _cmd_debug       = _acmd.debug or 'trapdebug'

-- /trapaddpoints <id> <amount>
RegisterCommand(_cmd_addpoints, function(source, args)
    if not adminAllowed(source) then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'No permission.')
        return
    end
    local target = tonumber(args[1] or '')
    local amount = parseInt(args[2])
    if not target or not amount then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', ('Usage: /%s <id> <amount>'):format(_cmd_addpoints))
        return
    end
    addlevelpoints(target, amount)
    TriggerClientEvent('Partay_hustle:client:notify', source, 'success', ('Added %d points to %d'):format(amount, target))
end)

-- /trapsetpoints <id> <points> [award]
RegisterCommand(_cmd_setpoints, function(source, args)
    if not adminAllowed(source) then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'No permission.')
        return
    end
    local target = tonumber(args[1] or '')
    local points = parseInt(args[2])
    local award = tostring(args[3] or '')
    local doAward = (award == '1' or award == 'true' or award == 'yes')
    if not target or points == nil then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', ('Usage: /%s <id> <points> [award]'):format(_cmd_setpoints))
        return
    end
    getplayerlevel(target, function(levelData)
        local prevRewarded = (levelData and tonumber(levelData.rewarded_level)) or 0
        local function lvlFromPoints(p)
            local lvl = 0
            p = tonumber(p) or 0
            for i, data in ipairs(Config.levels) do
                if p >= tonumber(data.points) then lvl = i else break end
            end
            return lvl
        end
        local newLevel = lvlFromPoints(points)
        if doAward and newLevel > prevRewarded then
            for lvl = (prevRewarded + 1), newLevel do
                local cfg = Config.levels[lvl]
                if cfg and cfg.reward then
                    GrantReward(target, cfg.reward)
                end
            end
            MySQL.update('UPDATE drug_selling_skills SET levelpoints = ?, rewarded_level = ? WHERE user = ?', { points, newLevel, tostring(getUUID(target)) })
            invalidateLeaderboardCache()
        else
            MySQL.update('UPDATE drug_selling_skills SET levelpoints = ? WHERE user = ?', { points, tostring(getUUID(target)) })
            invalidateLeaderboardCache()
        end
        TriggerClientEvent('Partay_hustle:client:notify', source, 'success', ('Set points for %d to %d'):format(target, points))
    end)
end)

-- /trapresetpoints <id>
RegisterCommand(_cmd_resetpoints, function(source, args)
    if not adminAllowed(source) then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'No permission.')
        return
    end
    local target = tonumber(args[1] or '')
    if not target then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', ('Usage: /%s <id>'):format(_cmd_resetpoints))
        return
    end
    MySQL.update('UPDATE drug_selling_skills SET levelpoints = ?, rewarded_level = ? WHERE user = ?', { 0, 0, tostring(getUUID(target)) })
    invalidateLeaderboardCache()
    TriggerClientEvent('Partay_hustle:client:notify', source, 'success', ('Reset points for %d'):format(target))
end)

-- /trapgiveitem <id> <item> <amount>
RegisterCommand(_cmd_giveitem, function(source, args)
    if not adminAllowed(source) then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'No permission.')
        return
    end
    local target = tonumber(args[1] or '')
    local item = args[2]
    local amount = parseInt(args[3]) or 1
    if not target or not item then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', ('Usage: /%s <id> <item> [amount]'):format(_cmd_giveitem))
        return
    end
    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:AddItem(target, item, amount)
    else
        GiveItem(target, item, amount, 'admin-grant')
    end
    TriggerClientEvent('Partay_hustle:client:notify', source, 'success', ('Gave %dx %s to %d'):format(amount, item, target))
end)

-- /trapgivemoney <id> <account> <amount>
RegisterCommand(_cmd_givemoney, function(source, args)
    if not adminAllowed(source) then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'No permission.')
        return
    end
    local target = tonumber(args[1] or '')
    local account = tostring(args[2] or 'cash')
    local amount = parseInt(args[3] or '0') or 0
    if not target or amount <= 0 then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', ('Usage: /%s <id> <cash|bank|black_money> <amount>'):format(_cmd_givemoney))
        return
    end
    if Config.Framework == 'esx' then
        local xPlayer = GetPlayer(target)
        if xPlayer then
            if account == 'bank' then
                xPlayer.addAccountMoney('bank', amount)
            elseif account == 'black_money' then
                xPlayer.addAccountMoney('black_money', amount)
            else
                xPlayer.addMoney(amount)
            end
        end
    else
        local Player = GetPlayer(target)
        if Player and Player.Functions and Player.Functions.AddMoney then
            Player.Functions.AddMoney(account, amount, 'admin-grant')
        end
    end
    TriggerClientEvent('Partay_hustle:client:notify', source, 'success', ('Gave %d %s to %d'):format(amount, account, target))
end)

-- /traphotspots [on|off|toggle] [id|all]
RegisterCommand(_cmd_hotspots, function(source, args)
    if not adminAllowed(source) then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'No permission.')
        return
    end
    local mode = tostring(args[1] or 'toggle')
    local targetArg = tostring(args[2] or '')
    local on
    if mode == 'on' then on = true elseif mode == 'off' then on = false else on = nil end
    local function send(to)
        TriggerClientEvent('Partay_hustle:client:toggleHotspots', to, on)
    end
    if targetArg == 'all' then
        send(-1)
        return
    end
    local target = tonumber(targetArg)
    if target then
        send(target)
    else
        send(source)
    end
end)

-- /trapdebug (toggle server debug)
RegisterCommand(_cmd_debug, function(source)
    if not adminAllowed(source) then
        TriggerClientEvent('Partay_hustle:client:notify', source, 'error', 'No permission.')
        return
    end
    Config.Debug = not Config.Debug
    TriggerClientEvent('Partay_hustle:client:notify', source, 'success', ('Debug is now %s'):format(tostring(Config.Debug)))
end)
