-----------------------------------------------------------------------
-- bridge/client.lua — MathStoreDemon-v3
-- Bridge do lado cliente: detecta framework, expõe dados do jogador,
-- notificações, e integração com ESX / QBX / QB / vRP / standalone
-----------------------------------------------------------------------

Bridge = Bridge or {}

local resourceName = GetCurrentResourceName()
local _fw          = nil   -- instância do framework
local _fwName      = nil   -- nome detectado

-----------------------------------------------------------------------
-- Inicialização: aguarda o framework ficar pronto e obtém a instância
-----------------------------------------------------------------------
CreateThread(function()
    -- Aguarda o core do cliente e a sessão de rede
    while not IsCoreReady() do Wait(100) end

    _fwName = Bridge.GetFramework()

    if _fwName == 'esx' then
        -- ESX: espera até o shared object estar disponível
        while not _fw do
            local ok, obj = pcall(function()
                return exports['es_extended']:getSharedObject()
            end)
            if ok and obj then _fw = obj end
            Wait(200)
        end

    elseif _fwName == 'qbx' then
        local ok, obj = pcall(function()
            return exports['qbx_core']:GetCoreObject()
        end)
        if ok and obj then _fw = obj end

    elseif _fwName == 'qb' then
        local ok, obj = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and obj then _fw = obj end
    end
    -- vRP e standalone não precisam de instância no client

    print(string.format('^2[%s] bridge/client.lua pronto (framework: %s)^0',
        resourceName, _fwName or 'standalone'))
end)

-----------------------------------------------------------------------
-- Bridge.GetPlayerData — retorna dados do jogador local
-- @return table|nil  { name, job, group, citizenid, ... }
-----------------------------------------------------------------------
function Bridge.GetPlayerData()
    if not _fwName then return nil end

    if _fwName == 'esx' then
        if not _fw then return nil end
        local pd = _fw.GetPlayerData()
        if not pd then return nil end
        return {
            name      = pd.name or GetPlayerName(PlayerId()),
            job       = pd.job and pd.job.name or '',
            jobLabel  = pd.job and pd.job.label or '',
            group     = pd.group or '',
            citizenid = pd.identifier or '',
        }

    elseif _fwName == 'qbx' or _fwName == 'qb' then
        if not _fw then return nil end
        local pd = _fw.Functions.GetPlayerData()
        if not pd then return nil end
        return {
            name      = pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname) or GetPlayerName(PlayerId()),
            job       = pd.job and pd.job.name or '',
            jobLabel  = pd.job and pd.job.label or '',
            group     = pd.group or pd.permission or '',
            citizenid = pd.citizenid or '',
        }

    elseif _fwName == 'vrp' then
        local userId = vRP and vRP.getUserId and vRP.getUserId() or nil
        if not userId then return nil end
        return {
            name      = GetPlayerName(PlayerId()),
            job       = '',
            group     = '',
            citizenid = tostring(userId),
        }
    end

    -- Standalone
    return {
        name      = GetPlayerName(PlayerId()),
        job       = '',
        group     = '',
        citizenid = '',
    }
end

-----------------------------------------------------------------------
-- Bridge.Notify — notificação no cliente
-- @param msg    string
-- @param tipo   string  'success'|'error'|'inform'|'warning'
-- @param duracao number  ms
-----------------------------------------------------------------------
function Bridge.Notify(msg, tipo, duracao)
    Bridge.ShowNotification(msg, tipo, duracao)
end

-----------------------------------------------------------------------
-- Bridge.IsPlayerLoggedIn — verifica se o jogador está logado
-- @return boolean
-----------------------------------------------------------------------
function Bridge.IsPlayerLoggedIn()
    if not IsCoreReady() then return false end

    if _fwName == 'esx' then
        if not _fw then return false end
        local pd = _fw.GetPlayerData()
        return pd ~= nil and pd.job ~= nil

    elseif _fwName == 'qbx' or _fwName == 'qb' then
        if not _fw then return false end
        local pd = _fw.Functions.GetPlayerData()
        return pd ~= nil

    elseif _fwName == 'vrp' then
        return vRP and vRP.getUserId and vRP.getUserId() ~= nil
    end

    return true  -- standalone: sempre logado
end

-----------------------------------------------------------------------
-- Evento: atualização de dados do jogador (ESX/QBX/QB)
-- Registrados incondicionalmente — só atuam se _fw estiver carregado
-----------------------------------------------------------------------

-- ESX: jogador carregado / job atualizado
AddEventHandler('esx:playerLoaded', function(pd)
    if _fw and _fwName == 'esx' then _fw.SetPlayerData(pd) end
end)
AddEventHandler('esx:setJob', function(job)
    if _fw and _fwName == 'esx' then
        local pd = _fw.GetPlayerData()
        if pd then pd.job = job end
    end
end)

-- QB/QBX: jogador carregado / job atualizado
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    -- dados já disponíveis via Bridge.GetPlayerData()
end)
AddEventHandler('QBCore:Client:OnJobUpdate', function(job)
    -- QB atualiza automaticamente via GetPlayerData()
end)
