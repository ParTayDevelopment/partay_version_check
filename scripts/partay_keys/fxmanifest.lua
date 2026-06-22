fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'ParTay Keys - Advanced Vehicle Access System'
version '1.0.0'
author 'ParTay Studios'

provide 'qbx_vehiclekeys'
provide 'qb-vehiclekeys'
provide 'vehiclekeys'
provide 'esx_vehiclelock'
provide 'esx_vehiclekeys'

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_target'
}

client_exports {
    'DisplayKey',
    'UseGpsTabletItem',
    'UseSignalFinderItem',
    'HasKeys',
    'GiveKeys',
    'RemoveKeys'
}

server_exports {
    'AdminSpawnVehicle',
    'AssertCanParkVehicle',
    'AssertCanRetrieveVehicle',
    'CanParkVehicle',
    'CanRetrieveVehicle',
    'CanVehicleBeSold',
    'GiveKeys',
    'GetDealershipProvider',
    'GetDispatchProvider',
    'GetPhoneProvider',
    'GetGarageProvider',
    'GetRegisteredDealershipEvents',
    'HasKeys',
    'NotifyGarageBlocked',
    'RegisterVehiclePurchase',
    'RemoveKeys',
    'RegisterLocksmithPhoneHandler',
    'SendLocksmithPhoneMessage',
    'SetLockState',
    'SyncSpawnedVehicleState',
    'SendPoliceAlert',
    'useAlarmRemovalToolItem',
    'useAdvancedSmartVehicleKeyItem',
    'useBasicVehicleKeyItem',
    'useBlankKeyItem',
    'useCarAlarmItem',
    'useDecoderItem',
    'useGpsTabletItem',
    'useGpsTrackerItem',
    'useHotwireItem',
    'useKeyItem',
    'useLocksmithEmployeeTabletItem',
    'useLocksmithOwnerTabletItem',
    'useLockpickItem',
    'useValetModuleItem',
    'useSignalFinderItem',
    'useOLEDVehicleKeyItem',
    'useSaleContractItem',
    'useSmartVehicleKeyItem',
    'usePartayItem',
    'WipeVehicleData'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/props.lua',
    'modules/recipes.lua',
    'modules/player_jobs.lua',
    'modules/service_peds.lua',
    'config/integrations.lua',
    'config/key_tiers.lua',
    'config/theft_security.lua',
    'config/ui.lua',
    'config/minigames.lua',
    'config/locksmith_business.lua',
    'config/logging.lua',
    'modules/key_tiers.lua',
    'modules/alarm_tiers.lua',
    'modules/gps_tiers.lua',
    'shared/notify.lua',
    'shared/minigames.lua',
    'shared/animations.lua'
}

client_scripts {
    'bridge/framework.lua',
    'client/admin_cl.lua',
    'client/main.lua',
    'client/interactions.lua',
    'client/heist.lua',
    'client/peds.lua',
    'client/security.lua',
    'client/fob.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/framework.lua',
    'bridge/admin_bridge.lua',
    'bridge/garage_bridge.lua',
    'bridge/dealership_bridge.lua',
    'server/helpers.lua',
    'server/logging.lua',
    'server/dispatch.lua',
    'server/phone.lua',
    'server/admin_sv.lua',
    'server/main.lua',
    'server/heist_sv.lua',
    'server/security_sv.lua',
    'server/exports.lua'
}

ui_page 'html/index.html'

data_file 'DLC_ITYP_REQUEST' 'stream/bzzz_prop_payment_terminal.ytyp'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/assets/*.png',
    'html/assets/*.svg',
    'installation/items/*.png',
    'installation/items/*.svg',
    'locales/*.json',
    'stream/*.ydr',
    'stream/*.ytyp'
}

escrow_ignore {
    'config.lua',
    'README.md',
    'fxmanifest.lua',
    'config/*',
    'config/**/*',
    'html/*',
    'html/**/*',
    'installation/*',
    'installation/**/*',
    'bridge/*',
    'bridge/**/*',
    'locales/*',
    'locales/**/*',
    'shared/*',
    'shared/**/*'
}
