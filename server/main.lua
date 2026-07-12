-----------------------------------------------------------------------
-- server/main.lua — MathStoreDemon-v3
--
-- Responsabilidades:
--   • Registrar todos os comandos de ASA e CAUDA
--   • Tratar callbacks NUI vindos do client (hudAction, closeHud, etc.)
--   • Validar permissão + cooldown antes de qualquer operação
--   • Disparar eventos de cliente para spawn/remoção de props/anim
--   • Executar callbacks de config (CanEquipWings, OnWingsEquipped, etc.)
--   • Cleanup admin global e local
--
-- Fluxo resumido:
--   1. Jogador abre o HUD (client dispara evento openHud → server responde)
--   2. NUI envia hudAction → server/main recebe, valida e reenvia ao client
--   3. Comandos de chat funcionam como atalhos diretos (sem HUD)
-----------------------------------------------------------------------

local resourceName = GetCurrentResourceName()

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

--- Quantidade total de cores de asa configuradas
local WING_MAX_COLORS = 42   -- igual ao número de .ydr no stream/
local TAIL_MAX_COLORS = 42

--- Valida range de cor
local function validWingColor(cor)
    return type(cor) == 'number' and cor >= 1 and cor <= WING_MAX_COLORS
end

local function validTailColor(cor)
    return type(cor) == 'number' and cor >= 1 and cor <= TAIL_MAX_COLORS
end

--- Notifica jogador e retorna false (para early-return limpo)
local function deny(source, msgKey, ...)
    Bridge.Notify(source, L(msgKey, ...), 'error')
    return false
end

-----------------------------------------------------------------------
-- Verificação de permissão com callback opcional de config
-----------------------------------------------------------------------
local function canUse(source)
    if Config.Callbacks and Config.Callbacks.CanEquipWings then
        local res = Config.Callbacks.CanEquipWings(source, nil)
        if res == false then return false end
    end
    return Bridge.HasPermission(source, 'use')
end

local function canAdmin(source)
    return Bridge.HasPermission(source, 'admin_cleanup')
end

-----------------------------------------------------------------------
-- Equipar ASA
-----------------------------------------------------------------------
local function equipWing(source, cor)
    if not canUse(source) then
        return deny(source, 'no_permission')
    end

    -- Cooldown
    local onCD, remaining = IsOnCooldown(source, 'equip')
    if onCD then
        return deny(source, 'cooldown_wait', math.ceil(remaining))
    end

    -- Callback CanEquipWings com cor
    if Config.Callbacks and Config.Callbacks.CanEquipWings then
        local res = Config.Callbacks.CanEquipWings(source, cor)
        if res == false then
            return deny(source, 'wings_locked')
        end
    end

    cor = math.floor(tonumber(cor) or 1)
    if not validWingColor(cor) then
        return deny(source, 'invalid_color', WING_MAX_COLORS)
    end

    -- Remove asa anterior se existia
    if PlayerWings[source] then
        TriggerClientEvent(resourceName .. ':removeWing', source)
    end

    PlayerWings[source] = { cor = cor }

    -- Dispara spawn no cliente
    TriggerClientEvent(resourceName .. ':spawnWing', source, cor)

    SetCooldown(source, 'equip')
    Bridge.Notify(source, L('wings_equipped', cor), 'success')

    if Config.Callbacks and Config.Callbacks.OnWingsEquipped then
        Config.Callbacks.OnWingsEquipped(source, cor)
    end

    return true
end

-----------------------------------------------------------------------
-- Remover ASA
-----------------------------------------------------------------------
local function removeWing(source)
    if not PlayerWings[source] then return end

    PlayerWings[source] = nil
    TriggerClientEvent(resourceName .. ':removeWing', source)
    Bridge.Notify(source, L('wings_removed'), 'info')

    if Config.Callbacks and Config.Callbacks.OnWingsRemoved then
        Config.Callbacks.OnWingsRemoved(source)
    end
end

