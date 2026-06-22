-- ==========================================
-- [[ INTEGRATIONS & ADVANCED COMPATIBILITY ]]
-- ==========================================
-- Provider options: 'auto', 'qbx', 'qb', 'esx', 'jg', 'custom', 'disabled'

Config.Integrations = {
    Garage = {
        -- auto detects the first supported running garage resource.
        Provider = 'auto',

        -- Shows a player notification when a vehicle cannot be retrieved because it is stolen/possessed.
        NotifyOnBlockedRetrieve = true,

        -- Shows a player notification when a vehicle cannot be stored because it is stolen/possessed.
        NotifyOnBlockedPark = true,

        -- Restores vehicles left "out" by the garage after a server restart.
        -- Enable only if your garage does not already handle restart recovery correctly.
        RestoreOutVehiclesOnStart = false,

        -- Garage state values vary by resource. These defaults match qbx/qb-style player_vehicles.
        StateColumn = 'state',
        OutStateValue = 0,
        StoredStateValue = 1,

        Providers = {
            qbx = {
                Resource = 'qbx_garages',
                VehicleTable = 'player_vehicles',
                OwnerColumn = 'citizenid',
                VehicleSpawnedEvents = {
                    'qbx_garages:server:vehicleSpawned'
                }
            },
            qb = {
                Resource = { 'qb-garages', 'qb-garages2' },
                VehicleTable = 'player_vehicles',
                OwnerColumn = 'citizenid',
                VehicleSpawnedEvents = {
                    'qb-garages:server:vehicleSpawned',
                    'qb-garages:server:VehicleSpawned',
                    'qb-garages:server:spawnedVehicle'
                }
            },
            esx = {
                Resource = { 'esx_garage', 'esx_advancedgarage' },
                VehicleTable = 'owned_vehicles',
                OwnerColumn = 'owner',
                VehicleSpawnedEvents = {
                    'esx_garage:server:vehicleSpawned',
                    'esx_advancedgarage:server:vehicleSpawned'
                }
            },
            jg = {
                Resource = { 'jg-advancedgarages', 'jg-advanced-garages' },
                VehicleTable = 'player_vehicles',
                OwnerColumn = 'citizenid',
                VehicleSpawnedEvents = {
                    'jg-advancedgarages:server:vehicleSpawned',
                    'jg-advanced-garages:server:vehicleSpawned'
                }
            }
        },
        Custom = {
            Resource = '',
            VehicleTable = 'player_vehicles',
            OwnerColumn = 'citizenid',
            VehicleSpawnedEvents = {}
        }
    },

    Dealership = {
        -- auto detects the first supported running dealership resource.
        Provider = Config.DealershipProvider or 'auto',
        Providers = {
            qbx = {
                Resource = { 'qbx_vehiclesales', 'qbx_vehicleshop' },
                Events = {
                    'qbx_vehicleshop:buyVehicle',
                    'qbx_vehicleshop:purchaseVehicle',
                    'qbx_vehicleshop:server:buyVehicle',
                    'qbx_vehicleshop:server:purchaseVehicle',
                    'qbx_vehicleshop:server:financeVehicle',
                    'qbx_vehiclesales:server:purchaseVehicle'
                }
            },
            qb = {
                Resource = 'qb-vehicleshop',
                Events = {
                    'qb-vehicleshop:server:buyShowroomVehicle',
                    'qb-vehicleshop:server:buyVehicle',
                    'qb-vehicleshop:server:purchaseVehicle',
                    'qb-vehicleshop:server:financeVehicle'
                }
            },
            esx = {
                Resource = 'esx_vehicleshop',
                Events = {
                    'esx_vehicleshop:buyVehicle',
                    'esx_vehicleshop:purchaseVehicle',
                    'esx_vehicleshop:setVehicleOwned',
                    'esx_vehicleshop:server:buyVehicle',
                    'esx_vehicleshop:server:purchaseVehicle'
                }
            },
            jg = {
                Resource = { 'jg-dealerships', 'jg_dealership' },
                Events = {
                    'jg_dealership:BuyVehicle',
                    'jg_dealership:PurchaseVehicle',
                    'jg_dealership:server:BuyVehicle',
                    'jg_dealership:server:PurchaseVehicle',
                    'jg-dealerships:server:purchase-vehicle:config',
                    'jg-dealerships:server:purchase-vehicle',
                    'jg-dealerships:server:purchaseVehicle'
                }
            }
        },
        Custom = {
            Resource = '',
            Events = {}
        }
    },

    Dispatch = {
        -- Provider options: 'auto', 'qbx', 'cd', 'ps', 'lb-tablet', 'qb', 'esx', 'custom', 'disabled'
        Provider = 'auto',

        Providers = {
            qbx = { Resource = 'qbx_police' },
            cd = { Resource = 'cd_dispatch' },
            ps = { Resource = 'ps-dispatch' },
            ['lb-tablet'] = { Resource = 'lb-tablet' },
            qb = { Resource = 'qb-core' },
            esx = { Resource = 'es_extended' }
        },

        -- Optional owner-supplied hook. Return true if your dispatch handled the alert.
        CustomHandler = nil
    },

    Phone = {
        -- Provider options: 'auto', 'lb-phone', 'npwd', 'qs-smartphone', 'gksphone', 'custom', 'disabled'
        Provider = 'auto',

        -- Phone messages are best-effort. Normal in-game notifications still run unless this is false.
        FallbackNotify = true,

        Providers = {
            ['lb-phone'] = {
                Resource = 'lb-phone',
                App = 'Mail',
                Sender = 'ParTay Locksmith'
            },
            npwd = {
                Resource = 'npwd',
                App = 'MESSAGES',
                Sender = 'ParTay Locksmith'
            },
            ['qs-smartphone'] = {
                Resource = { 'qs-smartphone', 'qs-smartphone-pro' },
                Sender = 'ParTay Locksmith'
            },
            gksphone = {
                Resource = { 'gksphone', 'gksphonev2' },
                Sender = 'ParTay Locksmith'
            }
        },

        Custom = {
            Resource = '',

            -- Optional hook for custom phone resources. Payload contains:
            -- source, citizenId, title, message, type, category, metadata.
            -- Return true when your phone handled it.
            Handler = nil,

            -- Optional event fired when Provider = 'custom' or when other providers miss.
            -- The event receives the same payload table.
            Event = ''
        }
    }
}

-- ADVANCED COMPATIBILITY SHIMS
-- Do not change this section unless you know which legacy resources call old vehicle-key events.
-- Incorrect settings can break dealership, garage, or job vehicle access.
Config.Compatibility = {
    EnableLegacyKeyEvents = true,
    RequireLegacyVehicleNearby = false,
    LegacyVehicleMaxDistance = 15.0,
    AllowLegacyTargetedKeyGrant = false,
    AllowClientPurchaseRegistration = true,
    AuditLegacyEvents = true
}
