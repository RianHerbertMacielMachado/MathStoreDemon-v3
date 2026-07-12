-----------------------------------------------------------------------
-- server/debug.lua — MathStoreDemon-v3
--
-- Sistema de debug do lado SERVIDOR.
-- Intercepta todos os pontos de borda das partes obfuscadas:
--   • TriggerClientEvent   (o que o server envia a clientes)
--   • TriggerLatentClientEvent (versão com bandwidth limit)
--   • RegisterNetEvent     (eventos que o server aceita receber)
--   • AddEventHandler      (handlers registrados server-side)
--   • TriggerEvent         (eventos locais server-side)
--   • Estado global: PlayerWings, PlayerTails, cooldowns
--   • PerformHttpRequest   (chamadas HTTP — auth, etc.)
--
-- ATIVAÇÃO: Config.Debug.Enabled = true  em config.lua
-----------------------------------------------------------------------

if not Config or not Config.Debug or not Config.Debug.Enabled then
    return
end

local resourceName = GetCurrentResourceName()
local cfg          = Config.Debug
local filter       = (cfg.Filter or ''):lower()
local startTime    = os.time()

local LOG_PREFIX   = '^5[DBG:SV]^7'
local WARN_PREFIX  = '^3[DBG:SV]^7'
local NET_PREFIX   = '^4[DBG:NET→CL]^7'
local EVT_PREFIX   = '^2[DBG:EVT]^7'
local HTTP_PREFIX  = '^6[DBG:HTTP]^7'

-----------------------------------------------------------------------
-- Utilitários
-----------------------------------------------------------------------

