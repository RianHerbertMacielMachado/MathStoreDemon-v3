-----------------------------------------------------------------------
-- fivem_dumper/server/main.lua
--
-- Ponto de entrada do fivem_dumper.
--
-- Modos de operação:
--   1. AUTO  — no onResourceStart do servidor, analisa automaticamente
--              qualquer resource que for iniciado após o fivem_dumper.
--   2. MANUAL — comando /dump <resourceName> (console ou in-game admin)
--               analisa um resource específico imediatamente.
--
-- Saída: fivem_dumper/output/<resourceName>/
--   ├── server/main_reconstructed.lua
--   ├── client/main_reconstructed.lua
--   ├── shared/events_map.lua
--   ├── shared/config_extracted.lua
--   └── ANALYSIS_REPORT.md
--
-- FUNCIONAMENTO:
--   • Detecta o caminho real do resource no disco via GetResourcePath()
--   • Lê o fxmanifest.lua para descobrir quais arquivos carregar
--   • Carrega cada arquivo no ENV instrumentado (env.lua)
--   • O LuaJIT do FiveM executa bytecode Luraph diretamente — sem parser
--   • Dispara eventos padrão para extrair handlers
--   • Escreve o output via io.open (funciona em qualquer servidor)
-----------------------------------------------------------------------

-- Garante que ENV e WRITER estão disponíveis (carregados antes deste arquivo)
assert(ENV,    "[Dumper] server/env.lua não carregado antes de main.lua")
assert(WRITER, "[Dumper] server/writer.lua não carregado antes de main.lua")

-----------------------------------------------------------------------
-- Configuração
-----------------------------------------------------------------------
local DUMPER_RES    = GetCurrentResourceName()
local MAX_TICKS     = 30    -- pump de threads por etapa
local AUTO_DUMP     = true  -- analisa automaticamente resources ao iniciar

-- Eventos cliente a disparar para extração dos handlers
local CLIENT_FIRE_EVENTS = {
    -- auth / lifecycle
    { "authStatus",               { true } },
    { "4572autorizar",            {} },
    { "4578desautorizar",         {} },
    -- wings
    { "spawn",                    { 1 } },
    { "remove",                   {} },
    { "abrir",                    {} },
    { "fechar",                   {} },
    { "bater",                    {} },
    { "toggle",                   {} },
    { "fly",                      { true } },
    { "changeColor",              { 1 } },
    { "deleteNearby",             {} },
    { "deleteMassive",            {} },
    -- tail
    { "tail:spawn",               { 1 } },
    { "tail:remove",              {} },
    { "tail:bater",               {} },
    { "tail:enrolar",             {} },
    { "tail:reta",                {} },
    { "tail:changeColor",         { 1 } },
    -- sync
    { "sync:spawn",               { 2, 1 } },
    { "sync:anim",                { 2, "abrir" } },
    { "sync:remove",              { 2 } },
    { "sync:bulk",                { {{source=2,cor=1}} } },
    { "tail:sync:spawn",          { 2, 1 } },
    { "tail:sync:bulk",           { {{source=2,cor=1}} } },
    -- bridge
    { "bridge:notify",            { "Test", "success", 3000 } },
    -- verificar
    { "receberCheckpoints",       { {} } },
    { "erroCheckpoints",          { "test" } },
    -- flight
    { "flight:start",             {} },
    { "flight:end",               {} },
    { "flight:animationChange",   { 1 } },
    { "wing:rasanteActive",       { true } },
    { "wing:subidaActive",        { true } },
    -- animprotect
    { "animprotect:priorityChanged", { 10 } },
    { "animprotect:priorityCleared", {} },
    -- animações fairy wing v6
    { "pegarasa",                 {} },
    { "removerasa",               {} },
    { "ritualasa1",               {} },
    { "ritualasa2",               {} },
    { "ritualasa3",               {} },
    { "ritualsair",               {} },
    { "ritual1",                  {} },
    { "ritual2",                  {} },
    { "agacharasa1",              {} },
    { "agacharasa2",              {} },
    { "agacharasa3",              {} },
    { "agacharasa4",              {} },
    { "agacharsair",              {} },
    { "meditar1",                 {} },
    { "meditar2",                 {} },
    { "msubir",                   {} },
    { "mdescer",                  {} },
    { "meditarsair",              {} },
    { "asaidle1",                 {} },
    { "asaidle2",                 {} },
    { "asaidle3",                 {} },
    { "asaidle4",                 {} },
    { "asaidle5",                 {} },
    { "asaidle6",                 {} },
    { "asaprazer",                {} },
    -- runes
    { "runafada",                 { 4 } },
    { "runadeletar",              {} },
    { "runeRemoveOldest",         {} },
    { "sync:runeSpawn",           { 2, 4 } },
    { "sync:runeDelete",          { 2 } },
    -- HUD / sound
    { "sync:playSound",           { 2, "sound1" } },
    { "asasv5hud",                { {} } },
    -- respostas server→client
    { "cl_h1",                    { true, 1 } },
    { "cl_h2",                    { true, 1 } },
    -- game
    { "gameEventTriggered",       { "CEventNetworkEntityDamage", {1,1,0,1,0} } },
    -- lifecycle
    { "onResourceStop",           { "RESOURCE" } },
}

