-----------------------------------------------------------------------
-- fivem_dumper/server/writer.lua
--
-- Gera os arquivos de output a partir dos dados coletados pelo COLLECTOR.
-- Saída em: fivem_dumper/output/<resourceName>/
--   ANALYSIS_REPORT.md
--   events_map.lua
--   commands_list.lua
--   api_calls.lua
-----------------------------------------------------------------------

WRITER = {}

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------
local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = tostring(k) end
    table.sort(keys)
    return keys
end

local function tcount(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function lua_str(s)
    s = tostring(s or "")
    s = s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n"):gsub("\r","\\r")
    return '"'..s..'"'
end

-----------------------------------------------------------------------
-- Escreve um arquivo relativo ao fivem_dumper via SaveResourceFile.
-- Cria cada nível de diretório tocando um ._keep antes.
-----------------------------------------------------------------------
local _res = GetCurrentResourceName()

local function ensure_dirs(rel_dir)
    local acc = ""
    for seg in rel_dir:gmatch("[^/]+") do
        acc = acc == "" and seg or (acc.."/"..seg)
        SaveResourceFile(_res, acc.."/._keep", "", -1)
    end
end

local function write_file(rel_path, content)
    local dir = rel_path:match("^(.+)/[^/]+$")
    if dir then ensure_dirs(dir) end
    local ok = SaveResourceFile(_res, rel_path, content, -1)
    if ok then
        print("^2[Dumper] ✓ "..rel_path.."^7")
    else
        print("^1[Dumper] ERRO ao escrever "..rel_path.."^7")
    end
    return ok
end

-----------------------------------------------------------------------
-- Gera ANALYSIS_REPORT.md
-----------------------------------------------------------------------
local function gen_report(d, elapsed_ms)
    local res = d.resource
    local lines = {
        "# Análise: "..res,
        "",
        "> Gerado por **fivem_dumper v"..DUMPER_VERSION.."**  ",
        "> Tempo de análise: **"..tostring(elapsed_ms).."ms**",
        "> Método: **interceptação nativa de APIs FiveM** (sem execução fake)",
        "",
        "---",
        "",
        "## Resumo",
        "",
        "| Métrica | Valor |",
        "|---------|-------|",
        string.format("| Eventos registrados (AddEventHandler) | %d |", tcount(d.events)),
        string.format("| Eventos de rede (RegisterNetEvent) | %d |", tcount(d.net_events)),
        string.format("| Comandos registrados | %d |", tcount(d.commands)),
        string.format("| TriggerClientEvent calls | %d |", tcount(d.client_events)),
        string.format("| TriggerEvent calls | %d |", tcount(d.sv_events)),
        string.format("| HTTP requests | %d |", #d.http_requests),
        string.format("| GetConvar calls | %d |", tcount(d.convars)),
        string.format("| CreateThread calls | %d |", d.threads or 0),
        string.format("| StateBag handlers | %d |", tcount(d.state_bags)),
        "",
    }

    -- Eventos
    local ev_keys = sorted_keys(d.events)
    if #ev_keys > 0 then
        lines[#lines+1] = "## Eventos (AddEventHandler)"
        lines[#lines+1] = ""
        for _, name in ipairs(ev_keys) do
            lines[#lines+1] = "- `"..name.."`"
        end
        lines[#lines+1] = ""
    end

    -- Net Events
    local net_keys = sorted_keys(d.net_events)
    if #net_keys > 0 then
        lines[#lines+1] = "## Eventos de Rede (RegisterNetEvent)"
        lines[#lines+1] = ""
        for _, name in ipairs(net_keys) do
            lines[#lines+1] = "- `"..name.."`"
        end
        lines[#lines+1] = ""
    end

    -- Comandos
    local cmd_keys = sorted_keys(d.commands)
    if #cmd_keys > 0 then
        lines[#lines+1] = "## Comandos"
        lines[#lines+1] = ""
        lines[#lines+1] = "| Comando | Restricted |"
        lines[#lines+1] = "|---------|------------|"
        for _, name in ipairs(cmd_keys) do
            local c = d.commands[name]
            lines[#lines+1] = string.format("| `/%s` | %s |",
                name, tostring(c and c.restricted or false))
        end
        lines[#lines+1] = ""
    end

    -- TriggerClientEvent
    local ce_keys = sorted_keys(d.client_events)
    if #ce_keys > 0 then
        lines[#lines+1] = "## TriggerClientEvent (server → client)"
        lines[#lines+1] = ""
        for _, name in ipairs(ce_keys) do
            lines[#lines+1] = string.format("- `%s` (%dx)", name, d.client_events[name])
        end
        lines[#lines+1] = ""
    end

    -- HTTP
    if #d.http_requests > 0 then
        lines[#lines+1] = "## HTTP Requests"
        lines[#lines+1] = ""
        for _, req in ipairs(d.http_requests) do
            lines[#lines+1] = string.format("- `%s %s`", req.method, req.url)
        end
        lines[#lines+1] = ""
    end

    -- Convars
    local cv_keys = sorted_keys(d.convars)
    if #cv_keys > 0 then
        lines[#lines+1] = "## Convars lidas"
        lines[#lines+1] = ""
        for _, name in ipairs(cv_keys) do
            lines[#lines+1] = string.format("- `%s` (default: `%s`)", name, tostring(d.convars[name]))
        end
        lines[#lines+1] = ""
    end

    -- StateBags
    local sb_keys = sorted_keys(d.state_bags)
    if #sb_keys > 0 then
        lines[#lines+1] = "## StateBag handlers"
        lines[#lines+1] = ""
        for _, key in ipairs(sb_keys) do
            lines[#lines+1] = "- `"..key.."`"
        end
        lines[#lines+1] = ""
    end

    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Gera events_map.lua
-----------------------------------------------------------------------
local function gen_events_map(d)
    local res = d.resource
    local lines = {
        "-----------------------------------------------------------------------",
        "-- "..res.." | events_map.lua",
        "-- Gerado por fivem_dumper v"..DUMPER_VERSION,
        "-- Todos os eventos observados durante a inicialização do resource.",
        "-----------------------------------------------------------------------",
        "",
        "local EVENTS = {",
    }

    -- Coleta todos os eventos únicos
    local all = {}
    local seen = {}
    for name in pairs(d.events) do
        if not seen[name] then seen[name]=true; all[#all+1]={name=name,type="handler"} end
    end
    for name in pairs(d.net_events) do
        if not seen[name] then seen[name]=true; all[#all+1]={name=name,type="net"} end
    end
    for name in pairs(d.client_events) do
        if not seen[name] then seen[name]=true; all[#all+1]={name=name,type="client_trigger"} end
    end
    table.sort(all, function(a,b) return a.name < b.name end)

    for _, ev in ipairs(all) do
        -- Gera chave Lua válida
        local key = ev.name
            :gsub("^"..res..":", "")
            :gsub("[^%a%d_]", "_")
            :upper()
        if key == "" or key:match("^%d") then key = "EV_"..key end
        lines[#lines+1] = string.format(
            "    %-50s = %s,  -- [%s]",
            key, lua_str(ev.name), ev.type)
    end

    lines[#lines+1] = "}"
    lines[#lines+1] = ""
    lines[#lines+1] = "return EVENTS"
    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Gera commands_list.lua
-----------------------------------------------------------------------
local function gen_commands(d)
    local res = d.resource
    local lines = {
        "-----------------------------------------------------------------------",
        "-- "..res.." | commands_list.lua",
        "-- Gerado por fivem_dumper v"..DUMPER_VERSION,
        "-----------------------------------------------------------------------",
        "",
        "local COMMANDS = {",
    }
    for _, name in ipairs(sorted_keys(d.commands)) do
        local c = d.commands[name]
        lines[#lines+1] = string.format(
            "    { command = %-30s restricted = %s },",
            lua_str(name)..",", tostring(c and c.restricted or false))
    end
    lines[#lines+1] = "}"
    lines[#lines+1] = ""
    lines[#lines+1] = "return COMMANDS"
    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Gera api_calls.lua — resumo de todas as chamadas de API observadas
-----------------------------------------------------------------------
local function gen_api_calls(d)
    local res = d.resource
    local lines = {
        "-----------------------------------------------------------------------",
        "-- "..res.." | api_calls.lua",
        "-- Gerado por fivem_dumper v"..DUMPER_VERSION,
        "-- Chamadas de API capturadas durante a inicialização real do resource.",
        "-----------------------------------------------------------------------",
        "",
    }

    lines[#lines+1] = "-- ── TriggerClientEvent calls ─────────────────────────────────────"
    for _, name in ipairs(sorted_keys(d.client_events)) do
        lines[#lines+1] = string.format("-- TriggerClientEvent(%s, src)  [x%d]",
            lua_str(name), d.client_events[name])
    end
    lines[#lines+1] = ""

    lines[#lines+1] = "-- ── PerformHttpRequest calls ─────────────────────────────────────"
    for _, req in ipairs(d.http_requests) do
        lines[#lines+1] = string.format("-- PerformHttpRequest(%s, cb, %s)",
            lua_str(req.url), lua_str(req.method))
    end
    lines[#lines+1] = ""

    lines[#lines+1] = "-- ── GetConvar calls ──────────────────────────────────────────────"
    for _, name in ipairs(sorted_keys(d.convars)) do
        lines[#lines+1] = string.format("-- GetConvar(%s, %s)",
            lua_str(name), lua_str(tostring(d.convars[name])))
    end
    lines[#lines+1] = ""

    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Função principal: gera todos os arquivos de output
-----------------------------------------------------------------------
function WRITER.generate(resource_name, elapsed_ms)
    local d = COLLECTOR._data[resource_name]
    if not d then
        print("^1[Dumper] Sem dados para: "..tostring(resource_name).."^7")
        return 0
    end

    local base = "output/"..resource_name
    local count = 0

    if write_file(base.."/ANALYSIS_REPORT.md",
        gen_report(d, elapsed_ms)) then count=count+1 end

    if write_file(base.."/events_map.lua",
        gen_events_map(d)) then count=count+1 end

    if write_file(base.."/commands_list.lua",
        gen_commands(d)) then count=count+1 end

    if write_file(base.."/api_calls.lua",
        gen_api_calls(d)) then count=count+1 end

    return count
end
