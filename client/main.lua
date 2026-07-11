-----------------------------------------------------------------------
-- client/main.lua — MathStoreDemon-v3
-- Lógica principal do cliente: comandos, keybinds, HUD, voo, toggle
-----------------------------------------------------------------------

local resourceName = GetCurrentResourceName()

-- Estado local do jogador
local asaEquipada    = false   -- true se as asas estão equipadas
local caudaEquipada  = false   -- true se a cauda está equipada
local asaAberta      = false   -- true se as asas estão abertas
local emVoo          = false   -- true se o modo voo está ativo
local corAtual       = 1       -- cor atual das asas
local corCaudaAtual  = 1       -- cor atual da cauda

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

local function notify(msg, tipo)
    tipo = tipo or 'inform'
    if Config.UseOxLib and lib then
        lib.notify({ title = 'Demon', description = msg, type = tipo })
    else
        SetNotificationTextEntry('STRING')
        AddTextComponentString(msg)
        DrawNotification(false, true)
    end
end

local function isReady()
    return IsCoreReady() and NetworkIsSessionStarted()
end

-----------------------------------------------------------------------
-- Registro de comandos client-side
-- (Server registra também; aqui usamos para keybinds e atalhos locais)
-----------------------------------------------------------------------

-- Comando: equipar asas
RegisterCommand(Config.Commands.equip, function(source, args)
    if not isReady() then return end
    local cor = tonumber(args[1]) or corAtual
    TriggerServerEvent(resourceName .. ':equipWings', cor)
end, false)

-- Comando: remover asas
RegisterCommand(Config.Commands.remove, function()
    if not isReady() then return end
    TriggerServerEvent(resourceName .. ':removeWings')
end, false)

-- Comando: toggle (abrir/fechar asas)
RegisterCommand(Config.Commands.toggle, function()
    if not isReady() or not asaEquipada then return end
    TriggerEvent(resourceName .. ':toggleWings')
end, false)

-- Comando: ativar/desativar voo
RegisterCommand(Config.Commands.fly, function()
    if not isReady() then return end
    if not asaEquipada then
        notify(L('flight_equip_first', Config.Commands.equip), 'error')
        return
    end
    TriggerEvent(resourceName .. ':toggleFly')
end, false)

-- Comando: mudar cor das asas
RegisterCommand(Config.Commands.color, function(source, args)
    if not isReady() or not asaEquipada then return end
    local cor = tonumber(args[1])
    if not cor then return end
    TriggerServerEvent(resourceName .. ':changeWingColor', cor)
end, false)

-- Comando: limpeza local (asas bugadas próximas)
RegisterCommand(Config.Commands.cleanup2, function()
    if not isReady() then return end
    TriggerServerEvent(resourceName .. ':localCleanup')
end, false)

-- Comando: limpeza admin (todas as asas do mundo)
RegisterCommand(Config.Commands.cleanup, function()
    if not isReady() then return end
    TriggerServerEvent(resourceName .. ':adminCleanup')
end, false)

-- Comando: abrir asas (animação no chão)
RegisterCommand(Config.Commands.abrir, function()
    if not isReady() or not asaEquipada then return end
    TriggerEvent(resourceName .. ':animAbrir')
end, false)

-- Comando: fechar asas (animação no chão)
RegisterCommand(Config.Commands.fechar, function()
    if not isReady() or not asaEquipada then return end
    TriggerEvent(resourceName .. ':animFechar')
end, false)

-- Comando: bater asas (animação no chão)
RegisterCommand(Config.Commands.bater, function()
    if not isReady() or not asaEquipada then return end
    TriggerEvent(resourceName .. ':animBater')
end, false)

-- Comandos de cauda
RegisterCommand(Config.TailCommands.equip, function(source, args)
    if not isReady() then return end
    local cor = tonumber(args[1]) or corCaudaAtual
    TriggerServerEvent(resourceName .. ':equipTail', cor)
end, false)

RegisterCommand(Config.TailCommands.remove, function()
    if not isReady() then return end
    TriggerServerEvent(resourceName .. ':removeTail')
end, false)

