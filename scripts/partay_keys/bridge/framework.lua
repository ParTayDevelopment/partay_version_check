Bridge = Bridge or {}
local FwType = 'standalone'
local InvType = 'standalone'
local unpack = table.unpack
local warnedMetadata = {}

local function CallExport(resource, exportName, ...)
    if GetResourceState(resource) ~= 'started' then return nil end

    local args = {...}
    local ok, result = pcall(function()
        return exports[resource][exportName](exports[resource], unpack(args))
    end)

    if ok then return result end

    ok, result = pcall(function()
        return exports[resource][exportName](unpack(args))
    end)

    return ok and result or nil
end

local function DetectFramework()
    if GetResourceState('qbx_core') == 'started' then
        FwType = 'qbx'
        QBCore = CallExport('qbx_core', 'GetCoreObject')
    elseif GetResourceState('qbx-core') == 'started' then
        FwType = 'qbx'
        QBCore = CallExport('qbx-core', 'GetCoreObject')
    elseif GetResourceState('qb-core') == 'started' then
        FwType = 'qb'
        QBCore = CallExport('qb-core', 'GetCoreObject')
    elseif GetResourceState('es_extended') == 'started' then
        FwType = 'esx'
        ESX = CallExport('es_extended', 'getSharedObject')
    else
        FwType = 'standalone'
    end

    return FwType
end

local function DetectInventory()
    if GetResourceState('ox_inventory') == 'started' then
        InvType = 'ox'
    elseif GetResourceState('qs-inventory') == 'started' then
        InvType = 'qs'
    elseif GetResourceState('qb-inventory') == 'started' or GetResourceState('ps-inventory') == 'started' then
        InvType = 'qb'
    else
        InvType = 'standalone'
    end

    return InvType
end

local function WarnMetadata(message)
    if not Config or not Config.DebugMode or warnedMetadata[message] then return end
    warnedMetadata[message] = true
    print(('^5[ParTay Keys Debug]^3 Metadata Warning: %s^0'):format(message))
end

function Bridge.WarnMetadata(message)
    WarnMetadata(message)
end

DetectFramework()
DetectInventory()

function Bridge.GetFramework()
    if FwType == 'standalone' then DetectFramework() end
    return FwType
end

function Bridge.GetInventory()
    DetectInventory()
    return InvType
end

function Bridge.GetItemDefinitions()
    local inventory = Bridge.GetInventory()

    if inventory == 'ox' then
        local ok, items = pcall(function()
            return exports.ox_inventory:Items()
        end)
        if ok and type(items) == 'table' then return items end
    end

    local framework = Bridge.GetFramework()
    if framework == 'qbx' then
        if not QBCore or not QBCore.Shared then
            QBCore = CallExport('qbx_core', 'GetCoreObject') or CallExport('qbx-core', 'GetCoreObject')
        end
        if QBCore and QBCore.Shared and type(QBCore.Shared.Items) == 'table' then
            return QBCore.Shared.Items
        end
    elseif framework == 'qb' then
        if not QBCore or not QBCore.Shared then
            QBCore = CallExport('qb-core', 'GetCoreObject')
        end
        if QBCore and QBCore.Shared and type(QBCore.Shared.Items) == 'table' then
            return QBCore.Shared.Items
        end
    elseif framework == 'esx' then
        if not ESX or type(ESX.Items) ~= 'table' then
            ESX = CallExport('es_extended', 'getSharedObject')
        end
        if ESX and type(ESX.Items) == 'table' then
            return ESX.Items
        end
    end

    return nil
end

function Bridge.ItemExists(itemName)
    itemName = tostring(itemName or ''):gsub('^%s*(.-)%s*$', '%1')
    if itemName == '' then return false, true end

    local definitions = Bridge.GetItemDefinitions()
    if type(definitions) ~= 'table' then return true, false end

    if definitions[itemName] then return true, true end

    local lowered = itemName:lower()
    if definitions[lowered] then return true, true end

    return false, true
end

function Bridge.InventorySupportsMetadata()
    local inventory = Bridge.GetInventory()
    return inventory == 'ox' or inventory == 'qb' or inventory == 'qs'
end

