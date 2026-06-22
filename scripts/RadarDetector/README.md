# RadarDetector

Vehicle-installed FiveM radar detector resource for Qbox-first servers. It uses `ox_inventory` for item installation, `ox_lib` for notifications/progress-ready UX, `ox_target` for vehicle removal interaction, `oxmysql` for persistence, and accepts radar transmit events from `wk_wars2x`.

## Dependencies

- qbx_core, qb-core, es_extended, or standalone mode
- ox_lib
- ox_inventory
- ox_target
- oxmysql
- wk_wars2x for police radar signal source

## Install

1. Put this folder in your resources and name the resource folder `RadarDetector`, or update the ox_inventory item export to match the actual resource name.
2. Import `sql/radar_detector.sql`, or let the resource create the table on start.
3. Add the item from `docs/ox_inventory_item.lua` to `ox_inventory/data/items.lua`.
4. Add the snippet from `docs/wk_wars2x_integration.lua` into the wk_wars2x client file where `RADAR` is available.
5. Ensure resources start in this order:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure qbx_core
ensure wk_wars2x
ensure RadarDetector
```

## Commands

`/detector show` shows the detector display.
`/detector hide` hides the detector display.
`/detector move` lets the player drag the display and save position with ESC.
`/detector mute` toggles detector audio.
`/detector vol 1-100` changes alert volume.
`/detector remove` removes the installed detector from the current vehicle.

## Notes

- Qbox is the default framework in `config/config.lua`.
- Detectors install on any vehicle by plate unless blocked by vehicle class config.
- The server validates install/removal, item use, police radar transmitter permission, and vehicle presence.
- Installed vehicles persist in `radar_detector_vehicles` instead of modifying framework vehicle tables.
