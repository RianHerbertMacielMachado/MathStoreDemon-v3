-----------------------------------------------------------------------
-- bridge/server.lua — MathStoreDemon-v3
-- Bridge de servidor: detecta framework e abstrai permissões/notificações
-- Suporta: QBX, QB-Core, ESX, vRP, Standalone
-----------------------------------------------------------------------

Bridge = Bridge or {}

local resourceName = GetCurrentResourceName()

-----------------------------------------------------------------------
-- Detecção de framework
-----------------------------------------------------------------------
local framework = Config and Config.Framework or 'auto'
local Framework = nil  -- instância do framework detectado

local function detectFramework()
    if framework ~= 'auto' then
        return framework
    end

    if GetResourceState('qbx_core') == 'started' then
        return 'qbx'
    elseif GetResourceState('qb-core') == 'started' then
        return 'qb'
    elseif GetResourceState('es_extended') == 'started' then
        return 'esx'
    elseif GetResourceState('vrp') == 'started' then
        return 'vrp'
    end

    return 'standalone'
end

local detectedFramework = detectFramework()

-- Carrega instância do framework
CreateThread(function()
    Wait(100)
    if detectedFramework == 'qbx' then
        Framework = exports['qbx_core']:GetCoreObject()
    elseif detectedFramework == 'qb' then
        Framework = exports['qb-core']:GetCoreObject()
    elseif detectedFramework == 'esx' then
        Framework = exports['es_extended']:getSharedObject()
    end
    -- vRP usa vRP global; standalone não precisa de instância
    print('^2[' .. resourceName .. '] Bridge servidor — framework detectado: ' .. detectedFramework .. '^0')
end)

-----------------------------------------------------------------------
-- Helpers internos
-----------------------------------------------------------------------

local function getPlayerIdentifier(source)
    -- Retorna o identifier principal do jogador (licença)
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if id and id:sub(1, 8) == 'license:' then
            return id
        end
    end
    -- fallback: steam ou discord
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if id then return id end
    end
    return tostring(source)
end

-----------------------------------------------------------------------
-- Verificação de permissão
-----------------------------------------------------------------------

-- Verifica ACE nativo do FiveM
local function checkAce(source, perm)
    if not perm or perm == '' then return false end
    return IsPlayerAceAllowed(source, perm) == true
end

-- Verifica grupos (QBX/QB/ESX)
local function checkGroups(source, groups)
    if not groups or #groups == 0 then return false end
    if detectedFramework == 'qbx' or detectedFramework == 'qb' then
        if Framework then
            local player = Framework.Functions.GetPlayer(source)
            if player then
                local group = player.PlayerData.group or player.PlayerData.permission or ''
                for _, g in ipairs(groups) do
                    -- Suporte a 'group.admin' (ACE) e 'admin' direto
                    local gName = g:gsub('group%.', '')
                    if group == gName or checkAce(source, g) then
                        return true
                    end
                end
            end
        end
    elseif detectedFramework == 'esx' then
        if Framework then
            local player = Framework.GetPlayerFromId(source)
            if player then
                local group = player.getGroup()
                for _, g in ipairs(groups) do
                    local gName = g:gsub('group%.', '')
                    if group == gName or checkAce(source, g) then
                        return true
                    end
                end
            end
        end
    end
    -- Fallback: ACE nativo
    for _, g in ipairs(groups) do
        if checkAce(source, g) then return true end
    end
    return false
end

-- Verifica jobs (QBX/QB/ESX)
local function checkJobs(source, jobs)
    if not jobs or #jobs == 0 then return false end
    if detectedFramework == 'qbx' or detectedFramework == 'qb' then
        if Framework then
            local player = Framework.Functions.GetPlayer(source)
            if player then
                local job = player.PlayerData.job and player.PlayerData.job.name or ''
                for _, j in ipairs(jobs) do
                    if job == j then return true end
                end
            end
        end
    elseif detectedFramework == 'esx' then
        if Framework then
            local player = Framework.GetPlayerFromId(source)
            if player then
                local job = player.getJob().name
                for _, j in ipairs(jobs) do
                    if job == j then return true end
                end
            end
        end
    end
    return false
end

