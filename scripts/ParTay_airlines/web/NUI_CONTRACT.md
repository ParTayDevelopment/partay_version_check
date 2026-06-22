# Airport Creator — NUI contract

This `web/` UI is a drop-in reskin. It does **not** change any Lua. It only
talks to `client/creator.lua` through the callbacks and messages below. If you
ever rewire the Lua, keep these names/shapes in sync.

## Resource name
`nui.js` resolves the resource from `cfx-nui-<resource>` automatically and
falls back to `ParTay_airlines`. Rename-safe.

## Lua → UI  (`SendNUIMessage`)
| action        | payload                                                        | UI effect |
|---------------|----------------------------------------------------------------|-----------|
| `open`        | `{ airports }`                                                 | show tablet, load stations |
| `close`       | `{}`                                                           | hide tablet |
| `airports`    | `{ airports }`                                                 | refresh station list |
| `pointPlaced` | `{ placement, target, point:{x,y,z,w}, saved?, airport? }`     | apply ATC/hangar point |
| `polyPlaced`  | `{ placement, points, saved?, airport? }`                     | refresh from server airport |
| `zonePlaced`  | `{ placement, zone, saved?, airport? }`                       | refresh from server airport |
| `ghostPlaced` | `{ placement, gate, saved?, airport? }`                       | refresh from server airport |

When `saved === true` the UI replaces its working copy with `airport`
(server-authoritative). When `saved` is absent (e.g. `creatorCurrentPoint`),
the point is applied locally and the strip shows **Unsaved** until you Save.

## UI → Lua  (`RegisterNUICallback`)
| callback             | payload |
|----------------------|---------|
| `creatorClose`       | `{}` |
| `creatorSaveAirport` | full airport object |
| `creatorPatchAirport`| `{ airportId, patch }` — used for `zoneDeleted` |
| `creatorSelection`   | `{ airportId, airport, tab, runwayZoneIndex, directionZoneIndex }` (sent on open / station change / tab change / runway select — drives in-world preview) |
| `creatorPlace`       | `{ mode, target, zoneKey?, runwayIndex?, index?, airportId, ... }` |
| `creatorTestAirport` | `{ airport, runwayIndex, directionIndex }` |
| `creatorCurrentPoint`| `{ target, ... }` |

### `creatorPlace` modes & targets used
- ATC point — `{ mode:'point', target:'atc' }`
- Airspace poly — `{ mode:'poly', target:'airspace', zoneKey:'controlledZone' }`
- Runway surface — `{ mode:'poly', target:'runway', index, runwayIndex }`
- Runway zone — `{ mode:'poly'|'box'|'sphere', target:'runwayZone', zoneKey, runwayIndex }`
- Airport zone — `{ mode:'poly'|'box'|'sphere', target:'zone', zoneKey }`
- Gate stand — `{ mode:'ghostGate', target:'gate', index, gateId, label, gate, aircraftModel, aircraftBoardingRadius, aircraftSpawn }`

`airportId` is attached to every placement so the server patches and returns
the full airport, matching `sendPlacementResult` in `client/creator.lua`.

## Zone keys
`taxiHold, takeoffHold, takeoffZone, approachZone, landingZone, arrivalGate`
(runway-level uses the first five; airport-level adds `arrivalGate`).

## Runway auto-build
The Runways tab has an `Auto build zones` action after a runway surface is drawn.
It generates both runway directions plus grouped `takeoffZone`, `approachZone`,
and `landingZone` entries, then persists through `creatorSaveAirport`. Taxi hold
and takeoff hold remain manual creator placements.

## Files
`index.html` (NUI page) · `style.css` · `nui.js` (bridge) · `app.js` (logic) ·
`dev.html` + `mock-airports.json` (browser preview) · this contract.

## Preview without FiveM
Open `web/dev.html` in a browser. Placement and save are stubbed; tab layout,
fields, radar scope and styling all render against the mock stations.

---

# Aircraft Radio (ATC) — NUI contract

Pilot-facing radio panel. Independent overlay in the **same** page (`#atc-root`),
shown/hidden by `client/main.lua`. Files: `atc.css`, `atc.js`, `atc_panel.png`
(the hardware bezel). Opened with the configured radio key (default **Z** / `airradio`).

## Lua → UI (`SendNUIMessage`)
| action         | payload | effect |
|----------------|---------|--------|
| `atcOpen`      | `{ facility, frequency, mode, status, onGround, emergency, clearance:{text,emergency,readbackRequired,readbackComplete}, flight }` | show panel, focus, fill header/clearance/flight |
| `atcClose`     | `{}` | hide panel (no focus change) |
| `atcLog`       | `{ who, kind:'pilot'|'atc'|'sys', text }` | append a transmission; `atc` blinks RECEIVING lamp |
| `atcClearance` | `{ text, emergency, readbackRequired, readbackComplete }` | update clearance and readback strip |
| `atcFlight`    | `{ callsign, airline, origin, dest, aircraft, gate, status, statusLabel, booked, seats, boarded }` | refresh Flight view |
| `atcStatus`    | `{ emergency }` | tint STATUS lamp |

