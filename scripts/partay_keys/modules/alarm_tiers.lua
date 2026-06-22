PartayKeys_AlarmTiers = PartayKeys_AlarmTiers or {}

Config.SecurityDefaults = Config.SecurityDefaults or {}
Config.SecurityDefaults.Alarm = Config.SecurityDefaults.Alarm or {
    Item = Config.Items.CarAlarm,
    DefaultTier = 'standard',
    Tiers = {
        basic = {
            Label = 'Basic Alarm',
            Item = Config.Items.BasicCarAlarm,
            Duration = 20,
            Cooldown = 90,
            DamageThreshold = 8.0,
            Features = {
                DamageAlarm = true,
                FailedHeistAlarm = true,
                FobPanic = true
            }
        },
        standard = {
            Label = 'Standard Alarm',
            Item = Config.Items.CarAlarm,
            Duration = 30,
            Cooldown = 60,
            DamageThreshold = 0.1,
            Features = {
                DamageAlarm = true,
                FailedHeistAlarm = true,
                FobPanic = true,
                PoliceAlert = true
            }
        },
        advanced = {
            Label = 'Advanced Alarm',
            Item = Config.Items.AdvancedCarAlarm,
            Duration = 45,
            Cooldown = 45,
            DamageThreshold = 0.1,
            Features = {
                DamageAlarm = true,
                FailedHeistAlarm = true,
                FobPanic = true,
                PoliceAlert = true,
                FailedHeistVoiceWarning = true,
                OwnerTamperNotifications = true,
                RepeatedAttemptEscalation = true,
                SmartNotifications = true
            }
        }
    },
    InstallTime = 5000,
    Duration = 30,
    Cooldown = 60,
    DamageThreshold = 0.1
}

local function GetAlarmConfig()
    local defaults = Config and Config.SecurityDefaults and Config.SecurityDefaults.Alarm or {}
    local alarm = Config and Config.Security and Config.Security.Alarm or {}

    return {
        Item = alarm.Item or defaults.Item,
        DefaultTier = alarm.DefaultTier or defaults.DefaultTier,
        Tiers = alarm.Tiers or defaults.Tiers or {},
        InstallTime = alarm.InstallTime or defaults.InstallTime,
        Duration = alarm.Duration or defaults.Duration,
        Cooldown = alarm.Cooldown or defaults.Cooldown,
        DamageThreshold = alarm.DamageThreshold or defaults.DamageThreshold
    }
end

local function Trim(value)
    return tostring(value or ''):gsub('^%s*(.-)%s*$', '%1')
end

function PartayKeys_GetDefaultAlarmTier()
    local alarm = GetAlarmConfig()
    local defaultTier = Trim(alarm.DefaultTier or 'standard')
    if defaultTier == '' then defaultTier = 'standard' end
    return defaultTier
end

function PartayKeys_GetAlarmTierConfig(tierName)
    local alarm = GetAlarmConfig()
    local tiers = alarm.Tiers or {}
    local tier = Trim(tierName)
    if tier == '' then tier = PartayKeys_GetDefaultAlarmTier() end

    local config = tiers[tier]
    if not config then
        tier = PartayKeys_GetDefaultAlarmTier()
        config = tiers[tier]
    end

    config = config or {}
    return tier, config
end

function PartayKeys_GetAlarmTierFromItem(itemName)
    itemName = Trim(itemName)
    if itemName == '' then return PartayKeys_GetDefaultAlarmTier() end

    local alarm = GetAlarmConfig()
    for tierName, tierConfig in pairs(alarm.Tiers or {}) do
        if tierConfig and tierConfig.Item == itemName then
            return tierName
        end
    end

    if itemName == alarm.Item then
        return PartayKeys_GetDefaultAlarmTier()
    end

    return nil
end

function PartayKeys_IsAlarmItem(itemName)
    return PartayKeys_GetAlarmTierFromItem(itemName) ~= nil
end

function PartayKeys_GetAllAlarmItems()
    local alarm = GetAlarmConfig()
    local items = {}
    local seen = {}

    local function add(itemName)
        itemName = Trim(itemName)
        if itemName ~= '' and not seen[itemName] then
            seen[itemName] = true
            items[#items + 1] = itemName
        end
    end

    add(alarm.Item)
    for _, tierConfig in pairs(alarm.Tiers or {}) do
        if tierConfig then add(tierConfig.Item) end
    end

    return items
end

function PartayKeys_GetAlarmItemForTier(tierName)
    local resolvedTier, tierConfig = PartayKeys_GetAlarmTierConfig(tierName)
    return tierConfig.Item or PartayKeys_GetAlarmItem(), resolvedTier, tierConfig
end

function PartayKeys_AlarmTierHasFeature(tierName, featureName)
    local _, tierConfig = PartayKeys_GetAlarmTierConfig(tierName)
    local features = tierConfig.Features or {}
    return features[featureName] == true
end

function PartayKeys_GetAlarmTierNumber(tierName, key, fallback)
    local alarm = GetAlarmConfig()
    local _, tierConfig = PartayKeys_GetAlarmTierConfig(tierName)
    local value = tonumber(tierConfig[key])
    if value ~= nil then return value end

    value = tonumber(alarm[key])
    if value ~= nil then return value end

    return fallback
end

function PartayKeys_GetAlarmItem()
    return GetAlarmConfig().Item
end

function PartayKeys_GetAlarmInstallTime()
    return tonumber(GetAlarmConfig().InstallTime) or 5000
end
