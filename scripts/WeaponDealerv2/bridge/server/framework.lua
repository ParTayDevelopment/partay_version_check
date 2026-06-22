Bridge = Bridge or {}
Bridge.Framework = {}

local Framework = {
    name = Config.Framework.Name or 'qbox',
    qb = nil,
    esx = nil
}

local function getQBCore()
    if Framework.qb then return Framework.qb end

    if GetResourceState('qb-core') == 'started' then
        Framework.qb = exports['qb-core']:GetCoreObject()
    end

    return Framework.qb
end

local function getESX()
    if Framework.esx then return Framework.esx end

    if GetResourceState('es_extended') == 'started' then
        Framework.esx = exports.es_extended:getSharedObject()
    end

    return Framework.esx
end

function Bridge.Framework.GetPlayer(source)
    if Framework.name == 'qbox' and GetResourceState('qbx_core') == 'started' then
        return exports.qbx_core:GetPlayer(source)
    end

    if Framework.name == 'qb' then
        local qb = getQBCore()
        return qb and qb.Functions.GetPlayer(source)
    end

    if Framework.name == 'esx' then
        local esx = getESX()
        return esx and esx.GetPlayerFromId(source)
    end
end

function Bridge.Framework.GetIdentifier(source)
    local player = Bridge.Framework.GetPlayer(source)
    if not player then return nil end

    if Framework.name == 'esx' then
        return player.identifier
    end

    return player.PlayerData and player.PlayerData.citizenid
end

local function sameIdentifier(left, right)
    if not left or not right then return false end
    return tostring(left):lower():gsub('^%s*(.-)%s*$', '%1') == tostring(right):lower():gsub('^%s*(.-)%s*$', '%1')
end

function Bridge.Framework.GetSourceByIdentifier(identifier)
    for _, playerId in ipairs(GetPlayers()) do
        local source = tonumber(playerId)
        if sameIdentifier(Bridge.Framework.GetIdentifier(source), identifier) then
            return source
        end
    end
end

function Bridge.Framework.SameIdentifier(left, right)
    return sameIdentifier(left, right)
end

function Bridge.Framework.GetName(source)
    local player = Bridge.Framework.GetPlayer(source)
    if not player then return ('Player %s'):format(source) end

    if Framework.name == 'esx' then
        local first = player.get and player.get('firstName') or nil
        local last = player.get and player.get('lastName') or nil
        return first and last and ('%s %s'):format(first, last) or player.getName()
    end

    if not player.PlayerData then return ('Player %s'):format(source) end

    local charinfo = player.PlayerData.charinfo or {}
    local first = charinfo.firstname or 'Unknown'
    local last = charinfo.lastname or 'Citizen'

    return (('%s %s'):format(first, last)):gsub('^%s*(.-)%s*$', '%1')
end

function Bridge.Framework.GetJob(source)
    local player = Bridge.Framework.GetPlayer(source)
    if not player then return nil end

    if Framework.name == 'esx' then
        local job = player.job
        if not job then return nil end

        return {
            name = job.name,
            grade = job.grade or 0,
            label = job.label,
            duty = true
        }
    end

    local job = player and player.PlayerData and player.PlayerData.job
    if not job then return nil end

    return {
        name = job.name,
        grade = job.grade and (job.grade.level or job.grade) or 0,
        label = job.label,
        duty = job.onduty == nil and true or job.onduty
    }
end

function Bridge.Framework.IsAuthorized(source, action)
    local job = Bridge.Framework.GetJob(source)
    if not job or job.name ~= Config.Job.Name then
        return false, 'not_authorized'
    end

    if Config.Job.RequireDuty and not job.duty then
        return false, 'off_duty'
    end

    local required = Config.Job.Grades[action] or 0
    if tonumber(job.grade) < required then
        return false, 'not_authorized'
    end

    return true
end

function Bridge.Framework.RemoveMoney(source, account, amount, reason)
    local player = Bridge.Framework.GetPlayer(source)
    if not player then return false end

    if Framework.name == 'esx' then
        local esxAccount = account == 'cash' and 'money' or account
        local balance = player.getAccount(esxAccount) and player.getAccount(esxAccount).money or 0
        if balance < amount then return false end
        player.removeAccountMoney(esxAccount, amount, reason or 'weapondealer-purchase')
        return true
    end

    if not player.Functions then return false end

    local money = player.PlayerData.money and player.PlayerData.money[account] or 0
    if money < amount then return false end

    return player.Functions.RemoveMoney(account, amount, reason or 'weapondealer-purchase') == true
end

function Bridge.Framework.GetMoney(source, account)
    local player = Bridge.Framework.GetPlayer(source)
    if not player then return 0 end

    if Framework.name == 'esx' then
        local esxAccount = account == 'cash' and 'money' or account
        return player.getAccount(esxAccount) and player.getAccount(esxAccount).money or 0
    end

    if player.Functions and player.Functions.GetMoney then
        return player.Functions.GetMoney(account) or 0
    end

    return player.PlayerData and player.PlayerData.money and player.PlayerData.money[account] or 0
end

function Bridge.Framework.AddMoney(source, account, amount, reason)
    local player = Bridge.Framework.GetPlayer(source)
    if not player then return false end

    if Framework.name == 'esx' then
        local esxAccount = account == 'cash' and 'money' or account
        player.addAccountMoney(esxAccount, amount, reason or 'weapondealer-commission')
        return true
    end

    if not player.Functions then return false end

    return player.Functions.AddMoney(account, amount, reason or 'weapondealer-commission') == true
end
