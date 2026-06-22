fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ParTay Airlines'
description 'Player-driven Qbox airline and airport RP core'
version '1.0.0'
author 'LoadedxDiaper / Codex'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

ui_page 'web/index.html'

client_scripts {
    'client/main.lua',
    'client/creator.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/creator.lua'
}

files {
    'install.sql',
    'web/index.html',
    'web/dev.html',
    'web/style.css',
    'web/nui.js',
    'web/atc.css',
    'web/atc.js',
    'web/atc_panel.png',
    'web/airhud.css',
    'web/airhud.js',
    'web/airhud_panel.png',
    'web/tablet.css',
    'web/tablet.js',
    'web/tablet_panel.png',
    'web/mock-airports.json',
    'web/NUI_CONTRACT.md',
    'web/app.js'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'oxmysql',
    'object_gizmo'
}
