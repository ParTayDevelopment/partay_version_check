Bridge = Bridge or {}
Bridge.Inventory = {}

local inventory = exports.ox_inventory

function Bridge.Inventory.GetItem(source, itemName)
    local slots = inventory:Search(source, 'slots', itemName)
    if not slots or not slots[1] then return nil end

    return slots[1]
end

function Bridge.Inventory.GetSlots(source, itemName)
    return inventory:Search(source, 'slots', itemName) or {}
end

function Bridge.Inventory.GetSlot(source, slot)
    return inventory:GetSlot(source, slot)
end

function Bridge.Inventory.GetItemMetadata(source, itemName)
    local item = Bridge.Inventory.GetItem(source, itemName)
    return item and (item.metadata or item.info), item
end

function Bridge.Inventory.AddItem(source, itemName, count, metadata)
    return inventory:AddItem(source, itemName, count or 1, metadata)
end

function Bridge.Inventory.RemoveItem(source, itemName, count, metadata, slot)
    return inventory:RemoveItem(source, itemName, count or 1, metadata, slot)
end

function Bridge.Inventory.RemoveTestWeapon(source, itemName, preferredSlot)
    if preferredSlot then
        local slot = inventory:GetSlot(source, preferredSlot)
        if slot and slot.name == itemName and slot.metadata and slot.metadata.weapondealer_test then
            return inventory:RemoveItem(source, itemName, 1, nil, preferredSlot)
        end
    end

    local slots = inventory:Search(source, 'slots', itemName) or {}
    for _, slot in ipairs(slots) do
        if slot.metadata and slot.metadata.weapondealer_test then
            return inventory:RemoveItem(source, itemName, 1, nil, slot.slot)
        end
    end

    return false
end

function Bridge.Inventory.CanCarry(source, itemName, count, metadata)
    return inventory:CanCarryItem(source, itemName, count or 1, metadata)
end

function Bridge.Inventory.RegisterStash(id, label, slots, weight, owner, groups, coords)
    return inventory:RegisterStash(id, label, slots, weight, owner, groups, coords)
end

function Bridge.Inventory.GetInventoryItemCount(inventoryId, itemName)
    local item = inventory:GetItem(inventoryId, itemName, nil, true)
    return tonumber(item or 0) or 0
end

function Bridge.Inventory.RemoveFromInventory(inventoryId, itemName, count, metadata, slot)
    return inventory:RemoveItem(inventoryId, itemName, count or 1, metadata, slot)
end

function Bridge.Inventory.AddToInventory(inventoryId, itemName, count, metadata)
    return inventory:AddItem(inventoryId, itemName, count or 1, metadata)
end
