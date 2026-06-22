local resourceName = GetCurrentResourceName()
local oxInv = exports.ox_inventory
local oxItems = oxInv:Items()

lib.locale()
if Config.Locale then pcall(function() lib.setLocale(Config.Locale) end) end

-- Framework bridge (ESX, QBCore, Qbox)
local Framework = {
    name = 'standalone',
    job = nil,
    gradeLevel = nil,
    gradeName = nil,
}

local function setJobInfo(name, level, gname)
    Framework.job = name
    Framework.gradeLevel = level
    Framework.gradeName = gname
end

-- ESX detection
local desiredFramework = (Config.Framework or 'auto'):lower()

CreateThread(function()
    if Framework.name ~= 'standalone' then return end
    if desiredFramework ~= 'auto' and desiredFramework ~= 'esx' then return end
    local esxState = GetResourceState('es_extended')
    if esxState == 'started' then
        Framework.name = 'esx'
        local ok, obj = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and obj then ESX = obj end
        -- Fallback to event legacy getter
        if not ESX then
            pcall(function()
                TriggerEvent('esx:getSharedObject', function(o) ESX = o end)
            end)
        end
        -- Initialize job
        CreateThread(function()
            while not ESX or not ESX.PlayerData do Wait(200) end
            if ESX.PlayerData.job then
                local j = ESX.PlayerData.job
                setJobInfo(j.name, j.grade or j.grade_level, j.grade_name or j.grade_label)
            end
        end)
        RegisterNetEvent('esx:playerLoaded', function(xPlayer)
            if xPlayer and xPlayer.job then
                local j = xPlayer.job
                setJobInfo(j.name, j.grade or j.grade_level, j.grade_name or j.grade_label)
            end
        end)
        RegisterNetEvent('esx:setJob', function(job)
            if job then setJobInfo(job.name, job.grade or job.grade_level, job.grade_name or job.grade_label) end
        end)
        print(('[%s] Framework detected: ESX'):format(resourceName))
        return
    elseif desiredFramework == 'esx' then
        print(('[%s] Framework forced to ESX but es_extended not started; running standalone'):format(resourceName))
    end
end)

-- QBCore / Qbox detection
CreateThread(function()
    if Framework.name ~= 'standalone' then return end
    if desiredFramework ~= 'auto' and desiredFramework ~= 'qb' and desiredFramework ~= 'qbox' then return end
    local coreName = nil
    if desiredFramework == 'qbox' then
        if GetResourceState('qbx-core') == 'started' then coreName = 'qbx-core' end
    else
        if GetResourceState('qb-core') == 'started' then coreName = 'qb-core' end
        if not coreName and GetResourceState('qbx-core') == 'started' then coreName = 'qbx-core' end
    end
    if coreName then
        Framework.name = 'qb'
        local ok, obj = pcall(function()
            return exports[coreName]:GetCoreObject()
        end)
        if ok and obj then QBCore = obj end

        CreateThread(function()
            while not QBCore do Wait(200) end
            local pdata = QBCore.Functions and QBCore.Functions.GetPlayerData and QBCore.Functions.GetPlayerData() or nil
            if pdata and pdata.job then
                local j = pdata.job
                local lvl = (j.grade and (j.grade.level or tonumber(j.grade))) or nil
                local gnm = (j.grade and (j.grade.name or tostring(j.grade))) or nil
                setJobInfo(j.name, lvl, gnm)
            end
        end)

        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
            local pdata = QBCore.Functions.GetPlayerData()
            if pdata and pdata.job then
                local j = pdata.job
                local lvl = (j.grade and (j.grade.level or tonumber(j.grade))) or nil
                local gnm = (j.grade and (j.grade.name or tostring(j.grade))) or nil
                setJobInfo(j.name, lvl, gnm)
            end
        end)
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
            if type(job) == 'table' and job.name then
                local lvl = (job.grade and (job.grade.level or tonumber(job.grade))) or nil
                local gnm = (job.grade and (job.grade.name or tostring(job.grade))) or nil
                setJobInfo(job.name, lvl, gnm)
            else
                local pdata = QBCore.Functions.GetPlayerData()
                if pdata and pdata.job then
                    local j = pdata.job
                    local lvl = (j.grade and (j.grade.level or tonumber(j.grade))) or nil
                    local gnm = (j.grade and (j.grade.name or tostring(j.grade))) or nil
                    setJobInfo(j.name, lvl, gnm)
                end
            end
        end)
        print(('[%s] Framework detected: %s'):format(resourceName, coreName))
        return
    elseif desiredFramework == 'qb' or desiredFramework == 'qbox' then
        print(('[%s] Framework forced to %s but %s not started; running standalone'):format(resourceName, desiredFramework, desiredFramework == 'qbox' and 'qbx-core' or 'qb-core/qbx-core'))
    end
