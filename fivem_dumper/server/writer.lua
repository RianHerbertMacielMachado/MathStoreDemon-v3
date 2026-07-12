-----------------------------------------------------------------------
-- fivem_dumper/server/writer.lua
--
-- Gera os arquivos de saída reconstruídos a partir dos dados
-- coletados pelo env instrumentado.
--
-- Saída (dentro de fivem_dumper/output/<resource>/):
--   server/main_reconstructed.lua
--   client/main_reconstructed.lua
--   shared/events_map.lua
--   shared/config_extracted.lua
--   ANALYSIS_REPORT.md
-----------------------------------------------------------------------

WRITER = {}  -- módulo global acessível por main.lua

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------
local function tcount(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    return keys
end

local function lua_string(s)
    s = tostring(s or "")
    s = s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n"):gsub("\r","\\r")
    return '"'..s..'"'
end

local function lua_val(v, depth)
    depth = depth or 0
    if depth > 4 then return "..." end
    local t = type(v)
    if t == "nil"     then return "nil" end
    if t == "boolean" then return tostring(v) end
    if t == "number"  then return tostring(v) end
    if t == "string"  then return lua_string(v) end
    if t == "table"   then
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 20 then parts[#parts+1] = "-- ... more"; break end
            local ks = type(k) == "number"
                and ("["..k.."]")
                or (k:match("^[%a_][%a%d_]*$") and k or ("["..lua_string(k).."]"))
            parts[#parts+1] = "    "..ks.." = "..lua_val(val, depth+1)..","
        end
        if #parts == 0 then return "{}" end
        return "{\n"..table.concat(parts, "\n").."\n}"
    end
    return "-- <"..t..">"
end

-----------------------------------------------------------------------
-- Escreve um arquivo via SaveResourceFile (cria dirs automaticamente)
-- e também via io.open como fallback.
-- SaveResourceFile só aceita paths relativos à raiz do resource.
-- Como os arquivos de output ficam DENTRO do fivem_dumper, calculamos
-- o path relativo a partir do GetResourcePath do dumper.
-----------------------------------------------------------------------
local _dumper_root = nil
local function get_dumper_root()
    if not _dumper_root then
        _dumper_root = GetResourcePath(GetCurrentResourceName())
            :gsub("\\","/"):gsub("/+","/"):gsub("/$","")
    end
    return _dumper_root
end

-- Cria cada nível de diretório via SaveResourceFile (toca um ._keep em cada dir)
-- SaveResourceFile não cria dirs aninhados de uma vez — precisamos tocar nível a nível.
local function ensure_dirs_srf(rel_dir)
    -- rel_dir ex: "output/vrp/server"
    -- Toca output/._keep, output/vrp/._keep, output/vrp/server/._keep
    local accumulated = ""
    for segment in rel_dir:gmatch("[^/]+") do
        accumulated = accumulated == "" and segment or (accumulated.."/"..segment)
        SaveResourceFile(GetCurrentResourceName(), accumulated.."/._keep", "", -1)
    end
end

local function write_file(abs_path, content)
    abs_path = abs_path:gsub("\\","/"):gsub("/+","/")

    -- Tenta: SaveResourceFile com criação prévia de cada nível de diretório
    local root = get_dumper_root()
    if abs_path:sub(1, #root) == root then
        -- rel = "output/vrp/server/main_reconstructed.lua"
        local rel = abs_path:sub(#root + 2)
        if rel and rel ~= "" then
            -- Cria todos os diretórios pai nível a nível
            local rel_dir = rel:match("^(.+)/[^/]+$")
            if rel_dir then
                ensure_dirs_srf(rel_dir)
            end
            -- Agora escreve o arquivo
            local ok = SaveResourceFile(GetCurrentResourceName(), rel, content, -1)
            if ok then return true end
            -- SaveResourceFile falhou mesmo após criar dirs — tenta io.open
        end
    end

    -- Fallback: io.open direto (funciona se o diretório já existir)
    local f, err = io.open(abs_path, "w")
    if not f then
        return false, "cannot write "..abs_path..": "..tostring(err)
    end
    f:write(content)
    f:close()
    return true
end

-----------------------------------------------------------------------
-- Detecta o tipo de um evento pelo nome
-----------------------------------------------------------------------
local function event_type(name)
    local n = name:lower()
    if n:find("anim")        then return "anim" end
    if n:find("rune")        then return "rune" end
    if n:find("hud")         then return "hud"  end
    if n:find("sound")       then return "sound" end
    if n:find("fly")         then return "fly"  end
    if n:find("spawn")       then return "spawn" end
    if n:find("remove")      then return "remove" end
    if n:find("sync")        then return "sync"  end
    if n:find("auth")        then return "auth"  end
    if n:find("connect")     then return "lifecycle" end
    if n:find("drop")        then return "lifecycle" end
    if n:find("start")       then return "lifecycle" end
    if n:find("stop")        then return "lifecycle" end
    return "generic"
end

-----------------------------------------------------------------------
-- Gera corpo de handler server-side baseado nos dados coletados
-----------------------------------------------------------------------
local function gen_sv_handler_body(eventName, hc, resource)
    if not hc then return "    -- handler não executado\nend)\n\n" end
    local lines = {}
    local indent = "    "

    -- Triggers para o cliente
    if hc.triggers_client and #hc.triggers_client > 0 then
        lines[#lines+1] = indent.."local src = source"
        for _, tc in ipairs(hc.triggers_client) do
            local tgt = tc.target == "ALL" and "-1" or "source"
            local args_s = ""
            if tc.args and #tc.args > 0 then
                local parts = {}
                for _, a in ipairs(tc.args) do
                    parts[#parts+1] = lua_val(a, 1)
                end
                args_s = ", "..table.concat(parts, ", ")
            end
            lines[#lines+1] = indent..string.format(
                'TriggerClientEvent(%s, %s%s)',
                lua_string(tc.name), tgt, args_s)
        end
    end

    -- Calls HTTP
    if hc.http_calls and #hc.http_calls > 0 then
        for _, req in ipairs(hc.http_calls) do
            lines[#lines+1] = indent..string.format(
                'PerformHttpRequest(%s, function(code, body) end, %s)',
                lua_string(req.url or ""), lua_string(req.method or "GET"))
        end
    end

    -- Natives chamados
    if hc.natives and #hc.natives > 0 then
        local seen = {}
        for _, n in ipairs(hc.natives) do
            if not seen[n.name] then
                seen[n.name] = true
                lines[#lines+1] = indent.."-- native: "..n.name
            end
        end
    end

    if #lines == 0 then
        lines[#lines+1] = indent.."-- sem chamadas observadas"
    end
    return table.concat(lines, "\n").."\nend)\n\n"
end

-----------------------------------------------------------------------
-- Gera corpo de handler client-side baseado nos dados coletados
-----------------------------------------------------------------------
local function gen_cl_handler_body(eventName, hc, resource)
    if not hc then return "    -- handler não executado\nend)\n\n" end
    local lines = {}
    local indent = "    "
    local ev_t   = event_type(eventName)

    -- Modelos
    if hc.models and #hc.models > 0 then
        lines[#lines+1] = indent.."-- models usados: "..table.concat(hc.models, ", ")
        for _, m in ipairs(hc.models) do
            lines[#lines+1] = indent..string.format(
                'local hash_%s = GetHashKey(%s)',
                m:gsub("[^%a%d]","_"), lua_string(m))
            lines[#lines+1] = indent.."RequestModel(hash_"..m:gsub("[^%a%d]","_")..")"
            lines[#lines+1] = indent.."while not HasModelLoaded(hash_"..m:gsub("[^%a%d]","_")..") do Wait(0) end"
        end
    end

    -- AnimDicts
    if hc.anims and #hc.anims > 0 then
        for _, d in ipairs(hc.anims) do
            lines[#lines+1] = indent.."RequestAnimDict("..lua_string(d)..")"
            lines[#lines+1] = indent.."while not HasAnimDictLoaded("..lua_string(d)..") do Wait(0) end"
        end
    end

    -- Anim plays
    if hc.anims_played and #hc.anims_played > 0 then
        for _, play in ipairs(hc.anims_played) do
            lines[#lines+1] = indent..string.format(
                'TaskPlayAnim(PlayerPedId(), %s, %s, 8.0, -8.0, -1, %d, 0, false, false, false)',
                lua_string(play.dict or ""), lua_string(play.clip or ""), play.flag or 0)
        end
    end

    -- Attach calls
    if hc.attach_calls and #hc.attach_calls > 0 then
        for _, ac in ipairs(hc.attach_calls) do
            lines[#lines+1] = indent..string.format(
                'AttachEntityToEntity(obj, PlayerPedId(), %d, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, false, false, false, false, 2, true)',
                ac.bone or 0,
                (ac.offset or {})[1] or 0, (ac.offset or {})[2] or 0, (ac.offset or {})[3] or 0,
                (ac.rot   or {})[1] or 0, (ac.rot   or {})[2] or 0, (ac.rot   or {})[3] or 0)
        end
    end

    -- NUI messages
    if hc.nui_messages and #hc.nui_messages > 0 then
        for _, msg in ipairs(hc.nui_messages) do
            lines[#lines+1] = indent.."SendNuiMessage("..lua_string(msg:sub(1,200))..")"
        end
    end

    -- Triggers server
    if hc.triggers_server and #hc.triggers_server > 0 then
        for _, ts in ipairs(hc.triggers_server) do
            local args_s = ""
            if ts.args and #ts.args > 0 then
                local parts = {}
                for _, a in ipairs(ts.args) do parts[#parts+1] = lua_val(a,1) end
                args_s = ", "..table.concat(parts, ", ")
            end
            lines[#lines+1] = indent.."TriggerServerEvent("..lua_string(ts.name)..args_s..")"
        end
    end

    -- Natives
    if hc.natives and #hc.natives > 0 then
        local seen = {}
        for _, n in ipairs(hc.natives) do
            if not seen[n.name] then
                seen[n.name] = true
                lines[#lines+1] = indent.."-- native: "..n.name
            end
        end
    end

    if #lines == 0 then
        if ev_t == "anim" then
            lines[#lines+1] = indent.."-- animação: ver anim_dicts e anim_plays acima"
        elseif ev_t == "rune" then
            lines[#lines+1] = indent.."-- rune: spawna objeto/modelo de runa"
        elseif ev_t == "spawn" then
            lines[#lines+1] = indent.."-- spawn: cria entidade"
        else
            lines[#lines+1] = indent.."-- sem chamadas observadas neste handler"
        end
    end

    return table.concat(lines, "\n").."\nend)\n\n"
end

-----------------------------------------------------------------------
-- Gera server/main_reconstructed.lua
-----------------------------------------------------------------------
local function gen_server(data, resource)
    local lines = {
        "-----------------------------------------------------------------------",
        "-- "..resource.." | server/main_reconstructed.lua",
        "-- Gerado por fivem_dumper v"..DUMPER_VERSION,
        "-- ATENÇÃO: estrutura reconstruída por análise dinâmica.",
        "-- Revise e ajuste conforme necessário.",
        "-----------------------------------------------------------------------",
        "",
    }

    -- RegisterNetEvent
    local net_evs = sorted_keys(data.net_events)
    if #net_evs > 0 then
        lines[#lines+1] = "-- ── Eventos de rede ──────────────────────────────────────────────"
        for _, name in ipairs(net_evs) do
            lines[#lines+1] = "RegisterNetEvent("..lua_string(name)..")"
        end
        lines[#lines+1] = ""
    end

    -- Comandos
    if #data.commands > 0 then
        lines[#lines+1] = "-- ── Comandos ─────────────────────────────────────────────────────"
        for _, cmd in ipairs(data.commands) do
            lines[#lines+1] = string.format(
                'RegisterCommand(%s, function(source, args, rawCommand)',
                lua_string(cmd.name))
            local hc = data.handler_calls["cmd:"..cmd.name]
            lines[#lines+1] = gen_sv_handler_body("cmd:"..cmd.name, hc, resource)
        end
    end

    -- onResourceStart
    lines[#lines+1] = "-- ── Lifecycle ────────────────────────────────────────────────────"
    lines[#lines+1] = "AddEventHandler('onResourceStart', function(resourceName)"
    lines[#lines+1] = "    if GetCurrentResourceName() ~= resourceName then return end"
    lines[#lines+1] = "    -- inicialização do resource"
    lines[#lines+1] = "end)\n"

    -- Handlers de eventos
    local ev_names = {}
    for _, ev in ipairs(data.events) do ev_names[#ev_names+1] = ev.name end

    -- Filtra lifecycle / net já registrados
    local lifecycle = { onResourceStart=true, onResourceStop=true,
                        playerConnecting=true, playerDropped=true }
    local sv_handlers = {}
    for _, name in ipairs(ev_names) do
        if not lifecycle[name] then
            sv_handlers[#sv_handlers+1] = name
        end
    end

    if #sv_handlers > 0 then
        lines[#lines+1] = "-- ── Handlers de eventos ──────────────────────────────────────────"
        for _, name in ipairs(sv_handlers) do
            local hc = data.handler_calls[name]
            lines[#lines+1] = "AddEventHandler("..lua_string(name)..", function(...)"
            lines[#lines+1] = gen_sv_handler_body(name, hc, resource)
        end
    end

    -- TriggerClientEvent calls observadas (server → client)
    if #data.client_events > 0 then
        lines[#lines+1] = "--[["
        lines[#lines+1] = "── TriggerClientEvent calls observadas ────────────────────────────"
        local seen = {}
        for _, ev in ipairs(data.client_events) do
            if not seen[ev.name] then
                seen[ev.name] = true
                lines[#lines+1] = string.format("  TriggerClientEvent(%s, src, ...)",
                    lua_string(ev.name))
            end
        end
        lines[#lines+1] = "--]]"
        lines[#lines+1] = ""
    end

    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Gera client/main_reconstructed.lua
-----------------------------------------------------------------------
local function gen_client(data, resource)
    local lines = {
        "-----------------------------------------------------------------------",
        "-- "..resource.." | client/main_reconstructed.lua",
        "-- Gerado por fivem_dumper v"..DUMPER_VERSION,
        "-----------------------------------------------------------------------",
        "",
    }

    -- Keybinds
    if #data.keybinds > 0 then
        lines[#lines+1] = "-- ── Keybinds ─────────────────────────────────────────────────────"
        for _, kb in ipairs(data.keybinds) do
            lines[#lines+1] = string.format(
                'RegisterKeyMapping(%s, %s, %s, %s)',
                lua_string(kb.command or ""),
                lua_string(kb.description or ""),
                lua_string(kb.inputType or "keyboard"),
                lua_string(kb.inputName or ""))
        end
        lines[#lines+1] = ""
    end

    -- NUI Callbacks
    if #data.nui_callbacks > 0 then
        lines[#lines+1] = "-- ── NUI Callbacks ────────────────────────────────────────────────"
        for _, nui in ipairs(data.nui_callbacks) do
            lines[#lines+1] = "RegisterNuiCallback("..lua_string(nui.name)..", function(data, cb)"
            lines[#lines+1] = "    cb({ ok = true })"
            lines[#lines+1] = "end)\n"
        end
    end

    -- AnimDicts usados (fora de handlers)
    local global_dicts = {}
    for d in pairs(data.anim_dicts) do global_dicts[#global_dicts+1] = d end
    table.sort(global_dicts)
    if #global_dicts > 0 then
        lines[#lines+1] = "-- ── AnimDicts usados ─────────────────────────────────────────────"
        lines[#lines+1] = "-- "..table.concat(global_dicts, ", ")
        lines[#lines+1] = ""
    end

    -- Modelos usados (fora de handlers)
    local global_models = sorted_keys(data.models)
    if #global_models > 0 then
        lines[#lines+1] = "-- ── Modelos (GetHashKey/RequestModel) ────────────────────────────"
        for _, m in ipairs(global_models) do
            lines[#lines+1] = "-- "..m
        end
        lines[#lines+1] = ""
    end

    -- Handlers de eventos
    local ev_names = {}
    for _, ev in ipairs(data.events) do ev_names[#ev_names+1] = ev.name end

    if #ev_names > 0 then
        lines[#lines+1] = "-- ── Handlers de eventos ──────────────────────────────────────────"
        for _, name in ipairs(ev_names) do
            local hc = data.handler_calls[name]
            lines[#lines+1] = "AddEventHandler("..lua_string(name)..", function(...)"
            lines[#lines+1] = gen_cl_handler_body(name, hc, resource)
        end
    end

    -- AttachEntityToEntity calls globais
    if #data.attach_calls > 0 then
        lines[#lines+1] = "--[[ AttachEntityToEntity calls observadas:"
        for _, ac in ipairs(data.attach_calls) do
            lines[#lines+1] = string.format(
                "  bone=%d offset=(%.2f,%.2f,%.2f) rot=(%.2f,%.2f,%.2f)",
                ac.bone or 0,
                (ac.offset or {})[1] or 0, (ac.offset or {})[2] or 0, (ac.offset or {})[3] or 0,
                (ac.rot   or {})[1] or 0, (ac.rot   or {})[2] or 0, (ac.rot   or {})[3] or 0)
        end
        lines[#lines+1] = "--]]"
        lines[#lines+1] = ""
    end

    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Gera shared/events_map.lua
-----------------------------------------------------------------------
local function gen_events_map(sv_data, cl_data, resource)
    local lines = {
        "-----------------------------------------------------------------------",
        "-- "..resource.." | shared/events_map.lua",
        "-- Mapa de todos os eventos observados (server + client)",
        "-- Gerado por fivem_dumper v"..DUMPER_VERSION,
        "-----------------------------------------------------------------------",
        "",
        "E = {",
    }

    -- Coleta todos os eventos únicos
    local all_events = {}
    local seen = {}
    for _, ev in ipairs(sv_data.events) do
        if not seen[ev.name] then
            seen[ev.name] = true
            all_events[#all_events+1] = { name=ev.name, side="SERVER" }
        end
    end
    for _, ev in ipairs(cl_data.events) do
        if not seen[ev.name] then
            seen[ev.name] = true
            all_events[#all_events+1] = { name=ev.name, side="CLIENT" }
        end
    end

    -- Ordena por nome
    table.sort(all_events, function(a,b) return a.name < b.name end)

    for _, ev in ipairs(all_events) do
        -- Gera chave limpa: tira prefixo de resource, transforma : em _
        local key = ev.name
            :gsub("^"..resource..":", "")
            :gsub(":", "_")
            :gsub("[^%a%d_]", "_")
            :upper()
        if key == "" then key = "EV_UNKNOWN" end
        lines[#lines+1] = string.format(
            '    %-40s = %s,  -- [%s]',
            key, lua_string(ev.name), ev.side)
    end

    lines[#lines+1] = "}"
    lines[#lines+1] = ""
    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Gera shared/config_extracted.lua
-----------------------------------------------------------------------
local function gen_config(sv_data, cl_data, resource)
    local lines = {
        "-----------------------------------------------------------------------",
        "-- "..resource.." | shared/config_extracted.lua",
        "-- Variáveis globais capturadas durante a análise dinâmica",
        "-- Gerado por fivem_dumper v"..DUMPER_VERSION,
        "-----------------------------------------------------------------------",
        "",
        "Config = Config or {}",
        "",
    }

    -- Globals do servidor
    local sv_keys = sorted_keys(sv_data.globals_set)
    if #sv_keys > 0 then
        lines[#lines+1] = "-- ── Globals do servidor ───────────────────────────────────────────"
        for _, k in ipairs(sv_keys) do
            local v = sv_data.globals_set[k]
            lines[#lines+1] = k.." = "..lua_val(v)
        end
        lines[#lines+1] = ""
    end

    -- Globals do cliente
    local cl_keys = sorted_keys(cl_data.globals_set)
    if #cl_keys > 0 then
        lines[#lines+1] = "-- ── Globals do cliente ────────────────────────────────────────────"
        for _, k in ipairs(cl_keys) do
            local v = cl_data.globals_set[k]
            lines[#lines+1] = k.." = "..lua_val(v)
        end
        lines[#lines+1] = ""
    end

    -- Convars lidas
    local all_convars = {}
    for k, v in pairs(sv_data.convars_read) do all_convars[k] = v end
    for k, v in pairs(cl_data.convars_read) do all_convars[k] = v end
    if next(all_convars) then
        lines[#lines+1] = "-- ── Convars lidas ─────────────────────────────────────────────────"
        for k, v in pairs(all_convars) do
            lines[#lines+1] = string.format('-- GetConvar(%s) default=%s', lua_string(k), lua_val(v))
        end
        lines[#lines+1] = ""
    end

    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Gera ANALYSIS_REPORT.md
-----------------------------------------------------------------------
local function gen_report(sv_data, cl_data, resource, elapsed_ms)
    local lines = {
        "# Análise Dinâmica: "..resource,
        "",
        "> Gerado por **fivem_dumper v"..DUMPER_VERSION.."**  ",
        "> Tempo de análise: **"..tostring(elapsed_ms).."ms**",
        "",
        "---",
        "",
        "## Servidor",
        "",
        string.format("| Métrica | Valor |"),
        "|---------|-------|",
        string.format("| Eventos registrados | %d |", #sv_data.events),
        string.format("| Eventos de rede | %d |", tcount(sv_data.net_events)),
        string.format("| Comandos | %d |", #sv_data.commands),
        string.format("| TriggerClientEvent calls | %d |", #sv_data.client_events),
        string.format("| HTTP requests | %d |", #sv_data.http_requests),
        string.format("| Threads criadas | %d |", sv_data.thread_count),
        "",
    }

    if #sv_data.commands > 0 then
        lines[#lines+1] = "### Comandos registrados"
        lines[#lines+1] = ""
        for _, cmd in ipairs(sv_data.commands) do
            lines[#lines+1] = string.format("- `/%s` (restricted=%s)",
                cmd.name, tostring(cmd.restricted))
        end
        lines[#lines+1] = ""
    end

    if tcount(sv_data.net_events) > 0 then
        lines[#lines+1] = "### Eventos de rede (servidor)"
        lines[#lines+1] = ""
        for _, name in ipairs(sorted_keys(sv_data.net_events)) do
            lines[#lines+1] = "- `"..name.."`"
        end
        lines[#lines+1] = ""
    end

    lines[#lines+1] = "---"
    lines[#lines+1] = ""
    lines[#lines+1] = "## Cliente"
    lines[#lines+1] = ""
    lines[#lines+1] = "| Métrica | Valor |"
    lines[#lines+1] = "|---------|-------|"
    lines[#lines+1] = string.format("| Eventos registrados | %d |", #cl_data.events)
    lines[#lines+1] = string.format("| Keybinds | %d |", #cl_data.keybinds)
    lines[#lines+1] = string.format("| NUI Callbacks | %d |", #cl_data.nui_callbacks)
    lines[#lines+1] = string.format("| TriggerServerEvent calls | %d |", #cl_data.server_events)
    lines[#lines+1] = string.format("| Modelos usados | %d |", tcount(cl_data.models))
    lines[#lines+1] = string.format("| AnimDicts | %d |", tcount(cl_data.anim_dicts))
    lines[#lines+1] = string.format("| Clips de animação | %d |", #cl_data.anim_plays)
    lines[#lines+1] = string.format("| AttachEntityToEntity | %d |", #cl_data.attach_calls)
    lines[#lines+1] = string.format("| State bag handlers | %d |", #cl_data.state_bag_keys)
    lines[#lines+1] = string.format("| Threads criadas | %d |", cl_data.thread_count)
    lines[#lines+1] = ""

    if #cl_data.keybinds > 0 then
        lines[#lines+1] = "### Keybinds"
        lines[#lines+1] = ""
        lines[#lines+1] = "| Comando | Descrição | Tipo | Tecla |"
        lines[#lines+1] = "|---------|-----------|------|-------|"
        for _, kb in ipairs(cl_data.keybinds) do
            lines[#lines+1] = string.format("| `/%s` | %s | %s | %s |",
                tostring(kb.command), tostring(kb.description),
                tostring(kb.inputType), tostring(kb.inputName))
        end
        lines[#lines+1] = ""
    end

    if tcount(cl_data.anim_dicts) > 0 then
        lines[#lines+1] = "### AnimDicts usados"
        lines[#lines+1] = ""
        for _, d in ipairs(sorted_keys(cl_data.anim_dicts)) do
            lines[#lines+1] = "- `"..d.."`"
        end
        lines[#lines+1] = ""
    end

    if tcount(cl_data.models) > 0 then
        lines[#lines+1] = "### Modelos"
        lines[#lines+1] = ""
        for _, m in ipairs(sorted_keys(cl_data.models)) do
            lines[#lines+1] = "- `"..m.."`"
        end
        lines[#lines+1] = ""
    end

    if #cl_data.attach_calls > 0 then
        lines[#lines+1] = "### AttachEntityToEntity"
        lines[#lines+1] = ""
        lines[#lines+1] = "| Bone | Offset | Rotation |"
        lines[#lines+1] = "|------|--------|----------|"
        for _, ac in ipairs(cl_data.attach_calls) do
            lines[#lines+1] = string.format("| %d | (%.2f, %.2f, %.2f) | (%.2f, %.2f, %.2f) |",
                ac.bone or 0,
                (ac.offset or {})[1] or 0, (ac.offset or {})[2] or 0, (ac.offset or {})[3] or 0,
                (ac.rot   or {})[1] or 0, (ac.rot   or {})[2] or 0, (ac.rot   or {})[3] or 0)
        end
        lines[#lines+1] = ""
    end

    -- Eventos server → client
    if #sv_data.client_events > 0 then
        lines[#lines+1] = "---"
        lines[#lines+1] = ""
        lines[#lines+1] = "## TriggerClientEvent (server → client)"
        lines[#lines+1] = ""
        local seen = {}
        for _, ev in ipairs(sv_data.client_events) do
            if not seen[ev.name] then
                seen[ev.name] = true
                lines[#lines+1] = "- `"..ev.name.."`"
            end
        end
        lines[#lines+1] = ""
    end

    -- HTTP
    if #sv_data.http_requests > 0 then
        lines[#lines+1] = "---"
        lines[#lines+1] = ""
        lines[#lines+1] = "## HTTP Requests"
        lines[#lines+1] = ""
        for _, req in ipairs(sv_data.http_requests) do
            lines[#lines+1] = string.format("- `%s %s`",
                req.method or "GET", req.url or "?")
        end
        lines[#lines+1] = ""
    end

    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Função principal: gera todos os arquivos de saída
-- Retorna lista de arquivos escritos ou nil, errmsg
-----------------------------------------------------------------------
function WRITER.generate(sv_data, cl_data, resource, output_base, elapsed_ms)
    elapsed_ms = elapsed_ms or 0
    local out   = output_base  -- ex: fivem_dumper/output/MathStoreFairyWingv6

    local files = {}
    local function write(rel, content)
        local path = out.."/"..rel
        local ok, err = write_file(path, content)
        if ok then
            files[#files+1] = path
            print("^2[Dumper] ✓ "..path.."^7")
        else
            print("^1[Dumper] ERRO ao escrever "..path..": "..(err or "?").."^7")
        end
    end

    write("server/main_reconstructed.lua",
        gen_server(sv_data, resource))

    write("client/main_reconstructed.lua",
        gen_client(cl_data, resource))

    write("shared/events_map.lua",
        gen_events_map(sv_data, cl_data, resource))

    write("shared/config_extracted.lua",
        gen_config(sv_data, cl_data, resource))

    write("ANALYSIS_REPORT.md",
        gen_report(sv_data, cl_data, resource, elapsed_ms))

    return files
end