RegisterCommand(Config.TailCommands.color, function(source, args)
    if not isReady() or not caudaEquipada then return end
    local cor = tonumber(args[1])
    if not cor then return end
    TriggerServerEvent(resourceName .. ':changeTailColor', cor)
end, false)

RegisterCommand(Config.TailCommands.bater, function()
    if not isReady() or not caudaEquipada then return end
    TriggerEvent(resourceName .. ':animCaudaBater')
end, false)

RegisterCommand(Config.TailCommands.enrolar, function()
    if not isReady() or not caudaEquipada then return end
    TriggerEvent(resourceName .. ':animCaudaEnrolar')
end, false)

RegisterCommand(Config.TailCommands.reta, function()
    if not isReady() or not caudaEquipada then return end
    TriggerEvent(resourceName .. ':animCaudaReta')
end, false)

-- Comando: abrir HUD
RegisterCommand(Config.HudCommand, function()
    if not isReady() then return end
    TriggerServerEvent(resourceName .. ':openHUD')
end, false)

-----------------------------------------------------------------------
-- Keybinds
-----------------------------------------------------------------------

if Config.Keybinds.toggle and Config.Keybinds.toggle ~= '' then
    RegisterKeyMapping(
        Config.Commands.toggle,
        L('keybind_toggle'),
        'keyboard',
        Config.Keybinds.toggle
    )
end

if Config.Keybinds.fly and Config.Keybinds.fly ~= '' and Config.Keybinds.fly ~= false then
    RegisterKeyMapping(
        Config.Commands.fly,
        L('keybind_fly'),
        'keyboard',
        Config.Keybinds.fly
    )
end

if Config.Keybinds.hud and Config.Keybinds.hud ~= '' and Config.Keybinds.hud ~= false then
    RegisterKeyMapping(
        Config.HudCommand,
        L('keybind_hud'),
        'keyboard',
        Config.Keybinds.hud
    )
end

-----------------------------------------------------------------------
-- Eventos recebidos do servidor
-----------------------------------------------------------------------

-- Servidor autoriza: spawnar asas
RegisterNetEvent(resourceName .. ':spawnWings', function(cor)
    corAtual     = cor or 1
    asaEquipada  = true
    asaAberta    = false
    SpawnWings(cor)  -- definido em bones.lua
    notify(L('wings_equipped', cor), 'success')
end)

-- Servidor manda remover asas
RegisterNetEvent(resourceName .. ':despawnWings', function()
    asaEquipada = false
    asaAberta   = false
    emVoo       = false
    RemoveWings()  -- definido em bones.lua
    notify(L('wings_removed'), 'inform')
end)

-- Servidor atualiza cor das asas
RegisterNetEvent(resourceName .. ':updateWingColor', function(cor)
    corAtual = cor
    UpdateWingColor(cor)  -- definido em bones.lua
    notify(L('color_changed', cor), 'success')
end)

-- Servidor autoriza: spawnar cauda
RegisterNetEvent(resourceName .. ':spawnTail', function(cor)
    corCaudaAtual = cor or 1
    caudaEquipada = true
    SpawnTail(cor)  -- definido em bones.lua
    notify(L('tail_equipped', cor), 'success')
end)

-- Servidor manda remover cauda
RegisterNetEvent(resourceName .. ':despawnTail', function()
    caudaEquipada = false
    RemoveTail()  -- definido em bones.lua
    notify(L('tail_removed'), 'inform')
end)

-- Servidor atualiza cor da cauda
RegisterNetEvent(resourceName .. ':updateTailColor', function(cor)
    corCaudaAtual = cor
    UpdateTailColor(cor)  -- definido em bones.lua
    notify(L('tail_color_changed', cor), 'success')
end)

-- Servidor manda abrir HUD com dados de estado
RegisterNetEvent(resourceName .. ':openHUDClient', function(dados)
    SendNUIMessage({
        action       = 'openHUD',
        canUse       = dados.canUse,
        hasWings     = dados.hasWings,
        hasTail      = dados.hasTail,
        wingColor    = dados.wingColor,
        tailColor    = dados.tailColor,
        maxColors    = dados.maxColors,
        maxTailColors = dados.maxTailColors,
    })
    SetNuiFocus(true, true)
end)

