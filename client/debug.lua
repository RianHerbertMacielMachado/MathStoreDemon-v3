-----------------------------------------------------------------------
-- client/debug.lua — MathStoreDemon-v3
--
-- Sistema de debug do lado CLIENTE.
-- Intercepta todos os pontos de entrada/saída das partes obfuscadas:
--   • AddEventHandler  (o que os scripts obfuscados RECEBEM)
--   • TriggerServerEvent (o que os scripts obfuscados ENVIAM ao server)
--   • TriggerEvent     (eventos locais client-side)
--   • SendNuiMessage   (o que vai para o HTML/NUI)
--   • Fetch NUI (o que o HTML envia de volta ao Lua — via URL /nomeevent)
--   • CreateThread     (threads que o obfuscado inicia)
--   • Globals rastreados: PlayerWings, PlayerTails, Bridge, IsCoreReady
--
-- ATIVAÇÃO: Config.Debug.Enabled = true  em config.lua
-- FILTRO:   Config.Debug.Filter  (string parcial de nome de evento)
--           Config.Debug.LogFile = true  (escreve em debug_client.log)
-----------------------------------------------------------------------

if not Config or not Config.Debug or not Config.Debug.Enabled then
    return
end

local resourceName = GetCurrentResourceName()
local cfg          = Config.Debug
local filter       = (cfg.Filter or ''):lower()
local useLogFile   = cfg.LogFile == true
local showThreads  = cfg.ShowThreads ~= false
local showNui      = cfg.ShowNui     ~= false
local showLocals   = cfg.ShowLocals  ~= false
local startTime    = GetGameTimer()

local LOG_PREFIX   = '^5[DBG:CL]^7'
local WARN_PREFIX  = '^3[DBG:CL]^7'
local NUI_PREFIX   = '^6[DBG:NUI]^7'
local EVT_PREFIX   = '^2[DBG:EVT]^7'
local NET_PREFIX   = '^4[DBG:NET]^7'

-----------------------------------------------------------------------
-- Utilitários
-----------------------------------------------------------------------

