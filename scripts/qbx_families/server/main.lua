local function notify(source, description, notifyType)
    TriggerClientEvent('qbx_families:client:notify', source, description, notifyType or 'inform')
end

local function getPlayer(source)
    return exports.qbx_core:GetPlayer(source)
end

local function getCitizenId(source)
    local player = getPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function getDiscordId(source)
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        local discordId = identifier:match('^discord:(%d+)$')
        if discordId then return discordId end
    end
end

local function getPlayerNameFromData(playerData, fallback)
    if not playerData then return fallback or 'Unknown' end

    local charinfo = playerData.charinfo or {}
    local first = charinfo.firstname or ''
    local last = charinfo.lastname or ''
    local name = (('%s %s'):format(first, last)):gsub('^%s+', ''):gsub('%s+$', '')

    return name ~= '' and name or playerData.name or fallback or 'Unknown'
end

local function getOnlineSourceByCitizenId(citizenid)
    for _, id in ipairs(GetPlayers()) do
        local source = tonumber(id)
        if getCitizenId(source) == citizenid then
            return source
        end
    end
end

local function getFamilyDefinition(family)
    return family and Config.Families[family] or nil
end

local function getRoleDefinition(family, role)
    local familyData = getFamilyDefinition(family)
    return familyData and familyData.roles and familyData.roles[role] or nil
end

local function getRoleOptions(family)
    local familyData = getFamilyDefinition(family)
    local options = {}

    if not familyData or not familyData.roles then return options end

    for role, data in pairs(familyData.roles) do
        if role ~= 'none' then
            options[#options + 1] = {
                value = role,
                label = data.label or role
            }
        end
    end

    table.sort(options, function(a, b)
        return a.label < b.label
    end)

    return options
end

local function getRewardDefinition(rewardId)
    for _, reward in ipairs(Config.Progression.rewards or {}) do
        if reward.id == rewardId then return reward end
    end
end

local function getLevel(totalPoints)
    local level = 1
    local currentLevelPoints = 0
    local nextLevel

    for targetLevel, requiredPoints in pairs(Config.Progression.levels or {}) do
        if totalPoints >= requiredPoints and targetLevel >= level then
            level = targetLevel
            currentLevelPoints = requiredPoints
        elseif requiredPoints > totalPoints and (not nextLevel or requiredPoints < nextLevel.points) then
            nextLevel = {
                level = targetLevel,
                points = requiredPoints
            }
        end
    end

    return level, nextLevel, currentLevelPoints
end

local activeEvents = {}

local function getEventPreset(presetId)
    presetId = tostring(presetId or Config.Events.defaultPreset or 'small')
    local presets = Config.Events.presets or {}
    return presetId, presets[presetId] or presets[Config.Events.defaultPreset or 'small'] or {
        label = 'Family Event',
        radius = Config.Events.defaultRadius or 35.0,
        pointsPerTick = Config.Events.defaultPointsPerTick or 10,
    }
end

local function getEventPresetForArea(area)
    area = tonumber(area) or 0.0

    local tiers = {}
    for presetId, preset in pairs(Config.Events.presets or {}) do
        tiers[#tiers + 1] = {
            id = presetId,
            preset = preset,
            maxArea = tonumber(preset.maxArea)
        }
    end

    table.sort(tiers, function(a, b)
        if a.maxArea and b.maxArea then return a.maxArea < b.maxArea end
        if a.maxArea then return true end
        if b.maxArea then return false end
        return a.id < b.id
    end)

    for _, tier in ipairs(tiers) do
        if not tier.maxArea or area <= tier.maxArea then
            return tier.id, tier.preset
        end
    end

    return getEventPreset(Config.Events.defaultPreset)
end

local function getEventPresetOptions()
    local options = {}
    for presetId, preset in pairs(Config.Events.presets or {}) do
        options[#options + 1] = {
            id = presetId,
            label = preset.label or presetId,
            description = preset.description or '',
            maxArea = preset.maxArea,
            radius = preset.radius or Config.Events.defaultRadius or 35.0,
            pointsPerTick = preset.pointsPerTick or Config.Events.defaultPointsPerTick or 10,
        }
    end

    table.sort(options, function(a, b)
        if a.maxArea and b.maxArea then return a.maxArea < b.maxArea end
        if a.maxArea then return true end
        if b.maxArea then return false end
        return a.label < b.label
    end)

    return options
end

local function getFamilyRedeemedRewards(family)
    local unlocked = {}
    if not family or family == 'none' then return unlocked end

    local rows = MySQL.query.await('SELECT reward_id FROM family_reward_redemptions WHERE family = ?', { family }) or {}
    for _, row in ipairs(rows) do
        unlocked[row.reward_id] = true
    end

    return unlocked
end

local function getAllowedEventProps(family)
    local redeemed = getFamilyRedeemedRewards(family)
    local props = {}
    for _, prop in ipairs(Config.Events.allowedProps or {}) do
        if prop.id and prop.model and (not prop.unlock or redeemed[prop.unlock]) then
            props[#props + 1] = {
                id = tostring(prop.id),
                label = prop.label or prop.id,
                model = tostring(prop.model),
                unlock = prop.unlock
            }
        end
    end

    table.sort(props, function(a, b)
        return a.label < b.label
    end)

    return props
end

local function getAllowedEventProp(propId, family, allowLocked)
    propId = tostring(propId or '')
    local redeemed = allowLocked and {} or getFamilyRedeemedRewards(family)
    for _, prop in ipairs(Config.Events.allowedProps or {}) do
        if tostring(prop.id or '') == propId and (allowLocked or not prop.unlock or redeemed[prop.unlock]) then
            return {
                id = tostring(prop.id),
                label = prop.label or prop.id,
                model = tostring(prop.model),
                unlock = prop.unlock
            }
        end
    end
end

local function getFamilyOptions(excludeFamily)
    local options = {}
    for family, data in pairs(Config.Families or {}) do
        if family ~= 'none' and family ~= excludeFamily then
            options[#options + 1] = {
                id = family,
                label = data.label or family
            }
        end
    end

    table.sort(options, function(a, b)
        return a.label < b.label
    end)

    return options
end

local function getCoordsPayload(coords)
    return {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }
end

local function normalizePoint(point)
    if type(point) ~= 'table' then return nil end

    local x = tonumber(point.x)
    local y = tonumber(point.y)
    local z = tonumber(point.z)
    if not x or not y or not z then return nil end

    return { x = x, y = y, z = z }
end

local isPointInsidePolygon

local function normalizePoints(points)
    if type(points) ~= 'table' then return {} end

    local clean = {}
    for _, point in ipairs(points) do
        local normalized = normalizePoint(point)
        if normalized then clean[#clean + 1] = normalized end
    end

    return clean
end

local function normalizeEventProps(props, zonePoints, family, allowLocked)
    if type(props) ~= 'table' then return {} end

    local clean = {}
    local polygon = normalizePoints(zonePoints)
    local maxProps = math.max(0, math.floor(tonumber(Config.Events.maxPropsPerEvent) or 0))
    for _, prop in ipairs(props) do
        if #clean >= maxProps then break end
        if type(prop) == 'table' then
            local definition = getAllowedEventProp(prop.id, family, allowLocked)
            local coords = normalizePoint(prop.coords)
            local rotation = normalizePoint(prop.rotation) or { x = 0.0, y = 0.0, z = tonumber(prop.heading) or 0.0 }
            local heading = tonumber(prop.heading) or 0.0

            local insideZone = #polygon < (Config.Events.minZonePoints or 4) or (coords and isPointInsidePolygon({ x = coords.x, y = coords.y }, polygon))
            if definition and coords and insideZone then
                clean[#clean + 1] = {
                    id = definition.id,
                    label = definition.label,
                    model = definition.model,
                    coords = coords,
                    rotation = rotation,
                    heading = heading % 360.0
                }
            end
        end
    end

    return clean
end

local function getZoneCenter(points)
    local clean = normalizePoints(points)
    if #clean == 0 then return nil end

    local x, y, z = 0.0, 0.0, 0.0
    for _, point in ipairs(clean) do
        x = x + point.x
        y = y + point.y
        z = z + point.z
    end

    return {
        x = x / #clean,
        y = y / #clean,
        z = z / #clean
    }
end

local function getPolygonArea(points)
    local clean = normalizePoints(points)
    if #clean < 3 then return 0.0 end

    local area = 0.0
    local j = #clean
    for i = 1, #clean do
        local current = clean[i]
        local previous = clean[j]
        area = area + ((previous.x + current.x) * (previous.y - current.y))
        j = i
    end

    return math.abs(area / 2.0)
end

isPointInsidePolygon = function(point, polygon)
    local inside = false
    local j = #polygon

    for i = 1, #polygon do
        local pi = polygon[i]
        local pj = polygon[j]

        if ((pi.y > point.y) ~= (pj.y > point.y)) and (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) + 0.000001) + pi.x) then
            inside = not inside
        end

        j = i
    end

    return inside
