-- phone_charger/server/main.lua

lib.callback.register('phone_charger:server:hasItem', function(source, itemName)
    if itemName ~= 'phone_charger' then return false end

    local count = exports.ox_inventory:Search(source, 'count', itemName) or 0
    return count > 0
end)

RegisterNetEvent('phone_charger:setPowerbankDurability', function(slot, durability)
    local src = source
    slot = tonumber(slot)
    durability = tonumber(durability)

    if not slot or not durability then return end

    -- Validate the slot still contains the powerbank item
    local item = exports.ox_inventory:GetSlot(src, slot)
    if not item or item.name ~= 'powerbank_charger' then return end

    durability = math.floor(math.max(0, math.min(100, durability)))

    exports.ox_inventory:SetDurability(src, slot, durability)
    local metadata = item.metadata or {}
    metadata.charge = ('%d%%'):format(durability)
    exports.ox_inventory:SetMetadata(src, slot, metadata)
end)