-- [[ Server-Only Bridge Functions ]] --
if not IsDuplicityVersion() then return end

function Bridge.GetPlayer(source)
    local framework = Bridge.GetFramework()
    if framework == 'esx' then
        return ESX.GetPlayerFromId(source)
    elseif framework == 'qbx' then
        local player = CallExport('qbx_core', 'GetPlayer', source) or CallExport('qbx-core', 'GetPlayer', source)
        if player then return player end

        if not QBCore or not QBCore.Functions then
            QBCore = CallExport('qbx_core', 'GetCoreObject') or CallExport('qbx-core', 'GetCoreObject')
        end
        if QBCore and QBCore.Functions and QBCore.Functions.GetPlayer then
            return QBCore.Functions.GetPlayer(source)
        end
    elseif framework == 'qb' then
        if not QBCore or not QBCore.Functions then
            QBCore = CallExport('qb-core', 'GetCoreObject')
        end
        if QBCore and QBCore.Functions and QBCore.Functions.GetPlayer then
            return QBCore.Functions.GetPlayer(source)
        end
    end
    return nil
end

function Bridge.GetCitizenID(source)
    local Player = Bridge.GetPlayer(source)
    if not Player then return nil end
    local framework = Bridge.GetFramework()
    if framework == 'esx' then
        return Player.identifier
    elseif framework == 'qb' or framework == 'qbx' then
        return Player.PlayerData and Player.PlayerData.citizenid or Player.Data and Player.Data.citizenid or Player.citizenid
    end
    return nil
end

function Bridge.GetCharacterName(source)
    local Player = Bridge.GetPlayer(source)
    if not Player then return GetPlayerName(source) end

    local framework = Bridge.GetFramework()
    if framework == 'esx' then
        if Player.getName then return Player.getName() end
        local firstName = Player.get and Player.get('firstName')
        local lastName = Player.get and Player.get('lastName')
        if firstName or lastName then
            return (('%s %s'):format(firstName or '', lastName or '')):gsub('^%s*(.-)%s*$', '%1')
        end
    elseif framework == 'qb' or framework == 'qbx' then
        local playerData = Player.PlayerData or Player.Data or Player
        local charinfo = playerData and playerData.charinfo
        if charinfo then
            local firstName = charinfo.firstname or charinfo.firstName
            local lastName = charinfo.lastname or charinfo.lastName
            if firstName or lastName then
                return (('%s %s'):format(firstName or '', lastName or '')):gsub('^%s*(.-)%s*$', '%1')
            end
        end
        if playerData and playerData.name then return playerData.name end
    end

    return GetPlayerName(source)
end

function Bridge.GetPlayerJob(source)
    local Player = Bridge.GetPlayer(source)
    if not Player then return nil end

    local framework = Bridge.GetFramework()
    if framework == 'esx' then
        local job = Player.getJob and Player.getJob() or Player.job
        if not job then return nil end
        local grade = job.grade
        local gradeLevel = type(grade) == 'table' and (grade.level or grade.grade) or grade
        local gradeName = type(grade) == 'table' and grade.name or job.grade_name or job.gradeName
        return {
            name = job.name,
            label = job.label,
            grade = grade,
            gradeLevel = tonumber(gradeLevel),
            gradeName = gradeName,
            isboss = job.isboss == true or job.boss == true,
            onduty = job.onduty ~= false
        }
    elseif framework == 'qb' or framework == 'qbx' then
        local playerData = Player.PlayerData or Player.Data or Player
        local job = playerData and playerData.job
        if not job then return nil end
        local grade = job.grade
        local gradeLevel = type(grade) == 'table' and (grade.level or grade.grade) or grade
        local gradeName = type(grade) == 'table' and grade.name or job.grade_name or job.gradeName
        return {
            name = job.name,
            label = job.label,
            grade = grade,
            gradeLevel = tonumber(gradeLevel),
            gradeName = gradeName,
            isboss = job.isboss == true or (type(grade) == 'table' and grade.isboss == true),
            onduty = job.onduty ~= false
        }
    end

    return nil
end

