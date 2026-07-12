fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author      'MathSchiavi | Discord: Math0001'
description 'MathStoreDemon-v3 - Wing & Tail System'
version     '1.0.0'

-----------------------------------------------------------------------
-- Dependências opcionais
-- Se não tiver ox_lib, defina Config.UseOxLib = false no config.lua
-----------------------------------------------------------------------
dependency '/assetpacks'

-----------------------------------------------------------------------
-- Scripts compartilhados (cliente + servidor)
-----------------------------------------------------------------------
shared_scripts {
    'bridge/oxlib_loader.lua',     -- carrega ox_lib se disponível
    'bridge/vrp_loader.lua',       -- carrega utils vRP se disponível
    'config/config.lua',
    'config/config_internal.lua',
    'config/locales.lua',
    'config/permissions.lua',
    'bridge/shared.lua',
}

-----------------------------------------------------------------------
-- Scripts do cliente
-----------------------------------------------------------------------
client_scripts {
    'client/debug.lua',     -- debug: carrega ANTES dos obfuscados (intercepts hooks)
    'client/core.lua',
    'bridge/client.lua',
    'client/main.lua',
    'client/verificar.lua',
    'client/bones.lua',
}

-----------------------------------------------------------------------
-- Scripts do servidor
-----------------------------------------------------------------------
server_scripts {
    'server/core.lua',
    'server/debug.lua',     -- debug: carrega ANTES do main (intercepts hooks)
    'bridge/server.lua',
    'server/main.lua',
}

-----------------------------------------------------------------------
-- NUI (interface HTML)
-----------------------------------------------------------------------
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/assets/css/style.css',
    'html/assets/js/app.js',
    'html/assets/img/**/*.png',
    -- Modelos e animações (streaming)
    'stream/**/*.ydr',
    'stream/**/*.ytyp',
    'stream/**/*.ycd',
}

-----------------------------------------------------------------------
-- Data files: registra os tipos de asset para o motor do jogo
-----------------------------------------------------------------------
data_file 'DLC_ITYP_REQUEST' 'stream/**/*.ytyp'
data_file 'ANIM_DICT'        'stream/**/*.ycd'

-----------------------------------------------------------------------
-- Arquivos que NÃO serão embaralhados pelo Escrow (editáveis)
-----------------------------------------------------------------------
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
    'client/debug.lua',
    'server/main.lua',
    'server/debug.lua',
}
