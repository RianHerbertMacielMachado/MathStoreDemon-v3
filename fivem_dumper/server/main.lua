-----------------------------------------------------------------------
-- fivem_dumper/server/main.lua
--
-- Ponto de entrada. Expõe:
--   /dump <resourceName> [verbose]  — analisa e gera output agora
--   /dumpall                         — re-gera output de todos os
--                                      resources já analisados
--   AUTO_DUMP=true                   — gera output automaticamente
--                                      quando qualquer resource inicia
--
-- Como funciona:
--   O collector.lua faz monkey-patch das APIs globais do FiveM
--   (AddEventHandler, RegisterNetEvent, RegisterCommand, etc.)
--   ANTES dos resources carregarem. Assim, quando qualquer resource
--   executa seus scripts nativamente (com LuaJIT real, Luraph incluso),
--   todas as chamadas de API são interceptadas e registradas.
--
--   O /dump apenas lê os dados já coletados e gera os arquivos de output.
--   Não há execução fake de scripts, não há ENV instrumentado,
--   não há io.open de arquivos externos, não há eventos hardcoded.
-----------------------------------------------------------------------

assert(COLLECTOR, "[Dumper] server/collector.lua não carregado antes de main.lua")
assert(WRITER,    "[Dumper] server/writer.lua não carregado antes de main.lua")

local DUMPER_RES = GetCurrentResourceName()
local AUTO_DUMP  = true   -- gera output automaticamente ao detectar onResourceStart

