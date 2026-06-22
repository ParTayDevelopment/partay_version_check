# ParTay Airlines

Player-driven Qbox airline and airport RP core for FiveM.

## V1 Features

- ox_lib context menus for passenger booking and pilot dispatch.
- ox_target interactions for ticket desks, pilot terminals, and boarding gates.
- ox_inventory `boarding_pass` items with flight metadata.
- oxmysql persistence for airline, flights, and tickets.
- Qbox job lock for `nolovelostairlines`.
- Real pilot requirement: flights stay `awaiting_pilot` until a staff member claims one from an aircraft.
- Pilot claim spawns the flight aircraft at the configured gate `aircraftSpawn`.
- Boarding validation by player, flight, gate, aircraft position, ticket status, and metadata.
- Passengers scan at the gate while the aircraft is parked, then auto-walk/seat into the plane.
- Zone-based ATC flow: gate boarding, taxi hold, runway hold, final check, takeoff detection, destination approach, landing, and arrival ramp deboarding.
- Aircraft radio NUI opened by the configured radio key, with ATC requests, clearance readback, transmission log, and flight status view.
- Glass cockpit HUD for aircraft pilot/front passenger seats, with PFD attitude/speed/altitude data and MFD airport/waypoint navigation.
- Movable/resizable cockpit HUD and ATC radio panels with per-player saved positions.
- FAA-style airspace volumes using 2D polygon boundaries with floor/ceiling altitude bands for tower, approach, and center control.
- Pilot payout only after passengers deboard at the destination.
- International Cayo route with passport and customs clearance requirements.

## Install

1. Place the resource in your server resources folder.
2. Add this to `server.cfg` after dependencies:

```cfg
ensure ParTay_airlines
```

3. Add this item to `ox_inventory/data/items.lua`:

```lua
['boarding_pass'] = {
    label = 'Boarding Pass',
    weight = 10,
    stack = false,
    close = true,
    description = 'Airline boarding pass with passenger and flight details.'
},

['pilot_tablet'] = {
    label = 'Pilot Tablet',
    weight = 1000,
    stack = false,
    close = true,
    description = 'Airline dispatch tablet for managing pilot flights.'
},
```

4. Restart `ox_inventory` after adding the item.
5. `install.sql` is included. By default, `Config.Database.autoCreateTables = true` also creates the needed tables on resource start.

## International Flights

The sample `lsia_cayo` route is marked international and requires:

- `passport` item in ox_inventory.
- Customs clearance at the configured customs desk before boarding.

Passenger flow for Cayo:

1. Buy ticket.
2. Clear customs with passport.
3. Scan boarding pass at the gate while the aircraft is parked in the gate boarding radius.
4. Auto-board into the aircraft.
5. Fly to Cayo.
6. Deboard inside the Cayo arrival ramp zone.

## Flight Flow

Flights are controlled by airport operation zones instead of fixed route rings. The pilot can taxi and fly naturally; the script only checks important airport events.

1. Pilot claims a scheduled flight. The aircraft spawns at the configured gate.
2. Pilot opens boarding. Passengers scan boarding passes at the gate.
3. The gate checks that the correct aircraft is parked inside the gate boarding radius.
4. Boarding scan moves the passenger into their aircraft seat.
5. Pilot closes boarding and contacts ground to start taxi.
6. Pilot taxis to the intermediate taxi hold marker.
7. ATC tells the pilot to hold and wait for runway instructions.
8. Pilot requests runway hold, taxis to the runway hold marker, then runs the final departure check.
9. ATC clears takeoff. The flight becomes airborne automatically when the aircraft leaves the takeoff zone above the configured altitude and speed.
10. Destination ATC detects the aircraft entering approach airspace while descending.
11. Landing is detected inside the destination landing zone at low altitude and speed.
12. Passengers complete the trip after exiting at the destination arrival ramp.

## Map Dev Notes

Airport behavior is managed from `/aircreator` and saved to oxmysql. `shared/config.lua` still controls global defaults, staff permissions, routes, aircraft, and legacy/static locations.

