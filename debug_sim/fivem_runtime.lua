-----------------------------------------------------------------------
-- debug_sim/fivem_runtime.lua
-- Simulador do runtime FiveM em Lua 5.4 puro.
-- Reimplementa o ambiente global que o FiveM injeta em cada script,
-- tanto server-side quanto client-side, capturando e logando tudo.
-----------------------------------------------------------------------

local SIM = {}

-----------------------------------------------------------------------
-- Configurações do simulador
-----------------------------------------------------------------------
SIM.LOG_FILE   = "debug_sim/output.log"
SIM.SIDE       = "SHARED" -- será sobrescrito por "CLIENT" ou "SERVER"
SIM.RESOURCE   = "MathStoreDemon-v3"
SIM.LOG_SCREEN = true

-----------------------------------------------------------------------
-- Log central
-----------------------------------------------------------------------
local _log_fh = io.open(SIM.LOG_FILE, "w")

local function log(tag, msg)
    local line = string.format("[%s][%s] %s", SIM.SIDE, tag, msg)
    if SIM.LOG_SCREEN then print(line) end
    if _log_fh then
        _log_fh:write(line .. "\n")
        _log_fh:flush()
    end
end

SIM.log = log

-----------------------------------------------------------------------
-- Serializer genérico (seguro contra ciclos)
-----------------------------------------------------------------------
local function ser(v, depth, seen)
    depth = depth or 0
    seen  = seen  or {}
    if depth > 5 then return "..." end
    local t = type(v)
    if t == "nil"      then return "nil" end
    if t == "boolean"  then return tostring(v) end
    if t == "number"   then return tostring(v) end
    if t == "string"   then
        local s = v:gsub("\n","\\n"):gsub("\r","\\r")
        if #s > 300 then s = s:sub(1,300).."…" end
        return '"'..s..'"'
    end
    if t == "function" then return "<function "..tostring(v)..">" end
    if t == "table" then
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local parts, n = {}, 0
        for k,val in pairs(v) do
            n = n + 1
            if n > 30 then parts[#parts+1]="..."; break end
            local ks = type(k)=="string" and k or ("["..tostring(k).."]")
            parts[#parts+1] = ks.."="..ser(val, depth+1, seen)
        end
        seen[v] = nil
        return "{"..table.concat(parts,", ").."}"
    end
    return "<"..t..">"
end

SIM.ser = ser

-----------------------------------------------------------------------
-- Registro de eventos (AddEventHandler / TriggerEvent)
-----------------------------------------------------------------------
local _event_handlers = {}   -- [eventName] = { fn, fn, ... }
local _net_events     = {}   -- set de nomes registrados via RegisterNetEvent
local _nui_callbacks  = {}   -- [name] = fn

-----------------------------------------------------------------------
-- Registro de threads (simula CreateThread / Citizen.CreateThread)
-----------------------------------------------------------------------
local _threads        = {}   -- coroutines pendentes
local _thread_count   = 0

-----------------------------------------------------------------------
-- Estado de jogadores simulados
-----------------------------------------------------------------------
local _players = {
    { id = 1, name = "TestPlayer1", identifiers = {"license:abc123", "steam:123"} },
    { id = 2, name = "TestPlayer2", identifiers = {"license:def456", "steam:456"} },
}

local _player_state = {}   -- [id] = { wings=nil, tail=nil }
for _, p in ipairs(_players) do
    _player_state[p.id] = {}
end

-----------------------------------------------------------------------
-- Globals rastreados (para detectar o que os obfuscados expõem)
-----------------------------------------------------------------------
local _known_globals   = {}
local function snapshot_globals(env)
    local new = {}
    for k, v in pairs(env) do
        if not _known_globals[k] then
            _known_globals[k] = true
            new[k] = v
        end
    end
    if next(new) then
        for k, v in pairs(new) do
            local vt = type(v)
            if vt ~= "userdata" then
                log("NEW_GLOBAL", k.." = "..ser(v, 1))
            end
        end
    end
end

-----------------------------------------------------------------------
-- Constrói o ambiente global simulado (injetado em cada script)
-----------------------------------------------------------------------
function SIM.build_env(side, source_player_id)
    local env = {}

    -- herda globals Lua padrão
    for k, v in pairs(_G) do env[k] = v end

    env.__index = env
    local source = source_player_id or 0

    -- ── CRITICAL: Luraph VM env propagation fix ──────────────────────
    -- Luraph scripts create an inner _ENV table initialized from the outer
    -- _ENV at load time. To ensure globals set by shared scripts (E, Bridge,
    -- Config, etc.) are visible from ALL Luraph inner VMs (including threads
    -- created later), we use a write-through metatable: any key set in env
    -- is ALSO written to _G, making it accessible to any inner VM.
    -- We use a separate guard table to avoid infinite loops.
    local _g_sync_skip = { _G=true, package=true, io=true, os=true, debug=true }
    setmetatable(env, {
        __index = function(t, k)
            -- First check raw env, then _G
            local v = rawget(t, k)
            if v ~= nil then return v end
            return rawget(_G, k)
        end,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            -- Sync to _G so Luraph inner VMs can find it
            if not _g_sync_skip[k] then
                rawset(_G, k, v)
            end
        end,
    })

    -- ── Constantes ──────────────────────────────────────────────────
    env.source = source

    -- ── Utilitários básicos FiveM ────────────────────────────────────
    env.GetCurrentResourceName = function()
        return SIM.RESOURCE
    end

    env.GetResourceState = function(name)
        -- Simula recursos presentes: vrp, ox_lib (falsos para não travar auth)
        local present = { vrp=true, ox_lib=false, ["qbx_core"]=false,
                          ["qb-core"]=false, es_extended=false }
        if present[name] then return "started" end
        return "missing"
    end

    env.LoadResourceFile = function(resource, file)
        log("LoadResourceFile", resource.."/"..file)
        -- Retorna nil para dependências externas (ox_lib init, vrp utils)
        return nil
    end

    env.GetConvar = function(name, default)
        log("GetConvar", 'name="'..name..'" default="'..tostring(default)..'"')
        -- Simula sem key configurada
        return default or ""
    end

    env.GetConvarInt = function(name, default)
        log("GetConvar", 'name="'..name..'" (int) default='..tostring(default))
        return default or 0
    end

    -- ── Tempo ────────────────────────────────────────────────────────
    env.GetGameTimer = function()
        -- milissegundos desde epoch (simulado)
        return math.floor(os.clock() * 1000)
    end

    env.os = os  -- os.time, os.clock, etc.

    -- ── Wait / Citizen.Wait ──────────────────────────────────────────
    -- Em coroutines reais vamos yield; fora delas apenas registra
    env.Wait = function(ms)
        local co = coroutine.running()
        if co then
            -- não bloqueia de verdade — apenas loga e volta
            log("Wait", tostring(ms).."ms (yielded)")
            coroutine.yield(ms)
        else
            log("Wait", tostring(ms).."ms (main thread, skipped)")
        end
    end

    -- ── Threads ─────────────────────────────────────────────────────
    env.CreateThread = function(fn)
        _thread_count = _thread_count + 1
        local id = _thread_count
        log("CreateThread", "#"..id.." registered")
        local co = coroutine.create(function()
            local ok, err = pcall(fn)
            if not ok then
                log("CreateThread", "#"..id.." ERROR: "..tostring(err))
            else
                log("CreateThread", "#"..id.." finished")
            end
        end)
        _threads[#_threads+1] = { id=id, co=co }
        return co
    end

    env.Citizen = {
        CreateThread    = env.CreateThread,
        Wait            = env.Wait,
        Trace           = function(msg) log("Citizen.Trace", msg) end,
        InvokeNative    = function(hash, ...)
            log("InvokeNative", string.format("hash=0x%X args=(%s)", hash, ser({...},1)))
        end,
    }

    -- ── Eventos ──────────────────────────────────────────────────────
    env.AddEventHandler = function(eventName, handler)
        log("AddEventHandler", '"'..eventName..'"')
        if not _event_handlers[eventName] then
            _event_handlers[eventName] = {}
        end
        table.insert(_event_handlers[eventName], handler)
    end

    env.RegisterNetEvent = function(eventName, handler)
        log("RegisterNetEvent", '"'..eventName..'"')
        _net_events[eventName] = true
        if handler then
            env.AddEventHandler(eventName, handler)
        end
    end

    env.TriggerEvent = function(eventName, ...)
        local args = {...}
        log("TriggerEvent", '"'..eventName..'"  args='..ser(args,2))
        if _event_handlers[eventName] then
            for _, h in ipairs(_event_handlers[eventName]) do
                local co = coroutine.running()
                if co then
                    -- Already in a coroutine — call directly with pcall
                    local ok, err = pcall(h, table.unpack(args))
                    if not ok then
                        log("TriggerEvent.ERROR", '"'..eventName..'" '..tostring(err))
                    end
                else
                    -- In main thread — wrap in coroutine to allow Wait()
                    local ok, err = pcall(h, table.unpack(args))
                    if not ok then
                        log("TriggerEvent.ERROR", '"'..eventName..'" '..tostring(err))
                    end
                end
            end
        end
    end

    env.TriggerServerEvent = function(eventName, ...)
        local args = {...}
        log("TriggerServerEvent", '"'..eventName..'"  src='..tostring(source)..'  args='..ser(args,2))
    end

    env.TriggerClientEvent = function(eventName, target, ...)
        local args = {...}
        local tgt = target == -1 and "ALL" or tostring(target)
        log("TriggerClientEvent", '"'..eventName..'"  target='..tgt..'  args='..ser(args,2))
        -- Simula loopback para handlers registrados
        if _event_handlers[eventName] then
            for _, h in ipairs(_event_handlers[eventName]) do
                local ok, err = pcall(h, table.unpack(args))
                if not ok then
                    log("TriggerClientEvent.ERROR", '"'..eventName..'" '..tostring(err))
                end
            end
        end
    end

    env.TriggerLatentClientEvent = function(eventName, target, bps, ...)
        log("TriggerLatentClientEvent", '"'..eventName..'"  target='..tostring(target)..'  bps='..tostring(bps))
    end

    -- ── NUI ──────────────────────────────────────────────────────────
    env.SendNuiMessage = function(json_str)
        log("SendNuiMessage", json_str or "nil")
    end

    env.RegisterNuiCallback = function(name, handler)
        log("RegisterNuiCallback", '"'..name..'"')
        _nui_callbacks[name] = handler
    end

    env.SetNuiFocus = function(hasFocus, hasCursor)
        log("SetNuiFocus", "focus="..tostring(hasFocus).." cursor="..tostring(hasCursor))
    end

    -- ── HTTP ─────────────────────────────────────────────────────────
    env.PerformHttpRequest = function(url, cb, method, data, headers)
        log("PerformHttpRequest", string.format('method=%s url="%s" body=%s',
            tostring(method or "GET"), url, ser(data,1)))
        -- Simula resposta de auth: key não configurada = não chama cb
        -- Para testar, simula HTTP 200 com status ok
        if cb then
            local fake_resp = '{"status":"ok","product":"demon_v3"}'
            log("PerformHttpRequest.RESPONSE", "200 "..fake_resp)
            cb(200, fake_resp, {})
        end
    end

    -- ── Comandos ─────────────────────────────────────────────────────
    local _commands = {}
    env.RegisterCommand = function(name, handler, restricted)
        log("RegisterCommand", '"/'..name..'"  restricted='..tostring(restricted))
        _commands[name] = handler
    end
    env._commands = _commands   -- expõe para o runner

    -- ── ACE / Permissões ─────────────────────────────────────────────
    env.IsPlayerAceAllowed = function(src, ace)
        log("IsPlayerAceAllowed", "src="..tostring(src).." ace="..tostring(ace))
        return false  -- sem permissão por padrão (testa o fluxo de negação)
    end

    env.IsPrincipalAceAllowed = function(principal, ace)
        return false
    end

    -- ── Jogadores ────────────────────────────────────────────────────
    env.GetPlayers = function()
        local ids = {}
        for _, p in ipairs(_players) do ids[#ids+1] = tostring(p.id) end
        return ids
    end

    env.GetPlayerName = function(src)
        for _, p in ipairs(_players) do
            if p.id == tonumber(src) then return p.name end
        end
        return "Unknown"
    end

    env.GetNumPlayerIdentifiers = function(src)
        for _, p in ipairs(_players) do
            if p.id == tonumber(src) then return #p.identifiers end
        end
        return 0
    end

    env.GetPlayerIdentifier = function(src, idx)
        for _, p in ipairs(_players) do
            if p.id == tonumber(src) then
                return p.identifiers[idx + 1]
            end
        end
        return nil
    end

    env.GetPlayerPed = function(src)
        log("GetPlayerPed", "src="..tostring(src))
        return 1000 + (tonumber(src) or 0)
    end

    env.GetEntityCoords = function(entity)
        log("GetEntityCoords", "entity="..tostring(entity))
        return {x=0.0, y=0.0, z=0.0}
    end

    -- ── Entidades / Props ────────────────────────────────────────────
    local _entity_counter = 5000

    env.CreateObject = function(model, x, y, z, isNetwork, bMissionEntity, doorFlag)
        _entity_counter = _entity_counter + 1
        local eid = _entity_counter
        log("CreateObject", string.format('model=%s pos=(%.1f,%.1f,%.1f) → entity=%d',
            ser(model,0), x or 0, y or 0, z or 0, eid))
        return eid
    end

    env.CreateObjectNoOffset = env.CreateObject

    env.AttachEntityToEntity = function(entity, entityTo, boneIndex, ox, oy, oz, rx, ry, rz, p9, useSoftPinning, collision, isPed, vertexIndex, fixedRot)
        log("AttachEntityToEntity", string.format(
            'entity=%d  attachTo=%d  bone=%d  offset=(%.2f,%.2f,%.2f)  rot=(%.2f,%.2f,%.2f)',
            entity or 0, entityTo or 0, boneIndex or 0,
            ox or 0, oy or 0, oz or 0,
            rx or 0, ry or 0, rz or 0
        ))
    end

    env.DeleteEntity = function(entity)
        log("DeleteEntity", "entity="..tostring(entity))
    end

    env.DeleteObject = env.DeleteEntity

    env.DoesEntityExist = function(entity)
        return entity ~= nil and entity > 0
    end

    env.IsEntityAttached = function(entity)
        return false
    end

    env.DetachEntity = function(entity, ...)
        log("DetachEntity", "entity="..tostring(entity))
    end

    env.SetEntityVisible = function(entity, visible)
        log("SetEntityVisible", "entity="..tostring(entity).." visible="..tostring(visible))
    end

    env.SetEntityCollision = function(entity, toggle, keepPhysics)
        log("SetEntityCollision", "entity="..tostring(entity))
    end

    env.SetEntityAsMissionEntity = function(entity, ...)
        log("SetEntityAsMissionEntity", "entity="..tostring(entity))
    end

    env.NetworkGetNetworkIdFromEntity = function(entity)
        log("NetworkGetNetworkIdFromEntity", "entity="..tostring(entity))
        return entity + 10000
    end

    env.NetworkGetEntityFromNetworkId = function(netId)
        log("NetworkGetEntityFromNetworkId", "netId="..tostring(netId))
        return netId - 10000
    end

    env.NetworkDoesEntityExistWithNetworkId = function(netId)
        return true
    end

    env.NetworkIsSessionStarted = function()
        return true
    end

    env.SetNetworkIdCanMigrate = function(...) end
    env.SetNetworkIdExistsOnAllMachines = function(...) end

    -- ── Models / Streaming ───────────────────────────────────────────
    env.RequestModel = function(model)
        log("RequestModel", "model="..ser(model,0))
    end

    env.HasModelLoaded = function(model)
        return true   -- sempre carregado no simulador
    end

    env.IsModelValid = function(model)
        return true
    end

    env.SetModelAsNoLongerNeeded = function(model)
        log("SetModelAsNoLongerNeeded", "model="..ser(model,0))
    end

    env.GetHashKey = function(model)
        if type(model) == "string" then
            -- hash simples para debug
            local h = 0
            for i = 1, #model do
                h = (h * 31 + string.byte(model, i)) & 0xFFFFFFFF
            end
            log("GetHashKey", '"'..model..'" → '..h)
            return h
        end
        return model
    end

    -- ── Animações ────────────────────────────────────────────────────
    env.RequestAnimDict = function(dict)
        log("RequestAnimDict", '"'..tostring(dict)..'"')
    end

    env.HasAnimDictLoaded = function(dict)
        return true
    end

    env.RemoveAnimDict = function(dict)
        log("RemoveAnimDict", '"'..tostring(dict)..'"')
    end

    env.TaskPlayAnim = function(ped, animDict, animName, blendIn, blendOut, duration, flag, playbackRate, ...)
        log("TaskPlayAnim", string.format(
            'ped=%d  dict="%s"  anim="%s"  duration=%d  flag=%d',
            ped or 0, tostring(animDict), tostring(animName),
            duration or -1, flag or 0
        ))
    end

    env.PlayAnimOnEntity = function(entity, animDict, animName, ...)
        log("PlayAnimOnEntity", string.format(
            'entity=%d  dict="%s"  anim="%s"',
            entity or 0, tostring(animDict), tostring(animName)
        ))
    end

    env.StopAnimTask = function(ped, animDict, animName, ...)
        log("StopAnimTask", string.format('ped=%d dict="%s" anim="%s"', ped or 0, tostring(animDict), tostring(animName)))
    end

    env.IsEntityPlayingAnim = function(entity, animDict, animName, ...)
        return false
    end

    env.GetEntityAnimCurrentTime = function(...) return 0.0 end
    env.SetEntityAnimCurrentTime  = function(...) end

    -- ── Ped / Bones ──────────────────────────────────────────────────
    env.PlayerPedId = function()
        return 1001  -- ped local simulado
    end

    env.PlayerId = function()
        return 1
    end

    env.GetPedBoneIndex = function(ped, boneId)
        log("GetPedBoneIndex", string.format("ped=%d boneId=%s", ped or 0, tostring(boneId)))
        return boneId  -- retorna o próprio id para log
    end

    env.GetPedBoneCoords = function(ped, boneIndex, ...)
        log("GetPedBoneCoords", "ped="..tostring(ped).." bone="..tostring(boneIndex))
        return {x=0.0, y=0.0, z=0.0}
    end

    env.IsPedInAnyVehicle = function(ped, atGetIn)
        return false
    end

    env.IsPedOnFoot = function(ped) return true end
    env.IsEntityDead   = function(entity) return false end
    env.IsPedFalling   = function(ped) return false end
    env.IsPedSwimming  = function(ped) return false end
    env.GetEntitySpeed = function(entity) return 0.0 end

    env.SetEntityVelocity = function(entity, vx, vy, vz)
        log("SetEntityVelocity", string.format("entity=%d vel=(%.2f,%.2f,%.2f)", entity or 0, vx or 0, vy or 0, vz or 0))
    end

    env.GetEntityVelocity = function(entity)
        return {x=0.0, y=0.0, z=0.0}
    end

    env.GetEntityHeading = function(entity) return 0.0 end
    env.SetEntityHeading = function(entity, heading)
        log("SetEntityHeading", "entity="..tostring(entity).." heading="..tostring(heading))
    end

    env.FreezeEntityPosition = function(entity, freeze)
        log("FreezeEntityPosition", "entity="..tostring(entity).." freeze="..tostring(freeze))
    end

    -- ── Keybinds ─────────────────────────────────────────────────────
    env.RegisterKeyMapping = function(command, description, inputType, inputName)
        log("RegisterKeyMapping", string.format(
            'cmd="/%s" desc="%s" type="%s" key="%s"',
            tostring(command), tostring(description),
            tostring(inputType), tostring(inputName)
        ))
    end

    -- ── Ped Config Flags ─────────────────────────────────────────────
    env.SetPedConfigFlag = function(ped, flagId, value)
        log("SetPedConfigFlag", string.format("ped=%d flag=%d val=%s", ped or 0, flagId or 0, tostring(value)))
    end

    env.GetPedConfigFlag = function(ped, flagId, p2)
        return false
    end

    -- ── Misc NUI aliases ─────────────────────────────────────────────
    -- FiveM has both RegisterNuiCallback and RegisterNUICallback (different case)
    env.RegisterNUICallback = function(name, handler)
        log("RegisterNUICallback", '"'..tostring(name)..'"')
        _nui_callbacks[name] = handler
    end

    -- ── Lua 5.1 compat (used by vRP and legacy resources) ────────────
    env.module = function(name, ...)
        log("module", '"'..tostring(name)..'" (Lua5.1 compat, ignored)')
        -- no-op in Lua 5.4 context
    end

    -- ── StateBag ─────────────────────────────────────────────────────
    local _state_bag_handlers = {}
    env.AddStateBagChangeHandler = function(keyname, bagName, handler)
        log("AddStateBagChangeHandler", string.format('key="%s" bag="%s"', tostring(keyname), tostring(bagName or '')))
        table.insert(_state_bag_handlers, {key=keyname, bag=tostring(bagName or ''), fn=handler})
    end

    local _player_statebags = setmetatable({}, {
        __newindex = function(t, k, v)
            rawset(t, k, v)
            -- fire handlers watching this key
            for _, h in ipairs(_state_bag_handlers) do
                if h.key == k then
                    local ok, err = pcall(h.fn, 'player:0', k, v, #tostring(v or ''), false)
                    if not ok then log("StateBag.ERROR", tostring(err)) end
                end
            end
        end,
    })

    env.LocalPlayer = {
        state = _player_statebags,
    }

    env.Player = function(id)
        return { state = _player_statebags }
    end

    -- ── Entity misc ──────────────────────────────────────────────────
    env.SetEntityAlpha = function(entity, alpha, skin)
        log("SetEntityAlpha", string.format("entity=%d alpha=%d", entity or 0, alpha or 255))
    end

    env.SetEntityLodDist = function(entity, dist) end
    env.PlaceObjectOnGroundProperly = function(entity) end
    env.SetEntityCoordsNoOffset = function(entity, x, y, z, b1, b2, b3) end
    env.GetOffsetFromEntityInWorldCoords = function(entity, x, y, z)
        return x or 0, y or 0, z or 0
    end

    env.IsEntityInAir = function(entity) return false end
    env.IsEntityVisible = function(entity) return true end
    env.IsPedClimbing = function(ped) return false end
    env.ApplyForceToEntity = function(...) end
    env.SetPedToRagdoll = function(...) end

    -- ── Ped appearance ───────────────────────────────────────────────
    env.SetPedComponentVariation = function(...) end
    env.SetPedCanPlayGestureAnims = function(...) end
    env.SetPedEnableWeaponBlocking = function(...) end
    env.SetPedHelmet = function(...) end
    env.SetPedResetFlag = function(...) end
    env.SetPedClothingSpawnModifier = function(...) end
    env.SetPedFleeAttributes = function(...) end
    env.SetPedCombatAttributes = function(...) end
    env.GetPedDrawableVariation = function(...) return 0 end
    env.GetPedTextureVariation = function(...) return 0 end
    env.IsPedMale = function() return true end

    -- ── Controls ─────────────────────────────────────────────────────
    env.IsControlPressed = function(i, c) return false end
    env.IsControlJustPressed = function(i, c) return false end
    env.IsDisabledControlPressed = function(i, c) return false end
    env.IsControlJustReleased = function(i, c) return false end
    env.DisableControlAction = function(...) end
    env.EnableControlAction = function(...) end
    env.DisableAllControlActions = function(...) end

    -- ── HUD extras ───────────────────────────────────────────────────
    env.SetTextScale = function(...) end
    env.SetTextFont = function(...) end
    env.SetTextProportional = function(...) end
    env.SetTextColour = function(...) end
    env.SetTextEntry = function(...) end
    env.SetTextCentre = function(...) end
    env.SetTextOutline = function() end
    env.SetTextDropshadow = function(...) end
    env.DrawText = function(...) end
    env.BeginTextCommandDisplayText = function(...) end
    env.EndTextCommandDisplayText = function(...) end
    env.BeginTextCommandGetWidth = function(...) end
    env.EndTextCommandGetWidth = function(...) return 0.1 end
    env.DrawText3D = function(...) end
    env.BeginTextCommandThefeedPost = function(...) end
    env.EndTextCommandThefeedPostTicker = function(...) end
    env.ThefeedSetNextPostBackgroundColor = function(...) end
    env.SetNotificationMessage = function(...) end
    env.AddTextComponentSubstringKeyboardDisplay = function(...) end

    -- ── Screen ───────────────────────────────────────────────────────
    env.IsScreenFadedOut = function() return false end
    env.IsScreenFadingOut = function() return false end
    env.IsScreenFadingIn = function() return false end

    -- ── Network extras ───────────────────────────────────────────────
    env.NetworkRequestControlOfNetworkId = function(netId) end
    env.NetworkSetNetworkIdCanMigrate = function(netId, b) end
    env.NetworkSetEntityInvisibleToNetwork = function(entity, b) end
    env.NetworkIsEntityNetworked = function(entity) return true end

    -- ── Animation extras ─────────────────────────────────────────────
    env.RequestAnimSet = function(s) end
    env.HasAnimSetLoaded = function(s) return true end
    env.GetEntityAnimCurrentTime = function(...) return 0.0 end
    env.SetEntityAnimCurrentTime = function(...) end

    -- ── cache (ox_lib/qb compatibility) ──────────────────────────────
    env.cache = {
        ped      = 1001,
        vehicle  = nil,
        seat     = nil,
        serverId = 1,
        resource = "MathStoreDemon-v3",
    }

    -- ── SetNuiFocusKeepInput ──────────────────────────────────────────
    env.SetNuiFocusKeepInput = function(toggle)
        log("SetNuiFocusKeepInput", tostring(toggle))
    end

    -- ── GetPlayerServerId ─────────────────────────────────────────────
    env.GetPlayerServerId = function(player) return 1 end
    env.GetTimeDifference = function(a, b) return math.abs((b or 0) - (a or 0)) end
    env.GetFrameTime = function() return 0.016 end
    env.GetSelectedPedWeapon = function(ped) return 0 end

    -- ── Missing stubs identified via nil-trap probe ───────────────────
    env.GetPlayerFromServerId = function(serverId)
        return tonumber(serverId) or 0
    end
    env.GetEntityType = function(entity)
        log("GetEntityType", "entity="..tostring(entity))
        return 1  -- 1=ped, 2=vehicle, 3=object
    end
    env.IsEntityOnScreen = function(entity)
        return true
    end
    env.GetEntityBoneIndexByName = function(entity, boneName)
        log("GetEntityBoneIndexByName", string.format("entity=%d bone=%s", entity or 0, tostring(boneName)))
        return 0
    end
    env.GetWorldPositionOfEntityBone = function(entity, boneIndex)
        return env.vector3(0,0,0)
    end
    env.GetEntityRotation = function(entity, rotOrder)
        return env.vector3(0,0,0)
    end
    env.SetEntityRotation = function(entity, rx, ry, rz, rotOrder, p5)
        log("SetEntityRotation", string.format("entity=%d rot=(%.2f,%.2f,%.2f)", entity or 0, rx or 0, ry or 0, rz or 0))
    end
    env.TaskPlayAnimAdvanced = function(ped, animDict, animName, x, y, z, rx, ry, rz, blendIn, blendOut, duration, flag, ...)
        log("TaskPlayAnimAdvanced", string.format('ped=%d dict="%s" anim="%s"', ped or 0, tostring(animDict), tostring(animName)))
    end
    env.ClearPedTasks = function(ped)
        log("ClearPedTasks", "ped="..tostring(ped))
    end
    env.ClearPedTasksImmediately = function(ped)
        log("ClearPedTasksImmediately", "ped="..tostring(ped))
    end
    env.TaskTurnPedToFaceCoord = function(...) end
    env.SetEntityNoCollisionEntity = function(entity, entity2, toggle)
        log("SetEntityNoCollisionEntity", string.format("e1=%d e2=%d toggle=%s", entity or 0, entity2 or 0, tostring(toggle)))
    end
    env.IsEntityAMissionEntity = function(entity) return true end
    env.GetFollowPedCamHeading = function() return 0.0 end
    env.GetGameplayCamRelativePitch = function() return 0.0 end
    env.GetGameplayCamRelativeHeading = function() return 0.0 end
    env.SetGameplayCamRelativeHeading = function(...) end
    env.SetGameplayCamRelativePitch = function(...) end
    env.GetFinalRenderedCamCoord = function() return env.vector3(0,0,0) end
    env.GetFinalRenderedCamRot = function(...) return env.vector3(0,0,0) end
    env.SetGravityLevel = function(level)
        log("SetGravityLevel", tostring(level))
    end
    env.GetGravityLevel = function() return 9 end
    env.Vdist = function(x1,y1,z1,x2,y2,z2)
        local dx,dy,dz = (x2 or 0)-(x1 or 0), (y2 or 0)-(y1 or 0), (z2 or 0)-(z1 or 0)
        return math.sqrt(dx*dx+dy*dy+dz*dz)
    end
    env.Vdist2 = function(x1,y1,z1,x2,y2,z2)
        local dx,dy,dz = (x2 or 0)-(x1 or 0), (y2 or 0)-(y1 or 0), (z2 or 0)-(z1 or 0)
        return dx*dx+dy*dy+dz*dz
    end
    env.GetAnimDuration = function(dict, anim) return 2.0 end
    env.GetVehiclePedIsIn = function(ped, lastVehicle) return 0 end
    env.GetVehicleModel = function(vehicle) return 0 end
    env.GetEntityModel = function(entity) return 0 end
    env.IsEntityAnObject = function(entity) return true end
    env.IsEntityAPed = function(entity) return false end
    env.IsEntityAVehicle = function(entity) return false end
    -- verificar.lua / animprotect natives
    env.GetAnimCurrentTime = function(ped, dict, anim) return 0.0 end
    env.SetAnimCurrentTime = function(ped, dict, anim, t) end
    env.SetPedMotionBlur = function(ped, toggle) end
    env.SetPedGravity = function(ped, toggle)
        log("SetPedGravity", "ped="..tostring(ped).." toggle="..tostring(toggle))
    end
    env.ResetPedMovementClipset = function(ped, p1)
        log("ResetPedMovementClipset", "ped="..tostring(ped))
    end
    env.SetPedMovementClipset = function(ped, clipset, p2)
        log("SetPedMovementClipset", string.format("ped=%d clip=%s", ped or 0, tostring(clipset)))
    end
    env.IsPedRunning = function(ped) return false end
    env.IsPedSprinting = function(ped) return false end
    env.IsPedStill = function(ped) return true end
    env.IsPedJumping = function(ped) return false end
    env.GetPedMaxMoveBlendRatio = function(ped) return 0.0 end
    env.GetNetworkTime = function() return math.floor(os.clock() * 1000) end
    env.GetEntityForwardVector = function(entity) return env.vector3(0,1,0) end
    env.GetEntityUpVector = function(entity) return env.vector3(0,0,1) end
    env.GetEntityRightVector = function(entity) return env.vector3(1,0,0) end
    env.GetGroundZFor_3dCoord = function(x,y,z) return true, (z or 0) - 1.0 end
    env.StartParticleFxLoopedAtCoord = function(...) return 0 end
    env.StopParticleFxLooped = function(...) end
    env.RemoveParticleFx = function(...) end
    env.RequestNamedPtfxAsset = function(fx) log("RequestNamedPtfxAsset", tostring(fx)) end
    env.HasNamedPtfxAssetLoaded = function(fx) return true end
    env.UseParticleFxAssetNextCall = function(fx) end
    env.SetEntityCoords = function(entity, x, y, z, ...)
        log("SetEntityCoords", string.format("entity=%d pos=(%.2f,%.2f,%.2f)", entity or 0, x or 0, y or 0, z or 0))
    end

    env.GetEntityCoords = function(entity)
        return setmetatable({_x=100.0,_y=200.0,_z=30.0}, {
            __index = function(t, k)
                if k == 'x' then return rawget(t,'_x')
                elseif k == 'y' then return rawget(t,'_y')
                elseif k == 'z' then return rawget(t,'_z') end
            end,
        })
    end

    -- ── removeMyWings global placeholder (set later by scripts) ──────
    -- This global gets set by client/main.lua; pre-declare as no-op to
    -- prevent nil errors if accessed before the script's init thread runs
    if not env.removeMyWings then
        env.removeMyWings = function()
            log("removeMyWings", "called before client/main.lua init (pre-stub)")
        end
    end

    -- ── StopResource / resource lifecycle ────────────────────────────
    env.StopResource = function(name)
        log("StopResource", '"'..tostring(name)..'" CALLED — seria parado em produção')
    end

    env.GetResourceMetadata = function(resource, key, index)
        return nil
    end

    -- ── HUD / Notifications (nativas) ────────────────────────────────
    env.SetTextComponentFormat = function(...) end
    env.AddTextComponentSubstringPlayerName = function(...) end
    env.DrawNotification = function(blink, showInBriefing)
        log("DrawNotification", "native notification")
    end

    env.BeginTextCommandDisplayHelp = function(...) end
    env.EndTextCommandDisplayHelp    = function(...) end

    -- ── JSON ─────────────────────────────────────────────────────────
    -- FiveM injeta json global; simulamos com um encoder simples
    local function json_encode(v, depth)
        depth = depth or 0
        if depth > 6 then return '"..."' end
        local t = type(v)
        if t == "nil"     then return "null" end
        if t == "boolean" then return tostring(v) end
        if t == "number"  then return tostring(v) end
        if t == "string"  then
            v = v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r')
            return '"'..v..'"'
        end
        if t == "table" then
            -- array?
            local is_arr = true
            local n = 0
            for k in pairs(v) do
                n = n + 1
                if type(k) ~= "number" or k ~= math.floor(k) then is_arr = false; break end
            end
            if is_arr and n == #v then
                local parts = {}
                for _, val in ipairs(v) do
                    parts[#parts+1] = json_encode(val, depth+1)
                end
                return "["..table.concat(parts,",").."]"
            else
                local parts = {}
                for k, val in pairs(v) do
                    parts[#parts+1] = '"'..tostring(k)..'":'..json_encode(val, depth+1)
                end
                return "{"..table.concat(parts,",").."}"
            end
        end
        return '"<'..t..'>"'
    end

    local function json_decode(s)
        -- Robust JSON decoder for the simulator
        -- Handles nil, tables (passed directly), and JSON strings
        if s == nil then return nil end
        -- If already a table (e.g. passed from Lua directly), return as-is
        if type(s) ~= "string" then return s end
        if s == "" or s == "null" then return nil end
        -- Clean the JSON string for Lua's load():
        -- 1. Replace JSON null with false
        -- 2. Convert {"key": value} to {["key"]=value} style is complex,
        --    so we use a simple approach: replace ": " with "="
        local clean = s
        local ok_clean, err_clean = pcall(function()
            -- Replace null values
            clean = clean:gsub("%bnull%b", "false")
            -- Handle simple null (not inside strings)
            clean = clean:gsub(":%s*null%s*([,}%]])", ": false%1")
            clean = clean:gsub("null", "false")
        end)
        if not ok_clean then
            -- gsub failed (shouldn't happen with pure strings, but be safe)
            return nil
        end
        -- Try load() with the cleaned string
        local fn, err = load("return " .. clean)
        if fn then
            local ok2, val = pcall(fn)
            if ok2 then return val end
        end
        -- Fallback: return nil (don't crash)
        return nil
    end

    env.json = {
        encode = json_encode,
        decode = json_decode,
    }

    -- ── lib (ox_lib stub) ────────────────────────────────────────────
    env.lib = nil   -- ox_lib não está presente (GetResourceState retorna "missing")

    -- ── vRP stub ─────────────────────────────────────────────────────
    env.vRP = {
        getUserId       = function(args) log("vRP.getUserId", ser(args,1)); return 1 end,
        hasPermission   = function(args) log("vRP.hasPermission", ser(args,1)); return true end,
        hasGroup        = function(args) log("vRP.hasGroup", ser(args,1)); return true end,
    }

    -- ── Misc FiveM globals ───────────────────────────────────────────
    env.exports       = setmetatable({}, {
        __index = function(t, resource)
            log("exports.__index", "accessing resource: "..tostring(resource))
            return setmetatable({}, {
                __index = function(t2, fn)
                    return function(...)
                        log("exports.call", resource..":"..fn.."("..ser({...},1)..")")
                        return nil
                    end
                end
            })
        end
    })

    env.msgpack  = { pack = function(v) return tostring(v) end,
                     unpack = function(v) return v end }

    -- ── Vectors (with proper metatables for arithmetic) ──────────────
    local function make_v3(x, y, z)
        x, y, z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
        local mt = {}
        mt.__index = function(t, k)
            if k == 'x' then return rawget(t,'_x')
            elseif k == 'y' then return rawget(t,'_y')
            elseif k == 'z' then return rawget(t,'_z') end
        end
        mt.__newindex = function(t, k, v) rawset(t, k, v) end
        mt.__add = function(a, b)
            local bx = type(b)=='table' and (b.x or rawget(b,'_x') or 0) or (type(b)=='number' and b or 0)
            local by = type(b)=='table' and (b.y or rawget(b,'_y') or 0) or (type(b)=='number' and b or 0)
            local bz = type(b)=='table' and (b.z or rawget(b,'_z') or 0) or (type(b)=='number' and b or 0)
            return make_v3((rawget(a,'_x') or 0)+bx, (rawget(a,'_y') or 0)+by, (rawget(a,'_z') or 0)+bz)
        end
        mt.__sub = function(a, b)
            local bx = type(b)=='table' and (b.x or rawget(b,'_x') or 0) or 0
            local by = type(b)=='table' and (b.y or rawget(b,'_y') or 0) or 0
            local bz = type(b)=='table' and (b.z or rawget(b,'_z') or 0) or 0
            return make_v3((rawget(a,'_x') or 0)-bx, (rawget(a,'_y') or 0)-by, (rawget(a,'_z') or 0)-bz)
        end
        mt.__mul = function(a, b)
            if type(b) == 'number' then
                return make_v3((rawget(a,'_x') or 0)*b, (rawget(a,'_y') or 0)*b, (rawget(a,'_z') or 0)*b)
            end
            return make_v3(0,0,0)
        end
        mt.__unm = function(a)
            return make_v3(-(rawget(a,'_x') or 0), -(rawget(a,'_y') or 0), -(rawget(a,'_z') or 0))
        end
        mt.__len = function(a)
            local ax, ay, az = rawget(a,'_x') or 0, rawget(a,'_y') or 0, rawget(a,'_z') or 0
            return math.sqrt(ax*ax + ay*ay + az*az)
        end
        mt.__lt = function(a, b)
            -- vector3 < number  OR  vector3 < vector3
            local la = math.sqrt((rawget(a,'_x') or 0)^2 + (rawget(a,'_y') or 0)^2 + (rawget(a,'_z') or 0)^2)
            local lb = type(b)=='number' and b
                    or math.sqrt((rawget(b,'_x') or 0)^2 + (rawget(b,'_y') or 0)^2 + (rawget(b,'_z') or 0)^2)
            return la < lb
        end
        mt.__le = function(a, b)
            local la = math.sqrt((rawget(a,'_x') or 0)^2 + (rawget(a,'_y') or 0)^2 + (rawget(a,'_z') or 0)^2)
            local lb = type(b)=='number' and b
                    or math.sqrt((rawget(b,'_x') or 0)^2 + (rawget(b,'_y') or 0)^2 + (rawget(b,'_z') or 0)^2)
            return la <= lb
        end
        mt.__eq = function(a, b)
            if type(b) == 'number' then
                local la = math.sqrt((rawget(a,'_x') or 0)^2 + (rawget(a,'_y') or 0)^2 + (rawget(a,'_z') or 0)^2)
                return la == b
            end
            return (rawget(a,'_x') or 0) == (rawget(b,'_x') or 0)
               and (rawget(a,'_y') or 0) == (rawget(b,'_y') or 0)
               and (rawget(a,'_z') or 0) == (rawget(b,'_z') or 0)
        end
        mt.__tostring = function(a)
            return string.format('vector3(%g, %g, %g)', rawget(a,'_x') or 0, rawget(a,'_y') or 0, rawget(a,'_z') or 0)
        end
        return setmetatable({_x=x,_y=y,_z=z}, mt)
    end

    env.vector3 = make_v3
    env.vector2 = function(x, y)
        return setmetatable({x=x or 0, y=y or 0}, {
            __tostring = function(a) return string.format('vector2(%g, %g)', a.x, a.y) end
        })
    end
    env.vector4  = function(x,y,z,w) return {x=x or 0,y=y or 0,z=z or 0,w=w or 0} end

    env.math     = math
    env.string   = string
    env.table    = table
    env.pairs    = pairs
    env.ipairs   = ipairs
    env.next     = next
    env.type     = type
    env.tostring = tostring
    env.tonumber = tonumber
    env.pcall    = pcall
    env.xpcall   = xpcall
    env.error    = error
    env.assert   = assert
    env.select   = select
    env.unpack   = table.unpack
    env.rawget   = rawget
    env.rawset   = rawset
    env.rawequal = rawequal
    env.setmetatable = setmetatable
    env.getmetatable = getmetatable
    env.load     = load
    env.loadstring = load
    env.print    = function(...)
        local parts = {}
        local args = {...}
        for _, v in ipairs(args) do parts[#parts+1] = tostring(v) end
        log("print", table.concat(parts, "\t"))
    end
    env.io       = io
    env.os       = os
    env.coroutine = coroutine
    env.require  = require

    -- The metatable is already set above with write-through to _G.
    -- All env keys set via env.X = Y are already in _G (except guarded ones).
    -- Ensure the current env keys are synced to _G now:
    for k, v in pairs(env) do
        if not _g_sync_skip[k] then
            rawset(_G, k, v)
        end
    end

    return env
end

-----------------------------------------------------------------------
-- Loader de arquivo com ambiente injetado
-----------------------------------------------------------------------
function SIM.load_file(path, env, label)
    label = label or path
    local content, err = io.open(path, "r")
    if not content then
        log("LOAD_ERROR", label.." — "..tostring(err))
        return false
    end
    local src = content:read("*a")
    content:close()

    -- Remove BOM se existir
    if src:sub(1,3) == "\xEF\xBB\xBF" then src = src:sub(4) end

    local fn, compile_err = load(src, "@"..label, "t", env)
    if not fn then
        -- Tenta como binário/obfuscado
        fn, compile_err = load(src, "@"..label, "b", env)
    end
    if not fn then
        -- Última tentativa: modo misto
        fn, compile_err = load(src, "@"..label, "bt", env)
    end

    if not fn then
        log("COMPILE_ERROR", label.." — "..tostring(compile_err))
        return false
    end

    log("LOADING", label)
    local ok, run_err = pcall(fn)
    if not ok then
        log("RUNTIME_ERROR", label.." — "..tostring(run_err))
        return false
    end

    log("LOADED_OK", label)

    -- Detecta novas globals criadas por este script
    snapshot_globals(env)
    return true
end

-----------------------------------------------------------------------
-- Executa threads pendentes (pump loop simplificado)
-----------------------------------------------------------------------
function SIM.run_threads(max_ticks)
    max_ticks = max_ticks or 5
    if #_threads == 0 then return end
    log("THREAD_PUMP", "running "..#_threads.." threads, max_ticks="..max_ticks)

    for tick = 1, max_ticks do
        local alive = {}
        for _, entry in ipairs(_threads) do
            if coroutine.status(entry.co) ~= "dead" then
                local ok, wait_ms = coroutine.resume(entry.co)
                if not ok then
                    log("THREAD_ERROR", "#"..entry.id.." "..tostring(wait_ms))
                else
                    if coroutine.status(entry.co) ~= "dead" then
                        alive[#alive+1] = entry
                    end
                end
            end
        end
        _threads = alive
        if #_threads == 0 then break end
    end

    log("THREAD_PUMP", "done, "..#_threads.." threads still alive (stopped early)")
end

-----------------------------------------------------------------------
-- Dispara um evento simulado (para acionar handlers registrados)
-- Handlers that call Wait() are handled by catching the yield error
-- and logging it rather than crashing.
-----------------------------------------------------------------------
function SIM.fire_event(eventName, ...)
    local args = {...}
    log("FIRE_EVENT", '"'..eventName..'"  args='..ser(args,2))
    if _event_handlers[eventName] then
        for _, h in ipairs(_event_handlers[eventName]) do
            -- Patch Wait to be a no-op during fire_event (avoids yield-outside-coro)
            local old_wait = _G.Wait
            _G.Wait = function(ms)
                log("Wait", tostring(ms).."ms (fire_event context, skipped)")
            end
            local ok, err = pcall(h, table.unpack(args))
            _G.Wait = old_wait
            if not ok then
                log("FIRE_EVENT.ERROR", '"'..eventName..'" '..tostring(err))
            end
        end
    else
        log("FIRE_EVENT.NOHANDLER", '"'..eventName..'"')
    end
end

-----------------------------------------------------------------------
-- Simula execução de um comando
-----------------------------------------------------------------------
function SIM.run_command(env, name, source, args)
    local cmds = env._commands or {}
    if cmds[name] then
        log("RUN_COMMAND", '"/'..name..'"  src='..tostring(source)..'  args='..ser(args,1))
        local ok, err = pcall(cmds[name], source, args or {})
        if not ok then
            log("RUN_COMMAND.ERROR", '"/'..name..'" '..tostring(err))
        end
    else
        log("RUN_COMMAND.MISSING", '"/'..name..'"')
    end
end

-----------------------------------------------------------------------
-- Dispara NUI callback (simula ação do HTML)
-----------------------------------------------------------------------
function SIM.fire_nui(name, body)
    log("FIRE_NUI", '"'..name..'"  body='..ser(body,2))
    if _nui_callbacks[name] then
        local ok, err = pcall(_nui_callbacks[name], body or {}, function(resp)
            log("FIRE_NUI.RESPONSE", '"'..name..'"  resp='..ser(resp,1))
        end)
        if not ok then
            log("FIRE_NUI.ERROR", '"'..name..'" '..tostring(err))
        end
    else
        log("FIRE_NUI.NOHANDLER", '"'..name..'"')
    end
end

-----------------------------------------------------------------------
-- Relatório final
-----------------------------------------------------------------------
function SIM.report()
    log("REPORT", "═══════════════════════════════════════════")
    log("REPORT", "EVENTOS REGISTRADOS (AddEventHandler):")
    local sorted = {}
    for name in pairs(_event_handlers) do sorted[#sorted+1] = name end
    table.sort(sorted)
    for _, name in ipairs(sorted) do
        log("REPORT", "  • "..name.." ("..#_event_handlers[name].." handlers)")
    end

    log("REPORT", "NET EVENTS (RegisterNetEvent):")
    local nets = {}
    for name in pairs(_net_events) do nets[#nets+1] = name end
    table.sort(nets)
    for _, name in ipairs(nets) do
        log("REPORT", "  • "..name)
    end

    log("REPORT", "NUI CALLBACKS (RegisterNuiCallback):")
    local nuis = {}
    for name in pairs(_nui_callbacks) do nuis[#nuis+1] = name end
    table.sort(nuis)
    for _, name in ipairs(nuis) do
        log("REPORT", "  • "..name)
    end

    log("REPORT", "═══════════════════════════════════════════")

    if _log_fh then _log_fh:close() end
end

return SIM
