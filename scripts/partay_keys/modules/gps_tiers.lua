Config.SecurityDefaults = Config.SecurityDefaults or {}
Config.SecurityDefaults.GPS = Config.SecurityDefaults.GPS or {
    TrackerItem = Config.Items.GPSTracker,
    TabletItem = Config.Items.GPSTablet,
    SignalFinderItem = Config.Items.SignalFinder,
    DefaultTier = 'basic',
    Tiers = {
        basic = {
            Label = 'Basic Tracker',
            Item = Config.Items.GPSTracker,
            PingRefresh = 30,
            RadiusSize = 250.0,
            BlipColor = 1,
            BlipAlpha = 96,
            Features = {
                TabletTracking = true,
                Notes = true,
                OfflineRecords = true,
                SignalFinderRemoval = true
            }
        },
        standard = {
            Label = 'Standard Tracker',
            Item = Config.Items.StandardGPSTracker,
            PingRefresh = 15,
            RadiusSize = 150.0,
            BlipColor = 1,
            BlipAlpha = 128,
            Features = {
                TabletTracking = true,
                Notes = true,
                OfflineRecords = true,
                SignalFinderRemoval = true,
                OnlineNotifications = true
            }
        },
        advanced = {
            Label = 'Advanced Tracker',
            Item = Config.Items.AdvancedGPSTracker,
            PingRefresh = 8,
            RadiusSize = 80.0,
            BlipColor = 5,
            BlipAlpha = 150,
            Features = {
                TabletTracking = true,
                Notes = true,
                OfflineRecords = true,
                SignalFinderRemoval = true,
                OnlineNotifications = true,
                UnauthorizedMovementAlerts = true,
                OwnerInstallProtected = true
            }
        }
    },
    InstallTime = 7000,
    PingRefresh = 15,
    RadiusSize = 150.0,
    BlipColor = 1,
    BlipAlpha = 128
}

local function GetGpsConfig()
    local defaults = Config and Config.SecurityDefaults and Config.SecurityDefaults.GPS or {}
    local gps = Config and Config.Security and Config.Security.GPS or {}

    return {
        TrackerItem = gps.TrackerItem or defaults.TrackerItem,
        TabletItem = gps.TabletItem or defaults.TabletItem,
        SignalFinderItem = gps.SignalFinderItem or defaults.SignalFinderItem,
        DefaultTier = gps.DefaultTier or defaults.DefaultTier,
        Tiers = gps.Tiers or defaults.Tiers or {},
        InstallTime = gps.InstallTime or defaults.InstallTime,
        PingRefresh = gps.PingRefresh or defaults.PingRefresh,
        RadiusSize = gps.RadiusSize or defaults.RadiusSize,
        BlipColor = gps.BlipColor or defaults.BlipColor,
        BlipAlpha = gps.BlipAlpha or defaults.BlipAlpha
    }
end

local function Trim(value)
    return tostring(value or ''):gsub('^%s*(.-)%s*$', '%1')
end

function PartayKeys_GetDefaultGpsTier()
    local gps = GetGpsConfig()
    local defaultTier = Trim(gps.DefaultTier or 'basic')
    if defaultTier == '' then defaultTier = 'basic' end
    return defaultTier
end

function PartayKeys_GetGpsTierConfig(tierName)
    local gps = GetGpsConfig()
    local tiers = gps.Tiers or {}
    local tier = Trim(tierName)
    if tier == '' then tier = PartayKeys_GetDefaultGpsTier() end

    local config = tiers[tier]
    if not config then
        tier = PartayKeys_GetDefaultGpsTier()
        config = tiers[tier]
    end

    config = config or {}
    return tier, config
end

function PartayKeys_GetGpsTierFromItem(itemName)
    itemName = Trim(itemName)
    if itemName == '' then return PartayKeys_GetDefaultGpsTier() end

    local gps = GetGpsConfig()
    for tierName, tierConfig in pairs(gps.Tiers or {}) do
        if tierConfig and tierConfig.Item == itemName then
            return tierName
        end
    end

    if itemName == gps.TrackerItem then
        return PartayKeys_GetDefaultGpsTier()
    end

    return nil
end

function PartayKeys_IsGpsTrackerItem(itemName)
    return PartayKeys_GetGpsTierFromItem(itemName) ~= nil
end

function PartayKeys_GetAllGpsTrackerItems()
    local gps = GetGpsConfig()
    local items = {}
    local seen = {}

    local function add(itemName)
        itemName = Trim(itemName)
        if itemName ~= '' and not seen[itemName] then
            seen[itemName] = true
            items[#items + 1] = itemName
        end
    end

    add(gps.TrackerItem)
    for _, tierConfig in pairs(gps.Tiers or {}) do
        if tierConfig then add(tierConfig.Item) end
    end

    return items
end

function PartayKeys_GpsTierHasFeature(tierName, featureName)
    local _, tierConfig = PartayKeys_GetGpsTierConfig(tierName)
    local features = tierConfig.Features or {}
    return features[featureName] == true
end

function PartayKeys_GetGpsTierNumber(tierName, key, fallback)
    local gps = GetGpsConfig()
    local _, tierConfig = PartayKeys_GetGpsTierConfig(tierName)
    local value = tonumber(tierConfig[key])
    if value ~= nil then return value end

    value = tonumber(gps[key])
    if value ~= nil then return value end

    return fallback
end

function PartayKeys_GetGpsTrackerItem()
    return GetGpsConfig().TrackerItem
end

function PartayKeys_GetGpsTabletItem()
    return GetGpsConfig().TabletItem
end

function PartayKeys_GetSignalFinderItem()
    return GetGpsConfig().SignalFinderItem
end

function PartayKeys_GetGpsInstallTime()
    return tonumber(GetGpsConfig().InstallTime) or 7000
end

function PartayKeys_GetGpsDefaultNumber(key, fallback)
    local value = tonumber(GetGpsConfig()[key])
    if value ~= nil then return value end
    return fallback
end
