# starter_zone

FiveM starter-zone clearance system for:
- qbx_core
- ox_lib
- ox_inventory
- cs_license

## Install

1. Put `starter_zone` in your resources folder.
2. Add to `server.cfg` after dependencies:

```cfg
ensure ox_lib
ensure qbx_core
ensure ox_inventory
ensure cs_license
ensure starter_zone
```

3. Edit `shared/config.lua`:
- zone coords
- bank amount
- playtime minutes
- bike ride distance and approved bike models
- starter kit items
- starter vehicle pickup spawn, blip, and wasabi_carlock key settings
- allowed jobs and their NUI display text/stats
- greeter NPC model, location, and auto-open distances
- unreleased-player starter blip settings
- framework admin permissions
- admin starter-clearance bypass toggle
- cs_license ID and driver license item names
- ID replacement fee/account

## Player command

```txt
/starter
```

This opens the `html/index.html` FiveM NUI terminal. The client script sends live checklist, starter item, job, bank, playtime, and character-name data into the UI with `SendNUIMessage`.

Unreleased players also get a waving greeter NPC from `Config.GreeterNpc`. When they come within `autoOpenDistance`, the same starter NUI opens automatically. If they walk past `autoCloseDistance`, the NUI closes only if it was opened by the greeter. Fully released players do not see the greeter.

Unreleased players also get a map blip from `Config.StarterBlip` so they can find the starter desk while `/starter` is still available.

Starter item images use the standard ox_inventory NUI path:

```txt
nui://ox_inventory/web/images/{item}.png
```

Starter pack quantities count against the configured max. For example, choosing 3 bandages uses 3 of the available starter item slots and gives 3 bandages total.

Starter essentials use gender-aware profiles in `Config.StarterKit.profiles`. Each profile can have its own `budget`, `maxChoices`, item list, and vehicle list. The script checks Qbox `charinfo.gender` first, then falls back to `illenium-appearance` `playerskins` data when needed.

Each item has a `cost` and `maxQuantity`. Optional starter vehicles are configured per profile and are registered into `jg-advancedgarages` using the `player_vehicles` table. Vehicles count toward the starter slot limit through `countsAsChoices`.

When a player chooses a starter vehicle, `Config.StarterVehiclePickup` controls where it spawns, how far the script searches for a clear nearby spawn point, the vehicle blip/route, starting fuel, and the `wasabi_carlock` key handoff. Starter vehicles default to 25% fuel and call `rcore_fuel` when it is running. The vehicle is registered first, then marked out of the garage only after the client successfully spawns it. The blip stays on the vehicle until the player enters it as driver.

Profiles can also define a one-time `bonus`. If enabled, the server rolls the bonus item during the starter pack claim, grants it through ox_inventory, and returns the selected item to the NUI for the reveal animation.

## Admin commands

```txt
/starterstatus [id]
/starterrelease [id]
/starterreset [id]
```

Admin commands use framework permissions from `Config.AdminPermissions` in `shared/config.lua`.
Default allowed groups are `admin` and `god`.

If `Config.AdminBypassStarterClearance` is enabled, players with those same framework permissions can leave the starter zone even if their checklist is incomplete. This bypass does not mark starter metadata as released and does not hide the greeter NPC or starter blip, so staff can still test onboarding.

## Starter jobs

Starter job selection is one-time during onboarding. The NUI shows a confirmation warning before locking the job. After a job is selected, other starter jobs are disabled and future job changes must happen through your normal Job Center flow.

Each allowed starter job can define `starterItems` in `Config.AllowedStarterJobs`. These are granted once when the starter job is selected, after ox_inventory capacity checks.

## Bike ride requirement

The checklist requires new citizens to ride an approved bike for the configured distance:

```lua
Config.BikeRide.milesRequired = 10.0
Config.BikeRide.vehicles = {
    'bmx',
    'cruiser',
    'fixter',
    'scorcher',
    'tribike',
    'tribike2',
    'tribike3'
}
```

Progress is stored in the existing starter metadata as `bikeRideDistance`. The client only submits batched distance while the player is driving an approved configured bike, and the server re-validates the current vehicle/model, starter-zone location, update interval, and server-side movement before saving progress.

## Legacy job completion hook

The old starter-shift export is still available so existing job scripts do not break, but it is no longer part of the default clearance checklist:

```lua
exports['starter_zone']:CompleteStarterShift(source, 'miner')
```

## Checklist

- Identity Established
- Register Official ID
- Choose Starter Essentials
- Choose a Starter Job
- Ride an approved bike for the configured distance
- Save configured bank amount
- Stay active for configured playtime


## Official ID behavior

The first time a player registers their official ID during onboarding, it is free and issues both `id_card` and `driver_license` through `cs_license`. The driver license expires after 30 days by default:

```lua
Config.License.driverLicenseItem = 'driver_license'
Config.License.driverLicenseExpireDays = 30
Config.License.giveDriverLicenseWithId = true
```

After the `id_card` checklist task is complete, selecting the ID option again issues replacement documents and charges the configured fee:

```lua
Config.License.replacementFee = 250
Config.License.replacementAccount = 'bank'
```
