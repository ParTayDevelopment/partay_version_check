Client = Client or {}
Client.Framework = Client.Framework or {}

local qb = nil
local esx = nil
local currentJob = nil

local function getQBCore()
    if qb then return qb end

    if GetResourceState('qb-core') == 'started' then
        qb = exports['qb-core']:GetCoreObject()
    end

    return qb
end

local function getESX()
    if esx then return esx end

    if GetResourceState('es_extended') == 'started' then
        esx = exports.es_extended:getSharedObject()
    end

    return esx
end

local function normalizeJob(job)
    if not job then return nil end
    if type(job) == 'string' then
        return {
            name = job,
            grade = 0,
            duty = true
        }
    end
    if not job.name then return nil end

    return {
        name = job.name,
        grade = job.grade and (job.grade.level or job.grade.grade or job.grade) or 0,
        duty = job.onduty == nil and true or job.onduty
    }
end

local function readFrameworkJob()
    local stateJob = LocalPlayer and LocalPlayer.state and LocalPlayer.state.job
    local normalizedStateJob = normalizeJob(stateJob)
    if normalizedStateJob and normalizedStateJob.name then
        return normalizedStateJob
    end

    if Config.Framework.Name == 'qbox' and GetResourceState('qbx_core') == 'started' then
        local ok, data = pcall(function()
            return exports.qbx_core:GetPlayerData()
        end)

        if ok and data and data.job then
            return normalizeJob(data.job)
        end
    end

    if Config.Framework.Name == 'qb' then
        local core = getQBCore()
        local data = core and core.Functions.GetPlayerData()
        if data and data.job then
            return normalizeJob(data.job)
        end
    end

    if Config.Framework.Name == 'esx' then
        local core = getESX()
        local data = core and core.GetPlayerData()
        if data and data.job then
            return normalizeJob(data.job)
        end
    end

end

function Client.Framework.RefreshJob(job)
    currentJob = normalizeJob(job) or readFrameworkJob()
    return currentJob
end

function Client.Framework.GetJob()
    return currentJob or Client.Framework.RefreshJob()
end

function Client.Framework.GetName()
    if Config.Framework.Name == 'qbox' and GetResourceState('qbx_core') == 'started' then
        local ok, data = pcall(function()
            return exports.qbx_core:GetPlayerData()
        end)

        local charinfo = ok and data and data.charinfo or nil
        if charinfo then
            local first = charinfo.firstname or ''
            local last = charinfo.lastname or ''
            local name = (('%s %s'):format(first, last)):gsub('^%s*(.-)%s*$', '%1')
            if name ~= '' then return name end
        end
    end

    if Config.Framework.Name == 'qb' then
        local core = getQBCore()
        local data = core and core.Functions.GetPlayerData()
        local charinfo = data and data.charinfo or nil
        if charinfo then
            local name = (('%s %s'):format(charinfo.firstname or '', charinfo.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
            if name ~= '' then return name end
        end
    end

    if Config.Framework.Name == 'esx' then
        local core = getESX()
        local data = core and core.GetPlayerData()
        if data and data.firstName and data.lastName then
            return ('%s %s'):format(data.firstName, data.lastName)
        end
    end

    return ('Player %s'):format(GetPlayerServerId(PlayerId()))
end

function Client.Framework.IsAuthorized(action)
    local job = Client.Framework.GetJob()
    if not job or job.name ~= Config.Job.Name then
        return false
    end

    if Config.Job.RequireDuty and not job.duty then
        return false
    end

    return tonumber(job.grade or 0) >= tonumber(Config.Job.Grades[action] or 0)
end

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    Client.Framework.RefreshJob(job)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Client.Framework.RefreshJob()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    currentJob = nil
end)

RegisterNetEvent('qbx_core:client:onJobUpdate', function(job)
    Client.Framework.RefreshJob(job)
end)

RegisterNetEvent('qbx_core:client:jobUpdate', function(job)
    Client.Framework.RefreshJob(job)
end)

RegisterNetEvent('qbx_core:client:setPlayerData', function(data)
    Client.Framework.RefreshJob(data and data.job)
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    currentJob = nil
end)

RegisterNetEvent('esx:setJob', function(job)
    Client.Framework.RefreshJob(job)
end)

RegisterNetEvent('esx:playerLoaded', function(data)
    Client.Framework.RefreshJob(data and data.job)
end)

CreateThread(function()
    Wait(1000)
    Client.Framework.RefreshJob()

    while true do
        Client.Framework.RefreshJob()
        Wait(1500)
    end
end)