function Bridge.SetPlayerJob(source, jobName, grade)
    local Player = Bridge.GetPlayer(source)
    if not Player or not jobName then return false end

    grade = tonumber(grade) or 0
    local framework = Bridge.GetFramework()
    if framework == 'esx' then
        if Player.setJob then
            local ok = pcall(Player.setJob, Player, jobName, grade)
            if ok then return true end
        end
    elseif framework == 'qb' or framework == 'qbx' then
        if Player.Functions and Player.Functions.SetJob then
            local ok = pcall(Player.Functions.SetJob, jobName, grade)
            if ok then return true end
            ok = pcall(Player.Functions.SetJob, Player.Functions, jobName, grade)
            if ok then return true end
        end

        local resource = framework == 'qbx' and 'qbx_core' or 'qb-core'
        local ok = pcall(function()
            exports[resource]:SetJob(source, jobName, grade)
        end)
        if ok then return true end
    end

    return false
end

function Bridge.SetPlayerDuty(source, duty)
    local Player = Bridge.GetPlayer(source)
    if not Player then return false end

    duty = duty == true
    local framework = Bridge.GetFramework()

    if framework == 'qb' or framework == 'qbx' then
        if Player.Functions and Player.Functions.SetJobDuty then
            local ok = pcall(Player.Functions.SetJobDuty, duty)
            if ok then return true end
            ok = pcall(Player.Functions.SetJobDuty, Player.Functions, duty)
            if ok then return true end
        end

        if framework == 'qbx' then
            for _, resource in ipairs({ 'qbx_core', 'qbx-core' }) do
                if GetResourceState(resource) == 'started' then
                    local ok = pcall(function() exports[resource]:SetJobDuty(source, duty) end)
                    if ok then return true end
                    ok = pcall(function() exports[resource]:SetDuty(source, duty) end)
                    if ok then return true end
                end
            end
        end
    elseif framework == 'esx' then
        if Player.setDuty then
            local ok = pcall(Player.setDuty, Player, duty)
            if ok then return true end
        end
    end

    return false
end

function Bridge.AddSocietyMoney(account, amount)
    account = tostring(account or '')
    amount = math.floor(tonumber(amount) or 0)
    if account == '' or amount <= 0 then return false end

    if GetResourceState('qbx_management') == 'started' then
        local ok = pcall(function() exports.qbx_management:AddMoney(account, amount) end)
        if ok then return true end
        ok = pcall(function() exports.qbx_management:AddAccountMoney(account, amount) end)
        if ok then return true end
    end

    if GetResourceState('qb-management') == 'started' then
        local ok = pcall(function() exports['qb-management']:AddMoney(account, amount) end)
        if ok then return true end
        ok = pcall(function() exports['qb-management']:AddAccountMoney(account, amount) end)
        if ok then return true end
    end

    if GetResourceState('qb-banking') == 'started' then
        local ok = pcall(function() exports['qb-banking']:AddMoney(account, amount, 'partay_keys locksmith invoice') end)
        if ok then return true end
        ok = pcall(function() exports['qb-banking']:AddAccountMoney(account, amount) end)
        if ok then return true end
    end

    if GetResourceState('esx_society') == 'started' then
        local societyAccount = account:find('society_') == 1 and account or ('society_%s'):format(account)
        local deposited = false
        TriggerEvent('esx_addonaccount:getSharedAccount', societyAccount, function(sharedAccount)
            if sharedAccount and sharedAccount.addMoney then
                sharedAccount.addMoney(amount)
                deposited = true
            end
        end)
        if deposited then return true end
    end

    return false
end

