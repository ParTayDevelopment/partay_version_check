Client = Client or {}
Client.Zones = Client.Zones or {}

Client.Zones.CurrentStore = nil
Client.Zones.InSalesDesk = false
Client.Zones.InStore = false
Client.Zones.StoreBlips = Client.Zones.StoreBlips or {}

local disabledWeaponControls = { 24, 25, 37, 45, 69, 70, 92, 114, 140, 141, 142, 257, 263, 264, 331 }

local function createBlip(coords, settings, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, settings.Sprite or 110)
    SetBlipColour(blip, settings.Color or 2)
    SetBlipScale(blip, settings.Scale or 0.75)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or settings.Label or 'Ammu-Nation')
    EndTextCommandSetBlipName(blip)
    Client.Zones.StoreBlips[#Client.Zones.StoreBlips + 1] = blip
end

local function createStoreBlips(store)
    if not Config.Blips or Config.Blips.Enabled == false then return end

    if Config.Blips.Stores ~= false and store.storeZone and Config.Blips.Store then
        createBlip(store.storeZone.coords, Config.Blips.Store, Config.Blips.Store.Label or store.label)
    end

    if Config.Blips.Assembly ~= false and store.assembly and store.assembly.Enabled ~= false and Config.Blips.AssemblyStation then
        createBlip(store.assembly.coords, Config.Blips.AssemblyStation, Config.Blips.AssemblyStation.Label or (store.label .. ' Assembly'))
    end
end

local function isDisarmExempt()
    local job = Client.Framework and Client.Framework.GetJob and Client.Framework.GetJob() or nil
    if not job or not job.name then return false end
    if Config.Job and job.name == Config.Job.Name then return true end
    return Config.DisarmZone and Config.DisarmZone.ExemptJobs and Config.DisarmZone.ExemptJobs[job.name] == true
end

local function createStoreZone(store)
    local zone = store.storeZone or {}
    local onEnter = function()
        Client.Zones.InStore = true

        if Config.DisarmZone and Config.DisarmZone.Enabled ~= false and not isDisarmExempt() then
            Client.Notify('store_weapon_policy', 'inform')
        end
    end
    local onExit = function()
        Client.Zones.InStore = false
        TriggerServerEvent('qbx_weapondealer:server:clearStoreVerification', store.id)
        if Client.Nui and Client.Nui.Opened then
            Client.Nui.Close()
        end
    end

    if zone.type == 'poly' and zone.points then
        local minZ = tonumber(zone.minZ or 0.0) or 0.0
        local maxZ = tonumber(zone.maxZ or (minZ + 4.0)) or (minZ + 4.0)
        local centerZ = minZ + ((maxZ - minZ) / 2.0)
        local points = {}

        for index, point in ipairs(zone.points) do
            points[index] = vec3(point.x, point.y, centerZ)
        end

        lib.zones.poly({
            points = points,
            thickness = math.max(maxZ - minZ, 1.0),
            debug = Config.Debug,
            onEnter = onEnter,
            onExit = onExit
        })
        return
    end

    lib.zones.sphere({
        coords = zone.coords,
        radius = zone.radius,
        debug = Config.Debug,
        onEnter = onEnter,
        onExit = onExit
    })
end

local function createSalesDeskZone(store)
    lib.zones.box({
        coords = vec3(store.salesDesk.coords.x, store.salesDesk.coords.y, store.salesDesk.coords.z),
        size = vec3(4.0, 4.0, 3.0),
        rotation = store.salesDesk.coords.w,
        debug = Config.Debug,
        onEnter = function()
            Client.Zones.InSalesDesk = true
        end,
        onExit = function()
            Client.Zones.InSalesDesk = false
            if Client.Nui and Client.Nui.Opened then
                Client.Nui.Close()
            end
        end
    })
end

CreateThread(function()
    for _, store in ipairs(Config.Stores) do
        createStoreBlips(store)
        createStoreZone(store)
        createSalesDeskZone(store)
    end
end)

CreateThread(function()
    while true do
        if Config.DisarmZone and Config.DisarmZone.Enabled ~= false and Client.Zones.InStore and not isDisarmExempt() then
            local ped = PlayerPedId()
            SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)

            for _, control in ipairs(disabledWeaponControls) do
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

    for _, blip in ipairs(Client.Zones.StoreBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
end)
