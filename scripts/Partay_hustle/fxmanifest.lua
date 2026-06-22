
fx_version 'cerulean'
game 'gta5'
name 'Partay_hustle'

version '1.0.7'

author "LoadedxDiaper"
website "https://partay.tebex.io/"
discord "https://discord.gg/partaystudios"

shared_script {
    'build/queue_handler.js',
    '@ox_lib/init.lua',
    'config.lua',
    'locales.lua'
}

server_script {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_main.lua',
    'server/sv_level.lua',
    'server/garage_adapters.lua',
    'client/open_client.lua',
}

client_script {
    'client/cl_main.lua',
    'client/cl_level.lua',
    'client/cl_ui.lua',
}

lua54 'yes'

escrow_ignore {
    'config.lua',
    'client/open_client.lua',
    'locales.lua'
}
dependency '/assetpacks'
dependency 'ox_lib'
dependency 'oxmysql'

-- NUI
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/logo.png'
}