function Bridge.RemoveSocietyMoney(account, amount)
    account = tostring(account or '')
    amount = math.floor(tonumber(amount) or 0)
    if account == '' or amount <= 0 then return false end

    if GetResourceState('qbx_management') == 'started' then
        local ok = pcall(function() exports.qbx_management:RemoveMoney(account, amount) end)
        if ok then return true end
        ok = pcall(function() exports.qbx_management:RemoveAccountMoney(account, amount) end)
        if ok then return true end
    end

    if GetResourceState('qb-management') == 'started' then
        local ok = pcall(function() exports['qb-management']:RemoveMoney(account, amount) end)
        if ok then return true end
        ok = pcall(function() exports['qb-management']:RemoveAccountMoney(account, amount) end)
        if ok then return true end
    end

    if GetResourceState('qb-banking') == 'started' then
        local ok = pcall(function() exports['qb-banking']:RemoveMoney(account, amount, 'partay_keys locksmith payroll') end)
        if ok then return true end
        ok = pcall(function() exports['qb-banking']:RemoveAccountMoney(account, amount) end)
        if ok then return true end
    end

    if GetResourceState('esx_society') == 'started' then
        local societyAccount = account:find('society_') == 1 and account or ('society_%s'):format(account)
        local removed = false
        TriggerEvent('esx_addonaccount:getSharedAccount', societyAccount, function(sharedAccount)
            if sharedAccount and sharedAccount.removeMoney then
                sharedAccount.removeMoney(amount)
                removed = true
            end
        end)
        if removed then return true end
    end

    return false
end

function Bridge.GetSocietyMoney(account)
    account = tostring(account or '')
    if account == '' then return nil end

    if GetResourceState('qbx_management') == 'started' then
        local ok, value = pcall(function() return exports.qbx_management:GetAccount(account) end)
        if ok and type(value) == 'table' then return tonumber(value.balance or value.amount or value.money or value.funds) end
        if ok and tonumber(value) then return tonumber(value) end
        ok, value = pcall(function() return exports.qbx_management:GetMoney(account) end)
        if ok and tonumber(value) then return tonumber(value) end
    end

    if GetResourceState('qb-management') == 'started' then
        local ok, value = pcall(function() return exports['qb-management']:GetAccount(account) end)
        if ok and tonumber(value) then return tonumber(value) end
        if ok and type(value) == 'table' then return tonumber(value.balance or value.amount or value.money or value.funds) end
        ok, value = pcall(function() return exports['qb-management']:GetMoney(account) end)
        if ok and tonumber(value) then return tonumber(value) end
    end

    if GetResourceState('qb-banking') == 'started' then
        local ok, value = pcall(function() return exports['qb-banking']:GetAccountBalance(account) end)
        if ok and tonumber(value) then return tonumber(value) end
        ok, value = pcall(function() return exports['qb-banking']:GetAccount(account) end)
        if ok and type(value) == 'table' then return tonumber(value.balance or value.amount or value.money or value.funds) end
    end

    if GetResourceState('esx_society') == 'started' then
        local societyAccount = account:find('society_') == 1 and account or ('society_%s'):format(account)
        local balance = nil
        TriggerEvent('esx_addonaccount:getSharedAccount', societyAccount, function(sharedAccount)
            if sharedAccount then balance = tonumber(sharedAccount.money or sharedAccount.balance) end
        end)
        return balance
    end

    return nil
end

function Bridge.CountOnlineJobs(jobs, requireDuty)
    local function normalizeJob(value)
        return tostring(value or ''):lower():gsub('^%s*(.-)%s*$', '%1')
    end

    local jobLookup = {}
    for _, jobName in ipairs(jobs or {}) do
        if jobName and jobName ~= '' then
            jobLookup[jobName] = true
            jobLookup[normalizeJob(jobName)] = true
        end
    end

    local framework = Bridge.GetFramework()
    local nativeCount = 0

    if framework == 'qb' or framework == 'qbx' then
        if not QBCore or not QBCore.Functions then
            QBCore = CallExport(framework == 'qbx' and 'qbx_core' or 'qb-core', 'GetCoreObject')
                or CallExport(framework == 'qbx' and 'qbx-core' or 'qb-core', 'GetCoreObject')
        end

        if QBCore and QBCore.Functions then
            for jobName in pairs(jobLookup) do
                if requireDuty ~= false and QBCore.Functions.GetDutyCount then
                    local ok, amount = pcall(QBCore.Functions.GetDutyCount, jobName)
                    nativeCount = nativeCount + (ok and tonumber(amount) or 0)
                elseif requireDuty ~= false and QBCore.Functions.GetPlayersOnDuty then
                    local ok, _players, amount = pcall(QBCore.Functions.GetPlayersOnDuty, jobName)
                    nativeCount = nativeCount + (ok and tonumber(amount) or 0)
                end
            end

            if nativeCount > 0 then return nativeCount end
        end
    elseif framework == 'esx' and ESX and ESX.GetNumPlayers then
        for jobName in pairs(jobLookup) do
            local ok, amount = pcall(ESX.GetNumPlayers, 'job', jobName)
            nativeCount = nativeCount + (ok and tonumber(amount) or 0)
        end

        if nativeCount > 0 then return nativeCount end
    end

    local count = 0
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local job = src and Bridge.GetPlayerJob(src)
        if job and (jobLookup[normalizeJob(job.name)] or jobLookup[normalizeJob(job.label)]) and (requireDuty == false or job.onduty ~= false) then
            count = count + 1
        end
    end

    return count
