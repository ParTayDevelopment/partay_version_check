
fx_version "cerulean"
game "gta5"

description "Restricted Zones"
author "LoadedxDiaper"
website "https://partay.tebex.io/"
discord "https://discord.gg/partaystudios"
version "1.0.0"

files {
    "locales/*.json"
}

shared_scripts {
    "@ox_lib/init.lua",
    "config.lua"
}

client_scripts {
    "@PolyZone/client.lua",
    "src/client.lua"
}

server_script "src/server.lua"

lua54 "yes"

dependency "PolyZone"
dependency "ox_lib"
dependency "ox_inventory"

escrow_ignore {
	'config.lua'
}
