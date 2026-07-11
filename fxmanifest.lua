
fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'MathSchiavi | Discord: Math0001'
description 'MathStoreDemon-v3 - Wing & Tail System'
version '1.0.0'
-- If you don't have ox_lib, remove the @ox_lib/init.lua line below
-- and set Config.UseOxLib = false in config/config.lua
shared_scripts {
    'bridge/oxlib_loader.lua',
    'bridge/vrp_loader.lua',
    'config/config.lua',
    'config/config_internal.lua',
    'config/locales.lua',
    'config/permissions.lua',
    'bridge/shared.lua',
}
client_scripts {
    'client/core.lua',
    'bridge/client.lua',
    'client/main.lua',
    'client/verificar.lua',
    'client/bones.lua',
}
server_scripts {
    'server/core.lua',
    'bridge/server.lua',
    'server/main.lua',
    'server/auth.lua',
}
ui_page 'html/index.html'
files {
    'html/index.html',
    'html/assets/css/style.css',
    'html/assets/js/app.js',
    'html/assets/img/**/*.png',
}
escrow_ignore {
    'config/config.lua',
    'config/config_internal.lua',
    'config/locales.lua',
    'config/permissions.lua',
    'bridge/shared.lua',
    'bridge/client.lua',
    'bridge/server.lua',
    'bridge/oxlib_loader.lua',
    'bridge/vrp_loader.lua',
    'client/main.lua',
    'client/verificar.lua',
    'client/bones.lua',
    'server/main.lua',
    'server/auth.lua',
}
lua54 'yes'   
-- Arquivos necessários
files {
    'stream/**/*.ydr',
    'stream/**/*.ytyp',
    'stream/**/*.ycd',
}
-- Data files para modelos e animações
data_file 'DLC_ITYP_REQUEST' 'stream/**/*.ytyp'
data_file 'ANIM_DICT' 'stream/**/*.ycd'
dependency '/assetpacks'
dependency '/assetpacks'