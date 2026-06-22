# ParTay Keys

ParTay Keys is a framework-agnostic vehicle access, key management, theft, alarm, GPS, garage, and dealership compatibility resource for FiveM roleplay servers.

Use `installation/INSTALLATION.md` for setup. Use this file for feature reference, exports, integrations, and operational notes.

## Core Features

- Physical vehicle keys with metadata support.
- Owner keys, shared keys, copied keys, key versions, and rekey invalidation.
- Key management menu for owned/shared key oversight.
- Key fob UI for lock, unlock, trunk, alarm, headlights, and vehicle info.
- Configurable theft flow: lockpick, hotwire, decoder, blank key, permanent possession.
- Stolen vehicle recovery and rekey flow.
- GPS trackers with tablet UI, notes, offline state, and tracker removal.
- Installable car alarms that react to additional damage while locked and engine-off.
- Locksmith and blackmarket service peds.
- Garage and dealership bridge support for Qbox, QBCore, ESX, JG, and custom integrations.
- Compatibility aliases for common vehicle key resource names.
- Optional Discord and FiveManage audit logging.

## Config Files

`config.lua`
: Main owner-facing settings, item names, commands, hotkeys, physical key behavior, shared key limits, and admin settings.

`config/integrations.lua`
: Garage/dealership provider selection, provider event lists, garage restart recovery, and advanced compatibility shims.

`config/key_tiers.lua`
: Key tier items, upgrade prices, capabilities, default tier, vehicle class defaults, and model overrides.

`config/theft_security.lua`
: Lockpick, hotwire, decoder, permanent theft, recovery, rekey, NPC lock chance, alarm, and GPS settings.

`config/ui.lua`
: Notification provider and display defaults.

`config/minigames.lua`
: Minigame provider and provider-specific settings.

`config/locksmith_business.lua`
: Owner-facing player-run locksmith settings, appointments, payroll, garage, stock behavior, and price guardrails.

`config/logging.lua`
: Optional Discord webhook and FiveManage logging.

`modules/player_jobs.lua`
: Internal locksmith setup defaults: setup point definitions, supplier contracts, stock order item presets, service tools, and service stock requirements.

`modules/recipes.lua`
: Internal fallback locksmith recipe defaults. Live workbench recipes, outputs, quantities, images, and components are managed from `/locksmithadmin`.

`modules/service_peds.lua`
: Internal service ped defaults. Live blackmarket dealer placement, currency, blip, and item prices are managed from `/locksmithadmin` Universal settings.

`modules/alarm_tiers.lua`, `modules/gps_tiers.lua`, `modules/key_tiers.lua`
: Tier definitions for alarms, GPS trackers, and vehicle key systems.

## Important Behavior

### Physical Keys

`Config.RequirePhysicalKey = true` means players must carry a valid physical key item for normal vehicle actions. This is recommended for servers using shared keys, copied keys, decoder theft, and rekeying.

When false, database ownership/shared access can grant vehicle access without requiring a physical key item. Theft can still grant temporary access, but the full physical key ecosystem is less strict.

### Theft Flow

The theft steps are siloed:

lockpick -> hotwire -> decoder

If a step is disabled or does not apply to the vehicle, the flow skips to the next required step. For example, an unlocked vehicle can skip lockpick, and a motorcycle does not need a door-based lockpick step.

When permanent theft is enabled, the decoder turns a blank key into a functional stolen key and updates `possession_id` to the thief while keeping the original owner intact. The original owner can recover and rekey the vehicle through the configured recovery flow.

### Rekeying

Rekeying increments the vehicle key version. Old physical keys are not magically removed from inventories or storage, but they become invalid because their metadata no longer matches the current key version.

### Trackers

Trackers are anonymous to the tablet user except for notes they write. The GPS tablet can track installed trackers, edit notes, forget removed tracker records, and show offline targets when the vehicle is stored or unavailable.

GPS tracker tiers are scaffolded in `modules/gps_tiers.lua`. The legacy `gps_tracker` item installs the `basic` tier by default, with standard and advanced tracker items available for locksmith shops and job stock.

### Alarms

Installed alarms can be triggered by fob action, failed theft steps, and additional damage while the vehicle is locked and the engine is off. If an alarm is already active, damage does not restart it until the active alarm stops.

Alarm tiers are scaffolded in `modules/alarm_tiers.lua`. The legacy `car_alarm` item installs the `standard` tier by default, with basic and advanced alarm items available for locksmith shops and job stock.

## Database

ParTay Keys auto-asserts its database requirements on startup.

Vehicle table columns added to `player_vehicles` or `owned_vehicles` when missing:

possession_id
shared_keys
key_version
has_alarm
alarm_tier
has_tracker
gps_tier
tracker_owner_id

Player-run locksmith business tables:

partay_locksmith_stock
partay_locksmith_locations
partay_locksmith_prices
partay_locksmith_settings
partay_locksmith_appointments
partay_locksmith_stock_orders
partay_locksmith_invoices
partay_locksmith_logs

### Locksmith MLO Setup

