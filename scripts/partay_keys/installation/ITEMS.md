# ParTay Keys Item Setup

Item names are configured in `config.lua` under `Config.Items`. If you rename an item here, update both `config.lua` and your inventory item definition.

Metadata support is required for full physical key behavior. Inventories that do not preserve item metadata can still run basic usable items, but physical vehicle keys, cloned keys, shared keys, and key versions will not behave correctly. With `Config.DebugMode = true`, ParTay Keys warns when metadata is missing where it is required.

## Item Images

Starter images are included in `installation/items/`. Core release icons are PNG files; locksmith business icons are SVG files for crisp tablet/workbench UI scaling. Copy the files your inventory supports into your inventory image folder, then replace them with your own server art whenever you want.

Included filenames:

basic_vehicle_key.png
smart_vehicle_key.png
advanced_smart_vehicle_key.png
oled_vehicle_key.png
lockpick.png
wiring_kit.png
electronic_decoder.png
blank_key.png
sale_contract.png
basic_car_alarm.svg
car_alarm.png
advanced_car_alarm.svg
alarm_removal_tool.svg
gps_tracker.png
standard_gps_tracker.svg
advanced_gps_tracker.svg
valet_module.svg
gps_tablet.png
signal_finder.png
locksmith_employee_tablet.svg
locksmith_owner_tablet.svg
legal_key_imprinter.svg
locksmith_blank_basic_key.svg
locksmith_blank_smart_key.svg
locksmith_blank_advanced_key.svg
locksmith_blank_oled_key.svg
empty_smart_fob.svg
empty_advanced_fob.svg
empty_oled_fob.svg
alarm_circuit_board.svg
alarm_siren.svg
tracker_circuit_board.svg
gps_antenna.svg
rugged_tablet_parts.svg

## ox_inventory

Path:

resources/[ox]/ox_inventory/data/items.lua

Add these entries inside the returned item table:

Smart, advanced smart, and OLED keys include an ox_inventory right-click `Display Key` button. Normal item use still opens the active key fob; using the same key again puts it away.