end)

-- Utility: get player's job name (string|nil)
local function getPlayerJob()
    return Framework.job
end

local function getPlayerJobInfo()
    return Framework.job, Framework.gradeLevel, Framework.gradeName
end

-- Utility: build readable item list from ox_inventory definitions
local function itemLabels(itemNames)
    local labels = {}
    for _, name in pairs(itemNames) do
        local def = oxItems[name]
        labels[#labels+1] = def and def.label or name
    end
    return labels
end

-- Cleanup zones on resource stop
local zones = {}
local insideAllowed = {}

-- Security ped state tables (initialized empty to avoid nil checks)
local securityPeds = {}
local securityPedHome = {}
local securityPedState = {}
local securityPedCooldown = {}

local function dbg(msg)
    if Config.DebugAccess then
        print(('[%s] %s'):format(resourceName, tostring(msg)))
    end
end

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < 3000 do
        Wait(20)
        waited = waited + 20
    end
    return HasAnimDictLoaded(dict)
end

local function disableControlsFor(ms)
    local t = GetGameTimer() + ms
    while GetGameTimer() < t do
        Wait(0)
        -- Movement + combat
        DisableControlAction(0, 30, true)  -- MOVE_LR
        DisableControlAction(0, 31, true)  -- MOVE_UD
        DisableControlAction(0, 21, true)  -- SPRINT
        DisableControlAction(0, 22, true)  -- JUMP
        DisableControlAction(0, 24, true)  -- ATTACK
        DisableControlAction(0, 25, true)  -- AIM
        DisableControlAction(0, 140, true) -- MELEE_LIGHT
        DisableControlAction(0, 141, true) -- MELEE_HEAVY
        DisableControlAction(0, 142, true) -- MELEE_ALTERNATE
        DisableControlAction(0, 257, true) -- ATTACK2
        DisableControlAction(0, 263, true) -- MELEE_ATTACK1
        DisableControlAction(0, 264, true) -- MELEE_ATTACK2
    end
end

-- Try to have a security ped theatrically eject the player
-- Clean up zones and player state when resource stops
AddEventHandler('onResourceStop', function(res)
    if res ~= resourceName then return end
    if next(zones) then
        for _, z in pairs(zones) do z:destroy() end
    end
    zones = {}
    local player = PlayerPedId()
    DetachEntity(player, true, true)
    ClearPedTasks(player)
end)

-- Zone logic
CreateThread(function()
    for zoneName, zoneCfg in pairs(Config.Zones) do
        local zone = PolyZone:Create(zoneCfg.points, {
            name = zoneName,
            minZ = zoneCfg.minZ,
            maxZ = zoneCfg.maxZ,
            debugPoly = Config.Debug,
        })

        zone:onPlayerInOut(function(isInside)
            if not isInside then
                dbg(('Exited zone: %s'):format(zoneName))
                -- Clear sticky allow when actually leaving the zone
                insideAllowed[zoneName] = nil
                return
            end

            dbg(('Entered zone: %s'):format(zoneName))

            -- If we've already allowed this continuous stay, do nothing
            if insideAllowed[zoneName] then
                dbg('Already authorized for current stay; skipping checks')
                return
            end

            -- Ask server authoritatively if entry is allowed
            local allowed, detail = lib.callback.await(resourceName .. ':server:CheckAccess', false, zoneName)
            if allowed then
                dbg('Access granted by server')
                insideAllowed[zoneName] = true
                return
            end

            -- 3) Deny and return to nearest entry point
            local ped = PlayerPedId()
            local pedCoords = GetEntityCoords(ped)

            -- find nearest entry
            local nearest, nearestDist = nil, 999999.0
            for _, entry in pairs(zoneCfg.entries or {}) do
                local dist = #(pedCoords - vector3(entry.x, entry.y, entry.z))
                if dist < nearestDist then
                    nearest, nearestDist = entry, dist
                end
            end

            if detail and detail.type == 'item' then
                dbg('Denied: missing required item(s)')
                local itemsList = detail.items or zoneCfg.items or {}
                if type(itemsList) ~= 'table' then itemsList = { itemsList } end
                local labels = itemLabels(itemsList)
                Config.Notify(locale('entry_denied_item', table.concat(labels, ' or ')), 'error')
            else
                dbg('Denied: job not allowed')
                Config.Notify(locale('entry_denied_job'), 'error')
            end

            if nearest then
                -- Ensure target is outside polygon; if not, push outward a few meters
                local target = vector3(nearest.x, nearest.y, nearest.z - (Config.MinusOneZForEntries and 1 or 0))

                local function isInsideAt(pos)
                    if zone.isPointInside then return zone:isPointInside(pos) end
                    -- Fallback: rely on PolyZone method naming; if unavailable, assume target is fine
                    return false
                end

                if isInsideAt(target) then
                    -- compute a simple centroid of polygon for direction
                    local cx, cy = 0.0, 0.0
                    local pts = zoneCfg.points or {}
                    for _, p in ipairs(pts) do cx = cx + p.x; cy = cy + p.y end
                    local count = math.max(#pts, 1)
                    cx, cy = cx / count, cy / count
                    local dir = vector3(nearest.x - cx, nearest.y - cy, 0.0)
                    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y) + 1e-6
                    dir = vector3(dir.x / len, dir.y / len, 0.0)

                    local pushed = false
                    for step = 3, 10, 1 do -- try from 3m to 10m
                        local cand = vector3(nearest.x + dir.x * step, nearest.y + dir.y * step, target.z)
                        if not isInsideAt(cand) then
                            target = cand
                            pushed = true
                            break
                        end
                    end
                    if not pushed then
                        -- final fallback: move 5m along heading if provided
                        if nearest.w then
                            local rad = math.rad(nearest.w)
                            local dx, dy = math.cos(rad) * 5.0, math.sin(rad) * 5.0
                            local cand = vector3(nearest.x + dx, nearest.y + dy, target.z)
                            if not isInsideAt(cand) then target = cand end
                        end
                    end
                end

                -- Directly place player outside the zone
                SetEntityCoords(ped, target.x, target.y, target.z)
                if nearest.w then SetEntityHeading(ped, nearest.w) end
            end

            if Config.FreezeOnReject then
                FreezeEntityPosition(ped, true)
                Wait(Config.FreezeTime)
                FreezeEntityPosition(ped, false)
            end
        end)

        zones[zoneName] = zone
    end
end)