`atcLog` is emitted automatically by `atcNotify`, `radioExchangeNotify` and
`atcOnce`, so zone-driven ATC calls appear in the panel too (toasts still fire).

## UI → Lua (`RegisterNUICallback`)
| callback      | payload | effect |
|---------------|---------|--------|
| `atcIntent`   | `{ intent }` | runs `submitAtcIntent` for the open target |
| `atcReadback` | `{}` | logs a readback of the current clearance (XMIT button) |
| `atcClose`    | `{}` | clears focus, `airspacePromptOpen=false` (ESC or Backspace) |
| `atcSavePos`  | `{ left, top, scale }` | saves the radio panel position/scale to resource KVP |

`intent` values map 1:1 to the Lua intents: `departure` (Request Taxi),
`takeoff` (Request Departure), `landing`, `transit`, `emergency`, plus
`touch_go`, `low_pass`, `flight_following` (under **More**).

## Hardware controls
`XMIT` → `atcReadback`. `ATC` → toggles ATC ⇄ Flight view (UI-only).
`RECEIVING` lamp blinks on incoming ATC. `STATUS` lamp red on emergency.

---

# Aircraft HUD - NUI contract

Pilot/front-passenger cockpit HUD. Files: `airhud.css`, `airhud.js`, `airhud_panel.png`.
It auto-shows when Lua detects the local player in an aircraft pilot/front passenger seat.

## Lua -> UI (`SendNUIMessage`)
| action | payload | effect |
|--------|---------|--------|
| `airhudShow` | `{ pos }` | show HUD and apply saved position if present |
| `airhudHide` | `{}` | hide HUD |
| `airhudData` | `{ pitch, roll, hdg, kias, gs, altMSL, altAGL, vsi, x, y, blips, waypoint }` | refresh PFD/MFD data |
| `airhudEdit` | `{ on, pos, reset }` | enter/exit/reset HUD move-resize mode |
| `atcEdit` | `{ on, pos, reset, keepOpen }` | enter/exit/reset radio move-resize mode |

## UI -> Lua (`RegisterNUICallback`)
| callback | payload | effect |
|----------|---------|--------|
| `airhudSavePos` | `{ left, top, scale }` | saves the HUD position/scale to resource KVP |
| `uiEditExit` | `{}` | leaves shared move/resize mode |
| `uiEditReset` | `{}` | clears saved HUD/radio positions and reapplies default layout |

---

# Airline Dispatch Tablet - NUI contract

Business/job-facing dispatch tablet. It opens from the configured ox_target
location in `Config.Locations.pilotTerminals`:

```lua
id = 'lsia_dispatch'
coords = vec3(-941.01, -2954.52, 13.95)
```

This tablet is separate from the aircraft radio. Dispatch is for airline job
operations; the `Z` radio remains pilot/ATC.

`Config.DispatchTablet.enabled` is enabled now that the pilot tablet UI is
installed. The same tablet can also be opened with the configured
`Config.DispatchTablet.item` ox_inventory item.

## Lua -> UI (`SendNUIMessage`)
| action | payload | effect |
|--------|---------|--------|
| `businessTabletOpen` | `{ data, terminal }` | show the dispatch tablet at the target location |
| `businessTabletClose` | `{}` | hide the dispatch tablet |
| `businessTabletData` | `{ data }` | refresh dashboard data after an action |

`Config.DispatchTablet.nuiAction` can rename the open action if a custom UI
needs a different message name. Default: `businessTabletOpen`.

## UI -> Lua (`RegisterNUICallback`)
| callback | payload | effect |
|----------|---------|--------|
| `businessTabletClose` | `{}` | closes tablet and clears NUI focus |
| `businessTabletRefresh` | `{}` | returns the latest dispatch dashboard data |
| `businessTabletCreateFlight` | `{ routeId, aircraftModel, departureMinutes }` | creates a scheduled/awaiting-pilot flight |
| `businessTabletClaimFlight` | `{ flightId }` | spawns the configured aircraft and claims the flight |
| `businessTabletSetFlightStatus` | `{ flightId, status }` | updates boarding/taxi/cancel statuses through server permission checks |
| `businessTabletCompleteFlight` | `{ flightId }` | completes the active flight and clears local guidance |

## Dashboard data

`businessTabletRefresh` and `businessTabletData.data` use the same shape:

```js
{
  airline,
  job: { name, label, grade, onduty },
  permissions: {
    createFlight,
    claimFlight,
    operateBoarding,
    cancelFlight
  },
  staffGrades,
  flights,
  routes,
  aircraft,
  airports,
  locations,
  currentFlight,
  now
}
```

The UI should use `permissions` only to hide/disable buttons. The server still
enforces all permissions.

Recommended tablet screens:
- Dashboard: active flights, status counts, current pilot flight
- Schedule: route, aircraft, departure minutes
- Claim: unclaimed flights
- My Flight: boarding/final call/close boarding/cancel/complete
- Manifest summary: seats, ticketed, boarded, completed