end

local function IsInventoryCurrency(currency)
    if currency ~= 'black_money' then return false end

    local framework = Bridge.GetFramework()
    local inventory = Bridge.GetInventory()
    if framework == 'esx' then
        return Config.Heist and Config.Heist.ESXBlackMoneyAsItem == true and (inventory == 'ox' or inventory == 'qb')
    end

    return inventory == 'ox' or inventory == 'qb'
end

local function GetInventoryCurrencyCount(source, currency)
    local count = 0
    for _, item in pairs(Bridge.GetInventoryItems(source)) do
        local itemName = item.name or item.item
        if itemName == currency then
            count = count + (tonumber(item.count or item.amount or item.quantity) or 0)
        end
    end
    return count
end

function Bridge.HasCurrency(source, currency, amount)
    local Player = Bridge.GetPlayer(source)
    if not Player then return false end

    local framework = Bridge.GetFramework()
    if framework == 'esx' then
        if IsInventoryCurrency(currency) then
            return GetInventoryCurrencyCount(source, currency) >= amount
        end

        if currency == 'cash' or currency == 'money' then
            return Player.getMoney() >= amount
        end
        local account = Player.getAccount(currency)
        return account and account.money and account.money >= amount
    elseif framework == 'qb' or framework == 'qbx' then
        if IsInventoryCurrency(currency) then
            return GetInventoryCurrencyCount(source, currency) >= amount
        end

        if framework == 'qbx' then
            local money = CallExport('qbx_core', 'GetMoney', source, currency) or CallExport('qbx-core', 'GetMoney', source, currency)
            return tonumber(money) and tonumber(money) >= amount
        end

        if not Player.Functions or not Player.Functions.GetMoney then return false end
        local money = Player.Functions.GetMoney(currency)
        return tonumber(money) and tonumber(money) >= amount
    end
    return false
end

function Bridge.RemoveCurrency(source, currency, amount)
    local Player = Bridge.GetPlayer(source)
    if not Player then return false end

    local framework = Bridge.GetFramework()
    if framework == 'esx' then
        if IsInventoryCurrency(currency) then
            return Bridge.RemoveInventoryItem(source, currency, amount)
        end

        if currency == 'cash' or currency == 'money' then
            Player.removeMoney(amount)
        else
            Player.removeAccountMoney(currency, amount)
        end
        return true
    elseif framework == 'qb' or framework == 'qbx' then
        if IsInventoryCurrency(currency) then
            return Bridge.RemoveInventoryItem(source, currency, amount)
        end

        if framework == 'qbx' then
            return CallExport('qbx_core', 'RemoveMoney', source, currency, amount, 'partay_keys') == true
                or CallExport('qbx-core', 'RemoveMoney', source, currency, amount, 'partay_keys') == true
        end

        if not Player.Functions or not Player.Functions.RemoveMoney then return false end
        Player.Functions.RemoveMoney(currency, amount, 'partay_keys')
        return true
    end
    return false
end

function Bridge.AddCurrency(source, currency, amount)
    local Player = Bridge.GetPlayer(source)
    if not Player then return false end

    local framework = Bridge.GetFramework()
    if framework == 'esx' then
        if IsInventoryCurrency(currency) then
            return Bridge.AddInventoryItem(source, currency, amount)
        end

        if currency == 'cash' or currency == 'money' then
            Player.addMoney(amount)
        else
            Player.addAccountMoney(currency, amount)
        end
        return true
    elseif framework == 'qb' or framework == 'qbx' then
        if IsInventoryCurrency(currency) then
            return Bridge.AddInventoryItem(source, currency, amount)
        end

        if framework == 'qbx' then
            return CallExport('qbx_core', 'AddMoney', source, currency, amount, 'partay_keys') == true
                or CallExport('qbx-core', 'AddMoney', source, currency, amount, 'partay_keys') == true
        end

        if not Player.Functions or not Player.Functions.AddMoney then return false end
        Player.Functions.AddMoney(currency, amount, 'partay_keys')
        return true
    end
    return false
