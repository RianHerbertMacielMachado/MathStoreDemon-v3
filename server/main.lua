-----------------------------------------------------------------------
-- server/main.lua — MathStoreDemon-v3
-- Lógica principal do servidor: comandos, callbacks, eventos
-----------------------------------------------------------------------

local resourceName = GetCurrentResourceName()

-- Tabelas de estado por jogador
-- playerWings[source]  = { cor = number }
-- playerTails[source]  = { cor = number }
local playerWings = {}
local playerTails = {}

-- Cooldowns ativos: cooldowns[source][feature] = os.time() + segundos
local cooldowns = {}

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

local function hasPermission(source, feature)
    -- Delega para a bridge de servidor
    if Bridge and Bridge.HasPermission then
        return Bridge.HasPermission(source, feature)
    end
    return true
end

local function checkCooldown(source, feature)
    local cd = Config.Cooldowns and Config.Cooldowns[feature]
    if not cd or cd <= 0 then return true end
    cooldowns[source] = cooldowns[source] or {}
    local expire = cooldowns[source][feature]
    if expire and os.time() < expire then
        local remaining = expire - os.time()
        TriggerClientEvent(resourceName .. ':notify', source, L('cooldown_wait', remaining), 'error')
        return false
    end
    cooldowns[source][feature] = os.time() + cd
    return true
end

-----------------------------------------------------------------------
-- Callback: verificar se pode equipar asas (HUD + comando)
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':canEquipWings', function(cor)
    local source = source
    local allowed = true

    -- Callback customizável
    if Config.Callbacks and Config.Callbacks.CanEquipWings then
        local result = Config.Callbacks.CanEquipWings(source, cor)
        if result == false then
            allowed = false
        end
    end

    TriggerClientEvent(resourceName .. ':canEquipWingsResult', source, allowed)
end)

-----------------------------------------------------------------------
-- Evento: equipar asas
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':equipWings', function(cor)
    local source = source

    if not hasPermission(source, 'use') then
        TriggerClientEvent(resourceName .. ':notify', source, L('no_permission'), 'error')
        return
    end

    -- Callback CanEquipWings
    if Config.Callbacks and Config.Callbacks.CanEquipWings then
        if Config.Callbacks.CanEquipWings(source, cor) == false then
            TriggerClientEvent(resourceName .. ':notify', source, L('wings_locked'), 'error')
            return
        end
    end

    if not checkCooldown(source, 'equip') then return end

    -- Valida cor
    local maxColors = Config.MaxColors or 3
    cor = tonumber(cor) or 1
    if cor < 1 or cor > maxColors then
        TriggerClientEvent(resourceName .. ':notify', source, L('invalid_color', maxColors), 'error')
        return
    end

    playerWings[source] = { cor = cor }

    -- Notifica todos os clientes para spawnar as asas no jogador
    TriggerClientEvent(resourceName .. ':spawnWings', source, cor)

    -- Callback pós-equip
    if Config.Callbacks and Config.Callbacks.OnWingsEquipped then
        Config.Callbacks.OnWingsEquipped(source, cor)
    end
end)

-----------------------------------------------------------------------
-- Evento: remover asas
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':removeWings', function()
    local source = source

    if not playerWings[source] then return end

    playerWings[source] = nil
    TriggerClientEvent(resourceName .. ':despawnWings', source)

    if Config.Callbacks and Config.Callbacks.OnWingsRemoved then
        Config.Callbacks.OnWingsRemoved(source)
    end
end)

-----------------------------------------------------------------------
-- Evento: mudar cor das asas
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':changeWingColor', function(cor)
    local source = source

    if not playerWings[source] then return end
    if not hasPermission(source, 'use') then
        TriggerClientEvent(resourceName .. ':notify', source, L('no_permission'), 'error')
        return
    end

    local maxColors = Config.MaxColors or 3
    cor = tonumber(cor) or 1
    if cor < 1 or cor > maxColors then
        TriggerClientEvent(resourceName .. ':notify', source, L('invalid_color', maxColors), 'error')
        return
    end

    playerWings[source].cor = cor
    TriggerClientEvent(resourceName .. ':updateWingColor', source, cor)
end)

-----------------------------------------------------------------------
-- Evento: equipar cauda
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':equipTail', function(cor)
    local source = source

    if not hasPermission(source, 'use') then
        TriggerClientEvent(resourceName .. ':notify', source, L('no_permission'), 'error')
        return
    end

    local maxColors = Config.MaxTailColors or Config.MaxColors or 3
    cor = tonumber(cor) or 1
    if cor < 1 or cor > maxColors then
        TriggerClientEvent(resourceName .. ':notify', source, L('tail_invalid_color', maxColors), 'error')
        return
    end

    playerTails[source] = { cor = cor }
    TriggerClientEvent(resourceName .. ':spawnTail', source, cor)
end)