-----------------------------------------------------------------------
-- Gera output para um resource e exibe resumo
-----------------------------------------------------------------------
local function do_dump(resource_name, source_player)
    local t0 = GetGameTimer()

    -- Verifica se temos dados coletados
    local d = COLLECTOR._data[resource_name]
    if not d then
        local msg = string.format(
            "^3[Dumper] Sem dados para '%s'. O resource precisa ter iniciado APÓS o fivem_dumper.^7",
            resource_name)
        print(msg)
        if source_player and source_player > 0 then
            TriggerClientEvent(DUMPER_EV_CLIENT_REPORT, source_player, {
                resource = resource_name, error = "sem dados coletados"
            })
        end
        return
    end

    print(string.format("^5[Dumper]^7 Gerando output para ^3%s^7...", resource_name))

    local elapsed = GetGameTimer() - (d.started_at or t0)
    local count   = WRITER.generate(resource_name, elapsed)

    -- Resumo
    local function tcount(t)
        if type(t)~="table" then return 0 end
        local n=0; for _ in pairs(t) do n=n+1 end; return n
    end

    print(string.format(
        "^2[Dumper]^7 ✓ ^3%s^7 — %d eventos, %d net, %d cmds, %d→client, %d HTTP — %d arquivos",
        resource_name,
        tcount(d.events), tcount(d.net_events), tcount(d.commands),
        tcount(d.client_events), #d.http_requests, count))

    -- Notifica o cliente que requisitou (se houver)
    if source_player and source_player > 0 then
        TriggerClientEvent(DUMPER_EV_CLIENT_REPORT, source_player, {
            resource    = resource_name,
            elapsed     = elapsed,
            files       = count,
            events      = tcount(d.events),
            net_events  = tcount(d.net_events),
            commands    = tcount(d.commands),
            ce_calls    = tcount(d.client_events),
            http        = #d.http_requests,
        })
    end
end

-----------------------------------------------------------------------
-- COMANDO: /dump <resourceName>
-- Gera output dos dados já coletados para o resource.
-- O resource deve ter iniciado DEPOIS do fivem_dumper.
-----------------------------------------------------------------------
RegisterCommand("dump", function(source, args)
    local resource_name = args[1]

    if not resource_name or resource_name == "" then
        print("^3[Dumper] Uso: /dump <resourceName>^7")
        print("^3[Dumper] Exemplo: /dump MathStoreFairyWingv6^7")
        print("^3[Dumper] Resources com dados coletados:^7")
        local count = 0
        for name in pairs(COLLECTOR._data) do
            print("^3[Dumper]   • "..name.."^7")
            count = count + 1
        end
        if count == 0 then
            print("^3[Dumper]   (nenhum ainda — aguarde o auto-dump ou reinicie resources)^7")
        end
        return
    end

    print(string.format("^5[Dumper] /dump: ^3%s^7 (source=%s)", resource_name, tostring(source)))
    do_dump(resource_name, tonumber(source) or 0)
end, true)

-----------------------------------------------------------------------
-- COMANDO: /dumpall
-- Gera output de todos os resources que têm dados coletados.
-----------------------------------------------------------------------
RegisterCommand("dumpall", function(source, args)
    local resources = {}
    for name in pairs(COLLECTOR._data) do
        resources[#resources+1] = name
    end
    if #resources == 0 then
        print("^3[Dumper] /dumpall: nenhum resource analisado ainda.^7")
        return
    end
    print(string.format("^5[Dumper] /dumpall: gerando output de %d resources...^7", #resources))
    for _, name in ipairs(resources) do
        Wait(0)
        do_dump(name, 0)
    end
    print("^2[Dumper] /dumpall concluído.^7")
end, true)

-----------------------------------------------------------------------
-- COMANDO: /dumplist
-- Lista todos os resources com dados coletados e suas métricas.
-----------------------------------------------------------------------
RegisterCommand("dumplist", function(source, args)
    local function tcount(t)
        if type(t)~="table" then return 0 end
        local n=0; for _ in pairs(t) do n=n+1 end; return n
    end
    local count = 0
    print("^5[Dumper] Resources coletados:^7")
    for name, d in pairs(COLLECTOR._data) do
        print(string.format(
            "^5[Dumper]^7   ^3%-40s^7 ev=%-4d net=%-4d cmd=%-4d ce=%-4d http=%-3d",
            name,
            tcount(d.events), tcount(d.net_events), tcount(d.commands),
            tcount(d.client_events), #d.http_requests))
        count = count + 1
    end
    if count == 0 then
        print("^3[Dumper]   (nenhum resource analisado ainda)^7")
    else
        print(string.format("^5[Dumper]^7 Total: %d resources. Use ^3/dump <nome>^7 ou ^3/dumpall^7.", count))
    end
end, true)

-----------------------------------------------------------------------
-- AUTO-DUMP: gera output automaticamente quando resource inicia
-- Usa um pequeno delay para garantir que o resource finalizou init.
-----------------------------------------------------------------------
AddEventHandler("onResourceStart", function(started_resource)
    if started_resource == DUMPER_RES then return end
    if not AUTO_DUMP then return end

    -- Aguarda 1 tick para o resource terminar de registrar tudo
    CreateThread(function()
        Wait(100)
        -- Só gera se temos dados (o collector pode não ter capturado se
        -- o resource iniciou antes do dumper, ou se não tem scripts server)
        if COLLECTOR._data[started_resource] then
            do_dump(started_resource, 0)
        end
    end)
end)

-----------------------------------------------------------------------
-- Banner
-----------------------------------------------------------------------
print(string.format("^5[Dumper]^7 FiveM Dumper v%s iniciado.", DUMPER_VERSION))
print("^5[Dumper]^7 Modo: ^2interceptação nativa de APIs^7 (funciona com qualquer script, incluindo Luraph)")
print("^5[Dumper]^7 Comandos:")
print("^5[Dumper]^7   ^3/dump <resource>^7     — gera output de um resource")
print("^5[Dumper]^7   ^3/dumpall^7              — gera output de todos os resources")
print("^5[Dumper]^7   ^3/dumplist^7             — lista resources coletados + métricas")
print(string.format("^5[Dumper]^7 Auto-dump: ^%s%s^7",
    AUTO_DUMP and "2" or "1", AUTO_DUMP and "ATIVO" or "INATIVO"))
