Client = Client or {}

local employeeTargets = {}
local stopConsentTablet
local assemblyProps = {}
local pickupPeds = {}
local activePickupPed = nil
local function serverAllows(action)
    return lib.callback.await('qbx_weapondealer:server:isAuthorized', false, action) == true
end

local function hasJobGrade(grade)
    local job = Client.Framework.GetJob()
    return job
        and job.name == Config.Job.Name
        and (Config.Job.RequireDuty ~= true or job.duty == true)
        and tonumber(job.grade or 0) >= tonumber(grade or 0)
end

local function removeEmployeeTarget(key)
    local targetId = employeeTargets[key]
    if not targetId then return end

    pcall(function()
        exports.ox_target:removeZone(targetId)
    end)

    employeeTargets[key] = nil
end

local function addSalesTarget(store)
    local key = 'sales:' .. store.id
    if employeeTargets[key] then return end

    local targetId = exports.ox_target:addBoxZone({
        coords = vec3(store.salesDesk.coords.x, store.salesDesk.coords.y, store.salesDesk.coords.z),
        size = store.salesDesk.size,
        rotation = store.salesDesk.coords.w,
        debug = Config.Debug,
        options = {
            {
                name = 'qbx_weapondealer_sales_' .. store.id,
                label = 'Legal Firearm Registry',
                icon = 'fa-solid fa-id-card',
                distance = Config.Security.MaxInteractDistance,
                onSelect = function()
                    if not serverAllows('Scan') then
                        Client.Notify('not_authorized', 'error')
                        return
                    end

                    Client.Nui.Open(store, 'sales')
                end
            }
        }
    })

    employeeTargets[key] = targetId

end

local function syncEmployeeTargets()
    local canScan = serverAllows('Scan')

    for _, store in ipairs(Config.Stores) do
        if canScan then
            addSalesTarget(store)
        else
            removeEmployeeTarget('sales:' .. store.id)
        end
    end
end