-----------------------------------------------------------------------
-- Evento: remover cauda
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':removeTail', function()
    local source = source
    if not playerTails[source] then return end
    playerTails[source] = nil
    TriggerClientEvent(resourceName .. ':despawnTail', source)
end)

-----------------------------------------------------------------------
-- Evento: mudar cor da cauda
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':changeTailColor', function(cor)
    local source = source

    if not playerTails[source] then return end
    if not hasPermission(source, 'use') then
        TriggerClientEvent(resourceName .. ':notify', source, L('no_permission'), 'error')
        return
    end

    local maxColors = Config.MaxTailColors or Config.MaxColors or 3
    cor = tonumber(cor) or 1
    if cor < 1 or cor > maxColors then
        TriggerClientEvent(resourceName .. ':notify', source, L('tail_invalid_color', maxColors), 'error')
        return
    end

    playerTails[source].cor = cor
    TriggerClientEvent(resourceName .. ':updateTailColor', source, cor)
end)

-----------------------------------------------------------------------
-- Evento: limpeza admin (remove TODAS as asas do mundo)
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':adminCleanup', function()
    local source = source

    if not hasPermission(source, 'admin_cleanup') then
        TriggerClientEvent(resourceName .. ':notify', source, L('no_permission'), 'error')
        return
    end

    local count = 0
    for src, _ in pairs(playerWings) do
        playerWings[src] = nil
        TriggerClientEvent(resourceName .. ':despawnWings', src)
        count = count + 1
    end
    for src, _ in pairs(playerTails) do
        playerTails[src] = nil
        TriggerClientEvent(resourceName .. ':despawnTail', src)
    end

    TriggerClientEvent(resourceName .. ':notify', source, L('massive_cleanup', count), 'success')
end)

-----------------------------------------------------------------------
-- Evento: limpeza local (remove asas/cauda bugadas próximas)
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':localCleanup', function()
    local source = source
    TriggerClientEvent(resourceName .. ':doLocalCleanup', source)
end)

-----------------------------------------------------------------------
-- Evento: abrir HUD
-----------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':openHUD', function()
    local source = source

    if Config.Callbacks and Config.Callbacks.CanOpenHUD then
        if Config.Callbacks.CanOpenHUD(source) == false then
            return
        end
    end

    -- Verifica permissão para saber o estado dos botões
    local canUse = hasPermission(source, 'use')
    local hasWings = playerWings[source] ~= nil
    local hasTail  = playerTails[source] ~= nil
    local currentWingColor = hasWings and playerWings[source].cor or 1
    local currentTailColor = hasTail  and playerTails[source].cor  or 1

    TriggerClientEvent(resourceName .. ':openHUDClient', source, {
        canUse          = canUse,
        hasWings        = hasWings,
        hasTail         = hasTail,
        wingColor       = currentWingColor,
        tailColor       = currentTailColor,
        maxColors       = Config.MaxColors or 3,
        maxTailColors   = Config.MaxTailColors or Config.MaxColors or 3,
    })
end)

-----------------------------------------------------------------------
-- Limpeza ao desconectar
-----------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local source = source
    playerWings[source] = nil
    playerTails[source] = nil
    if cooldowns[source] then cooldowns[source] = nil end
end)

-----------------------------------------------------------------------
-- Registra comandos via ox_lib ou RegisterCommand
-----------------------------------------------------------------------
local function registerCmd(name, handler, restricted)
    if Config.UseOxLib and lib and lib.addCommand then
        lib.addCommand(name, { restricted = restricted }, handler)
    else
        RegisterCommand(name, handler, restricted or false)
    end
end

-- Comando: equipar asas
registerCmd(Config.Commands.equip, function(source, args)
    local cor = tonumber(args[1]) or 1
    TriggerEvent(resourceName .. ':equipWings', cor)
    -- Redireciona para o evento de rede para reaproveitar a lógica
    TriggerNetEvent(resourceName .. ':equipWings', cor)
end, false)

-- Comando: remover asas
registerCmd(Config.Commands.remove, function(source)
    TriggerNetEvent(resourceName .. ':removeWings')
end, false)

-- Comando: equipar cauda
registerCmd(Config.TailCommands.equip, function(source, args)
    local cor = tonumber(args[1]) or 1
    TriggerNetEvent(resourceName .. ':equipTail', cor)
end, false)

-- Comando: remover cauda
registerCmd(Config.TailCommands.remove, function(source)
    TriggerNetEvent(resourceName .. ':removeTail')
end, false)

-- Comando: limpeza admin
registerCmd(Config.Commands.cleanup, function(source)
    TriggerNetEvent(resourceName .. ':adminCleanup')
end, false)

-- Comando: limpeza local
registerCmd(Config.Commands.cleanup2, function(source)
    TriggerNetEvent(resourceName .. ':localCleanup')
end, false)

-- Comando: abrir HUD
registerCmd(Config.HudCommand, function(source)
    TriggerNetEvent(resourceName .. ':openHUD')
end, false)

print('^3[' .. resourceName .. '] server/main.lua carregado.^0')
