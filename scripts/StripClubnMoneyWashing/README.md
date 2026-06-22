# Partay Illegal Club

A fully configurable pole dancing and money washing system for FiveM servers. The resource now supports multiple frameworks, flexible inventory handling, NPC dancers, skill-based tax breaks, and an enhanced tipping experience.

---

## Core Features

- **Framework auto-detection** – Works with ESX, QBCore, Qbox, or standalone. Money handlers adjust automatically, and you can force a specific framework via `Config.Framework`.
- **Inventory flexibility** – Supports `ox_inventory`, framework-native items, or plain accounts. Dirty and clean money handling are built into the resource runtime.
- **Pole management** – Configure any number of poles with coordinates, pole-specific dance areas, and NPC dancers. Each pole can inherit society accounts and expose unique targets.
- **Animation bridge** – The `Config.EmoteMenus` bridge triggers animations through rpemotes, rpemotes-reborn, dpemotes, or a custom handler before falling back to the built-in scenarios.
- **Enhanced tipping UI** – Players use an ox_lib slider to pick the tip/wash amount. The dialog calculates tax rate, withheld cash, and clean payout in real time.
- **Particle-rich tipping** – Throwing money spawns the configurable cash prop, plays the rain animation, and runs a 3-second money particle effect before cleaning up.
- **XP & leveling** – Tipping and washing award XP. Reaching higher levels unlocks better tax rates. Players can check progress with `/moneywashleaderboard`.
- **Society payouts** – Clean tax splits between the configured society and the current dancer (player or NPC). Payouts respect framework-specific boss accounts and fallback settings.
- **Escrow-friendly config** – End-user editing stays in `config/config.lua`, `config/emote_menus.lua`, and `locales/*.json`, while runtime helpers can remain locked for Tebex escrow delivery.

---

## Installation

1. Copy the resource folder into your server’s `resources` directory.
2. Ensure dependencies are present:
   - [ox_lib](https://github.com/overextended/ox_lib)
   - [ox_target](https://github.com/overextended/ox_target)
   - Optional: [ox_inventory](https://github.com/overextended/ox_inventory)
   - Your selected framework (ESX, QBCore, or Qbox) if not running standalone
3. Configure `config/config.lua` and `locales/en.json` to match your server setup.
4. Add `ensure Partay_Illegalclub` (or your folder name) to `server.cfg`.

---

## Configuration Overview

### `Config.Framework`
Controls framework selection, inventory mode, and transaction reasons. Set `mode = 'auto'` to detect ESX/QBCore/Qbox automatically.

### `Config.ClubZones`
Each club zone supports:
- `society` for shared payouts
- `poleDanceAreaDefaults` to define local dance-area behavior around each pole
- `poles` entries with:
  `coords` for pole center
  `animations` for pole-only dance options
  `danceArea` for floor-dance radius and animation overrides around that pole
  `ped` for NPC dancer spawning, wash/tip target, and animation cycling

### `Config.Tip`
Controls the tipping animation, cash prop, ptfx placement, sequence timing, and cleanup timing.

### `Config.TipOptions`
Slider defaults, min/max, steps, and UI text. Also used server-side to validate amounts.

### `Config.Levels`
XP thresholds and tax rates for each level. `Config.Experience` configures XP gain per action.

---

## Commands

- `/moneywashleaderboard` – Displays the player’s current XP, next level requirement, and active tax rate via ox_lib notifications.

---

## Targeting & Interactions

- **Poles** – Target pole props to start dancing. Animations use the selected emote menu (if available) or the defined scenario.
- **Leaning zones** – Players enter a designated zone and press `E` to tip. The ox_lib slider appears to pick a tip/wash amount.
- **NPC dancers** – If enabled per pole, an NPC becomes the tip target. Player zones are hidden automatically to prevent duplicate prompts.

---

## Money Flow

1. Client sends the chosen amount to the server.
2. Server checks dirty money first; otherwise clean tips are used.
3. Washing applies the player’s current tax rate (from the leveling system).
4. Clean payouts go back to the player, while the society and active dancer receive their configured cuts.
5. Players earn XP for both tipping clean money and washing dirty cash.

---

## Customization Tips

- Tune tip timing under `Config.Tip.releaseDelay` and `Config.Tip.sequenceEndDelay`.
- Adjust `Config.DancerCut` to control how much of the tax goes to the active dancer.
- Add new animations under `Config.Animations` and reference them in `Config.ClubZones[*].poles[*].animations`, `danceArea.animations`, or `ped.animations`.
- Per-pole dance areas let you keep pole dances and floor dances separate around the same pole.

---

## Support

For further help, configuration questions, or custom work, join the Partay Development Discord: [https://discord.gg/partaydevelopment](https://discord.gg/partaydevelopment).
