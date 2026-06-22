Restricted Zones (PolyZone + ox_lib + ox_inventory)

## Features

- Auto-detects ESX (`es_extended`), QBCore (`qb-core`), or Qbox (`qbx-core`). Falls back to standalone (items-only).
- Server-authoritative access checks via `ox_lib` callback (prevents client spoofing).
- PolyZone polygons with `minZ`/`maxZ`, entry points, job allowlist, item requirements, and optional item consumption.
- In-game Zone Builder using `ox_lib` with movement-friendly hotkeys and clipboard export.
- Localized notifications/UI via `ox_lib` with bundled locales (`en`, `es`, `fr`, `ar`).

## Requirements

- PolyZone
- ox_lib
- ox_inventory
- Optional (for job checks): `es_extended` or `qb-core`/`qbx-core`

Dependencies are declared in `fxmanifest.lua` and should be started before this resource.

## Installation

1) Place this resource in your server resources folder.
2) Ensure dependency order in `server.cfg` (example):
```
ensure ox_lib
ensure ox_inventory
ensure PolyZone
ensure ParTay_RestrictedZones
```

3) Configure zones in `config.lua` (see below), then restart the resource.

## Framework Auto-Detection

- ESX: Detected when `es_extended` is started. Listens to `esx:playerLoaded` and `esx:setJob` for updates.
- QB/Qbox: Detected when `qb-core` or `qbx-core` is started. Listens to `QBCore:Client:OnPlayerLoaded` and `QBCore:Client:OnJobUpdate`.
- Standalone: If none are running, only item gating applies (job rules are ignored).

You can force a framework in `Config.Framework = 'esx' | 'qb' | 'qbox' | 'standalone' | 'auto'`.

## Configuration (`config.lua`)

- `Config.Framework`: `'auto' | 'esx' | 'qb' | 'qbox' | 'standalone'` (auto prefers ESX, then QB/Qbox).
- `Config.Debug`: Show PolyZone outlines while configuring.
- `Config.DebugAccess`: Print access decisions to F8.
- `Config.MinusOneZForEntries`: Nudge Z down 1.0 when placing at entry on denial.
- `Config.FreezeOnReject` / `Config.FreezeTime`: Briefly freeze on denial.
- `Config.WristBandTime`: Seconds of grace after item-based admission before re-checking.
- `Config.RequireItemEvenWithJob`: Require item even when job is allowed.
- `Config.BuilderAutoCloseOnExport`: Close overlay after exporting from hotkey.
- `Config.Locale`: `'en' | 'es' | 'fr' | 'ar'` (see `locales/*.json`).
- `Config.Notify(msg, type)`: Notification adapter (defaults to `ox_lib:notify`).

### Zone definition

```lua
Config.Zones = {
  ["My Club"] = {
    entries = {
      vector4(123.0, -456.0, 78.9, 180.0),
    },
    points = {
      vector2(120.0, -460.0),
      vector2(130.0, -460.0),
      vector2(130.0, -450.0),
      vector2(120.0, -450.0),
    },
    minZ = 77.9,
    maxZ = 79.9,
    jobs = { "police", "ambulance" }, -- optional
    items = { "club_ticket", "id_card" }, -- optional
    removeItem = true, -- optional
  },
}
```

Notes:
- If a zone has both `jobs` and `items`, the server admits by job OR item. Set `Config.RequireItemEvenWithJob = true` to require an item even for allowed jobs.
- Item labels in notifications come from `ox_inventory:Items()`; unknown items show their name.

## Commands (Builder)

- `/rz` — Toggle movement-friendly builder overlay (name is configurable via `Config.BuilderCommand`).
- `/rzmenu` — Open detailed menu for name/jobs/items/minZ/maxZ.

Access control (`Config.BuilderAccess`):
- `ace`: ACE string. If set, players with this ACE may use the builder.
- `jobs`: Map of job rules: `true` (any grade), number (min numeric grade), or `{ min = N, grades = {"boss"} }`.

Grant ACE example (if you set `ace = "restrictedzones.builder"`):
```
add_ace group.admin restrictedzones.builder allow
```

Hotkeys while overlay is active:
- `E`: add polygon point (XY)
- `G`: add entry (XYZ + heading)
- `↑/↓`: maxZ+/minZ- (hold SHIFT for faster)
- `←`: toggle item consumption
- `→`: export to clipboard (closes overlay if configured)
- `Backspace`: close overlay (reopen with `/rz`)

Export copies a Lua snippet you can paste into `Config.Zones` in `config.lua`.

## Server Authority & Events

- Access is decided server-side via `lib.callback`:
  - Client awaits: `resourceName .. ':server:CheckAccess'`
  - Server registers: `lib.callback.register(resourceName .. ':server:CheckAccess', ...)`
- On success by item, the server optionally consumes one item (`removeItem = true`) and grants a temporary wristband (grace) so quick re-entry does not re-check items.
- Deprecated no-op event kept for compatibility: `resourceName .. ':server:RemoveItem'`.

## Locales

- Files in `locales/*.json` (bundled: `en`, `es`, `fr`, `ar`).
- Set `Config.Locale` to switch language.
- You can extend or translate strings by adding another JSON file and referencing it in `fxmanifest.lua` (already uses `locales/*.json`).

## Troubleshooting

- I can’t enter even with the right job:
  - Ensure your framework is running and detected (client console shows detected framework). Job names must match your framework’s job name exactly.

- Items don’t work:
  - Ensure the item exists in `ox_inventory` and is present in the player’s inventory. Check `removeItem` if you expect consumption.

- Teleport puts me inside the polygon:
  - Adjust `entries` positions or set `Config.MinusOneZForEntries = true` (default). Ensure your polygon and entry are not overlapping.

- Builder doesn’t open:
  - Verify `Config.BuilderAccess` rules (ACE and/or jobs). In standalone mode, only ACE can grant builder access.

## Changelog

- Initialize guard AI state tables on client to avoid nil reference errors during cleanup/tick.
- Security peds are not exported by the builder in this version (feature reserved for custom use); the AI loop is safe to leave enabled.