local function serialize(val, depth)
    depth = depth or 0
    if depth > 4 then return '...' end
    local t = type(val)
    if t == 'nil'     then return 'nil' end
    if t == 'boolean' then return tostring(val) end
    if t == 'number'  then return tostring(val) end
    if t == 'string'  then
        if #val > 200 then return '"' .. val:sub(1, 200) .. '…"' end
        return '"' .. val .. '"'
    end
    if t == 'function' then return '<function>' end
    if t == 'table' then
        local parts = {}
        local count = 0
        for k, v in pairs(val) do
            count = count + 1
            if count > 20 then parts[#parts + 1] = '...'; break end
            local key = type(k) == 'string' and k or ('[' .. tostring(k) .. ']')
            parts[#parts + 1] = key .. '=' .. serialize(v, depth + 1)
        end
        return '{' .. table.concat(parts, ', ') .. '}'
    end
    return '<' .. t .. '>'
end

local function ts()
    return string.format('+%ds', os.time() - startTime)
end

local function shouldLog(name)
    if filter == '' then return true end
    return name:lower():find(filter, 1, true) ~= nil
end

local function dbg(prefix, msg)
    print(prefix .. ' ' .. ts() .. ' ' .. msg)
end

-----------------------------------------------------------------------
-- 1. Interceptar TriggerClientEvent
--    Captura TUDO que o server envia a qualquer cliente
-----------------------------------------------------------------------
local _TriggerClientEvent = TriggerClientEvent

TriggerClientEvent = function(eventName, target, ...)
    if shouldLog(eventName) then
        local args = { ... }
        local argsStr = ''
        for i, v in ipairs(args) do
            argsStr = argsStr .. (i > 1 and ', ' or '') .. serialize(v)
        end
        local targetStr = target == -1 and 'ALL' or tostring(target)
        dbg(NET_PREFIX, string.format(
            'TriggerClientEvent: "%s"  target=%s  data=(%s)',
            eventName, targetStr, argsStr
        ))
    end
    return _TriggerClientEvent(eventName, target, ...)
end

-----------------------------------------------------------------------
-- 2. Interceptar TriggerLatentClientEvent
-----------------------------------------------------------------------
local _TriggerLatentClientEvent = TriggerLatentClientEvent

if _TriggerLatentClientEvent then
    TriggerLatentClientEvent = function(eventName, target, bps, ...)
        if shouldLog(eventName) then
            dbg(NET_PREFIX, string.format(
                'TriggerLatentClientEvent: "%s"  target=%s  bps=%s',
                eventName, tostring(target), tostring(bps)
            ))
        end
        return _TriggerLatentClientEvent(eventName, target, bps, ...)
    end
end

-----------------------------------------------------------------------
-- 3. Interceptar RegisterNetEvent
--    Mostra quais eventos o servidor (obfuscado) registra como receptores
-----------------------------------------------------------------------
local _RegisterNetEvent = RegisterNetEvent

RegisterNetEvent = function(eventName, handler)
    if shouldLog(eventName) then
        dbg(EVT_PREFIX, 'RegisterNetEvent: "' .. eventName .. '"'
            .. (handler and '  [with inline handler]' or ''))
    end
    if handler then
        return _RegisterNetEvent(eventName, handler)
    end
    return _RegisterNetEvent(eventName)
end

-----------------------------------------------------------------------
-- 4. Interceptar AddEventHandler
--    Envolve cada handler para logar quando disparar + quem disparou
-----------------------------------------------------------------------
local _AddEventHandler = AddEventHandler

AddEventHandler = function(eventName, handler)
    if not shouldLog(eventName) then
        return _AddEventHandler(eventName, handler)
    end

    local wrapped = function(...)
        local src = source  -- source é global no contexto de eventos FiveM
        local args = { ... }
        local argsStr = ''
        for i, v in ipairs(args) do
            argsStr = argsStr .. (i > 1 and ', ' or '') .. serialize(v)
        end
        dbg(EVT_PREFIX, string.format(
            'EVENT fired: "%s"  source=%s  args=(%s)',
            eventName, tostring(src), argsStr
        ))
        local ok, err = pcall(handler, ...)
        if not ok then
            dbg(WARN_PREFIX, 'ERROR in handler "' .. eventName .. '": ' .. tostring(err))
        end
    end

    return _AddEventHandler(eventName, wrapped)
end

-----------------------------------------------------------------------
-- 5. Interceptar TriggerEvent (local server-side)
-----------------------------------------------------------------------
local _TriggerEvent = TriggerEvent

TriggerEvent = function(eventName, ...)
    if shouldLog(eventName) then
        local args = { ... }
        local argsStr = ''
        for i, v in ipairs(args) do
            argsStr = argsStr .. (i > 1 and ', ' or '') .. serialize(v)
        end
        dbg(EVT_PREFIX, 'TriggerEvent(local-sv): "' .. eventName .. '"  data=(' .. argsStr .. ')')
    end
    return _TriggerEvent(eventName, ...)
end

-----------------------------------------------------------------------
-- 6. Interceptar PerformHttpRequest
--    Captura chamadas HTTP (auth, webhooks, etc.) feitas pelo obfuscado
-----------------------------------------------------------------------
if cfg.ShowHttp ~= false then
    local _PerformHttpRequest = PerformHttpRequest

    PerformHttpRequest = function(url, cb, method, data, headers, options)
        dbg(HTTP_PREFIX, string.format(
            'HTTP %s → %s  body=%s',
            (method or 'GET'), url, serialize(data)
        ))

        local wrappedCb = function(statusCode, responseText, responseHeaders)
            -- trunca resposta para não poluir
            local resp = (responseText or ''):sub(1, 300)
            dbg(HTTP_PREFIX, string.format(
                'HTTP response %s ← %s  body=%s',
                tostring(statusCode), url, resp
            ))
            if cb then cb(statusCode, responseText, responseHeaders) end
        end

        return _PerformHttpRequest(url, wrappedCb, method, data, headers, options)
    end
end

-----------------------------------------------------------------------
-- 7. Watcher de estado global a cada intervalo
--    Mostra snapshot de PlayerWings, PlayerTails, WingObjects, TailObjects
-----------------------------------------------------------------------
if cfg.ShowLocals ~= false then
    CreateThread(function()
        Wait(3000)
        while true do
            Wait(cfg.WatchInterval or 10000)

            dbg(LOG_PREFIX, '── SNAPSHOT DE ESTADO ──')

            -- Jogadores online
            local players = GetPlayers()
            dbg(LOG_PREFIX, 'Jogadores online: ' .. #players)

            -- Wings
            local wCount = 0
            for src, data in pairs(PlayerWings or {}) do
                wCount = wCount + 1
                dbg(LOG_PREFIX, string.format(
                    '  Wing[%s] cor=%s  obj=%s',
                    tostring(src),
                    data and tostring(data.cor) or 'nil',
                    tostring((WingObjects or {})[src])
                ))
            end
            if wCount == 0 then dbg(LOG_PREFIX, '  Wings: nenhuma equipada') end

            -- Tails
            local tCount = 0
            for src, data in pairs(PlayerTails or {}) do
                tCount = tCount + 1
                dbg(LOG_PREFIX, string.format(
                    '  Tail[%s] cor=%s  obj=%s',
                    tostring(src),
                    data and tostring(data.cor) or 'nil',
                    tostring((TailObjects or {})[src])
                ))
            end
            if tCount == 0 then dbg(LOG_PREFIX, '  Tails: nenhuma equipada') end

            dbg(LOG_PREFIX, '── FIM SNAPSHOT ──')
        end
    end)
end

-----------------------------------------------------------------------
-- 8. Log de connects / disconnects de jogadores
-----------------------------------------------------------------------
_AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    dbg(LOG_PREFIX, string.format('playerConnecting: name="%s" source=%s', name, tostring(src)))
end)

_AddEventHandler('playerDropped', function(reason)
    local src = source
    dbg(LOG_PREFIX, string.format(
        'playerDropped: source=%s reason="%s"  hadWing=%s  hadTail=%s',
        tostring(src),
        tostring(reason),
        tostring((PlayerWings or {})[src] ~= nil),
        tostring((PlayerTails or {})[src] ~= nil)
    ))
end)

-----------------------------------------------------------------------
-- 9. Comando de debug em tempo real: /dmdbg [snapshot|clear|filter <txt>]
-----------------------------------------------------------------------
RegisterCommand('dmdbg', function(src, args)
    -- só console (src == 0) ou admin
    if src ~= 0 and not Bridge.HasPermission(src, 'admin_cleanup') then
        return
    end

    local subcmd = args[1] or 'snapshot'

    if subcmd == 'snapshot' then
        dbg(LOG_PREFIX, '=== SNAPSHOT MANUAL (solicitado por ' .. tostring(src) .. ') ===')
        dbg(LOG_PREFIX, 'PlayerWings = ' .. serialize(PlayerWings))
        dbg(LOG_PREFIX, 'PlayerTails = ' .. serialize(PlayerTails))
        dbg(LOG_PREFIX, 'WingObjects = ' .. serialize(WingObjects))
        dbg(LOG_PREFIX, 'TailObjects = ' .. serialize(TailObjects))

    elseif subcmd == 'players' then
        for _, pid in ipairs(GetPlayers()) do
            local id = tonumber(pid)
            dbg(LOG_PREFIX, string.format(
                'Player[%s] name="%s"  wing=%s  tail=%s',
                pid,
                GetPlayerName(id) or '?',
                serialize((PlayerWings or {})[id]),
                serialize((PlayerTails or {})[id])
            ))
        end

    elseif subcmd == 'filter' then
        local newFilter = args[2] or ''
        filter = newFilter:lower()
        dbg(LOG_PREFIX, 'Filter atualizado para: "' .. filter .. '"')

    elseif subcmd == 'help' then
        dbg(LOG_PREFIX, 'Comandos: /dmdbg snapshot | /dmdbg players | /dmdbg filter <texto> | /dmdbg help')
    end
end, true)

-----------------------------------------------------------------------
-- 10. Registro inicial
-----------------------------------------------------------------------
CreateThread(function()
    Wait(200)
    dbg(LOG_PREFIX, '=== DEBUG SERVER ATIVO | resource: ' .. resourceName .. ' ===')
    dbg(LOG_PREFIX, 'filter="' .. filter .. '"')
    dbg(LOG_PREFIX, 'showHttp=' .. tostring(cfg.ShowHttp ~= false) ..
        '  showLocals=' .. tostring(cfg.ShowLocals ~= false) ..
        '  watchInterval=' .. tostring(cfg.WatchInterval or 10000) .. 'ms')
    dbg(LOG_PREFIX, 'Comandos disponíveis: /dmdbg snapshot | players | filter <txt> | help')
end)

print('^5[' .. resourceName .. '] server/debug.lua carregado (debug ATIVO).^0')
