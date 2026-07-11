-----------------------------------------------------------------------
-- server/core.lua — MathStoreDemon-v3
-- Núcleo do servidor: controle de estado, pronto e parada
-----------------------------------------------------------------------

local resourceName = GetCurrentResourceName()
local serverReady  = false

-----------------------------------------------------------------------
-- Aguarda o servidor ficar pronto
-----------------------------------------------------------------------
CreateThread(function()
    Wait(500)
    serverReady = true
    TriggerEvent(resourceName .. ':serverCoreReady')
    print('^2[' .. resourceName .. '] Server core iniciado com sucesso.^0')
end)

--- Retorna true se o core do servidor está pronto
function IsServerCoreReady()
    return serverReady
end

-----------------------------------------------------------------------
-- Limpa estado ao parar o resource
-----------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res == resourceName then
        serverReady = false
    end
end)
