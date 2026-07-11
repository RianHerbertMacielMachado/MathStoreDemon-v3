-----------------------------------------------------------------------
-- bridge/shared.lua — MathStoreDemon-v3
-- Utilitários compartilhados (cliente + servidor)
-- Carregado como shared_script — roda nos dois lados
-----------------------------------------------------------------------

Bridge = Bridge or {}

local resourceName = GetCurrentResourceName()

-----------------------------------------------------------------------
-- Detecção de framework (compartilhada)
-----------------------------------------------------------------------
local _framework = nil

function Bridge.GetFramework()
    if _framework then return _framework end

    local cfg = Config and Config.Framework or 'auto'

    if cfg ~= 'auto' then
        _framework = cfg
        return _framework
    end

    if GetResourceState('qbx_core')   == 'started' then _framework = 'qbx'
    elseif GetResourceState('qb-core')   == 'started' then _framework = 'qb'
    elseif GetResourceState('es_extended')== 'started' then _framework = 'esx'
    elseif GetResourceState('vrp')       == 'started' then _framework = 'vrp'
    else _framework = 'standalone'
    end

    return _framework
end

-----------------------------------------------------------------------
-- Notificação (compartilhada — cada lado usa sua implementação)
-----------------------------------------------------------------------

--- Envia uma notificação ao jogador local (client-side only)
--- No servidor, use Bridge.Notify(source, msg, tipo) de bridge/server.lua
--- @param msg string
--- @param tipo string  'success' | 'error' | 'inform' | 'warning'
--- @param duracao number  (ms, padrão 5000)
function Bridge.ShowNotification(msg, tipo, duracao)
    tipo   = tipo   or 'inform'
    duracao = duracao or (Config and Config.Notifications and Config.Notifications.duration) or 5000

    -- ox_lib
    if Config and Config.UseOxLib and lib and lib.notify then
        lib.notify({ title = 'Demon', description = msg, type = tipo, duration = duracao })
        return
    end

    -- Notificação nativa GTA V
    SetNotificationTextEntry('STRING')
    AddTextComponentString(msg)
    DrawNotification(false, true)
end

-----------------------------------------------------------------------
-- Helper: locale / tradução
-----------------------------------------------------------------------

--- Retorna string traduzida (alias para a função global L())
--- @param key string
--- @param ... any
--- @return string
function Bridge.L(key, ...)
    if L then return L(key, ...) end
    return key
end

-----------------------------------------------------------------------
-- Helper: nome do resource
-----------------------------------------------------------------------
function Bridge.GetResourceName()
    return resourceName
end

-----------------------------------------------------------------------
-- Helper: evento com prefixo do resource
--- @param suffix string
--- @return string
function Bridge.Event(suffix)
    return resourceName .. ':' .. suffix
end

-----------------------------------------------------------------------
-- Versão / info
-----------------------------------------------------------------------
Bridge.Version  = GetResourceMetadata(resourceName, 'version', 0) or '1.0.0'
Bridge.Author   = GetResourceMetadata(resourceName, 'author',  0) or 'MathSchiavi'