-- Verifica vRP permissões
local function checkVRP(source, vrpPerms)
    if not vrpPerms or #vrpPerms == 0 then return false end
    if detectedFramework ~= 'vrp' then return false end
    local vRP = vRP
    if not vRP then return false end
    local userId = vRP.getUserId and vRP.getUserId({source}) or nil
    if not userId then return false end
    for _, perm in ipairs(vrpPerms) do
        if vRP.hasPermission and vRP.hasPermission({userId, perm}) then
            return true
        end
    end
    return false
end

-- Verifica vRP grupos
local function checkVRPGroups(source, groups)
    if not groups or #groups == 0 then return false end
    if detectedFramework ~= 'vrp' then return false end
    local vRP = vRP
    if not vRP then return false end
    local userId = vRP.getUserId and vRP.getUserId({source}) or nil
    if not userId then return false end
    for _, g in ipairs(groups) do
        if vRP.hasGroup and vRP.hasGroup({userId, g}) then
            return true
        end
    end
    return false
end

-- Verifica citizenids específicos
local function checkCitizenIds(source, citizenids)
    if not citizenids or #citizenids == 0 then return false end
    local identifier = getPlayerIdentifier(source)
    if detectedFramework == 'qbx' or detectedFramework == 'qb' then
        if Framework then
            local player = Framework.Functions.GetPlayer(source)
            if player then
                local cid = player.PlayerData.citizenid or ''
                for _, id in ipairs(citizenids) do
                    if cid == id or identifier == id then return true end
                end
            end
        end
    elseif detectedFramework == 'esx' then
        if Framework then
            local player = Framework.GetPlayerFromId(source)
            if player then
                local id = player.getIdentifier()
                for _, cid in ipairs(citizenids) do
                    if id == cid or identifier == cid then return true end
                end
            end
        end
    elseif detectedFramework == 'vrp' then
        local vRP = vRP
        if vRP then
            local userId = vRP.getUserId and vRP.getUserId({source}) or nil
            if userId then
                for _, id in ipairs(citizenids) do
                    if tostring(userId) == tostring(id) then return true end
                end
            end
        end
    end
    -- Fallback por identifier
    for _, id in ipairs(citizenids) do
        if identifier == id then return true end
    end
    return false
end

-----------------------------------------------------------------------
-- Bridge.HasPermission — ponto principal de verificação
-----------------------------------------------------------------------
function Bridge.HasPermission(source, feature)
    -- Callback customizável tem prioridade
    if Config.Callbacks and Config.Callbacks.HasPermission then
        local result = Config.Callbacks.HasPermission(source, feature)
        if result ~= nil then return result end
    end

    local feat = Permissions and Permissions.Features and Permissions.Features[feature]
    if not feat then return true end
    if feat.enabled == false then return true end

    -- ACE nativo
    local aceKey = Permissions.Ace and Permissions.Ace[feature]
    if aceKey and checkAce(source, aceKey) then return true end

    -- vRP dedicado
    if detectedFramework == 'vrp' then
        local vrpGroups = Permissions.VRP and Permissions.VRP[feature]
        if checkVRPGroups(source, vrpGroups) then return true end
        if checkVRP(source, feat.vrpPermissions) then return true end
    end

    -- Grupos framework
    if checkGroups(source, feat.groups) then return true end

    -- Jobs
    if checkJobs(source, feat.jobs) then return true end

    -- CitizenIDs específicos
    if checkCitizenIds(source, feat.citizenids) then return true end

    return false
end

-----------------------------------------------------------------------
-- Bridge.Notify — envia notificação ao cliente
-----------------------------------------------------------------------
function Bridge.Notify(source, message, notifType, duration)
    notifType = notifType or 'info'
    duration  = duration or (Config.Notifications and Config.Notifications.duration) or 5000
    TriggerClientEvent(resourceName .. ':bridgeNotify', source, message, notifType, duration)
end

-----------------------------------------------------------------------
-- Bridge.GetPlayerName
-----------------------------------------------------------------------
function Bridge.GetPlayerName(source)
    return GetPlayerName(source) or 'Unknown'
end

-----------------------------------------------------------------------
-- Bridge.GetIdentifier
-----------------------------------------------------------------------
function Bridge.GetIdentifier(source)
    return getPlayerIdentifier(source)
end

print('^3[' .. resourceName .. '] bridge/server.lua carregado (framework: ' .. detectedFramework .. ').^0')
