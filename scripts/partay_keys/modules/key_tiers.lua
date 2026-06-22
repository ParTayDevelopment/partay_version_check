-- [[ ParTay Keys - Key Tier Helpers ]] --

local function NormalizeText(value)
    if value == nil then return nil end
    return tostring(value):gsub('^%s*(.-)%s*$', '%1')
end

function PartayKeys_GetKeyTierConfig(tier)
    tier = NormalizeText(tier or Config.DefaultKeyTier or 'smart')
    return tier, Config.KeyTiers and Config.KeyTiers[tier] or nil
end

function PartayKeys_GetKeyItemForTier(tier)
    local normalizedTier, tierConfig = PartayKeys_GetKeyTierConfig(tier)
    tierConfig = tierConfig or Config.KeyTiers.smart
    return tierConfig and tierConfig.Item or Config.KeyItemName, normalizedTier
end

function PartayKeys_GetKeyTierForItem(itemName)
    itemName = NormalizeText(itemName)
    if not itemName or itemName == '' then return nil end

    for tier, tierConfig in pairs(Config.KeyTiers or {}) do
        if tierConfig.Item == itemName then
            return tier
        end

    end

    return nil
end

function PartayKeys_IsKeyItem(itemName)
    return PartayKeys_GetKeyTierForItem(itemName) ~= nil
end

function PartayKeys_GetAllKeyItems()
    local items = {}
    local seen = {}

    for _, tier in ipairs(Config.KeyTierOrder or {}) do
        local tierConfig = Config.KeyTiers and Config.KeyTiers[tier]
        if tierConfig and tierConfig.Item and not seen[tierConfig.Item] then
            items[#items + 1] = tierConfig.Item
            seen[tierConfig.Item] = true
        end

    end

    return items
end

function PartayKeys_GetKeyTierFromMetadata(metadata, itemName)
    local metadataTier = type(metadata) == 'table' and NormalizeText(metadata.key_tier) or nil
    if metadataTier and Config.KeyTiers and Config.KeyTiers[metadataTier] then
        return metadataTier
    end

    return PartayKeys_GetKeyTierForItem(itemName) or Config.DefaultKeyTier or 'smart'
end

function PartayKeys_KeyTierHasCapability(tier, capability)
    local _, tierConfig = PartayKeys_GetKeyTierConfig(tier)
    return tierConfig and tierConfig.Capabilities and tierConfig.Capabilities[capability] == true
end

function PartayKeys_GetKeyTierNumber(tier, group, key, fallback)
    local _, tierConfig = PartayKeys_GetKeyTierConfig(tier)
    local values = type(tierConfig) == 'table' and type(tierConfig[group]) == 'table' and tierConfig[group] or {}
    local value = tonumber(values[key])
    if value ~= nil then return value end

    return fallback
end

function PartayKeys_ResolveDefaultKeyTier(vehicleClass, model)
    local modelKey = model and tostring(model):lower() or nil
    if modelKey and Config.VehicleModelKeyTiers and Config.VehicleModelKeyTiers[modelKey] then
        return Config.VehicleModelKeyTiers[modelKey]
    end

    vehicleClass = tonumber(vehicleClass)
    if vehicleClass and Config.VehicleClassKeyTiers and Config.VehicleClassKeyTiers[vehicleClass] then
        return Config.VehicleClassKeyTiers[vehicleClass]
    end

    return Config.DefaultKeyTier or 'smart'
end