-----------------------------------------------------------------------
-- Equipar CAUDA
-----------------------------------------------------------------------
local function equipTail(source, cor)
    if not canUse(source) then
        return deny(source, 'no_permission')
    end

    local onCD, remaining = IsOnCooldown(source, 'equip_tail')
    if onCD then
        return deny(source, 'cooldown_wait', math.ceil(remaining))
    end

    cor = math.floor(tonumber(cor) or 1)
    if not validTailColor(cor) then
        return deny(source, 'tail_invalid_color', TAIL_MAX_COLORS)
    end

    if PlayerTails[source] then
        TriggerClientEvent(resourceName .. ':removeTail', source)
    end

    PlayerTails[source] = { cor = cor }
    TriggerClientEvent(resourceName .. ':spawnTail', source, cor)

    SetCooldown(source, 'equip_tail')
    Bridge.Notify(source, L('tail_equipped', cor), 'success')

    return true
end

-----------------------------------------------------------------------
-- Remover CAUDA
-----------------------------------------------------------------------
local function removeTail(source)
    if not PlayerTails[source] then return end

    PlayerTails[source] = nil
    TriggerClientEvent(resourceName .. ':removeTail', source)
    Bridge.Notify(source, L('tail_removed'), 'info')
end

-----------------------------------------------------------------------
-- Trocar cor da ASA
-----------------------------------------------------------------------
local function changeWingColor(source, cor)
    if not PlayerWings[source] then
        return deny(source, 'flight_equip_first', Config.Commands.equip)
    end

    cor = math.floor(tonumber(cor) or 1)
    if not validWingColor(cor) then
        return deny(source, 'invalid_color', WING_MAX_COLORS)
    end

    PlayerWings[source].cor = cor
    TriggerClientEvent(resourceName .. ':spawnWing', source, cor)
    Bridge.Notify(source, L('color_changed', cor), 'info')
end

-----------------------------------------------------------------------
-- Trocar cor da CAUDA
-----------------------------------------------------------------------
local function changeTailColor(source, cor)
    if not PlayerTails[source] then return end

    cor = math.floor(tonumber(cor) or 1)
    if not validTailColor(cor) then
        return deny(source, 'tail_invalid_color', TAIL_MAX_COLORS)
    end

    PlayerTails[source].cor = cor
    TriggerClientEvent(resourceName .. ':spawnTail', source, cor)
    Bridge.Notify(source, L('tail_color_changed', cor), 'info')
end

-----------------------------------------------------------------------
-- TOGGLE ASA (abrir / fechar em solo)
-----------------------------------------------------------------------
local function toggleWing(source)
    if not PlayerWings[source] then
        return deny(source, 'flight_equip_first', Config.Commands.equip)
    end
    TriggerClientEvent(resourceName .. ':toggleWing', source)
end

-----------------------------------------------------------------------
-- ABRIR asa (animação solo)
-----------------------------------------------------------------------
local function abrirWing(source)
    if not PlayerWings[source] then
        return deny(source, 'flight_equip_first', Config.Commands.equip)
    end
    TriggerClientEvent(resourceName .. ':abrirWing', source)
end

-----------------------------------------------------------------------
-- FECHAR asa (animação solo)
-----------------------------------------------------------------------
local function fecharWing(source)
    if not PlayerWings[source] then
        return deny(source, 'flight_equip_first', Config.Commands.equip)
    end
    TriggerClientEvent(resourceName .. ':fecharWing', source)
end

-----------------------------------------------------------------------
-- BATER asas (animação solo)
-----------------------------------------------------------------------
local function baterWing(source)
    if not PlayerWings[source] then
        return deny(source, 'flight_equip_first', Config.Commands.equip)
    end
    TriggerClientEvent(resourceName .. ':baterWing', source)
end

-----------------------------------------------------------------------
-- VOO (toggle flight mode)
-----------------------------------------------------------------------
local function toggleFly(source)
    if not PlayerWings[source] then
        return deny(source, 'flight_equip_first', Config.Commands.equip)
    end
    TriggerClientEvent(resourceName .. ':toggleFly', source)
end

-----------------------------------------------------------------------
-- ANIMAÇÕES de CAUDA
-----------------------------------------------------------------------
local function caudaBater(source)
    if not PlayerTails[source] then return end
    TriggerClientEvent(resourceName .. ':caudaBater', source)
end

local function caudaEnrolar(source)
    if not PlayerTails[source] then return end
    TriggerClientEvent(resourceName .. ':caudaEnrolar', source)
end

local function caudaReta(source)
    if not PlayerTails[source] then return end
    TriggerClientEvent(resourceName .. ':caudaReta', source)
end

