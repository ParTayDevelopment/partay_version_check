fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'No Love Lost Starter Zone'
description 'No Love Lost city-boundary onboarding for new players'
version '1.0.2'
author "LoadedxDiaper"
website "https://partay.tebex.io/"
discord "https://discord.gg/partaystudios"

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/myLogo.png'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql',
    'qbx_core',
    'ox_inventory'
}