end

function Bridge.GetInventoryItems(source)
    local inventory = Bridge.GetInventory()
    if inventory == 'ox' then
        local ok, items = pcall(function() return exports.ox_inventory:GetInventoryItems(source) end)
        return (ok and items) or {}
    elseif inventory == 'qb' then
        local Player = Bridge.GetPlayer(source)
        if Player and Player.Functions and Player.Functions.GetItems then
            local ok, items = pcall(function() return Player.Functions.GetItems() end)
            return (ok and items) or {}
        end
    elseif inventory == 'qs' then
        local ok, items = pcall(function() return exports['qs-inventory']:getItems(source) end)
        return (ok and items) or {}
    end
    return {}
end

function Bridge.HasInventoryItem(source, itemName, amount)
    amount = amount or 1
    local items = Bridge.GetInventoryItems(source)

    for _, item in pairs(items) do
        local name = item.name or item.item
        if name == itemName then
            local count = item.count or item.amount or item.quantity or 1
            if count >= amount then
                return true
            end
        end
    end

    return false
end

function Bridge.HasVehicleKey(source, plate, possession_id)
    if not plate and not possession_id then return false end
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1') or plate
    local items = Bridge.GetInventoryItems(source)
    for _, item in pairs(items) do
        local itemName = item.name or item.item
        if PartayKeys_IsKeyItem(itemName) then
            local metadata = item.metadata or item.info
            if metadata then
                local metadataPlate = metadata.plate and metadata.plate:gsub('^%s*(.-)%s*$', '%1') or metadata.plate
                if plate and metadataPlate == plate then
                    return true
                end
                if possession_id and metadata.possession_id == possession_id then
                    return true
                end
            else
                WarnMetadata(('Vehicle key item "%s" has no metadata. Vehicle key actions require metadata-capable inventory/items.'):format(tostring(itemName)))
            end
        end
    end
    return false
end

local function HasVehicleKeyVersion(source, plate, possession_id, key_version)
    if not plate then return false end
    plate = plate:gsub('^%s*(.-)%s*$', '%1')
    local items = Bridge.GetInventoryItems(source)
    for _, item in pairs(items) do
        local itemName = item.name or item.item
        if PartayKeys_IsKeyItem(itemName) then
            local metadata = item.metadata or item.info
            local metadataPlate = metadata and metadata.plate and metadata.plate:gsub('^%s*(.-)%s*$', '%1') or metadata and metadata.plate
            if metadata and metadataPlate == plate then
                local matchesVersion = tonumber(metadata.key_version) == tonumber(key_version)
                if matchesVersion then
                    return true
                end
            elseif not metadata then
                WarnMetadata(('Vehicle key item "%s" has no metadata. Duplicate/current-key checks may not work for this inventory item.'):format(tostring(itemName)))
            end
        end
    end
    return false
end

function Bridge.AddInventoryItem(source, itemName, amount, metadata)
    local inventory = Bridge.GetInventory()
    if inventory == 'ox' then
        local ok, result = pcall(function()
            return exports.ox_inventory:AddItem(source, itemName, amount, metadata)
        end)
        if not ok then
            WarnMetadata(('Unable to add item "%s" through ox_inventory: %s'):format(tostring(itemName), tostring(result)))
        end
        return ok and result ~= false
    elseif inventory == 'qb' then
        local Player = Bridge.GetPlayer(source)
        if Player and Player.Functions and Player.Functions.AddItem then
            local ok, result = pcall(function()
                return Player.Functions.AddItem(itemName, amount, false, metadata)
            end)
            if not ok then
                WarnMetadata(('Unable to add item "%s" through qb inventory: %s'):format(tostring(itemName), tostring(result)))
            end
            return ok and result ~= false
        else
            WarnMetadata(('Unable to add item "%s"; qb inventory player AddItem was unavailable.'):format(tostring(itemName)))
        end
    elseif inventory == 'qs' then
        local ok, result = pcall(function() return exports['qs-inventory']:AddItem(source, itemName, amount, metadata) end)
        if not ok then
            WarnMetadata(('Unable to add item "%s" through qs-inventory: %s'):format(tostring(itemName), tostring(result)))
        end
        return ok and result ~= false
    else
        if metadata then
            WarnMetadata(('Inventory "%s" does not support metadata item grants. Item "%s" was not added.'):format(tostring(inventory), tostring(itemName)))
        end
    end

    return false
