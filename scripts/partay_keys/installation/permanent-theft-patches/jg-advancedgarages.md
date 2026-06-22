# JG Advanced Garages Permanent Theft Patch

Use this only if you want permanent theft possession to work through `jg-advancedgarages`.

The goal is:

- `citizenid` remains the registered/legal owner.
- `possession_id` controls the active garage holder while a vehicle is permanently stolen.
- The thief can see, retrieve, and store the vehicle while they hold possession.
- The original owner is blocked from retrieving/storing the vehicle until recovery/rekey restores possession.
- Spawned vehicles sync ParTay alarm, tracker, possession, and stolen state after garage takeout.

## 1. Add Indexes

Run once in your database:

```sql
CREATE INDEX idx_partay_possession_id ON player_vehicles (possession_id);
CREATE INDEX idx_partay_possession_garage ON player_vehicles (possession_id, in_garage);
```

## 2. Patch `jg-advancedgarages/config/config-cl.lua`

Add this helper near the top of the file:

```lua
local function NotifyPartayGarageBlocked(reason, context)
  local title = context == "park" and "Storage Blocked" or "Retrieval Blocked"
  local messages = {
    stolen = context == "park"
      and "This vehicle is stolen or held by another possessor. Recover it through a locksmith before storing it."
      or "This vehicle is stolen or held by another possessor. Recover it through a locksmith before taking it out.",
    not_owner = "You are not registered to this vehicle.",
    not_registered = "This vehicle is not registered.",
    no_identifier = "Unable to verify your character identity.",
    invalid = "Invalid vehicle record."
  }
  local fallback = context == "park" and "This vehicle cannot be stored." or "This vehicle cannot be retrieved."
  local description = messages[reason] or fallback
  local duration = reason == "stolen" and 7500 or 5000

  SetTimeout(850, function()
    if lib and lib.notify then
      lib.notify({
        title = title,
        description = description,
        type = "error",
        duration = duration,
        position = "top"
      })
      return
    end

    TriggerEvent("partay_keys:client:Notify", title, description, "error", duration)
  end)
end
```

Replace the `TakeOutVehicle:config` event with:

```lua
RegisterNetEvent("jg-advancedgarages:client:TakeOutVehicle:config", function(vehicle, vehicleDbData, type)
  -- ParTay Keys: sync permanent theft/possession/security state after garage spawn.
  if GetResourceState("partay_keys") ~= "started" then return end

  local plate = vehicleDbData and (vehicleDbData.plate or vehicleDbData.vehicle_plate or vehicleDbData.vehiclePlate)
  if not plate and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    plate = GetVehicleNumberPlateText(vehicle)
  end

  if plate and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    TriggerServerEvent("partay_keys:server:SyncSpawnedVehicleState", VehToNet(vehicle), plate)
  end
end)
```

Replace the `insert-vehicle-verification` callback with:

```lua
RegisterNetEvent('jg-advancedgarages:client:insert-vehicle-verification', function(vehicle, plate, garageId, vehicleDbData, props, fuel, body, engine, damageModel, cb)
  -- ParTay Keys: block storing stolen possession vehicles for the wrong character.
  if GetResourceState("partay_keys") == "started" and plate then
    local allowed, reason = lib.callback.await("partay_keys:server:CanParkVehicle", false, plate)
    if allowed ~= true then
      cb(false)

      NotifyPartayGarageBlocked(reason, "park")
      return
    end

    cb(true)
    return
  end

  cb(true)
end)
```

Replace the `takeout-vehicle-verification` callback with:

```lua
lib.callback.register("jg-advancedgarages:client:takeout-vehicle-verification", function(plate, vehicleDbData, garageId)
  -- ParTay Keys: original owners cannot retrieve vehicles currently possessed by a thief.
  if GetResourceState("partay_keys") == "started" and plate then
    local allowed, reason = lib.callback.await("partay_keys:server:CanRetrieveVehicle", false, plate)
    if allowed ~= true then
      NotifyPartayGarageBlocked(reason, "retrieve")
      return false
    end

    return true
  end

  return true
end)
```

## 3. Patch `jg-advancedgarages/framework/main.lua`

In `Framework.Queries`, replace these query templates.

Replace `GetVehicles` with:

```lua
GetVehicles = "SELECT * FROM %s WHERE COALESCE(NULLIF(possession_id, ''), %s) = ? AND job_vehicle = 0 AND gang_vehicle = 0",
```

Replace `GetVehicle` with:

```lua
GetVehicle = "SELECT * FROM %s WHERE COALESCE(NULLIF(possession_id, ''), %s) = ? AND plate = ?",
```

Replace `StoreVehicle` with:

```lua
StoreVehicle = "UPDATE %s SET in_garage = 1, garage_id = ?, fuel = ?, body = ?, engine = ?, damage = ? WHERE COALESCE(NULLIF(possession_id, ''), %s) = ? AND plate = ?",
```

Replace `VehicleDriveOut` with:

```lua
VehicleDriveOut = "UPDATE %s SET in_garage = 0 WHERE COALESCE(NULLIF(possession_id, ''), %s) = ? AND plate = ?",
```

Replace `UpdateGarageId` with:

```lua
UpdateGarageId = "UPDATE %s SET garage_id = ? WHERE COALESCE(NULLIF(possession_id, ''), %s) = ? AND plate = ?",
```

## 4. Test Checklist

After restarting the server:

1. Owner buys and stores a normal vehicle.
2. Thief steals the vehicle permanently using the decoder.
3. Owner should not retrieve or store the stolen vehicle.
4. Thief should see, retrieve, and store the stolen vehicle.
5. Owner recovers/rekeys the vehicle.
6. Owner should regain garage access and the thief should lose it.
