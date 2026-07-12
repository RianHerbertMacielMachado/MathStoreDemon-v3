-----------------------------------------------------------------------
-- fivem_dumper/client/main.lua
--
-- Lado cliente do fivem_dumper.
-- Recebe notificações do servidor e exibe feedback ao jogador admin.
-----------------------------------------------------------------------

local DUMPER_RES = GetCurrentResourceName()

-----------------------------------------------------------------------
-- HUD de notificação: exibe resultado da análise via DrawNotification
-- Simples e sem dependências externas.
-----------------------------------------------------------------------
local function notify(msg, type_)
    -- Tenta ox_lib se disponível
    if exports and exports["ox_lib"] then
        local ok = pcall(function()
            exports["ox_lib"]:notify({ title="FiveM Dumper", description=msg, type=type_ or "success" })
        end)
        if ok then return end
    end

    -- Tenta ESX/QB notify
    if exports and exports["es_extended"] then
        local ok = pcall(function()
            exports["es_extended"]:ShowNotification(msg)
        end)
        if ok then return end
    end

    -- Fallback: DrawNotification nativo
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName("~b~FiveM Dumper~s~\n"..msg)
    EndTextCommandThefeedPostTicker(false, false)
end

-----------------------------------------------------------------------
-- Recebe relatório do servidor e notifica o jogador (se for admin)
-----------------------------------------------------------------------
RegisterNetEvent(DUMPER_EV_CLIENT_REPORT)
AddEventHandler(DUMPER_EV_CLIENT_REPORT, function(report)
    if type(report) ~= "table" then return end

    if report.error then
        notify("Erro: "..tostring(report.error), "error")
        return
    end

    if report.resource then
        local msg = string.format(
            "Análise de %s concluída!\n%d eventos | %d arquivos | %dms",
            report.resource,
            (report.sv_events or 0) + (report.cl_events or 0),
            report.files   or 0,
            report.elapsed or 0)
        notify(msg, "success")
    end
end)

-----------------------------------------------------------------------
-- Comando client /dumpstatus — mostra onde estão os arquivos gerados
-- (conveniente para admins in-game saberem onde olhar)
-----------------------------------------------------------------------
RegisterCommand("dumpstatus", function()
    local msg = "Output em: fivem_dumper/output/"
    notify(msg, "info")
    print("^5[Dumper Client]^7 "..msg)
end, false)

print("^5[Dumper Client]^7 carregado.")
