# Qbox Permanent Theft Garage Patch

Use this only if you want permanent theft possession to work through stock `qbx_garages`.

The goal is:

- `citizenid` remains the registered/legal owner.
- `possession_id` controls who can garage/retrieve a permanently stolen vehicle.
- The original owner does not see the vehicle in their garage while `possession_id` belongs to someone else.
- The thief can see the vehicle even if the `garage` column still points to the owner's previous garage.

## 1. Add Indexes

Run once in your database:

```sql
CREATE INDEX idx_partay_possession_id ON player_vehicles (possession_id);
CREATE INDEX idx_partay_possession_state ON player_vehicles (possession_id, state);
```

## 2. Patch `qbx_vehicles/server/main.lua`

In `buildWhereClause(filters)`, add this local near the top after `whereClauseCrumbs`:

```lua
local garageHandledByPossessionFilter = false
```

Replace the `if filters.citizenid then ... end` block with:

```lua
if filters.citizenid then
    if filters.includePossession then
        if filters.garage then
            whereClauseCrumbs[#whereClauseCrumbs+1] = [[
                (
                    (
                        citizenid = ?
                        AND garage = ?
                        AND (
                            possession_id IS NULL
                            OR possession_id = ''
                            OR possession_id = citizenid
                        )
                    )
                    OR (
                        possession_id = ?
                        AND possession_id IS NOT NULL
                        AND possession_id <> ''
                        AND possession_id <> citizenid
                    )
                )
            ]]
            placeholders[#placeholders+1] = filters.citizenid
            placeholders[#placeholders+1] = filters.garage
            placeholders[#placeholders+1] = filters.citizenid
            garageHandledByPossessionFilter = true
        else
            whereClauseCrumbs[#whereClauseCrumbs+1] = [[
                (
                    (
                        citizenid = ?
                        AND (
                            possession_id IS NULL
                            OR possession_id = ''
                            OR possession_id = citizenid
                        )
                    )
                    OR (
                        possession_id = ?
                        AND possession_id IS NOT NULL
                        AND possession_id <> ''
                        AND possession_id <> citizenid
                    )
                )
            ]]
            placeholders[#placeholders+1] = filters.citizenid
            placeholders[#placeholders+1] = filters.citizenid
        end
    else
        whereClauseCrumbs[#whereClauseCrumbs+1] = 'citizenid = ?'
        placeholders[#placeholders+1] = filters.citizenid
    end
end
```

Then change the garage filter from:

```lua
if filters.garage then
```

to:

```lua
if filters.garage and not garageHandledByPossessionFilter then
```

## 3. Patch `qbx_garages/server/main.lua`

In `GetPlayerVehicleFilter`, add:

```lua
filter.includePossession = true
```

right after:

```lua
filter.citizenid = not garage.shared and player.PlayerData.citizenid or nil
```

In `isParkable`, replace the ownership check with a possession-aware check:

```lua
if not garage.shared then
    local canPark, reason = exports.partay_keys:AssertCanParkVehicle(source, playerVehicle.props.plate)
    if not canPark then
        return false, reason
    end
end
```

`AssertCanParkVehicle` shows the player the ParTay Keys garage message when storage is blocked. Use this export for patched garage store flows.

This replaces the generic `locale('error.not_owned')` notification for this path with a longer message when the vehicle is still marked as stolen possession.
