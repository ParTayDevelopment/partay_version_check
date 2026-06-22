-- [[ ParTay Keys - Player Job Defaults ]] --
-- Internal default tables for player-run jobs. Owner-facing locksmith staff,
-- permission, stock, and pricing controls are managed from in-game setup.

Config.PlayerJobDefaults = Config.PlayerJobDefaults or {}

local LocksmithSetupProps = Props and Props.Locksmith and Props.Locksmith.Setup or {}

Config.PlayerJobDefaults.Locksmith = {
    ServicePermissions = {
        Shop = { Label = 'Shop Orders', MinGrade = 0, Enabled = true },
        Copy = { Label = 'Physical Key Copies', MinGrade = 0, Enabled = true },
        Recover = { Label = 'Vehicle Recovery', MinGrade = 0, Enabled = true },
        ReKey = { Label = 'Vehicle Re-Key', MinGrade = 0, Enabled = true },
        KeyTiers = { Label = 'Key System Upgrades', MinGrade = 0, Enabled = true },
        Garage = { Label = 'Job Garage', MinGrade = 0, Enabled = true }
    },

    ManagementPermissions = {
        Payroll = { Enabled = true, Label = 'Payroll', MinGrade = 4 },
        Candidates = { Enabled = true, Label = 'Nearby Candidates', MinGrade = 4 },
        Reports = { Enabled = true, Label = 'Business Reports', MinGrade = 4 },
        AppointmentSchedule = { Enabled = true, Label = 'Schedule Appointments', MinGrade = 1 },
        AppointmentComplete = { Enabled = true, Label = 'Complete Appointments', MinGrade = 1 },
        AppointmentCancel = { Enabled = true, Label = 'Cancel Appointments', MinGrade = 2 },
        AppointmentReminder = { Enabled = true, Label = 'Send Appointment Reminders', MinGrade = 1 }
    },

    StaffDefaults = {
        DefaultHireGrade = 0,
        MinEmployeeGrade = 0,
        MaxEmployeeGrade = 4,
        FireJob = 'unemployed',
        FireGrade = 0
    },

    RequiredTools = {
        Copy = Config.Items.LegalKeyImprinter,
        ReKey = Config.Items.LegalKeyImprinter,
        KeyTiers = Config.Items.LegalKeyImprinter
    },

    ServiceStock = {
        copy = 'tier_blank',
        rekey = 'tier_blank',
        upgrade = 'tier_blank',
        recover = {}
    },

    SelfService = {
        EnableKeyTierServices = true,
        EnableShop = true,
        ServiceFees = {
            Copy = 0,
            Recover = 500,
            ReKey = 2500
        },
        Items = {
            { item = Config.Items.BasicCarAlarm, label = 'Basic Alarm', price = 900, image = 'assets/basic_car_alarm.svg', description = 'Entry-level alarm package with core theft and damage response.' },
            { item = Config.Items.CarAlarm, label = 'Standard Alarm', price = 1500, image = 'assets/car_alarm.png', description = 'Balanced alarm package with damage, fob panic, and witnessed alert support.' },
            { item = Config.Items.AdvancedCarAlarm, label = 'Advanced Alarm', price = 3000, image = 'assets/advanced_car_alarm.svg', description = 'Premium alarm package prepared for smart notification features.' },
            { item = Config.Items.AlarmRemovalTool, label = 'Alarm Removal Tool', price = 1200, image = 'assets/alarm_removal_tool.svg', description = 'Reusable tool for removing installed alarms before upgrades.' },
            { item = Config.Items.GPSTracker, label = 'Basic GPS Tracker', price = 1500, image = 'assets/gps_tracker.png', description = 'Wide-radius tracker for basic vehicle recovery work.' },
            { item = Config.Items.StandardGPSTracker, label = 'Standard GPS Tracker', price = 2500, image = 'assets/standard_gps_tracker.svg', description = 'Improved tracker with tighter pings and better signal resolution.' },
            { item = Config.Items.AdvancedGPSTracker, label = 'Advanced GPS Tracker', price = 4000, image = 'assets/advanced_gps_tracker.svg', description = 'Premium tracker prepared for smart notification features.' },
            { item = Config.Items.ValetModule, label = 'OLED Valet Module', price = 3500, image = 'assets/valet_module.svg', description = 'Vehicle-side module required for OLED key valet call-in.' },
            { item = Config.Items.GPSTablet, label = 'GPS Tablet', price = 1000 },
            { item = Config.Items.SignalFinder, label = 'Signal Finder', price = 750 }
        }
    },

    Setup = {
        TargetDistance = 2.0,
        AllowExistingMloProps = true
    },

    SetupStockMethods = {
        auto = {
            Label = 'Automatic Insert',
            Description = 'Owners order and pay for materials, then stock is inserted immediately.',
            Enabled = true
        },
        delivery = {
            Label = 'Supplier Delivery',
            Description = 'Owners order stock, then a supplier truck arrives after a delay and drops off boxes.',
            Enabled = true
        },
        pickup = {
            Label = 'Warehouse Pickup',
            Description = 'Owners order stock, then employees drive to a pickup point, load boxes, and return them to stock.',
            Enabled = true
        }
    },

    SetupPoints = {
        workbench = {
            Label = 'Use Locksmith Workbench',
            Description = 'Crafting station for locksmith stock and finished security items. Stand spot controls where employees animate while using the bench.',
            Model = LocksmithSetupProps.Workbench or 'prop_tool_bench02',
            Icon = 'fas fa-screwdriver-wrench',
            AllowExistingProp = true
        },
        management = {
            Label = 'Open Locksmith Management',
            Description = 'Owner and manager terminal for business settings, reports, funds, and employee management.',
            Model = LocksmithSetupProps.Management or 'prop_monitor_w_large',
            Icon = 'fas fa-desktop',
            AllowExistingProp = true
        },
        timeclock = {
            Label = 'Locksmith Timeclock',
            Description = 'Employee duty toggle point. Staff clock in or out here before using duty-gated locksmith services.',
            Model = LocksmithSetupProps.Timeclock or 'prop_ld_keypad_01',
            Icon = 'fas fa-clock',
            Required = false,
            Frameworks = { qb = true, qbx = true },
            AllowExistingProp = true
        },
        register = {
            Label = 'Use Locksmith Register',
            Description = 'Customer-facing register. Customers place paid orders here when employees are online.',
            Model = LocksmithSetupProps.Register or 'prop_till_01',
            Icon = 'fas fa-cash-register',
            AllowExistingProp = true
        },
        customer_pickup = {
            Label = 'Customer Order Pick-Up',
            Description = 'Optional pickup table/box location. Filled customer orders appear here as targetable packages.',
            Model = LocksmithSetupProps.CustomerPickup or 'prop_cs_cardbox_01',
            Icon = 'fas fa-box-open',
            Required = true,
            Targetable = true,
            AllowExistingProp = true
        },
        stock = {
            Label = 'Open Locksmith Stock',
            Description = 'Physical stock storage. Employees use this to fill customer orders and store delivered materials.',
            Model = LocksmithSetupProps.Stock or 'prop_boxpile_06b',
            Icon = 'fas fa-boxes-stacked',
            AllowExistingProp = true
        },
        status_sign = {
            Label = 'Locksmith Status Sign',
            Description = 'Public shop status board. It displays open, on-call, or closed status plus optional contact details.',
            Model = LocksmithSetupProps.StatusSign or 'prop_noticeboard_01',
            Icon = 'fas fa-sign-hanging',
            Required = false,
            AllowExistingProp = true
        },
        fallback_ped = {
            Label = 'Self-Service Locksmith',
            Description = 'NPC clerk for self-service locksmith locations. Player-owned shops do not use this point.',
            Model = LocksmithSetupProps.SelfServicePed or 's_m_m_highsec_01',
            Icon = 'fas fa-user-tie',
            Required = true,
            IsPed = true,
            AllowExistingProp = false
        },
        garage = {
            Label = 'Locksmith Garage',
            Description = 'Job garage interaction point. Supported external garages use this as the configured garage location; standalone mode also uses a child vehicle spawn preview.',
            Model = LocksmithSetupProps.Garage or 'prop_parkingpay',
            Icon = 'fas fa-warehouse',
            Required = false,
            AllowExistingProp = true
        },
        vehicle_spawn = {
            Label = 'Garage Vehicle Spawn',
            Description = 'Standalone fallback spawn position for locksmith service vehicles. Place it as a child point from the garage setup card.',
            Model = LocksmithSetupProps.GarageVehiclePreview or 'speedo',
            Icon = 'fas fa-car-side',
            Required = false,
            Targetable = false,
            AllowExistingProp = false,
            SubPointOf = 'garage',
            VehiclePreview = true,
            RequiresGarageMode = 'standalone',
            RequiresWith = 'garage'
        },
        delivery_spawn = {
            Label = 'Delivery Truck Spawn',
            Description = 'Stand where supplier delivery trucks should spawn. Route points on this setup card control the truck driving path before it reaches the Delivery Drop-Off driver start.',
            RouteDescription = 'Truck route: start at Delivery Truck Spawn, follow each waypoint you add here, then finish at the first Delivery Drop-Off route point.',
            Icon = 'fas fa-truck',
            Required = true,
            RequiresStockMethod = 'delivery',
            CoordOnly = true,
            SpawnProp = false,
            Targetable = false,
            AllowExistingProp = false
        },
        delivery_dropoff = {
            Label = 'Delivery Drop-Off',
            Description = 'Stand where the supplier driver should deliver the stock box. The first route point is where the truck stops and the driver gets out.',
            RouteDescription = 'Driver route: first point is the truck stop/NPC start, then each waypoint walks the driver to this drop-off coordinate.',
            Icon = 'fas fa-box-open',
            Required = true,
            RequiresStockMethod = 'delivery',
            CoordOnly = true,
            SpawnProp = false,
            Targetable = false,
            AllowExistingProp = false
        }
    },

    SupplierContracts = {
        budget = {
            Label = 'Budget Supplier',
            PriceMultiplier = 0.85,
            DelayMultiplier = 1.35,
            Description = 'Lower material costs with slower delivery windows.'
        },
        standard = {
            Label = 'Standard Supplier',
            PriceMultiplier = 1.0,
            DelayMultiplier = 1.0,
            Description = 'Balanced supplier pricing and timing.'
        },
        premium = {
            Label = 'Premium Supplier',
            PriceMultiplier = 1.2,
            DelayMultiplier = 0.65,
            Description = 'Higher material costs with faster turnaround.'
        }
    },

    OrderItems = {
        { item = Config.Items.LocksmithBlankBasicKey, label = 'Basic Blank Key Stock', price = 40, image = 'assets/locksmith_blank_basic_key.svg' },
        { item = Config.Items.EmptySmartFob, label = 'Empty Smart Fob Shells', price = 90, image = 'assets/empty_smart_fob.svg' },
        { item = Config.Items.EmptyAdvancedFob, label = 'Empty Advanced Fob Shells', price = 140, image = 'assets/empty_advanced_fob.svg' },
        { item = Config.Items.EmptyOLEDFob, label = 'Empty OLED Fob Shells', price = 220, image = 'assets/empty_oled_fob.svg' },
        { item = Config.Items.RuggedTabletParts, label = 'Rugged Tablet Parts', price = 125, image = 'assets/rugged_tablet_parts.svg' },
        { item = Config.Items.AlarmCircuitBoard, label = 'Alarm Circuit Boards', price = 175, image = 'assets/alarm_circuit_board.svg' },
        { item = Config.Items.AlarmSiren, label = 'Alarm Sirens', price = 150, image = 'assets/alarm_siren.svg' },
        { item = Config.Items.AlarmRemovalTool, label = 'Alarm Removal Tools', price = 700, image = 'assets/alarm_removal_tool.svg' },
        { item = Config.Items.TrackerCircuitBoard, label = 'Tracker Circuit Boards', price = 200, image = 'assets/tracker_circuit_board.svg' },
        { item = Config.Items.GpsAntenna, label = 'GPS Antennas', price = 175, image = 'assets/gps_antenna.svg' },
        { item = Config.Items.ValetModule, label = 'OLED Valet Modules', price = 2100, image = 'assets/valet_module.svg' },
        { item = Config.Items.SignalFinder, label = 'Signal Finders', price = 450, image = 'assets/signal_finder.png' }
    },

    -- Economy, required tools, service stock, and recipes intentionally live
    -- in accessible config files.
}
