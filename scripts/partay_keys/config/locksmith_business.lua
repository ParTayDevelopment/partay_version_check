-- [[ ParTay Keys - Locksmith Business ]] --
-- Owner-facing player-run locksmith settings, economy guardrails, and service
-- requirements used by tablets, /locksmithadmin, invoices, and stock validation.

Config.PlayerJobs = Config.PlayerJobs or {}

local LocksmithDefaults = Config.PlayerJobDefaults and Config.PlayerJobDefaults.Locksmith or {}
local LocksmithStockingProps = Props and Props.Locksmith and Props.Locksmith.Stocking or {}
local LocksmithGarageProps = Props and Props.Locksmith and Props.Locksmith.Garage or {}
local LocksmithStockBoxModel = type(LocksmithStockingProps.StockBox) == 'table'
    and LocksmithStockingProps.StockBox.Model
    or LocksmithStockingProps.StockBox

Config.PlayerJobs.Locksmith = {
    Enabled = Config.EnablePlayerRunLocksmith == true,

    RequireDuty = false,
    CustomerRange = 6.0,
    VehicleRange = 14.0,

    -- Employee tablet command for mobile service work away from the shop.
    EmployeeTabletCommand = 'locksmithtablet',

    -- Customer invoices are approved first, then paid after the employee completes the work.
    InvoiceExpiresSeconds = 120,
    ApprovedJobExpiresMinutes = 20,

    Appointments = {
        Enabled = true,
        Command = 'locksmithrequest',
        AllowKeyMenuRequest = true,
        NotifyOffDutyWhenOnCall = true,
        ExpireMinutes = 20
    },

    Workflow = {
        RequireWorkBeforePayment = true,
        HoldCustomerKeysUntilPaid = true,
        DoorWorkSeconds = 3.5
    },

    Business = {
        Enabled = true,
        OwnerMinGrade = 4,

        SocietyDeposits = true,
        SocietyMaxTransaction = 100000,

        DefaultShopStatus = 'closed', -- open, on_call, or closed
        DefaultOnCallContact = '',
        EmployeeManagement = true,
        HireRange = 6.0,
        ConsumeStockForJobs = true,
        ConsumeStockForShop = true,

        Workbench = {
            Enabled = true,
            TargetDistance = 2.0,
            CraftMinGrade = 0,
            OwnerOnly = false,
            CraftSeconds = 5.0
        },

        Garage = {
            Enabled = true,
            -- auto: detected garage provider when available, otherwise standalone.
            -- standalone: ParTay Keys spawns temporary job vehicles directly.
            -- provider: setup creates a point that should be mirrored in your garage resource.
            -- disabled: garage point and actions are unavailable.
            Mode = 'auto',
            RequireDuty = true,
            TargetDistance = 3.0,
            StoreRadius = 8.0,
            SpawnOffset = vector4(0.0, -5.5, 0.0, 0.0),
            PlatePrefix = 'LOCK',
            ProviderGarageType = 'job',
            ProviderGarageNamePrefix = 'partay_locksmith',
            Vehicles = LocksmithGarageProps.ServiceVehicles or {
                { label = 'Service Van', model = 'speedo' },
                { label = 'Utility Pickup', model = 'bison' }
            }
        },

        Stocking = {
            Enabled = true,
            DefaultSupplierContract = 'standard',
            MaxOrderQuantity = 50,
            CarryBoxSeconds = 3.0,
            DeliveryDelaySeconds = 90,
            PickupDelaySeconds = 90,

            -- Default off-site warehouse pickup point for pickup-based orders.
            -- The active warehouse pickup location, optional ped, and optional blip are managed in /locksmithadmin > Universal.
            PickupLocations = {},

            -- Deep supplier/order defaults live in modules/player_jobs.lua.
            SupplierContracts = LocksmithDefaults.SupplierContracts or {},
            OrderItems = LocksmithDefaults.OrderItems or {},

            -- Presentation defaults used by delivery/pickup flows.
            BoxModel = LocksmithStockBoxModel or 'prop_cardbordbox_04a',
            TruckModel = LocksmithStockingProps.DeliveryTruck or 'boxville2',
            DeliveryPedModel = LocksmithStockingProps.DeliveryPed or 's_m_m_dockwork_01',
            DeliverySpawnOffset = vector4(0.0, -8.0, 0.0, 0.0)
        }
    }
}

Config.LocksmithPayment = {
    EmployeeCommissionPercent = 0,
    EmployeeCommissionAccount = 'cash',
    MaxCommissionPercent = 25,
    MaxCommissionPerInvoice = 5000,

    -- server: commissions/payroll are minted by the server.
    -- society: commissions/payroll attempt to withdraw from the configured society account first.
    PaySource = 'society',
    PayrollEnabled = true,
    MaxPayrollPayout = 1000,
    PayrollAccount = 'bank'
}

Config.PlayerJobs.Locksmith.Payment = Config.LocksmithPayment

Config.LocksmithPriceLimits = {
    Default = { Min = 0, Max = 100000 },
    Services = {
        Copy = { Min = 0, Max = 5000 },
        Recover = { Min = 100, Max = 10000 },
        ReKey = { Min = 500, Max = 25000 }
    },
    KeyTiers = {
        basic = { Min = 0, Max = 5000 },
        smart = { Min = 100, Max = 10000 },
        advanced = { Min = 500, Max = 20000 },
        oled = { Min = 1000, Max = 30000 }
    },
    Shop = {
        [Config.Items.BasicCarAlarm] = { Min = 250, Max = 7500 },
        [Config.Items.CarAlarm] = { Min = 250, Max = 10000 },
        [Config.Items.AdvancedCarAlarm] = { Min = 500, Max = 20000 },
        [Config.Items.AlarmRemovalTool] = { Min = 100, Max = 10000 },
        [Config.Items.GPSTracker] = { Min = 250, Max = 10000 },
        [Config.Items.StandardGPSTracker] = { Min = 250, Max = 15000 },
        [Config.Items.AdvancedGPSTracker] = { Min = 500, Max = 25000 },
        [Config.Items.ValetModule] = { Min = 500, Max = 25000 },
        [Config.Items.GPSTablet] = { Min = 250, Max = 10000 },
        [Config.Items.SignalFinder] = { Min = 100, Max = 5000 }
    },
    Orders = {
        [Config.Items.LocksmithBlankBasicKey] = { Min = 1, Max = 1000 },
        [Config.Items.EmptySmartFob] = { Min = 1, Max = 2500 },
        [Config.Items.EmptyAdvancedFob] = { Min = 1, Max = 5000 },
        [Config.Items.EmptyOLEDFob] = { Min = 1, Max = 7500 },
        [Config.Items.RuggedTabletParts] = { Min = 1, Max = 5000 },
        [Config.Items.AlarmCircuitBoard] = { Min = 1, Max = 5000 },
        [Config.Items.AlarmSiren] = { Min = 1, Max = 5000 },
        [Config.Items.AlarmRemovalTool] = { Min = 100, Max = 10000 },
        [Config.Items.TrackerCircuitBoard] = { Min = 1, Max = 5000 },
        [Config.Items.GpsAntenna] = { Min = 1, Max = 5000 },
        [Config.Items.SignalFinder] = { Min = 100, Max = 10000 }
    }
}
