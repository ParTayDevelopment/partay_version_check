local _pcmd = (Config.Commands and Config.Commands.player) or {}
local _lbCmd = _pcmd.leaderboard or Config.leaderboardCommand or 'trapleaderboard'

-- Live update toggle for leaderboard
local _LB_LIVE = false
local _LB_UNLOCK = false -- click progress at 100% to unlock claim
local REFRESH_MS = (Config.UI and Config.UI.leaderboardRefreshMs) or 2000
local REFRESH_LOOPS = (Config.UI and Config.UI.leaderboardLiveMaxLoops) or 300

local function computeLevel(points)
    local lvl = 0
    for level, data in ipairs(Config.levels) do
        if points >= tonumber(data.points) then
            lvl = level
        else
            break
        end
    end
    return lvl
end

RegisterCommand(_lbCmd, function(source, args)
    -- Open the new trap leaderboard UI
    OpenTrapLeaderboard()
end)

-- Function to open the trap leaderboard UI
function OpenTrapLeaderboard()
    -- Hide any existing text UI
    lib.hideTextUI()
    
    -- Fetch all data from server using existing callbacks
    local leaderboardData = lib.callback.await('Partay_hustle:getLeaderboard', false)
    local playerData = lib.callback.await('Partay_hustle:getLevel', false)
    local unclaimedData = lib.callback.await('Partay_hustle:getUnclaimedLevels', false)
    
    -- Send all data to NUI
    SendNUIMessage({
        action = 'openUI',
        leaderboard = leaderboardData or {},
        playerData = playerData or {},
        unclaimedData = unclaimedData or {unclaimed = 0, current = 1, rewarded = 0},
        levels = Config.levels or {}
    })
    
    -- Enable NUI focus so player can interact
    SetNuiFocus(true, true)
end

-- NUI Callback: Close UI
RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'closeUI'
    })
    cb('ok')
end)

-- NUI Callback: Get data (for refresh)
RegisterNUICallback('getData', function(data, cb)
    local callbackName = data.callback
    
    local result = lib.callback.await(callbackName, false)
    cb(result or {})
end)

-- NUI Callback: Claim rewards
RegisterNUICallback('claimRewards', function(data, cb)
    local claimed = lib.callback.await('Partay_hustle:claimRewards', false)
    
    -- Show notification
    if claimed and claimed > 0 then
        local msg = (_L and _L('claimed_rewards', { count = claimed })) or ('Claimed %d reward(s)'):format(claimed)
        TriggerEvent('Partay_hustle:client:notify', 'success', msg)
    else
        local msg = (_L and _L('no_rewards')) or 'No rewards to claim'
        TriggerEvent('Partay_hustle:client:notify', 'inform', msg)
    end
    
    cb(claimed or 0)
end)

-- Optional: Update UI when player gains XP (if you have such an event)
RegisterNetEvent('Partay_hustle:updateLevel')
AddEventHandler('Partay_hustle:updateLevel', function(playerData)
    -- Update UI if it's currently open
    SendNUIMessage({
        action = 'updateData',
        playerData = playerData
    })
end)

-- Optional: Update leaderboard in real-time
RegisterNetEvent('Partay_hustle:updateLeaderboard')
AddEventHandler('Partay_hustle:updateLeaderboard', function(leaderboardData)
    SendNUIMessage({
        action = 'updateData',
        leaderboard = leaderboardData
    })
end)
