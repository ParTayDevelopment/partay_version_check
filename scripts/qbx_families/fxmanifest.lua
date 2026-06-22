fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbx_families'
description 'Family RP system for Qbox'
version '1.0.0'
author 'Partay Studios'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/CircleZone.lua',
    'client/main.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'PolyZone',
    'screenshot-basic',
    'qbx_core'
}
