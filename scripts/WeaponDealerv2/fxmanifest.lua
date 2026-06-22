
fx_version 'cerulean'
game 'gta5'

name 'weaponsdealer'
description 'Legal weapon dealer registration workflow.'
version '1.0.2'
author "LoadedxDiaper"
website "https://partay.tebex.io/"
discord "https://discord.gg/partaystudios"

lua54 'yes'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/init.lua',
    'locales/en.lua',
    'config/config.lua',
    'config/weapons.lua'
}

client_scripts {
    'client/framework.lua',
    'client/notifications.lua',
    'client/zones.lua',
    'client/tablet.lua',
    'client/assembly.lua',
    'client/preview.lua',
    'client/damage.lua',
    'client/nui.lua',
    'client/targets.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server/framework.lua',
    'bridge/server/inventory.lua',
    'bridge/server/license.lua',
    'bridge/server/tablet.lua',
    'bridge/server/phone.lua',
    'bridge/server/banking.lua',
    'server/logs.lua',
    'server/main.lua',
    'server/hooks.lua',
    'server/profiles.lua',
    'server/tradeins.lua',
    'server/quotes.lua',
    'server/accessories.lua',
    'server/melee.lua',
    'server/assembly.lua',
    'server/parts.lua',
    'server/preview.lua',
    'server/scans.lua',
    'server/orders.lua',
    'server/pickups.lua'
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql',
    'cs_license'
}
