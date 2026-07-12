-----------------------------------------------------------------------
-- fivem_dumper/server/collector.lua
--
-- Intercepta as APIs globais do FiveM no lado servidor.
-- Todos os resources compartilham o mesmo _G no servidor,
-- então monkey-patchar as funções aqui captura chamadas de
-- QUALQUER resource que iniciar depois do fivem_dumper.
--
-- Dados coletados por resource:
--   events        — AddEventHandler calls
--   net_events    — RegisterNetEvent calls
--   commands      — RegisterCommand calls
--   exports_reg   — exports registrados
--   client_events — TriggerClientEvent calls
--   sv_events     — TriggerServerEvent calls
--   http_requests — PerformHttpRequest calls
--   convars       — GetConvar/GetConvarInt calls
--   threads       — CreateThread calls
--   state_bags    — AddStateBagChangeHandler calls
-----------------------------------------------------------------------

COLLECTOR = {}

-- Dados por resource: COLLECTOR._data["resourceName"] = { ... }
COLLECTOR._data     = {}
-- Resource atualmente "ativo" (sendo executado no tick corrente)
COLLECTOR._current  = nil
-- Stack para suportar chamadas aninhadas
COLLECTOR._stack    = {}

-----------------------------------------------------------------------
-- Cria/retorna a tabela de dados de um resource
-----------------------------------------------------------------------
local function get_data(res)
    if not res or res == "" then return nil end
    if not COLLECTOR._data[res] then
        COLLECTOR._data[res] = {
            resource      = res,
            events        = {},   -- [name] = true
            net_events    = {},   -- [name] = true
            commands      = {},   -- [name] = { restricted }
            exports_reg   = {},   -- [name] = true
            client_events = {},   -- [name] = count
            sv_events     = {},   -- [name] = count
            http_requests = {},   -- { method, url }
            convars       = {},   -- [name] = default
            threads       = 0,
            state_bags    = {},   -- [key] = true
            started_at    = GetGameTimer(),
        }
    end
    return COLLECTOR._data[res]
end

-----------------------------------------------------------------------
-- Retorna o resource que está chamando agora.
-- GetInvokingResource() é a forma nativa do FiveM de saber qual
-- resource originou a chamada atual.
-- Fallback: COLLECTOR._current se não houver invoking resource.
-----------------------------------------------------------------------
local function calling_resource()
    local inv = GetInvokingResource and GetInvokingResource()
    if inv and inv ~= "" and inv ~= GetCurrentResourceName() then
        return inv
    end
    return COLLECTOR._current
end

-----------------------------------------------------------------------
-- Guarda os originais ANTES de qualquer monkey-patch
-----------------------------------------------------------------------
local _orig = {
    AddEventHandler          = AddEventHandler,
    RegisterNetEvent         = RegisterNetEvent,
    RegisterCommand          = RegisterCommand,
    TriggerClientEvent       = TriggerClientEvent,
    TriggerEvent             = TriggerEvent,
    PerformHttpRequest       = PerformHttpRequest,
    GetConvar                = GetConvar,
    GetConvarInt             = GetConvarInt,
    CreateThread             = CreateThread,
    AddStateBagChangeHandler = AddStateBagChangeHandler,
}

-----------------------------------------------------------------------
-- Monkey-patch: AddEventHandler
-----------------------------------------------------------------------
AddEventHandler = function(eventName, handler)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then d.events[tostring(eventName)] = true end
    end
    return _orig.AddEventHandler(eventName, handler)
end

-----------------------------------------------------------------------
-- Monkey-patch: RegisterNetEvent
-----------------------------------------------------------------------
RegisterNetEvent = function(eventName, handler)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then d.net_events[tostring(eventName)] = true end
    end
    return _orig.RegisterNetEvent(eventName, handler)
end

-----------------------------------------------------------------------
-- Monkey-patch: RegisterCommand
-----------------------------------------------------------------------
RegisterCommand = function(commandName, handler, restricted)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then
            d.commands[tostring(commandName)] = {
                restricted = restricted == true
            }
        end
    end
    return _orig.RegisterCommand(commandName, handler, restricted)
end

-----------------------------------------------------------------------
-- Monkey-patch: TriggerClientEvent
-----------------------------------------------------------------------
TriggerClientEvent = function(eventName, target, ...)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then
            d.client_events[tostring(eventName)] = (d.client_events[tostring(eventName)] or 0) + 1
        end
    end
    return _orig.TriggerClientEvent(eventName, target, ...)
end

-----------------------------------------------------------------------
-- Monkey-patch: TriggerEvent (server interno)
-----------------------------------------------------------------------
TriggerEvent = function(eventName, ...)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then
            d.sv_events[tostring(eventName)] = (d.sv_events[tostring(eventName)] or 0) + 1
        end
    end
    return _orig.TriggerEvent(eventName, ...)
end

-----------------------------------------------------------------------
-- Monkey-patch: PerformHttpRequest
-----------------------------------------------------------------------
PerformHttpRequest = function(url, callback, method, ...)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then
            d.http_requests[#d.http_requests + 1] = {
                url    = tostring(url or ""),
                method = tostring(method or "GET"),
            }
        end
    end
    return _orig.PerformHttpRequest(url, callback, method, ...)
end

-----------------------------------------------------------------------
-- Monkey-patch: GetConvar / GetConvarInt
-----------------------------------------------------------------------
GetConvar = function(name, default)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then d.convars[tostring(name)] = default end
    end
    return _orig.GetConvar(name, default)
end

GetConvarInt = function(name, default)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then d.convars[tostring(name)] = default end
    end
    return _orig.GetConvarInt(name, default)
end

-----------------------------------------------------------------------
-- Monkey-patch: CreateThread
-----------------------------------------------------------------------
CreateThread = function(fn)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then d.threads = d.threads + 1 end
    end
    return _orig.CreateThread(fn)
end

-----------------------------------------------------------------------
-- Monkey-patch: AddStateBagChangeHandler
-----------------------------------------------------------------------
AddStateBagChangeHandler = function(keyFilter, bagFilter, handler)
    local res = calling_resource()
    if res then
        local d = get_data(res)
        if d then d.state_bags[tostring(keyFilter or "*")] = true end
    end
    return _orig.AddStateBagChangeHandler(keyFilter, bagFilter, handler)
end

-----------------------------------------------------------------------
-- Coleta dados quando um resource inicia (onResourceStart)
-- O resource já executou seus scripts neste ponto — os monkey-patches
-- já capturaram tudo que foi registrado durante a inicialização.
-----------------------------------------------------------------------
_orig.AddEventHandler("onResourceStart", function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    -- Garante que a entrada existe mesmo que o resource não tenha
    -- chamado nenhuma API monitorada
    get_data(resourceName)
    -- Marca timestamp de conclusão
    local d = COLLECTOR._data[resourceName]
    if d then
        d.finished_at = GetGameTimer()
    end
end)

-----------------------------------------------------------------------
-- Limpa dados quando resource para (permite re-análise ao reiniciar)
-----------------------------------------------------------------------
_orig.AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    COLLECTOR._data[resourceName] = nil
end)

print("^5[Dumper]^7 Collector ativo — interceptando APIs globais do FiveM.")
