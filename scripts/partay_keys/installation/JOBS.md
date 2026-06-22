# Locksmith Job Setup

Use this when `Config.EnablePlayerRunLocksmith = true`.

The examples below use the job name `locksmith`, but ParTay Keys does not require
that exact name. Create any framework job you want, then enter that job name when
creating the shop in `/locksmithadmin`.

Runtime locksmith access comes from the in-game shop setup stored in the
database. Do not maintain a separate ParTay Keys job list in config.

Restart your framework resource after adding or changing framework jobs.

## QBX / Qbox

Open:

`resources/[qbx]/qbx_core/shared/jobs.lua`

Add this inside the returned jobs table:

```lua
['locksmith'] = {
    label = 'Locksmith',
    defaultDuty = true,
    offDutyPay = false,
    grades = {
        [0] = {
            name = 'Apprentice',
            payment = 35
        },
        [1] = {
            name = 'Technician',
            payment = 50
        },
        [2] = {
            name = 'Senior Technician',
            payment = 65
        },
        [3] = {
            name = 'Manager',
            payment = 85,
            bankAuth = true
        },
        [4] = {
            name = 'Owner',
            payment = 100,
            isboss = true,
            bankAuth = true
        },
    },
},
```

## QB-Core

Open:

`resources/[qb]/qb-core/shared/jobs.lua`

Add this inside `QBShared.Jobs`:

```lua
['locksmith'] = {
    label = 'Locksmith',
    defaultDuty = true,
    offDutyPay = false,
    grades = {
        ['0'] = {
            name = 'Apprentice',
            payment = 35
        },
        ['1'] = {
            name = 'Technician',
            payment = 50
        },
        ['2'] = {
            name = 'Senior Technician',
            payment = 65
        },
        ['3'] = {
            name = 'Manager',
            payment = 85,
            bankAuth = true
        },
        ['4'] = {
            name = 'Owner',
            payment = 100,
            isboss = true,
            bankAuth = true
        },
    },
},
```

## ESX

Run this SQL against your database:

```sql
INSERT INTO `jobs` (`name`, `label`) VALUES
('locksmith', 'Locksmith')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES
('locksmith', 0, 'apprentice', 'Apprentice', 35, '{}', '{}'),
('locksmith', 1, 'technician', 'Technician', 50, '{}', '{}'),
('locksmith', 2, 'senior_technician', 'Senior Technician', 65, '{}', '{}'),
('locksmith', 3, 'manager', 'Manager', 85, '{}', '{}'),
('locksmith', 4, 'owner', 'Owner', 100, '{}', '{}')
ON DUPLICATE KEY UPDATE
    `name` = VALUES(`name`),
    `label` = VALUES(`label`),
    `salary` = VALUES(`salary`);
```

If your ESX schema does not have a unique key on `job_name` plus `grade`, delete existing locksmith grades before re-running the insert.

## Society Account

ParTay Keys can deposit ped purchases, stock orders, invoices, payroll, and commissions into the configured society account when the relevant options are enabled.

Default account:

`locksmith`

Make sure your society/management resource has an account for the same name:

- QBX: `qbx_management`
- QB-Core: `qb-management`
- ESX: `esx_society`

## Setup Command

Admins configure shops in-game with:

`/locksmithadmin`

Shop owners can adjust their assigned shop with:

`/locksmithowner`

Recommended ACE:

```cfg
add_ace group.admin partay_keys.locksmithsetup allow
```

The admin setup tablet supports creating/deleting shops, choosing `Player Owned` or `Self Service`, assigning job names for player-owned shops, placing spawned props, using existing MLO props, stand spots, and route points through the built-in gizmo-style placement tools. Player-owned shops use the saved framework job name for owner and employee access. Self-service shops do not use a framework job name and only require the NPC clerk ped. The owner setup tablet is scoped to the owner's current job and cannot create, delete, rename, reassign, or convert shops. Spawned props and peds follow in front of the player while they walk; press `G` to toggle fixed fine-placement mode with axis arrows and rotation rings, `Ctrl` for slow movement, and `Shift` for faster movement.
