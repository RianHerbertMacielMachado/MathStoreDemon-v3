fx_version 'cerulean'
game 'gta5'

name        'FiveM Dumper'
description 'Intercepts native FiveM APIs to analyze any resource — works with Luraph bytecode.'
version     '2.0.0'
author      'fivem_dumper'

shared_scripts {
    'shared/constants.lua',
}

-- ORDEM IMPORTA:
--   1. collector.lua  — monkey-patches as APIs globais PRIMEIRO
--   2. writer.lua     — gera os arquivos de output
--   3. main.lua       — comandos /dump, /dumpall, auto-dump
server_scripts {
    'server/collector.lua',
    'server/writer.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

lua54 'yes'