When player-run locksmith is enabled, authorized admins can place the business inside any MLO:

Run `/locksmithadmin` to open the full admin setup tablet. From there, create a named location, enter the job name that should operate it, place the workbench, management terminal, register, and stock point with the visible preview tool, then finalize the location. Shop owners can use `/locksmithowner` for the scoped owner setup view, which only allows them to adjust locations assigned to their current job.

Enable the player-run business with `Config.EnablePlayerRunLocksmith` in `config.lua`. Setup access is configured with `Config.LocksmithSetupPermission`; by default, it accepts `Config.AdminGroup`, `command.car`, or this dedicated ACE:

add_ace group.admin partay_keys.locksmithsetup allow

Setup points can either spawn their configured prop or use an existing MLO prop. Supported points show a `Use MLO Prop` option. That mode lets admins aim at an existing MLO prop, highlights the detected prop, and saves the target zone to that prop's position.

After placing a point, use `Set Stand Spot` to save where players should stand before that point opens or starts its animation. This is useful for MLO counters, stock shelves, workbenches, registers, and management terminals where the target prop is not exactly where the player should stand.

Use `Add Route Point` on placed points when an NPC or delivery vehicle needs a guided path through an MLO, alley, gate, or loading bay. Add route points in travel order. For supplier deliveries, add route points to the `Delivery Truck Spawn` point so the driver can follow that path toward the delivery drop-off. `Clear Route` removes the saved route for that point.

Spawned setup props and fallback peds use the built-in gizmo-style placement editor. The setup screen closes while editing, the preview follows in front of the player while they walk, and `G` toggles fixed fine-placement mode. Axis arrows and rotation rings stay visible for precision work; in fine mode, `W/A/S/D` moves the prop, `Ctrl` slows movement, `Shift` moves faster, `Enter` saves, and `Backspace` cancels without replacing the previously saved point.

The `/locksmithadmin` tablet also includes a `Universal` tab for admin-level business defaults that affect every location, including the active supplier contract and stock order item prices. Those prices still respect the min/max economy guardrails from `config/locksmith_business.lua`.

You can create multiple locations. Re-placing a point moves it, clearing a point returns that location to draft status, and finalized points persist in `partay_locksmith_locations` for owner and employee tablets.

If a location includes a locksmith garage point, also place the `Garage Vehicle Spawn` point. Standalone garage vehicles spawn there; older setups without that point fall back to the garage point plus `Garage.SpawnOffset`.

Use `installation/JOBS.md` for default QBX, QB-Core, and ESX locksmith job setup examples.

Resource tables created when missing:

partay_vehicle_keys
partay_vehicle_trackers
  tracker_tier

Old revoked key rows are cleaned up according to `Config.KeyHistoryRetentionDays`.

## Inventory Items

Use `installation/ITEMS.md` for copy-paste item definitions.

Starter item images are included in `installation/items/`. They are only inventory icons and can be replaced through your inventory resource.

ParTay Keys registers Qbox/QBCore usable item handlers automatically when `qbx_core` or `qb-core` is running. For `ox_inventory`, use the individual `server = { export = 'partay_keys.use...Item' }` snippets from `installation/ITEMS.md`.

Metadata support is required for vehicle keys and copied/cloned key behavior.

Detected metadata-capable inventory paths include `ox_inventory`, `qb-inventory`, `ps-inventory`, and `qs-inventory`.

## Commands

Default owner-configurable commands:

/keyfob       opens the key fob UI
/keys         opens key management
/givekeys     admin key assignment flow

Default keybinds:

U             lock/unlock
G             engine toggle

The lock keybind uses an internal command registered in client code. Server owners only need to configure `Config.LockHotkey`.

## Garage Integration

ParTay Keys can detect supported garage providers automatically. Custom garages should use the exports below.

Before retrieving/spawning a vehicle:

local allowed, reason = exports.partay_keys:AssertCanRetrieveVehicle(source, plate)
if not allowed then return end

Before parking/storing a vehicle:

local allowed, reason = exports.partay_keys:AssertCanParkVehicle(source, plate)
if not allowed then return end

After spawning a custom garage vehicle:

exports.partay_keys:SyncSpawnedVehicleState(netId, plate)

Garage provider helpers:

local provider = exports.partay_keys:GetGarageProvider()
local canRetrieve, reason = exports.partay_keys:CanRetrieveVehicle(source, plate)

## Dealership Integration

ParTay Keys auto-registers known purchase events for supported dealership providers.

For custom dealerships:

Config.DealershipProvider = 'custom'

Config.Integrations.Dealership.Custom.Events = {
    'your_shop:server:vehiclePurchased'
}

The purchase event payload should include the buyer/source and plate. Supported plate fields include:

plate
plateText
plate_number
plateNumber
vehicle_plate
vehiclePlate
registration
props.plate
vehicleProps.plate

Direct export:

exports.partay_keys:RegisterVehiclePurchase(source, plate, model)

Dealership helpers:

local provider = exports.partay_keys:GetDealershipProvider()
local events = exports.partay_keys:GetRegisteredDealershipEvents()
local canSell = exports.partay_keys:CanVehicleBeSold(plate)

