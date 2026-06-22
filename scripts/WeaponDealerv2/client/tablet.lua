Client = Client or {}
Client.TabletVisual = Client.TabletVisual or {}

local tabletProp = nil
local active = false
local activeMode = nil
local frozen = false

local function getConfig()
    return Config.TerminalTablet or Config.ConsentTablet or {}
end

function Client.TabletVisual.Stop()
    active = false
    activeMode = nil

    local ped = cache.ped or PlayerPedId()
    local anim = getConfig().Anim
    if anim and anim.Dict then
        StopAnimTask(ped, anim.Dict, anim.Name or 'base', 1.0)
    end

    ClearPedTasks(ped)

    if frozen then
        FreezeEntityPosition(ped, false)
        frozen = false
    end

    if tabletProp and DoesEntityExist(tabletProp) then
        SetEntityAsMissionEntity(tabletProp, true, true)
        DeleteEntity(tabletProp)
    end

    tabletProp = nil
end

local function startScenario(mode, options)
    local ped = cache.ped or PlayerPedId()

    if mode == 'sales' then
        local terminal = options and options.terminal
        if terminal then
            SetEntityCoordsNoOffset(ped, terminal.x, terminal.y, terminal.z, false, false, false)
            SetEntityHeading(ped, terminal.w or terminal.heading or GetEntityHeading(ped))
            FreezeEntityPosition(ped, true)
            frozen = true
        end

        TaskStartScenarioInPlace(ped, 'PROP_HUMAN_ATM', 0, true)
        active = true
        activeMode = mode
        return true
    end

    if mode == 'order' then
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_LEANING', 0, true)
        active = true
        activeMode = mode
        return true
    end

    return false
end

function Client.TabletVisual.Start(mode, options)
    mode = mode or 'tablet'

    Client.TabletVisual.Stop()

    if startScenario(mode, options) then
        return
    end

    local cfg = getConfig()
    if cfg.Enabled == false then return end

    local ped = cache.ped or PlayerPedId()
    local anim = cfg.Anim or {}
    local propModel = cfg.Prop or 'prop_cs_tablet'
    local model = joaat(propModel)

    if anim.Dict and anim.Name then
        lib.requestAnimDict(anim.Dict, 5000)
        TaskPlayAnim(ped, anim.Dict, anim.Name, 4.0, 4.0, -1, anim.Flag or 49, 0.0, false, false, false)
    end

    if IsModelInCdimage(model) then
        lib.requestModel(model, 5000)

        local coords = GetEntityCoords(ped)
        tabletProp = CreateObject(model, coords.x, coords.y, coords.z + 0.2, true, true, false)
        SetEntityAsMissionEntity(tabletProp, true, true)
        AttachEntityToEntity(
            tabletProp,
            ped,
            GetPedBoneIndex(ped, cfg.Bone or 28422),
            cfg.Offset and cfg.Offset.x or 0.0,
            cfg.Offset and cfg.Offset.y or -0.03,
            cfg.Offset and cfg.Offset.z or 0.0,
            cfg.Rotation and cfg.Rotation.x or 20.0,
            cfg.Rotation and cfg.Rotation.y or -90.0,
            cfg.Rotation and cfg.Rotation.z or 0.0,
            true,
            true,
            false,
            true,
            1,
            true
        )
        SetModelAsNoLongerNeeded(model)
    end

    active = true
    activeMode = mode
end

CreateThread(function()
    while true do
        if active then
            local ped = cache.ped or PlayerPedId()
            local anim = getConfig().Anim
            if activeMode == 'sales' and not IsPedUsingScenario(ped, 'PROP_HUMAN_ATM') then
                TaskStartScenarioInPlace(ped, 'PROP_HUMAN_ATM', 0, true)
            elseif activeMode == 'order' and not IsPedUsingScenario(ped, 'WORLD_HUMAN_LEANING') then
                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_LEANING', 0, true)
            elseif anim and anim.Dict and anim.Name and not IsEntityPlayingAnim(ped, anim.Dict, anim.Name, 3) then
                TaskPlayAnim(ped, anim.Dict, anim.Name, 4.0, 4.0, -1, anim.Flag or 49, 0.0, false, false, false)
            end
        end

        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= WD.Resource then return end

    Client.TabletVisual.Stop()
end)
