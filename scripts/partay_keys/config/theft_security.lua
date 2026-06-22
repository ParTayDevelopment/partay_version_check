-- ==========================================
-- [[ THEFT & SECURITY ]]
-- ==========================================

-- Alerts the original owner when permanent theft/decoder possession changes occur.
Config.NotifyOwnerOnTheft = true

Config.Heist = {
    -- Each theft step is independent. If a step is disabled, the flow skips to the next required step.
    EnableLockpicking = true,
    EnableHotwiring = true,

    -- Delay before showing the hotwire warning after entering a vehicle without access.
    HotwireWarningDelay = 3500,

    -- Percent chance that the active theft item breaks after a failed step.
    BreakChanceOnFail = 50,

    -- Consumes the blank key when a decoder successfully creates a functional stolen key.
    ConsumeOnSuccess = true,

    -- true: decoder theft updates possession until the vehicle is recovered/rekeyed.
    -- false: theft remains temporary access only.
    EnablePermanentTheft = true,

    -- Recovery is returning a stolen vehicle to the original owner.
    RecoveryRequiresLocksmith = true,

    -- Rekeying invalidates old key versions and shared keys.
    ReKeyRequiresLocksmith = true,

    Police = {
        -- Jobs counted as police for theft-gated features and fallback police alerts.
        Jobs = { 'police', 'sheriff', 'state' },

        Lockpick = {
            -- If enabled, lockpicking cannot start unless enough police are online/on duty.
            RequireOnline = false,
            MinimumOnline = 2
        },

        Decoder = {
            -- If enabled, key decoding cannot start unless enough police are online/on duty.
            RequireOnline = false,
            MinimumOnline = 2
        }
    },

    PoliceAlerts = {
        -- Sends dispatch only when a heist-failure alarm is witnessed by a nearby NPC.
        Enabled = true,

        -- NPCs within this distance can hear the alarm even without line of sight.
        HearingDistance = 55.0,

        -- NPCs within this distance with line of sight can report what they saw.
        SightDistance = 42.0,

        -- Prevents repeated dispatch spam from repeated failures on the same vehicle.
        Cooldown = 60,

        -- Alert code/title passed into the dispatch payload.
        Code = '10-60',
        Title = 'Vehicle Theft Alarm'
    },

    NPCVehicles = {
        -- Gives NPC vehicles a chance to spawn unlocked instead of always forcing a lockpick step.
        EnableLockChance = true,

        -- Percent chance NPC vehicles start locked.
        LockedChance = 40,

        Robbery = {
            -- Enables occupied NPC vehicle robbery behavior. This only applies to unregistered NPC vehicles.
            Enabled = true,

            -- If an unlocked NPC vehicle has a driver, trying the door makes the driver bail out.
            UnlockedDoorFlee = true,

            -- Pointing a firearm at the driver for this long makes them surrender temporary vehicle access.
            GunpointEnabled = true,
            AimHoldTime = 1500,

            -- Max distance from the vehicle/driver when requesting temporary access.
            MaxDistance = 12.0,

            Retaliation = {
                -- Armed aggressive NPCs can fight back instead of surrendering keys.
                Enabled = true,

                -- When true, only NPCs from configured aggressive relationship groups retaliate.
                AggressiveOnly = true,

                -- Percent chance an armed aggressive NPC retaliates when threatened.
                ArmedAggressiveChance = 100,

                -- Percent chance an armed non-aggressive NPC retaliates if AggressiveOnly is false.
                ArmedCivilianChance = 20,

                -- Prevents the same NPC from repeatedly re-triggering retaliation logic.
                Cooldown = 15000,

                AggressiveRelationshipGroups = {
                    'AMBIENT_GANG_BALLAS',
                    'AMBIENT_GANG_FAMILY',
                    'AMBIENT_GANG_MEXICAN',
                    'AMBIENT_GANG_LOST',
                    'AMBIENT_GANG_MARABUNTE',
                    'AMBIENT_GANG_CULT',
                    'AMBIENT_GANG_SALVA',
                    'AMBIENT_GANG_WEICHENG',
                    'AMBIENT_GANG_HILLBILLY'
                }
            },

            -- Prevents repeated robbery grants against the same target.
            Cooldown = 8000
        }
    },

    -- Currency used when a thief sells stolen possession to another player with a sale contract.
    -- The self-service blackmarket dealer shop currency is managed in-game from /locksmithadmin.
    BlackmarketCurrency = 'black_money',

    -- ESX normally treats black_money as an account. Enable this for ESX servers that use
    -- ox_inventory-style black_money as an item instead.
    ESXBlackMoneyAsItem = false,

    -- Max distance between seller, buyer, and vehicle for blackmarket sale contracts.
    MaxSaleDistance = 5.0
}

-- Alarm/GPS item mappings and tier defaults are internal module defaults now:
-- modules/alarm_tiers.lua and modules/gps_tiers.lua. Keep this file focused on
-- theft policy and economy rules that server owners are likely to tune.
Config.Security = Config.Security or {}
