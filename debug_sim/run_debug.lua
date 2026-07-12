-----------------------------------------------------------------------
-- debug_sim/run_debug.lua
-- Entry-point do simulador FiveM.
-- Carrega todos os scripts na ordem exata do fxmanifest.lua,
-- executa shared → server → client, dispara eventos e comandos
-- simulados e gera o relatório completo.
--
-- Uso:  cd /home/user/webapp && lua5.4 debug_sim/run_debug.lua
-----------------------------------------------------------------------

-- garante que o require encontre os módulos em debug_sim/
package.path = package.path .. ";./debug_sim/?.lua;./?/init.lua"

local SIM = require("fivem_runtime")

local ROOT = "."   -- raiz do resource

-----------------------------------------------------------------------
-- Ordem de carregamento extraída do fxmanifest.lua
-----------------------------------------------------------------------
local SHARED_SCRIPTS = {
    "bridge/oxlib_loader.lua",
    "bridge/vrp_loader.lua",
    "config/config.lua",
    "config/config_internal.lua",
    "config/locales.lua",
    "config/permissions.lua",
    "bridge/shared.lua",
}

local SERVER_SCRIPTS = {
    "server/core.lua",
    "server/debug.lua",
    "bridge/server.lua",
    "server/main.lua",
}

local CLIENT_SCRIPTS = {
    "client/debug.lua",
    -- CRITICAL: bridge/shared.lua must load BEFORE bridge/client.lua
    -- bridge/shared.lua defines the 'E' event-name table and 'Bridge' stub
    -- that bridge/client.lua reads on its first line.
    "bridge/shared.lua",
    "bridge/client.lua",
    "client/core.lua",
    "client/main.lua",
    "client/verificar.lua",
    "client/bones.lua",
}

-----------------------------------------------------------------------
-- Helper: caminho completo
-----------------------------------------------------------------------
local function path(rel)
    return ROOT .. "/" .. rel
end

-----------------------------------------------------------------------
-- ══════════════════════════════════════════════════════════════════
-- FASE 1 — SERVER SIDE
-- ══════════════════════════════════════════════════════════════════
-----------------------------------------------------------------------
print("\n" .. string.rep("═",60))
print("  SIMULADOR FiveM — SERVER SIDE")
print(string.rep("═",60) .. "\n")

SIM.SIDE     = "SERVER"
SIM.LOG_FILE = "debug_sim/output_server.log"

local sv_env = SIM.build_env("SERVER", 0)

-- Habilita debug no Config (será sobrescrito depois de config.lua carregar,
-- mas precisamos de true ANTES dos outros scripts)
-- Injetamos diretamente no env para garantir
sv_env.Config = sv_env.Config or {}

-- Carrega shared scripts no contexto server
for _, rel in ipairs(SHARED_SCRIPTS) do
    SIM.load_file(path(rel), sv_env, rel)
end

-- Força debug ativo no config carregado
if sv_env.Config and sv_env.Config.Debug then
    sv_env.Config.Debug.Enabled = true
    sv_env.Config.Debug.ShowNativeHooks = true
    sv_env.Config.Debug.ShowHttp = true
    sv_env.Config.Debug.ShowLocals = true
end

-- Carrega server scripts
for _, rel in ipairs(SERVER_SCRIPTS) do
    SIM.load_file(path(rel), sv_env, rel)
end

-- Pump inicial de threads (onResourceStart, auth, etc.)
SIM.fire_event("onResourceStart", SIM.RESOURCE)
SIM.run_threads(10)

-----------------------------------------------------------------------
-- Simula ações server-side
-----------------------------------------------------------------------
print("\n" .. string.rep("─",50))
print("  SERVER — Simulando ações de jogadores")
print(string.rep("─",50) .. "\n")

-- Jogador 1 conecta
SIM.fire_event("playerConnecting", "TestPlayer1", function() end, {})
SIM.run_threads(3)

