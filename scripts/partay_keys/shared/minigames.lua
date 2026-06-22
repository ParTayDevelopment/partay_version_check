-- [[ Open Minigame Wrapper ]] --

local warnedMinigameProviders = {}

local function NormalizeMinigameType()
    local configured = Config.Minigames and Config.Minigames.Provider or Config.MinigameType or 'ox_lib'
    local minigameType = tostring(configured):lower()
    minigameType = minigameType:gsub('%-', '_')

    if minigameType == 'ps' then return 'ps_ui' end
    if minigameType == 'qb' or minigameType == 'qb_skillbar' then return 'qb_skillbar' end
    if minigameType == 'boii' then return 'boii_ui' end
    if minigameType == 'bl' then return 'bl_ui' end

    return minigameType
end

local function WarnMinigameProvider(message)
    if not Config or not Config.DebugMode or warnedMinigameProviders[message] then return end
    warnedMinigameProviders[message] = true
    print(('^5[ParTay Keys Debug]^3 Minigame Warning: %s^0'):format(message))
end

local function ResourceStarted(resource)
    return GetResourceState and GetResourceState(resource) == 'started'
end

local function Finish(cb, success)
    cb(success == true)
end

local function RunOxSkillCheck(cb)
    if not lib or not lib.skillCheck then return false end

    local settings = Config.Minigames and Config.Minigames.Providers and Config.Minigames.Providers.ox_lib or Config.MinigameSettings or {}
    local diff = settings.Difficulty or {'easy', 'easy', 'hard'}
    local keys = settings.Keys or {'w', 'a', 's', 'd'}
    local ok, success = pcall(function()
        return lib.skillCheck(diff, keys)
    end)
    if not ok then return false end

    Finish(cb, success)
    return true
end

function RunHeistMinigame(difficultyOverride, cb)
    local provider = NormalizeMinigameType()
    local providers = Config.Minigames and Config.Minigames.Providers or {}
    local settings = providers[provider] or Config.MinigameSettings or {}

    if provider == 'ox_lib' then
        if RunOxSkillCheck(cb) then return end
    elseif provider == 'ps_ui' and ResourceStarted('ps-ui') then
        local circles = settings.Circles or 2
        local time = settings.Time or 20
        local ok = pcall(function()
            exports['ps-ui']:Circle(function(success)
                Finish(cb, success)
            end, circles, time)
        end)
        if ok then return end
    elseif provider == 'qb_skillbar' and ResourceStarted('qb-skillbar') then
        local duration = settings.Duration or 7500
        local position = settings.Position or math.random(10, 30)
        local width = settings.Width or math.random(10, 20)
        local ok = pcall(function()
            exports['qb-skillbar']:GetSkillbarObject().Start({
                duration = duration,
                pos = position,
                width = width,
            }, function()
                Finish(cb, true)
            end, function()
                Finish(cb, false)
            end)
        end)
        if ok then return end
    elseif provider == 'boii_ui' and ResourceStarted('boii_ui') then
        local ok = pcall(function()
            exports['boii_ui']:skill_check({
                style = settings.Style or 'default',
                difficulty = difficultyOverride or settings.Difficulty or 3
            }, function(success)
                Finish(cb, success)
            end)
        end)
        if ok then return end
    elseif provider == 'bl_ui' and ResourceStarted('bl_ui') then
        local iterations = settings.Iterations or 3
        local difficulty = settings.Difficulty or difficultyOverride or 50
        local ok, success = pcall(function()
            if exports.bl_ui.CircleProgress then
                return exports.bl_ui:CircleProgress(iterations, difficulty)
            end
            if exports.bl_ui.Progress then
                return exports.bl_ui:Progress(iterations, difficulty)
            end
            return false
        end)
        if ok then
            Finish(cb, success)
            return
        end
    elseif provider == 'rcore' and ResourceStarted('rcore_minigames') then
        local ok = pcall(function()
            exports['rcore_minigames']:StartMinigame(function(success)
                Finish(cb, success)
            end, settings or {})
        end)
        if ok then return end
    elseif provider == 'custom' and type(Config.CustomMinigame) == 'function' then
        local ok = pcall(function()
            Config.CustomMinigame(difficultyOverride, function(success)
                Finish(cb, success)
            end)
        end)
        if ok then return end
    end

    WarnMinigameProvider(('Provider "%s" failed or is unavailable. Falling back to ox_lib skill check.'):format(provider))
    if RunOxSkillCheck(cb) then return end

    WarnMinigameProvider('ox_lib skill check fallback failed. Returning failure.')
    Finish(cb, false)
end