local function addAssemblyStation(store)
    local assembly = store.assembly
    if not assembly or assembly.Enabled == false or not Config.Assembly or Config.Assembly.Enabled == false then return end

    local coords = assembly.coords
    local modelName = assembly.prop or 'prop_armoury_01'
    local model = joaat(modelName)
    local fallbacks = assembly.propFallbacks or {}

    if not IsModelInCdimage(model) then
        for _, fallback in ipairs(fallbacks) do
            local fallbackModel = joaat(fallback)
            if IsModelInCdimage(fallbackModel) then
                if Config.Debug then
                    print(('[%s] CLIENT DEBUG: assembly prop model not found: %s; using fallback: %s'):format(WD.Resource, tostring(modelName), tostring(fallback)))
                end

                modelName = fallback
                model = fallbackModel
                break
            end
        end
    end

    local options = {
        {
            name = 'qbx_weapondealer_assembly_' .. store.id,
            label = 'Assembly Station',
            icon = 'fa-solid fa-screwdriver-wrench',
            distance = Config.Security.MaxInteractDistance,
            canInteract = function()
                return Client.Framework.IsAuthorized('Order')
            end,
            onSelect = function()
                if not serverAllows('Order') then
                    Client.Notify('not_authorized', 'error')
                    return
                end

                Client.Nui.Open(store, 'assembly')
            end
        },
        {
            name = 'qbx_weapondealer_parts_stash_' .. store.id,
            label = 'Open Parts Stash',
            icon = 'fa-solid fa-boxes-stacked',
            distance = Config.Security.MaxInteractDistance,
            canInteract = function()
                return hasJobGrade(Config.PartsStorage and Config.PartsStorage.DepositGrade or 0)
            end,
            onSelect = function()
                if not serverAllows('Order') then
                    Client.Notify('not_authorized', 'error')
                    return
                end

                exports.ox_inventory:openInventory('stash', assembly.stash)
            end
        }
    }
    local object = nil

    if IsModelInCdimage(model) then
        local loaded = lib.requestModel(model, 5000)
        local offset = assembly.propOffset or vec3(0.0, 0.0, 0.0)

        if loaded ~= false and HasModelLoaded(model) then
            object = CreateObjectNoOffset(model, coords.x + offset.x, coords.y + offset.y, coords.z + offset.z, false, false, false)
        end

        if object and object ~= 0 then
            SetEntityHeading(object, coords.w or 0.0)
            FreezeEntityPosition(object, true)
            SetEntityCollision(object, true, true)
            SetEntityVisible(object, true, false)
            SetEntityAsMissionEntity(object, true, true)
            SetModelAsNoLongerNeeded(model)
            assemblyProps[#assemblyProps + 1] = object
            exports.ox_target:addLocalEntity(object, options)

            if Config.Debug then
                print(('[%s] CLIENT DEBUG: assembly prop spawned for %s using %s'):format(WD.Resource, store.id, tostring(modelName)))
            end
        elseif Config.Debug then
            print(('[%s] CLIENT DEBUG: assembly prop create failed for %s using %s loaded=%s hasModel=%s'):format(
                WD.Resource,
                store.id,
                tostring(modelName),
                tostring(loaded),
                tostring(HasModelLoaded(model))
            ))
        end
    elseif Config.Debug then
        print(('[%s] CLIENT DEBUG: assembly prop model not found and no fallback worked: %s'):format(WD.Resource, tostring(modelName)))
    end

    if object and object ~= 0 then return end

    exports.ox_target:addBoxZone({
        coords = vec3(coords.x, coords.y, coords.z),
        size = assembly.size or vec3(1.6, 1.6, 1.8),
        rotation = coords.w,
        debug = Config.Debug,
        options = options
    })
end

Client.PickupPed = Client.PickupPed or {}

function Client.PickupPed.PlayExchange()
    local ped = activePickupPed
    if not ped or not DoesEntityExist(ped) then return end

    ClearPedTasks(ped)
    TaskTurnPedToFaceEntity(ped, cache.ped, 1000)
    TaskTurnPedToFaceEntity(cache.ped, ped, 1000)
    Wait(600)

    lib.requestAnimDict('mp_common', 3000)
    TaskPlayAnim(ped, 'mp_common', 'givetake1_a', 4.0, -4.0, 1600, 49, 0.0, false, false, false)
    TaskPlayAnim(cache.ped, 'mp_common', 'givetake1_a', 4.0, -4.0, 1600, 49, 0.0, false, false, false)
    Wait(1200)

    local thanks = Config.PickupPed and Config.PickupPed.Thanks or 'Thank you for your business.'
    BeginTextCommandPrint('STRING')
    AddTextComponentSubstringPlayerName(thanks)
    EndTextCommandPrint(3000, true)

    if Config.PickupPed and Config.PickupPed.Scenario then
        TaskStartScenarioInPlace(ped, Config.PickupPed.Scenario, 0, true)
    end
end

local function addPickupInteraction(store)
    local pedCfg = Config.PickupPed or {}

    if pedCfg.Enabled then
        local coords = pedCfg.Coords or store.pickup.coords
        local model = joaat(pedCfg.Model or 's_m_y_ammucity_01')

        if IsModelInCdimage(model) then
            lib.requestModel(model, 5000)
            local ped = CreatePed(4, model, coords.x, coords.y, coords.z, coords.w or 0.0, false, false)

            if ped and ped ~= 0 then
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedDiesWhenInjured(ped, false)
                SetPedCanRagdoll(ped, false)
                FreezeEntityPosition(ped, true)
                if pedCfg.Scenario then
                    TaskStartScenarioInPlace(ped, pedCfg.Scenario, 0, true)
                end
                SetModelAsNoLongerNeeded(model)
                pickupPeds[#pickupPeds + 1] = ped

                exports.ox_target:addLocalEntity(ped, {
                    {
                        name = 'qbx_weapondealer_pickup_ped_' .. store.id,
                        label = 'Secure Weapon Pickup',
                        icon = 'fa-solid fa-box-archive',
                        distance = Config.Security.MaxInteractDistance,
                        onSelect = function()
                            activePickupPed = ped
                            Client.Nui.Open(store, 'pickup')
                        end
                    }
                })
                return
            end
        elseif Config.Debug then
            print(('[%s] CLIENT DEBUG: pickup ped model not found: %s'):format(WD.Resource, tostring(pedCfg.Model)))
        end
    end

    exports.ox_target:addBoxZone({
        coords = vec3(store.pickup.coords.x, store.pickup.coords.y, store.pickup.coords.z),
        size = store.pickup.size,
        rotation = store.pickup.coords.w,
        debug = Config.Debug,
        options = {
            {
                name = 'qbx_weapondealer_pickup_' .. store.id,
                label = 'Secure Weapon Pickup',
                icon = 'fa-solid fa-box-archive',
                distance = Config.Security.MaxInteractDistance,
                onSelect = function()
                    activePickupPed = nil
                    Client.Nui.Open(store, 'pickup')
                end
            }
        }
    })
end

CreateThread(function()
    for _, store in ipairs(Config.Stores) do
        addAssemblyStation(store)
        addPickupInteraction(store)

        for _, station in ipairs(store.orderStations or {}) do
            exports.ox_target:addBoxZone({
                coords = vec3(station.coords.x, station.coords.y, station.coords.z),
                size = station.size,
                rotation = station.coords.w,
                debug = Config.Debug,
                options = {
                    {
                        name = 'qbx_weapondealer_order_' .. station.id,
                        label = 'Browse Firearm Orders',
                        icon = 'fa-solid fa-gun',
                        distance = Config.Security.MaxInteractDistance,
                        onSelect = function()
                            Client.Nui.OpenOrderStation(store, station)
                        end
                    }
                }
            })
        end
    end

    Wait(1500)

    while true do
        syncEmployeeTargets()
        Wait(2000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= WD.Resource then return end

    for key in pairs(employeeTargets) do
        removeEmployeeTarget(key)
    end

    for _, object in ipairs(assemblyProps) do
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end

    for _, ped in ipairs(pickupPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    stopConsentTablet()
end)

local pendingDocumentConsent = nil

function stopConsentTablet()
    if Client.TabletVisual then
        Client.TabletVisual.Stop()
    end
end

local function startConsentTablet()
    if Client.TabletVisual then
        Client.TabletVisual.Start()
    end
end

RegisterNUICallback('documentConsentResponse', function(data, cb)
    if pendingDocumentConsent then
        pendingDocumentConsent:resolve(data and data.approved == true)
        pendingDocumentConsent = nil
    end

    cb({ ok = true })
end)

RegisterNUICallback('documentConsentClosed', function(_, cb)
    stopConsentTablet()
    cb({ ok = true })
end)

RegisterNetEvent('qbx_weapondealer:client:buyerScanProgress', function(rows)
    SendNUIMessage({
        action = 'documentConsentProgress',
        checks = rows or {}
    })
end)

lib.callback.register('qbx_weapondealer:client:confirmDocumentScan', function(employeeName, storeName)
    if pendingDocumentConsent then
        return false
    end

    local restoreNuiFocus = Client.Nui and Client.Nui.Opened
    local consent = promise.new()
    pendingDocumentConsent = consent

    startConsentTablet()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'documentConsentRequest',
        resource = WD.Resource,
        employeeName = employeeName,
        storeName = storeName or 'the gun store'
    })

    SetTimeout(30000, function()
        if pendingDocumentConsent == consent then
            SendNUIMessage({ action = 'documentConsentClose' })
            consent:resolve(false)
            pendingDocumentConsent = nil
            stopConsentTablet()
        end
    end)

    local approved = Citizen.Await(consent)

    if restoreNuiFocus then
        SetNuiFocus(true, true)
    else
        SetNuiFocus(false, false)
    end

    return approved == true
end)