- Airport ATC point: tower or antenna center used for blips, debug coverage, and airspace visualization.
- Airport airspace: the single boundary where pilots are detected, asked whether they intend to land or transit, and considered inside that airport's control area.
- Runway surface: one precise poly per runway. Use at least 4 raycast points for clean runway edges.
- Auto-built directions: each runway gets two directions, one from each runway end. Each direction owns approach, takeoff, and landing zones.
- Manual hold zones: taxi hold and takeoff hold are always placed by hand per runway so map devs can match real taxiways and hold-short lines.
- Gates: aircraft spawn/boarding stands placed with a transparent ghost aircraft. ATC can send landed pilots to a saved gate waypoint.
- Hangars/storage: point markers for storing or returning airline aircraft.

Airport zones support `sphere`, `box`, and `poly`:

```lua
-- sphere
{ type = 'sphere', label = 'Ramp', coords = vec3(0.0, 0.0, 0.0), radius = 40.0 }

-- box
{ type = 'box', label = 'Hold Short', coords = vec3(0.0, 0.0, 0.0), length = 40.0, width = 12.0, heading = 90.0, thickness = 20.0 }

-- poly
{ type = 'poly', label = 'Runway', points = { vec3(0.0, 0.0, 0.0), vec3(10.0, 0.0, 0.0), vec3(10.0, 40.0, 0.0), vec3(0.0, 40.0, 0.0) }, thickness = 35.0 }
```

Routes in `Config.Routes` now describe commercial service: origin, destination, gate, price, requirements, aircraft, and payout. They should not force sky rings or exact taxi paths.

## Commands

- `/flights` opens the passenger booking menu.
- `/airline` opens airline dispatch for the `nolovelostairlines` job.
- `/airradio` opens the aircraft radio. Default key is `Z` from `Config.ATC.radioKey`.
- `/airhud` toggles the cockpit HUD on/off for the local player.
- `/airhudmove` opens move/resize mode for both the cockpit HUD and ATC radio while seated in an aircraft as pilot or front passenger.
- `/aircreator` or `/airzone` opens the in-game Airport Creator tablet for airline supervisors/admins.

## Pilot Radio And Cockpit HUD

The aircraft radio and cockpit HUD are separate overlays inside the same NUI page.

Aircraft radio:

- Opens with `/airradio` or the configured radio key, currently `Z`.
- Sends pilot intent requests: taxi/departure, landing, transit, emergency, touch-and-go, low pass, and flight following.
- Shows current facility, frequency, clearance, transmission log, readback status, and flight info.
- Uses the XMIT hotspot/button for clearance readback.
- Uses the ATC hotspot/button to switch between ATC and Flight views.
- Closes with `Escape` or `Backspace`.

Cockpit HUD:

- Auto-shows when the local player is the pilot or front passenger of an aircraft.
- Hides `jg-hud` while visible, then restores it when the HUD hides.
- Displays a PFD-style attitude/speed/altitude display and an MFD-style navigation map.
- Tracks nearby configured airports, active route origin/destination, and the GTA waypoint.

Layout editing:

- Use `/airhudmove` while seated in an aircraft to move/resize both the radio and cockpit HUD.
- Drag either panel to reposition it.
- Use the `-` and `+` buttons on each panel to resize it.
- Click `Lock In` to leave edit mode.
- Click `Reset All` to clear saved radio/HUD positions.
- Positions are saved per player using FiveM resource KVP keys, so players do not need to edit files.

## Airspace Volumes

ATC contact airspace is modeled with stacked 3D volumes in `Config.AirspaceVolumes`.
Each volume is data-driven and uses:

```lua
{
    id = 'lsia_tower_core',
    label = 'LSIA Tower Core',
    class = 'D',
    facility = 'LSIA Tower',
    airport = 'lsia',
    frequency = '118.100',
    floor = 0.0,
    ceiling = 700.0,
    priority = 10,
    polygon = {
        vec2(-2450.0, -3600.0),
        vec2(-850.0, -3950.0),
        vec2(450.0, -2900.0)
    }
}
```

Detection checks the aircraft XY position against the polygon, then checks aircraft Z altitude against `floor` and `ceiling`. Horizontally overlapping volumes are allowed because altitude bands separate tower, approach, and center airspace.

Current default structure:

