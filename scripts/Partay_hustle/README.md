# Partay_hustle

Street sales with levels, rewards, hotspots, and optional dispatch integration for ESX/QBCore/QBX. Fully configurable, framework-agnostic helpers, and ox_inventory aware.

## Setup Cheatsheet (Super Simple)

Edit `config.lua`:
- Require an item: set `Config.HustleRequirement.enabled = true` and keep `items = { 'trap_phone' }` (or change to your item).
- Enforce zones: set `Config.Server.enforceZone = true` so players must be inside a zone to sell.
- Cooldowns & caps: set `Config.Server.sellCooldownMs`, `perItemCooldownMs`, and `hourlyCap.perPlayerSales`.
  - Busy servers: `sellCooldownMs = 3000-5000`, `perItemCooldownMs = 20000-30000`, `perPlayerSales = 120`.
- Optional XP: enable external XP with `Config.ExternalXP.enabled = true` (default) and leave `export.resource = 'pickle_xp'`, `method = 'AddPlayerXP'`.

That’s enough to go live. Tweak the rest later.

## Features

- Framework autodetect: ESX, QB, or QBX (override in `config.lua`).
- Item-gated selling (e.g. requires `trap_phone`).
- Zone-based selling with optional hotspot blips you can toggle.
- Inventory lockout during sales to prevent dupes (ox_inventory `invBusy`).
- Use an ox_inventory item to start selling (e.g., use `trap_phone` to trigger `/hustle`).
- Dynamic economy per item: quantity, price range, payout type (money or item), custom handoff prop.
- Per-item buyer restriction: limit which ped models can buy specific items.
- Leveling system with percent price boosts and one-time level rewards (money, item, vehicle).
- Claim system: players can claim unclaimed level rewards via the leaderboard UI.
- Leaderboard and per-player rank UI.
- External XP integration (optional) to award XP via an export or event (e.g., `pickle_xp`).
- Multiple dispatch systems: cd_dispatch, ps-dispatch, lb-tablet, or built-in basic alert.
- ox_inventory support when available; falls back to framework inventories.
- Safe SQL auto-migrations on start (optional) or manual `sql.sql`.
- Admin tools and ACE permission gate.

## Requirements

- ox_lib
- oxmysql (configure your connection string in server.cfg)
- One framework: ESX (`es_extended`) or QB/QBX (`qb-core`/`qbx_core`)
- (Recommended) ox_inventory
- (Optional) A dispatch resource if you enable that system (cd_dispatch, ps-dispatch, lb-tablet)

## Installation

1) Place this resource folder (`Partay_hustle`) in your resources.

2) Ensure order in your `server.cfg` (example):
```
ensure ox_lib
ensure oxmysql
# your framework here (es_extended / qb-core / qbx_core)
ensure ox_inventory     # optional but supported
ensure cd_dispatch      # optional
ensure ps-dispatch      # optional
ensure lb-tablet        # optional
ensure Partay_hustle
```

3) Database setup:
- By default, `Config.Database.autoMigrate = true` will create/alter the table at start.
- If you prefer manual, run `sql.sql` in your database.

4) Items:
- Make sure you actually have the items your config uses (e.g. `trap_phone`, `weed_packaged`, etc.) defined in your inventory system.
- If using ox_inventory, add items to its items list as usual.


- OX Inventory Item

['sell_phone'] = {
	label = 'Sell Phone',
	weight = 10,
	stack = false,
	close = true,
	description = 'Best way to get to the money is with this device!'
},

5) Permissions (Admin commands):
- Give your admin group access to the ACE used by this resource:
```
add_ace group.admin partay_hustle.admin allow
```

## Configuration (config.lua)

- `Config.Framework` = `'auto' | 'esx' | 'qb' | 'qbx'`
  - `auto` detects running framework at resource start.

- `Config.HustleRequirement`
  - `enabled`: require an item to sell.
  - `items`: list of acceptable items (e.g., `{'trap_phone'}`).
  - `any`: true = any one of the listed items, false = require all.