end

local function getFamilyRecord(citizenid)
    if not citizenid then return nil end

    return MySQL.single.await('SELECT citizenid, family, role, invited_by, created_at, updated_at FROM family_members WHERE citizenid = ?', { citizenid })
end

local function getDefaultFamilyRecord(citizenid)
    return {
        citizenid = citizenid,
        family = 'none',
        role = 'none'
    }
end

local function getEffectiveFamily(citizenid)
    return getFamilyRecord(citizenid) or getDefaultFamilyRecord(citizenid)
end

local function normalizeImageUrl(value)
    local url = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if url == '' then return nil end
    if #url > 900 then return nil, 'Image URL is too long.' end
    if not url:match('^https?://') then return nil, 'Image URL must start with http:// or https://.' end

    return url
end

local function normalizeThemeColor(value)
    local color = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if color == '' then return nil end
    if color:match('^#%x%x%x%x%x%x$') then return color end
    if color:match('^#%x%x%x$') then
        local r, g, b = color:sub(2, 2), color:sub(3, 3), color:sub(4, 4)
        return ('#%s%s%s%s%s%s'):format(r, r, g, g, b, b)
    end

    return nil, 'Theme color must be a hex color like #5ea2ff.'
end

local function getFamilySettings(family)
    if not family or family == 'none' then
        return {
            imageUrl = nil,
            themeColor = nil,
        }
    end

    local row = MySQL.single.await('SELECT image_url, theme_color FROM family_settings WHERE family = ? LIMIT 1', { family })

    return {
        imageUrl = row and row.image_url or nil,
        themeColor = row and row.theme_color or nil,
    }
end

