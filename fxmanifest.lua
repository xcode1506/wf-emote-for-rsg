fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'wf-emote'
author 'Hugo'
description 'WF Emote - standalone emote book for RedM: self-contained UI with scrolling category lists and 3D preview before selecting.'
version '1.1.0'

client_scripts {
    'config.lua',
    'animations.lua',
    'client.lua',
    'wf_interact_config.lua',
    'wf_interact_locales.lua',
    'wf_interact_utils.lua',
    'wf_interact_shared.lua',
    'wf_interact_extra.lua',
    'wf_interact_client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'animations.lua',
    'server.lua',
}

-- wf-interact world-interaction picker NUI (chairs, beds, piano, baths, ...)
ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
    'ui/font.ttf',
    'ui/logo.png',
    -- emote book artwork and fonts
    'ui/assets/background.png',
    'ui/assets/chip_torn.png',
    'ui/assets/panel_torn.png',
    'ui/assets/grain.png',
    'ui/assets/league-gothic.woff2',
    'ui/assets/caslon.woff2',
    'ui/assets/caslon-italic.woff2',
    'ui/assets/icons/*.png',
}

-- streamed female pose clips (rm_30-custom-female-pose pack)
file 'stream/*.ycd'

dependencies {
    'oxmysql',
}
