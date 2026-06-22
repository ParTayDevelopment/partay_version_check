
fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'Growl'
description 'Hunger and Thirst Sounds'
version '2.0.2'
author "LoadedxDiaper"
website "https://partay.tebex.io/"
discord "https://discord.gg/partaystudios"

files {
    'html/ui.html',
    'html/sounds/stomach_growl.ogg'
}

ui_page 'html/ui.html'

shared_script 'config.lua'

client_script 'client/hunger_thirst_alert.lua'

server_script 'server.lua'

escrow_ignore {
    'config.lua'
  }
