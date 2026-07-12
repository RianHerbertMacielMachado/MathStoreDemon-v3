-----------------------------------------------------------------------
-- fivem_dumper/shared/constants.lua
-- Constantes compartilhadas entre server e client.
-----------------------------------------------------------------------

DUMPER_VERSION   = "2.0.0"
DUMPER_RESOURCE  = GetCurrentResourceName()

-- Evento para o client enviar dados coletados de volta ao servidor
DUMPER_EV_CLIENT_REPORT = DUMPER_RESOURCE .. ":clientReport"
DUMPER_EV_REQUEST_DUMP  = DUMPER_RESOURCE .. ":requestDump"