-----------------------------------------------------------------------
-- CLEANUP GLOBAL (admin) — remove asas de TODOS os jogadores
-----------------------------------------------------------------------
local function adminCleanup(source)
    if not canAdmin(source) then
        return deny(source, 'no_permission')
    end

    local count = 0
    for _, player in ipairs(GetPlayers()) do
        local pid = tonumber(player)
        if PlayerWings[pid] then
            PlayerWings[pid] = nil
            TriggerClientEvent(resourceName .. ':removeWing', pid)
            count = count + 1
        end
        if PlayerTails[pid] then
            PlayerTails[pid] = nil
            TriggerClientEvent(resourceName .. ':removeTail', pid)
            count = count + 1
        end
    end

    Bridge.Notify(source, L('massive_cleanup', count), 'info')
end

-----------------------------------------------------------------------
-- CLEANUP LOCAL — remove props bugados perto do jogador
-- (o client detecta e dispara evento de confirmação)
-----------------------------------------------------------------------
local function localCleanup(source)
    TriggerClientEvent(resourceName .. ':localCleanup', source)
end

-----------------------------------------------------------------------
-- Registrar COMANDOS
-----------------------------------------------------------------------
local cmds = Config.Commands
local tcmds = Config.TailCommands

-- /asasdm [cor]  — equipar asa
RegisterCommand(cmds.equip, function(source, args)
    local cor = tonumber(args[1]) or 1
    equipWing(source, cor)
end, false)

-- /removerdm  — remover asa
RegisterCommand(cmds.remove, function(source)
    removeWing(source)
end, false)

-- /asasdmtg  — toggle (abrir/fechar asa)
RegisterCommand(cmds.toggle, function(source)
    toggleWing(source)
end, false)

-- /asasvoardm  — toggle flight
RegisterCommand(cmds.fly, function(source)
    toggleFly(source)
end, false)

-- /asascordm [cor]  — mudar cor
RegisterCommand(cmds.color, function(source, args)
    local cor = tonumber(args[1]) or 1
    changeWingColor(source, cor)
end, false)

-- /asaslimpardm  — admin cleanup global
RegisterCommand(cmds.cleanup, function(source)
    adminCleanup(source)
end, false)

-- /asaslimpar2dm  — cleanup local (props bugados)
RegisterCommand(cmds.cleanup2, function(source)
    localCleanup(source)
end, false)

-- /abrirdm  — abrir asa (animação)
RegisterCommand(cmds.abrir, function(source)
    abrirWing(source)
end, false)

-- /fechardm  — fechar asa (animação)
RegisterCommand(cmds.fechar, function(source)
    fecharWing(source)
end, false)

-- /baterdm  — bater asa (animação)
RegisterCommand(cmds.bater, function(source)
    baterWing(source)
end, false)

-- /caudadm [cor]  — equipar cauda
RegisterCommand(tcmds.equip, function(source, args)
    local cor = tonumber(args[1]) or 1
    equipTail(source, cor)
end, false)

-- /removercd  — remover cauda
RegisterCommand(tcmds.remove, function(source)
    removeTail(source)
end, false)

-- /caudacordm [cor]  — mudar cor da cauda
RegisterCommand(tcmds.color, function(source, args)
    local cor = tonumber(args[1]) or 1
    changeTailColor(source, cor)
end, false)

-- /caudabt  — bater cauda
RegisterCommand(tcmds.bater, function(source)
    caudaBater(source)
end, false)

-- /caudacl  — enrolar cauda
RegisterCommand(tcmds.enrolar, function(source)
    caudaEnrolar(source)
end, false)

-- /caudaop  — cauda reta
RegisterCommand(tcmds.reta, function(source)
    caudaReta(source)
end, false)

-----------------------------------------------------------------------
-- COMANDO HUD
-----------------------------------------------------------------------
RegisterCommand(Config.HudCommand, function(source)
    if Config.Callbacks and Config.Callbacks.CanOpenHUD then
        if Config.Callbacks.CanOpenHUD(source) == false then
            return deny(source, 'no_permission')
        end
    end

    local hasWing     = PlayerWings[source] ~= nil
    local hasTail     = PlayerTails[source] ~= nil
    local canEquip    = canUse(source)

    TriggerClientEvent(resourceName .. ':openHud', source, {
        hasWing  = hasWing,
        hasTail  = hasTail,
        canEquip = canEquip,
        locale   = Config.Locale or 'pt-BR',
    })
end, false)

