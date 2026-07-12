-----------------------------------------------------------------------
-- fivem_deob/extractor.lua
-- Executa a simulação completa de um resource FiveM e extrai
-- todos os dados observáveis dos scripts (incluindo obfuscados).
--
-- Retorna uma tabela `result` com:
--   .resource  — nome do resource
--   .manifest  — tabela do manifest
--   .server    — dados do lado servidor (data)
--   .client    — dados do lado cliente (data)
--   .shared_globals — globals compartilhados (E, Config, etc.)
--   .all_files — todos os arquivos .lua encontrados no resource
-----------------------------------------------------------------------

local RT  = require("fivem_deob.runtime")
local MAN = require("fivem_deob.manifest")

local EX = {}

-- ── Detecta SO (Windows vs Unix) ────────────────────────────────────
local IS_WINDOWS = package.config:sub(1,1) == '\\'

-- ── Resolve caminho absoluto de forma portável ───────────────────────
-- Retorna o caminho absoluto de `dir` (funciona em Windows e Linux)
-- Prioriza extração puramente em Lua para evitar problemas com
-- io.popen em caminhos OneDrive/rede no Windows
local function resolve_abs_path(dir)
    -- Método 1: verificação rápida — se já é absoluto, retorna como está
    -- Windows: C:\... ou C:/... ou \\...
    -- Linux: /...
    if IS_WINDOWS then
        if dir:match("^%a:[/\\]") or dir:match("^\\\\") then
            -- Já é absoluto — normaliza separadores e remove trailing slash
            local norm = dir:gsub('\\', '/'):gsub('[/\\]+$', '')
            return norm
        end
    else
        if dir:sub(1,1) == "/" then
            return dir:gsub('[/]+$', '')
        end
    end

    -- Método 2: caminho relativo → tenta via io.popen
    local cmd
    if IS_WINDOWS then
        local d = dir:gsub('/', '\\')
        cmd = 'cd /d "' .. d .. '" 2>nul && cd'
    else
        cmd = 'cd "' .. dir .. '" 2>/dev/null && pwd'
    end
    local ok_p, ph = pcall(io.popen, cmd)
    if ok_p and ph then
        local ok_r, result = pcall(function() return ph:read("*l") end)
        pcall(function() ph:close() end)
        if ok_r and result and result ~= "" then
            result = result:gsub("\r$", ""):gsub("[/\\]+$", "")
            -- Normaliza para forward-slashes
            result = result:gsub('\\', '/')
            return result
        end
    end

    -- Método 3: fallback — retorna dir normalizado sem trailing slash
    return dir:gsub('[/\\]+$', '')
end

-- ── Extrai nome do resource a partir do caminho absoluto ─────────────
local function name_from_path(abs_path)
    -- Windows: C:\foo\bar  → bar
    -- Linux:   /foo/bar    → bar
    local name = abs_path:match("[/\\]([^/\\]+)[/\\]?$")
    return name or abs_path
end

-- ── Varredura recursiva de todos os arquivos .lua ────────────────────
-- Retorna lista de caminhos relativos ao resource_dir
-- Limitado a MAX_FILES arquivos e MAX_DEPTH níveis de profundidade
local MAX_FILES = 200
local MAX_DEPTH = 4
-- Diretórios a ignorar durante a varredura
-- (inclui diretórios do próprio fivem_deob para evitar auto-carregamento)
local SKIP_DIRS = {
    deob_output=true, [".git"]=true, ["node_modules"]=true,
    [".svn"]=true, [".hg"]=true, vendor=true,
    -- Diretórios do próprio fivem_deob (ferramenta de deobfuscação)
    fivem_deob=true, app_build=true, debug_sim=true,
    -- Outros diretórios de ferramentas comuns
    dist=true, build=true, ["__pycache__"]=true,
    -- Diretórios do repositório git que não são recursos FiveM
    ["go_app"]=true, ["go-app"]=true,
}