- LSIA Tower/Core: low altitude airport control.
- LSIA Class B shelves: stacked LSIA approach shelves.
- Sandy Tower and Grapeseed Tower: low altitude North County airport control.
- North County Approach: larger regional approach sector above tower airspace.
- Cayo Tower and Cayo Approach: island tower/approach control.
- San Andreas Center: high altitude center sector above regional approach.

Altitude bands are compressed for GTA aircraft handling:

- LSIA Tower/Core: `0-550`
- LSIA Shelf 1: `550-850`
- LSIA Shelf 2: `850-2850`
- LSIA Shelf 3: `2850-5350`
- Sandy Tower/Shelves: `0-400`, `400-700`, `700-1700`
- Grapeseed Tower/Shelves: `0-350`, `350-650`, `650-1500`
- Other approach sectors: roughly `1500-4500`
- San Andreas Center: `4500-7500`

When `Config.Airspace.useVolumes = true`, aircraft contact, entry/exit messages, and radio suggestions use these polygon volumes. The old airport radius airspace remains in code only as a temporary fallback, and it is disabled by default with `Config.Airspace.allowRadiusFallback = false`.

Airport operation zones are still separate from airspace:

- Runway surfaces
- Approach/takeoff/landing zones
- Taxi hold and takeoff hold zones
- Gates and hangars

Those zones drive airport workflow and landing/takeoff detection. Airspace volumes only decide which ATC facility controls or contacts the aircraft.

## Dispatch Tablet Handoff

The airline job dispatch target is `Config.Locations.pilotTerminals.lsia_dispatch` at `-941.01, -2954.52, 13.95`.

When `Config.DispatchTablet.enabled = true`, that target opens the dispatch tablet bridge instead of the old ox_lib context menu. The `pilot_tablet` ox_inventory item can also open it anywhere for airline staff. A custom UI should consume the `businessTabletOpen`, `businessTabletData`, and `businessTabletClose` messages and call the `businessTablet*` NUI callbacks documented in `web/NUI_CONTRACT.md`.

The dispatch tablet is for airline job operations like scheduling, claiming, boarding flow, and completing flights. The aircraft radio remains separate on the pilot ATC panel.

## Airport Zone Setup

Use `/aircreator` to create precise airport operation zones in-game. This is for airport infrastructure, not forced flight routes.

Recommended zone types:

- `sphere`: forgiving areas like arrival ramps and large approach airspace.
- `box`: hold-short lines, compact taxi holds, rectangular ramp areas.
- `poly`: runways and angled runway/touchdown/takeoff areas where precision matters.

Workflow:

1. Run `/aircreator` or `/airzone`.
2. Pick or create an airport in the tablet.
3. Set the ATC point, coverage radius, and airport airspace radius.
4. In the ATC tab, set the airport airspace radius. Radius is the recommended airspace setup for now.
5. Draw each runway as a 4+ point poly.
6. Click `Auto Build ATC` on the runway. This creates both approach directions, runway landing zone, and departure zone.
7. Open the Zones tab, select the runway and direction, and verify the generated zones are listed.
8. Place `taxiHold` and `takeoffHold` manually from the Zones tab.
9. Place airport-wide gates with the ghost aircraft tool and add hangar/storage points as needed.
10. Turn on Debug Zones in Overview to see the airspace sphere, runway polys, generated direction zones, approach cues, gate markers, hangar markers, and ATC coverage sphere.
11. Save. Placements return to the tablet and auto-save the airport to oxmysql.

Auto Build ATC calculates the runway centerline from the longest runway poly edge, not the diagonal corners of the poly. Approach corridors are one continuous centered zone from the runway threshold outward, and takeoff corridors continue beyond the departure end.

Landing zones are auto-built on the runway surface with a low landing altitude cap. Approach zones include glide-slope metadata: higher allowed altitude farther out and lower allowed altitude close to the runway. Approach and takeoff zone capture defaults to `35` through `160` above the runway base so aircraft are detected while descending or climbing without counting ground taxi movement. Takeoff zones are built beyond the opposite runway end so a pilot can be assigned either direction. Taxi hold and takeoff hold are manual because those depend on the actual taxiway layout. Gates are airport-wide stands managed from the Gates tab, not runway trigger zones.

After updating glide or capture settings, run `Auto Build ATC` again for the runway so the approach and takeoff zones receive the latest slope and vertical-bound metadata. Test mode shows whether a miss is caused by 2D footprint or Z bounds.

