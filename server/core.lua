-----------------------------------------------------------------------
-- server/core.lua — MathStoreDemon-v3
-- Núcleo do servidor:
--   • Estado global de asas e caudas por jogador
--   • Sistema de cooldown
--   • Autenticação da key do produto
--   • Evento de pronto do servidor
-----------------------------------------------------------------------

local resourceName = GetCurrentResourceName()

-----------------------------------------------------------------------
-- Estado global
-- PlayerWings[source]  = { cor = number }  ou nil
-- PlayerTails[source]  = { cor = number }  ou nil
-----------------------------------------------------------------------
PlayerWings = {}
PlayerTails = {}

-- Objetos (props) spawned no mundo, rastreados pelo servidor
-- WingObjects[source]  = netId  (int)
-- TailObjects[source]  = netId  (int)
WingObjects = {}
TailObjects = {}

-----------------------------------------------------------------------
-- Cooldown
-----------------------------------------------------------------------
local cooldowns = {}

--- Verifica se o jogador está em cooldown para uma ação
---@param source number
---@param action string
---@return boolean, number  -- em cooldown, segundos restantes
function IsOnCooldown(source, action)
    local seconds = Config.Cooldowns and Config.Cooldowns[action] or 0
    if seconds <= 0 then return false, 0 end

    local key = tostring(source) .. '_' .. action
    local last = cooldowns[key]
    if not last then return false, 0 end

    local elapsed = os.time() - last
    if elapsed >= seconds then
        cooldowns[key] = nil
        return false, 0
    end
    return true, seconds - elapsed
end

--- Registra início de cooldown para um jogador/ação
---@param source number
---@param action string
function SetCooldown(source, action)
    local seconds = Config.Cooldowns and Config.Cooldowns[action] or 0
    if seconds <= 0 then return end
    local key = tostring(source) .. '_' .. action
    cooldowns[key] = os.time()
end

--- Limpa todos os cooldowns de um jogador (ao sair)
---@param source number
function ClearPlayerCooldowns(source)
    local prefix = tostring(source) .. '_'
    for k in pairs(cooldowns) do
        if k:sub(1, #prefix) == prefix then
            cooldowns[k] = nil
        end
    end
end

-----------------------------------------------------------------------
-- Limpeza ao jogador sair
-----------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local source = source
    PlayerWings[source] = nil
    PlayerTails[source] = nil
    WingObjects[source] = nil
    TailObjects[source] = nil
    ClearPlayerCooldowns(source)
end)

-----------------------------------------------------------------------
-- Autenticação do produto
-- A key é lida do convar  mathstore_demon_key  (set no server.cfg)
-- Formato: set mathstore_demon_key "AP-XXXX-XXXX-XXXX"
--
-- O servidor faz uma requisição HTTP ao painel de autenticação.
-- Em caso de falha de rede o recurso continua, mas loga aviso.
-- Em caso de key bloqueada / produto errado o recurso é parado.
-----------------------------------------------------------------------
local AUTH_URL    = 'https://mathstore.shop/api/auth/verify'
local PRODUCT_ID  = 'demon_v3'
local CONVAR_NAME = 'mathstore_demon_key'

local authDone    = true
local authPassed  = true

local function logAuth(msg)
    print('^1[' .. resourceName .. '] AUTH | ' .. msg .. '^0')
end

local function doAuth()
    local key = GetConvar(CONVAR_NAME, '')

    if key == '' or key == 'AP-XXXX-XXXX-XXXX' then
        logAuth(L('auth_no_key'))
        logAuth(L('auth_add_line'))
        logAuth(L('auth_format', CONVAR_NAME))
        logAuth(L('auth_replace'))
        logAuth(L('auth_contact'))
        -- Não pára o recurso por ausência de key; permite uso em ambiente de dev
        authDone   = true
        authPassed = true
        return
    end

    local body = json.encode({ key = key, product = PRODUCT_ID, resource = resourceName })

    PerformHttpRequest(AUTH_URL, function(statusCode, responseText, _headers)
        authDone = true

        if statusCode == 0 or statusCode == nil then
            -- Sem resposta (sem internet ou servidor offline)
            logAuth(L('auth_connection', statusCode or 0))
            logAuth(L('auth_connection2'))
            logAuth(L('auth_connection3'))
            -- Permite continuar mesmo sem validação (modo offline tolerante)
            authPassed = true
            return
        end

        if statusCode ~= 200 then
            logAuth(L('auth_connection', statusCode))
            logAuth(L('auth_connection2'))
            authPassed = true   -- tolerante a erros HTTP
            return
        end

        local data = json.decode(responseText or '{}') or {}

        if data.status == 'not_found' then
            logAuth(L('auth_not_found'))
            logAuth(L('auth_check_cfg'))
            logAuth(L('auth_format', CONVAR_NAME))
            logAuth(L('auth_shutdown'))
            StopResource(resourceName)
            authPassed = false
            return
        end

        if data.status == 'disabled' then
            logAuth(L('auth_disabled'))
            logAuth(L('auth_disabled_reason'))
            logAuth(L('auth_disabled_contact'))
            logAuth(L('auth_shutdown'))
            StopResource(resourceName)
            authPassed = false
            return
        end

        if data.status == 'wrong_product' then
            logAuth(L('auth_wrong_product'))
            logAuth(L('auth_wrong_product2'))
            logAuth(L('auth_shutdown'))
            StopResource(resourceName)
            authPassed = false
            return
        end

        -- status == 'ok' ou qualquer outro valor positivo
        authPassed = true
        print('^2[' .. resourceName .. '] Produto autenticado com sucesso.^0')
    end, 'POST', body, { ['Content-Type'] = 'application/json' })
end

-----------------------------------------------------------------------
-- Expõe se a auth passou (usada por server/main.lua)
-----------------------------------------------------------------------
function IsAuthPassed()
    return authPassed
end

-----------------------------------------------------------------------
-- Init — roda auth após o recurso iniciar completamente
-----------------------------------------------------------------------
AddEventHandler('onResourceStart', function(res)
    if res ~= resourceName then return end
    CreateThread(function()
        Wait(500)
        doAuth()
        print('^3[' .. resourceName .. '] server/core.lua carregado.^0')
    end)
end)