```lua
['basic_vehicle_key'] = {
    label = 'Basic Vehicle Key',
    weight = 10,
    stack = false,
    close = true,
    consume = 0,
    description = 'A basic physical key for locking and unlocking a vehicle.',
    server = { export = 'partay_keys.useBasicVehicleKeyItem' }
},

['smart_vehicle_key'] = {
    label = 'Smart Vehicle Key',
    weight = 10,
    stack = false,
    close = true,
    consume = 0,
    description = 'A smart key fob for remote vehicle functions.',
    client = { export = 'partay_keys.DisplayKey' },
    buttons = {
        {
            label = 'Display Key',
            action = function(slot)
                exports.partay_keys:DisplayKey(slot)
            end
        }
    },
    server = { export = 'partay_keys.useSmartVehicleKeyItem' }
},

['advanced_smart_vehicle_key'] = {
    label = 'Advanced Smart Vehicle Key',
    weight = 10,
    stack = false,
    close = true,
    consume = 0,
    description = 'An advanced smart key with remote engine support.',
    client = { export = 'partay_keys.DisplayKey' },
    buttons = {
        {
            label = 'Display Key',
            action = function(slot)
                exports.partay_keys:DisplayKey(slot)
            end
        }
    },
    server = { export = 'partay_keys.useAdvancedSmartVehicleKeyItem' }
},

['oled_vehicle_key'] = {
    label = 'OLED Vehicle Key',
    weight = 10,
    stack = false,
    close = true,
    consume = 0,
    description = 'A premium OLED vehicle key system.',
    client = { export = 'partay_keys.DisplayKey' },
    buttons = {
        {
            label = 'Display Key',
            action = function(slot)
                exports.partay_keys:DisplayKey(slot)
            end
        }
    },
    server = { export = 'partay_keys.useOLEDVehicleKeyItem' }
},

['lockpick'] = {
    label = 'Lockpick',
    weight = 50,
    stack = true,
    close = true,
    consume = 0,
    description = 'A standard tool for forcing locks.',
    server = { export = 'partay_keys.useLockpickItem' }
},

['wiring_kit'] = {
    label = 'Wiring Kit',
    weight = 100,
    stack = true,
    close = true,
    consume = 0,
    description = 'Used to bypass standard ignitions.',
    server = { export = 'partay_keys.useHotwireItem' }
},

['electronic_decoder'] = {
    label = 'Electronic Decoder',
    weight = 500,
    stack = false,
    close = true,
    consume = 0,
    description = 'A device used to decode vehicle security data.',
    server = { export = 'partay_keys.useDecoderItem' }
},

['blank_key'] = {
    label = 'Blank Key Fob',
    weight = 10,
    stack = true,
    close = true,
    consume = 0,
    description = 'A blank fob ready to accept cloned vehicle data.',
    server = { export = 'partay_keys.useBlankKeyItem' }
},

['sale_contract'] = {
    label = 'Vehicle Sale Contract',
    weight = 50,
    stack = true,
    close = true,
    consume = 0,
    description = 'A blackmarket contract for transferring stolen vehicle possession.',
    server = { export = 'partay_keys.useSaleContractItem' }
},

['basic_car_alarm'] = {
    label = 'Basic Car Alarm',
    weight = 1000,
    stack = false,
    close = true,
    consume = 0,
    description = 'Entry-level alarm hardware for core theft and damage response.',
    server = { export = 'partay_keys.useCarAlarmItem' }
},

['car_alarm'] = {
    label = 'Standard Car Alarm',
    weight = 1000,
    stack = false,
    close = true,
    consume = 0,
    description = 'A standard aftermarket alarm system with balanced theft response.',
    server = { export = 'partay_keys.useCarAlarmItem' }
},

['advanced_car_alarm'] = {
    label = 'Advanced Car Alarm',
    weight = 1000,
    stack = false,
    close = true,
    consume = 0,
    description = 'Premium alarm hardware prepared for expanded smart security features.',
    server = { export = 'partay_keys.useCarAlarmItem' }
},

['alarm_removal_tool'] = {
    label = 'Alarm Removal Tool',
    weight = 600,
    stack = false,
    close = true,
    consume = 0,
    description = 'Reusable tool for removing installed vehicle alarms before upgrades.',
    server = { export = 'partay_keys.useAlarmRemovalToolItem' }
},

['gps_tracker'] = {
    label = 'Basic GPS Tracker',
    weight = 200,
    stack = false,
    close = true,
    consume = 0,
    description = 'A basic magnetic GPS tracking unit.',
    server = { export = 'partay_keys.useGpsTrackerItem' }
},

['standard_gps_tracker'] = {
    label = 'Standard GPS Tracker',
    weight = 200,
    stack = false,
    close = true,
    consume = 0,
    description = 'Improved tracker hardware with tighter pings and better signal resolution.',
    server = { export = 'partay_keys.useGpsTrackerItem' }
},

['advanced_gps_tracker'] = {
    label = 'Advanced GPS Tracker',
    weight = 200,
    stack = false,
    close = true,
    consume = 0,
    description = 'Premium tracker hardware prepared for expanded smart tracking features.',
    server = { export = 'partay_keys.useGpsTrackerItem' }
},

['valet_module'] = {
    label = 'OLED Valet Module',
    weight = 400,
    stack = false,
    close = true,
    consume = 0,
    description = 'Vehicle-side module required for OLED key valet call-in.',
    server = { export = 'partay_keys.useValetModuleItem' }
},

['gps_tablet'] = {
    label = 'GPS Tracking Tablet',
    weight = 800,
    stack = false,
    close = true,
    consume = 0,
    description = 'A tablet loaded with tracking software.',
    client = { export = 'partay_keys.UseGpsTabletItem' },
    server = { export = 'partay_keys.useGpsTabletItem' }
},

['signal_finder'] = {
    label = 'Signal Finder',
    weight = 500,
    stack = false,
    close = true,
    consume = 0,
    description = 'A handheld scanner for detecting hidden vehicle tracker signals.',
    client = { export = 'partay_keys.UseSignalFinderItem' },
    server = { export = 'partay_keys.useSignalFinderItem' }
},

['locksmith_employee_tablet'] = {
    label = 'Locksmith Service Tablet',
    weight = 800,
    stack = false,
    close = true,
    consume = 0,
    description = 'Employee tablet for creating locksmith jobs and customer invoices.',
    server = { export = 'partay_keys.useLocksmithEmployeeTabletItem' }
},

['locksmith_owner_tablet'] = {
    label = 'Locksmith Owner Tablet',
    weight = 800,
    stack = false,
    close = true,
    consume = 0,
    description = 'Owner tablet for managing locksmith business stock and operations.',
    server = { export = 'partay_keys.useLocksmithOwnerTabletItem' }
},

['legal_key_imprinter'] = {
    label = 'Legal Key Imprinter',
    weight = 750,
    stack = false,
    close = true,
    consume = 0,
    description = 'Certified locksmith tool used for imprinting and servicing legal vehicle keys.'
},

['locksmith_blank_basic_key'] = {
    label = 'Basic Locksmith Blank Key',
    weight = 10,
    stack = true,
    close = true,
    consume = 0,
    description = 'Legal blank key stock for basic key systems.'
},

['locksmith_blank_smart_key'] = {
    label = 'Smart Locksmith Blank Fob',
    weight = 10,
    stack = true,
    close = true,
    consume = 0,
    description = 'Legal smart fob stock assembled from an empty shell and cut key blade.'
},

['locksmith_blank_advanced_key'] = {
    label = 'Advanced Locksmith Blank Fob',
    weight = 10,
    stack = true,
    close = true,
    consume = 0,
    description = 'Legal advanced fob stock assembled from an empty shell and cut key blade.'
},

['locksmith_blank_oled_key'] = {
    label = 'OLED Locksmith Blank Fob',
    weight = 10,
    stack = true,
    close = true,
    consume = 0,
    description = 'Legal OLED fob stock assembled from an empty shell and cut key blade.'
},

['empty_smart_fob'] = {
    label = 'Empty Smart Fob Shell',
    weight = 50,
    stack = true,
    close = true,
    consume = 0,
    description = 'Unprogrammed smart fob shell used by locksmith workbench recipes.'
},

['empty_advanced_fob'] = {
    label = 'Empty Advanced Fob Shell',
    weight = 60,
    stack = true,
    close = true,
    consume = 0,
    description = 'Unprogrammed advanced fob shell used by locksmith workbench recipes.'
},

['empty_oled_fob'] = {
    label = 'Empty OLED Fob Shell',
    weight = 75,
    stack = true,
    close = true,
    consume = 0,
    description = 'Unprogrammed OLED fob shell used by locksmith workbench recipes.'
},

['alarm_circuit_board'] = {
    label = 'Alarm Circuit Board',
    weight = 100,
    stack = true,
    close = true,
    consume = 0,
    description = 'Component used to assemble alarm system stock.'
},

['alarm_siren'] = {
    label = 'Alarm Siren',
    weight = 300,
    stack = true,
    close = true,
    consume = 0,
    description = 'Component used to assemble alarm system stock.'
},

['tracker_circuit_board'] = {
    label = 'Tracker Circuit Board',
    weight = 100,
    stack = true,
    close = true,
    consume = 0,
    description = 'Component used to assemble GPS tracker stock.'
},

['gps_antenna'] = {
    label = 'GPS Antenna',
    weight = 100,
    stack = true,
    close = true,
    consume = 0,
    description = 'Component used to assemble GPS-enabled locksmith stock.'
},

['rugged_tablet_parts'] = {
    label = 'Rugged Tablet Parts',
    weight = 500,
    stack = true,
    close = true,
    consume = 0,
    description = 'Component stock used for locksmith tablets and blank-key batches.'
},
```

