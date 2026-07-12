-----------------------------------------------------------------------
-- fivem_deob/extractor.lua
-- Executa a simulação completa de um resource FiveM e extrai
-- todos os dados observáveis dos scripts (incluindo obfuscados).
--
-- Retorna uma tabela `extracted` com:
--   .server  — dados do lado servidor
--   .client  — dados do lado cliente
--   .shared  — globals compartilhados (E table, Config, etc.)
-----------------------------------------------------------------------

local RT  = require("fivem_deob.runtime")
local MAN = require("fivem_deob.manifest")

local EX = {}

-- ── Eventos de jogo a disparar no cliente para extrair handlers ─────
-- Tenta um payload genérico razoável para cada evento
local CLIENT_FIRE_EVENTS = {
    -- auth
    { "authStatus",          { true } },
    { "4572autorizar",       {} },
    { "4578desautorizar",    {} },
    -- wings
    { "spawn",               { 1 } },
    { "remove",              {} },
    { "abrir",               {} },
    { "fechar",              {} },
    { "bater",               {} },
    { "toggle",              {} },
    { "fly",                 { true } },
    { "changeColor",         { 1 } },
    { "deleteNearby",        {} },
    { "deleteMassive",       {} },
    -- tail
    { "tail:spawn",          { 1 } },
    { "tail:remove",         {} },
    { "tail:bater",          {} },
    { "tail:enrolar",        {} },
    { "tail:reta",           {} },
    { "tail:changeColor",    { 1 } },
    -- sync
    { "sync:spawn",          { 2, 1 } },
    { "sync:anim",           { 2, "abrir" } },
    { "sync:remove",         { 2 } },
    { "sync:bulk",           { {{source=2,cor=1}} } },
    { "tail:sync:spawn",     { 2, 1 } },
    { "tail:sync:bulk",      { {{source=2,cor=1}} } },
    -- bridge
    { "bridge:notify",       { "Test", "success", 3000 } },
    -- verificar / animprotect
    { "receberCheckpoints",  { {} } },
    { "erroCheckpoints",     { "test" } },
    -- flight
    { "flight:start",        {} },
    { "flight:end",          {} },
    { "flight:animationChange", { 1 } },
    { "wing:rasanteActive",  { true } },
    { "wing:subidaActive",   { true } },
    -- animprotect
    { "animprotect:priorityChanged", { 10 } },
    { "animprotect:priorityCleared", {} },
    -- game
    { "gameEventTriggered",  { "CEventNetworkEntityDamage", {1,1,0,1,0} } },
    -- lifecycle
    { "onResourceStop",      { "RESOURCE" } },  -- RESOURCE substituído depois
}

-- ── Eventos de jogo a disparar no servidor ──────────────────────────
local SERVER_FIRE_EVENTS = {
    { "onResourceStart",     { "RESOURCE" } },
    { "playerConnecting",    { "TestPlayer1", function() end, {} } },
    { "playerDropped",       { "Disconnected" } },
}

-- ── Helper: imprime linha com prefixo ───────────────────────────────
local function make_logger(prefix, verbose, log_file)
    local fh = log_file and io.open(log_file, "a") or nil
    return function(tag, msg)
        if verbose then
            local line = string.format("[%s][%s] %s", prefix, tag, tostring(msg))
            print(line)
            if fh then fh:write(line.."\n"); fh:flush() end
        elseif fh then
            local line = string.format("[%s][%s] %s", prefix, tag, tostring(msg))
            fh:write(line.."\n"); fh:flush()
        end
    end, fh
end

