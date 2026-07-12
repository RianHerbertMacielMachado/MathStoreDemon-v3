-----------------------------------------------------------------------
-- fivem_deob/reconstructor.lua
-- Reconstrói arquivos Lua LEGÍVEIS a partir dos dados extraídos
-- pelo extractor. Cria:
--   output/server/main_reconstructed.lua
--   output/server/core_reconstructed.lua
--   output/client/main_reconstructed.lua
--   output/client/events_reconstructed.lua
--   output/shared/events_map.lua
--   output/ANALYSIS_REPORT.md
-----------------------------------------------------------------------

local REC = {}

-- ── Helpers de formatação ────────────────────────────────────────────
local function indent(n) return string.rep("    ", n) end

local function comment_block(lines)
    local out = { "-----------------------------------------------------------------------" }
    for _, l in ipairs(lines) do out[#out+1] = "-- "..l end
    out[#out+1] = "-----------------------------------------------------------------------"
    return table.concat(out, "\n")
end

local function section(title)
    return string.format(
        "\n%s\n-- %-65s --\n%s\n",
        string.rep("-",71), title, string.rep("-",71)
    )
end

-- ── Serializa uma tabela Lua de forma legível ───────────────────────
local function lua_val(v, depth, seen)
    depth = depth or 0; seen = seen or {}
    local t = type(v)
    if t == "nil"     then return "nil" end
    if t == "boolean" then return tostring(v) end
    if t == "number"  then return tostring(v) end
    if t == "string"  then
        -- escapa corretamente
        local s = v:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n"):gsub("\r","\\r")
        return '"'..s..'"'
    end
    if t == "function" then return "--[[function]]nil" end
    if t == "table" then
        if seen[v] then return "--[[cycle]]nil" end
        if depth > 4 then return "{--[[...]]}" end
        seen[v] = true
        local parts, is_arr = {}, true
        local n = 0
        for k in pairs(v) do
            n = n+1
            if type(k)~="number" or k~=math.floor(k) or k<=0 then is_arr=false end
        end
        if is_arr and n==#v then
            for _, val in ipairs(v) do
                parts[#parts+1] = indent(depth+1)..lua_val(val,depth+1,seen)
            end
            seen[v] = nil
            if #parts == 0 then return "{}" end
            return "{\n"..table.concat(parts,",\n").."\n"..indent(depth).."}"
        else
            for k, val in pairs(v) do
                local key = type(k)=="string"
                    and (k:match("^[a-zA-Z_][a-zA-Z0-9_]*$") and k or '["'..k..'"]')
                    or ("["..tostring(k).."]")
                parts[#parts+1] = indent(depth+1)..key.." = "..lua_val(val,depth+1,seen)
            end
            seen[v] = nil
            if #parts == 0 then return "{}" end
            table.sort(parts)
            return "{\n"..table.concat(parts,",\n").."\n"..indent(depth).."}"
        end
    end
    return '"<'..t..'>"'
end

-- ── Gera header padrão ──────────────────────────────────────────────
local function file_header(filename, description, resource, auto)
    return comment_block({
        filename,
        "Resource: "..tostring(resource),
        "Description: "..tostring(description),
        "",
        "ARQUIVO RECONSTRUÍDO AUTOMATICAMENTE",
        "Gerado por fivem_deob em: "..os.date("%Y-%m-%d %H:%M:%S"),
        "",
        auto and "Este arquivo foi reconstruído com base na análise dinâmica" or "",
        auto and "dos scripts obfuscados. Revise e ajuste conforme necessário." or "",
    })
end

-- ════════════════════════════════════════════════════════════════════
-- Reconstrói server/main_reconstructed.lua
-- ════════════════════════════════════════════════════════════════════
local function build_server_main(result)
    local lines = {}
    local sv    = result.server
    local res   = result.resource
    local cfg   = result.shared_globals.Config or {}
    local E     = result.shared_globals.E or {}

    lines[#lines+1] = file_header("server/main_reconstructed.lua",
        "Lógica principal do servidor — reconstruída via análise dinâmica", res, true)

    lines[#lines+1] = section("DEPENDÊNCIAS")
    lines[#lines+1] = [[-- Este arquivo depende de server/core.lua (carregado antes)
-- e de bridge/server.lua (framework detection).
-- Globals esperados: Config, E, Bridge, PlayerWings, PlayerTails, WingObjects, TailObjects]]

    lines[#lines+1] = section("EVENTOS NET REGISTRADOS")
    lines[#lines+1] = "-- Eventos de rede descobertos durante a simulação:"
    local net_list = {}
    for name in pairs(sv.net_events) do net_list[#net_list+1] = name end
    table.sort(net_list)
    for _, name in ipairs(net_list) do
        lines[#lines+1] = "-- RegisterNetEvent(\""..name.."\")"
    end

    lines[#lines+1] = section("COMANDOS")
    if #sv.commands == 0 then
        lines[#lines+1] = "-- Nenhum comando registrado diretamente neste lado (server)."
        lines[#lines+1] = "-- Comandos podem estar em server/core.lua ou server/main.lua original."
    else
        for _, cmd in ipairs(sv.commands) do
            lines[#lines+1] = ""
            lines[#lines+1] = string.format(
                "-- COMANDO: /%s  (restricted=%s)", cmd.name, tostring(cmd.restricted))
            lines[#lines+1] = string.format(
                'RegisterCommand("%s", function(source, args, rawCommand)', cmd.name)
            lines[#lines+1] = '    -- TODO: implementar lógica do comando'
            lines[#lines+1] = '    -- args[1] = primeiro argumento (ex: número de cor)'
            lines[#lines+1] = 'end, '..tostring(cmd.restricted)..')'
        end
    end

    lines[#lines+1] = section("EVENTOS DISPARO → CLIENTE")
    if #sv.client_events == 0 then
        lines[#lines+1] = "-- Nenhum TriggerClientEvent observado na simulação."
    else
        -- Agrupa por nome
        local seen = {}
        for _, ev in ipairs(sv.client_events) do
            if not seen[ev.name] then
                seen[ev.name] = true
                lines[#lines+1] = "-- TriggerClientEvent(\""..ev.name.."\", target, ...)"
            end
        end
    end

    lines[#lines+1] = section("EVENTOS RECEBIDOS DO CLIENTE")
    -- Eventos que o server registra handlers
    local ev_list = {}
    for _, ev in ipairs(sv.events) do ev_list[#ev_list+1] = ev.name end
    table.sort(ev_list)
    for _, name in ipairs(ev_list) do
        lines[#lines+1] = ""
        lines[#lines+1] = "-- EVENTO RECEBIDO: "..name
        lines[#lines+1] = 'RegisterNetEvent("'..name..'")'
        lines[#lines+1] = 'AddEventHandler("'..name..'", function(...)'
        lines[#lines+1] = '    local src = source'
        lines[#lines+1] = '    -- TODO: lógica do handler'
        lines[#lines+1] = 'end)'
    end

    lines[#lines+1] = section("HTTP REQUESTS OBSERVADAS")
    if #sv.http_requests == 0 then
        lines[#lines+1] = "-- Nenhuma requisição HTTP observada."
    else
        for _, req in ipairs(sv.http_requests) do
            lines[#lines+1] = string.format(
                "-- %s %s", req.method or "GET", tostring(req.url))
        end
    end

    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════════════
-- Reconstrói client/main_reconstructed.lua
-- ════════════════════════════════════════════════════════════════════
local function build_client_main(result)
    local lines = {}
    local cl    = result.client
    local res   = result.resource
    local E     = result.shared_globals.E or {}
    local cfg   = result.shared_globals.Config or {}

    lines[#lines+1] = file_header("client/main_reconstructed.lua",
        "Lógica principal do cliente — reconstruída via análise dinâmica", res, true)

    lines[#lines+1] = section("VARIÁVEIS DE ESTADO")
    lines[#lines+1] = [[local _wingEntity    = nil   -- entidade das asas
local _tailEntity    = nil   -- entidade da cauda
local _wingColor     = 0     -- cor atual das asas
local _tailColor     = 0     -- cor atual da cauda
local _wingActive    = false -- asas visíveis
local _tailActive    = false -- cauda visível
local _isFlying      = false -- modo de voo ativo
local _animProtPrio  = nil   -- prioridade animprotect atual]]

    -- Keybinds
    if #cl.keybinds > 0 then
        lines[#lines+1] = section("KEYBINDS")
        for _, kb in ipairs(cl.keybinds) do
            lines[#lines+1] = string.format(
                'RegisterKeyMapping("%s", "%s", "%s", "%s")',
                tostring(kb.command), tostring(kb.description),
                tostring(kb.inputType), tostring(kb.inputName))
        end
    end

    -- NUI Callbacks
    if #cl.nui_callbacks > 0 then
        lines[#lines+1] = section("NUI CALLBACKS")
        for _, nui in ipairs(cl.nui_callbacks) do
            lines[#lines+1] = ""
            lines[#lines+1] = "-- NUI Callback: "..nui.name
            lines[#lines+1] = 'RegisterNUICallback("'..nui.name..'", function(data, cb)'
            lines[#lines+1] = '    -- TODO: lógica NUI para "'..nui.name..'"'
            lines[#lines+1] = '    cb({ status = "ok" })'
            lines[#lines+1] = 'end)'
        end
    end

    -- State bag handlers
    if #cl.state_bag_keys > 0 then
        lines[#lines+1] = section("STATE BAG HANDLERS")
        for _, sb in ipairs(cl.state_bag_keys) do
            lines[#lines+1] = string.format(
                'AddStateBagChangeHandler("%s", "%s", function(bagName, key, value, reserved, replicated)',
                sb.key, sb.bag)
            lines[#lines+1] = '    -- TODO: reagir à mudança de state bag'
            lines[#lines+1] = 'end)'
        end
    end

    -- Eventos net (handlers do cliente)
    lines[#lines+1] = section("EVENTOS DE REDE (CLIENT HANDLERS)")
    local ev_list = {}
    for _, ev in ipairs(cl.events) do ev_list[#ev_list+1] = ev.name end
    table.sort(ev_list)

    for _, name in ipairs(ev_list) do
        -- Classifica o tipo de evento
        local tag = ""
        if name:find(":spawn$") then tag = " -- Spawna entidade"
        elseif name:find(":remove$") or name:find(":remove$") then tag = " -- Remove entidade"
        elseif name:find(":abrir$") or name:find(":fechar$") or name:find(":bater$") then tag = " -- Animação de asa"
        elseif name:find("tail:") then tag = " -- Cauda"
        elseif name:find("sync:") then tag = " -- Sincronização multiplayer"
        elseif name:find("animprotect") then tag = " -- Sistema de proteção de animação"
        elseif name:find("flight:") then tag = " -- Sistema de voo"
        elseif name:find("auth") then tag = " -- Autenticação/autorização"
        end
        lines[#lines+1] = ""
        lines[#lines+1] = "RegisterNetEvent(\""..name.."\")"
        lines[#lines+1] = "AddEventHandler(\""..name.."\", function(...)"..tag
        lines[#lines+1] = "    -- TODO: implementar handler"
        lines[#lines+1] = "end)"
    end

    -- Animações descobertas
    if next(cl.anim_dicts) then
        lines[#lines+1] = section("ANIMAÇÕES DESCOBERTAS")
        lines[#lines+1] = "-- Dicionários de animação utilizados:"
        local dicts = {}
        for dict in pairs(cl.anim_dicts) do dicts[#dicts+1] = dict end
        table.sort(dicts)
        for _, dict in ipairs(dicts) do
            lines[#lines+1] = '--   RequestAnimDict("'..dict..'")'
        end
        if #cl.anim_plays > 0 then
            lines[#lines+1] = ""
            lines[#lines+1] = "-- Clips de animação observados:"
            local seen = {}
            for _, play in ipairs(cl.anim_plays) do
                local key = (play.dict or "?")..":"..(play.clip or "?")
                if not seen[key] then
                    seen[key] = true
                    lines[#lines+1] = string.format(
                        '--   TaskPlayAnim(ped, "%s", "%s", ...)',
                        tostring(play.dict), tostring(play.clip))
                end
            end
        end
    end

    -- Modelos descobertos
    if next(cl.models) then
        lines[#lines+1] = section("MODELOS DESCOBERTOS")
        lines[#lines+1] = "-- Modelos requisitados/hasheados durante a simulação:"
        local models = {}
        for m in pairs(cl.models) do models[#models+1] = m end
        table.sort(models)
        for _, m in ipairs(models) do
            lines[#lines+1] = '--   GetHashKey("'..m..'")'
        end
    end

    -- AttachEntityToEntity calls
    if #cl.attach_calls > 0 then
        lines[#lines+1] = section("ATTACH CALLS (BONES)")
        lines[#lines+1] = "-- Chamadas AttachEntityToEntity observadas:"
        for _, a in ipairs(cl.attach_calls) do
            lines[#lines+1] = string.format(
                "--   entity=%d to=%d bone=%d off=(%.2f,%.2f,%.2f) rot=(%.2f,%.2f,%.2f)",
                a.entity or 0, a.entityTo or 0, a.bone or 0,
                a.offset[1] or 0, a.offset[2] or 0, a.offset[3] or 0,
                a.rot[1] or 0, a.rot[2] or 0, a.rot[3] or 0)
        end
        lines[#lines+1] = ""
        lines[#lines+1] = "-- Bones usados:"
        local bones = {}
        for b in pairs(cl.bones_used) do bones[#bones+1] = b end
        table.sort(bones)
        for _, b in ipairs(bones) do
            lines[#lines+1] = "--   BoneId: "..b
        end
    end

    -- TriggerServerEvent calls
    if #cl.server_events > 0 then
        lines[#lines+1] = section("TRIGGER SERVER EVENTS")
        lines[#lines+1] = "-- TriggerServerEvent calls observadas no cliente:"
        local seen = {}
        for _, ev in ipairs(cl.server_events) do
            if not seen[ev.name] then
                seen[ev.name] = true
                lines[#lines+1] = '--   TriggerServerEvent("'..ev.name..'")'
            end
        end
    end

    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════════════
-- Reconstrói shared/events_map.lua — mapa completo dos eventos
-- ════════════════════════════════════════════════════════════════════
local function build_events_map(result)
    local lines = {}
    local E     = result.shared_globals.E
    local res   = result.resource

    lines[#lines+1] = file_header("shared/events_map.lua",
        "Mapa completo de eventos — extraído dos scripts obfuscados", res, true)

    lines[#lines+1] = "\n-- Tabela E: nomes dos eventos (extraídos de bridge/shared.lua)"
    lines[#lines+1] = "-- Estes são os valores REAIS dos eventos internos do resource."
    lines[#lines+1] = ""

    if type(E) == "table" and next(E) then
        lines[#lines+1] = "E = {"
        local keys = {}
        for k in pairs(E) do keys[#keys+1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = E[k]
            if type(v) == "string" then
                lines[#lines+1] = string.format('    %-30s = "%s",', k, v)
            end
        end
        lines[#lines+1] = "}"
    else
        lines[#lines+1] = "-- Tabela E não encontrada ou vazia."
        lines[#lines+1] = "-- Eventos extraídos diretamente dos handlers:"
        lines[#lines+1] = ""
        local sv_evs, cl_evs = {}, {}
        for _, ev in ipairs(result.server.events) do sv_evs[ev.name] = true end
        for _, ev in ipairs(result.client.events) do cl_evs[ev.name] = true end
        local all = {}
        for n in pairs(sv_evs) do all[n] = "server" end
        for n in pairs(cl_evs) do
            all[n] = all[n] and "shared" or "client"
        end
        local names = {}
        for n in pairs(all) do names[#names+1] = n end
        table.sort(names)
        lines[#lines+1] = "-- Todos os eventos registrados:"
        for _, n in ipairs(names) do
            lines[#lines+1] = string.format('-- [%-8s]  "%s"', all[n], n)
        end
    end

    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════════════
-- Reconstrói shared/config_extracted.lua — Config lida dos scripts
-- ════════════════════════════════════════════════════════════════════
local function build_config_extracted(result)
    local lines = {}
    local cfg   = result.shared_globals.Config
    local res   = result.resource

    lines[#lines+1] = file_header("shared/config_extracted.lua",
        "Configuração lida dos scripts — extraída via análise dinâmica", res, true)

    lines[#lines+1] = ""
    if type(cfg) == "table" and next(cfg) then
        lines[#lines+1] = "-- Config lida durante a simulação:"
        lines[#lines+1] = "Config = "..lua_val(cfg, 0)
    else
        lines[#lines+1] = "-- Config não encontrada ou vazia na simulação."
        lines[#lines+1] = "-- Verifique config/config.lua e config/config_internal.lua."
    end

    -- Convars lidos
    local sv_cvars = result.server.convars_read
    local cl_cvars = result.client.convars_read
    if next(sv_cvars) or next(cl_cvars) then
        lines[#lines+1] = ""
        lines[#lines+1] = "-- ConVars lidos pelos scripts:"
        local all_cvars = {}
        for k,v in pairs(sv_cvars) do all_cvars[k] = {v, "server"} end
        for k,v in pairs(cl_cvars) do all_cvars[k] = {v, all_cvars[k] and "shared" or "client"} end
        local names = {}
        for k in pairs(all_cvars) do names[#names+1] = k end
        table.sort(names)
        for _, name in ipairs(names) do
            local info = all_cvars[name]
            lines[#lines+1] = string.format(
                '-- %-40s  default=%-15s  [%s]',
                name, tostring(info[1]), info[2])
        end
    end

    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════════════
-- Gera ANALYSIS_REPORT.md — relatório completo em Markdown
-- ════════════════════════════════════════════════════════════════════
local function build_report(result)
    local lines = {}
    local res   = result.resource
    local sv    = result.server
    local cl    = result.client
    local E     = result.shared_globals.E or {}
    local cfg   = result.shared_globals.Config or {}

    local function h(level, text)
        lines[#lines+1] = string.rep("#", level).." "..text
    end
    local function p(text) lines[#lines+1] = (text or "") end
    local function code(lang, text)
        lines[#lines+1] = "```"..(lang or "")
        lines[#lines+1] = text
        lines[#lines+1] = "```"
    end

    h(1, "Análise Dinâmica: "..res)
    p("Gerado em: "..os.date("%Y-%m-%d %H:%M:%S").." por fivem_deob")
    p("")

    h(2, "Visão Geral")
    -- Conta eventos únicos
    local sv_evs, cl_evs = 0, 0
    for _ in pairs(sv.event_handlers) do sv_evs=sv_evs+1 end
    for _ in pairs(cl.event_handlers) do cl_evs=cl_evs+1 end

    p("| Item | Server | Client |")
    p("|------|--------|--------|")
    p("| Eventos registrados | "..sv_evs.." | "..cl_evs.." |")
    p("| Comandos registrados | "..#sv.commands.." | "..#cl.commands.." |")
    p("| NUI Callbacks | "..#sv.nui_callbacks.." | "..#cl.nui_callbacks.." |")
    p("| TriggerServerEvent calls | - | "..#cl.server_events.." |")
    p("| TriggerClientEvent calls | "..#sv.client_events.." | - |")
    local n_anim_dicts = 0; for _ in pairs(cl.anim_dicts) do n_anim_dicts=n_anim_dicts+1 end
    local n_models = 0; for _ in pairs(cl.models) do n_models=n_models+1 end
    p("| AnimDicts usados | - | "..n_anim_dicts.." |")
    p("| Modelos (GetHashKey) | - | "..n_models.." |")
    p("| HTTP Requests | "..#sv.http_requests.." | - |")
    p("| Keybinds | - | "..#cl.keybinds.." |")
    p("")

    h(2, "Tabela E (Nomes dos Eventos)")
    if next(E) then
        p("Extraída de `bridge/shared.lua`:")
        p("")
        p("| Chave | Valor (nome do evento) |")
        p("|-------|----------------------|")
        local keys = {}
        for k in pairs(E) do keys[#keys+1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = E[k]
            if type(v) == "string" then
                p("| `"..k.."` | `"..v.."` |")
            end
        end
    else
        p("*Tabela E não detectada.*")
    end
    p("")

    h(2, "Configuração")
    if type(cfg) == "table" and cfg.Commands then
        p("### Comandos configurados")
        p("")
        if type(cfg.Commands) == "table" then
            p("| Chave | Comando |")
            p("|-------|---------|")
            local keys = {}
            for k in pairs(cfg.Commands) do keys[#keys+1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                p("| `"..k.."` | `/"..tostring(cfg.Commands[k]).."` |")
            end
        end
        if type(cfg.TailCommands) == "table" then
            p("")
            p("| Chave (cauda) | Comando |")
            p("|---------------|---------|")
            local keys = {}
            for k in pairs(cfg.TailCommands) do keys[#keys+1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                p("| `"..k.."` | `/"..tostring(cfg.TailCommands[k]).."` |")
            end
        end
    end
    if type(cfg) == "table" then
        p("")
        if cfg.HudCommand then p("- **HudCommand**: `/"..cfg.HudCommand.."`") end
        if cfg.Framework  then p("- **Framework**: `"..cfg.Framework.."`") end
        if cfg.Locale     then p("- **Locale padrão**: `"..cfg.Locale.."`") end
    end
    p("")

    -- Globals internos de config_internal
    h(2, "Config Internal (Obfuscado)")
    local ci_keys = { "BoneId","TailBoneId","ModelPrefix","TailModelPrefix",
                      "MaxColors","TailMaxColors","AP_ApiBase","AP_ConvarName","AP_ProductSlug" }
    p("| Campo | Valor |")
    p("|-------|-------|")
    for _, k in ipairs(ci_keys) do
        local v = type(cfg)=="table" and cfg[k]
        if v ~= nil then
            p("| `"..k.."` | `"..tostring(v).."` |")
        end
    end
    p("")

    h(2, "Eventos do Servidor")
    h(3, "Eventos Registrados (handlers)")
    local sv_ev_names = {}
    for name in pairs(sv.event_handlers) do sv_ev_names[#sv_ev_names+1] = name end
    table.sort(sv_ev_names)
    for _, name in ipairs(sv_ev_names) do
        p("- `"..name.."`  ("..#sv.event_handlers[name].." handler(s))")
    end
    p("")

    h(3, "Comandos Registrados")
    if #sv.commands > 0 then
        p("| Comando | Restricted |")
        p("|---------|-----------|")
        for _, cmd in ipairs(sv.commands) do
            p("| `/"..cmd.name.."` | "..tostring(cmd.restricted).." |")
        end
    else
        p("*Nenhum.*")
    end
    p("")

    h(3, "HTTP Requests (API/Auth)")
    if #sv.http_requests > 0 then
        for _, req in ipairs(sv.http_requests) do
            p("- `"..tostring(req.method).."` → `"..tostring(req.url).."`")
        end
    else
        p("*Nenhuma.*")
    end
    p("")

    h(2, "Eventos do Cliente")
    h(3, "Eventos Registrados")
    local cl_ev_names = {}
    for name in pairs(cl.event_handlers) do cl_ev_names[#cl_ev_names+1] = name end
    table.sort(cl_ev_names)
    for _, name in ipairs(cl_ev_names) do
        p("- `"..name.."` ("..#cl.event_handlers[name].." handler(s))")
    end
    p("")

    h(3, "NUI Callbacks")
    if #cl.nui_callbacks > 0 then
        for _, nui in ipairs(cl.nui_callbacks) do
            p("- `"..nui.name.."`")
        end
    else
        p("*Nenhum.*")
    end
    p("")

    h(3, "Keybinds")
    if #cl.keybinds > 0 then
        p("| Comando | Descrição | Tipo | Tecla |")
        p("|---------|-----------|------|-------|")
        for _, kb in ipairs(cl.keybinds) do
            p("| `/"..tostring(kb.command).."` | "..tostring(kb.description)
              .." | "..tostring(kb.inputType).." | "..tostring(kb.inputName).." |")
        end
    else
        p("*Nenhum.*")
    end
    p("")

    h(3, "Animações")
    if next(cl.anim_dicts) then
        p("**Dicionários:**")
        local dicts = {}
        for d in pairs(cl.anim_dicts) do dicts[#dicts+1] = d end
        table.sort(dicts)
        for _, d in ipairs(dicts) do p("- `"..d.."`") end
        p("")
        if #cl.anim_plays > 0 then
            p("**Clips observados:**")
            p("| Dict | Clip | Flag |")
            p("|------|------|------|")
            local seen = {}
            for _, play in ipairs(cl.anim_plays) do
                local key = (play.dict or "?")..":"..(play.clip or "?")
                if not seen[key] then
                    seen[key] = true
                    p("| `"..tostring(play.dict).."` | `"..tostring(play.clip)
                      .."` | "..tostring(play.flag or "-").." |")
                end
            end
        end
    else
        p("*Nenhuma animação observada.*")
    end
    p("")

    h(3, "Modelos")
    if next(cl.models) then
        local models = {}
        for m in pairs(cl.models) do models[#models+1] = m end
        table.sort(models)
        for _, m in ipairs(models) do p("- `"..m.."`") end
    else
        p("*Nenhum modelo observado.*")
    end
    p("")

    h(3, "Bones Usados")
    if next(cl.bones_used) then
        local bones = {}
        for b in pairs(cl.bones_used) do bones[#bones+1] = b end
        table.sort(bones)
        for _, b in ipairs(bones) do p("- BoneId: `"..b.."`") end
    else
        p("*Nenhum bone observado.*")
    end
    p("")

    h(3, "AttachEntityToEntity")
    if #cl.attach_calls > 0 then
        p("| Entity | EntityTo | Bone | Offset | Rot |")
        p("|--------|----------|------|--------|-----|")
        for _, a in ipairs(cl.attach_calls) do
            p(string.format("| %d | %d | %d | (%.2f,%.2f,%.2f) | (%.2f,%.2f,%.2f) |",
                a.entity or 0, a.entityTo or 0, a.bone or 0,
                a.offset[1] or 0, a.offset[2] or 0, a.offset[3] or 0,
                a.rot[1] or 0, a.rot[2] or 0, a.rot[3] or 0))
        end
    else
        p("*Nenhuma chamada observada.*")
    end
    p("")

    h(2, "TriggerServerEvent (cliente → servidor)")
    if #cl.server_events > 0 then
        local seen = {}
        for _, ev in ipairs(cl.server_events) do
            if not seen[ev.name] then
                seen[ev.name] = true
                p("- `"..ev.name.."`")
            end
        end
    else
        p("*Nenhum observado.*")
    end
    p("")

    h(2, "State Bag Handlers")
    if #cl.state_bag_keys > 0 then
        for _, sb in ipairs(cl.state_bag_keys) do
            p("- key=`"..tostring(sb.key).."` bag=`"..tostring(sb.bag).."`")
        end
    else
        p("*Nenhum.*")
    end
    p("")

    h(2, "Exports Chamados")
    local any_exp = false
    for resource, fns in pairs(cl.exports_called) do
        any_exp = true
        for fn in pairs(fns) do
            p("- `exports['"..resource.."']:"..fn.."()`")
        end
    end
    if not any_exp then p("*Nenhum export observado.*") end
    p("")

    h(2, "Notas de Reconstrução")
    p([[
Os arquivos em `output/` foram gerados automaticamente com base na
análise dinâmica dos scripts (incluindo os obfuscados via Luraph).

**Como usar:**
1. `output/ANALYSIS_REPORT.md` — este relatório completo
2. `output/shared/events_map.lua` — tabela E com todos os nomes de eventos
3. `output/shared/config_extracted.lua` — Config lida dos scripts
4. `output/server/main_reconstructed.lua` — estrutura do server/main.lua
5. `output/client/main_reconstructed.lua` — estrutura do client/main.lua

**Próximos passos:**
- Revise os handlers nos arquivos reconstruídos e adicione a lógica real
- Use os nomes dos eventos da tabela E para conectar server ↔ client
- Verifique os bones, modelos e animações descobertos
]])

    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════════════
-- Entry point principal: gera todos os arquivos de saída
-- ════════════════════════════════════════════════════════════════════
function REC.generate(result, output_dir)
    output_dir = output_dir or "output"

    -- Cria diretórios necessários
    local function mkdir(dir)
        os.execute('mkdir -p "'..dir..'"')
    end
    mkdir(output_dir)
    mkdir(output_dir.."/server")
    mkdir(output_dir.."/client")
    mkdir(output_dir.."/shared")

    local files_written = {}

    local function write_file(path, content)
        local f = io.open(path, "w")
        if f then
            f:write(content)
            f:close()
            files_written[#files_written+1] = path
        else
            io.stderr:write("ERROR: cannot write "..path.."\n")
        end
    end

    write_file(output_dir.."/server/main_reconstructed.lua",
        build_server_main(result))

    write_file(output_dir.."/client/main_reconstructed.lua",
        build_client_main(result))

    write_file(output_dir.."/shared/events_map.lua",
        build_events_map(result))

    write_file(output_dir.."/shared/config_extracted.lua",
        build_config_extracted(result))

    write_file(output_dir.."/ANALYSIS_REPORT.md",
        build_report(result))

    return files_written
end

return REC
