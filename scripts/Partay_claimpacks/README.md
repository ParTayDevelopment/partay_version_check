# Claim Pack 

This is a resource that lets players claim configurable reward packs from NPC vendors. Supports multiple RP frameworks, Discord-gated rewards, server-side cooldown enforcement, and the overextended stack.

## Features
- Framework auto-detect for ESX, QBCore, and Qbox (overrideable in `config.lua`).
- One-time or cooldown-based repeatable rewards with ox_inventory delivery.
- ox_target interaction on streamed ped entities.
- Optional restriction layers: jobs, gender, Discord roles (Badger_Discord_API or HTTP fallback).
- Role-based claim caps and robust server-side enforcement to prevent duplicate claims.
- Optional map blips per location, automatically hiding for one-time rewards once claimed.

## Requirements
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_inventory](https://github.com/overextended/ox_inventory)
- [ox_target](https://github.com/overextended/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)
- Optional Discord roles: [Badger_Discord_API](https://github.com/JaredScar/Badger_Discord_API)

## Installation
1. Drop the `Partay_claimpacks` folder into your server resources directory.
2. Ensure the dependencies above start before this resource (oxmysql must be running).
3. Add `ensure Partay_claimpacks` to your `server.cfg`.
4. Configure `config.lua` (locations, rewards, cooldowns, restrictions, etc.) to match your server.

## Configuration Highlights
- `Config.RequireStay = false` disables the stay-in-zone timer globally. Override per location with `requireTimeSeconds` if desired.
- `Config.Locations`: define each claim point (ped, target label/icon, reward table, restrictions, cooldowns, role caps).
  - `blip`: optional map blip settings (`enabled`, `sprite`, `color`, `scale`, `shortRange`, `label`). Blips for `oneTime` locations disappear after the reward is claimed and reappear only if the player can claim again.
  - `ped.animation`: optional idle animation or scenario played on the vendor ped (supports animation dict/clip or scenario names).
  - `oneTime = true` (default when omitted) limits the reward to a single claim per identifier. Set `false` to allow repeated claims governed by `cooldownSeconds`.
  - `cooldownSeconds`: seconds a player must wait before claiming again (ignored when `nil` or `0`).
  - `roleCaps`: map of Discord role IDs to maximum claim counts per location.
- `Config.PedStreaming`: control spawn/despawn distances for vendor NPCs.
- `Config.Notify`: adjust ox_lib notification defaults (position defined in `shared/notifications.lua`).
- Discord integration expects the `PARTAY_CLAIMPACKS_BOT_TOKEN` and `PARTAY_CLAIMPACKS_GUILD_ID` convars when using HTTP fallback.

Rewards accept either a single `{ name = 'item', count = 1 }` table or an array of such tables. Metadata tables are passed through to ox_inventory.