--- Serializa qualquer valor de forma legível
local function serialize(val, depth)
    depth = depth or 0
    if depth > 4 then return '...' end
    local t = type(val)
    if t == 'nil'     then return 'nil' end
    if t == 'boolean' then return tostring(val) end
    if t == 'number'  then return tostring(val) end
    if t == 'string'  then
        -- trunca strings longas para não poluir o log
        if #val > 200 then
            return '"' .. val:sub(1, 200) .. '…"'
        end
        return '"' .. val .. '"'
    end
    if t == 'function' then return '<function>' end
    if t == 'table' then
        local parts = {}
        local count = 0
        for k, v in pairs(val) do
            count = count + 1
            if count > 20 then
                parts[#parts + 1] = '...'
                break
            end
            local key = type(k) == 'string' and k or ('[' .. tostring(k) .. ']')
            parts[#parts + 1] = key .. '=' .. serialize(v, depth + 1)
        end
        return '{' .. table.concat(parts, ', ') .. '}'
    end
    return '<' .. t .. '>'
end

--- Timestamp relativo ao início do resource (ms)
local function ts()
    return string.format('+%dms', GetGameTimer() - startTime)
end

--- Filtra pelo nome do evento
local function shouldLog(name)
    if filter == '' then return true end
    return name:lower():find(filter, 1, true) ~= nil
end

--- Escreve no chat de desenvolvimento (F8) e opcionalmente em arquivo
local function dbg(prefix, msg)
    local line = prefix .. ' ' .. ts() .. ' ' .. msg
    print(line)
end

-----------------------------------------------------------------------
-- 1. Interceptar AddEventHandler
--    Envolve o callback registrado para logar toda vez que disparar
-----------------------------------------------------------------------
local _AddEventHandler = AddEventHandler

AddEventHandler = function(eventName, handler)
    if not shouldLog(eventName) then
        return _AddEventHandler(eventName, handler)
    end

    local wrapped = function(...)
        local args = { ... }
        local argsStr = ''
        for i, v in ipairs(args) do
            argsStr = argsStr .. (i > 1 and ', ' or '') .. serialize(v)
        end
        dbg(EVT_PREFIX, 'EVENT fired: "' .. eventName .. '"  args=(' .. argsStr .. ')')
        return handler(...)
    end

    return _AddEventHandler(eventName, wrapped)
end

-----------------------------------------------------------------------
-- 2. Interceptar TriggerServerEvent
--    Captura tudo que o cliente (incluindo obfuscado) envia ao server
-----------------------------------------------------------------------
local _TriggerServerEvent = TriggerServerEvent

TriggerServerEvent = function(eventName, ...)
    if shouldLog(eventName) then
        local args = { ... }
        local argsStr = ''
        for i, v in ipairs(args) do
            argsStr = argsStr .. (i > 1 and ', ' or '') .. serialize(v)
        end
        dbg(NET_PREFIX, 'TriggerServerEvent: "' .. eventName .. '"  data=(' .. argsStr .. ')')
    end
    return _TriggerServerEvent(eventName, ...)
end

-----------------------------------------------------------------------
-- 3. Interceptar TriggerEvent (local client)
-----------------------------------------------------------------------
local _TriggerEvent = TriggerEvent

TriggerEvent = function(eventName, ...)
    if shouldLog(eventName) then
        local args = { ... }
        local argsStr = ''
        for i, v in ipairs(args) do
            argsStr = argsStr .. (i > 1 and ', ' or '') .. serialize(v)
        end
        dbg(EVT_PREFIX, 'TriggerEvent(local): "' .. eventName .. '"  data=(' .. argsStr .. ')')
    end
    return _TriggerEvent(eventName, ...)
end

-----------------------------------------------------------------------
-- 4. Interceptar SendNuiMessage
--    Captura mensagens que o Lua envia ao HTML (openHud, closeHud, etc.)
-----------------------------------------------------------------------
if showNui then
    local _SendNuiMessage = SendNuiMessage

    SendNuiMessage = function(jsonStr)
        dbg(NUI_PREFIX, 'SendNuiMessage → ' .. (jsonStr or 'nil'))
        return _SendNuiMessage(jsonStr)
    end
end

-----------------------------------------------------------------------
-- 5. Interceptar RegisterNuiCallback
--    Captura respostas do HTML ao Lua (hudAction, closeHud, etc.)
-----------------------------------------------------------------------
if showNui then
    local _RegisterNuiCallback = RegisterNuiCallback

    RegisterNuiCallback = function(cbName, handler)
        local wrapped = function(body, cb)
            dbg(NUI_PREFIX, 'NUI callback received: "' .. cbName .. '"  body=' .. serialize(body))
            return handler(body, function(response)
                dbg(NUI_PREFIX, 'NUI callback response: "' .. cbName .. '"  → ' .. serialize(response))
                return cb(response)
            end)
        end
        return _RegisterNuiCallback(cbName, wrapped)
    end
end

-----------------------------------------------------------------------
-- 6. Interceptar CreateThread
--    Mostra quantas threads os obfuscados criam (ajuda a mapear loops)
-----------------------------------------------------------------------
if showThreads then
    local _CreateThread = CreateThread
    local threadCount   = 0

    CreateThread = function(fn)
        threadCount = threadCount + 1
        local id = threadCount
        dbg(LOG_PREFIX, 'CreateThread #' .. id .. ' started')
        return _CreateThread(function()
            local ok, err = pcall(fn)
            if not ok then
                dbg(WARN_PREFIX, 'Thread #' .. id .. ' ERROR: ' .. tostring(err))
            else
                dbg(LOG_PREFIX, 'Thread #' .. id .. ' finished')
            end
        end)
    end
end

-----------------------------------------------------------------------
-- 7. Watcher de globals relevantes
--    Verifica se as variáveis globais que o obfuscado deveria setar
--    foram criadas e loga seu estado a cada intervalo
-----------------------------------------------------------------------
if showLocals then
    CreateThread(function()
        Wait(3000) -- aguarda scripts carregarem
        while true do
            Wait(cfg.WatchInterval or 5000)

            local function watchGlobal(name, val)
                dbg(LOG_PREFIX, 'GLOBAL [' .. name .. '] = ' .. serialize(val))
            end

            watchGlobal('IsCoreReady()',   type(IsCoreReady) == 'function' and tostring(IsCoreReady()) or 'NOT SET')
            watchGlobal('Bridge',          Bridge)
            watchGlobal('PlayerWings',     PlayerWings)  -- se o obfuscado expuser
            watchGlobal('PlayerTails',     PlayerTails)  -- se o obfuscado expuser

            -- Detecta qualquer global nova criada desde o último ciclo
            -- (util para ver o que os obfuscados expõem)
            if cfg.WatchNewGlobals then
                for k, v in pairs(_G) do
                    if type(v) ~= 'function' and type(k) == 'string'
                       and not k:match('^_') then
                        local vt = type(v)
                        if vt == 'table' or vt == 'boolean' or vt == 'number' then
                            -- só loga não-string para não poluir com locales, etc.
                            if k ~= 'Config' and k ~= 'Locales' and k ~= 'Permissions'
                               and k ~= 'Bridge' and k ~= 'I18N' then
                                dbg(LOG_PREFIX, '_G["' .. k .. '"] = ' .. serialize(v, 1))
                            end
                        end
                    end
                end
            end
        end
    end)
end

-----------------------------------------------------------------------
-- 8. Interceptar SetEntityCoords / AttachEntityToEntity
--    Os scripts obfuscados de bones/props usam essas nativas FiveM
--    — logar aqui revela ONDE o prop está sendo attachado
-----------------------------------------------------------------------
if cfg.ShowNativeHooks then
    local _AttachEntityToEntity = AttachEntityToEntity

    AttachEntityToEntity = function(entity, entityTo, boneIndex, ...)
        dbg(LOG_PREFIX, string.format(
            'AttachEntityToEntity(entity=%s, to=%s, bone=%s)',
            tostring(entity), tostring(entityTo), tostring(boneIndex)
        ))
        return _AttachEntityToEntity(entity, entityTo, boneIndex, ...)
    end

    local _CreateObject = CreateObject

    CreateObject = function(model, ...)
        local args = { model, ... }
        dbg(LOG_PREFIX, 'CreateObject(model=' .. serialize(model) .. ')')
        local result = _CreateObject(model, ...)
        dbg(LOG_PREFIX, 'CreateObject → entity=' .. tostring(result))
        return result
    end

    local _RequestModel = RequestModel

    RequestModel = function(model)
        dbg(LOG_PREFIX, 'RequestModel(model=' .. serialize(model) .. ')')
        return _RequestModel(model)
    end

    local _PlayAnimOnEntity = PlayAnimOnEntity

    if _PlayAnimOnEntity then
        PlayAnimOnEntity = function(entity, animDict, animName, ...)
            dbg(LOG_PREFIX, string.format(
                'PlayAnimOnEntity(entity=%s, dict="%s", anim="%s")',
                tostring(entity), tostring(animDict), tostring(animName)
            ))
            return _PlayAnimOnEntity(entity, animDict, animName, ...)
        end
    end

    local _TaskPlayAnim = TaskPlayAnim

    TaskPlayAnim = function(ped, animDict, animName, ...)
        dbg(LOG_PREFIX, string.format(
            'TaskPlayAnim(ped=%s, dict="%s", anim="%s")',
            tostring(ped), tostring(animDict), tostring(animName)
        ))
        return _TaskPlayAnim(ped, animDict, animName, ...)
    end
end

-----------------------------------------------------------------------
-- 9. Captura de erros globais (pcall wrapper dos eventos)
-----------------------------------------------------------------------
local _origAddEventHandler = _AddEventHandler

_origAddEventHandler('onClientResourceStart', function(res)
    if res == resourceName then
        dbg(LOG_PREFIX, '=== DEBUG CLIENT ATIVO | resource: ' .. resourceName .. ' ===')
        dbg(LOG_PREFIX, 'filter="' .. filter .. '"  logFile=' .. tostring(useLogFile))
        dbg(LOG_PREFIX, 'showNui=' .. tostring(showNui) ..
            '  showThreads=' .. tostring(showThreads) ..
            '  showLocals=' .. tostring(showLocals) ..
            '  nativeHooks=' .. tostring(cfg.ShowNativeHooks or false))
    end
end)

print('^5[' .. resourceName .. '] client/debug.lua carregado (debug ATIVO).^0')
