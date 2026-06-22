local Framework = _G.PartayFramework or {
    name = nil
}
_G.PartayFramework = Framework

local ESX, QBCore, QBOX

local function resourceActive(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local function detectESX()
    if not resourceActive('es_extended') then return false end

    local ok, obj = pcall(function()
        if exports and exports['es_extended'] and exports['es_extended'].getSharedObject then
            return exports['es_extended']:getSharedObject()
        end
    end)

    if ok and obj then
        ESX = obj
        return true
    end

    TriggerEvent('esx:getSharedObject', function(shared)
        ESX = shared
    end)

    return ESX ~= nil
end

local function detectQBCore()
    if not resourceActive('qb-core') then return false end

    local ok, obj = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)

    if ok and obj then
        QBCore = obj
        return true
    end

    if QBCore and QBCore.Functions then
        return true
    end

    return false
end

local function detectQbox()
    if resourceActive('qbx-core') then
        local ok, obj = pcall(function()
            return exports['qbx-core']:GetCoreObject()
        end)
        if ok and obj then
            QBOX = obj
            return true
        end
    end

    if resourceActive('qbox') then
        local ok, obj = pcall(function()
            return exports['qbox']:GetCoreObject()
        end)
        if ok and obj then
            QBOX = obj
            return true
        end
    end

    return false
end

local function ensureDetected()
    if Framework.name then return Framework.name end

    local override = (Config.Framework or 'auto'):lower()

    local detectors = {
        esx = function()
            if detectESX() then
                Framework.name = 'esx'
                return true
            end
        end,
        qbcore = function()
            if detectQBCore() then
                Framework.name = 'qbcore'
                return true
            end
        end,
        qbox = function()
            if detectQbox() then
                Framework.name = 'qbox'
                return true
            end
        end
    }

    if override ~= 'auto' and detectors[override] then
        detectors[override]()
        return Framework.name
    end

    for _, fn in ipairs({ detectors.esx, detectors.qbcore, detectors.qbox }) do
        if fn() then break end
    end

    if not Framework.name and Config.Debug then
        print('[Partay_claimpacks] Framework auto-detect failed. Set Config.Framework to override.')
    end

    return Framework.name
end

local function parseGender(value)
    if value == nil then return nil end
    if type(value) == 'number' then
        return value == 1 and 'female' or 'male'
    end
    if type(value) == 'string' then
        value = value:lower()
        if value == 'm' or value == 'male' then
            return 'male'
        elseif value == 'f' or value == 'female' then
            return 'female'
        end
    end
    return nil
end

local function genderFromPedModel(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    if IsPedMale then
        local ok, isMale = pcall(IsPedMale, ped)
        if ok and type(isMale) == 'boolean' then
            return isMale and 'male' or 'female'
        end
    end
    local model = GetEntityModel(ped)
    if not model or model == 0 then return nil end
    if model == GetHashKey('mp_m_freemode_01') then return 'male' end
    if model == GetHashKey('mp_f_freemode_01') then return 'female' end
    return nil
end

local function identifierFromIdentifiers(source)
    local identifiers = GetPlayerIdentifiers(source)
    if not identifiers then return nil end

    local fallback
    for _, id in ipairs(identifiers) do
        if id:find('license:', 1, true) then
            return id
        elseif id:find('fivem:', 1, true) then
            fallback = fallback or id
        elseif id:find('discord:', 1, true) then
            fallback = fallback or id
        end
    end
    return fallback
end

function Framework.GetIdentifier(source)
    if GetPlayerIdentifierByType then
        local license = GetPlayerIdentifierByType(source, 'license')
        if license and license ~= '' then
            return license
        end
    end

    return identifierFromIdentifiers(source)
end

function Framework.GetPlayerData(source)
    ensureDetected()

    if Framework.name == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return nil end
        local job = xPlayer.getJob and xPlayer.getJob() or xPlayer.job
        local gender = xPlayer.get and xPlayer.get('sex') or xPlayer.sex
        return {
            name = xPlayer.getName and xPlayer.getName() or xPlayer.name,
            identifier = Framework.GetIdentifier(source) or xPlayer.identifier,
            job = job and job.name or nil,
            jobLabel = job and (job.label or job.name) or nil,
            jobGrade = job and (job.grade or job.grade_name or job.grade_label) or nil,
            gender = parseGender(gender)
        }
    end

    if Framework.name == 'qbcore' and QBCore then
        local player = QBCore.Functions.GetPlayer(source)
        if not player then return nil end
        local data = player.PlayerData or {}
        return {
            name = data.charinfo and data.charinfo.firstname and (data.charinfo.firstname .. ' ' .. (data.charinfo.lastname or '')) or data.name,
            identifier = Framework.GetIdentifier(source) or data.license or data.citizenid,
            job = data.job and data.job.name or nil,
            jobLabel = data.job and (data.job.label or data.job.name) or nil,
            jobGrade = data.job and data.job.grade and (data.job.grade.name or data.job.grade.level) or nil,
            gender = parseGender(data.charinfo and data.charinfo.gender)
        }
    end

    if Framework.name == 'qbox' and QBOX then
        local player
        if QBOX.Functions and QBOX.Functions.GetPlayer then
            player = QBOX.Functions.GetPlayer(source)
        end
        if not player then
            if QBOX.GetPlayer then
                player = QBOX.GetPlayer(source)
            elseif QBOX.PlayerData and QBOX.PlayerData[source] then
                player = QBOX.PlayerData[source]
            end
        end

        if not player then return nil end
        local data = player.PlayerData or player
        return {
            name = data.charinfo and data.charinfo.firstname and (data.charinfo.firstname .. ' ' .. (data.charinfo.lastname or '')) or data.name,
            identifier = Framework.GetIdentifier(source) or data.license or data.citizenid,
            job = data.job and data.job.name or nil,
            jobLabel = data.job and (data.job.label or data.job.name) or nil,
            jobGrade = data.job and data.job.grade and (data.job.grade.name or data.job.grade.level) or nil,
            gender = parseGender(data.charinfo and data.charinfo.gender)
        }
    end

    return nil
end

function Framework.GetJobName(source)
    local player = Framework.GetPlayerData(source)
    return player and player.job or nil
end

function Framework.HasJob(source, allowedJobs)
    if not allowedJobs then return true end
    if type(allowedJobs) ~= 'table' then
        allowedJobs = { allowedJobs }
    end

    local job = Framework.GetJobName(source)
    if not job then return false end

    job = job:lower()
    for key, value in pairs(allowedJobs) do
        local candidate = type(key) == 'number' and value or key
        if type(candidate) == 'string' and job == candidate:lower() then
            return true
        end
    end
    return false
end

function Framework.GetGender(source)
    local player = Framework.GetPlayerData(source)
    local frameworkGender = parseGender(player and player.gender or nil)

    local mode = (Config.GenderSource or 'auto'):lower()
    if mode == 'framework' then
        return frameworkGender or genderFromPedModel(source)
    end

    local pedGender = parseGender(genderFromPedModel(source))
    if mode == 'ped' then
        return pedGender or frameworkGender
    end

    if pedGender and frameworkGender and pedGender ~= frameworkGender and Config.Debug then
        print(('[Partay_claimpacks] Gender mismatch for %s: framework=%s ped=%s; using ped model.'):format(tostring(source), tostring(frameworkGender), tostring(pedGender)))
    end

    return pedGender or frameworkGender
end

function Framework.GetFramework()
    ensureDetected()
    return Framework.name
end

return Framework