-- ==========================
-- In-game Zone Builder (ox_lib)
-- ==========================

local builder = {
    active = false,
    preview = nil,
    name = 'New Zone',
    points = {}, -- vector2
    entries = {}, -- vector3 or vector4
    minZ = nil,
    maxZ = nil,
    jobs = {},
    items = {},
    removeItem = false,
    peds = {}, -- retained for backward-compatibility in overlay count; not exported
    modeThread = nil,
}

local function round(n)
    return math.floor(n * 10000 + 0.5) / 10000
end

local function vec2ToString(v)
    return ('vector2(%.4f, %.4f)'):format(round(v.x), round(v.y))
end

local function vec3ToString(v)
    return ('vector3(%.4f, %.4f, %.4f)'):format(round(v.x), round(v.y), round(v.z))
end

local function vec4ToString(v)
    return ('vector4(%.4f, %.4f, %.4f, %.4f)'):format(round(v.x), round(v.y), round(v.z), round(v.w))
end

local function destroyPreview()
    if builder.preview then
        builder.preview:destroy()
        builder.preview = nil
    end
end

local function updatePreview()
    destroyPreview()
    if #builder.points >= 3 then
        builder.preview = PolyZone:Create(builder.points, {
            name = 'rz_preview',
            minZ = builder.minZ or (GetEntityCoords(PlayerPedId()).z - 1.0),
            maxZ = builder.maxZ or (GetEntityCoords(PlayerPedId()).z + 1.0),
            debugPoly = true,
        })
    end
