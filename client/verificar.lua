-----------------------------------------------------------------------
-- client/verificar.lua — MathStoreDemon-v3
-- Verificações de estado: ped vivo, sessão ativa, props, voo
-- Roda em loop para garantir que props permaneçam attachados
-- e para processar o modo de voo frame a frame.
-----------------------------------------------------------------------

local resourceName = GetCurrentResourceName()

-----------------------------------------------------------------------
-- Intervalo dos loops (ms)
-----------------------------------------------------------------------
local TICK_VERIFY = 1000   -- verificação de integridade dos props
local TICK_FLY    = 0      -- loop de voo (frame a frame)

-----------------------------------------------------------------------
-- Variáveis de controle de voo
-----------------------------------------------------------------------
local velVoo       = 0.0   -- velocidade atual no voo
local velMax       = Config.VooVelMax    or 2.5
local velAcel      = Config.VooAcel     or 0.05
local velDesacel   = Config.VooDesacel  or 0.08
local alturaMin    = Config.VooAlturaMin or 0.3  -- altura mínima acima do chão

-----------------------------------------------------------------------
-- Loop de verificação de integridade dos props
-- Garante que asas/cauda continuem attachadas ao ped mesmo após
-- animações, respawn ou teleporte.
-----------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(TICK_VERIFY)

        if not IsCoreReady() then goto continue end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or IsEntityDead(ped) then
            goto continue
        end

        -- Verifica integridade das asas
        if GetWingsAttached() and not AreWingsValid() then
            ReattachWings()   -- definido em bones.lua
        end

        -- Verifica integridade da cauda
        if GetTailAttached() and not IsTailValid() then
            ReattachTail()    -- definido em bones.lua
        end

        ::continue::
    end
end)

-----------------------------------------------------------------------
-- Loop de voo
-- Processa movimento, gravidade e animação enquanto emVoo é true.
-- Referencia a flag emVoo via GetFlyMode() de bones.lua.
-----------------------------------------------------------------------
CreateThread(function()
    while true do
        -- Quando não está em voo, dorme mais tempo para economizar CPU
        if not GetFlyMode() then
            Wait(500)
            goto flyLoop
        end

        Wait(TICK_FLY)

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or IsEntityDead(ped) then
            SetFlyMode(false)
            goto flyLoop
        end

        -- Desativa gravidade do ped enquanto voa
        SetEntityHasGravity(ped, false)

        local fwd     = GetEntityForwardVector(ped)
        local pos     = GetEntityCoords(ped)
        local camRot  = GetGameplayCamRot(2)
        local pitch   = math.rad(camRot.x)

        -- Lê teclas de movimento
        local moveUD  = GetControlNormal(0, 8)   -- frente/trás (W/S)
        local moveH   = GetControlNormal(0, 9)   -- lateral (A/D)
        local subir   = IsControlPressed(0, 44)  -- Space / Jump
        local descer  = IsControlPressed(0, 46)  -- C / Crouch

        -- Calcula direção do voo com base na câmera
        local camFwd = GetEntityForwardVector(GetGameplayCam())

        -- Acelera se há input, desacelera caso contrário
        if math.abs(moveUD) > 0.1 or math.abs(moveH) > 0.1 then
            velVoo = math.min(velVoo + velAcel, velMax)
        else
            velVoo = math.max(velVoo - velDesacel, 0.0)
        end

        -- Componente vertical
        local velZ = 0.0
        if subir  then velZ =  0.6 end
        if descer then velZ = -0.4 end

        -- Impede atravessar o chão
        local _, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z, false)
        if pos.z <= groundZ + alturaMin and velZ < 0 then
            velZ = 0.0
        end

        -- Aplica velocidade
        local vx = camFwd.x * moveUD * velVoo * -1
        local vy = camFwd.y * moveUD * velVoo * -1
        SetEntityVelocity(ped, vx, vy, velZ)

        -- Animação de voo em loop (loopfly) quando se move
        if velVoo > 0.1 then
            if not IsEntityPlayingAnim(ped, 'mts_dm3', 'mts_dm3_loopfly', 3) then
                TaskPlayAnim(ped, 'mts_dm3', 'mts_dm3_loopfly', 2.0, -2.0, -1, 1 + 16, 0, false, false, false)
            end
        end

        ::flyLoop::
    end
end)

-----------------------------------------------------------------------
-- Restaura gravidade ao sair do voo
-----------------------------------------------------------------------
AddEventHandler(resourceName .. ':toggleFly', function()
    -- Quando o voo é desativado, restaura gravidade
    if not GetFlyMode() then
        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            SetEntityHasGravity(ped, true)
            velVoo = 0.0
            -- Para animação de voo
            StopAnimTask(ped, 'mts_dm3', 'mts_dm3_loopfly', -2.0)
        end
    end
end)

-----------------------------------------------------------------------
-- Garante gravidade ao remover asas
-----------------------------------------------------------------------
AddEventHandler(resourceName .. ':despawnWings', function()
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        SetEntityHasGravity(ped, true)
        velVoo = 0.0
    end
end)

-----------------------------------------------------------------------
-- Garante gravidade ao parar o resource
-----------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= resourceName then return end
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        SetEntityHasGravity(ped, true)
        velVoo = 0.0
    end
end)

print('^3[' .. resourceName .. '] client/verificar.lua carregado.^0')
