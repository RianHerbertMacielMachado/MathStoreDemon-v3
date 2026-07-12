-----------------------------------------------------------------------
-- fivem_deob/reconstructor.lua
-- Reconstrói arquivos Lua LEGÍVEIS a partir dos dados extraídos
-- pelo extractor. Cria:
--   output/server/main_reconstructed.lua
--   output/client/main_reconstructed.lua
--   output/shared/events_map.lua
--   output/shared/config_extracted.lua
--   output/ANALYSIS_REPORT.md
-----------------------------------------------------------------------

local REC = {}

-- ── Detecta OS ──────────────────────────────────────────────────────
local IS_WINDOWS = package.config:sub(1,1) == '\\'

-- ── mkdir portável: cria UM diretório (não recursivo) ───────────────
-- Tenta via lfs primeiro, fallback via os.execute
local _lfs_ok, _lfs = pcall(require, "lfs")

local function mkdir_one(dir)
    -- Normaliza separadores para o SO atual
    local d = IS_WINDOWS and dir:gsub('/', '\\') or dir
    if _lfs_ok then
        -- lfs.mkdir falha silenciosamente se já existe — isso é OK
        _lfs.mkdir(d)
    end
    -- Sempre tenta também via os.execute como fallback extra
    -- (lfs.mkdir pode falhar em caminhos OneDrive/rede sem erro visível)
    if IS_WINDOWS then
        os.execute('md "'..d..'" 2>nul')
    else
        os.execute('mkdir "'..d..'" 2>/dev/null')
    end
end