-- Jogador 1 usa comando /demonhud
SIM.run_command(sv_env, sv_env.Config.HudCommand or "demonhud", 1, {})
SIM.run_threads(3)

-- Jogador 1 usa /asasdm 5
SIM.run_command(sv_env, sv_env.Config.Commands and sv_env.Config.Commands.equip or "asasdm", 1, {"5"})
SIM.run_threads(3)

-- Jogador 1 usa /caudadm 3
SIM.run_command(sv_env, sv_env.Config.TailCommands and sv_env.Config.TailCommands.equip or "caudadm", 1, {"3"})
SIM.run_threads(3)

-- Simula NUI hudAction: pegarambos (wingId=7, tailId=7)
SIM.fire_event(SIM.RESOURCE .. ":hudAction",
    { action = "pegarambos", wingId = "7", tailId = "7" })
SIM.run_threads(3)

-- Simula NUI hudAction: asaabrir
SIM.fire_event(SIM.RESOURCE .. ":hudAction", { action = "asaabrir" })
SIM.run_threads(2)

-- Simula NUI hudAction: caudabater
SIM.fire_event(SIM.RESOURCE .. ":hudAction", { action = "caudabater" })
SIM.run_threads(2)

-- Simula NUI hudAction: removerasa
SIM.fire_event(SIM.RESOURCE .. ":hudAction", { action = "removerasa" })
SIM.run_threads(2)

-- Simula reqPlayerState
SIM.fire_event(SIM.RESOURCE .. ":reqPlayerState")
SIM.run_threads(2)

-- Jogador 1 sai
SIM.fire_event("playerDropped", "Disconnected")
SIM.run_threads(2)

-- Relatório server
SIM.report()

-----------------------------------------------------------------------
-- ══════════════════════════════════════════════════════════════════
-- FASE 2 — CLIENT SIDE
-- ══════════════════════════════════════════════════════════════════
-----------------------------------------------------------------------
print("\n" .. string.rep("═",60))
print("  SIMULADOR FiveM — CLIENT SIDE")
print(string.rep("═",60) .. "\n")

-- Novo runtime para client com log separado
-- IMPORTANT: require() is cached — we must reload the module fresh
package.loaded['fivem_runtime'] = nil  -- clear cache
local SIM2 = require("fivem_runtime")
SIM2.SIDE     = "CLIENT"
SIM2.LOG_FILE = "debug_sim/output_client.log"

local cl_env = SIM2.build_env("CLIENT", 1)

-- Carrega shared no contexto client
-- NOTE: bridge/shared.lua is loaded here for configs (locales, config_internal, etc.)
-- but the CLIENT_SCRIPTS list below also includes bridge/shared.lua FIRST
-- to guarantee it runs before bridge/client.lua in the correct FiveM order.
for _, rel in ipairs(SHARED_SCRIPTS) do
    SIM2.load_file(path(rel), cl_env, rel)
end

-- Força debug ativo
if cl_env.Config and cl_env.Config.Debug then
    cl_env.Config.Debug.Enabled      = true
    cl_env.Config.Debug.ShowNativeHooks = true
    cl_env.Config.Debug.ShowNui      = true
    cl_env.Config.Debug.ShowThreads  = true
end

-- Carrega client scripts
for _, rel in ipairs(CLIENT_SCRIPTS) do
    SIM2.load_file(path(rel), cl_env, rel)
end

-- Pump inicial
SIM2.fire_event("onClientResourceStart", SIM2.RESOURCE)
SIM2.run_threads(10)

-----------------------------------------------------------------------
-- Simula ações client-side
-----------------------------------------------------------------------
print("\n" .. string.rep("─",50))
print("  CLIENT — Simulando eventos recebidos do server")
print(string.rep("─",50) .. "\n")

-- authStatus (servidor confirma que resource está autorizado)
SIM2.fire_event(SIM2.RESOURCE .. ":authStatus", true)
SIM2.run_threads(5)

