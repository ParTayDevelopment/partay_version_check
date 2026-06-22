local Zones = _G.PartayZones
local Target = _G.PartayTarget
if not Zones or not Target then
    error('[Partay_claimpacks] Target/Zones not loaded; check client script order.')
end

local LOCALE = Config.Locale or 'en'
local requireStay = Config.RequireStay ~= false
local notify = PartayClaimpacksNotify

local claimed = {}
local pending = {}
local locationsById = {}
local blips = {}

local function removeBlip(locationId)
    local blip = blips[locationId]
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
    blips[locationId] = nil
end

local function getBlipCoords(location)
    if not location then return nil end
    local ped = location.ped
    if not ped then return nil end
    local coords = ped.coords
    if not coords then return nil end
    if type(coords) == 'vector3' then
        return coords
    end
    if type(coords) == 'table' then
        local x = coords.x or coords[1] or 0.0
        local y = coords.y or coords[2] or 0.0
        local z = coords.z or coords[3] or 0.0
        return vector3(x + 0.0, y + 0.0, z + 0.0)
    end
    return nil
end

local function refreshBlip(locationId)
    local location = locationsById[locationId]
    if not location then return end

    local options = location.blip
    if type(options) ~= 'table' or options.enabled == false then
        removeBlip(locationId)
        return
    end

    if location.oneTime ~= false and claimed[locationId] then
        removeBlip(locationId)
        return
    end

    local coords = getBlipCoords(location)
    if not coords then
        removeBlip(locationId)
        return
    end

    local blip = blips[locationId]
    if not blip or not DoesBlipExist(blip) then
        blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, options.sprite or 1)
        if options.color then
            SetBlipColour(blip, options.color)
        end
        SetBlipScale(blip, options.scale or 0.8)
        SetBlipDisplay(blip, options.display or 4)
        SetBlipAsShortRange(blip, options.shortRange ~= false)
        if options.category then
            SetBlipCategory(blip, options.category)
        end
        if options.alpha then
            SetBlipAlpha(blip, options.alpha)
        end
        blips[locationId] = blip
    end

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(options.label or location.label or locationId)
    EndTextCommandSetBlipName(blip)
end


local function translate(key, ...)
    local locale = Locales and Locales[LOCALE]
    local text = locale and locale[key] or key
    if select('#', ...) > 0 and type(text) == 'string' and text:find('%%') then
        return text:format(...)
    end
    return text
end

local function setClaimed(locationId, value)
    local location = locationsById[locationId]
    if not location then return end

    if location.oneTime == false then
        claimed[locationId] = false
        if value == false then
            Zones.Reset(locationId)
        end
        refreshBlip(locationId)
        return
    end

    local claimedState = value and true or false
    claimed[locationId] = claimedState

    if claimedState then
        Zones.OnClaimed(locationId)
    else
        Zones.Reset(locationId)
    end

    refreshBlip(locationId)
end

local function isClaimed(locationId)
    return claimed[locationId] == true
end

local function canInteract(locationId)
    if isClaimed(locationId) or pending[locationId] then
        return false
    end
    return true
end

local function attemptClaim(locationId)
    local location = locationsById[locationId]
    if not location then return end

    if isClaimed(locationId) then
        if notify then
            notify.Warning(translate('already_claimed'))
        end
        return
    end

    if requireStay and (location.requireTimeSeconds or 0) > 0 and not Zones.IsReady(locationId) then
        if notify then
            notify.Warning(translate('not_ready'))
        end
        return
    end

    if pending[locationId] then return end
    pending[locationId] = true

    local ok, response = pcall(lib.callback.await, 'Partay_claimpacks:server:claim', false, locationId)
    pending[locationId] = nil

    if not ok then
        if Config.Debug then
            print(('[Partay_claimpacks] Claim callback error for %s: %s'):format(locationId, tostring(response)))
        end
        return
    end

    if not response then
        if Config.Debug then
            print(('[Partay_claimpacks] No response for claim request %s'):format(locationId))
        end
        return
    end

    if response.success then
        if location.oneTime == false then
            Zones.OnClaimed(locationId)
        else
            setClaimed(locationId, true)
        end
    elseif response.reason == 'already_claimed' then
        setClaimed(locationId, true)
    end
end

local function bootstrap()
    for _, location in ipairs(Config.Locations or {}) do
        if location.id then
            locationsById[location.id] = location
            claimed[location.id] = false
            refreshBlip(location.id)
        end
    end

    Zones.Init(Config.Locations)

    Target.init(Config.Locations, {
        canInteract = canInteract,
        onSelect = attemptClaim
    })

    Citizen.CreateThread(function()
        for _, location in ipairs(Config.Locations or {}) do
            if location.id and location.oneTime ~= false then
                local resolved = false
                local attempts = 0

                while attempts < 6 and not resolved do
                    attempts = attempts + 1
                    local ok, has, reason = pcall(lib.callback.await, 'Partay_claimpacks:server:hasClaimed', false, location.id)

                    if ok then
                        if reason == 'pending_player_data' then
                            Citizen.Wait(500)
                        else
                            if has then
                                setClaimed(location.id, true)
                            else
                                refreshBlip(location.id)
                            end
                            resolved = true
                        end
                    else
                        if Config.Debug then
                            print(('[Partay_claimpacks] hasClaimed bootstrap callback failed for %s on attempt %s'):format(location.id, tostring(attempts)))
                        end
                        Citizen.Wait(500)
                    end
                end

                if not resolved then
                    refreshBlip(location.id)
                end
            end
            Citizen.Wait(100)
        end
    end)
end

bootstrap()

RegisterNetEvent('Partay_claimpacks:client:claimed', function(locationId)
    if not locationId then return end
    local location = locationsById[locationId]
    if not location then return end

    if location.oneTime == false then
        Zones.OnClaimed(locationId)
        refreshBlip(locationId)
    else
        setClaimed(locationId, true)
    end
end)












