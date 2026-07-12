fx_version 'cerulean'
game 'gta5'

name        'FiveM Dumper'
description 'Dynamic analysis & deobfuscation of any FiveM resource — runs inside the real FiveM/CFX runtime.'
version     '1.0.0'
author      'fivem_dumper'

-- Shared data structures (event names, config keys, etc.)
shared_scripts {
    'shared/constants.lua',
}

-- Server-side: loader + instrumentation + writer
server_scripts {
    'server/env.lua',
    'server/writer.lua',
    'server/main.lua',
}

-- Client-side: intercepts client calls triggered by server during dump
client_scripts {
    'client/main.lua',
}

lua54 'yes'
