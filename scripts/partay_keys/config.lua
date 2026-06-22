Config = {}

-- ==========================================
-- [[ PRIMARY CONFIG ]]
-- ==========================================
-- Debug should stay true during installation so missing dependencies and config mistakes are visible.
-- For production, set this false once the resource is fully tested.
Config.DebugMode = true
Config.Locale = 'en'

-- Main integrations. Detailed provider data lives in config/integrations.lua.
-- Keep these on 'auto' unless you need to force a specific supported integration.
Config.NotificationProvider = 'ox_lib'
Config.MinigameProvider = 'ox_lib'
Config.DealershipProvider = 'auto'

-- ==========================================
-- [[ CORE KEY SYSTEM ]]
-- ==========================================
-- true: players must carry a valid physical key item for normal vehicle actions.
-- false: ownership/shared database access is enough, but theft can still use temporary access.
Config.RequirePhysicalKey = true

-- Maximum active shared keys per vehicle version. Rekeying invalidates old shared keys.
Config.SharedKeysLimit = 3

-- PENDING FEATURE: planned support for illegally copying shared keys through the decoder flow.
-- This toggle is documented for roadmap visibility but is not active in 1.0.0.
Config.AllowSharedKeyDecoderCopy = false

-- Days to keep inactive/old key ledger rows before cleanup can remove them.
Config.KeyHistoryRetentionDays = 30

-- Maximum distance for direct key handoffs and shared-key interactions.
Config.KeyHandoffRadius = 3.0

-- Item names used by inventory integrations.
-- If you rename these, update your inventory item definitions to match.
Config.Items = {
    BasicVehicleKey = 'basic_vehicle_key',
    SmartVehicleKey = 'smart_vehicle_key',
    AdvancedSmartVehicleKey = 'advanced_smart_vehicle_key',
    OLEDVehicleKey = 'oled_vehicle_key',
    Lockpick = 'lockpick',
    WiringKit = 'wiring_kit',
    ElectronicDecoder = 'electronic_decoder',
    BlankKey = 'blank_key',
    SaleContract = 'sale_contract',
    BasicCarAlarm = 'basic_car_alarm',
    CarAlarm = 'car_alarm',
    AdvancedCarAlarm = 'advanced_car_alarm',
    AlarmRemovalTool = 'alarm_removal_tool',
    GPSTracker = 'gps_tracker',
    StandardGPSTracker = 'standard_gps_tracker',
    AdvancedGPSTracker = 'advanced_gps_tracker',
    GPSTablet = 'gps_tablet',
    SignalFinder = 'signal_finder',
    LocksmithEmployeeTablet = 'locksmith_employee_tablet',
    LocksmithOwnerTablet = 'locksmith_owner_tablet',
    LegalKeyImprinter = 'legal_key_imprinter',
    LocksmithBlankBasicKey = 'locksmith_blank_basic_key',
    LocksmithBlankSmartKey = 'locksmith_blank_smart_key',
    LocksmithBlankAdvancedKey = 'locksmith_blank_advanced_key',
    LocksmithBlankOLEDKey = 'locksmith_blank_oled_key',
    EmptySmartFob = 'empty_smart_fob',
    EmptyAdvancedFob = 'empty_advanced_fob',
    EmptyOLEDFob = 'empty_oled_fob',
    AlarmCircuitBoard = 'alarm_circuit_board',
    AlarmSiren = 'alarm_siren',
    TrackerCircuitBoard = 'tracker_circuit_board',
    GpsAntenna = 'gps_antenna',
    RuggedTabletParts = 'rugged_tablet_parts',
    ValetModule = 'valet_module'
}

-- Runtime aliases used by the bridge and compatibility exports.
Config.KeyItemName = Config.Items.SmartVehicleKey

-- ==========================================
-- [[ COMMANDS & HOTKEYS ]]
-- ==========================================
Config.LockHotkey = 'U'
Config.EngineHotkey = 'G'
Config.FobCommand = 'keyfob'
Config.KeyMenuCommand = 'keys'

-- true: tapping exit turns the engine off, holding exit leaves it running.
Config.LeaveEngineRunning = true
Config.LeaveEngineRunningHoldTime = 650

-- ==========================================
-- [[ ADMIN VEHICLE REGISTRATION ]]
-- ==========================================
-- Admin groups that can use admin key tools and receive temporary access for spawned vehicles.
Config.AdminGroup = {'group.admin', 'group.god'}

-- true: /givekeys can permanently register/save admin-spawned vehicles when appropriate.
Config.AdminPermanentSave = true
Config.AdminGiveKeysCommand = 'givekeys'
Config.AdminGiveKeysCooldown = 30

-- ==========================================
-- [[ PLAYER-RUN LOCKSMITH ]]
-- ==========================================
-- true: enables employee/owner locksmith business systems, stock, invoices, and setup locations.
-- false: keeps the resource in NPC/self-service locksmith mode.
Config.EnablePlayerRunLocksmith = true

-- In-game setup for placing locksmith business points inside MLOs.
-- /locksmithadmin: full admin setup for creating, deleting, and assigning shops.
-- /locksmithowner: scoped owner setup for tuning only the shop assigned to their job.
Config.LocksmithSetupEnabled = true
Config.LocksmithSetupAdminCommand = 'locksmithadmin'
Config.LocksmithSetupOwnerCommand = 'locksmithowner'

-- Who can use /locksmithadmin and save/finalize protected business points.
-- AcePermission lets owners grant setup access without giving full admin tools:
-- add_ace group.admin partay_keys.locksmithsetup allow
Config.LocksmithSetupPermission = {
    AcePermission = 'partay_keys.locksmithsetup',
    Groups = Config.AdminGroup,
    AllowCommandCar = true
}
