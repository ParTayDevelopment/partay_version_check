-- [[ ParTay Keys - Internal Locksmith Recipe Defaults ]] --
-- Fallback workbench recipes used to seed/reset the in-game Recipes page.
-- Server owners should tune recipes from /locksmithadmin instead of editing
-- this internal defaults module.

PartayKeys_DefaultLocksmithRecipes = {
    {
        id = 'empty_smart_fobs',
        label = 'Assemble Empty Smart Fob Shells',
        produces = Config.Items.EmptySmartFob,
        image = 'assets/empty_smart_fob.svg',
        amount = 3,
        components = {
            { item = Config.Items.RuggedTabletParts, label = 'Fob Shell Parts', amount = 1 },
            { item = Config.Items.TrackerCircuitBoard, label = 'Microcontroller Board', amount = 1 }
        }
    },
    {
        id = 'empty_advanced_fobs',
        label = 'Assemble Empty Advanced Fob Shells',
        produces = Config.Items.EmptyAdvancedFob,
        image = 'assets/empty_advanced_fob.svg',
        amount = 2,
        components = {
            { item = Config.Items.RuggedTabletParts, label = 'Fob Shell Parts', amount = 1 },
            { item = Config.Items.TrackerCircuitBoard, label = 'Microcontroller Board', amount = 2 },
            { item = Config.Items.GpsAntenna, label = 'Signal Module', amount = 1 }
        }
    },
    {
        id = 'empty_oled_fobs',
        label = 'Assemble Empty OLED Fob Shells',
        produces = Config.Items.EmptyOLEDFob,
        image = 'assets/empty_oled_fob.svg',
        amount = 1,
        components = {
            { item = Config.Items.RuggedTabletParts, label = 'Fob Shell Parts', amount = 2 },
            { item = Config.Items.TrackerCircuitBoard, label = 'Display Controller', amount = 2 },
            { item = Config.Items.GpsAntenna, label = 'Signal Module', amount = 1 }
        }
    },
    {
        id = 'blank_smart_fobs',
        label = 'Assemble Smart Blank Fobs',
        produces = Config.Items.LocksmithBlankSmartKey,
        image = 'assets/locksmith_blank_smart_key.svg',
        amount = 1,
        components = {
            { item = Config.Items.LocksmithBlankBasicKey, label = 'Cut Basic Blank Key', amount = 1 },
            { item = Config.Items.EmptySmartFob, label = 'Empty Smart Fob Shell', amount = 1 }
        }
    },
    {
        id = 'blank_advanced_fobs',
        label = 'Assemble Advanced Blank Fobs',
        produces = Config.Items.LocksmithBlankAdvancedKey,
        image = 'assets/locksmith_blank_advanced_key.svg',
        amount = 1,
        components = {
            { item = Config.Items.LocksmithBlankBasicKey, label = 'Cut Basic Blank Key', amount = 1 },
            { item = Config.Items.EmptyAdvancedFob, label = 'Empty Advanced Fob Shell', amount = 1 }
        }
    },
    {
        id = 'blank_oled_fobs',
        label = 'Assemble OLED Blank Fobs',
        produces = Config.Items.LocksmithBlankOLEDKey,
        image = 'assets/locksmith_blank_oled_key.svg',
        amount = 1,
        components = {
            { item = Config.Items.LocksmithBlankBasicKey, label = 'Cut Basic Blank Key', amount = 1 },
            { item = Config.Items.EmptyOLEDFob, label = 'Empty OLED Fob Shell', amount = 1 }
        }
    },
    {
        id = 'basic_alarm_system',
        label = 'Assemble Basic Alarm',
        produces = Config.Items.BasicCarAlarm,
        image = 'assets/basic_car_alarm.svg',
        amount = 1,
        components = {
            { item = Config.Items.AlarmCircuitBoard, label = 'Alarm Circuit Board', amount = 1 }
        }
    },
    {
        id = 'standard_alarm_system',
        label = 'Assemble Standard Alarm',
        produces = Config.Items.CarAlarm,
        image = 'assets/car_alarm.png',
        amount = 1,
        components = {
            { item = Config.Items.AlarmCircuitBoard, label = 'Alarm Circuit Board', amount = 1 },
            { item = Config.Items.AlarmSiren, label = 'Alarm Siren', amount = 1 }
        }
    },
    {
        id = 'advanced_alarm_system',
        label = 'Assemble Advanced Alarm',
        produces = Config.Items.AdvancedCarAlarm,
        image = 'assets/advanced_car_alarm.svg',
        amount = 1,
        components = {
            { item = Config.Items.AlarmCircuitBoard, label = 'Alarm Circuit Board', amount = 2 },
            { item = Config.Items.AlarmSiren, label = 'Alarm Siren', amount = 1 },
            { item = Config.Items.TrackerCircuitBoard, label = 'Smart Security Board', amount = 1 }
        }
    },
    {
        id = 'alarm_removal_tool',
        label = 'Prepare Alarm Removal Tool',
        produces = Config.Items.AlarmRemovalTool,
        image = 'assets/alarm_removal_tool.svg',
        amount = 1,
        components = {
            { item = Config.Items.RuggedTabletParts, label = 'Tool Housing Parts', amount = 1 },
            { item = Config.Items.AlarmCircuitBoard, label = 'Bypass Interface Board', amount = 1 }
        }
    },
    {
        id = 'basic_gps_tracker',
        label = 'Assemble Basic GPS Tracker',
        produces = Config.Items.GPSTracker,
        image = 'assets/gps_tracker.png',
        amount = 1,
        components = {
            { item = Config.Items.TrackerCircuitBoard, label = 'Tracker Circuit Board', amount = 1 },
            { item = Config.Items.GpsAntenna, label = 'GPS Antenna', amount = 1 }
        }
    },
    {
        id = 'standard_gps_tracker',
        label = 'Assemble Standard GPS Tracker',
        produces = Config.Items.StandardGPSTracker,
        image = 'assets/standard_gps_tracker.svg',
        amount = 1,
        components = {
            { item = Config.Items.TrackerCircuitBoard, label = 'Tracker Circuit Board', amount = 1 },
            { item = Config.Items.GpsAntenna, label = 'GPS Antenna', amount = 2 }
        }
    },
    {
        id = 'advanced_gps_tracker',
        label = 'Assemble Advanced GPS Tracker',
        produces = Config.Items.AdvancedGPSTracker,
        image = 'assets/advanced_gps_tracker.svg',
        amount = 1,
        components = {
            { item = Config.Items.TrackerCircuitBoard, label = 'Tracker Circuit Board', amount = 2 },
            { item = Config.Items.GpsAntenna, label = 'GPS Antenna', amount = 2 },
            { item = Config.Items.RuggedTabletParts, label = 'Signal Housing Parts', amount = 1 }
        }
    },
    {
        id = 'gps_tablet',
        label = 'Prepare GPS Tablet',
        produces = Config.Items.GPSTablet,
        amount = 1,
        components = {
            { item = Config.Items.RuggedTabletParts, label = 'Rugged Tablet Parts', amount = 1 },
            { item = Config.Items.GpsAntenna, label = 'GPS Antenna', amount = 1 }
        }
    },
    {
        id = 'valet_module',
        label = 'Assemble OLED Valet Module',
        produces = Config.Items.ValetModule,
        amount = 1,
        components = {
            { item = Config.Items.TrackerCircuitBoard, label = 'Control Board', amount = 2 },
            { item = Config.Items.GpsAntenna, label = 'Short Range Receiver', amount = 1 },
            { item = Config.Items.RuggedTabletParts, label = 'Module Housing Parts', amount = 1 }
        }
    },
    {
        id = 'signal_finder',
        label = 'Assemble Signal Finder',
        produces = Config.Items.SignalFinder,
        image = 'assets/signal_finder.png',
        amount = 1,
        components = {
            { item = Config.Items.RuggedTabletParts, label = 'Signal Housing Parts', amount = 1 },
            { item = Config.Items.TrackerCircuitBoard, label = 'Scanner Board', amount = 1 },
            { item = Config.Items.GpsAntenna, label = 'Directional Antenna', amount = 1 }
        }
    }
}

function PartayKeys_GetDefaultLocksmithRecipes()
    return PartayKeys_DefaultLocksmithRecipes or {}
end
