-----------------------------------------------------------------------
-- client/core.lua — MathStoreDemon-v3
-- Núcleo do cliente: aguarda a sessão de rede iniciar e expõe
-- a função IsCoreReady() para os demais scripts do client.
-----------------------------------------------------------------------

local resourceName = GetCurrentResourceName()
local coreReady    = false

-----------------------------------------------------------------------
-- Aguarda a sessão de rede estar ativa antes de liberar o resource
-----------------------------------------------------------------------
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(100)
    end
    coreReady = true
    TriggerEvent(resourceName .. ':coreClientReady')
    print('^2[' .. resourceName .. '] Client core pronto.^0')
end)

-----------------------------------------------------------------------
-- Retorna true quando a sessão de rede está ativa
-----------------------------------------------------------------------
function IsCoreReady()
    return coreReady
end

-----------------------------------------------------------------------
-- Reseta o estado ao parar o resource
-----------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res == resourceName then
        coreReady = false
    end
end)
