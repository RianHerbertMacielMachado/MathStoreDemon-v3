Permissions = {}

-----------------------------------------------------------------------
-- Permission Groups (map friendly names to ACE/framework groups)
-----------------------------------------------------------------------

Permissions.Groups = {
    admin = {'group.admin', 'group.god', 'group.superadmin'},
    moderator = {'group.mod', 'group.moderator', 'group.helper'},
    vip = {'group.vip', 'group.diamond'}
}

-----------------------------------------------------------------------
-- Feature Permissions
-- enabled: if false, everyone can use (no check)
-- groups: keys from Permissions.Groups above
-- jobs: framework job names (QBX/QB/ESX)
-- citizenids: specific player identifiers (citizenid or vRP user_id)
--
-- OPTIONAL (advanced):
-- sets: table of set names. Only works if your framework has a
--       "sets" system in PlayerData (e.g. custom QBX implementations).
--       Leave empty {} or remove entirely if not applicable.
-- vrpPermissions: table of vRP permission strings (only for vRP servers).
--       Uses vRP.hasPermission(user_id, perm) for checking.
--       Leave empty {} or remove entirely if not using vRP.
-----------------------------------------------------------------------

Permissions.Features = {
    use = {
        enabled = true,
        groups = {'admin'},
        jobs = {},
        citizenids = {},
        sets = {'ceo', 'admin', 'ninfas'}, -- uncomment if your server uses Sets
        vrpPermissions = {},                -- vRP: e.g. {'wings.use', 'vip.access'}
    },
    admin_cleanup = {
        enabled = true,
        groups = {'admin'},
        jobs = {},
        citizenids = {},
        sets = {'admin'},                   -- uncomment if your server uses Sets
        vrpPermissions = {'Admin'},                -- vRP: e.g. {'wings.admin'}
    }
}

-----------------------------------------------------------------------
-- ACE Permissions (FiveM native permission system)
-----------------------------------------------------------------------

Permissions.Ace = {
    use = 'mathstore_demon.use',
    admin_cleanup = 'mathstore_demon.admin'
}

-----------------------------------------------------------------------
-- VRP FRAMEWORK ONLY - vRP Group Permissions
-- Only used when running on a vRP server.
-- Add the exact vRP group names your server uses.
-- Uses vRP.HasGroup() and vRP.hasPermission() for checking.
-----------------------------------------------------------------------

Permissions.VRP = {
    use = {'demonios3.permissao', 'Admin'},
    admin_cleanup = {'Admin'},
}
