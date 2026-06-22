local Zones = _G.PartayZones or {}
_G.PartayZones = Zones

local LOCALE = Config.Locale or 'en'
local requireStay = Config.RequireStay ~= false
local checkInterval = Config.CheckInterval or 250

local states = {}
local locations = {}
local notify = PartayClaimpacksNotify

local function translate(key, ...)
    local locale = Locales and Locales[LOCALE]
    local text = locale and locale[key] or key
    if select('#', ...) > 0 and type(text) == 'string' and text:find('%%') then
        return text:format(...)
    end
    return text
end

local function toVector3(value)
    if type(value) == 'vector3' then
        return value
    end
    if type(value) == 'table' then
        local x = value.x or value[1] or 0.0
        local y = value.y or value[2] or 0.0
        local z = value.z or value[3] or 0.0
        return vector3(x + 0.0, y + 0.0, z + 0.0)
    end
    return vector3(0.0, 0.0, 0.0)
end

local function ensureState(location)
    local state = states[location.id]
    if not state then
        state = {
            ready = not (requireStay and (location.requireTimeSeconds or 0) > 0),
            disabled = false
        }
        states[location.id] = state
    end
    return state
end

function Zones.Init(locationList)
    for _, location in ipairs(locationList or {}) do
        if location.id then
            locations[location.id] = location
            ensureState(location)
        end
    end

    if not requireStay then
        for _, state in pairs(states) do
            state.ready = true
        end
        return
    end

    Citizen.CreateThread(function()
        while true do
            local playerPed = PlayerPedId()
            if playerPed and playerPed ~= 0 then
                local coords = GetEntityCoords(playerPed)
                for id, location in pairs(locations) do
                    local state = ensureState(location)
                    if not state.disabled then
                        local required = (location.requireTimeSeconds or 0) > 0
                        if not required then
                            state.ready = true
                        else
                            local center = location.ped and location.ped.coords and toVector3(location.ped.coords)
                            if center then
                                local radius = location.zoneRadius or Config.DefaultZoneRadius or 3.0
                                local distance = #(coords - center)

                                if distance <= radius then
                                    if not state.inside then
                                        state.inside = true
                                        state.ready = false
                                        state.started = GetGameTimer()
                                        state.lastRemaining = math.ceil(location.requireTimeSeconds or 0)
                                        state.sent = nil
                                        if notify then
                                            local label = location.label or id
                                            local seconds = math.ceil(location.requireTimeSeconds or 0)
                                            notify.Notify(translate('stay_info', seconds, label))
                                        end
                                        TriggerEvent('Partay_claimpacks:client:stayState', id, 'enter')
                                    else
                                        if not state.ready then
                                            local elapsed = ((GetGameTimer() - (state.started or GetGameTimer())) / 1000)
                                            local targetSeconds = location.requireTimeSeconds or 0
                                            local remaining = math.max(0, targetSeconds - elapsed)
                                            if remaining <= 0 then
                                                state.ready = true
                                                state.sent = true
                                                if notify then
                                                    local label = location.label or id
                                                    notify.Success(translate('stay_completed', label))
                                                end
                                                TriggerServerEvent('Partay_claimpacks:server:stayComplete', id)
                                                TriggerEvent('Partay_claimpacks:client:stayState', id, 'ready')
                                            else
                                                local rounded = math.ceil(remaining)
                                                if rounded ~= state.lastRemaining then
                                                    state.lastRemaining = rounded
                                                    TriggerEvent('Partay_claimpacks:client:stayState', id, 'countdown', rounded)
                                                end
                                            end
                                        end
                                    end
                                else
                                    if state.inside then
                                        state.inside = false
                                        if state.sent or state.started then
                                            TriggerServerEvent('Partay_claimpacks:server:stayReset', id)
                                        end

                                        if state.started and not state.ready and notify then
                                            notify.Warning(translate('outside_zone'))
                                        end

                                        state.ready = false
                                        state.started = nil
                                        state.sent = nil
                                        state.lastRemaining = nil
                                        TriggerEvent('Partay_claimpacks:client:stayState', id, 'exit')
                                    end
                                end
                            end
                        end
                    end
                end
            end
            Citizen.Wait(checkInterval)
        end
    end)
end

function Zones.IsReady(locationId)
    local location = locations[locationId]
    if not location then return true end
    if not requireStay or (location.requireTimeSeconds or 0) <= 0 then
        return true
    end
    local state = states[locationId]
    if state and state.disabled then
        return true
    end
    return state and state.ready or false
end

function Zones.Reset(locationId)
    local state = states[locationId]
    if state then
        state.ready = false
        state.sent = nil
        state.started = nil
        state.inside = false
        state.lastRemaining = nil
        state.disabled = false
    end
end

function Zones.OnClaimed(locationId)
    local location = locations[locationId]
    if not location then return end
    local state = ensureState(location)

    if not requireStay or (location.requireTimeSeconds or 0) <= 0 then
        state.disabled = location.oneTime ~= false
        return
    end

    if location.oneTime ~= false then
        state.ready = true
        state.disabled = true
        state.inside = false
        state.started = nil
        state.sent = nil
        state.lastRemaining = nil
        return
    end

    TriggerServerEvent('Partay_claimpacks:server:stayReset', locationId)
    state.ready = false
    state.sent = nil
    state.started = GetGameTimer()
    state.lastRemaining = math.ceil(location.requireTimeSeconds or 0)
    state.inside = true
end