-----------------------------------------------------------------------
-- ox_lib commands (se UseOxLib = true)
-----------------------------------------------------------------------
if Config.UseOxLib and lib then
    lib.addCommand(cmds.equip, {
        help = 'Equipar asas demoníacas',
        params = {{ name = 'cor', type = 'number', optional = true, help = 'ID da cor (1-' .. WING_MAX_COLORS .. ')' }},
    }, function(source, args)
        equipWing(source, args.cor or 1)
    end)

    lib.addCommand(cmds.remove, { help = 'Remover asas' }, function(source)
        removeWing(source)
    end)

    lib.addCommand(cmds.toggle, { help = 'Abrir/fechar asas' }, function(source)
        toggleWing(source)
    end)

    lib.addCommand(cmds.fly, { help = 'Toggle modo de voo' }, function(source)
        toggleFly(source)
    end)

    lib.addCommand(cmds.color, {
        help = 'Mudar cor das asas',
        params = {{ name = 'cor', type = 'number', help = 'ID da cor (1-' .. WING_MAX_COLORS .. ')' }},
    }, function(source, args)
        changeWingColor(source, args.cor)
    end)

    lib.addCommand(cmds.cleanup, { help = '[ADMIN] Remover todas as asas do mundo' }, function(source)
        adminCleanup(source)
    end)

    lib.addCommand(cmds.abrir, { help = 'Animação: abrir asas' }, function(source)
        abrirWing(source)
    end)

    lib.addCommand(cmds.fechar, { help = 'Animação: fechar asas' }, function(source)
        fecharWing(source)
    end)

    lib.addCommand(cmds.bater, { help = 'Animação: bater asas' }, function(source)
        baterWing(source)
    end)

    lib.addCommand(tcmds.equip, {
        help = 'Equipar cauda demoníaca',
        params = {{ name = 'cor', type = 'number', optional = true, help = 'ID da cor (1-' .. TAIL_MAX_COLORS .. ')' }},
    }, function(source, args)
        equipTail(source, args.cor or 1)
    end)

    lib.addCommand(tcmds.remove, { help = 'Remover cauda' }, function(source)
        removeTail(source)
    end)

    lib.addCommand(tcmds.color, {
        help = 'Mudar cor da cauda',
        params = {{ name = 'cor', type = 'number', help = 'ID da cor (1-' .. TAIL_MAX_COLORS .. ')' }},
    }, function(source, args)
        changeTailColor(source, args.cor)
    end)

    lib.addCommand(tcmds.bater, { help = 'Animação: bater cauda' }, function(source)
        caudaBater(source)
    end)

    lib.addCommand(tcmds.enrolar, { help = 'Animação: enrolar cauda' }, function(source)
        caudaEnrolar(source)
    end)

    lib.addCommand(tcmds.reta, { help = 'Animação: cauda reta' }, function(source)
        caudaReta(source)
    end)

    lib.addCommand(Config.HudCommand, { help = 'Abrir/fechar HUD Demon' }, function(source)
        if Config.Callbacks and Config.Callbacks.CanOpenHUD then
            if Config.Callbacks.CanOpenHUD(source) == false then
                return deny(source, 'no_permission')
            end
        end
        TriggerClientEvent(resourceName .. ':openHud', source, {
            hasWing  = PlayerWings[source] ~= nil,
            hasTail  = PlayerTails[source] ~= nil,
            canEquip = canUse(source),
            locale   = Config.Locale or 'pt-BR',
        })
    end)
end

-----------------------------------------------------------------------
-- Keybinds registrados no cliente via RegisterKeyMapping
-- O cliente dispara eventos de rede para o servidor
-----------------------------------------------------------------------

-- O cliente solicita toggle via evento de rede
RegisterNetEvent(resourceName .. ':reqToggleWing', function()
    local source = source
    toggleWing(source)
end)

RegisterNetEvent(resourceName .. ':reqToggleFly', function()
    local source = source
    toggleFly(source)
end)

