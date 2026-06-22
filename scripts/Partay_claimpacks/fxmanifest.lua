
fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'Partay_claimpacks'
description 'Lets players claim configurable reward packs from NPC vendors'
version '3.0.2'
author "LoadedxDiaper"
website "https://partay.tebex.io/"
discord "https://discord.gg/partaystudios"

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target'
}

shared_scripts {
    'dist/patch_update.js',
    '@ox_lib/init.lua',
    'config.lua',
    'shared/notifications.lua',
    'locales/*.lua'
}

client_scripts {
    'client/target.lua',
    'client/zones.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',
    'server/discord.lua',
    'server/storage.lua',
    'server/claims.lua',
    'server/main.lua'
}

escrow_ignore {
	'config.lua',
    'shared/notifications.lua',
    'locales/*.lua'
}
