
fx_version "cerulean"
game "gta5"
lua54 "yes"
description "Custom Money Washing w/ Dancing"
author "LoadedxDiaper"
website "https://partay.tebex.io/"
discord "https://discord.gg/partaystudios"
version "2.0.0"

files {
    "locales/*.json"
}

shared_scripts {
    "@ox_lib/init.lua",
    "config/config.lua",
    "src/config_shared.lua"
}

server_script "src/server.lua"
client_scripts {
    "config/emote_menus.lua",
    "src/config_client.lua",
    "src/client.lua"
}

escrow_ignore {
    'config/config.lua',
    "config/emote_menus.lua",
    "locales/*.json"
}
