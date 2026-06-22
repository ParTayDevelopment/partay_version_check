local resourceName = GetCurrentResourceName()
local uiOpen = false

local function openUI(message, data)
    if uiOpen then return end
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', message = message or 'Hello from '..resourceName })
    if data then
        SendNUIMessage({ action = 'setData', payload = data })
    end
end

local function closeUI()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- NUI callback from html/app.js when closed (Esc or ×)
RegisterNUICallback('close', function(_, cb)
    closeUI()
    cb(1)
end)

-- Command to open the UI manually
--[[RegisterCommand('partayui', function()
    if uiOpen then
        closeUI()
    else
        openUI('Partay Hustle UI', {
            version = GetResourceMetadata(resourceName, 'version', 0) or 'dev',
            hint = 'This is a starter NUI. Customize freely.'
        })
    end
end)]]

-- Optional key mapping (K by default)
--RegisterKeyMapping('partayui', 'Toggle Partay UI', 'keyboard', 'K')

-- Event to open UI programmatically from elsewhere
RegisterNetEvent('Partay_hustle:client:openUI', function(message, data)
    openUI(message, data)
end)

-- Event to close UI programmatically
RegisterNetEvent('Partay_hustle:client:closeUI', function()
    closeUI()
end)

