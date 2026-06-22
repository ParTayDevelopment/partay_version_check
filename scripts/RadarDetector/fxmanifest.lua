fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'RadarDetector'
author "LoadedxDiaper"
description 'Vehicle-installed radar detector with ox_inventory install flow and wk_wars2x radar signal support.'
website "https://partaystudios.tebex.io/"
discord "https://discord.gg/partaystudios"
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'locales/en.lua',
    'config/config.lua',
    'shared/*.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/*.lua'
}

ui_page 'html/nui/index.html'

files {
    'html/nui/index.html',
    'html/nui/init.js',
    'html/nui/jquery.js',
    'html/nui/style.css',
    'html/nui/fonts/*.ttf',
    'html/nui/images/*.png',
    'html/nui/images/R7/*.png',
    'html/nui/sounds/*.ogg',
    'html/nui/sounds/R8/*.ogg'
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql'
}