For airports near water, generated approach/takeoff checks use the runway/zone base Z instead of ground-under-aircraft distance. This prevents water depth or sea-floor collision from changing the measured approach altitude.

LSIA uses the largest default airspace radius. When an active pilot enters an airport airspace while airborne, ATC asks for intent:

- `Request Landing`: assigns the first configured runway direction with approach and landing zones.
- `Transit / Passing Through`: ATC acknowledges the aircraft as passing through and does not assign a runway.

ATC notifies pilots when entering and leaving controlled airspace only after the aircraft is airborne enough. If the pilot closes the intent prompt without choosing landing or transit, ATC repeats the prompt on the configured reminder interval until they answer or leave airspace.

If airport airspaces overlap, the intent prompt uses the nearest airport center so two ATCs do not talk over each other. Debug mode draws one airspace sphere per airport.

Airspace radius is preferred for now because airport airspaces are large and easier to tune as spheres. A single controlled airspace poly can still be saved for custom shapes later, but radius remains the simplest setup.

Raycast polygon controls:

- `E`: add the point where your camera is aiming.
- `Backspace`: undo the last point.
- `Enter`: save/export once you have at least 4 points.
- `Delete`: cancel the polygon setup.
- `G`: toggle same-Z snapping. Same-Z is useful for clean flat runway polygons.

## Ghost Aircraft Placement

Use `/aircreator` and choose the Gates tab to visually line up aircraft spawn positions at airport-wide gates or arrival ramps.

The ghost aircraft is local-only, transparent, frozen, invincible, and not a real flight aircraft. Gate plane placement uses `object_gizmo` for exact positioning and rotation. Landing gear is forced down before and after gizmo editing so the plane sits correctly on its wheels.

Controls:

- `W`: translate mode.
- `R`: rotate mode.
- `Q`: switch local/world mode.
- `G`: toggle cursor.
- `Left Alt`: snap to ground.
- `Enter`: save placement.

Placed gates return to the tablet and auto-save to oxmysql. ATC uses the airport's gate list after landing, regardless of which runway/direction the pilot used.

## Testing An Airport In Game

1. `/aircreator`, pick the airport, enable Debug Zones, and confirm the ATC sphere, airport airspace sphere, runway poly, direction zones, gate markers, and hangar markers are visible.
2. In Runways, select `Auto Build ATC` for each runway.
3. In Zones, select the runway and direction. Confirm `takeoffZone`, `approachZone`, and `landingZone` show as auto-built direction zones.
4. In Overview, click `Test Airport Zones`. The tablet closes and a live ox_lib checklist shows whether your player or aircraft is inside the selected airport airspace, runway surface, taxi hold, takeoff hold, takeoff zone, approach zone, and landing zone. It also shows glide-path altitude status for auto-built approach zones.
5. Drive or fly through the zones. The zone outlines stay visible while the checklist updates.
6. Press `Backspace` to exit test mode and reopen the creator.
7. Place at least one gate at the departure airport and one gate at the arrival airport.
8. Create or use a route that points to those airports.
9. As the airline job, claim the flight. The aircraft should spawn at the departure gate.
10. Open boarding, scan a boarding pass, close boarding, then start taxi.
11. Taxi into the taxi hold and takeoff hold zones. ATC should call out the assigned runway direction and final check.
12. Take off, leave the takeoff zone above the configured altitude/speed, then fly toward the arrival airport.
13. Descend through the approach zone, land on the runway landing zone, and slow down. ATC should record landing and set a waypoint to one of the airport-wide gates.

## Config

Edit `shared/config.lua`.

- Replace example LSIA coords with your real ticket desks, pilot dispatch terminals, boarding gates, aircraft spawns, taxi holds, runway holds, takeoff zones, approach zones, landing zones, and airport-wide gates.
- Add routes under `Config.Routes`.
- Add aircraft under `Config.Aircraft`.
- Adjust airline job grade permissions under `Config.StaffGrades`.

## V2 Targets

- Admin airport creator UI.
- Gizmo prop placement.
- DUI departure boards, gate screens, kiosks, and pilot tablets.
- Full airline management UI.
- Restricted zone enforcement.
- Reputation, baggage, refunds, and advanced government/private flight flows.
