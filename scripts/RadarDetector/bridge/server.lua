Bridge = {}

local framework = (Config.Framework or 'standalone'):lower()
local qbCore
local esx

local function tryExport(resource, method)
    if GetResourceState(resource) ~= 'started' then return nil end

    local ok, result = pcall(function()
        return exports[resource][method]()
    end)

    if ok then return result end
    return nil
end

CreateThread(function()
    if framework == 'qbox' then
        qbCore = tryExport('qbx_core', 'GetCoreObject')
    elseif framework == 'qbcore' then
        qbCore = tryExport('qb-core', 'GetCoreObject')
    elseif framework == 'esx' then
        esx = tryExport('es_extended', 'getSharedObject')
    end
end)

function Bridge.GetPlayer(source)
    if framework == 'qbox' and GetResourceState('qbx_core') == 'started' then
        local ok, player = pcall(function()
            return exports.qbx_core:GetPlayer(source)
        end)
        return ok and player or nil
    end

    if framework == 'qbcore' then
        qbCore = qbCore or tryExport('qb-core', 'GetCoreObject')
        return qbCore and qbCore.Functions.GetPlayer(source) or nil
    end

    if framework == 'esx' then
        esx = esx or tryExport('es_extended', 'getSharedObject')
        return esx and esx.GetPlayerFromId(source) or nil
    end

    return nil
end

function Bridge.GetIdentifier(source)
    local player = Bridge.GetPlayer(source)

    if framework == 'esx' and player then
        return player.identifier
    end

    if player and player.PlayerData then
        return player.PlayerData.citizenid or player.PlayerData.license
    end

    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:find('license:', 1, true) then
            return identifier
        end
    end

    return ('src:%s'):format(source)
end

function Bridge.GetJob(source)
    local player = Bridge.GetPlayer(source)

    if framework == 'esx' and player and player.job then
        return player.job.name, player.job.grade or 0
    end

    if player and player.PlayerData and player.PlayerData.job then
        local job = player.PlayerData.job
        local grade = 0

        if type(job.grade) == 'table' then
            grade = job.grade.level or job.grade.grade or 0
        else
            grade = job.grade or 0
        end

        return job.name, grade
    end

    return nil, 0
end

function Bridge.HasRadarPermission(source)
    local radarConfig = Config.Radars.wk_wars2x
    if not radarConfig.requireAllowedJob then return true end

    local job, grade = Bridge.GetJob(source)
    local minimumGrade = job and radarConfig.allowedJobs[job]

    return minimumGrade ~= nil and tonumber(grade or 0) >= minimumGrade
end

function Bridge.Notify(source, message, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = Config.Item.label,
        description = message,
        type = notifyType or 'inform',
        position = Config.Notifications.position
    })
end
