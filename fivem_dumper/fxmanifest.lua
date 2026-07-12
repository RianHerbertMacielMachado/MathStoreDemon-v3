fx_version 'cerulean'
game 'gta5'

name        'FiveM Dumper'
description 'Deobfuscates any resource using FiveM LuaJIT: LoadResourceFile -> load() -> string.dump(). Works with Luraph.'
version     '3.1.0'
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