end

local function csvToList(str)
    local list = {}
    if not str or str == '' then return list end
    for item in string.gmatch(str, '([^,]+)') do
        local s = item:gsub('^%s+', ''):gsub('%s+$', '')
        if s ~= '' then list[#list+1] = s end
    end
    return list
end

local function listToCsv(list)
    if not list or #list == 0 then return '' end
    return table.concat(list, ', ')
end

local function builderExport()
    if #builder.points < 3 then
        return nil, 'Add at least 3 polygon points.'
    end
    if not builder.minZ or not builder.maxZ then
        return nil, 'Set minZ and maxZ first.'
    end
    if builder.minZ >= builder.maxZ then
        return nil, 'minZ must be less than maxZ.'
    end

    local lines = {}
    lines[#lines+1] = ('["%s"] = {'):format(builder.name)

    -- entries
    lines[#lines+1] = '    entries = {'
    for _, e in ipairs(builder.entries) do
        if e.w then
            lines[#lines+1] = '        ' .. vec4ToString(e) .. ','
        else
            lines[#lines+1] = '        ' .. vec3ToString(e) .. ','
        end
    end
    if #builder.entries == 0 then
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        lines[#lines+1] = '        ' .. vec4ToString(vec4(coords.x, coords.y, coords.z, heading)) .. ','
    end
    lines[#lines+1] = '    },'

    -- points
    lines[#lines+1] = '    points = {'
    for _, p in ipairs(builder.points) do
        lines[#lines+1] = '        ' .. vec2ToString(p) .. ','
    end
    lines[#lines+1] = '    },'

    -- minZ / maxZ
    lines[#lines+1] = ('    minZ = %.4f,'):format(round(builder.minZ))
    lines[#lines+1] = ('    maxZ = %.4f,'):format(round(builder.maxZ))

    -- jobs
    if #builder.jobs > 0 then
        lines[#lines+1] = '    jobs = {'
        for _, j in ipairs(builder.jobs) do
            lines[#lines+1] = ('        "%s",'):format(j)
        end
        lines[#lines+1] = '    },'
    end

    -- items
    if #builder.items > 0 then
        lines[#lines+1] = '    items = {'
        for _, it in ipairs(builder.items) do
            lines[#lines+1] = ('        "%s",'):format(it)
        end
        lines[#lines+1] = '    },'
        if builder.removeItem then
            lines[#lines+1] = '    removeItem = true,'
        end
    end

    -- Note: security peds are no longer exported

    lines[#lines+1] = '}'

    return table.concat(lines, '\n')
end

local function showBuilderMenu()
    builder.active = true
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    -- Hide overlay while menu is open to avoid stuck UI
    pcall(function() lib.hideTextUI() end)
    lib.registerContext({
        id = 'rz_builder_main',
        title = locale('builder_title'),
        onExit = function()
            -- Restore overlay if still in builder mode
            if builder.active then showOverlayHint() end
        end,
        options = {
            { title = locale('builder_menu_name_title', builder.name), description = locale('builder_menu_name_desc'), arrow = true, onSelect = function()
                local input = lib.inputDialog(locale('builder_name_dialog_title'), {
                    { type = 'input', label = locale('builder_name_dialog_label'), default = builder.name, required = true }
                })
                if input and input[1] then builder.name = input[1] end
                showBuilderMenu()
            end },
            { title = locale('builder_add_point_title'), description = locale('builder_add_point_desc', pcoords.x, pcoords.y), onSelect = function()
                local v2 = vector2(pcoords.x, pcoords.y)
                builder.points[#builder.points+1] = v2
                updatePreview()
                Config.Notify(locale('notify_added_point', #builder.points), 'success')
                showBuilderMenu()
            end },
            { title = locale('builder_add_entry_title'), description = locale('builder_add_entry_desc', pcoords.x, pcoords.y, pcoords.z, GetEntityHeading(ped)), onSelect = function()
                local v4 = vector4(pcoords.x, pcoords.y, pcoords.z, GetEntityHeading(ped))
                builder.entries[#builder.entries+1] = v4
                Config.Notify(locale('notify_added_entry', #builder.entries), 'success')
                showBuilderMenu()
            end },
            { title = locale('builder_set_z_title', pcoords.z), arrow = true, onSelect = function()
                local res = lib.inputDialog(locale('builder_z_dialog_title'), {
                    { type = 'number', label = 'minZ', default = builder.minZ or (pcoords.z - 1.0), required = true },
                    { type = 'number', label = 'maxZ', default = builder.maxZ or (pcoords.z + 1.0), required = true },
                })
                if res then builder.minZ = res[1]; builder.maxZ = res[2]; updatePreview() end
                showBuilderMenu()
            end },
            { title = locale('builder_jobs_title', #builder.jobs > 0 and listToCsv(builder.jobs) or 'none'), description = locale('builder_jobs_desc'), arrow = true, onSelect = function()
                local res = lib.inputDialog(locale('builder_jobs_dialog_title'), {
                    { type = 'input', label = locale('builder_jobs_dialog_label'), default = listToCsv(builder.jobs) }
                })
                if res then builder.jobs = csvToList(res[1]) end
                showBuilderMenu()
            end },
            { title = locale('builder_items_title', #builder.items > 0 and listToCsv(builder.items) or 'none'), description = locale('builder_items_desc'), arrow = true, onSelect = function()
                local res = lib.inputDialog(locale('builder_items_dialog_title'), {
                    { type = 'input', label = locale('builder_items_dialog_label'), default = listToCsv(builder.items) }
                })
                if res then builder.items = csvToList(res[1]) end
                showBuilderMenu()
            end },
            -- Security peds removed from builder UI
            { title = locale('builder_consume_title', builder.removeItem and 'true' or 'false'), onSelect = function()
                builder.removeItem = not builder.removeItem
                showBuilderMenu()
            end },
            { title = locale('builder_undo_point'), disabled = (#builder.points == 0), onSelect = function()
                if #builder.points > 0 then table.remove(builder.points) updatePreview() end
                showBuilderMenu()
            end },
            { title = locale('builder_undo_entry'), disabled = (#builder.entries == 0), onSelect = function()
                if #builder.entries > 0 then table.remove(builder.entries) end
                showBuilderMenu()
            end },
            -- Undo ped option removed
            { title = locale('builder_clear_all_title'), description = locale('builder_clear_all_desc'), onSelect = function()
                destroyPreview()
                builder = { active = true, preview = nil, name = 'New Zone', points = {}, entries = {}, minZ = nil, maxZ = nil, jobs = {}, items = {}, removeItem = false, peds = {}, modeThread = nil }
                showBuilderMenu()
            end },
            { title = locale('builder_export_title'), description = locale('builder_export_desc'), onSelect = function()
                local txt, err = builderExport()
                if not txt then
                    Config.Notify(err, 'error')
                else
                    lib.setClipboard(txt)
                    Config.Notify(locale('notify_zone_copied'), 'success')
                end
                showBuilderMenu()
            end },
            { title = locale('builder_close'), onSelect = function() end },
        }
    })
    lib.showContext('rz_builder_main')
end

local builderCommand = (Config.BuilderCommand or 'rz')

-- Movement-friendly builder mode helpers
local stopBuilderMode -- forward declaration so references below capture this local
local function ensureZ()
    if not builder.minZ or not builder.maxZ then
        local z = GetEntityCoords(PlayerPedId()).z
        builder.minZ = builder.minZ or (z - 1.0)
        builder.maxZ = builder.maxZ or (z + 1.0)
    end
end

local function showOverlayHint()
    lib.showTextUI(locale('builder_overlay_hint', builderCommand .. 'menu', #builder.points, #builder.entries, #builder.peds, builder.minZ or 0.0, builder.maxZ or 0.0))
end

local function startBuilderMode()
    if builder.active then return end
    builder.active = true
    ensureZ()
    updatePreview()
    showOverlayHint()

    builder.modeThread = CreateThread(function()
        while builder.active do
            Wait(0)

            -- refresh hint periodically
            if (GetFrameCount() % 30) == 0 then showOverlayHint() end

            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)

            -- E: add polygon point (XY)
            if IsControlJustPressed(0, 38) then -- INPUT_PICKUP (E)
                builder.points[#builder.points+1] = vector2(pos.x, pos.y)
                updatePreview()
                Config.Notify(locale('notify_added_point', #builder.points), 'success')
            end

            -- G: add entry (XYZ + heading)
            if IsControlJustPressed(0, 47) then -- INPUT_DETONATE (G)
                builder.entries[#builder.entries+1] = vector4(pos.x, pos.y, pos.z, GetEntityHeading(ped))
                Config.Notify(locale('notify_added_entry', #builder.entries), 'success')
            end

            -- Up/Down arrows: adjust maxZ/minZ (hold SHIFT for faster)
            local step = IsControlPressed(0, 21) and 0.5 or 0.1 -- INPUT_SPRINT
            if IsControlJustPressed(0, 172) then -- INPUT_FRONTEND_UP
                builder.maxZ = (builder.maxZ or pos.z + 1.0) + step
                updatePreview()
            elseif IsControlJustPressed(0, 173) then -- INPUT_FRONTEND_DOWN
                builder.minZ = (builder.minZ or pos.z - 1.0) - step
                updatePreview()
            end

            -- Left arrow: toggle removeItem
            if IsControlJustPressed(0, 174) then -- INPUT_FRONTEND_LEFT
                builder.removeItem = not builder.removeItem
                Config.Notify(locale('notify_consumption_toggle', builder.removeItem and 'true' or 'false'), 'inform')
            end

            -- Right arrow: export to clipboard
            if IsControlJustPressed(0, 175) then -- INPUT_FRONTEND_RIGHT
                local txt, err = builderExport()
                if not txt then
                    Config.Notify(err, 'error')
                else
                    lib.setClipboard(txt)
                    Config.Notify(locale('notify_zone_copied'), 'success')
                    if Config.BuilderAutoCloseOnExport then
                        stopBuilderMode()
                        Config.Notify(locale('notify_builder_closed_menu', builderCommand), 'inform')
                    end
                end
            end

            -- Backspace: close overlay (movement mode)
            if IsControlJustPressed(0, 177) then -- INPUT_FRONTEND_CANCEL (Backspace)
                stopBuilderMode()
                Config.Notify(locale('notify_builder_closed', builderCommand, builderCommand), 'inform')
            end
        end
    end)
end

local function stopBuilderMode()
    if not builder.active then return end
    builder.active = false
    builder.modeThread = nil
    lib.hideTextUI()
end

RegisterCommand(builderCommand, function()
    -- permission check for builder
    local access = Config.BuilderAccess or {}
    local function hasAce()
        local aceName = access.ace
        if type(aceName) ~= 'string' or aceName == '' then return false end
        return IsPlayerAceAllowed(PlayerId(), aceName) or false
    end

    local function hasJobAccess()
        local rules = access.jobs
        if not rules or not next(rules) then return false end
        local jname, jlvl, jgname = getPlayerJobInfo()
        if not jname then return false end
        local rule = rules[jname]
        if not rule then return false end
        if rule == true then return true end
        if type(rule) == 'number' then
            return (type(jlvl) == 'number' and jlvl >= rule)
        end
        if type(rule) == 'table' then
            if rule.min and type(jlvl) == 'number' and jlvl >= rule.min then return true end
            if rule.grades and jgname then
                for _, g in ipairs(rule.grades) do
                    if g == jgname then return true end
                end
            end
        end
        return false
    end

    -- Always allow closing if currently active
    if builder.active then
        stopBuilderMode()
        return
    end

    if hasAce() or hasJobAccess() then
        startBuilderMode()
    else
        --Config.Notify(locale('notify_no_permission'), 'error')
    end
end, false)

-- Optional menu while in movement mode for advanced edits
RegisterCommand(builderCommand .. 'menu', function()
    -- reuse same permission gates
    local access = Config.BuilderAccess or {}
    local function hasAce()
        local aceName = access.ace
        if type(aceName) ~= 'string' or aceName == '' then return false end
        return IsPlayerAceAllowed(PlayerId(), aceName) or false
    end
    local function hasJobAccess()
        local rules = access.jobs
        if not rules or not next(rules) then return false end
        local jname, jlvl, jgname = getPlayerJobInfo()
        if not jname then return false end
        local rule = rules[jname]
        if not rule then return false end
        if rule == true then return true end
        if type(rule) == 'number' then
            return (type(jlvl) == 'number' and jlvl >= rule)
        end
        if type(rule) == 'table' then
            if rule.min and type(jlvl) == 'number' and jlvl >= rule.min then return true end
            if rule.grades and jgname then
                for _, g in ipairs(rule.grades) do
                    if g == jgname then return true end
                end
            end
        end
        return false
    end
    if hasAce() or hasJobAccess() then
        showBuilderMenu()
    else
        --Config.Notify(locale('notify_no_permission'), 'error')
    end
end, false)

-- Ensure overlay is hidden if resource stops while active
AddEventHandler('onResourceStop', function(res)
    if res ~= resourceName then return end
    pcall(function() lib.hideTextUI() end)
    -- cleanup peds
    if next(securityPeds) then
        for _, list in pairs(securityPeds) do
            for _, ped in ipairs(list) do
                if DoesEntityExist(ped) then DeleteEntity(ped) end
            end
        end
    end
    securityPedHome = {}
    securityPedState = {}
    securityPedCooldown = {}
end)

-- Drive simple guard AI: look at player and approach when close to zone entries; return to home otherwise
CreateThread(function()
    local tick = 0
    while true do
        Wait(500)
        tick = tick + 1
        if next(securityPeds) then
            local player = PlayerPedId()
            local ppos = GetEntityCoords(player)
            for zoneName, list in pairs(securityPeds) do
                local zoneCfg = Config.Zones[zoneName]
                if zoneCfg and type(list) == 'table' then
                    -- compute proximity to any entry point for activation
                    local nearEntry = false
                    local minEntryDist = 999999.0
                    if zoneCfg.entries then
                        for _, e in ipairs(zoneCfg.entries) do
                            local d = #(ppos - vector3(e.x, e.y, e.z))
                            if d < minEntryDist then minEntryDist = d end
                        end
                    end
                    if minEntryDist <= 12.0 then nearEntry = true end

                    for _, ped in ipairs(list) do
                        if DoesEntityExist(ped) then
                            local pedPos = GetEntityCoords(ped)
                            local dist = #(ppos - pedPos)

                            -- periodically make them look at player when nearby
                            if dist < 20.0 then
                                TaskLookAtEntity(ped, player, 700, 2048, 2)
                            end

                            local state = securityPedState[ped] or 'idle'
                            local cooldownUntil = securityPedCooldown[ped]
                            local onCooldown = cooldownUntil and (GetGameTimer() < cooldownUntil)
                            if nearEntry and not onCooldown and dist > 2.5 and dist < 10.0 then
                                if state ~= 'following' then
                                    ClearPedTasks(ped)
                                    TaskGoToEntity(ped, player, -1, 2.0, 1.5, 0, 0)
                                    securityPedState[ped] = 'following'
                                end
                            else
                                -- return to home if wandered
                                local home = securityPedHome[ped]
                                if home then
                                    local dh = #(vector3(home.x, home.y, home.z) - pedPos)
                                    if dh > 1.5 and (not nearEntry or dist >= 10.0) then
                                        if state ~= 'returning' then
                                            ClearPedTasks(ped)
                                            TaskGoStraightToCoord(ped, home.x, home.y, home.z, 1.5, -1, home.w or 0.0, 0.0)
                                            securityPedState[ped] = 'returning'
                                        end
                                    elseif state ~= 'idle' then
                                        ClearPedTasks(ped)
                                        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_GUARD_STAND', 0, true)
                                        if home and home.w then SetEntityHeading(ped, home.w) end
                                        securityPedState[ped] = 'idle'
                                        if onCooldown and (GetGameTimer() >= cooldownUntil) then securityPedCooldown[ped] = nil end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Keybind intentionally omitted; use the command directly.
