Config = {}

-----------------------------------------------------------------------
-- Framework & General Settings
-----------------------------------------------------------------------

-- Framework detection: 'auto', 'qbx', 'qb', 'esx', 'vrp', 'standalone'
Config.Framework = 'vrp'

-- Enable ox_lib integration (lib.addCommand, lib.notify, etc.)
-- Set to false if ox_lib is not available on the target server
Config.UseOxLib = true

-- Language (system + HUD): 'pt-BR', 'en-US', 'es', 'fr', 'pt-PT', 'th'
-- Request new languages: contact math0001 on Discord
Config.Locale = 'pt-BR'

-- Notification system: 'auto', 'ox_lib', 'qb', 'esx', 'vrp', 'native'
-- 'auto' picks the best available (ox_lib > framework > native)
Config.Notifications = {
    type = 'ox_lib',
    duration = 5000,
}

-----------------------------------------------------------------------
-- Command Names (customer can rename freely)
-----------------------------------------------------------------------

Config.Commands = {
    equip     = 'asasdm',          -- Equip wings (accepts color param)
    remove    = 'removerdm',       -- Remove equipped wings
    toggle    = 'asasdmtg',        -- Open/close wings
    fly       = 'asasvoardm',      -- Toggle flight mode
    color     = 'asascordm',       -- Change wing color
    cleanup   = 'asaslimpardm',    -- Admin: remove ALL wings in the world (global)
    cleanup2  = 'asaslimpar2dm',   -- Remove orphaned/bugged wings near you
    abrir     = 'abrirdm',         -- Open wings (ground animation)
    fechar    = 'fechardm',        -- Close wings (ground animation)
    bater     = 'baterdm',         -- Flap wings (ground animation)
}

-- HUD command
Config.HudCommand = 'demonhud'

-- Tail-specific commands (spawn/remove tail independently)
Config.TailCommands = {
    equip     = 'caudadm',         -- Equip tail (accepts color param)
    remove    = 'removercd',    -- Remove equipped tail
    color     = 'caudacordm',      -- Change tail color
    bater     = 'caudabt',         -- Flap/swing tail animation
    enrolar   = 'caudacl',    -- Wrap tail around waist
    reta      = 'caudaop',       -- Extend tail straight (like wing open)
}

-----------------------------------------------------------------------
-- Keybinds (player can rebind in GTA V Settings > Key Bindings > FiveM)
-- Set key to false to disable that keybind
-- Key names: https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/
-----------------------------------------------------------------------

Config.Keybinds = {
    toggle = '',       -- Open/close wings
    fly    = false,      -- Toggle flight (disabled by default, set a key to enable)
    hud    = '',         -- Open demon HUD (set a key like 'F6' to enable)
}

-----------------------------------------------------------------------
-- Callbacks (customer can override behavior without touching code)
-----------------------------------------------------------------------

Config.Callbacks = {}

-- Called BEFORE equipping wings. Return false to block.
-- Also controls whether the GET WING button appears enabled in the HUD.
-- @param source number - Player server ID
-- @param cor number - Wing color being equipped (nil when checking HUD state)
-- @return boolean|nil - false blocks, true/nil allows
Config.Callbacks.CanEquipWings = function(source, cor)
    -- if Player(source).state.bucket == 666 then
        return true
    -- end
    -- return false
end

-- Called AFTER wings are equipped successfully
-- @param source number - Player server ID
-- @param cor number - Wing color equipped
Config.Callbacks.OnWingsEquipped = function(source, cor)
    -- Example: log to discord, give xp, etc.
end

-- Called AFTER wings are removed
-- @param source number - Player server ID
Config.Callbacks.OnWingsRemoved = function(source)
    -- Example: remove buffs, log, etc.
end

-- Called BEFORE opening the HUD. Return false to block.
-- @param source number - Player server ID
-- @return boolean - false blocks, true/nil allows
Config.Callbacks.CanOpenHUD = function(source)
    return true
end

-- Override permission check. Return nil to use default bridge logic.
-- @param source number - Player server ID
-- @param permission string - Permission key being checked
-- @return boolean|nil - true=allow, false=deny, nil=use default
Config.Callbacks.HasPermission = function(source, permission)
    return nil -- use default
end

-----------------------------------------------------------------------
-- Cooldowns (seconds) — 0 = no cooldown
-----------------------------------------------------------------------

Config.Cooldowns = {
}

