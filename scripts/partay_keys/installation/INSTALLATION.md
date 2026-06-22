# ParTay Keys Installation

This file is the quick setup path. Use `README.md` for exports, integration details, compatibility notes, and feature reference.

## 1. Requirements

Required:

ox_lib
oxmysql
ox_target

Supported frameworks:

Qbox / qbx_core
QBCore / qb-core
ESX / es_extended

Supported garage/dealership integrations are configured in `config/integrations.lua`.

## 2. Install The Resource

Place the folder here:

resources/[standalone]/partay_keys

Add this to `server.cfg` after your framework and required dependencies:

ensure oxmysql
ensure ox_lib
ensure ox_target

ensure qbx_core # or qb-core / es_extended
ensure partay_keys

If another resource calls vehicle-key exports during startup, make sure `partay_keys` starts before that resource.

## 3. Disable Other Vehicle Key Resources

Do not run another full vehicle key resource beside ParTay Keys.

ParTay Keys provides compatibility aliases for common resource names:

qbx_vehiclekeys
qb-vehiclekeys
vehiclekeys
esx_vehiclelock
esx_vehiclekeys

## 4. Add Inventory Items

Open `installation/ITEMS.md` and add the item snippets for your inventory.

Copy the included item images from `installation/items/` into your inventory image folder. These are only starter inventory icons and can be replaced with any images your server prefers.

Common paths:

resources/[ox]/ox_inventory/data/items.lua
resources/[qb]/qb-core/shared/items.lua
resources/[ps]/ps-inventory/shared/items.lua
resources/[qs]/qs-inventory/shared/items.lua
resources/[qs]/qs-inventory/config/items.lua

Common image paths:

resources/[ox]/ox_inventory/web/images
resources/[qb]/qb-inventory/html/images
resources/[ps]/ps-inventory/html/images
resources/[qs]/qs-inventory/html/images

Metadata support is required for physical vehicle keys, key versions, shared keys, and cloned keys.

## 5. Review Config

Start with:

config.lua

Then review only the files you need:

config/integrations.lua     garage, dealership, compatibility shims
config/key_tiers.lua        key tiers, upgrade prices, default classes
config/theft_security.lua   lockpick, hotwire, decoder, alarm, GPS
config/ui.lua               notification provider and display defaults
config/minigames.lua        minigame provider settings
config/locksmith_business.lua owner-facing player-run locksmith settings and economy
config/logging.lua          Discord/FiveManage audit logging
modules/player_jobs.lua     advanced locksmith stock, supplier, and point defaults
modules/recipes.lua         internal fallback recipes; edit live recipes in /locksmithadmin
modules/service_peds.lua    internal service ped defaults; live blackmarket settings are in-game

Keep `Config.DebugMode = true` for first install. Turn it off after testing.

## 6. Database

No SQL file is required for a normal install.

On startup, ParTay Keys automatically verifies and creates the columns/tables it needs:

player_vehicles / owned_vehicles:
possession_id
shared_keys
key_version
has_alarm
alarm_tier
has_tracker
gps_tier
tracker_owner_id

partay_vehicle_keys
partay_vehicle_trackers
partay_vehicle_trackers.tracker_tier
partay_locksmith_stock
partay_locksmith_locations
partay_locksmith_prices
partay_locksmith_settings
partay_locksmith_appointments
partay_locksmith_stock_orders
partay_locksmith_invoices
partay_locksmith_logs

## 7. Restart And Smoke Test

After editing config and item definitions, fully restart the server.

Minimum test pass:

1. Buy a dealership vehicle and confirm a key is received.
2. Lock/unlock the vehicle with the hotkey or fob.
3. Open the key menu with /keys.
4. Install and trigger an alarm.
5. Install a GPS tracker and open the GPS tablet.
6. Run one theft flow: lockpick, hotwire, decoder.
7. If player-run locksmith is enabled, configure `Config.EnablePlayerRunLocksmith` and `Config.LocksmithSetupPermission`, then review `config/locksmith_business.lua` and `installation/JOBS.md`. Run `/locksmithadmin`, create a named location, choose `Player Owned` or `Self Service`, and finalize it after placing the required points. Player-owned shops require a framework job name and business points; self-service shops only require the NPC clerk ped. Shop owners can later use `/locksmithowner` to adjust only player-owned shops assigned to their current job. Use `Place Prop` to spawn a prop or `Use MLO Prop` to aim at and select an existing highlighted MLO prop. After a point is placed, use `Set Stand Spot` to save where players should stand before that point opens or starts its animation. Use `Add Route Point` for delivery spawns or other NPC path points when the route must avoid walls, gates, counters, or MLO clutter. Locksmith garage setup reflects the detected garage provider; provider-backed garages show the mapping to mirror in that garage resource, while standalone fallback garages expose a child vehicle spawn placement with a transparent vehicle preview for heading. Object placement uses `object_gizmo` when available and supports `Backspace`/`Escape` cancel. Use the admin setup tablet's `Universal` tab to adjust supplier contracts and stock order item prices for every location.
8. Target the placed locksmith workbench or stock point and build stock from recipe parts.
9. Restart the server and confirm garage retrieval and placed locksmith points still work.

If a test fails, enable `Config.DebugMode = true`, restart the server, and check the server console for `ERR_` prefixed logs.

## Optional: Permanent Theft Garage Patches

Permanent theft keeps the legal owner in the normal owner column, but moves active possession to `possession_id`. Some garage resources need a small patch so their garage lists, storage checks, and retrieval checks respect that active possession.

Patch only the garage resource you actually use. The patch folder also includes a short index:

- `installation/permanent-theft-patches/README.md`
- `installation/permanent-theft-patches/qbox.md`
- `installation/permanent-theft-patches/jg-advancedgarages.md`

These patches are only needed when `Config.Heist.EnablePermanentTheft = true` and you want stolen vehicles to move through garages until recovery/rekey.

## Optional: Player-Run Locksmith Job

Use `installation/JOBS.md` for QBX, QB-Core, and ESX examples for adding the default `locksmith` job and society account.