## Public Exports

### Client Exports

exports.partay_keys:HasKeys(vehicle)
exports.partay_keys:GiveKeys(vehicleOrPlate)
exports.partay_keys:RemoveKeys()

### Server Exports

exports.partay_keys:HasKeys(source, vehicleOrPlate)
exports.partay_keys:GiveKeys(source, vehicleOrPlate, model)
exports.partay_keys:RemoveKeys(source, vehicleOrPlate)
exports.partay_keys:SetLockState(vehicleOrNetId, state)

exports.partay_keys:AdminSpawnVehicle(source, targetPlayer, model)
exports.partay_keys:RegisterVehiclePurchase(source, plate, model)
exports.partay_keys:WipeVehicleData(plate)

exports.partay_keys:CanRetrieveVehicle(source, plate)
exports.partay_keys:AssertCanRetrieveVehicle(source, plate)
exports.partay_keys:CanParkVehicle(source, plate)
exports.partay_keys:AssertCanParkVehicle(source, plate)
exports.partay_keys:SyncSpawnedVehicleState(netIdOrEntity, plate)
exports.partay_keys:GetGarageProvider()
exports.partay_keys:GetPhoneProvider()

exports.partay_keys:CanVehicleBeSold(plate)
exports.partay_keys:GetDealershipProvider()
exports.partay_keys:GetRegisteredDealershipEvents()

### Locksmith Phone Integration

Locksmith appointment, invoice, shop-order, and customer status messages can be routed through phone providers from `config/integrations.lua`.

Supported built-in providers:

`lb-phone`, `npwd`, `qs-smartphone`, `gksphone`

Custom phone resources can either set `Config.Integrations.Phone.Custom.Handler` or register a runtime handler:

```lua
exports.partay_keys:RegisterLocksmithPhoneHandler('my-phone', function(payload)
    -- payload.source, payload.citizenId, payload.title, payload.message,
    -- payload.type, payload.category, payload.metadata
    return true
end)
```

You can also send a locksmith phone message through the same bridge:

```lua
exports.partay_keys:SendLocksmithPhoneMessage(source, {
    title = 'Locksmith',
    message = 'Your order is ready.',
    metadata = { event = 'custom' }
})
```

### Item Use Exports

These are intended for inventory item definitions:

partay_keys.useKeyItem
partay_keys.useLockpickItem
partay_keys.useHotwireItem
partay_keys.useDecoderItem
partay_keys.useBlankKeyItem
partay_keys.useSaleContractItem
partay_keys.useCarAlarmItem
partay_keys.useGpsTrackerItem
partay_keys.useGpsTabletItem
partay_keys.usePartayItem

### Logging Export

exports.partay_keys:SendAuditLog(title, message, logType)

## Compatibility Aliases

ParTay Keys provides aliases for:

qbx_vehiclekeys
qb-vehiclekeys
vehiclekeys
esx_vehiclelock
esx_vehiclekeys

Supported legacy server events include common `SetOwner`, `AcquireVehicleKeys`, `AddKeys`, and `GiveVehicleKeys` patterns. Compatibility behavior is controlled in `config/integrations.lua` under `Config.Compatibility`.

Keep compatibility audit logging enabled during install so legacy callers are visible in the console.

## Notifications And Minigames

`ox_lib` is required even when another notification or minigame provider is selected, because the resource still uses ox_lib for core UI, callbacks, menus, and input dialogs.

Notification provider is set in:

Config.NotificationProvider = 'ox_lib'

Minigame provider is set in:

Config.MinigameProvider = 'ox_lib'

Provider-specific settings live in `config/ui.lua` and `config/minigames.lua`.

## Fob UI

The key fob UI is loaded from:

html/index.html
html/style.css
html/app.js
html/assets/

The fob UI uses tier-specific images:

html/assets/fob_base.png
html/assets/fob_smart.png
html/assets/fob_advanced.png
html/assets/fob_oled.png

## Operational Notes

- Fully restart the server after changing `fxmanifest.lua`, config load order, item definitions, or NUI files.
- Keep `Config.DebugMode = true` during first install and provider testing.
- Look for `ERR_` prefixed server logs when debugging critical failures.
- If keys open the fob but do not control the vehicle, check item metadata and key version.
- If dealership keys are not granted, confirm the dealership provider/event or call `RegisterVehiclePurchase`.
- If garage retrieval is blocked unexpectedly, call `AssertCanRetrieveVehicle` and inspect the returned reason.

## Basic Test Checklist

1. Purchase a dealership vehicle and confirm a physical key.
2. Lock/unlock from hotkey and fob.
3. Open /keys and view owned/shared vehicles.
4. Share a key and confirm shared key limit behavior.
5. Rekey and confirm old keys no longer work.
6. Install alarm, trigger by damage, then stop by lock/unlock.
7. Install GPS tracker, add tablet note, restart, and confirm note persists.
8. Lockpick, hotwire, decode, and recover a stolen vehicle.
9. Restart with a vehicle out and confirm garage recovery behavior.
