local Storage = _G.PartayStorage or {}
_G.PartayStorage = Storage

local ready = false
local usingSql = false
local useLegacy = false
local oxmysql = nil

local function resourceActive(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local function ensureOxmysqlExports()
    if oxmysql then return true end
    if not resourceActive('oxmysql') then
        return false, '[Partay_claimpacks] oxmysql is not started. Start oxmysql before this resource.'
    end
    if not exports or not exports.oxmysql then
        return false, '[Partay_claimpacks] Unable to access oxmysql exports. Update oxmysql or ensure it is named correctly.'
    end
    oxmysql = exports.oxmysql
    if type(oxmysql.query_async) ~= 'function' then
        return false, '[Partay_claimpacks] oxmysql exports do not provide query_async. Update oxmysql to the latest version.'
    end
    return true
end

local function ensureSql()
    if usingSql then return true end

    if type(MySQL) == 'table'
        and type(MySQL.prepare) == 'function'
        and type(MySQL.single) == 'function'
        and MySQL.single.await
        and MySQL.prepare.await
    then
        useLegacy = true
        MySQL.ready(function()
            MySQL.query([[CREATE TABLE IF NOT EXISTS `partay_claimpacks_claims` (
                `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
                `identifier` VARCHAR(128) NOT NULL,
                `location` VARCHAR(64) NOT NULL,
                `claimed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_identifier_location` (`identifier`, `location`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

            MySQL.query([[CREATE TABLE IF NOT EXISTS `partay_claimpacks_role_counts` (
                `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
                `role_id` VARCHAR(64) NOT NULL,
                `location` VARCHAR(64) NOT NULL,
                `count` INT UNSIGNED NOT NULL DEFAULT 0,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_role_location` (`role_id`, `location`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])
        end)

        usingSql = true
        return true
    end

    local ok, err = ensureOxmysqlExports()
    if not ok then
        error(err, 0)
    end

    oxmysql:query([[CREATE TABLE IF NOT EXISTS `partay_claimpacks_claims` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(128) NOT NULL,
        `location` VARCHAR(64) NOT NULL,
        `claimed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uniq_identifier_location` (`identifier`, `location`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    oxmysql:query([[CREATE TABLE IF NOT EXISTS `partay_claimpacks_role_counts` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `role_id` VARCHAR(64) NOT NULL,
        `location` VARCHAR(64) NOT NULL,
        `count` INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uniq_role_location` (`role_id`, `location`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    usingSql = true
    return true
end

local function ensureReady()
    if ready then return end
    ensureSql()
    ready = true
end

local function execSingle(query, params)
    if useLegacy then
        return MySQL.single.await(query, params)
    end

    local row
    if oxmysql.single_async then
        row = oxmysql:single_async(query, params)
    else
        local result = oxmysql:query_async(query, params)
        row = result and result[1]
    end
    return row
end

local function execExecute(query, params)
    if useLegacy then
        return MySQL.prepare.await(query, params)
    end
    if oxmysql.execute_async then
        return oxmysql:execute_async(query, params)
    end
    return oxmysql:query_async(query, params)
end

local function sqlGetClaimData(identifier, locationId)
    local row = execSingle([[SELECT UNIX_TIMESTAMP(`claimed_at`) AS `last_claim`
        FROM `partay_claimpacks_claims`
        WHERE `identifier` = ? AND `location` = ?
        LIMIT 1
    ]], { identifier, locationId })
    if row and row.last_claim then
        return { last = tonumber(row.last_claim) }
    end
    return nil
end

local function sqlSetClaim(identifier, locationId, claimedAt)
    local timestamp = tonumber(claimedAt)
    if timestamp then
        execExecute([[INSERT INTO `partay_claimpacks_claims` (`identifier`, `location`, `claimed_at`)
            VALUES (?, ?, FROM_UNIXTIME(?))
            ON DUPLICATE KEY UPDATE `claimed_at` = FROM_UNIXTIME(?)
        ]], { identifier, locationId, timestamp, timestamp })
    else
        execExecute([[INSERT INTO `partay_claimpacks_claims` (`identifier`, `location`, `claimed_at`)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON DUPLICATE KEY UPDATE `claimed_at` = CURRENT_TIMESTAMP
        ]], { identifier, locationId })
    end
end

local function sqlGetRoleCount(roleId, locationId)
    local row = execSingle([[SELECT `count`
        FROM `partay_claimpacks_role_counts`
        WHERE `role_id` = ? AND `location` = ?
        LIMIT 1
    ]], { roleId, locationId })
    if row and row.count then
        return tonumber(row.count) or 0
    end
    return 0
end

local function sqlIncrementRoleCount(roleId, locationId)
    execExecute([[INSERT INTO `partay_claimpacks_role_counts` (`role_id`, `location`, `count`)
        VALUES (?, ?, 1)
        ON DUPLICATE KEY UPDATE `count` = `count` + 1
    ]], { roleId, locationId })
end

function Storage.Init()
    ensureReady()
end

function Storage.HasClaimed(identifier, locationId)
    if not identifier or not locationId then return false end
    ensureReady()
    return sqlGetClaimData(identifier, locationId) ~= nil
end

function Storage.GetClaimData(identifier, locationId)
    if not identifier or not locationId then return nil end
    ensureReady()
    return sqlGetClaimData(identifier, locationId)
end

function Storage.MarkClaimed(identifier, locationId, claimedAt)
    if not identifier or not locationId then return false end
    ensureReady()
    sqlSetClaim(identifier, locationId, claimedAt)
    return true
end

function Storage.GetRoleClaimCount(roleId, locationId)
    if not roleId or roleId == '' or not locationId then return 0 end
    ensureReady()
    return sqlGetRoleCount(roleId, locationId)
end

function Storage.IncrementRoleClaim(roleId, locationId)
    if not roleId or roleId == '' or not locationId then return end
    ensureReady()
    sqlIncrementRoleCount(roleId, locationId)
end

function Storage.UsingSql()
    return usingSql
end

return Storage