end

function Bridge.RemoveInventoryItem(source, itemName, amount, metadata, slot)
    amount = amount or 1

    local inventory = Bridge.GetInventory()
    if inventory == 'ox' then
        local ok, result = pcall(function()
            return exports.ox_inventory:RemoveItem(source, itemName, amount, metadata, slot)
        end)
        if not ok then
            WarnMetadata(('Unable to remove item "%s" through ox_inventory: %s'):format(tostring(itemName), tostring(result)))
        end
        return ok and result == true
    elseif inventory == 'qb' then
        local Player = Bridge.GetPlayer(source)
        if Player and Player.Functions and Player.Functions.RemoveItem then
            local ok, result = pcall(function()
                return Player.Functions.RemoveItem(itemName, amount, slot or false)
            end)
            if not ok then
                WarnMetadata(('Unable to remove item "%s" through qb inventory: %s'):format(tostring(itemName), tostring(result)))
            end
            return ok and result == true
        end
    elseif inventory == 'qs' then
        local ok, result = pcall(function()
            return exports['qs-inventory']:RemoveItem(source, itemName, amount, slot, metadata)
        end)
        if not ok then
            WarnMetadata(('Unable to remove item "%s" through qs-inventory: %s'):format(tostring(itemName), tostring(result)))
        end
        return ok and result ~= false
    end

    return false
end

function Bridge.GeneratePlate()
    local framework = Bridge.GetFramework()
    if framework == 'qb' or framework == 'qbx' then
        if QBCore and QBCore.Shared and QBCore.Shared.RandomInt and QBCore.Shared.RandomStr then
            local plate = QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(3)
            return string.upper(plate)
        end
    elseif framework == 'esx' then
        local math_random = math.random
        return string.upper(string.format("%02d%s%03d", math_random(10,99), string.char(math_random(97,122), math_random(97,122), math_random(97,122)), math_random(100,999)))
    end
    return "ADMIN"..math.random(100,999)
end

local function ResolveVehicleLabel(vehicle)
    if type(vehicle) == 'table' then
        return vehicle.label or vehicle.displayName or vehicle.name or vehicle.brand or vehicle.model or vehicle.vehicle
    end

    if not vehicle or vehicle == '' then return 'Unknown Vehicle' end

    local text = tostring(vehicle)
    local hash = tonumber(text)

    if Bridge.GetFramework() == 'qbx' then
        if hash then
            local ok, vehicleData = pcall(function()
                return exports.qbx_core:GetVehiclesByHash(hash)
            end)
            if ok and type(vehicleData) == 'table' then
                return vehicleData.name or vehicleData.label or vehicleData.model or text
            end
        else
            local ok, vehicleData = pcall(function()
                return exports.qbx_core:GetVehiclesByName(string.lower(text))
            end)
            if ok and type(vehicleData) == 'table' then
                return vehicleData.name or vehicleData.label or vehicleData.model or text
            end
        end
    end

    if QBCore and QBCore.Shared and QBCore.Shared.Vehicles then
        local vehicleData = QBCore.Shared.Vehicles[string.lower(text)]
        if vehicleData then
            return vehicleData.name or vehicleData.label or vehicleData.model or text
        end
    end

    return text
end