-- Spawnar asa cor 5
SIM2.fire_event(SIM2.RESOURCE .. ":spawn", 5)
SIM2.run_threads(10)

-- Spawnar cauda cor 3
SIM2.fire_event(SIM2.RESOURCE .. ":tail:spawn", 3)
SIM2.run_threads(10)

-- Animações de asa
SIM2.fire_event(SIM2.RESOURCE .. ":abrir")
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":bater")
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":fechar")
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":toggle")
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":fly", true)
SIM2.run_threads(5)

-- Animações de cauda
SIM2.fire_event(SIM2.RESOURCE .. ":tail:bater")
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":tail:enrolar")
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":tail:reta")
SIM2.run_threads(5)

-- Sync events (outros jogadores)
SIM2.fire_event(SIM2.RESOURCE .. ":sync:spawn", 2, 5)
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":tail:sync:spawn", 2, 3)
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":sync:anim", 2, "abrir")
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":sync:bulk", {{source=2,cor=5},{source=3,cor=1}})
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":tail:sync:bulk", {{source=2,cor=3}})
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":sync:remove", 2)
SIM2.run_threads(5)

-- Mudança de cor
SIM2.fire_event(SIM2.RESOURCE .. ":changeColor", 3)
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":tail:changeColor", 2)
SIM2.run_threads(5)

-- Limpeza
SIM2.fire_event(SIM2.RESOURCE .. ":deleteNearby")
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":deleteMassive")
SIM2.run_threads(5)

-- Auth events
SIM2.fire_event(SIM2.RESOURCE .. ":4572autorizar")
SIM2.run_threads(3)

SIM2.fire_event(SIM2.RESOURCE .. ":4578desautorizar")
SIM2.run_threads(3)

-- Flight events
SIM2.fire_event("flight:start")
SIM2.run_threads(5)

SIM2.fire_event("flight:end")
SIM2.run_threads(5)

SIM2.fire_event("flight:animationChange", 1)
SIM2.run_threads(5)

-- Wing/tail state events
SIM2.fire_event("wing:rasanteActive", true)
SIM2.run_threads(3)

SIM2.fire_event("wing:subidaActive", true)
SIM2.run_threads(3)

-- AnimProtect events
SIM2.fire_event("animprotect:priorityChanged", 10)
SIM2.run_threads(3)

SIM2.fire_event("animprotect:priorityCleared")
SIM2.run_threads(3)

-- Game event
SIM2.fire_event("gameEventTriggered", "CEventNetworkEntityDamage", {1,1,0,1,0,0,0})
SIM2.run_threads(3)

-- Remover
SIM2.fire_event(SIM2.RESOURCE .. ":remove")
SIM2.run_threads(5)

SIM2.fire_event(SIM2.RESOURCE .. ":tail:remove")
SIM2.run_threads(5)

-- Bridge notify
SIM2.fire_event(SIM2.RESOURCE .. ":bridge:notify", "Teste de notificação", "success", 4000)
SIM2.run_threads(2)

-- Checkpoint events (verificar.lua)
SIM2.fire_event(SIM2.RESOURCE .. ":receberCheckpoints", {})
SIM2.run_threads(3)

SIM2.fire_event(SIM2.RESOURCE .. ":erroCheckpoints", "test error")
SIM2.run_threads(3)

-- Resource stop
SIM2.fire_event("onResourceStop", SIM2.RESOURCE)
SIM2.run_threads(5)

-- Relatório client
SIM2.report()

-----------------------------------------------------------------------
-- Resumo final na tela
-----------------------------------------------------------------------
print("\n" .. string.rep("═",60))
print("  SIMULAÇÃO CONCLUÍDA")
print(string.rep("═",60))
print("  Logs escritos em:")
print("    debug_sim/output_server.log")
print("    debug_sim/output_client.log")
print(string.rep("═",60) .. "\n")