RegisterNetEvent(resourceName .. ':reqOpenHud', function()
    local source = source
    if Config.Callbacks and Config.Callbacks.CanOpenHUD then
        if Config.Callbacks.CanOpenHUD(source) == false then return end
    end
    TriggerClientEvent(resourceName .. ':openHud', source, {
        hasWing  = PlayerWings[source] ~= nil,
        hasTail  = PlayerTails[source] ~= nil,
        canEquip = canUse(source),
        locale   = Config.Locale or 'pt-BR',
    })
end)

-----------------------------------------------------------------------
-- NUI callbacks  (client/main.lua usa TriggerServerEvent via NUI fetch)
-----------------------------------------------------------------------

-- hudAction: ações disparadas pelo NUI (botões do radial menu)
RegisterNetEvent(resourceName .. ':hudAction', function(data)
    local source = source
    if type(data) ~= 'table' then return end

    local action = data.action

    if action == 'pegarasa' then
        local cor = tonumber(data.wingId) or 1
        equipWing(source, cor)

    elseif action == 'pegarcauda' then
        local cor = tonumber(data.tailId) or 1
        equipTail(source, cor)

    elseif action == 'pegarambos' then
        local wingCor = tonumber(data.wingId) or 1
        local tailCor = tonumber(data.tailId) or wingCor
        equipWing(source, wingCor)
        equipTail(source, tailCor)

    elseif action == 'removerasa' then
        removeWing(source)

    elseif action == 'removercauda' then
        removeTail(source)

    elseif action == 'asafechar' then
        fecharWing(source)

    elseif action == 'asaabrir' then
        abrirWing(source)

    elseif action == 'asabater' then
        baterWing(source)

    elseif action == 'toggleasa' then
        if PlayerWings[source] then
            removeWing(source)
        else
            local cor = tonumber(data.wingId) or 1
            equipWing(source, cor)
        end

    elseif action == 'togglecauda' then
        if PlayerTails[source] then
            removeTail(source)
        else
            local cor = tonumber(data.tailId) or 1
            equipTail(source, cor)
        end

    elseif action == 'caudareta' then
        caudaReta(source)

    elseif action == 'caudaenrolar' then
        caudaEnrolar(source)

    elseif action == 'caudabater' then
        caudaBater(source)
    end
end)

-- closeHud: NUI informa que o HUD foi fechado
RegisterNetEvent(resourceName .. ':closeHud', function()
    -- Sem lógica server-side necessária; evento registrado para extensibilidade
end)

-- Evento disparado pelo cleanup local do cliente: confirma remoção de prop bugado
RegisterNetEvent(resourceName .. ':confirmLocalCleanup', function(wingCleaned, tailCleaned)
    local source = source
    if wingCleaned then WingObjects[source] = nil end
    if tailCleaned then TailObjects[source] = nil end
end)

-- O cliente reporta o netId do prop criado (para tracking server-side)
RegisterNetEvent(resourceName .. ':reportWingObject', function(netId)
    local source = source
    if type(netId) == 'number' then
        WingObjects[source] = netId
    end
end)

RegisterNetEvent(resourceName .. ':reportTailObject', function(netId)
    local source = source
    if type(netId) == 'number' then
        TailObjects[source] = netId
    end
end)

-----------------------------------------------------------------------
-- Callback para cliente verificar estado (ex.: ao reconectar HUD)
-----------------------------------------------------------------------
if lib then
    lib.callback.register(resourceName .. ':getPlayerState', function(source)
        return {
            hasWing  = PlayerWings[source] ~= nil,
            hasTail  = PlayerTails[source] ~= nil,
            wingCor  = PlayerWings[source] and PlayerWings[source].cor or nil,
            tailCor  = PlayerTails[source] and PlayerTails[source].cor or nil,
            canEquip = canUse(source),
            locale   = Config.Locale or 'pt-BR',
        }
    end)
end

-- Fallback sem ox_lib: evento de rede simples
RegisterNetEvent(resourceName .. ':reqPlayerState', function()
    local source = source
    TriggerClientEvent(resourceName .. ':playerState', source, {
        hasWing  = PlayerWings[source] ~= nil,
        hasTail  = PlayerTails[source] ~= nil,
        wingCor  = PlayerWings[source] and PlayerWings[source].cor or nil,
        tailCor  = PlayerTails[source] and PlayerTails[source].cor or nil,
        canEquip = canUse(source),
        locale   = Config.Locale or 'pt-BR',
    })
end)

print('^3[' .. resourceName .. '] server/main.lua carregado.^0')