local function ensureDatabase()
    local function trySchemaQuery(query)
        pcall(function()
            MySQL.query.await(query)
        end)
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_members` (
            `citizenid` varchar(50) NOT NULL,
            `family` varchar(50) NOT NULL,
            `role` varchar(50) NOT NULL,
            `invited_by` varchar(50) DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`citizenid`),
            KEY `idx_family_members_family` (`family`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_audit_logs` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `action` varchar(50) NOT NULL,
            `actor_citizenid` varchar(50) DEFAULT NULL,
            `target_citizenid` varchar(50) DEFAULT NULL,
            `family` varchar(50) DEFAULT NULL,
            `payload` longtext DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_family_audit_logs_family` (`family`),
            KEY `idx_family_audit_logs_created_at` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_heads` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `family` varchar(50) NOT NULL,
            `citizenid` varchar(50) DEFAULT NULL,
            `discord` varchar(32) DEFAULT NULL,
            `assigned_by` varchar(50) DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_family_heads_family` (`family`),
            KEY `idx_family_heads_citizenid` (`citizenid`),
            KEY `idx_family_heads_discord` (`discord`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_points` (
            `family` varchar(50) NOT NULL,
            `available_points` int(11) NOT NULL DEFAULT 0,
            `total_points` int(11) NOT NULL DEFAULT 0,
            `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`family`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_settings` (
            `family` varchar(50) NOT NULL,
            `image_url` varchar(900) DEFAULT NULL,
            `theme_color` varchar(7) DEFAULT NULL,
            `updated_by` varchar(50) DEFAULT NULL,
            `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`family`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    trySchemaQuery('ALTER TABLE `family_settings` ADD COLUMN `theme_color` varchar(7) DEFAULT NULL AFTER `image_url`')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_funds` (
            `family` varchar(50) NOT NULL,
            `balance` int(11) NOT NULL DEFAULT 0,
            `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`family`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_fund_transactions` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `family` varchar(50) NOT NULL,
            `citizenid` varchar(50) DEFAULT NULL,
            `type` varchar(40) NOT NULL,
            `amount` int(11) NOT NULL,
            `balance_after` int(11) NOT NULL DEFAULT 0,
            `metadata` longtext DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_family_fund_transactions_family` (`family`),
            KEY `idx_family_fund_transactions_created_at` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_reward_redemptions` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `family` varchar(50) NOT NULL,
            `reward_id` varchar(80) NOT NULL,
            `redeemed_by` varchar(50) NOT NULL,
            `cost` int(11) NOT NULL DEFAULT 0,
            `fund_cost` int(11) NOT NULL DEFAULT 0,
            `payload` longtext DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_family_reward_redemptions_family` (`family`),
            KEY `idx_family_reward_redemptions_reward_id` (`reward_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    trySchemaQuery('ALTER TABLE `family_reward_redemptions` ADD COLUMN `fund_cost` int(11) NOT NULL DEFAULT 0 AFTER `cost`')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_events` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `family` varchar(50) NOT NULL,
            `name` varchar(80) NOT NULL,
            `created_by` varchar(50) NOT NULL,
            `coords` longtext NOT NULL,
            `props` longtext NULL,
            `preset` varchar(50) DEFAULT NULL,
            `radius` float NOT NULL DEFAULT 35,
            `points_per_tick` int(11) NOT NULL DEFAULT 10,
            `status` varchar(20) NOT NULL DEFAULT 'active',
            `location` varchar(80) DEFAULT NULL,
            `started_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `starts_at` timestamp NULL DEFAULT NULL,
            `ended_at` timestamp NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_family_events_family` (`family`),
            KEY `idx_family_events_status` (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_event_templates` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `family` varchar(50) NOT NULL,
            `name` varchar(80) NOT NULL,
            `created_by` varchar(50) NOT NULL,
            `coords` longtext NOT NULL,
            `props` longtext NULL,
            `preset` varchar(50) DEFAULT NULL,
            `radius` float NOT NULL DEFAULT 35,
            `points_per_tick` int(11) NOT NULL DEFAULT 10,
            `banner_url` longtext NULL,
            `location` varchar(80) DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_family_event_templates_family` (`family`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    trySchemaQuery('ALTER TABLE `family_event_templates` MODIFY COLUMN `banner_url` longtext NULL')
    trySchemaQuery('ALTER TABLE `family_event_templates` ADD COLUMN `preset` varchar(50) DEFAULT NULL AFTER `coords`')
    trySchemaQuery('ALTER TABLE `family_event_templates` ADD COLUMN `props` longtext NULL AFTER `coords`')
    trySchemaQuery('ALTER TABLE `family_event_templates` ADD COLUMN `location` varchar(80) DEFAULT NULL AFTER `banner_url`')
    trySchemaQuery('ALTER TABLE `family_events` ADD COLUMN `preset` varchar(50) DEFAULT NULL AFTER `coords`')
    trySchemaQuery('ALTER TABLE `family_events` ADD COLUMN `props` longtext NULL AFTER `coords`')
    trySchemaQuery('ALTER TABLE `family_events` ADD COLUMN `location` varchar(80) DEFAULT NULL AFTER `points_per_tick`')
    trySchemaQuery('ALTER TABLE `family_events` ADD COLUMN `starts_at` timestamp NULL DEFAULT NULL AFTER `started_at`')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `family_event_shares` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `template_id` int(11) NOT NULL,
            `owner_family` varchar(50) NOT NULL,
            `shared_with_family` varchar(50) NOT NULL,
            `shared_by` varchar(50) NOT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_family_event_share` (`template_id`, `shared_with_family`),
            KEY `idx_family_event_shares_owner` (`owner_family`),
            KEY `idx_family_event_shares_shared_with` (`shared_with_family`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.update.await("UPDATE family_events SET status = 'ended', ended_at = COALESCE(ended_at, NOW()) WHERE status IN ('active', 'scheduled')")
end

CreateThread(function()
    ensureDatabase()
end)

local function isFamilyHead(source, family)
    if not source or source == 0 or not family or family == 'none' then return false end

    local citizenid = getCitizenId(source)
    local discordId = getDiscordId(source)
    if not citizenid and not discordId then return false end

    local conditions = {}
    local params = { family }

    if citizenid then
        conditions[#conditions + 1] = 'citizenid = ?'
        params[#params + 1] = citizenid
    end

    if discordId then
        conditions[#conditions + 1] = 'discord = ?'
        params[#params + 1] = discordId
    end

    local query = ('SELECT id FROM family_heads WHERE family = ? AND (%s) LIMIT 1'):format(table.concat(conditions, ' OR '))
    return MySQL.single.await(query, params) ~= nil
end

local function canManage(source, actorFamily, permission)
    local permissions = Config.Management.headPermissions or {}
    return permissions[permission] == true and isFamilyHead(source, actorFamily.family)
end

local function audit(action, actorCitizenId, targetCitizenId, family, payload)
    MySQL.insert.await([[
        INSERT INTO family_audit_logs (action, actor_citizenid, target_citizenid, family, payload)
        VALUES (?, ?, ?, ?, ?)
    ]], { action, actorCitizenId, targetCitizenId, family, json.encode(payload or {}) })

    if lib and lib.logger then
        pcall(function()
            lib.logger(0, 'family:' .. action, ('%s | actor: %s | target: %s | family: %s'):format(action, actorCitizenId or 'system', targetCitizenId or 'n/a', family or 'n/a'), payload or {})
        end)
    end
end

local function refreshFamilyMembers(family)
    if not family or family == 'none' then return end

    local rows = MySQL.query.await('SELECT citizenid FROM family_members WHERE family = ?', { family }) or {}
    for _, row in ipairs(rows) do
        local targetSource = getOnlineSourceByCitizenId(row.citizenid)
        if targetSource then
            TriggerClientEvent('qbx_families:client:refreshMenu', targetSource)
        end
    end
end

local function saveFamilySettings(source, data)
    local citizenid = getCitizenId(source)
    local family = getEffectiveFamily(citizenid)

    if family.family == 'none' or not isFamilyHead(source, family.family) then
        return false, 'Only Head of House can update family settings.'
    end

    local imageUrl, err = normalizeImageUrl(data and data.imageUrl)
    if err then return false, err end
    local themeColor
    themeColor, err = normalizeThemeColor(data and data.themeColor)
    if err then return false, err end

    MySQL.insert.await([[
        INSERT INTO family_settings (family, image_url, theme_color, updated_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE image_url = VALUES(image_url), theme_color = VALUES(theme_color), updated_by = VALUES(updated_by), updated_at = NOW()
    ]], { family.family, imageUrl, themeColor, citizenid })

    audit('family_settings_updated', citizenid, nil, family.family, {
        imageUrl = imageUrl,
        themeColor = themeColor
    })
    refreshFamilyMembers(family.family)

    return true, 'Family settings updated.'
end

local function donateFamilyFunds(source, data)
    local citizenid = getCitizenId(source)
    local family = getEffectiveFamily(citizenid)
    if family.family == 'none' then return false, 'You are not in a family.' end

    local amount = math.floor(tonumber(data and data.amount) or 0)
    local minAmount = math.floor(tonumber(Config.Funds.minDonation) or 1)
    local maxAmount = math.floor(tonumber(Config.Funds.maxDonation) or 100000)
    if amount < minAmount or amount > maxAmount then
        return false, ('Donation must be between $%s and $%s.'):format(minAmount, maxAmount)
    end

    local account = tostring(data and data.account or 'cash')
    local allowed = false
    for _, option in ipairs(Config.Funds.donationAccounts or {}) do
        if option.value == account then
            allowed = true
            break
        end
    end
    if not allowed then return false, 'Choose a valid donation account.' end

    local player = getPlayer(source)
    if not player then return false, 'Player not found.' end

    if not player.Functions.RemoveMoney(account, amount, 'family-fund-donation') then
        return false, 'You do not have enough money for that donation.'
    end

    local ok, balanceOrError = changeFamilyFunds(family.family, amount, citizenid, 'donation', {
        account = account
    })

    if not ok then
        player.Functions.AddMoney(account, amount, 'family-fund-donation-refund')
        return false, balanceOrError
    end

    refreshFamilyMembers(family.family)
    return true, ('Donated $%s to the family fund.'):format(amount)
end

local function setFamily(actorSource, targetCitizenId, family, role, reason)
    if family == 'none' then
        MySQL.query.await('DELETE FROM family_members WHERE citizenid = ?', { targetCitizenId })
        MySQL.query.await('DELETE FROM family_heads WHERE citizenid = ?', { targetCitizenId })
        audit('family_removed', actorSource and getCitizenId(actorSource) or 'system', targetCitizenId, family, { reason = reason })
        return true
    end

    if not getFamilyDefinition(family) then return false, 'That family does not exist.' end
    if not getRoleDefinition(family, role) then return false, 'That role does not exist in this family.' end

    MySQL.query.await('DELETE FROM family_heads WHERE citizenid = ? AND family <> ?', { targetCitizenId, family })

    MySQL.insert.await([[
        INSERT INTO family_members (citizenid, family, role, invited_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE family = VALUES(family), role = VALUES(role), invited_by = VALUES(invited_by), updated_at = NOW()
    ]], { targetCitizenId, family, role, actorSource and getCitizenId(actorSource) or 'system' })

    audit('family_set', actorSource and getCitizenId(actorSource) or 'system', targetCitizenId, family, {
        role = role,
        reason = reason
    })

    return true
end

local function getHeadCount(family)
    return MySQL.scalar.await('SELECT COUNT(*) FROM family_heads WHERE family = ?', { family }) or 0
end

local function ensureFamilyPoints(family)
    MySQL.insert.await([[
        INSERT IGNORE INTO family_points (family, available_points, total_points)
        VALUES (?, 0, 0)
    ]], { family })
end

local function getFamilyPoints(family)
    ensureFamilyPoints(family)
    return MySQL.single.await('SELECT family, available_points, total_points FROM family_points WHERE family = ?', { family }) or {
        family = family,
        available_points = 0,
        total_points = 0,
    }
end

local function ensureFamilyFunds(family)
    MySQL.insert.await([[
        INSERT IGNORE INTO family_funds (family, balance)
        VALUES (?, 0)
    ]], { family })
end

local function getFamilyFunds(family)
    if not family or family == 'none' then return 0 end
    ensureFamilyFunds(family)
    return MySQL.scalar.await('SELECT balance FROM family_funds WHERE family = ?', { family }) or 0
end

local function logFamilyFundTransaction(family, citizenid, transactionType, amount, balanceAfter, metadata)
    MySQL.insert.await([[
        INSERT INTO family_fund_transactions (family, citizenid, type, amount, balance_after, metadata)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { family, citizenid, transactionType, amount, balanceAfter, json.encode(metadata or {}) })
end

local function changeFamilyFunds(family, amount, citizenid, transactionType, metadata)
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return false, 'Fund amount cannot be zero.' end
    if not getFamilyDefinition(family) or family == 'none' then return false, 'That family does not exist.' end

    ensureFamilyFunds(family)

    if amount > 0 then
        MySQL.update.await('UPDATE family_funds SET balance = balance + ? WHERE family = ?', { amount, family })
    else
        local changed = MySQL.update.await('UPDATE family_funds SET balance = balance + ? WHERE family = ? AND balance >= ?', { amount, family, math.abs(amount) })
        if not changed or changed < 1 then return false, 'That family does not have enough funds.' end
    end

    local balance = getFamilyFunds(family)
    logFamilyFundTransaction(family, citizenid, transactionType or 'adjustment', amount, balance, metadata)
    audit('family_funds_updated', citizenid or 'system', nil, family, {
        amount = amount,
        balance = balance,
        transactionType = transactionType or 'adjustment',
        metadata = metadata or {}
    })

    return true, balance
end

local function updateFamilyPoints(family, amount, actorCitizenId, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return false, 'Point amount cannot be zero.' end
    if not getFamilyDefinition(family) or family == 'none' then return false, 'That family does not exist.' end

    ensureFamilyPoints(family)

    if amount > 0 then
        MySQL.update.await([[
            UPDATE family_points
            SET available_points = available_points + ?, total_points = total_points + ?
            WHERE family = ?
        ]], { amount, amount, family })
    else
        local points = getFamilyPoints(family)
        if points.available_points + amount < 0 then
            return false, 'That family does not have enough available points.'
        end

        MySQL.update.await('UPDATE family_points SET available_points = available_points + ? WHERE family = ?', { amount, family })
    end

    audit('family_points_updated', actorCitizenId or 'system', nil, family, {
        amount = amount,
        reason = reason or 'staff'
    })

    return true
end

local function getFamilyMembersInsideEvent(event)
    local count = 0
    local members = {}
    local rows = MySQL.query.await('SELECT citizenid FROM family_members WHERE family = ?', { event.family }) or {}
    local points = normalizePoints(event.points or event.coords)
    local center = event.coords and event.coords.x and vector3(event.coords.x, event.coords.y, event.coords.z) or nil

    for _, row in ipairs(rows) do
        local targetSource = getOnlineSourceByCitizenId(row.citizenid)
        if targetSource then
            local ped = GetPlayerPed(targetSource)
            if ped and ped ~= 0 then
                local playerCoords = GetEntityCoords(ped)
                local inside = false

                if #points >= (Config.Events.minZonePoints or 4) then
                    inside = isPointInsidePolygon({ x = playerCoords.x, y = playerCoords.y }, points)
                elseif center then
                    inside = #(playerCoords - center) <= event.radius
                end

                if inside then
                    count = count + 1
                    members[#members + 1] = {
                        source = targetSource,
                        citizenid = row.citizenid,
                        name = GetPlayerName(targetSource) or row.citizenid
                    }
                end
            end
        end
    end

    return count, members
end

local function getActiveFamilyEvent(family)
    local event = activeEvents[family]
    if not event then return nil end

    local isScheduled = event.status == 'scheduled'
    local insideCount, insideMembers = 0, {}
    if not isScheduled then
        insideCount, insideMembers = getFamilyMembersInsideEvent(event)
    end

    return {
        id = event.id,
        family = event.family,
        name = event.name,
        coords = event.coords,
        points = event.points,
        pointCount = event.points and #event.points or 0,
        zoneArea = event.points and getPolygonArea(event.points) or 0,
        props = event.props or {},
        preset = event.preset,
        radius = event.radius,
        pointsPerTick = event.pointsPerTick,
        bannerUrl = event.bannerUrl,
        location = event.location or 'Marked Event Area',
        templateId = event.templateId,
        tickMinutes = Config.Events.tickMinutes,
        status = event.status or 'active',
        startsAt = event.startsAt,
        startsIn = event.startsAt and math.max(0, event.startsAt - os.time()) or 0,
        startedBy = event.startedBy,
        startedAt = event.startedAt,
        insideCount = insideCount,
        insideMembers = insideMembers,
    }
end

local function normalizeEventInput(data, familyKey)
    local name = tostring(data.name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then name = 'Family Event' end
    if #name > 80 then name = name:sub(1, 80) end

    local location = tostring(data.location or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if location == '' then location = 'Marked Event Area' end
    if #location > 80 then location = location:sub(1, 80) end

    local bannerUrl = tostring(data.bannerUrl or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if bannerUrl == '' then bannerUrl = nil end
    if bannerUrl and #bannerUrl > (Config.Events.maxBannerBytes or 900000) then bannerUrl = nil end
    if bannerUrl and not bannerUrl:match('^https?://') and not bannerUrl:match('^data:image/[a-zA-Z0-9+.-]+;base64,') then bannerUrl = nil end

    local points = normalizePoints(data.points)
    local area = getPolygonArea(points)
    local presetId, preset = getEventPresetForArea(area)
    local radius = tonumber(preset.radius) or Config.Events.defaultRadius or 35.0
    local pointsPerTick = math.floor(tonumber(preset.pointsPerTick) or Config.Events.defaultPointsPerTick or 10)
    local coords = getZoneCenter(points)
    local props = normalizeEventProps(data.props, points, familyKey)

    return name, presetId, radius, pointsPerTick, bannerUrl, coords, points, area, props, location
end

local function getEventTemplates(family)
    local rows = MySQL.query.await([[
        SELECT
            t.id, t.family, t.name, t.coords, t.props, t.preset, t.radius, t.points_per_tick, t.banner_url, t.location, t.created_at, t.updated_at,
            CASE WHEN t.family = ? THEN 1 ELSE 0 END AS owned,
            s.owner_family
        FROM family_event_templates t
        LEFT JOIN family_event_shares s ON s.template_id = t.id AND s.shared_with_family = ?
        WHERE t.family = ? OR s.shared_with_family = ?
        ORDER BY t.updated_at DESC, t.id DESC
    ]], { family, family, family, family }) or {}

    local templates = {}
    for _, row in ipairs(rows) do
        local ok, coords = pcall(json.decode, row.coords)
        local propsOk, props = pcall(json.decode, row.props or '[]')
        local points = ok and normalizePoints(coords) or {}
        local center = #points > 0 and getZoneCenter(points) or (ok and normalizePoint(coords) or nil)
        local familyData = getFamilyDefinition(row.family)
        local ownerData = getFamilyDefinition(row.owner_family)
        local owned = tonumber(row.owned) == 1 or row.owned == true
        templates[#templates + 1] = {
            id = row.id,
            family = row.family,
            familyLabel = familyData and familyData.label or row.family,
            ownerFamily = row.owner_family,
            ownerFamilyLabel = ownerData and ownerData.label or row.owner_family,
            owned = owned,
            shared = not owned,
            name = row.name,
            coords = center,
            points = points,
            pointCount = #points,
            zoneArea = getPolygonArea(points),
            props = propsOk and normalizeEventProps(props, points, nil, true) or {},
            preset = row.preset,
            radius = row.radius,
            pointsPerTick = row.points_per_tick,
            bannerUrl = row.banner_url,
            location = row.location or 'Marked Event Area',
            createdAt = row.created_at,
            updatedAt = row.updated_at,
        }
    end

    return templates
end

local function createEventTemplate(source, data)
    local citizenid = getCitizenId(source)
    local family = getEffectiveFamily(citizenid)
    if family.family == 'none' then return false, 'You are not in a family.' end
    if not isFamilyHead(source, family.family) then return false, 'Only Heads of House can create family events.' end

    local name, presetId, radius, pointsPerTick, bannerUrl, coords, points, area, props, location = normalizeEventInput(data, family.family)
    if #points < (Config.Events.minZonePoints or 4) then return false, ('Add at least %s zone points before saving.'):format(Config.Events.minZonePoints or 4) end
    if not coords then return false, 'Add event zone points before saving.' end
    if type(data.props) == 'table' and #props < #data.props then
        return false, 'All event props must be approved and placed inside the event zone.'
    end

    local templateId = MySQL.insert.await([[
        INSERT INTO family_event_templates (family, name, created_by, coords, props, preset, radius, points_per_tick, banner_url, location)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { family.family, name, citizenid, json.encode(points), json.encode(props), presetId, radius, pointsPerTick, bannerUrl, location })

    audit('family_event_template_created', citizenid, nil, family.family, {
        templateId = templateId,
        name = name,
        coords = coords,
        points = points,
        zoneArea = area,
        props = props,
        preset = presetId,
        radius = radius,
        pointsPerTick = pointsPerTick,
        bannerUrl = bannerUrl,
        location = location
    })

    return true, name
end

local function startFamilyEvent(source, templateId)
    local citizenid = getCitizenId(source)
    local family = getEffectiveFamily(citizenid)
    if family.family == 'none' then return false, 'You are not in a family.' end
    if not isFamilyHead(source, family.family) then return false, 'Only Heads of House can start family events.' end
    if activeEvents[family.family] then return false, 'This family already has an active event.' end

    templateId = tonumber(templateId)
    if not templateId then return false, 'Choose a saved event to start.' end

    local template = MySQL.single.await([[
        SELECT t.id, t.family, t.name, t.coords, t.props, t.preset, t.radius, t.points_per_tick, t.banner_url, t.location
        FROM family_event_templates t
        LEFT JOIN family_event_shares s ON s.template_id = t.id AND s.shared_with_family = ?
        WHERE t.id = ? AND (t.family = ? OR s.shared_with_family = ?)
        LIMIT 1
    ]], { family.family, templateId, family.family, family.family })

    if not template then return false, 'Saved event not found.' end

    local ok, coords = pcall(json.decode, template.coords)
    if not ok or type(coords) ~= 'table' then return false, 'Saved event has invalid zone data.' end
    local propsOk, decodedProps = pcall(json.decode, template.props or '[]')
    local points = normalizePoints(coords)
    local props = propsOk and normalizeEventProps(decodedProps, points, nil, true) or {}
    local center = #points >= (Config.Events.minZonePoints or 4) and getZoneCenter(points) or normalizePoint(coords)

    local countdownSeconds = math.max(0, math.floor((Config.Events.startCountdownMinutes or 10) * 60))
    local startsAt = os.time() + countdownSeconds

    local eventId = MySQL.insert.await([[
        INSERT INTO family_events (family, name, created_by, coords, props, preset, radius, points_per_tick, status, location, starts_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))
    ]], { family.family, template.name, citizenid, json.encode(coords), json.encode(props), template.preset, template.radius, template.points_per_tick, 'scheduled', template.location or 'Marked Event Area', startsAt })

    activeEvents[family.family] = {
        id = eventId,
        family = family.family,
        name = template.name,
        coords = center,
        points = points,
        zoneArea = getPolygonArea(points),
        props = props,
        preset = template.preset,
        radius = template.radius,
        pointsPerTick = template.points_per_tick,
        bannerUrl = template.banner_url,
        location = template.location or 'Marked Event Area',
        templateId = tonumber(template.id) or template.id,
        status = 'scheduled',
        startsAt = startsAt,
        startedBy = citizenid,
        startedAt = os.time(),
    }

    audit('family_event_scheduled', citizenid, nil, family.family, {
        eventId = eventId,
        templateId = tonumber(template.id) or template.id,
        name = template.name,
        coords = center,
        points = points,
        zoneArea = getPolygonArea(points),
        props = props,
        preset = template.preset,
        radius = template.radius,
        pointsPerTick = template.points_per_tick,
        bannerUrl = template.banner_url,
        location = template.location or 'Marked Event Area'
    })

    return true, template.name
end

local function shareEventTemplate(source, templateId, sharedWithFamily)
    local citizenid = getCitizenId(source)
    local family = getEffectiveFamily(citizenid)
    if family.family == 'none' then return false, 'You are not in a family.' end
    if not isFamilyHead(source, family.family) then return false, 'Only Heads of House can share family events.' end

    templateId = tonumber(templateId)
    sharedWithFamily = tostring(sharedWithFamily or '')
    if not templateId then return false, 'Saved event not found.' end
    if sharedWithFamily == '' or sharedWithFamily == 'none' or sharedWithFamily == family.family or not getFamilyDefinition(sharedWithFamily) then
        return false, 'Choose another valid family to share with.'
    end

    local template = MySQL.single.await('SELECT id, name FROM family_event_templates WHERE id = ? AND family = ? LIMIT 1', { templateId, family.family })
    if not template then return false, 'Only the owning family can share this event.' end

    MySQL.insert.await([[
        INSERT IGNORE INTO family_event_shares (template_id, owner_family, shared_with_family, shared_by)
        VALUES (?, ?, ?, ?)
    ]], { templateId, family.family, sharedWithFamily, citizenid })

    audit('family_event_template_shared', citizenid, nil, family.family, {
        templateId = templateId,
        name = template.name,
        sharedWithFamily = sharedWithFamily
    })

    return true, template.name
end

local function deleteEventTemplate(source, templateId)
    local citizenid = getCitizenId(source)
    local family = getEffectiveFamily(citizenid)
    if family.family == 'none' then return false, 'You are not in a family.' end
    if not isFamilyHead(source, family.family) then return false, 'Only Heads of House can delete family events.' end

    templateId = tonumber(templateId)
    if not templateId then return false, 'Saved event not found.' end

    local template = MySQL.single.await('SELECT id, name FROM family_event_templates WHERE id = ? AND family = ? LIMIT 1', { templateId, family.family })
    if not template then return false, 'Saved event not found.' end

    for _, event in pairs(activeEvents) do
        if event.templateId == templateId then
            return false, 'Stop this event before deleting it.'
        end
    end

    MySQL.update.await('DELETE FROM family_event_shares WHERE template_id = ?', { templateId })
    MySQL.update.await('DELETE FROM family_event_templates WHERE id = ? AND family = ?', { templateId, family.family })
    audit('family_event_template_deleted', citizenid, nil, family.family, {
        templateId = templateId,
        name = template.name
    })

    return true, template.name
end

local function getEventPropScene(event)
    if not event or event.status ~= 'active' then return nil end

    return {
        id = event.id,
        family = event.family,
        name = event.name,
        coords = event.coords,
        props = event.props or {},
        status = event.status
    }
end

local function stopFamilyEvent(source)
    local citizenid = getCitizenId(source)
    local family = getEffectiveFamily(citizenid)
    if family.family == 'none' then return false, 'You are not in a family.' end
    if not isFamilyHead(source, family.family) then return false, 'Only Heads of House can stop family events.' end

    local event = activeEvents[family.family]
    if not event then return false, 'This family does not have an active event.' end

    MySQL.update.await("UPDATE family_events SET status = 'ended', ended_at = NOW() WHERE id = ?", { event.id })
    activeEvents[family.family] = nil
    TriggerClientEvent('qbx_families:client:syncEventProps', -1, nil)

    audit('family_event_stopped', citizenid, nil, family.family, {
        eventId = event.id,
        name = event.name
    })

    return true, event.name
end

CreateThread(function()
    while true do
        Wait(1000)

        local now = os.time()
        for family, event in pairs(activeEvents) do
            if event.status == 'scheduled' and event.startsAt and event.startsAt <= now then
                event.status = 'active'
                MySQL.update.await("UPDATE family_events SET status = 'active' WHERE id = ?", { event.id })
                TriggerClientEvent('qbx_families:client:syncEventProps', -1, getEventPropScene(event))
                audit('family_event_started', 'event', nil, family, {
                    eventId = event.id,
                    templateId = event.templateId,
                    name = event.name
                })
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait((Config.Events.tickMinutes or 5) * 60000)

        for family, event in pairs(activeEvents) do
            if event.status == 'active' then
                local insideCount = getFamilyMembersInsideEvent(event)
                if insideCount >= (Config.Events.minimumMembersInZone or 1) then
                    local points = (event.pointsPerTick or Config.Events.defaultPointsPerTick or 10) * insideCount
                    updateFamilyPoints(family, points, 'event', ('event:%s'):format(event.name))
                    audit('family_event_points_awarded', 'event', nil, family, {
                        eventId = event.id,
                        name = event.name,
                        insideCount = insideCount,
                        points = points
                    })
                end
            end
        end
    end
end)

local function isHeadRecord(family, citizenid, discordId)
    if not citizenid and not discordId then return false end

    local conditions = {}
    local params = { family }

    if citizenid then
        conditions[#conditions + 1] = 'citizenid = ?'
        params[#params + 1] = citizenid
    end

    if discordId then
        conditions[#conditions + 1] = 'discord = ?'
        params[#params + 1] = discordId
    end

    local query = ('SELECT id FROM family_heads WHERE family = ? AND (%s) LIMIT 1'):format(table.concat(conditions, ' OR '))
    return MySQL.single.await(query, params) ~= nil
end

local function addFamilyHead(actorSource, targetSource, family)
    if not getFamilyDefinition(family) or family == 'none' then
        return false, 'That family does not exist.'
    end

    local targetCitizenId = getCitizenId(targetSource)
    if not targetCitizenId then return false, 'Player not found.' end

    local targetFamily = getEffectiveFamily(targetCitizenId)
    if targetFamily.family ~= family then
        return false, 'That player must be in the family before they can be made head of house.'
    end

    local discordId = getDiscordId(targetSource)
    if isHeadRecord(family, targetCitizenId, discordId) then
        return false, 'That player is already a head of house.'
    end

    local maxHeads = Config.Management.maxHeadsPerFamily or 2
    if getHeadCount(family) >= maxHeads then
        return false, ('That family already has the max of %s heads.'):format(maxHeads)
    end

    MySQL.insert.await([[
        INSERT INTO family_heads (family, citizenid, discord, assigned_by)
        VALUES (?, ?, ?, ?)
    ]], { family, targetCitizenId, discordId, actorSource and getCitizenId(actorSource) or 'system' })

    audit('family_head_added', actorSource and getCitizenId(actorSource) or 'system', targetCitizenId, family, {
        discord = discordId
    })

    return true
end

local function removeFamilyHead(actorSource, targetSource, family)
    if not getFamilyDefinition(family) or family == 'none' then
        return false, 'That family does not exist.'
    end

    local targetCitizenId = getCitizenId(targetSource)
    if not targetCitizenId then return false, 'Player not found.' end

    local discordId = getDiscordId(targetSource)
    if not isHeadRecord(family, targetCitizenId, discordId) then
        return false, 'That player is not a head of house for this family.'
    end

    if discordId then
        MySQL.update.await('DELETE FROM family_heads WHERE family = ? AND (citizenid = ? OR discord = ?)', { family, targetCitizenId, discordId })
    else
        MySQL.update.await('DELETE FROM family_heads WHERE family = ? AND citizenid = ?', { family, targetCitizenId })
    end

    audit('family_head_removed', actorSource and getCitizenId(actorSource) or 'system', targetCitizenId, family, {
        discord = discordId
    })

    return true
end

local function randomPlate()
    for _ = 1, 25 do
        local plate = ('FAM%s%s'):format(math.random(100, 999), string.char(math.random(65, 90)))
        local existing = MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE plate = ?', { plate })
        if not existing then return plate end
    end
end

local function giveVehicleReward(source, player, reward)
    local plate = randomPlate()
    if not plate then return false, 'Could not generate a vehicle plate.' end

    local model = reward.vehicle
    local hash = joaat(model)
    local garage = reward.garage or Config.Progression.defaultGarage or 'Legion Square'
    local mods = json.encode({
        model = hash,
        plate = plate,
    })

    local ok, insertId = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO player_vehicles
                (license, citizenid, vehicle, hash, mods, plate, garage, state, garage_id, in_garage, fuel, engine, body, job_vehicle, gang_vehicle)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            player.PlayerData.license,
            player.PlayerData.citizenid,
            model,
            hash,
            mods,
            plate,
            garage,
            1,
            garage,
            1,
            reward.fuel or 100,
            1000,
            1000,
            0,
            0
        })
    end)

    if not ok or not insertId then
        ok, insertId = pcall(function()
            return MySQL.insert.await([[
                INSERT INTO player_vehicles
                    (license, citizenid, vehicle, hash, mods, plate, garage, state)
                VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                player.PlayerData.license,
                player.PlayerData.citizenid,
                model,
                hash,
                mods,
                plate,
                garage,
                1
            })
        end)
    end

    if not ok or not insertId then return false, 'Could not add the vehicle to the garage.' end

    return true, {
        vehicle = model,
        plate = plate,
        garage = garage
    }
end

local function grantReward(source, reward)
    local player = getPlayer(source)
    if not player then return false, 'Player not found.' end

    if reward.type == 'money' then
        player.Functions.AddMoney(reward.account or 'bank', reward.amount or 0, 'family-reward')
        return true, {
            account = reward.account or 'bank',
            amount = reward.amount or 0
        }
    end

    if reward.type == 'item' then
        local ok = exports.ox_inventory:AddItem(source, reward.item, reward.count or 1, reward.metadata)
        if not ok then return false, 'Could not add the item reward.' end
        return true, {
            item = reward.item,
            count = reward.count or 1
        }
    end

    if reward.type == 'vehicle' then
        return giveVehicleReward(source, player, reward)
    end

    if reward.type == 'prop_unlock' then
        return true, {
            unlock = reward.id
        }
    end

    return false, 'Unknown reward type.'
end

local function buildRewards(family, level, availablePoints, familyFunds)
    local rewards = {}

    for _, reward in ipairs(Config.Progression.rewards or {}) do
        local redeemed = false
        if reward.repeatable == false then
            redeemed = MySQL.scalar.await('SELECT id FROM family_reward_redemptions WHERE family = ? AND reward_id = ? LIMIT 1', { family, reward.id }) ~= nil
        end

        rewards[#rewards + 1] = {
            id = reward.id,
            label = reward.label,
            description = reward.description,
            type = reward.type,
            cost = reward.cost or 0,
            fundCost = reward.fundCost or 0,
            requiredLevel = reward.requiredLevel or 1,
            unlocked = level >= (reward.requiredLevel or 1),
            affordable = availablePoints >= (reward.cost or 0) and (familyFunds or 0) >= (reward.fundCost or 0),
            redeemed = redeemed,
            repeatable = reward.repeatable ~= false,
        }
    end

    return rewards
end

local function redeemReward(source, rewardId)
    local citizenid = getCitizenId(source)
    local family = getEffectiveFamily(citizenid)
    if family.family == 'none' then return false, 'You are not in a family.' end
    if not isFamilyHead(source, family.family) then return false, 'Only Heads of House can redeem family rewards.' end

    local reward = getRewardDefinition(rewardId)
    if not reward then return false, 'That reward does not exist.' end

    local points = getFamilyPoints(family.family)
    local familyFunds = getFamilyFunds(family.family)
    local level = getLevel(points.total_points or 0)
    local cost = reward.cost or 0
    local fundCost = reward.fundCost or 0

    if level < (reward.requiredLevel or 1) then return false, 'Your family level is too low for that reward.' end
    if (points.available_points or 0) < cost then return false, 'Your family does not have enough points.' end
    if familyFunds < fundCost then return false, 'Your family does not have enough saved funds.' end

    if reward.repeatable == false then
        local redeemed = MySQL.scalar.await('SELECT id FROM family_reward_redemptions WHERE family = ? AND reward_id = ? LIMIT 1', { family.family, reward.id })
        if redeemed then return false, 'That reward has already been redeemed.' end
    end

    if cost > 0 then
        local changed = MySQL.update.await('UPDATE family_points SET available_points = available_points - ? WHERE family = ? AND available_points >= ?', { cost, family.family, cost })
        if not changed or changed < 1 then return false, 'Your family does not have enough points.' end
    end

    if fundCost > 0 then
        local ok, err = changeFamilyFunds(family.family, -fundCost, citizenid, 'reward_redeem', {
            reward = reward.id,
            rewardLabel = reward.label
        })
        if not ok then
            if cost > 0 then
                MySQL.update.await('UPDATE family_points SET available_points = available_points + ? WHERE family = ?', { cost, family.family })
            end
            return false, err
        end
    end

    local ok, payloadOrError = grantReward(source, reward)
    if not ok then
        if cost > 0 then
            MySQL.update.await('UPDATE family_points SET available_points = available_points + ? WHERE family = ?', { cost, family.family })
        end
        if fundCost > 0 then
            changeFamilyFunds(family.family, fundCost, citizenid, 'reward_refund', {
                reward = reward.id,
                reason = payloadOrError
            })
        end

        return false, payloadOrError
    end

    MySQL.insert.await([[
        INSERT INTO family_reward_redemptions (family, reward_id, redeemed_by, cost, fund_cost, payload)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { family.family, reward.id, citizenid, cost, fundCost, json.encode(payloadOrError or {}) })

    audit('family_reward_redeemed', citizenid, citizenid, family.family, {
        reward = reward.id,
        rewardLabel = reward.label,
        cost = cost,
        fundCost = fundCost,
        payload = payloadOrError
    })
    refreshFamilyMembers(family.family)

    return true, reward.label
end

local function getJobLabelFromJson(jobJson)
    if not jobJson or jobJson == '' then return 'Unknown' end

    local ok, job = pcall(json.decode, jobJson)
    if not ok or type(job) ~= 'table' then return 'Unknown' end

    local grade = job.grade
    local gradeName = type(grade) == 'table' and (grade.name or grade.label or grade.level) or grade

    return ('%s - %s'):format(job.label or job.name or 'Unknown', gradeName or '0')
end

local function buildMember(row)
    local onlineSource = getOnlineSourceByCitizenId(row.citizenid)
    local onlinePlayer = onlineSource and getPlayer(onlineSource)
    local onlineData = onlinePlayer and onlinePlayer.PlayerData or nil
    local name = row.player_name
    local jobLabel = getJobLabelFromJson(row.job)

    if onlineData then
        name = getPlayerNameFromData(onlineData, name)
        local job = onlineData.job or {}
        local grade = job.grade or {}
        jobLabel = ('%s - %s'):format(job.label or job.name or 'Unknown', type(grade) == 'table' and (grade.name or grade.level) or tostring(grade or '0'))
    elseif row.charinfo and row.charinfo ~= '' then
        local ok, charinfo = pcall(json.decode, row.charinfo)
        if ok and type(charinfo) == 'table' then
            name = getPlayerNameFromData({ charinfo = charinfo, name = row.player_name }, name)
        end
    end

    local familyData = getFamilyDefinition(row.family)
    local roleData = getRoleDefinition(row.family, row.role)

    return {
        citizenid = row.citizenid,
        name = name or row.citizenid,
        family = row.family,
        familyLabel = familyData and familyData.label or row.family,
        role = row.role,
        roleLabel = roleData and roleData.label or row.role,
        jobLabel = jobLabel,
        online = onlineSource ~= nil,
        source = onlineSource,
    }
end

local function getMembers(family)
    local rows = MySQL.query.await([[
        SELECT fm.citizenid, fm.family, fm.role, p.name AS player_name, p.charinfo, p.job
        FROM family_members fm
        LEFT JOIN players p ON p.citizenid = fm.citizenid
        WHERE fm.family = ?
        ORDER BY fm.role ASC, p.name ASC
    ]], { family })

    local members = {}
    for _, row in ipairs(rows or {}) do
        members[#members + 1] = buildMember(row)
    end

    return members
end

local function getNearbyPlayers(source, distance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return {} end

    local coords = GetEntityCoords(ped)
    local players = {}

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if target and target ~= source then
            local targetPed = GetPlayerPed(target)
            if targetPed and targetPed ~= 0 and #(coords - GetEntityCoords(targetPed)) <= (distance or 5.0) then
                local player = getPlayer(target)
                if player and player.PlayerData then
                    players[#players + 1] = {
                        source = target,
                        citizenid = player.PlayerData.citizenid,
                        name = getPlayerNameFromData(player.PlayerData, GetPlayerName(target)),
                    }
                end
            end
        end
    end

    return players
end

lib.callback.register('qbx_families:server:getMenuData', function(source)
    local citizenid = getCitizenId(source)
    if not citizenid then return nil end

    local family = getEffectiveFamily(citizenid)
    local familyData = getFamilyDefinition(family.family)
    local roleData = getRoleDefinition(family.family, family.role)
    local isHead = isFamilyHead(source, family.family)
    local points = family.family ~= 'none' and getFamilyPoints(family.family) or { available_points = 0, total_points = 0 }
    local familyFunds = family.family ~= 'none' and getFamilyFunds(family.family) or 0
    local level, nextLevel, currentLevelPoints = getLevel(points.total_points or 0)

    return {
        self = {
            citizenid = citizenid,
            family = family.family,
            familyLabel = familyData and familyData.label or family.family,
            role = family.role,
            roleLabel = roleData and roleData.label or family.role,
            isHead = isHead,
            canInvite = canManage(source, family, 'canInvite'),
            canKick = canManage(source, family, 'canKick'),
            canSetRole = canManage(source, family, 'canSetRole'),
            canGiveAllowance = canManage(source, family, 'canGiveAllowance'),
            isManager = isHead,
        },
        members = family.family ~= 'none' and getMembers(family.family) or {},
        roles = family.family ~= 'none' and getRoleOptions(family.family) or {},
        settings = getFamilySettings(family.family),
        nearby = family.family ~= 'none' and getNearbyPlayers(source, 5.0) or {},
        allowanceMax = Config.Allowance.maxAmount,
        funds = {
            balance = familyFunds,
            donationAccounts = Config.Funds.donationAccounts or {},
            minDonation = Config.Funds.minDonation or 1,
            maxDonation = Config.Funds.maxDonation or 100000,
        },
        progression = {
            level = level,
            availablePoints = points.available_points or 0,
            totalPoints = points.total_points or 0,
            currentLevelPoints = currentLevelPoints,
            nextLevel = nextLevel,
            rewards = family.family ~= 'none' and buildRewards(family.family, level, points.available_points or 0, familyFunds) or {},
        },
        event = family.family ~= 'none' and getActiveFamilyEvent(family.family) or nil,
        eventTemplates = family.family ~= 'none' and getEventTemplates(family.family) or {},
        eventPresets = getEventPresetOptions(),
        eventAllowedProps = getAllowedEventProps(family.family),
        eventMaxProps = Config.Events.maxPropsPerEvent or 0,
        eventMinZonePoints = Config.Events.minZonePoints or 4,
        eventTickMinutes = Config.Events.tickMinutes or 5,
        familyShareOptions = family.family ~= 'none' and getFamilyOptions(family.family) or {},
    }
end)

RegisterNetEvent('qbx_families:server:invite', function(targetSource, role)
    local source = source
    local actorCitizenId = getCitizenId(source)
    local actorFamily = getEffectiveFamily(actorCitizenId)
    targetSource = tonumber(targetSource)

    if actorFamily.family == 'none' or not canManage(source, actorFamily, 'canInvite') then
        return notify(source, 'You cannot invite family members.', 'error')
    end

    if not targetSource or not getCitizenId(targetSource) then
        return notify(source, 'That player is not online.', 'error')
    end

    local roleData = getRoleDefinition(actorFamily.family, role)
    if not roleData then
        return notify(source, 'That family role does not exist.', 'error')
    end

    local targetCitizenId = getCitizenId(targetSource)
    local currentTargetFamily = getEffectiveFamily(targetCitizenId)
    if currentTargetFamily.family ~= 'none' and currentTargetFamily.family ~= actorFamily.family then
        return notify(source, 'That player is already in another family.', 'error')
    end

    local ok, err = setFamily(source, targetCitizenId, actorFamily.family, role, 'family_invite')
    notify(source, ok and 'Family member added.' or err, ok and 'success' or 'error')
    if ok then notify(targetSource, 'You were added to a family.', 'success') end
end)

RegisterNetEvent('qbx_families:server:kick', function(targetCitizenId)
    local source = source
    local actorFamily = getEffectiveFamily(getCitizenId(source))
    local targetFamily = getEffectiveFamily(targetCitizenId)

    if actorFamily.family == 'none' or actorFamily.family ~= targetFamily.family or not canManage(source, actorFamily, 'canKick') then
        return notify(source, 'You cannot kick this family member.', 'error')
    end

    local targetSource = getOnlineSourceByCitizenId(targetCitizenId)
    if isHeadRecord(targetFamily.family, targetCitizenId, targetSource and getDiscordId(targetSource) or nil) then
        return notify(source, 'Heads of house can only be removed by staff.', 'error')
    end

    setFamily(source, targetCitizenId, 'none', 'none', 'family_kick')
    notify(source, 'Family member removed.', 'success')

    if targetSource then notify(targetSource, 'You were removed from your family.', 'error') end
end)

RegisterNetEvent('qbx_families:server:setRole', function(targetCitizenId, role)
    local source = source
    local actorFamily = getEffectiveFamily(getCitizenId(source))
    local targetFamily = getEffectiveFamily(targetCitizenId)

    if actorFamily.family == 'none' or actorFamily.family ~= targetFamily.family or not canManage(source, actorFamily, 'canSetRole') then
        return notify(source, 'You cannot change this family member role.', 'error')
    end

    local roleData = getRoleDefinition(actorFamily.family, role)
    if not roleData then
        return notify(source, 'That role does not exist.', 'error')
    end

    local ok, err = setFamily(source, targetCitizenId, actorFamily.family, role, 'family_role_change')
    notify(source, ok and 'Family role updated.' or err, ok and 'success' or 'error')
end)

RegisterNetEvent('qbx_families:server:allowance', function(targetCitizenId, amount)
    local source = source
    local actorFamily = getEffectiveFamily(getCitizenId(source))
    local targetFamily = getEffectiveFamily(targetCitizenId)
    amount = math.floor(tonumber(amount) or 0)

    if actorFamily.family == 'none' or actorFamily.family ~= targetFamily.family or not canManage(source, actorFamily, 'canGiveAllowance') then
        return notify(source, 'You cannot give family allowance.', 'error')
    end

    if amount <= 0 or amount > (Config.Allowance.maxAmount or 5000) then
        return notify(source, ('Allowance must be between $1 and $%s.'):format(Config.Allowance.maxAmount or 5000), 'error')
    end

    local targetSource = getOnlineSourceByCitizenId(targetCitizenId)
    if not targetSource then
        return notify(source, 'Allowance can only be given to online family members.', 'error')
    end

    local actor = getPlayer(source)
    local target = getPlayer(targetSource)
    if not actor or not target then return notify(source, 'Player not found.', 'error') end

    local moneyType = Config.Allowance.moneyType or 'cash'
    if not actor.Functions.RemoveMoney(moneyType, amount, 'family-allowance') then
        return notify(source, 'You do not have enough cash.', 'error')
    end

    target.Functions.AddMoney(moneyType, amount, 'family-allowance')
    audit('allowance_given', getCitizenId(source), targetCitizenId, actorFamily.family, { amount = amount, moneyType = moneyType })
    notify(source, ('Allowance sent: $%s.'):format(amount), 'success')
    notify(targetSource, ('You received $%s family allowance.'):format(amount), 'success')
end)

RegisterNetEvent('qbx_families:server:redeemReward', function(rewardId)
    local source = source
    local ok, result = redeemReward(source, rewardId)
    notify(source, ok and ('Redeemed: %s.'):format(result) or result, ok and 'success' or 'error')
end)

RegisterNetEvent('qbx_families:server:saveSettings', function(data)
    local source = source
    local ok, result = saveFamilySettings(source, data or {})
    notify(source, result, ok and 'success' or 'error')
end)

RegisterNetEvent('qbx_families:server:donateFunds', function(data)
    local source = source
    local ok, result = donateFamilyFunds(source, data or {})
    notify(source, result, ok and 'success' or 'error')
end)

RegisterNetEvent('qbx_families:server:startEvent', function(data)
    local source = source
    local ok, result = startFamilyEvent(source, data and data.templateId or data)
    notify(source, ok and ('Family event scheduled: %s.'):format(result) or result, ok and 'success' or 'error')
end)

RegisterNetEvent('qbx_families:server:createEventTemplate', function(data)
    local source = source
    local ok, result = createEventTemplate(source, data or {})
    notify(source, ok and ('Saved family event: %s.'):format(result) or result, ok and 'success' or 'error')
end)

RegisterNetEvent('qbx_families:server:deleteEventTemplate', function(templateId)
    local source = source
    local ok, result = deleteEventTemplate(source, templateId)
    notify(source, ok and ('Deleted saved event: %s.'):format(result) or result, ok and 'success' or 'error')
end)

RegisterNetEvent('qbx_families:server:shareEventTemplate', function(data)
    local source = source
    local ok, result = shareEventTemplate(source, data and data.templateId, data and data.family)
    notify(source, ok and ('Shared saved event: %s.'):format(result) or result, ok and 'success' or 'error')
end)

RegisterNetEvent('qbx_families:server:stopEvent', function()
    local source = source
    local ok, result = stopFamilyEvent(source)
    notify(source, ok and ('Family event stopped: %s.'):format(result) or result, ok and 'success' or 'error')
end)

RegisterNetEvent('qbx_families:server:requestActivePropScenes', function()
    local source = source
    for _, event in pairs(activeEvents) do
        if event.status == 'active' then
            TriggerClientEvent('qbx_families:client:syncEventProps', source, getEventPropScene(event))
        end
    end
end)

lib.addCommand('setfamily', {
    help = 'Sets a player family and role',
    restricted = Config.AdminPermission,
    params = {
        { name = 'target', type = 'playerId', help = 'Player ID' },
        { name = 'family', type = 'string', help = 'Family key' },
        { name = 'role', type = 'string', help = 'Role key' },
    }
}, function(source, args)
    local targetCitizenId = getCitizenId(args.target)
    if not targetCitizenId then return notify(source, 'Player not found.', 'error') end

    local ok, err = setFamily(source, targetCitizenId, args.family, args.role, 'admin_setfamily')
    notify(source, ok and 'Family updated.' or err, ok and 'success' or 'error')
    if ok then notify(args.target, 'Your family was updated by staff.', 'inform') end
end)

lib.addCommand('removefamily', {
    help = 'Removes a player from their family',
    restricted = Config.AdminPermission,
    params = {
        { name = 'target', type = 'playerId', help = 'Player ID' },
    }
}, function(source, args)
    local targetCitizenId = getCitizenId(args.target)
    if not targetCitizenId then return notify(source, 'Player not found.', 'error') end

    setFamily(source, targetCitizenId, 'none', 'none', 'admin_removefamily')
    notify(source, 'Family removed.', 'success')
    notify(args.target, 'Your family was removed by staff.', 'inform')
end)

lib.addCommand('addfamilyhead', {
    help = 'Adds a head of house for a family',
    restricted = Config.AdminPermission,
    params = {
        { name = 'target', type = 'playerId', help = 'Player ID' },
        { name = 'family', type = 'string', help = 'Family key' },
    }
}, function(source, args)
    local ok, err = addFamilyHead(source, args.target, args.family)
    notify(source, ok and 'Head of house added.' or err, ok and 'success' or 'error')
    if ok then notify(args.target, 'You were made a head of house.', 'success') end
end)

lib.addCommand('removefamilyhead', {
    help = 'Removes a head of house for a family',
    restricted = Config.AdminPermission,
    params = {
        { name = 'target', type = 'playerId', help = 'Player ID' },
        { name = 'family', type = 'string', help = 'Family key' },
    }
}, function(source, args)
    local ok, err = removeFamilyHead(source, args.target, args.family)
    notify(source, ok and 'Head of house removed.' or err, ok and 'success' or 'error')
    if ok then notify(args.target, 'You are no longer a head of house.', 'inform') end
end)

lib.addCommand('addfamilypoints', {
    help = 'Adds points to a family',
    restricted = Config.AdminPermission,
    params = {
        { name = 'family', type = 'string', help = 'Family key' },
        { name = 'amount', type = 'number', help = 'Amount of points' },
        { name = 'reason', type = 'string', help = 'Reason', optional = true },
    }
}, function(source, args)
    local ok, err = updateFamilyPoints(args.family, args.amount, source ~= 0 and getCitizenId(source) or 'console', args.reason)
    notify(source, ok and 'Family points added.' or err, ok and 'success' or 'error')
end)

lib.addCommand('removefamilypoints', {
    help = 'Removes available points from a family',
    restricted = Config.AdminPermission,
    params = {
        { name = 'family', type = 'string', help = 'Family key' },
        { name = 'amount', type = 'number', help = 'Amount of points' },
        { name = 'reason', type = 'string', help = 'Reason', optional = true },
    }
}, function(source, args)
    local amount = math.abs(tonumber(args.amount) or 0) * -1
    local ok, err = updateFamilyPoints(args.family, amount, source ~= 0 and getCitizenId(source) or 'console', args.reason)
    notify(source, ok and 'Family points removed.' or err, ok and 'success' or 'error')
end)

exports('GetFamily', function(source)
    local citizenid = getCitizenId(source)
    return citizenid and getEffectiveFamily(citizenid) or nil
end)