- `Config.DrugList`
  - Define each sellable item with label, quantity/price ranges, level points, handoff prop, and payout type:
  - `payout.type`: `money` or `item`
  - `payout.name`:
    - `money`: `cash`, `bank`, `black_money` (ESX) or `cash`/`bank` for QB
    - `item`: name of item to give (e.g., `markedbills`)
  - Optional per-item `dispatch` override: `{ enabled = true, chance = 35, message = '...', code = '10-66' }`
  - Optional per-item buyer denial override: `denialChance = 25` or `buyer = { denialChance = 25 }`
  - Optional per-item buyer restriction:
    - `allowedPedModels = { 'mp_m_freemode_01', 'a_f_y_hipster_02' }` — only these ped models will spawn as buyers for this item. You can use model names or hashes. Leave nil/empty to allow any from `Config.pedlist`.
  - Optional per-item seller restriction:
    - `allowedSellerModels = { 'mp_f_freemode_01' }` — only players using one of these ped models can sell this item. Accepts names or hashes. Omit to allow all player models.

- `Config.ItemPropFallback`
  - Default prop model if an item entry does not define `prop`.

- `Config.Dispatch`
  - `enabled`: master switch.
  - `system`: `'cd' | 'ps' | 'lb' | 'basic' | 'none'`
  - `chance`: % chance to alert on a sale (can be overridden per item).
  - `jobs`: who receives dispatch.
  - `title`, `message`, `code`, `includeCodeInTitle`.
  - System-specific blocks (`cd`, `ps`, `lb`) for extra options or custom event names.
  - Built-in fallback creates a basic blip for police online if no 3rd-party system is available.

- `Config.Buyer`
  - `speed`: movement speed used when buyer approaches.
  - `denialChance`: default % chance that a buyer declines and walks off (can be overridden per item).

- `Config.levels`
  - Define XP thresholds and price boosts (`percentmore`).
  - Optional one-time `reward` per level: `{ type = 'money'|'item'|'vehicle', ... }`.
  - Vehicle reward: either set `Config.Rewards.vehicle.handlerEvent` or handle the generic event `Partay_hustle:garage:giveVehicle` in your own garage script. See `server/garage_adapters.lua` for examples.

- `Config.Zones`
  - A list of coordinates with `maxRange`. You can mark some with `isHotSpot = true` to highlight priority areas.

- `Config.Commands`
  - All player/admin command names are configurable here. Defaults are listed below.

- `Config.Server`
  - `enforceZone`: require the player to be inside any `Config.Zones` to sell.
  - `sellCooldownMs`: per-player sale cooldown.
  - `perItemCooldownMs`: per-player, per-item sale cooldown to prevent macro spam.
  - `hourlyCap.perPlayerSales`: max successful sales per player per hour (0 disables).
  - `hourlyCap.serverSales`: optional server-wide sales cap per hour (0 disables).

- `Config.RateLimits` (ms)
  - `getLevelMs`, `getUnclaimedMs`, `claimRewardsMs`, `getLeaderboardMs`, `getAvailableDrugMs`.

- `Config.ExternalXP`
  - `enabled`: true/false to enable external XP awards when a sale succeeds.
  - `skill`: string identifier of the XP track in your system (default `networking`).
  - `xp`: amount to award per successful sale (default 1000).
  - `identifierMode`: how to identify the player when calling the export/event:
    - `source` (default), `citizenid` (QB/QBX), `license`, or `license2`.
  - `export`: configure an export to call (default integrates with `pickle_xp:AddPlayerXP`).
    - `resource`: export resource name (e.g., `pickle_xp` or `pickle_crafting`).
    - `method`: exported function name (e.g., `AddPlayerXP`).
    - `args`: optional function `function(source, info) -> { a1, a2, a3 }` to build custom arguments.
      - `info = { item, label, quantity, total }` about the sale.
      - If omitted, defaults to `{ identifier, skill, xp }` based on `identifierMode`.
  - `event`: alternatively, set a server event name to trigger as `TriggerEvent(event, source, info)`.

## Player Commands

- `/hustle`: Start a sale in a valid zone.
- `/traphelp`: Show help summary and common commands.
- `/traprank`: Show your rank label determined by your XP.
- `/trapleaderboard`: Show top players by XP.
  - Includes a button to claim any unclaimed level rewards.
- `/traphotspots [on|off|toggle]`: Toggle hotspot blips client-side.
- `/trapcancel`: Cancel your current hustle.

Note: The resource adds chat suggestions for player commands if your `chat` resource is running.

Server sale event: `Partay_hustle:server:sell` (client triggers this when completing the handoff)
  - Backwards-compatible alias remains for `Partay_hustle:server:banplayer`.

## Admin Commands (ACE: `partay_hustle.admin`)

