Client = Client or {}
Client.Damage = Client.Damage or {}

local function applyWeaponDamageModifiers()
    local cfg = Config.WeaponDamage
    if not cfg or cfg.Enabled == false then return end

    for weaponHash, modifier in pairs(cfg.Modifiers or {}) do
        SetWeaponDamageModifier(weaponHash, tonumber(modifier) or 1.0)
    end

    for _, category in pairs(cfg.Categories or {}) do
        local modifier = tonumber(category.Modifier or 1.0) or 1.0
        for _, weaponHash in ipairs(category.Weapons or {}) do
            SetWeaponDamageModifier(weaponHash, modifier)
        end
    end
end

CreateThread(function()
    if not Config.WeaponDamage or Config.WeaponDamage.Enabled == false then return end

    while true do
        applyWeaponDamageModifiers()
        Wait(math.max(1, tonumber(Config.WeaponDamage.RefreshSeconds or 10) or 10) * 1000)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        applyWeaponDamageModifiers()
    end
end)