-- ── Cria diretório e todos os pais de forma portável ────────────────
-- Funciona em Windows (C:\foo\bar) e Linux (/foo/bar)
local function mkdirp(dir)
    -- No Linux sem lfs: usa mkdir -p diretamente (mais simples e confiável)
    if not IS_WINDOWS and not _lfs_ok then
        os.execute('mkdir -p "' .. dir .. '"')
        return
    end

    -- No Linux com lfs: tenta mkdir -p primeiro (mais robusto),
    -- cai no incremental se falhar
    if not IS_WINDOWS and _lfs_ok then
        local ok = os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
        if ok then return end
        -- Se mkdir -p falhou por algum motivo, continua para o loop incremental
    end

    -- Windows (ou Linux com mkdir -p falho):
    -- Abordagem dupla: tenta 'md' com o caminho COMPLETO primeiro
    -- (funciona quando todos os pais já existem), depois loop incremental
    local norm = dir:gsub('\\', '/'):gsub('/+$', '')

    -- Detecta drive letter: "C:/Users/foo" → prefix="C:", rest="/Users/foo"
    local prefix = ""
    local rest   = norm
    if norm:match("^%a:[/\\]") then
        prefix = norm:sub(1, 2)   -- "C:"
        rest   = norm:sub(3)      -- "/Users/foo"
    end

    -- Remove leading slash do rest, guarda se havia
    local has_root = rest:sub(1,1) == "/"
    if has_root then rest = rest:sub(2) end

    -- Divide em componentes não-vazios
    local parts = {}
    for p in rest:gmatch("[^/]+") do
        if p ~= "" then parts[#parts+1] = p end
    end

    -- Reconstrói e cria incrementalmente
    -- No Windows: começa com "C:" (sem barra); no Linux: com "/" ou ""
    local current
    if IS_WINDOWS then
        current = prefix   -- "C:" ou "" (caminho relativo)
    else
        current = has_root and "/" or ""
    end

    for _, part in ipairs(parts) do
        if current == "" or current == "/" then
            current = current .. part
        else
            current = current .. "/" .. part
        end
        mkdir_one(current)
    end

    -- Tentativa final com caminho completo usando md (robusto para OneDrive)
    if IS_WINDOWS then
        local full = norm:gsub('/', '\\')
        os.execute('md "' .. full .. '" 2>nul')
    end
end

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
-- Gera CORPO REAL de um handler a partir das chamadas observadas
-- ════════════════════════════════════════════════════════════════════
local function build_handler_body(event_name, hc, indent_level, side)
    if not hc then
        return { indent(indent_level).."-- Handler não disparado na simulação" }
    end

    local lines = {}
    local ind   = indent(indent_level)
    local ind2  = indent(indent_level + 1)

    -- Detecta tipo de evento pelo nome
    local is_spawn  = event_name:match(":spawn$") or event_name:match("^spawn$")
    local is_remove = event_name:match(":remove$") or event_name:match("^remove$")
    local is_anim   = event_name:match(":abrir$") or event_name:match(":fechar$")
                   or event_name:match(":bater$")  or event_name:match(":enrolar$")
                   or event_name:match(":reta$")
    local is_color  = event_name:match(":changeColor$") or event_name:match("color")
    local is_sync   = event_name:match("^sync:") or event_name:match(":sync:")
    local is_flight = event_name:match("^flight:") or event_name:match(":flight:")
    local is_auth   = event_name:match("auth") or event_name:match("autorizar")
    local is_tail   = event_name:match("^tail:")
    local is_server_event = (side == "SERVER")

    -- ── Parâmetros típicos de servidor ──────────────────────────────
    if is_server_event then
        lines[#lines+1] = ind.."local src = source"
    end

    -- ── Animações observadas ─────────────────────────────────────────
    if hc.anims and #hc.anims > 0 then
        for _, dict in ipairs(hc.anims) do
            lines[#lines+1] = ""
            lines[#lines+1] = ind.."-- Carrega dicionário de animação"
            lines[#lines+1] = ind..'if not HasAnimDictLoaded("'..dict..'") then'
            lines[#lines+1] = ind2..'RequestAnimDict("'..dict..'")'
            lines[#lines+1] = ind2..'while not HasAnimDictLoaded("'..dict..'") do Wait(10) end'
            lines[#lines+1] = ind..'end'
        end
    end

    -- ── Clips de animação observados ────────────────────────────────
    if hc.anims_played and #hc.anims_played > 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = ind.."-- Animações reproduzidas neste handler:"
        local seen_anim = {}
        for _, play in ipairs(hc.anims_played) do
            local key = (play.dict or "?")..":"..(play.clip or "?")
            if not seen_anim[key] then
                seen_anim[key] = true
                local ped_ref = (side == "SERVER") and "GetPlayerPed(src)" or "PlayerPedId()"
                lines[#lines+1] = string.format(
                    ind..'TaskPlayAnim(%s, "%s", "%s", 8.0, -8.0, -1, %d, 0, false, false, false)',
                    ped_ref,
                    tostring(play.dict), tostring(play.clip),
                    play.flag or 0)
            end
        end
    end

    -- ── Criação de entidades ─────────────────────────────────────────
    if (hc.entities_created or 0) > 0 then
        if is_spawn then
            lines[#lines+1] = ""
            lines[#lines+1] = ind.."-- Cria entidade/objeto (spawn detectado na simulação)"
            lines[#lines+1] = ind.."-- Substitua 'model' pelo modelo correto"
            lines[#lines+1] = ind..'local model = GetHashKey("prop_example")'
            lines[#lines+1] = ind..'RequestModel(model)'
            lines[#lines+1] = ind..'while not HasModelLoaded(model) do Wait(10) end'
            lines[#lines+1] = ind..'local coords = GetEntityCoords(PlayerPedId())'
            lines[#lines+1] = ind..'local entity = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)'
            if hc.attach_calls and #hc.attach_calls > 0 then
                local a = hc.attach_calls[1]
                lines[#lines+1] = string.format(
                    ind..'AttachEntityToEntity(entity, PlayerPedId(), %d, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, false, false, false, false, 2, true)',
                    a.bone or 0,
                    (a.offset and a.offset[1]) or 0.0,
                    (a.offset and a.offset[2]) or 0.0,
                    (a.offset and a.offset[3]) or 0.0,
                    (a.rot   and a.rot[1])    or 0.0,
                    (a.rot   and a.rot[2])    or 0.0,
                    (a.rot   and a.rot[3])    or 0.0)
            end
            lines[#lines+1] = ind..'SetModelAsNoLongerNeeded(model)'
        elseif is_remove then
            lines[#lines+1] = ""
            lines[#lines+1] = ind.."-- Remove entidade existente"
            lines[#lines+1] = ind..'if DoesEntityExist(entity) then'
            lines[#lines+1] = ind2..'DetachEntity(entity, true, false)'
            lines[#lines+1] = ind2..'DeleteEntity(entity)'
            lines[#lines+1] = ind2..'entity = nil'
            lines[#lines+1] = ind..'end'
        end
    elseif (hc.entities_deleted or 0) > 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = ind.."-- Deleta entidade (observado na simulação)"
        lines[#lines+1] = ind..'if DoesEntityExist(entity) then'
        lines[#lines+1] = ind2..'DeleteEntity(entity)'
        lines[#lines+1] = ind2..'entity = nil'
        lines[#lines+1] = ind..'end'
    end

    -- ── Attach calls observadas ──────────────────────────────────────
    if hc.attach_calls and #hc.attach_calls > 0 and not is_spawn then
        lines[#lines+1] = ""
        lines[#lines+1] = ind.."-- Attach entity observado:"
        for _, a in ipairs(hc.attach_calls) do
            lines[#lines+1] = string.format(
                ind..'-- AttachEntityToEntity(entity, PlayerPedId(), %d, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, ...)',
                a.bone or 0,
                (a.offset and a.offset[1]) or 0.0,
                (a.offset and a.offset[2]) or 0.0,
                (a.offset and a.offset[3]) or 0.0,
                (a.rot   and a.rot[1])    or 0.0,
                (a.rot   and a.rot[2])    or 0.0,
                (a.rot   and a.rot[3])    or 0.0)
        end
    end

    -- ── TriggerServerEvent calls ─────────────────────────────────────
    if hc.triggers_server and #hc.triggers_server > 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = ind.."-- Dispara evento(s) no servidor:"
        local seen_tsv = {}
        for _, t in ipairs(hc.triggers_server) do
            if not seen_tsv[t.name] then
                seen_tsv[t.name] = true
                -- Tenta reconstituir args
                local args_str = ""
                if t.args and #t.args > 0 then
                    local parts = {}
                    for _, a in ipairs(t.args) do
                        if type(a) == "string" then
                            parts[#parts+1] = '"'..a..'"'
                        elseif type(a) == "number" then
                            parts[#parts+1] = tostring(a)
                        elseif type(a) == "boolean" then
                            parts[#parts+1] = tostring(a)
                        else
                            parts[#parts+1] = "..."
                        end
                    end
                    args_str = ", "..table.concat(parts, ", ")
                end
                lines[#lines+1] = ind..'TriggerServerEvent("'..t.name..'"'..args_str..')'
            end
        end
    end

    -- ── TriggerClientEvent calls (servidor→cliente) ─────────────────
    if hc.triggers_client and #hc.triggers_client > 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = ind.."-- Dispara evento(s) no cliente:"
        local seen_tcl = {}
        for _, t in ipairs(hc.triggers_client) do
            if not seen_tcl[t.name] then
                seen_tcl[t.name] = true
                local tgt = t.target or "src"
                if tgt == "1" or tgt == "ALL" then
                    tgt = tgt == "ALL" and "-1" or "src"
                end
                lines[#lines+1] = ind..'TriggerClientEvent("'..t.name..'", '..tgt..')'
            end
        end
    end

    -- ── SendNuiMessage ───────────────────────────────────────────────
    if hc.nui_messages and #hc.nui_messages > 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = ind.."-- Envia mensagem NUI:"
        for _, msg in ipairs(hc.nui_messages) do
            -- Trunca msg se muito longa
            local m = msg
            if #m > 120 then m = m:sub(1,120).."..." end
            lines[#lines+1] = ind.."-- SendNuiMessage(json.encode({...}))"
            lines[#lines+1] = ind.."-- Payload observado: "..m
            break  -- só o primeiro para não poluir
        end
        lines[#lines+1] = ind.."SendNuiMessage(json.encode({action = \"...\", data = {}}))"
    end

    -- ── HTTP calls ───────────────────────────────────────────────────
    if hc.http_calls and #hc.http_calls > 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = ind.."-- HTTP request observada:"
        for _, req in ipairs(hc.http_calls) do
            lines[#lines+1] = string.format(
                ind..'PerformHttpRequest("%s", function(status, body, headers)',
                tostring(req.url))
            lines[#lines+1] = ind2..'local data = json.decode(body)'
            lines[#lines+1] = ind2..'if status == 200 and data then'
            lines[#lines+1] = ind2..'    -- processar resposta'
            lines[#lines+1] = ind2..'end'
            lines[#lines+1] = ind..string.format('end, "%s")', req.method or "GET")
        end
    end

    -- ── Natives observadas (as mais importantes) ─────────────────────
    if hc.natives and #hc.natives > 0 then
        -- Filtra nativas mais relevantes para mostrar como código
        local important = {
            SetEntityCoords=true, SetEntityHeading=true,
            FreezeEntityPosition=true, SetEntityVisible=true,
            SetPedGravity=true, SetGravityLevel=true,
            SetEntityVelocity=true, SetEntityRotation=true,
            SetEntityAlpha=true, SetEntityNoCollisionEntity=true,
            SetEntityCollision=true, ClearPedTasks=true,
            ClearPedTasksImmediately=true, SetNuiFocus=true,
        }
        local shown = {}
        for _, n in ipairs(hc.natives) do
            if important[n.name] and not shown[n.name] then
                shown[n.name] = true
                -- Reconstrói a chamada com args conhecidos
                local args_parts = {}
                if n.args then
                    for _, a in ipairs(n.args) do
                        if type(a) == "number" then
                            args_parts[#args_parts+1] = tostring(a)
                        elseif type(a) == "boolean" then
                            args_parts[#args_parts+1] = tostring(a)
                        elseif type(a) == "string" then
                            args_parts[#args_parts+1] = '"'..a..'"'
                        else
                            args_parts[#args_parts+1] = "entity"
                        end
                    end
                end
                if #args_parts > 0 then
                    lines[#lines+1] = ind..n.name.."("..table.concat(args_parts,", ")..")"
                else
                    lines[#lines+1] = ind..n.name.."(entity)"
                end
            end
        end
    end

    -- ── Modelos carregados ───────────────────────────────────────────
    if hc.models and #hc.models > 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = ind.."-- Modelos usados neste handler:"
        for _, m in ipairs(hc.models) do
            lines[#lines+1] = ind..'-- GetHashKey("'..m..'")'
        end
    end

    -- ── Conteúdo vazio → comentário informativo ──────────────────────
    if #lines == 0 then
        -- Adiciona comentários baseados no tipo de evento
        if is_auth then
            lines[#lines+1] = ind.."-- Handler de autenticação/autorização"
            lines[#lines+1] = ind.."-- Verifica se o jogador tem permissão para usar o resource"
            if is_server_event then
                lines[#lines+1] = ind.."TriggerClientEvent(\""..event_name:gsub("desautorizar","autorizar").."\", src, true)"
            end
        elseif is_color then
            lines[#lines+1] = ind.."-- Muda a cor (argumento: índice de cor)"
            lines[#lines+1] = ind.."local colorIndex = ... -- índice da cor"
            if is_server_event then
                lines[#lines+1] = ind..'TriggerClientEvent("'..event_name..'", -1, colorIndex)'
            end
        elseif is_sync then
            lines[#lines+1] = ind.."-- Sincronização multiplayer"
            lines[#lines+1] = ind.."-- Propaga estado para todos os clientes"
            if is_server_event then
                lines[#lines+1] = ind..'TriggerClientEvent("'..event_name..'", -1, ...)'
            end
        elseif is_flight then
            lines[#lines+1] = ind.."-- Controla sistema de voo"
        elseif is_remove then
            lines[#lines+1] = ind.."-- Remove entidade/efeito"
        elseif is_spawn then
            lines[#lines+1] = ind.."-- Spawna entidade"
        else
            lines[#lines+1] = ind.."-- Handler disparado durante simulação (sem chamadas observáveis)"
        end
    end

    return lines
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

    -- Conta eventos
    local ev_count = 0
    for _ in pairs(sv.event_handlers) do ev_count = ev_count + 1 end

    if ev_count == 0 then
        lines[#lines+1] = section("NOTA: SERVER SEM EVENTOS DIRETOS")
        lines[#lines+1] = [[-- O servidor deste resource não registrou event handlers
-- durante a simulação. Isso pode significar:
-- 1. Os handlers do servidor usam uma estrutura guardada por resource_name
--    e o nome não correspondeu durante a simulação
-- 2. Os arquivos server/*.lua fazem RegisterNetEvent mas não AddEventHandler
--    (os handlers podem estar em callbacks de framework como QBCore/ESX)
-- 3. A lógica do servidor está toda em server/core.lua (carregado antes)
--
-- Os arquivos extras (.lua não listados no manifest) também foram
-- processados — veja a seção EVENTOS NET REGISTRADOS abaixo.
]]
    end

    lines[#lines+1] = section("EVENTOS NET REGISTRADOS")
    lines[#lines+1] = "-- Eventos de rede descobertos durante a simulação:"
    local net_list = {}
    for name in pairs(sv.net_events) do net_list[#net_list+1] = name end
    table.sort(net_list)
    if #net_list == 0 then
        lines[#lines+1] = "-- Nenhum RegisterNetEvent observado no servidor."
    else
        for _, name in ipairs(net_list) do
            lines[#lines+1] = 'RegisterNetEvent("'..name..'")'
        end
    end

    lines[#lines+1] = section("COMANDOS")
    if #sv.commands == 0 then
        lines[#lines+1] = "-- Nenhum comando registrado diretamente neste lado (server)."
    else
        for _, cmd in ipairs(sv.commands) do
            local hc = sv.handler_calls and sv.handler_calls["cmd:"..cmd.name]
            lines[#lines+1] = ""
            lines[#lines+1] = string.format(
                "-- COMANDO: /%s  (restricted=%s)", cmd.name, tostring(cmd.restricted))
            lines[#lines+1] = string.format(
                'RegisterCommand("%s", function(source, args, rawCommand)', cmd.name)
            lines[#lines+1] = '    local src = source'
            if hc then
                local body = build_handler_body("cmd:"..cmd.name, hc, 1, "SERVER")
                for _, l in ipairs(body) do lines[#lines+1] = l end
            else
                lines[#lines+1] = '    -- args[1] = primeiro argumento'
            end
            lines[#lines+1] = 'end, '..tostring(cmd.restricted)..')'
        end
    end

    lines[#lines+1] = section("EVENTOS DISPARO → CLIENTE")
    if #sv.client_events == 0 then
        lines[#lines+1] = "-- Nenhum TriggerClientEvent observado na simulação."
    else
        local seen = {}
        for _, ev in ipairs(sv.client_events) do
            if not seen[ev.name] then
                seen[ev.name] = true
                lines[#lines+1] = '-- TriggerClientEvent("'..ev.name..'", target, ...)'
            end
        end
    end

    lines[#lines+1] = section("EVENTOS RECEBIDOS (HANDLERS DO SERVIDOR)")
    local ev_list = {}
    for name in pairs(sv.event_handlers) do ev_list[#ev_list+1] = name end
    table.sort(ev_list)

    if #ev_list == 0 then
        lines[#lines+1] = "-- Nenhum handler de servidor detectado na simulação."
        lines[#lines+1] = "-- Se o resource tem lógica de servidor, ela pode estar:"
        lines[#lines+1] = "-- - em callbacks de framework (ESX/QBCore)"
        lines[#lines+1] = "-- - protegida por verificação de resource_name"
        lines[#lines+1] = "-- - usando RegisterNetEvent sem AddEventHandler explícito"
        lines[#lines+1] = ""
        -- Gera handlers baseados nos TriggerServerEvent calls do cliente
        if result.client and #result.client.server_events > 0 then
            lines[#lines+1] = "-- Eventos disparados pelo CLIENTE para o servidor:"
            lines[#lines+1] = "-- (Reconstituídos a partir dos TriggerServerEvent observados)"
            local seen = {}
            for _, ev in ipairs(result.client.server_events) do
                if not seen[ev.name] then
                    seen[ev.name] = true
                    lines[#lines+1] = ""
                    lines[#lines+1] = '-- Evento: '..ev.name
                    lines[#lines+1] = 'RegisterNetEvent("'..ev.name..'")'
                    lines[#lines+1] = 'AddEventHandler("'..ev.name..'", function(...)'
                    lines[#lines+1] = '    local src = source'
                    -- Tenta classificar
                    local body = build_handler_body(ev.name, nil, 1, "SERVER")
                    for _, l in ipairs(body) do lines[#lines+1] = l end
                    lines[#lines+1] = 'end)'
                end
            end
        end
    else
        for _, name in ipairs(ev_list) do
            lines[#lines+1] = ""
            lines[#lines+1] = "-- EVENTO: "..name
            lines[#lines+1] = 'RegisterNetEvent("'..name..'")'
            lines[#lines+1] = 'AddEventHandler("'..name..'", function(...)'
            local hc = sv.handler_calls and sv.handler_calls[name]
            local body = build_handler_body(name, hc, 1, "SERVER")
            for _, l in ipairs(body) do lines[#lines+1] = l end
            lines[#lines+1] = 'end)'
        end
    end

    lines[#lines+1] = section("HTTP REQUESTS OBSERVADAS")
    if #sv.http_requests == 0 then
        lines[#lines+1] = "-- Nenhuma requisição HTTP observada."
    else
        for _, req in ipairs(sv.http_requests) do
            lines[#lines+1] = string.format(
                '-- %s %s', req.method or "GET", tostring(req.url))
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
            lines[#lines+1] = '-- NUI Callback: '..nui.name
            lines[#lines+1] = 'RegisterNUICallback("'..nui.name..'", function(data, cb)'
            -- Tenta gerar corpo real
            local hc = cl.handler_calls and cl.handler_calls["nui:"..nui.name]
            if hc then
                local body = build_handler_body("nui:"..nui.name, hc, 1, "CLIENT")
                for _, l in ipairs(body) do lines[#lines+1] = l end
            else
                -- NUI callbacks são opacos — gera código genérico sensato
                if nui.name == "closeHud" or nui.name:match("[Cc]lose") then
                    lines[#lines+1] = '    SetNuiFocus(false, false)'
                elseif nui.name == "hudAction" or nui.name:match("[Aa]ction") then
                    lines[#lines+1] = '    local action = data.action'
                    lines[#lines+1] = '    local value  = data.value'
                    lines[#lines+1] = '    -- processar ação da HUD'
                end
            end
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
            lines[#lines+1] = '    -- Reage à mudança de state bag: '..sb.key
            lines[#lines+1] = '    if value then'
            lines[#lines+1] = '        -- aplicar novo valor'
            lines[#lines+1] = '    end'
            lines[#lines+1] = 'end)'
        end
    end

    -- Eventos net (handlers do cliente)
    lines[#lines+1] = section("EVENTOS DE REDE (CLIENT HANDLERS)")
    local ev_list = {}
    for name in pairs(cl.event_handlers) do ev_list[#ev_list+1] = name end
    table.sort(ev_list)

    for _, name in ipairs(ev_list) do
        -- Classifica o tipo de evento para o comentário
        local tag = ""
        if name:find(":spawn$")      then tag = " -- Spawna entidade"
        elseif name:find(":remove$") then tag = " -- Remove entidade"
        elseif name:find(":abrir$") or name:find(":fechar$") or name:find(":bater$") then
            tag = " -- Animação"
        elseif name:find("tail:")    then tag = " -- Cauda"
        elseif name:find("sync:")    then tag = " -- Sincronização"
        elseif name:find("animprotect") then tag = " -- AnimProtect"
        elseif name:find("flight:")  then tag = " -- Voo"
        elseif name:find("auth")     then tag = " -- Autenticação"
        elseif name:find("color")    then tag = " -- Cor"
        end

        lines[#lines+1] = ""
        lines[#lines+1] = 'RegisterNetEvent("'..name..'")'
        lines[#lines+1] = 'AddEventHandler("'..name..'", function(...)' .. tag

        -- Gera corpo REAL a partir das chamadas observadas
        local hc = cl.handler_calls and cl.handler_calls[name]
        local body = build_handler_body(name, hc, 1, "CLIENT")
        for _, l in ipairs(body) do lines[#lines+1] = l end

        lines[#lines+1] = 'end)'
    end

    -- Animações descobertas
    if next(cl.anim_dicts) then
        lines[#lines+1] = section("ANIMAÇÕES DESCOBERTAS")
        lines[#lines+1] = "-- Dicionários de animação utilizados (referência):"
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
                "--   entity=%d to=%d bone=%d off=(%.4f,%.4f,%.4f) rot=(%.4f,%.4f,%.4f)",
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
        for name in pairs(result.server.event_handlers) do sv_evs[name] = true end
        for name in pairs(result.client.event_handlers) do cl_evs[name] = true end
        local all = {}
        for n in pairs(sv_evs) do all[n] = "server" end
        for n in pairs(cl_evs) do
            all[n] = all[n] and "shared" or "client"
        end
        -- Adiciona TriggerServerEvent do cliente (eventos esperados no servidor)
        for _, ev in ipairs(result.client.server_events) do
            if not all[ev.name] then all[ev.name] = "server(expected)" end
        end
        local names = {}
        for n in pairs(all) do names[#names+1] = n end
        table.sort(names)
        lines[#lines+1] = "-- Todos os eventos registrados e esperados:"
        for _, n in ipairs(names) do
            lines[#lines+1] = string.format('-- [%-18s]  "%s"', all[n], n)
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

    h(1, "Análise Dinâmica: "..res)
    p("Gerado em: "..os.date("%Y-%m-%d %H:%M:%S").." por fivem_deob")
    p("")

    -- Arquivos analisados
    if result.all_files and #result.all_files > 0 then
        h(2, "Arquivos Analisados")
        p("Total de arquivos .lua no resource: **"..#result.all_files.."**")
        if result.extra_files and #result.extra_files > 0 then
            p("")
            p("Arquivos **não listados no fxmanifest** mas encontrados e processados:")
            for _, f in ipairs(result.extra_files) do
                p("- `"..f.."`")
            end
        end
        p("")
    end

    h(2, "Visão Geral")
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
    if #sv_ev_names == 0 then
        p("*Nenhum handler de servidor detectado na simulação.*")
        p("")
        p("Eventos esperados (TriggerServerEvent do cliente):")
        local seen = {}
        for _, ev in ipairs(cl.server_events) do
            if not seen[ev.name] then
                seen[ev.name] = true
                p("- `"..ev.name.."`")
            end
        end
    else
        for _, name in ipairs(sv_ev_names) do
            local hc = sv.handler_calls and sv.handler_calls[name]
            local call_count = hc and (
                (hc.natives and #hc.natives or 0) +
                (hc.triggers_client and #hc.triggers_client or 0) +
                (hc.anims_played and #hc.anims_played or 0)
            ) or 0
            p("- `"..name.."` — "..call_count.." chamadas observadas")
        end
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
    h(3, "Eventos Registrados (com chamadas observadas)")
    local cl_ev_names = {}
    for name in pairs(cl.event_handlers) do cl_ev_names[#cl_ev_names+1] = name end
    table.sort(cl_ev_names)
    for _, name in ipairs(cl_ev_names) do
        local hc = cl.handler_calls and cl.handler_calls[name]
        local call_count = hc and (
            (hc.natives and #hc.natives or 0) +
            (hc.triggers_server and #hc.triggers_server or 0) +
            (hc.anims_played and #hc.anims_played or 0) +
            (hc.entities_created or 0) +
            (hc.entities_deleted or 0)
        ) or 0
        p("- `"..name.."` — "..call_count.." chamadas observadas")
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
            p(string.format("| %d | %d | %d | (%.4f,%.4f,%.4f) | (%.4f,%.4f,%.4f) |",
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
- Revise os handlers nos arquivos reconstruídos — o corpo foi gerado
  com base nas chamadas REAIS observadas durante a simulação
- Use os nomes dos eventos da tabela E para conectar server ↔ client
- Verifique os bones, modelos e animações descobertos
- Handlers marcados como "sem chamadas observáveis" precisam de
  lógica adicional deduzida pelo contexto do nome do evento
]])

    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════════════
-- Entry point principal: gera todos os arquivos de saída
-- ════════════════════════════════════════════════════════════════════
function REC.generate(result, output_dir)
    output_dir = output_dir or "output"

    -- Cria diretórios de forma portável (sem -p)
    mkdirp(output_dir)
    mkdirp(output_dir.."/server")
    mkdirp(output_dir.."/client")
    mkdirp(output_dir.."/shared")

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