- `/trapaddpoints <id> <amount>`: Add XP to a player.
- `/trapsetpoints <id> <points> [award]`: Set exact XP; pass `award` (1/true/yes) to grant any newly earned level rewards immediately.
- `/trapresetpoints <id>`: Reset a player's XP and awarded levels.
- `/trapgiveitem <id> <item> [amount]`: Give an item to a player.
- `/trapgivemoney <id> <account> <amount>`: Give money via account (`cash`, `bank`, `black_money`).
- `/traphotspots [on|off|toggle] [id|all]`: Toggle hotspot blips for a specific player or everyone.
- `/trapdebug`: Toggle server-side debug logging.

## Third-Party Integrations

- Inventory
  - Uses `ox_inventory` when started for item count, removal, and rewards.
  - Falls back to ESX/QB inventory methods if ox_inventory is not installed.

- Dispatch
  - `cd_dispatch`: via `cd_dispatch:AddNotification` per department, styled blips.
  - `ps-dispatch`: uses `exports['ps-dispatch']:CustomDispatch` or a custom event you define in config.
  - `lb-tablet`: triggers a custom event you define in config.
  - `basic`: built-in minimal alert; creates a police-radius blip client-side.

- Garage / Vehicle Rewards
  - By default triggers `Partay_hustle:garage:giveVehicle` with `(source, model, reward)`.
  - Override with `Config.Rewards.vehicle.handlerEvent` to integrate your own garage.
  - JG Advanced Garages: set `Config.Garage.system = 'jg'` (already set by default here). We provide a handler in `client/open_client.lua` that calls `exports['jg-advancedgarages']:AddOwnedVehicle(owner, model, plate, props, garage, state)`.

- External XP / pickle_xp
  - This resource can optionally award XP for each successful sale in another system.
  - Default config targets `pickle_xp` (or `pickle_crafting`) export `AddPlayerXP`.
  - Identifier is chosen based on `Config.ExternalXP.identifierMode` (`source`/`citizenid`/`license`/`license2`).
  - You can provide a custom `args` function to shape the call.
  - Example (default):
    - config.lua
      - `Config.ExternalXP = { enabled = true, skill = 'networking', xp = 1000, identifierMode = 'source', export = { resource = 'pickle_xp', method = 'AddPlayerXP', args = nil } }`
  - Or trigger a server event by setting `Config.ExternalXP.event` and leaving `export` nil.

## Tips & Notes

- Make sure your sellable items exist in your economy. If the item does not exist, players cannot sell it.
- Price boost is computed based on XP thresholds in `Config.levels`.
- Per-item `dispatch` overrides `Config.Dispatch` for that item only.
- The script prevents selling while in a vehicle, and checks zones before starting.
- Set `Config.Debug = true` for additional logging.

## Performance & Rate Limits

- Edit `config.lua` to change these. Simple rule: higher numbers = less spam.
- Server checks:
  - `Config.Server.enforceZone`: true/false, require being inside a zone to sell.
  - `Config.Server.sellCooldownMs`: time between sales per player (default 2000).
  - `Config.Server.perItemCooldownMs`: time before selling the same item again (default 15000).
  - `Config.Server.hourlyCap.perPlayerSales`: max sales per player per hour (default 120, set 0 to disable).
  - `Config.Server.hourlyCap.serverSales`: optional server-wide hourly cap (default 0 = off).
- Callback (menu/data) limits:
  - `Config.RateLimits.getLevelMs` (default 500)
  - `Config.RateLimits.getUnclaimedMs` (default 1000)
  - `Config.RateLimits.claimRewardsMs` (default 2000)
  - `Config.RateLimits.getLeaderboardMs` (default 2000)
  - `Config.RateLimits.getAvailableDrugMs` (default 300)

Quick tips for busy servers (200+ players):
- Use `sellCooldownMs` 3000–5000 and `perItemCooldownMs` 20000–30000.
- Keep `getLeaderboardMs` at least 2000.
- Set `perPlayerSales` to something that fits your economy; `0` disables.

## SQL
- Manual script provided in `sql.sql`. Auto-migrate is enabled by default.

## Support

- If something doesn’t alert, verify your chosen dispatch resource is started and matches `Config.Dispatch.system`.
- For inventory issues, confirm ox_inventory is running or your framework’s inventory is available.
- Double-check items and command names if you’ve customized `Config.Commands`.

Enjoy and hustle responsibly.
