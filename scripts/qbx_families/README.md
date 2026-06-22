# qbx_families

Qbox family RP system kept separate from jobs and gangs.

## Setup

Add the resource to your server start order:

```cfg
ensure qbx_families
```

The resource creates its own database tables on start. The SQL file is included in `sql/families.sql` if you prefer importing it manually.

## Player Command

```text
/family
```

Players can see their family, role, family members, online status, and each member's current job.

## Staff Commands

```text
/setfamily [playerId] [family] [role]
/removefamily [playerId]
```

These use the configured Qbox admin permission, `group.admin`.

Example:

```text
/setfamily 12 carter member
/setfamily 18 carter cousin
```

## Management

Heads of House can invite, remove, change roles, and give allowance from pocket cash.

Heads are separate from RP titles. A player can be a Cousin, Brother, Sister, or any other role and still be a Head of House.

Each family can have up to 2 Heads of House by default:

```lua
Config.Management.maxHeadsPerFamily = 2
```

Staff commands:

```text
/addfamilyhead [playerId] [family]
/removefamilyhead [playerId] [family]
```

The system stores the player's CitizenID and Discord ID when assigning a Head of House.

## Family Points And Rewards

Families share one point balance. Everyone can view family level, total points, available points, and configured rewards from `/family`.

Only Heads of House can redeem rewards.

Staff commands:

```text
/addfamilypoints [family] [amount] [reason]
/removefamilypoints [family] [amount] [reason]
```

Rewards are configured in `Config.Progression.rewards`.

Supported reward types:

```text
money
item
vehicle
```

Vehicle rewards are given as owned vehicles to the Head of House who redeems the reward. They are parked in the configured garage, defaulting to `Legion Square`.

## Family Events

Heads of House can use the `Events` tab in `/family` to create saved events from their current location.

Saved events include:

```text
Event name
Configured event size preset
Placed center location
Optional captured scene banner
```

Event tier and points are controlled in `Config.Events.presets`. Families cannot type their own point value.
Event zones are polygon zones and require at least 4 points by default:

```lua
Config.Events.minZonePoints = 4
```

The event builder lives inside the tablet:

```text
Choose the event tier preset.
Click Add Points once, walk the zone, and right-click each corner/edge point.
Press Enter to save placed points and return to the tablet.
Press Backspace or Esc to cancel the placement session.
Click Capture Banner, face the scene, and right-click to capture the image.
Save the event from the tablet.
```

After a saved event is created, Heads of House can start it later from the same tablet tab. This lets families reuse recurring event zones without rebuilding them every time.

Owned saved events can be shared with another configured family. Shared families can see and start the event from their own Events tab, but only the owning family can delete/share the original saved event.

When an event is active:

```text
Family members inside the event radius count as participants.
The family earns points every configured tick.
Points are based on members inside the zone.
```

The client creates a PolyZone polygon for the active event, and the server verifies player position inside the polygon before awarding points.

Event config is in `Config.Events`.

```lua
Config.Events.tickMinutes = 5
Config.Events.defaultRadius = 35.0
Config.Events.defaultPointsPerTick = 10
```

Starting an event schedules it first. By default, events start after a 10 minute countdown:

```lua
Config.Events.startCountdownMinutes = 10
```

Only one scheduled or active event can run per family at a time.

Captured banners use `screenshot-basic` and are stored with the saved event. Keep `screenshot-basic` ensured before `qbx_families`.

Most family notifications display inside the tablet while it is open. Important notifications fall back to ox_lib when the tablet is closed.

## Adding Families

Add more family definitions in `config.lua` under `Config.Families`. Each family can reuse the same role keys or have custom ones.