-- ── Execução principal ──────────────────────────────────────────────
function EX.run(resource_dir, opts)
    opts = opts or {}
    local verbose   = opts.verbose   or false
    local log_file  = opts.log_file  or nil
    local max_ticks = opts.max_ticks or 3

    resource_dir = resource_dir:gsub("/$","")

    -- ── Resolve caminho absoluto para obter o nome correto ──────────
    -- io.popen('pwd') resolve '.' e paths relativos para o nome real
    local abs_dir
    do
        local ph = io.popen('cd "'..resource_dir..'" 2>/dev/null && pwd')
        if ph then
            abs_dir = ph:read("*l"); ph:close()
        end
        abs_dir = abs_dir or resource_dir
    end

    -- ── Lê o manifest ──────────────────────────────────────────────
    local manifest_path = resource_dir.."/fxmanifest.lua"
    if not MAN.file_exists(manifest_path) then
        manifest_path = resource_dir.."/__resource.lua"
    end
    local manifest, merr = MAN.parse(manifest_path)
    if not manifest then
        return nil, "Manifest error: "..tostring(merr)
    end

    -- ── Detecta resource name pelo nome real da pasta ───────────────
    -- opts.resource_name permite sobrescrever manualmente
    local resource_name = opts.resource_name
        or abs_dir:match("([^/]+)$")
        or "unknown"

    local log_sv, fh_sv = make_logger("SERVER", verbose, log_file)
    local log_cl, fh_cl = make_logger("CLIENT", verbose, log_file)

    -- ════════════════════════════════════════════════════════════════
    -- FASE 1: SERVER
    -- ════════════════════════════════════════════════════════════════
    local sv_env = RT.new_env("SERVER", {
        resource = resource_name,
        log      = log_sv,
        resources = opts.resources or {},
    })

    -- Carrega shared
    for _, rel in ipairs(manifest.shared) do
        local path = resource_dir.."/"..rel
        if MAN.file_exists(path) then
            log_sv("LOAD", rel)
            local ok, err = RT.load_file(path, sv_env, rel)
            if not ok then log_sv("LOAD.ERROR", rel.." — "..tostring(err)) end
        end
    end

    -- Carrega server scripts
    for _, rel in ipairs(manifest.server) do
        local path = resource_dir.."/"..rel
        if MAN.file_exists(path) then
            log_sv("LOAD", rel)
            local ok, err = RT.load_file(path, sv_env, rel)
            if not ok then log_sv("LOAD.ERROR", rel.." — "..tostring(err)) end
        end
    end

    RT.run_threads(sv_env, max_ticks)

    -- Dispara eventos server
    local sv_data = RT.get_data(sv_env)
    for _, ev_def in ipairs(SERVER_FIRE_EVENTS) do
        local name = ev_def[1]
        local args = ev_def[2] or {}
        -- Substitui placeholder de resource name
        local actual_name = name:gsub("RESOURCE", resource_name)
        local full_name
        if actual_name:find(":") or actual_name == "onResourceStart"
           or actual_name == "playerConnecting" or actual_name == "playerDropped" then
            full_name = actual_name
        else
            full_name = resource_name..":"..actual_name
        end
        RT.fire_event(sv_env, full_name, table.unpack(args))
        RT.run_threads(sv_env, max_ticks)
    end

    -- Dispara comandos registrados com args vazios (para descoberta)
    for name, handler in pairs(sv_data.cmd_handler_map) do
        log_sv("TRY_COMMAND", "/"..name)
        local ok, err = pcall(handler, 1, {}, false)
        if not ok then log_sv("CMD.ERROR", name.." "..tostring(err)) end
    end

    RT.run_threads(sv_env, max_ticks)

    -- ════════════════════════════════════════════════════════════════
    -- FASE 2: CLIENT
    -- ════════════════════════════════════════════════════════════════
    package.loaded['fivem_deob.runtime'] = nil  -- força reload limpo
    RT = require("fivem_deob.runtime")

    local cl_env = RT.new_env("CLIENT", {
        resource = resource_name,
        log      = log_cl,
        resources = opts.resources or {},
    })

    -- Carrega shared no contexto client
    for _, rel in ipairs(manifest.shared) do
        local path = resource_dir.."/"..rel
        if MAN.file_exists(path) then
            log_cl("LOAD", rel)
            local ok, err = RT.load_file(path, cl_env, rel)
            if not ok then log_cl("LOAD.ERROR", rel.." — "..tostring(err)) end
        end
    end

    RT.run_threads(cl_env, max_ticks)

    -- Carrega client scripts
    for _, rel in ipairs(manifest.client) do
        local path = resource_dir.."/"..rel
        if MAN.file_exists(path) then
            log_cl("LOAD", rel)
            local ok, err = RT.load_file(path, cl_env, rel)
            if not ok then log_cl("LOAD.ERROR", rel.." — "..tostring(err)) end
        end
    end

    RT.run_threads(cl_env, max_ticks)

    -- Dispara eventos client
    local cl_data = RT.get_data(cl_env)
    for _, ev_def in ipairs(CLIENT_FIRE_EVENTS) do
        local name = ev_def[1]
        local args = ev_def[2] or {}
        local full_name = name:find(":")
            and (name:find("^on") and name or resource_name..":"..name)
            or resource_name..":"..name
        -- Casos especiais: eventos sem prefixo de resource
        if name:match("^flight:") or name:match("^wing:")
           or name:match("^animprotect:") or name == "gameEventTriggered"
           or name:match("^on") then
            full_name = name
        end
        RT.fire_event(cl_env, full_name, table.unpack(args))
        RT.run_threads(cl_env, max_ticks)
    end

    -- ════════════════════════════════════════════════════════════════
    -- Coleta resultado final
    -- ════════════════════════════════════════════════════════════════
    local result = {
        resource = resource_name,
        manifest = manifest,
        server   = RT.get_data(sv_env),
        client   = RT.get_data(cl_env),
        -- Globals compartilhados detectados
        shared_globals = {
            E               = sv_env.E or cl_env.E,
            Bridge          = type(sv_env.Bridge)=="table" and sv_env.Bridge or cl_env.Bridge,
            Config          = sv_env.Config or cl_env.Config,
            RES_NAME        = sv_env.RES_NAME or cl_env.RES_NAME,
            WING_STATE_KEY  = sv_env.WING_STATE_KEY or cl_env.WING_STATE_KEY,
        },
    }

    if fh_sv then fh_sv:close() end
    if fh_cl then fh_cl:close() end

    return result
end

return EX