## qb-inventory / QBCore Shared Items

Path:

resources/[qb]/qb-core/shared/items.lua

Some servers keep shared items in a different QBCore path. Add these entries wherever your server defines `QBShared.Items`.

```lua
['basic_vehicle_key'] = {
    ['name'] = 'basic_vehicle_key',
    ['label'] = 'Basic Vehicle Key',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'basic_vehicle_key.png',
    ['unique'] = true,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A basic physical key for locking and unlocking a vehicle.'
},

['smart_vehicle_key'] = {
    ['name'] = 'smart_vehicle_key',
    ['label'] = 'Smart Vehicle Key',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'smart_vehicle_key.png',
    ['unique'] = true,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A smart key fob for remote vehicle functions.'
},

['advanced_smart_vehicle_key'] = {
    ['name'] = 'advanced_smart_vehicle_key',
    ['label'] = 'Advanced Smart Vehicle Key',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'advanced_smart_vehicle_key.png',
    ['unique'] = true,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'An advanced smart key with remote engine support.'
},

['oled_vehicle_key'] = {
    ['name'] = 'oled_vehicle_key',
    ['label'] = 'OLED Vehicle Key',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'oled_vehicle_key.png',
    ['unique'] = true,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A premium OLED vehicle key system.'
},

['lockpick'] = {
    ['name'] = 'lockpick',
    ['label'] = 'Lockpick',
    ['weight'] = 50,
    ['type'] = 'item',
    ['image'] = 'lockpick.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A standard tool for forcing locks.'
},

['wiring_kit'] = {
    ['name'] = 'wiring_kit',
    ['label'] = 'Wiring Kit',
    ['weight'] = 100,
    ['type'] = 'item',
    ['image'] = 'wiring_kit.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Used to bypass standard ignitions.'
},

['electronic_decoder'] = {
    ['name'] = 'electronic_decoder',
    ['label'] = 'Electronic Decoder',
    ['weight'] = 500,
    ['type'] = 'item',
    ['image'] = 'electronic_decoder.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A device used to decode vehicle security data.'
},

['blank_key'] = {
    ['name'] = 'blank_key',
    ['label'] = 'Blank Key Fob',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'blank_key.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A blank fob ready to accept cloned vehicle data.'
},

['sale_contract'] = {
    ['name'] = 'sale_contract',
    ['label'] = 'Vehicle Sale Contract',
    ['weight'] = 50,
    ['type'] = 'item',
    ['image'] = 'sale_contract.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A blackmarket contract for transferring stolen vehicle possession.'
},

['basic_car_alarm'] = {
    ['name'] = 'basic_car_alarm',
    ['label'] = 'Basic Car Alarm',
    ['weight'] = 1000,
    ['type'] = 'item',
    ['image'] = 'basic_car_alarm.svg',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Entry-level alarm hardware for core theft and damage response.'
},

['car_alarm'] = {
    ['name'] = 'car_alarm',
    ['label'] = 'Standard Car Alarm',
    ['weight'] = 1000,
    ['type'] = 'item',
    ['image'] = 'car_alarm.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A standard aftermarket alarm system with balanced theft response.'
},

['advanced_car_alarm'] = {
    ['name'] = 'advanced_car_alarm',
    ['label'] = 'Advanced Car Alarm',
    ['weight'] = 1000,
    ['type'] = 'item',
    ['image'] = 'advanced_car_alarm.svg',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Premium alarm hardware prepared for expanded smart security features.'
},

['alarm_removal_tool'] = {
    ['name'] = 'alarm_removal_tool',
    ['label'] = 'Alarm Removal Tool',
    ['weight'] = 600,
    ['type'] = 'item',
    ['image'] = 'alarm_removal_tool.svg',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Reusable tool for removing installed vehicle alarms before upgrades.'
},

['gps_tracker'] = {
    ['name'] = 'gps_tracker',
    ['label'] = 'Basic GPS Tracker',
    ['weight'] = 200,
    ['type'] = 'item',
    ['image'] = 'gps_tracker.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A basic magnetic GPS tracking unit.'
},

['standard_gps_tracker'] = {
    ['name'] = 'standard_gps_tracker',
    ['label'] = 'Standard GPS Tracker',
    ['weight'] = 200,
    ['type'] = 'item',
    ['image'] = 'standard_gps_tracker.svg',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Improved tracker hardware with tighter pings and better signal resolution.'
},

['advanced_gps_tracker'] = {
    ['name'] = 'advanced_gps_tracker',
    ['label'] = 'Advanced GPS Tracker',
    ['weight'] = 200,
    ['type'] = 'item',
    ['image'] = 'advanced_gps_tracker.svg',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Premium tracker hardware prepared for expanded smart tracking features.'
},

['valet_module'] = {
    ['name'] = 'valet_module',
    ['label'] = 'OLED Valet Module',
    ['weight'] = 400,
    ['type'] = 'item',
    ['image'] = 'valet_module.svg',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Vehicle-side module required for OLED key valet call-in.'
},

['gps_tablet'] = {
    ['name'] = 'gps_tablet',
    ['label'] = 'GPS Tracking Tablet',
    ['weight'] = 800,
    ['type'] = 'item',
    ['image'] = 'gps_tablet.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A tablet loaded with tracking software.'
},

['signal_finder'] = {
    ['name'] = 'signal_finder',
    ['label'] = 'Signal Finder',
    ['weight'] = 500,
    ['type'] = 'item',
    ['image'] = 'signal_finder.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A handheld scanner for detecting hidden vehicle tracker signals.'
},

['locksmith_employee_tablet'] = {
    ['name'] = 'locksmith_employee_tablet',
    ['label'] = 'Locksmith Service Tablet',
    ['weight'] = 800,
    ['type'] = 'item',
    ['image'] = 'locksmith_employee_tablet.svg',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Employee tablet used to create locksmith jobs and invoices.'
},

['locksmith_owner_tablet'] = {
    ['name'] = 'locksmith_owner_tablet',
    ['label'] = 'Locksmith Owner Tablet',
    ['weight'] = 800,
    ['type'] = 'item',
    ['image'] = 'locksmith_owner_tablet.svg',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Owner tablet used to manage locksmith stock, prices, employees, and reports.'
},

['legal_key_imprinter'] = {
    ['name'] = 'legal_key_imprinter',
    ['label'] = 'Legal Key Imprinter',
    ['weight'] = 1000,
    ['type'] = 'item',
    ['image'] = 'legal_key_imprinter.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Certified locksmith tool used for imprinting and servicing legal vehicle keys.'
},

['locksmith_blank_basic_key'] = {
    ['name'] = 'locksmith_blank_basic_key',
    ['label'] = 'Basic Locksmith Blank Key',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'locksmith_blank_basic_key.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Legal blank key stock for basic key systems.'
},

['locksmith_blank_smart_key'] = {
    ['name'] = 'locksmith_blank_smart_key',
    ['label'] = 'Smart Locksmith Blank Fob',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'locksmith_blank_smart_key.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Legal smart fob stock assembled from an empty shell and cut key blade.'
},

['locksmith_blank_advanced_key'] = {
    ['name'] = 'locksmith_blank_advanced_key',
    ['label'] = 'Advanced Locksmith Blank Fob',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'locksmith_blank_advanced_key.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Legal advanced fob stock assembled from an empty shell and cut key blade.'
},

['locksmith_blank_oled_key'] = {
    ['name'] = 'locksmith_blank_oled_key',
    ['label'] = 'OLED Locksmith Blank Fob',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'locksmith_blank_oled_key.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Legal OLED fob stock assembled from an empty shell and cut key blade.'
},

['empty_smart_fob'] = {
    ['name'] = 'empty_smart_fob',
    ['label'] = 'Empty Smart Fob Shell',
    ['weight'] = 50,
    ['type'] = 'item',
    ['image'] = 'empty_smart_fob.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Unprogrammed smart fob shell used by locksmith workbench recipes.'
},

['empty_advanced_fob'] = {
    ['name'] = 'empty_advanced_fob',
    ['label'] = 'Empty Advanced Fob Shell',
    ['weight'] = 60,
    ['type'] = 'item',
    ['image'] = 'empty_advanced_fob.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Unprogrammed advanced fob shell used by locksmith workbench recipes.'
},

['empty_oled_fob'] = {
    ['name'] = 'empty_oled_fob',
    ['label'] = 'Empty OLED Fob Shell',
    ['weight'] = 75,
    ['type'] = 'item',
    ['image'] = 'empty_oled_fob.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Unprogrammed OLED fob shell used by locksmith workbench recipes.'
},

['alarm_circuit_board'] = {
    ['name'] = 'alarm_circuit_board',
    ['label'] = 'Alarm Circuit Board',
    ['weight'] = 100,
    ['type'] = 'item',
    ['image'] = 'alarm_circuit_board.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Component used to assemble alarm systems.'
},

['alarm_siren'] = {
    ['name'] = 'alarm_siren',
    ['label'] = 'Alarm Siren',
    ['weight'] = 250,
    ['type'] = 'item',
    ['image'] = 'alarm_siren.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Component used to assemble alarm systems.'
},

['tracker_circuit_board'] = {
    ['name'] = 'tracker_circuit_board',
    ['label'] = 'Tracker Circuit Board',
    ['weight'] = 100,
    ['type'] = 'item',
    ['image'] = 'tracker_circuit_board.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Component used to assemble GPS-enabled locksmith stock.'
},

['gps_antenna'] = {
    ['name'] = 'gps_antenna',
    ['label'] = 'GPS Antenna',
    ['weight'] = 100,
    ['type'] = 'item',
    ['image'] = 'gps_antenna.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Component used to assemble GPS-enabled locksmith stock.'
},

['rugged_tablet_parts'] = {
    ['name'] = 'rugged_tablet_parts',
    ['label'] = 'Rugged Tablet Parts',
    ['weight'] = 500,
    ['type'] = 'item',
    ['image'] = 'rugged_tablet_parts.svg',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Component stock used for locksmith tablets, fob shells, and blank-key batches.'
},
```

ParTay Keys registers these QBCore/Qbox items as usable automatically when `qb-core` or `qbx_core` is running.

## ps-inventory

Path:

resources/[ps]/ps-inventory/shared/items.lua

Most ps-inventory installs use QBCore-style shared item definitions. Use the `qb-inventory / QBCore Shared Items` snippet above, then confirm your ps-inventory build preserves item `info` metadata.

## qs-inventory

Common paths:

resources/[qs]/qs-inventory/shared/items.lua
resources/[qs]/qs-inventory/config/items.lua

qs-inventory item file layouts vary by release. Add the same item names from `Config.Items`, mark all vehicle key items as unique/non-stackable, and make sure metadata is preserved when items are added.

ParTay Keys can grant metadata keys through `qs-inventory` with:

```lua
exports['qs-inventory']:AddItem(source, itemName, amount, nil, metadata)
```

If your qs-inventory build requires custom usable item registration, route item use to the matching server exports listed in the `ox_inventory` section.
