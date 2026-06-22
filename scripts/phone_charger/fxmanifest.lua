
fx_version 'cerulean'
game 'gta5'

shared_scripts {
    '@ox_lib/init.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'lb-phone'
}