local function scan_all_lua(resource_dir)
    local files = {}
    local visited = {}

    -- Helper: adiciona arquivo à lista se não visitado e não excluído
    local function add_file(rel)
        rel = rel:gsub("\\","/"):gsub("^/","")
        if rel == "" then return end
        if visited[rel] then return end
        if rel:match("^deob_output") then return end
        if rel:match("^%.git") then return end
        visited[rel] = true
        files[#files+1] = rel
    end

    -- ── Tentativa 1: lfs (LuaFileSystem) ─────────────────────────────
    local ok_lfs, lfs = pcall(require, "lfs")
    if ok_lfs then
        local function scan_dir(dir, rel_prefix, depth)
            if depth > MAX_DEPTH then return end
            if #files >= MAX_FILES then return end
            local ok_iter, iter_or_err = pcall(lfs.dir, dir)
            if not ok_iter then return end
            pcall(function()
                for entry in iter_or_err do
                    if #files >= MAX_FILES then break end
                    if entry ~= "." and entry ~= ".." then
                        local full = dir.."/"..entry
                        local rel  = rel_prefix == "" and entry or (rel_prefix.."/"..entry)
                        local ok_attr, attr = pcall(lfs.attributes, full)
                        if ok_attr and attr then
                            if attr.mode == "directory" then
                                if not SKIP_DIRS[entry] then
                                    scan_dir(full, rel, depth + 1)
                                end
                            elseif attr.mode == "file" and entry:match("%.lua$") then
                                add_file(rel)
                            end
                        end
                    end
                end
            end)
        end
        scan_dir(resource_dir, "", 0)
        if #files > 0 then
            table.sort(files)
            return files
        end
        -- lfs está disponível mas retornou 0 arquivos — tenta popen como fallback
    end

    -- ── Tentativa 2: io.popen (sem arquivo temporário) ────────────────
    -- Mais confiável no Windows que os.execute + os.tmpname
    local prefix_len = #resource_dir + 1
    local pipe, pipe_err

    if IS_WINDOWS then
        -- dir /s /b lista todos os arquivos recursivamente com caminho completo
        local d = resource_dir:gsub("/","\\")
        pipe = io.popen('dir /s /b "'..d..'\\*.lua" 2>nul')
    else
        local cmd = 'find "'..resource_dir..'" -maxdepth '..MAX_DEPTH
            ..[[ \( -name deob_output -o -name .git -o -name fivem_deob]]
            ..[[ -o -name app_build -o -name debug_sim -o -name node_modules \)]]
            ..[[ -prune -o -name "*.lua" -print 2>/dev/null]]
        pipe = io.popen(cmd)
    end

    if pipe then
        local count = 0
        for line in pipe:lines() do
            if count >= MAX_FILES then break end
            line = line:gsub("\r$","")
            if line ~= "" then
                local rel = line:sub(prefix_len+1):gsub("\\","/"):gsub("^/","")
                if rel ~= "" and not visited[rel]
                    and not rel:match("^deob_output")
                    and not rel:match("^%.git") then
                    visited[rel] = true
                    files[#files+1] = rel
                    count = count + 1
                end
            end
        end
        pcall(function() pipe:close() end)
    end

    -- ── Tentativa 3: os.execute + tmpfile (último recurso) ───────────
    if #files == 0 then
        local tmp = os.tmpname()
        -- No Windows, os.tmpname pode retornar path sem extensão válida
        -- Acrescenta extensão e prefixo de temp conhecido
        if IS_WINDOWS and not tmp:match("%.") then
            tmp = tmp .. ".txt"
        end
        local cmd
        if IS_WINDOWS then
            local d = resource_dir:gsub("/","\\")
            cmd = 'dir /s /b "'..d..'\\*.lua" 2>nul > "'..tmp..'"'
        else
            cmd = 'find "'..resource_dir..'" -maxdepth '..MAX_DEPTH
                ..' -name "*.lua" -print 2>/dev/null > "'..tmp..'"'
        end
        os.execute(cmd)
        local f = io.open(tmp, "r")
        if f then
            for line in f:lines() do
                if #files >= MAX_FILES then break end
                line = line:gsub("\r$","")
                if line ~= "" then
                    local rel = line:sub(prefix_len+1):gsub("\\","/"):gsub("^/","")
                    if rel ~= "" and not visited[rel]
                        and not rel:match("^deob_output") then
                        visited[rel] = true
                        files[#files+1] = rel
                    end
                end
            end
            f:close()
        end
        pcall(function() os.remove(tmp) end)
    end

    table.sort(files)
    return files
end

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

-- ── Cria lista dedup de arquivos: manifest_files primeiro, depois extras ─
local function merge_file_lists(manifest_list, all_files)
    local seen = {}
    local result = {}
    -- Normaliza separadores antes de comparar
    local function norm(p) return p:gsub("\\","/") end
    -- Primeiro: os do manifest (mantém ordem)
    for _, rel in ipairs(manifest_list) do
        local n = norm(rel)
        if not seen[n] then
            seen[n] = true
            result[#result+1] = rel
        end
    end
    -- Depois: todos os outros .lua não listados no manifest
    for _, rel in ipairs(all_files) do
        local n = norm(rel)
        if not seen[n] then
            seen[n] = true
            result[#result+1] = rel
        end
    end
    return result
end

-- ── Execução principal ──────────────────────────────────────────────
function EX.run(resource_dir, opts)
    opts = opts or {}
    local verbose   = opts.verbose   or false
    local log_file  = opts.log_file  or nil
    local max_ticks = opts.max_ticks or 3

    resource_dir = resource_dir:gsub("[/\\]$","")

    -- ── Resolve caminho absoluto para obter o nome correto ──────────
    local abs_dir = resolve_abs_path(resource_dir)

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
        or name_from_path(abs_dir)
        or "unknown"

    -- ── Varre TODOS os .lua do resource ─────────────────────────────
    local all_lua_files = scan_all_lua(resource_dir)

    -- Listas completas: manifest + extras (sem duplicatas)
    local all_shared = merge_file_lists(manifest.shared, {})
    local all_server = merge_file_lists(manifest.server, {})
    local all_client = merge_file_lists(manifest.client, {})

    -- Arquivos não listados no manifest mas existentes → vai para shared
    -- (carrega em ambos os lados, pois não sabemos de qual lado são)
    local manifest_all = {}
    for _, v in ipairs(manifest.shared) do manifest_all[v:gsub("\\","/")] = true end
    for _, v in ipairs(manifest.server) do manifest_all[v:gsub("\\","/")] = true end
    for _, v in ipairs(manifest.client) do manifest_all[v:gsub("\\","/")] = true end

    -- Filtra arquivos extras (não no manifest, não são config/deob_output)
    local extra_files = {}
    for _, rel in ipairs(all_lua_files) do
        local r = rel:gsub("\\","/")
        if not manifest_all[r]
            and not r:match("^deob_output")
            and not r:match("^%.git")
            and r ~= "fxmanifest.lua"
            and r ~= "__resource.lua" then
            extra_files[#extra_files+1] = rel
        end
    end

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

    -- Carrega arquivos extras (não no manifest) no servidor também
    for _, rel in ipairs(extra_files) do
        local path = resource_dir.."/"..rel
        if MAN.file_exists(path) then
            log_sv("LOAD.EXTRA", rel)
            local ok, err = RT.load_file(path, sv_env, rel)
            if not ok then log_sv("LOAD.EXTRA.ERROR", rel.." — "..tostring(err)) end
        end
    end

    -- Pumpa threads após carregar todos os scripts
    RT.run_threads(sv_env, max_ticks * 2)

    -- Dispara onResourceStart antes dos outros eventos
    -- (alguns scripts registram handlers dentro de onResourceStart)
    RT.fire_event(sv_env, "onResourceStart", resource_name)
    RT.run_threads(sv_env, max_ticks * 2)
    -- Também via TriggerEvent para capturar scripts que usam TriggerEvent internamente
    sv_env.TriggerEvent("onResourceStart", resource_name)
    RT.run_threads(sv_env, max_ticks * 2)

    -- Dispara eventos server
    local sv_data = RT.get_data(sv_env)
    for _, ev_def in ipairs(SERVER_FIRE_EVENTS) do
        local name = ev_def[1]
        local args = ev_def[2] or {}
        -- Substitui placeholder de resource name
        local actual_args = {}
        for i, a in ipairs(args) do
            if type(a)=="string" then
                actual_args[i] = a:gsub("RESOURCE", resource_name)
            else
                actual_args[i] = a
            end
        end
        local actual_name = name:gsub("RESOURCE", resource_name)
        local full_name
        if actual_name:find(":") or actual_name == "onResourceStart"
           or actual_name == "playerConnecting" or actual_name == "playerDropped" then
            full_name = actual_name
        else
            full_name = resource_name..":"..actual_name
        end
        RT.fire_event(sv_env, full_name, table.unpack(actual_args))
        RT.run_threads(sv_env, max_ticks)
    end

    -- Dispara onResourceStart novamente (caso scripts registrem handlers dentro dele)
    RT.fire_event(sv_env, "onResourceStart", resource_name)
    RT.run_threads(sv_env, max_ticks * 2)

    -- Dispara todos os eventos registrados no servidor que ainda não foram disparados
    -- (lida com scripts que registram handlers APÓS onResourceStart)
    local sv_fired = { onResourceStart=true, playerConnecting=true, playerDropped=true }
    for evname in pairs(sv_data.event_handlers) do
        if not sv_fired[evname] then
            log_sv("FIRE_EXTRA", evname)
            RT.fire_event(sv_env, evname)
            RT.run_threads(sv_env, max_ticks)
            sv_fired[evname] = true
        end
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

    -- Carrega arquivos extras no cliente também
    for _, rel in ipairs(extra_files) do
        local path = resource_dir.."/"..rel
        if MAN.file_exists(path) then
            log_cl("LOAD.EXTRA", rel)
            local ok, err = RT.load_file(path, cl_env, rel)
            if not ok then log_cl("LOAD.EXTRA.ERROR", rel.." — "..tostring(err)) end
        end
    end

    RT.run_threads(cl_env, max_ticks)

    -- Dispara eventos client
    local cl_data = RT.get_data(cl_env)
    for _, ev_def in ipairs(CLIENT_FIRE_EVENTS) do
        local name = ev_def[1]
        local args = ev_def[2] or {}
        -- Substitui placeholder
        local actual_args = {}
        for i, a in ipairs(args) do
            if type(a)=="string" then
                actual_args[i] = a:gsub("RESOURCE", resource_name)
            else
                actual_args[i] = a
            end
        end
        local full_name = name:find(":")
            and (name:find("^on") and name or resource_name..":"..name)
            or resource_name..":"..name
        -- Casos especiais: eventos sem prefixo de resource
        if name:match("^flight:") or name:match("^wing:")
           or name:match("^animprotect:") or name == "gameEventTriggered"
           or name:match("^on") then
            full_name = name
        end
        RT.fire_event(cl_env, full_name, table.unpack(actual_args))
        RT.run_threads(cl_env, max_ticks)
    end

    -- Também dispara todos os eventos registrados que ainda não foram disparados
    -- (eventos com nome prefixado que não estão na lista acima)
    local fired = {}
    for _, ev_def in ipairs(CLIENT_FIRE_EVENTS) do
        local name = ev_def[1]
        local full_name
        if name:match("^flight:") or name:match("^wing:")
           or name:match("^animprotect:") or name == "gameEventTriggered"
           or name:match("^on") then
            full_name = name
        else
            full_name = name:find(":") and (name:find("^on") and name or resource_name..":"..name)
                or resource_name..":"..name
        end
        fired[full_name] = true
    end
    for evname in pairs(cl_data.event_handlers) do
        if not fired[evname] then
            log_cl("FIRE_EXTRA", evname)
            RT.fire_event(cl_env, evname)
            RT.run_threads(cl_env, max_ticks)
        end
    end

    -- ════════════════════════════════════════════════════════════════
    -- Coleta resultado final
    -- ════════════════════════════════════════════════════════════════
    local result = {
        resource     = resource_name,
        manifest     = manifest,
        all_files    = all_lua_files,
        extra_files  = extra_files,
        server       = RT.get_data(sv_env),
        client       = RT.get_data(cl_env),
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