-- Limpeza local (objetos bugados próximos)
RegisterNetEvent(resourceName .. ':doLocalCleanup', function()
    CleanupNearbyProps()  -- definido em bones.lua
end)

-- Notificação genérica vinda do servidor
RegisterNetEvent(resourceName .. ':notify', function(msg, tipo)
    notify(msg, tipo)
end)

-- Notificação via bridge
RegisterNetEvent(resourceName .. ':bridgeNotify', function(msg, tipo, duracao)
    notify(msg, tipo)
end)

-----------------------------------------------------------------------
-- Eventos locais de toggle/animações
-----------------------------------------------------------------------

AddEventHandler(resourceName .. ':toggleWings', function()
    if not asaEquipada then return end
    if asaAberta then
        asaAberta = false
        PlayWingAnimation('close')  -- definido em bones.lua
    else
        asaAberta = true
        PlayWingAnimation('open')
    end
end)

AddEventHandler(resourceName .. ':toggleFly', function()
    if not asaEquipada then return end
    emVoo = not emVoo
    SetFlyMode(emVoo)  -- definido em bones.lua
end)

AddEventHandler(resourceName .. ':animAbrir', function()
    if not asaEquipada then return end
    asaAberta = true
    PlayWingAnimation('open')
end)

AddEventHandler(resourceName .. ':animFechar', function()
    if not asaEquipada then return end
    asaAberta = false
    PlayWingAnimation('close')
end)

AddEventHandler(resourceName .. ':animBater', function()
    if not asaEquipada then return end
    PlayWingAnimation('flap')
end)

AddEventHandler(resourceName .. ':animCaudaBater', function()
    if not caudaEquipada then return end
    PlayTailAnimation('flap')  -- definido em bones.lua
end)

AddEventHandler(resourceName .. ':animCaudaEnrolar', function()
    if not caudaEquipada then return end
    PlayTailAnimation('wrap')
end)

AddEventHandler(resourceName .. ':animCaudaReta', function()
    if not caudaEquipada then return end
    PlayTailAnimation('straight')
end)

-----------------------------------------------------------------------
-- NUI callbacks (HTML → Lua)
-----------------------------------------------------------------------

RegisterNUICallback('closeHUD', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('equipWings', function(data, cb)
    local cor = tonumber(data.cor) or 1
    TriggerServerEvent(resourceName .. ':equipWings', cor)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('removeWings', function(data, cb)
    TriggerServerEvent(resourceName .. ':removeWings')
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('toggleWings', function(data, cb)
    TriggerEvent(resourceName .. ':toggleWings')
    cb('ok')
end)

RegisterNUICallback('toggleFly', function(data, cb)
    TriggerEvent(resourceName .. ':toggleFly')
    cb('ok')
end)

RegisterNUICallback('equipTail', function(data, cb)
    local cor = tonumber(data.cor) or 1
    TriggerServerEvent(resourceName .. ':equipTail', cor)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('removeTail', function(data, cb)
    TriggerServerEvent(resourceName .. ':removeTail')
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('changeWingColor', function(data, cb)
    local cor = tonumber(data.cor) or 1
    TriggerServerEvent(resourceName .. ':changeWingColor', cor)
    cb('ok')
end)

RegisterNUICallback('changeTailColor', function(data, cb)
    local cor = tonumber(data.cor) or 1
    TriggerServerEvent(resourceName .. ':changeTailColor', cor)
    cb('ok')
end)

-----------------------------------------------------------------------
-- Limpeza ao parar o resource
-----------------------------------------------------------------------

AddEventHandler('onResourceStop', function(res)
    if res ~= resourceName then return end
    if asaEquipada  then RemoveWings() end
    if caudaEquipada then RemoveTail() end
    SetNuiFocus(false, false)
    emVoo       = false
    asaEquipada  = false
    caudaEquipada = false
    asaAberta    = false
end)

print('^3[' .. resourceName .. '] client/main.lua carregado.^0')
