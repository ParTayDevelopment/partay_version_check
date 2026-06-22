Client = Client or {}
Client.AssemblyCraft = Client.AssemblyCraft or {}

local active = false

local disabledControls = { 24, 25, 30, 31, 37, 44, 45, 140, 141, 142, 257, 263, 264 }

local function getAnimation()
    return Config.Assembly and Config.Assembly.Animation or {}
end

function Client.AssemblyCraft.Start()
    if active then return end
    active = true

    if Client.TabletVisual then
        Client.TabletVisual.Stop()
    end

    local ped = cache.ped or PlayerPedId()
    local anim = getAnimation()

    if anim.Dict and anim.Name then
        lib.requestAnimDict(anim.Dict, 5000)
        TaskPlayAnim(ped, anim.Dict, anim.Name, 4.0, 4.0, -1, anim.Flag or 49, 0.0, false, false, false)
    end

    CreateThread(function()
        local duration = math.max(1000, (tonumber(Config.Assembly and Config.Assembly.CraftTimeSeconds or 12) or 12) * 1000)

        if lib.progressBar then
            lib.progressBar({
                duration = duration,
                label = Config.Assembly.ProgressLabel or 'Assembling registered firearm order...',
                useWhileDead = false,
                canCancel = false,
                disable = {
                    move = true,
                    car = true,
                    combat = true
                }
            })
        end
    end)
end

function Client.AssemblyCraft.Stop()
    if not active then return end
    active = false

    if lib.progressActive and lib.progressActive() and lib.cancelProgress then
        lib.cancelProgress()
    end

    local ped = cache.ped or PlayerPedId()
    local anim = getAnimation()
    if anim.Dict and anim.Name then
        StopAnimTask(ped, anim.Dict, anim.Name, 1.0)
    end
    ClearPedSecondaryTask(ped)

    if Client.Nui and Client.Nui.Opened and Client.TabletVisual then
        Client.TabletVisual.Start()
    end
end

CreateThread(function()
    while true do
        if active then
            local ped = cache.ped or PlayerPedId()
            local anim = getAnimation()

            if anim.Dict and anim.Name and not IsEntityPlayingAnim(ped, anim.Dict, anim.Name, 3) then
                TaskPlayAnim(ped, anim.Dict, anim.Name, 4.0, 4.0, -1, anim.Flag or 49, 0.0, false, false, false)
            end

            for _, control in ipairs(disabledControls) do
                DisableControlAction(0, control, true)
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= WD.Resource then return end
    Client.AssemblyCraft.Stop()
end)