-- Eventos servidor a disparar
local SERVER_FIRE_EVENTS = {
    { "onResourceStart",     { "RESOURCE" } },
    { "playerConnecting",    { "TestPlayer", function() end, {} } },
    { "playerDropped",       { "Disconnected" } },
}

-----------------------------------------------------------------------
-- Logger colorido para o console do servidor
-----------------------------------------------------------------------
local function make_log(prefix, verbose)
    return function(tag, msg)
        if verbose or tag == "LOAD.ERROR" or tag == "ERROR"
                   or tag == "Thread.KILLED" or tag == "Thread.ERROR" then
            print(string.format("^3[%s][%s]^7 %s", prefix, tag, tostring(msg)))
        end
    end
end

-----------------------------------------------------------------------
-- Lê e parseia o fxmanifest.lua de um resource
-- Retorna tabela { server={}, client={}, shared={} } ou nil, err
-----------------------------------------------------------------------
local function parse_manifest(resource_name, resource_path)
    -- Usa LoadResourceFile (API nativa FiveM) — evita io.open que pode
    -- bloquear em drives de rede mapeados (SMB/SAMBA).
    local src = LoadResourceFile(resource_name, "fxmanifest.lua")
    local manifest_path = resource_path.."/fxmanifest.lua"
    if not src then
        -- Tenta formato legado __resource.lua
        src = LoadResourceFile(resource_name, "__resource.lua")
        manifest_path = resource_path.."/__resource.lua"
    end
    if not src then
        -- Último fallback: io.open (caso LoadResourceFile não funcione)
        local f = io.open(manifest_path:gsub("__resource%.lua$","fxmanifest.lua"), "rb")
        if not f then
            f = io.open(resource_path.."/__resource.lua", "rb")
        end
        if not f then
            return nil, "fxmanifest.lua não encontrado em: "..resource_path
        end
        src = f:read("*a")
        f:close()
    end

    local result = { server={}, client={}, shared={} }

    -- Ambiente mínimo para executar o manifest
    local menv = setmetatable({}, {
        __index = function(t, k) return function(...) end end,
        __newindex = rawset,
    })

    -- Filtra paths que o dumper não pode abrir:
    --   @alias/path.lua  → referência a outro resource, não existe localmente
    --   path/*/file.lua  → glob, o FiveM expande mas io.open não consegue
    --   *.js / *.ts      → não são Lua, load() vai falhar
    local function is_loadable(path)
        if type(path) ~= "string" then return false end
        if path:sub(1,1) == "@" then return false end   -- alias @resource/
        if path:find("%*") then return false end         -- glob *
        if path:find("%?") then return false end         -- glob ?
        if path:match("%.[jJ][sS]$") then return false end  -- .js
        if path:match("%.[tT][sS]$") then return false end  -- .ts
        return true
    end

    -- Captura as diretivas de arquivo
    local function collect(list_name)
        return function(files)
            if type(files) == "string" then
                if is_loadable(files) then
                    result[list_name][#result[list_name]+1] = files
                end
            elseif type(files) == "table" then
                for _, f in ipairs(files) do
                    if is_loadable(f) then
                        result[list_name][#result[list_name]+1] = f
                    end
                end
            end
        end
    end

    menv.server_scripts   = collect("server")
    menv.client_scripts   = collect("client")
    menv.shared_scripts   = collect("shared")
    menv.server_script    = collect("server")   -- singular
    menv.client_script    = collect("client")
    menv.shared_script    = collect("shared")
    menv.fx_version       = function() end
    menv.game             = function() end
    menv.lua54            = function() end
    menv.name             = function() end
    menv.description      = function() end
    menv.version          = function() end
    menv.author           = function() end
    menv.dependency       = function() end
    menv.dependencies     = function() end
    menv.files            = function() end
    menv.data_file        = function() end
    menv.ui_page          = function() end
    menv.loadscreen       = function() end
    menv.this_is_a_map    = function() end
    menv.convar_category  = function() end
    menv.provide          = function() end

    local fn, err = load(src, "@"..manifest_path, "t", menv)
    if not fn then return nil, "manifest parse error: "..tostring(err) end
    local ok, rerr = pcall(fn)
    if not ok then return nil, "manifest runtime: "..tostring(rerr) end

    return result
end

-----------------------------------------------------------------------
-- Normaliza nome de evento (adiciona prefixo de resource se necessário)
-----------------------------------------------------------------------
local function normalize_event(name, resource)
    -- Eventos que NÃO recebem prefixo de resource
    if name:match("^flight:") or name:match("^wing:")
    or name:match("^animprotect:") or name:match("^tail:")
    or name:match("^sync:") or name:match("^bridge:")
    or name:match("^on%u") or name == "gameEventTriggered"
    or name == "onResourceStop" then
        return name:gsub("RESOURCE", resource)
    end
    -- Eventos que já têm ":" são prefixados com resource name
    local full = name:find(":")
        and (name:find("^on") and name or resource..":"..name)
        or resource..":"..name
    return full:gsub("RESOURCE", resource)
end

-----------------------------------------------------------------------
-- Pump auxiliar: roda threads do ENV e cede o tick ao servidor.
-- CRÍTICO: Wait(0) real (do FiveM) entre cada rodada de coroutines
-- evita que o CreateThread do dumper trave o loop principal do servidor.
-----------------------------------------------------------------------
local function pump(env, ticks)
    for _ = 1, (ticks or 1) do
        ENV.run_threads(env, 1)
        Wait(0)  -- cede o tick ao servidor FiveM entre cada rodada
    end
end

-----------------------------------------------------------------------
-- NÚCLEO: analisa um resource completo
-- resource_name : nome do resource (ex: "MathStoreFairyWingv6")
-- Retorna { sv_data, cl_data, files_written } ou nil, err
-----------------------------------------------------------------------
local function analyse_resource(resource_name, verbose)
    local t_start = GetGameTimer()

    print(string.format("^5[Dumper]^7 Iniciando análise de ^3%s^7...", resource_name))
    Wait(0)  -- cede tick antes de qualquer io.open

    -- ── 1. Resolve caminho do resource ────────────────────────────
    local resource_path = GetResourcePath(resource_name)
    if not resource_path or resource_path == "" then
        return nil, "GetResourcePath retornou vazio para: "..resource_name
    end
    -- Normaliza separadores
    resource_path = resource_path:gsub("\\", "/"):gsub("/+", "/"):gsub("/$", "")
    print(string.format("^5[Dumper]^7 Caminho: ^6%s^7", resource_path))
    Wait(0)

    -- ── 2. Parseia o manifest ──────────────────────────────────────
    print("^5[Dumper]^7 Lendo manifest...")
    Wait(0)
    local manifest, merr = parse_manifest(resource_name, resource_path)
    if not manifest then
        return nil, "Manifest: "..tostring(merr)
    end

    local function count_files()
        return #manifest.shared + #manifest.server + #manifest.client
    end
    print(string.format("^5[Dumper]^7 Manifest: %d shared, %d server, %d client",
        #manifest.shared, #manifest.server, #manifest.client))
    Wait(0)

    if count_files() == 0 then
        return nil, "Nenhum arquivo Lua encontrado no manifest de: "..resource_name
    end

    -- ── 3. Fase SERVER ─────────────────────────────────────────────
    print("^5[Dumper]^7 Fase SERVER...")
    Wait(0)
    local log_sv = make_log("SV/"..resource_name, verbose)
    local sv_env = ENV.new(resource_name, log_sv)

    -- Carrega shared
    for _, rel in ipairs(manifest.shared) do
        local path = resource_path.."/"..rel
        log_sv("LOAD", rel)
        Wait(0)
        local ok, err = ENV.load_file(resource_name, path, sv_env, rel)
        if not ok then log_sv("LOAD.ERROR", rel.." — "..tostring(err)) end
    end
    pump(sv_env, MAX_TICKS)

    -- Carrega server scripts
    for _, rel in ipairs(manifest.server) do
        local path = resource_path.."/"..rel
        log_sv("LOAD", rel)
        Wait(0)
        local ok, err = ENV.load_file(resource_name, path, sv_env, rel)
        if not ok then log_sv("LOAD.ERROR", rel.." — "..tostring(err)) end
    end
    pump(sv_env, MAX_TICKS)

    -- Dispara eventos servidor
    local sv_data = sv_env.__dumper_data

    ENV.fire_event(sv_env, "onResourceStart", resource_name)
    pump(sv_env, MAX_TICKS)
    sv_env.TriggerEvent("onResourceStart", resource_name)
    pump(sv_env, MAX_TICKS)

    for _, ev_def in ipairs(SERVER_FIRE_EVENTS) do
        local name     = ev_def[1]
        local args     = ev_def[2] or {}
        local act_args = {}
        for i, a in ipairs(args) do
            act_args[i] = (type(a)=="string") and a:gsub("RESOURCE", resource_name) or a
        end
        local full = name:gsub("RESOURCE", resource_name)
        ENV.fire_event(sv_env, full, table.unpack(act_args))
        pump(sv_env, MAX_TICKS)
    end

    -- Dispara todos os eventos registrados que ainda não foram disparados
    local sv_fired = { onResourceStart=true, playerConnecting=true, playerDropped=true }
    for evname in pairs(sv_data.event_handlers) do
        if not sv_fired[evname] then
            log_sv("FIRE_EXTRA", evname)
            ENV.fire_event(sv_env, evname)
            pump(sv_env, MAX_TICKS)
            sv_fired[evname] = true
        end
    end

    -- Proba comandos registrados
    for name, handler in pairs(sv_data.cmd_handler_map or {}) do
        log_sv("TRY_COMMAND", "/"..name)
        pcall(handler, 1, {}, false)
    end

    print(string.format("^5[Dumper]^7 SERVER: %d eventos, %d net, %d cmds, %d TriggerClientEvent",
        #sv_data.events, tcount(sv_data.net_events),
        #sv_data.commands, #sv_data.client_events))

    -- ── 4. Fase CLIENT ─────────────────────────────────────────────
    print("^5[Dumper]^7 Fase CLIENT...")
    Wait(0)
    local log_cl = make_log("CL/"..resource_name, verbose)
    local cl_env = ENV.new(resource_name, log_cl)
    -- Marca como client-side
    cl_env.__dumper_data.side = "CLIENT"

    -- Carrega shared no contexto client
    for _, rel in ipairs(manifest.shared) do
        local path = resource_path.."/"..rel
        log_cl("LOAD", rel)
        Wait(0)
        local ok, err = ENV.load_file(resource_name, path, cl_env, rel)
        if not ok then log_cl("LOAD.ERROR", rel.." — "..tostring(err)) end
    end
    pump(cl_env, MAX_TICKS)

    -- Carrega client scripts
    for _, rel in ipairs(manifest.client) do
        local path = resource_path.."/"..rel
        log_cl("LOAD", rel)
        Wait(0)
        local ok, err = ENV.load_file(resource_name, path, cl_env, rel)
        if not ok then log_cl("LOAD.ERROR", rel.." — "..tostring(err)) end
    end
    pump(cl_env, MAX_TICKS)

    -- Dispara eventos client
    local cl_data = cl_env.__dumper_data

    for _, ev_def in ipairs(CLIENT_FIRE_EVENTS) do
        local name     = ev_def[1]
        local args     = ev_def[2] or {}
        local act_args = {}
        for i, a in ipairs(args) do
            act_args[i] = (type(a)=="string") and a:gsub("RESOURCE", resource_name) or a
        end
        local full = normalize_event(name, resource_name)
        ENV.fire_event(cl_env, full, table.unpack(act_args))
        pump(cl_env, MAX_TICKS)
    end

    -- Dispara eventos extras que estão registrados mas não foram disparados
    local cl_fired = {}
    for _, ev_def in ipairs(CLIENT_FIRE_EVENTS) do
        cl_fired[normalize_event(ev_def[1], resource_name)] = true
    end
    for evname in pairs(cl_data.event_handlers) do
        if not cl_fired[evname] then
            log_cl("FIRE_EXTRA", evname)
            ENV.fire_event(cl_env, evname)
            pump(cl_env, MAX_TICKS)
        end
    end

    print(string.format("^5[Dumper]^7 CLIENT: %d eventos, %d keybinds, %d NUI, %d anims, %d models",
        #cl_data.events, #cl_data.keybinds, #cl_data.nui_callbacks,
        tcount(cl_data.anim_dicts), tcount(cl_data.models)))

    -- ── 5. Escreve output ──────────────────────────────────────────
    -- Resolve o caminho de output: dentro da pasta do próprio fivem_dumper
    local dumper_path = GetResourcePath(DUMPER_RES)
    if not dumper_path or dumper_path == "" then
        return nil, "Não foi possível resolver o caminho do fivem_dumper"
    end
    dumper_path = dumper_path:gsub("\\","/"):gsub("/+","/"):gsub("/$","")

    local output_base = dumper_path.."/output/"..resource_name
    local elapsed     = GetGameTimer() - t_start

    print(string.format("^5[Dumper]^7 Escrevendo output em: ^6%s^7", output_base))

    local files = WRITER.generate(sv_data, cl_data, resource_name, output_base, elapsed)

    print(string.format(
        "^2[Dumper]^7 ✓ Análise de ^3%s^7 concluída em ^2%dms^7 — %d arquivos gerados.",
        resource_name, elapsed, #files))

    -- Notifica clientes (para eventual display HUD)
    TriggerClientEvent(DUMPER_EV_CLIENT_REPORT, -1, {
        resource = resource_name,
        elapsed  = elapsed,
        files    = #files,
        sv_events = #sv_data.events,
        cl_events = #cl_data.events,
    })

    return { sv=sv_data, cl=cl_data, files=files, elapsed=elapsed }
end

-- Helper tcount para uso neste arquivo
function tcount(t)
    if type(t) ~= "table" then return 0 end
    local n = 0; for _ in pairs(t) do n=n+1 end; return n
end

-----------------------------------------------------------------------
-- Fila de análise: processa um resource por vez, mas não descarta
-- os que chegam durante uma análise — enfileira e executa em sequência.
-----------------------------------------------------------------------
local _analysed = {}   -- set: resources já analisados (auto-mode)
local _queue    = {}   -- fila FIFO: { resource_name, verbose, source }
local _running  = false

local function process_queue()
    if _running or #_queue == 0 then return end
    _running = true
    local item = table.remove(_queue, 1)
    CreateThread(function()
        local ok, err = pcall(analyse_resource, item.resource_name, item.verbose)
        if not ok then
            print("^1[Dumper] ERRO ao analisar '"..item.resource_name.."': "
                ..tostring(err).."^7")
        end
        _running = false
        -- Processa próximo item da fila
        if #_queue > 0 then
            -- Pequeno yield antes do próximo para não travar o server tick
            Wait(100)
            process_queue()
        end
    end)
end

local function dump_async(resource_name, verbose, source_player)
    -- Não enfileira o mesmo resource duas vezes seguidas
    for _, item in ipairs(_queue) do
        if item.resource_name == resource_name then
            print(string.format("^3[Dumper] '%s' já está na fila (%d pendentes).^7",
                resource_name, #_queue))
            return
        end
    end
    _queue[#_queue+1] = { resource_name=resource_name, verbose=verbose, source=source_player }
    print(string.format("^5[Dumper]^7 Enfileirado: ^3%s^7 (posição %d na fila)",
        resource_name, #_queue))
    process_queue()
end

-----------------------------------------------------------------------
-- COMANDO: /dump <resourceName> [verbose]
-- Pode ser usado no console do servidor ou por admin in-game
-----------------------------------------------------------------------
RegisterCommand("dump", function(source, args, rawCommand)
    local resource_name = args[1]
    local verbose       = (args[2] == "verbose" or args[2] == "-v")

    if not resource_name or resource_name == "" then
        print("^3[Dumper] Uso: /dump <resourceName> [verbose]^7")
        print("^3[Dumper] Exemplo: /dump MathStoreFairyWingv6^7")
        print("^3[Dumper] Exemplo: /dump MathStoreFairyWingv6 verbose^7")
        return
    end

    -- Verifica se o resource existe e está rodando
    local state = GetResourceState(resource_name)
    if state ~= "started" then
        print(string.format(
            "^1[Dumper] Resource '%s' não está rodando (state=%s).^7",
            resource_name, tostring(state)))
        print("^3[Dumper] Use /dump em qualquer resource que esteja started.^7")
        return
    end

    print(string.format(
        "^5[Dumper] /dump disparado por source=%s para: ^3%s^7",
        tostring(source), resource_name))

    dump_async(resource_name, verbose, tonumber(source) or 0)
end, true)  -- true = requer ace permission "command.dump" (configure no server.cfg)

-----------------------------------------------------------------------
-- AUTO-MODE: analisa automaticamente ao detectar onResourceStart
-----------------------------------------------------------------------
AddEventHandler("onResourceStart", function(started_resource)
    -- Ignora o próprio dumper
    if started_resource == DUMPER_RES then return end
    if not AUTO_DUMP then return end

    -- Evita reanálise do mesmo resource
    if _analysed[started_resource] then return end
    _analysed[started_resource] = true

    -- Pequeno delay para garantir que o resource terminou de inicializar.
    -- NÃO usa SetTimeout — a assinatura varia entre versões do FiveM:
    --   Antigas: SetTimeout(ms, fn)   Novas: SetTimeout(fn, ms)
    -- CreateThread+Wait funciona em TODAS as versões.
    CreateThread(function()
        Wait(500)
        local state = GetResourceState(started_resource)
        if state ~= "started" then
            print(string.format("^3[Dumper] Auto-dump: '%s' não está mais started (state=%s), pulando.^7",
                started_resource, tostring(state)))
            return
        end
        print(string.format("^5[Dumper] Auto-dump: ^3%s^7 iniciado — enfileirando...", started_resource))
        dump_async(started_resource, false, -1)
    end)
end)

-----------------------------------------------------------------------
-- Reinicia a lista de analisados quando o dumper é reiniciado
-- (ex: restart fivem_dumper → re-analisa tudo)
-----------------------------------------------------------------------
AddEventHandler("onResourceStop", function(stopped_resource)
    if stopped_resource == DUMPER_RES then return end
    -- Remove do cache para permitir re-análise se o resource for reiniciado
    _analysed[stopped_resource] = nil
end)

-----------------------------------------------------------------------
-- Recebe relatório do client e imprime no console
-----------------------------------------------------------------------
RegisterNetEvent(DUMPER_EV_CLIENT_REPORT)
AddEventHandler(DUMPER_EV_CLIENT_REPORT, function(report)
    if type(report) == "table" and report.resource then
        print(string.format(
            "^5[Dumper] Client report: ^3%s^7 — sv_events=%d cl_events=%d files=%d elapsed=%dms",
            report.resource,
            report.sv_events or 0, report.cl_events or 0,
            report.files    or 0, report.elapsed   or 0))
    end
end)

-----------------------------------------------------------------------
-- Banner de inicialização
-----------------------------------------------------------------------
print(string.format(
    "^5[Dumper]^7 FiveM Dumper v%s iniciado.",
    DUMPER_VERSION or "1.0.0"))
print("^5[Dumper]^7 Comandos:")
print("^5[Dumper]^7   ^3/dump <resourceName>^7         — analisa um resource específico")
print("^5[Dumper]^7   ^3/dump <resourceName> verbose^7  — com logs detalhados")
print(string.format(
    "^5[Dumper]^7 Auto-dump: ^%s%s^7 (analisa resources ao iniciar)",
    AUTO_DUMP and "2" or "1",
    AUTO_DUMP and "ATIVO" or "INATIVO"))
local _banner_path = GetResourcePath(DUMPER_RES):gsub("\\","/"):gsub("/+","/"):gsub("/$","")
print("^5[Dumper]^7 Output: ^6".._banner_path.."/output/^7")
