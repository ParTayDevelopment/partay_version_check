-- [[ ParTay Handheld Props ]] --
-- Disable or adjust these props without editing client logic.

Props = Props or {}

Props.Handheld = {
    Enabled = true,

    Fob = {
        Enabled = true,
        Model = 'p_car_keys_01',
        Bone = 57005,
        Pos = vector3(0.12, 0.02, -0.02),
        Rot = vector3(80.0, 160.0, 20.0)
    },

    Tablet = {
        Enabled = true,
        Model = 'prop_cs_tablet',
        Bone = 60309,
        Pos = vector3(0.03, 0.002, -0.02),
        Rot = vector3(10.0, 160.0, 0.0),
        Animation = 'TabletHold'
    },

    Clipboard = {
        Enabled = true,
        Model = 'p_amb_clipboard_01',
        Bone = 57005,
        Pos = vector3(0.16, 0.02, -0.02),
        Rot = vector3(80.0, 160.0, 20.0),
        Animation = 'ClipboardHold'
    },

    Decoder = {
        Enabled = true,
        Model = 'prop_cs_tablet',
        Bone = 60309,
        Pos = vector3(0.03, 0.002, -0.02),
        Rot = vector3(10.0, 160.0, 0.0)
    },

    Terminal = {
        Enabled = true,
        Model = 'bzzz_prop_payment_terminal',
        Bone = 57005,
        Pos = vector3(0.12, 0.04, -0.02),
        Rot = vector3(65.0, 160.0, 10.0),
        Animation = 'TerminalHold'
    }
}

Props.Locksmith = Props.Locksmith or {}

-- Default models used by in-game locksmith setup. Runtime locations can still
-- be placed and changed in /locksmithadmin; these are the initial defaults.
Props.Locksmith.Setup = Props.Locksmith.Setup or {
    Workbench = 'prop_tool_bench02',
    Management = 'prop_monitor_w_large',
    Timeclock = 'prop_time_clock',
    Register = 'prop_till_01',
    CustomerPickup = 'prop_cs_cardbox_01',
    Stock = 'prop_boxpile_06b',
    StatusSign = 'prop_noticeboard_01',
    SelfServicePed = 's_m_m_highsec_01',
    Garage = 'prop_parkingpay',
    GarageVehiclePreview = 'speedo'
}

Props.Locksmith.Stocking = Props.Locksmith.Stocking or {
    StockBox = {
        Model = 'prop_cardbordbox_04a',
        Bone = 28422,
        Pos = vector3(0.0, -0.03, -0.08),
        Rot = vector3(5.0, 0.0, 0.0),
        Animation = 'LocksmithStockBox'
    },
    DeliveryTruck = 'boxville2',
    DeliveryPed = 's_m_m_dockwork_01',
    WarehousePed = 's_m_m_warehouse_01',
    CustomerOrderPickup = 'prop_cs_cardbox_01'
}

Props.Locksmith.Garage = Props.Locksmith.Garage or {
    ServiceVehicles = {
        { label = 'Service Van', model = 'speedo' },
        { label = 'Utility Pickup', model = 'bison' }
    }
}