-- Agnostic Inventory Metadata Injection
function Bridge.GiveVehicleKey(source, plate, brandName, key_version, possession_id, extraMetadata)
    local inventory = Bridge.GetInventory()
    plate = plate and plate:gsub('^%s*(.-)%s*$', '%1') or plate
    key_version = tonumber(key_version) or 1
    local citizenId = Bridge.GetCitizenID(source)
    extraMetadata = type(extraMetadata) == 'table' and extraMetadata or {}
    local keyTier = extraMetadata.key_tier or PartayKeys_ResolveDefaultKeyTier(extraMetadata.vehicle_class, brandName)
    local keyItem = PartayKeys_GetKeyItemForTier(keyTier)
    keyTier = PartayKeys_GetKeyTierForItem(keyItem) or keyTier

    if Config.DebugMode then
        print(('[ParTay Keys Debug] GiveVehicleKey resolved plate=%s model=%s class=%s tier=%s item=%s version=%s inventory=%s'):format(
            tostring(plate),
            tostring(brandName),
            tostring(extraMetadata.vehicle_class),
            tostring(keyTier),
            tostring(keyItem),
            tostring(key_version),
            tostring(inventory)
        ))
    end

    if not Bridge.InventorySupportsMetadata() then
        WarnMetadata(('Inventory "%s" does not support vehicle key metadata. Physical key for plate "%s" was not granted; DB access record will still be maintained.'):format(tostring(inventory), tostring(plate)))
    end

    local function recordKey(metadata)
        if not IsDuplicityVersion() or not PartayKeys_RecordVehicleKey or not citizenId then return end

        local keyType = 'owner'
        if metadata.temporary_theft then
            keyType = 'temporary_theft'
        elseif metadata.stolen then
            keyType = 'stolen'
        elseif metadata.shared then
            keyType = 'shared'
        end

        PartayKeys_RecordVehicleKey({
            plate = plate,
            owner_id = metadata.original_owner_id or citizenId,
            owner_name = metadata.original_owner_name or metadata.owner_name or Bridge.GetCharacterName(source),
            holder_id = citizenId,
            holder_name = Bridge.GetCharacterName(source),
            key_type = keyType,
            key_version = key_version,
            possession_id = possession_id or citizenId,
            issued_by = metadata.shared_by,
            issued_by_name = metadata.shared_by_name,
            metadata = metadata
        })
    end

    if HasVehicleKeyVersion(source, plate, possession_id, key_version) then
        recordKey(extraMetadata)
        return false
    end

    local vehicleLabel = ResolveVehicleLabel(brandName)
    local _, tierConfig = PartayKeys_GetKeyTierConfig(keyTier)
    local keyLabel = tierConfig and tierConfig.Label or 'Vehicle Key'
    local metadata = {
        plate = plate,
        key_tier = keyTier,
        key_version = key_version,
        label = keyLabel,
        description = ("%s | Plate: %s | %s"):format(vehicleLabel, plate, keyLabel),
        brand = vehicleLabel,
        vehicle_label = vehicleLabel,
        vehicle_model = tostring(brandName or ''),
    }
    if possession_id then
        metadata.possession_id = possession_id
        metadata.current_possession_id = possession_id
    end

    for key, value in pairs(extraMetadata) do
        metadata[key] = value
    end
    metadata.key_tier = keyTier
    
    if inventory == 'ox' then
        local ok, result = pcall(function()
            return exports.ox_inventory:AddItem(source, keyItem, 1, metadata)
        end)
        if not ok then
            WarnMetadata(('Unable to grant metadata vehicle key through ox_inventory: %s'):format(tostring(result)))
        end
    elseif inventory == 'qs' then
        local ok, result = pcall(function()
            return exports['qs-inventory']:AddItem(source, keyItem, 1, nil, metadata)
        end)
        if not ok then
            WarnMetadata(('Unable to grant metadata vehicle key through qs-inventory: %s'):format(tostring(result)))
        end
    elseif inventory == 'qb' then
        local Player = Bridge.GetPlayer(source)
        if Player and Player.Functions and Player.Functions.AddItem then
            local ok, result = pcall(function()
                return Player.Functions.AddItem(keyItem, 1, false, metadata)
            end)
            if not ok then
                WarnMetadata(('Unable to grant metadata vehicle key through qb inventory: %s'):format(tostring(result)))
            end
        else
            WarnMetadata('Unable to grant metadata vehicle key; qb inventory player AddItem was unavailable.')
        end
    end

    recordKey(metadata)
    return true
end
