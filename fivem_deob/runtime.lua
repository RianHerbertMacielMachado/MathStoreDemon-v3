-----------------------------------------------------------------------
-- fivem_deob/runtime.lua
-- Motor de simulação do ambiente FiveM em Lua 5.4 puro.
-- Versão standalone: pode ser copiado para qualquer projeto.
--
-- Uso:
--   local RT = require("fivem_deob.runtime")
--   local env = RT.new_env("CLIENT")
--   RT.load_file("myscript.lua", env)
--   RT.run_threads(env, 5)
--   local data = RT.get_data(env)
-----------------------------------------------------------------------

local RT = {}

-- ── Serializer seguro (sem ciclos) ─────────────────────────────────
local function ser(v, depth, seen)
    depth = depth or 0; seen = seen or {}
    if depth > 4 then return "..." end
    local t = type(v)
    if t == "nil"      then return "nil" end
    if t == "boolean"  then return tostring(v) end
    if t == "number"   then return tostring(v) end
    if t == "string"   then
        local s = v:gsub("\n","\\n"):gsub("\r","\\r")
        return '"'..(#s>200 and s:sub(1,200).."…" or s)..'"'
    end
    if t == "function" then return "<fn>" end
    if t == "table" then
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local parts, n = {}, 0
        for k,val in pairs(v) do
            n = n+1; if n > 20 then parts[#parts+1]="..."; break end
            local ks = type(k)=="string" and k or ("["..tostring(k).."]")
            parts[#parts+1] = ks.."="..ser(val, depth+1, seen)
        end
        seen[v] = nil
        return "{"..table.concat(parts,", ").."}"
    end
    return "<"..t..">"
end
RT.ser = ser

-- ── Cria um novo ambiente de simulação ─────────────────────────────
function RT.new_env(side, opts)
    opts = opts or {}
    local resource = opts.resource or "unknown"
    local log_fn   = opts.log      or function() end

    -- ── Dados coletados (acessíveis via RT.get_data) ────────────────
    local data = {
        side            = side,
        events          = {},   -- { name, handler_count, fired_args }
        net_events      = {},   -- set
        commands        = {},   -- { name, handler, restricted }
        nui_callbacks   = {},   -- { name, handler }
        server_events   = {},   -- TriggerServerEvent calls
        client_events   = {},   -- TriggerClientEvent calls
        natives_called  = {},   -- { native_name = count }
        models          = {},   -- GetHashKey / RequestModel calls
        anim_dicts      = {},   -- RequestAnimDict calls
        anim_plays      = {},   -- TaskPlayAnim calls  { dict, clip, ped, flag }
        keybinds        = {},   -- RegisterKeyMapping calls
        state_bag_keys  = {},   -- AddStateBagChangeHandler keys
        http_requests   = {},   -- PerformHttpRequest calls
        globals_set     = {},   -- globals novos definidos pelos scripts
        threads         = {},   -- coroutines pendentes
        thread_count    = 0,
        event_handlers  = {},   -- [name] = { fn, ... }
        nui_handler_map = {},   -- [name] = fn
        cmd_handler_map = {},   -- [name] = fn
        attach_calls    = {},   -- AttachEntityToEntity calls
        bones_used      = {},   -- GetPedBoneIndex / bone IDs
        convars_read    = {},   -- GetConvar calls
        exports_called  = {},   -- exports.resource:fn() calls
        state_bag_handlers = {},
        -- ── Per-handler call tracking (para reconstrução real) ─────
        handler_calls   = {},   -- [eventName] = { natives=[], triggers=[], models=[], anims=[], entities_created=0, ... }
    }

    -- ── Contexto do handler em execução (para rastrear chamadas) ────
    local _current_handler = nil  -- nome do evento sendo executado

    local function track(category, value)
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc[category] = hc[category] or {}
                table.insert(hc[category], value)
            end
        end
    end

    -- ── Helpers internos ────────────────────────────────────────────
    local function native(name, ...)
        data.natives_called[name] = (data.natives_called[name] or 0) + 1
        log_fn("NATIVE", name.."("..ser({...},1)..")")
        track("natives", { name=name, args={...} })
    end

    -- ── Constrói env ────────────────────────────────────────────────
    local env = {}

    -- Copia globals Lua padrão
    for k,v in pairs(_G) do env[k] = v end

    -- Write-through: env → _G  (crítico para Luraph inner VMs)
    local _skip = { _G=true, package=true, io=true, os=true, debug=true }
    setmetatable(env, {
        __index = function(t, k)
            return rawget(t,k) or rawget(_G, k)
        end,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            if not _skip[k] then rawset(_G, k, v) end
        end,
    })

    -- Sync inicial
    for k,v in pairs(env) do
        if not _skip[k] then rawset(_G, k, v) end
    end

    -- Armazena referência ao data para acesso externo
    env.__deob_data = data

    -- ── FiveM globals ───────────────────────────────────────────────
    env.GetCurrentResourceName = function() return resource end
    env.GetResourceState = function(name)
        local present = opts.resources or {}
        return present[name] and "started" or "missing"
    end
    env.LoadResourceFile = function(res, file)
        log_fn("LoadResourceFile", res.."/"..file)
        return nil
    end
    env.GetConvar = function(name, default)
        data.convars_read[name] = default
        log_fn("GetConvar", name.."="..tostring(default))
        return default or ""
    end
    env.GetConvarInt = function(name, default)
        data.convars_read[name] = default
        return default or 0
    end
    env.GetGameTimer = function() return math.floor(os.clock()*1000) end
    env.GetNetworkTime = function() return math.floor(os.clock()*1000) end
    env.GetFrameTime = function() return 0.016 end
    env.os = os

    -- ── Wait / Threads ──────────────────────────────────────────────
    env.Wait = function(ms)
        local co = coroutine.running()
        if co then coroutine.yield(ms)
        else log_fn("Wait", tostring(ms).."ms (main, skip)") end
    end

    env.CreateThread = function(fn)
        data.thread_count = data.thread_count + 1
        local id = data.thread_count
        log_fn("CreateThread", "#"..id)
        local co = coroutine.create(function()
            local ok, err = pcall(fn)
            if not ok then log_fn("Thread.ERROR", "#"..id.." "..tostring(err)) end
        end)
        data.threads[#data.threads+1] = { id=id, co=co }
        return co
    end
    env.Citizen = {
        CreateThread = env.CreateThread,
        Wait        = env.Wait,
        Trace       = function(msg) log_fn("Citizen.Trace", tostring(msg)) end,
    }

    -- ── Eventos ─────────────────────────────────────────────────────
    env.AddEventHandler = function(eventName, handler)
        log_fn("AddEventHandler", '"'..eventName..'"')
        if not data.event_handlers[eventName] then
            data.event_handlers[eventName] = {}
            data.events[#data.events+1] = { name=eventName, args={} }
            -- Inicializa rastreamento por handler
            data.handler_calls[eventName] = {
                natives         = {},
                triggers_server = {},
                triggers_client = {},
                models          = {},
                anims           = {},
                anims_played    = {},
                entities_created = 0,
                entities_deleted = 0,
                attach_calls    = {},
                commands_fired  = {},
                http_calls      = {},
                state_set       = {},
                nui_messages    = {},
                convars         = {},
            }
        end
        -- Wraps handler para rastrear chamadas durante execução
        local orig = handler
        local wrapped = function(...)
            local prev = _current_handler
            _current_handler = eventName
            local ok, err = pcall(orig, ...)
            _current_handler = prev
            if not ok then
                log_fn("Handler.ERROR", '"'..eventName..'" '..tostring(err))
            end
        end
        table.insert(data.event_handlers[eventName], wrapped)
    end

    env.RegisterNetEvent = function(eventName, handler)
        log_fn("RegisterNetEvent", '"'..eventName..'"')
        data.net_events[eventName] = true
        if handler then env.AddEventHandler(eventName, handler) end
    end

    local function fire_handlers(eventName, args)
        if data.event_handlers[eventName] then
            local old_wait = rawget(_G, "Wait")
            rawset(_G, "Wait", function(ms) end)   -- no-op Wait em handlers
            for _, h in ipairs(data.event_handlers[eventName]) do
                local ok, err = pcall(h, table.unpack(args))
                if not ok then log_fn("Event.ERROR", '"'..eventName..'" '..tostring(err)) end
            end
            rawset(_G, "Wait", old_wait)
        end
    end

    env.TriggerEvent = function(eventName, ...)
        log_fn("TriggerEvent", '"'..eventName..'"')
        fire_handlers(eventName, {...})
    end

    env.TriggerServerEvent = function(eventName, ...)
        local a = {...}
        log_fn("TriggerServerEvent", '"'..eventName..'" args='..ser(a,2))
        data.server_events[#data.server_events+1] = { name=eventName, args=a }
        track("triggers_server", { name=eventName, args=a })
    end

    env.TriggerClientEvent = function(eventName, target, ...)
        local a = {...}
        local tgt = target==-1 and "ALL" or tostring(target)
        log_fn("TriggerClientEvent", '"'..eventName..'" tgt='..tgt)
        data.client_events[#data.client_events+1] = { name=eventName, target=tgt, args=a }
        track("triggers_client", { name=eventName, target=tgt, args=a })
        fire_handlers(eventName, a)
    end

    env.TriggerLatentClientEvent = function(eventName, target, bps, ...)
        log_fn("TriggerLatentClientEvent", '"'..eventName..'"')
        track("triggers_client", { name=eventName, target=tostring(target), latent=true })
    end

    -- ── NUI ─────────────────────────────────────────────────────────
    env.SendNuiMessage = function(json_str)
        log_fn("SendNuiMessage", tostring(json_str))
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.nui_messages = hc.nui_messages or {}
                table.insert(hc.nui_messages, tostring(json_str))
            end
        end
    end
    env.RegisterNuiCallback = function(name, handler)
        log_fn("RegisterNuiCallback", '"'..name..'"')
        data.nui_callbacks[#data.nui_callbacks+1] = { name=name }
        data.nui_handler_map[name] = handler
    end
    env.RegisterNUICallback = env.RegisterNuiCallback  -- alias maiúsculo
    env.SetNuiFocus = function(hasFocus, hasCursor)
        native("SetNuiFocus", hasFocus, hasCursor)
    end
    env.SetNuiFocusKeepInput = function(toggle) native("SetNuiFocusKeepInput", toggle) end

    -- ── HTTP ────────────────────────────────────────────────────────
    env.PerformHttpRequest = function(url, cb, method, body, headers)
        log_fn("PerformHttpRequest", (method or "GET").." "..tostring(url))
        local req = { url=url, method=method or "GET", body=body }
        data.http_requests[#data.http_requests+1] = req
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.http_calls = hc.http_calls or {}
                table.insert(hc.http_calls, req)
            end
        end
        if cb then
            local fake = '{"status":"ok","authorized":true}'
            log_fn("HTTP.RESPONSE", "200 "..fake)
            pcall(cb, 200, fake, {})
        end
    end

    -- ── Comandos ────────────────────────────────────────────────────
    env.RegisterCommand = function(name, handler, restricted)
        log_fn("RegisterCommand", '"/'..name..'" restricted='..tostring(restricted))
        data.commands[#data.commands+1] = {
            name=name, restricted=restricted or false
        }
        data.cmd_handler_map[name] = handler
    end
    env._commands = data.cmd_handler_map

    -- ── Permissões ──────────────────────────────────────────────────
    env.IsPlayerAceAllowed = function(src, ace) return false end
    env.IsPrincipalAceAllowed = function(p, ace) return false end

    -- ── Jogadores ───────────────────────────────────────────────────
    local _players = opts.players or {
        { id=1, name="TestPlayer1", identifiers={"license:abc","steam:111"} },
        { id=2, name="TestPlayer2", identifiers={"license:def","steam:222"} },
    }
    env.GetPlayers = function()
        local ids={}; for _,p in ipairs(_players) do ids[#ids+1]=tostring(p.id) end
        return ids
    end
    env.GetPlayerName = function(src)
        for _,p in ipairs(_players) do if p.id==tonumber(src) then return p.name end end
        return "Unknown"
    end
    env.GetNumPlayerIdentifiers = function(src)
        for _,p in ipairs(_players) do if p.id==tonumber(src) then return #p.identifiers end end
        return 0
    end
    env.GetPlayerIdentifier = function(src, idx)
        for _,p in ipairs(_players) do
            if p.id==tonumber(src) then return p.identifiers[idx+1] end
        end
        return nil
    end
    env.GetPlayerPed = function(src) return 1000+(tonumber(src) or 0) end
    env.GetPlayerFromServerId = function(sid) return tonumber(sid) or 0 end
    env.GetPlayerServerId = function(player) return 1 end
    env.PlayerId = function() return 1 end
    env.PlayerPedId = function() return 1001 end

    -- ── StateBag ────────────────────────────────────────────────────
    local _sbags = setmetatable({}, {
        __newindex = function(t, k, v)
            rawset(t,k,v)
            for _, h in ipairs(data.state_bag_handlers) do
                if h.key == k then pcall(h.fn,'player:0',k,v,#tostring(v or ''),false) end
            end
        end,
    })
    env.AddStateBagChangeHandler = function(keyname, bagName, handler)
        log_fn("AddStateBagChangeHandler", keyname.."/"..tostring(bagName))
        data.state_bag_keys[#data.state_bag_keys+1] = { key=keyname, bag=tostring(bagName or '') }
        table.insert(data.state_bag_handlers, {key=keyname, fn=handler})
    end
    env.LocalPlayer = { state = _sbags }
    env.Player = function(id) return { state = _sbags } end

    -- ── Entidades ───────────────────────────────────────────────────
    local _eid = 5000
    env.CreateObject = function(model, x, y, z, ...)
        _eid = _eid + 1
        log_fn("CreateObject", "model="..ser(model,0).." eid=".._eid)
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then hc.entities_created = (hc.entities_created or 0) + 1 end
        end
        return _eid
    end
    env.CreateObjectNoOffset = env.CreateObject
    env.DeleteEntity = function(e)
        log_fn("DeleteEntity", "eid="..tostring(e))
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then hc.entities_deleted = (hc.entities_deleted or 0) + 1 end
        end
    end
    env.DeleteObject = env.DeleteEntity
    env.DoesEntityExist = function(e) return (e or 0) > 0 end
    env.IsEntityAttached = function(e) return false end
    env.DetachEntity = function(e,...) native("DetachEntity", e) end
    env.SetEntityVisible = function(e,v) native("SetEntityVisible",e,v) end
    env.SetEntityCollision = function(e,...) end
    env.SetEntityAsMissionEntity = function(e,...) end
    env.IsEntityAMissionEntity = function(e) return true end
    env.SetEntityAlpha = function(e,a,...) native("SetEntityAlpha",e,a) end
    env.SetEntityLodDist = function(e,d) end
    env.PlaceObjectOnGroundProperly = function(e) end
    env.SetEntityCoordsNoOffset = function(e,...) end
    env.SetEntityCoords = function(e,x,y,z,...)
        native("SetEntityCoords",e,x,y,z)
        track("natives", { name="SetEntityCoords", args={e,x,y,z} })
    end
    env.GetOffsetFromEntityInWorldCoords = function(e,x,y,z) return x or 0,y or 0,z or 0 end
    env.IsEntityInAir = function(e) return false end
    env.IsEntityVisible = function(e) return true end
    env.IsEntityOnScreen = function(e) return true end
    env.IsEntityDead = function(e) return false end
    env.GetEntitySpeed = function(e) return 0.0 end
    env.GetEntityHeading = function(e) return 0.0 end
    env.SetEntityHeading = function(e,h) native("SetEntityHeading",e,h) end
    env.FreezeEntityPosition = function(e,f) native("FreezeEntityPosition",e,f) end
    env.SetEntityVelocity = function(e,...) native("SetEntityVelocity",e,...) end
    env.GetEntityVelocity = function(e) return env.vector3(0,0,0) end
    env.GetEntityType = function(e) return 1 end
    env.GetEntityModel = function(e) return 0 end
    env.IsEntityAnObject = function(e) return true end
    env.IsEntityAPed = function(e) return false end
    env.IsEntityAVehicle = function(e) return false end
    env.GetEntityForwardVector = function(e) return env.vector3(0,1,0) end
    env.GetEntityUpVector = function(e) return env.vector3(0,0,1) end
    env.GetEntityRightVector = function(e) return env.vector3(1,0,0) end
    env.ApplyForceToEntity = function(...) end
    env.SetPedToRagdoll = function(...) end
    env.SetEntityNoCollisionEntity = function(e1,e2,t) native("SetEntityNoCollisionEntity",e1,e2,t) end

    env.AttachEntityToEntity = function(entity, entityTo, boneIndex, ox, oy, oz, rx, ry, rz, ...)
        local call = {
            entity=entity, entityTo=entityTo, bone=boneIndex,
            offset={ox or 0,oy or 0,oz or 0}, rot={rx or 0,ry or 0,rz or 0}
        }
        data.attach_calls[#data.attach_calls+1] = call
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.attach_calls = hc.attach_calls or {}
                table.insert(hc.attach_calls, call)
            end
        end
        log_fn("AttachEntityToEntity",
            string.format("eid=%d to=%d bone=%d off=(%.2f,%.2f,%.2f) rot=(%.2f,%.2f,%.2f)",
            entity or 0, entityTo or 0, boneIndex or 0,
            ox or 0, oy or 0, oz or 0, rx or 0, ry or 0, rz or 0))
    end

    env.GetEntityCoords = function(entity)
        return env.vector3(100.0, 200.0, 30.0)
    end
    env.GetEntityRotation = function(entity, ...) return env.vector3(0,0,0) end
    env.SetEntityRotation = function(entity, rx, ry, rz, ...) native("SetEntityRotation",entity,rx,ry,rz) end
    env.GetEntityBoneIndexByName = function(entity, boneName) return 0 end
    env.GetWorldPositionOfEntityBone = function(entity, boneIndex) return env.vector3(0,0,0) end
    env.GetGroundZFor_3dCoord = function(x,y,z,...) return true,(z or 0)-1.0 end

    -- ── Network ─────────────────────────────────────────────────────
    env.NetworkGetNetworkIdFromEntity = function(e) return (e or 0)+10000 end
    env.NetworkGetEntityFromNetworkId = function(n) return (n or 0)-10000 end
    env.NetworkDoesEntityExistWithNetworkId = function(n) return true end
    env.NetworkIsSessionStarted = function() return true end
    env.NetworkIsEntityNetworked = function(e) return true end
    env.NetworkRequestControlOfNetworkId = function(n) end
    env.NetworkSetNetworkIdCanMigrate = function(n,b) end
    env.NetworkSetEntityInvisibleToNetwork = function(e,b) end
    env.SetNetworkIdCanMigrate = function(...) end
    env.SetNetworkIdExistsOnAllMachines = function(...) end

    -- ── Models / Streaming ──────────────────────────────────────────
    env.RequestModel = function(model)
        data.models[ser(model,0)] = true
        log_fn("RequestModel", ser(model,0))
        track("models", ser(model,0))
    end
    env.HasModelLoaded = function(m) return true end
    env.IsModelValid = function(m) return true end
    env.SetModelAsNoLongerNeeded = function(m) end
    env.GetHashKey = function(model)
        if type(model)=="string" then
            data.models[model] = true
            log_fn("GetHashKey", '"'..model..'"')
            track("models", model)
            local h=0
            for i=1,#model do h=(h*31+string.byte(model,i))&0xFFFFFFFF end
            return h
        end
        return model
    end

    -- ── Animações ───────────────────────────────────────────────────
    env.RequestAnimDict = function(dict)
        data.anim_dicts[dict] = true
        log_fn("RequestAnimDict", '"'..tostring(dict)..'"')
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.anims = hc.anims or {}
                if not (function() for _,v in ipairs(hc.anims) do if v==dict then return true end end end)() then
                    table.insert(hc.anims, dict)
                end
            end
        end
    end
    env.HasAnimDictLoaded = function(d) return true end
    env.RemoveAnimDict = function(d)
        -- Também registra em anim_dicts — se foi removido, foi usado
        if type(d) == "string" and d ~= "" then
            data.anim_dicts[d] = true
        end
        log_fn("RemoveAnimDict", '"'..tostring(d)..'"')
    end
    env.TaskPlayAnim = function(ped, animDict, animName, blendIn, blendOut, duration, flag, ...)
        local play = {
            dict=animDict, clip=animName, ped=ped, flag=flag, duration=duration
        }
        data.anim_plays[#data.anim_plays+1] = play
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.anims_played = hc.anims_played or {}
                table.insert(hc.anims_played, play)
            end
        end
        log_fn("TaskPlayAnim",
            string.format('ped=%d dict="%s" clip="%s" dur=%d flag=%d',
            ped or 0, tostring(animDict), tostring(animName), duration or -1, flag or 0))
    end
    env.TaskPlayAnimAdvanced = function(ped, animDict, animName, ...)
        local play = { dict=animDict, clip=animName, ped=ped }
        data.anim_plays[#data.anim_plays+1] = play
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.anims_played = hc.anims_played or {}
                table.insert(hc.anims_played, play)
            end
        end
        log_fn("TaskPlayAnimAdvanced", string.format('ped=%d dict="%s" clip="%s"', ped or 0, tostring(animDict), tostring(animName)))
    end
    env.PlayAnimOnEntity = function(entity, animDict, animName, ...)
        local play = { dict=animDict, clip=animName, entity=entity }
        data.anim_plays[#data.anim_plays+1] = play
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.anims_played = hc.anims_played or {}
                table.insert(hc.anims_played, play)
            end
        end
        log_fn("PlayAnimOnEntity", string.format('eid=%d dict="%s" clip="%s"', entity or 0, tostring(animDict), tostring(animName)))
    end
    env.StopAnimTask = function(ped, animDict, animName, ...)
        log_fn("StopAnimTask", string.format('ped=%d dict="%s" clip="%s"', ped or 0, tostring(animDict), tostring(animName)))
    end
    env.IsEntityPlayingAnim = function(e,d,a,...) return false end
    env.GetEntityAnimCurrentTime = function(...) return 0.0 end
    env.SetEntityAnimCurrentTime = function(...) end
    env.GetAnimCurrentTime = function(ped, dict, anim) return 0.0 end
    env.SetAnimCurrentTime = function(ped, dict, anim, t) end
    env.GetAnimDuration = function(dict, anim) return 2.0 end
    env.RequestAnimSet = function(s) end
    env.HasAnimSetLoaded = function(s) return true end

    -- ── Ped ─────────────────────────────────────────────────────────
    env.GetPedBoneIndex = function(ped, boneId)
        data.bones_used[tostring(boneId)] = true
        log_fn("GetPedBoneIndex", "ped="..tostring(ped).." boneId="..tostring(boneId))
        return boneId
    end
    env.GetPedBoneCoords = function(ped, boneIndex, ...)
        log_fn("GetPedBoneCoords", "ped="..tostring(ped).." bone="..tostring(boneIndex))
        return env.vector3(0,0,0)
    end
    env.IsPedInAnyVehicle = function(ped, ...) return false end
    env.IsPedOnFoot = function(ped) return true end
    env.IsPedFalling = function(ped) return false end
    env.IsPedSwimming = function(ped) return false end
    env.IsPedClimbing = function(ped) return false end
    env.IsPedRunning = function(ped) return false end
    env.IsPedSprinting = function(ped) return false end
    env.IsPedStill = function(ped) return true end
    env.IsPedJumping = function(ped) return false end
    env.IsPedMale = function() return true end
    env.GetPedMaxMoveBlendRatio = function(ped) return 0.0 end
    env.GetVehiclePedIsIn = function(ped,...) return 0 end
    env.SetPedComponentVariation = function(...) end
    env.SetPedCanPlayGestureAnims = function(...) end
    env.SetPedEnableWeaponBlocking = function(...) end
    env.SetPedHelmet = function(...) end
    env.SetPedResetFlag = function(...) end
    env.SetPedClothingSpawnModifier = function(...) end
    env.SetPedFleeAttributes = function(...) end
    env.SetPedCombatAttributes = function(...) end
    env.SetPedMotionBlur = function(ped, toggle) end
    env.SetPedGravity = function(ped, toggle) native("SetPedGravity", ped, toggle) end
    env.ResetPedMovementClipset = function(ped, p1) native("ResetPedMovementClipset", ped) end
    env.SetPedMovementClipset = function(ped, clipset, p2) native("SetPedMovementClipset", ped, clipset) end
    env.GetPedDrawableVariation = function(...) return 0 end
    env.GetPedTextureVariation = function(...) return 0 end
    env.ClearPedTasks = function(ped) native("ClearPedTasks", ped) end
    env.ClearPedTasksImmediately = function(ped) native("ClearPedTasksImmediately", ped) end
    env.TaskTurnPedToFaceCoord = function(...) end
    env.SetPedConfigFlag = function(ped, flagId, value) native("SetPedConfigFlag", ped, flagId, value) end
    env.GetPedConfigFlag = function(ped, flagId, p2) return false end
    env.GetSelectedPedWeapon = function(ped) return 0 end

    -- ── Keybinds ────────────────────────────────────────────────────
    env.RegisterKeyMapping = function(command, description, inputType, inputName)
        log_fn("RegisterKeyMapping",
            string.format('cmd="/%s" desc="%s" type="%s" key="%s"',
            tostring(command), tostring(description), tostring(inputType), tostring(inputName)))
        data.keybinds[#data.keybinds+1] = {
            command=command, description=description,
            inputType=inputType, inputName=inputName
        }
    end

    -- ── Controls ────────────────────────────────────────────────────
    env.IsControlPressed = function(i,c) return false end
    env.IsControlJustPressed = function(i,c) return false end
    env.IsDisabledControlPressed = function(i,c) return false end
    env.IsControlJustReleased = function(i,c) return false end
    env.DisableControlAction = function(...) end
    env.EnableControlAction = function(...) end
    env.DisableAllControlActions = function(...) end

    -- ── Camera ──────────────────────────────────────────────────────
    env.GetFollowPedCamHeading = function() return 0.0 end
    env.GetGameplayCamRelativePitch = function() return 0.0 end
    env.GetGameplayCamRelativeHeading = function() return 0.0 end
    env.SetGameplayCamRelativeHeading = function(...) end
    env.SetGameplayCamRelativePitch = function(...) end
    env.GetFinalRenderedCamCoord = function() return env.vector3(0,0,0) end
    env.GetFinalRenderedCamRot = function(...) return env.vector3(0,0,0) end

    -- ── HUD / Screen ────────────────────────────────────────────────
    env.IsScreenFadedOut = function() return false end
    env.IsScreenFadingOut = function() return false end
    env.IsScreenFadingIn = function() return false end
    env.SetTextScale = function(...) end; env.SetTextFont = function(...) end
    env.SetTextProportional = function(...) end; env.SetTextColour = function(...) end
    env.SetTextEntry = function(...) end; env.SetTextCentre = function(...) end
    env.SetTextOutline = function() end; env.SetTextDropshadow = function(...) end
    env.DrawText = function(...) end; env.DrawText3D = function(...) end
    env.BeginTextCommandDisplayText = function(...) end
    env.EndTextCommandDisplayText = function(...) end
    env.BeginTextCommandGetWidth = function(...) end
    env.EndTextCommandGetWidth = function(...) return 0.1 end
    env.BeginTextCommandThefeedPost = function(...) end
    env.EndTextCommandThefeedPostTicker = function(...) end
    env.ThefeedSetNextPostBackgroundColor = function(...) end
    env.SetNotificationMessage = function(...) end
    env.AddTextComponentSubstringKeyboardDisplay = function(...) end
    env.AddTextComponentSubstringPlayerName = function(...) end
    env.SetTextComponentFormat = function(...) end
    env.DrawNotification = function(...) end
    env.BeginTextCommandDisplayHelp = function(...) end
    env.EndTextCommandDisplayHelp = function(...) end

    -- ── Gameplay ────────────────────────────────────────────────────
    env.SetGravityLevel = function(level) native("SetGravityLevel", level) end
    env.GetGravityLevel = function() return 9 end
    env.Vdist = function(x1,y1,z1,x2,y2,z2)
        local dx,dy,dz=(x2 or 0)-(x1 or 0),(y2 or 0)-(y1 or 0),(z2 or 0)-(z1 or 0)
        return math.sqrt(dx*dx+dy*dy+dz*dz)
    end
    env.Vdist2 = function(x1,y1,z1,x2,y2,z2)
        local dx,dy,dz=(x2 or 0)-(x1 or 0),(y2 or 0)-(y1 or 0),(z2 or 0)-(z1 or 0)
        return dx*dx+dy*dy+dz*dz
    end
    env.GetVehicleModel = function(v) return 0 end

    -- ── Particles ───────────────────────────────────────────────────
    env.RequestNamedPtfxAsset = function(fx) end
    env.HasNamedPtfxAssetLoaded = function(fx) return true end
    env.UseParticleFxAssetNextCall = function(fx) end
    env.StartParticleFxLoopedAtCoord = function(...) return 0 end
    env.StopParticleFxLooped = function(...) end
    env.RemoveParticleFx = function(...) end

    -- ── Resource lifecycle ──────────────────────────────────────────
    env.GetResourceMetadata = function(r,k,i) return nil end
    env.StopResource = function(name) log_fn("StopResource", name) end

    -- ── ACE / vRP / ox_lib stubs ────────────────────────────────────
    env.vRP = {
        getUserId     = function(args) return 1 end,
        hasPermission = function(args) return true end,
        hasGroup      = function(args) return true end,
    }
    env.exports = setmetatable({}, {
        __index = function(t, resource)
            data.exports_called[resource] = data.exports_called[resource] or {}
            return setmetatable({}, {
                __index = function(t2, fn)
                    return function(...)
                        data.exports_called[resource][fn] = true
                        log_fn("exports", resource..":"..fn.."("..ser({...},1)..")")
                        return nil
                    end
                end,
            })
        end,
    })
    env.lib = nil
    env.msgpack = { pack=function(v) return tostring(v) end, unpack=function(v) return v end }
    env.module = function(name, ...) log_fn("module", tostring(name).." (Lua5.1, no-op)") end

    -- ── JSON ────────────────────────────────────────────────────────
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
            local is_arr, n = true, 0
            for k in pairs(v) do
                n=n+1
                if type(k)~="number" or k~=math.floor(k) then is_arr=false; break end
            end
            if is_arr and n==#v then
                local parts={}
                for _,val in ipairs(v) do parts[#parts+1]=json_encode(val,depth+1) end
                return "["..table.concat(parts,",").."]"
            else
                local parts={}
                for k,val in pairs(v) do
                    parts[#parts+1]='"'..tostring(k)..'":'..json_encode(val,depth+1)
                end
                return "{"..table.concat(parts,",").."}"
            end
        end
        return '"<'..t..'>"'
    end

    local function json_decode(s)
        if s == nil then return nil end
        if type(s) ~= "string" then return s end
        if s == "" or s == "null" then return nil end
        local ok, clean = pcall(function()
            return s:gsub("null","false")
        end)
        if not ok then return nil end
        local fn = load("return "..clean)
        if fn then
            local ok2, val = pcall(fn)
            if ok2 then return val end
        end
        return nil
    end

    env.json = { encode=json_encode, decode=json_decode }

    -- ── Vectors com metatables completas ────────────────────────────
    local function make_v3(x, y, z)
        x,y,z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
        local mt = {}
        mt.__index = function(t, k)
            if k=='x' then return rawget(t,'_x')
            elseif k=='y' then return rawget(t,'_y')
            elseif k=='z' then return rawget(t,'_z') end
        end
        mt.__newindex = function(t,k,v) rawset(t,k,v) end
        mt.__add = function(a,b)
            local bx=type(b)=='table' and (b.x or rawget(b,'_x') or 0) or (type(b)=='number' and b or 0)
            local by=type(b)=='table' and (b.y or rawget(b,'_y') or 0) or (type(b)=='number' and b or 0)
            local bz=type(b)=='table' and (b.z or rawget(b,'_z') or 0) or (type(b)=='number' and b or 0)
            return make_v3((rawget(a,'_x') or 0)+bx,(rawget(a,'_y') or 0)+by,(rawget(a,'_z') or 0)+bz)
        end
        mt.__sub = function(a,b)
            local bx=type(b)=='table' and (b.x or rawget(b,'_x') or 0) or 0
            local by=type(b)=='table' and (b.y or rawget(b,'_y') or 0) or 0
            local bz=type(b)=='table' and (b.z or rawget(b,'_z') or 0) or 0
            return make_v3((rawget(a,'_x') or 0)-bx,(rawget(a,'_y') or 0)-by,(rawget(a,'_z') or 0)-bz)
        end
        mt.__mul = function(a,b)
            if type(b)=='number' then
                return make_v3((rawget(a,'_x') or 0)*b,(rawget(a,'_y') or 0)*b,(rawget(a,'_z') or 0)*b)
            elseif type(a)=='number' then
                return make_v3(a*(rawget(b,'_x') or 0),a*(rawget(b,'_y') or 0),a*(rawget(b,'_z') or 0))
            end
            return make_v3(0,0,0)
        end
        mt.__div = function(a,b)
            if type(b)=='number' and b~=0 then
                return make_v3((rawget(a,'_x') or 0)/b,(rawget(a,'_y') or 0)/b,(rawget(a,'_z') or 0)/b)
            end
            return make_v3(0,0,0)
        end
        mt.__unm = function(a)
            return make_v3(-(rawget(a,'_x') or 0),-(rawget(a,'_y') or 0),-(rawget(a,'_z') or 0))
        end
        mt.__len = function(a)
            local ax,ay,az=rawget(a,'_x') or 0,rawget(a,'_y') or 0,rawget(a,'_z') or 0
            return math.sqrt(ax*ax+ay*ay+az*az)
        end
        mt.__lt = function(a,b)
            local la=math.sqrt((rawget(a,'_x') or 0)^2+(rawget(a,'_y') or 0)^2+(rawget(a,'_z') or 0)^2)
            local lb=type(b)=='number' and b or math.sqrt((rawget(b,'_x') or 0)^2+(rawget(b,'_y') or 0)^2+(rawget(b,'_z') or 0)^2)
            return la < lb
        end
        mt.__le = function(a,b)
            local la=math.sqrt((rawget(a,'_x') or 0)^2+(rawget(a,'_y') or 0)^2+(rawget(a,'_z') or 0)^2)
            local lb=type(b)=='number' and b or math.sqrt((rawget(b,'_x') or 0)^2+(rawget(b,'_y') or 0)^2+(rawget(b,'_z') or 0)^2)
            return la <= lb
        end
        mt.__eq = function(a,b)
            if type(b)=='number' then
                local la=math.sqrt((rawget(a,'_x') or 0)^2+(rawget(a,'_y') or 0)^2+(rawget(a,'_z') or 0)^2)
                return la==b
            end
            return (rawget(a,'_x') or 0)==(rawget(b,'_x') or 0)
               and (rawget(a,'_y') or 0)==(rawget(b,'_y') or 0)
               and (rawget(a,'_z') or 0)==(rawget(b,'_z') or 0)
        end
        mt.__tostring = function(a)
            return string.format('vector3(%g, %g, %g)',rawget(a,'_x') or 0,rawget(a,'_y') or 0,rawget(a,'_z') or 0)
        end
        return setmetatable({_x=x,_y=y,_z=z}, mt)
    end

    env.vector3 = make_v3
    env.vector2 = function(x,y)
        return setmetatable({x=x or 0,y=y or 0},{
            __tostring=function(a) return string.format('vector2(%g,%g)',a.x,a.y) end,
            __add=function(a,b) return env.vector2((a.x or 0)+(b.x or 0),(a.y or 0)+(b.y or 0)) end,
        })
    end
    env.vector4 = function(x,y,z,w) return {x=x or 0,y=y or 0,z=z or 0,w=w or 0} end

    -- ── Misc padrão Lua (garante presença) ──────────────────────────
    env.math=math; env.string=string; env.table=table
    env.pairs=pairs; env.ipairs=ipairs; env.next=next
    env.type=type; env.tostring=tostring; env.tonumber=tonumber
    env.pcall=pcall; env.xpcall=xpcall; env.error=error
    env.assert=assert; env.select=select; env.unpack=table.unpack
    env.rawget=rawget; env.rawset=rawset; env.rawequal=rawequal
    env.setmetatable=setmetatable; env.getmetatable=getmetatable
    env.load=load; env.loadstring=load
    env.print=function(...)
        local parts={}; for _,v in ipairs({...}) do parts[#parts+1]=tostring(v) end
        log_fn("print", table.concat(parts,"\t"))
    end
    env.io=io; env.os=os; env.coroutine=coroutine; env.require=require
    env.cache = { ped=1001, vehicle=nil, seat=nil, serverId=1, resource=resource }

    return env
end

-- ── Carrega um arquivo no ambiente ─────────────────────────────────
function RT.load_file(path, env, label)
    label = label or path
    local f, err = io.open(path, "r")
    if not f then return false, "cannot open: "..tostring(err) end
    local src = f:read("*a"); f:close()
    if src:sub(1,3)=="\xEF\xBB\xBF" then src=src:sub(4) end  -- BOM

    local fn, cerr = load(src, "@"..label, "t", env)
    if not fn then fn, cerr = load(src, "@"..label, "bt", env) end
    if not fn then return false, "compile error: "..tostring(cerr) end

    local ok, rerr = pcall(fn)
    if not ok then return false, "runtime error: "..tostring(rerr) end
    return true
end

-- ── Pump de threads ─────────────────────────────────────────────────
function RT.run_threads(env, max_ticks)
    max_ticks = max_ticks or 4
    local data = env.__deob_data
    if not data or #data.threads == 0 then return end

    for tick = 1, max_ticks do
        local alive = {}
        for _, entry in ipairs(data.threads) do
            if coroutine.status(entry.co) ~= "dead" then
                local ok, w = coroutine.resume(entry.co)
                if not ok then
                    local log_fn = data._log_fn or function() end
                    log_fn("Thread.ERROR", "#"..entry.id.." "..tostring(w))
                elseif coroutine.status(entry.co) ~= "dead" then
                    alive[#alive+1] = entry
                end
            end
        end
        data.threads = alive
        if #data.threads == 0 then break end
    end
end

-- ── Dispara um evento ────────────────────────────────────────────────
function RT.fire_event(env, eventName, ...)
    local data = env.__deob_data
    local args = {...}
    if data.event_handlers[eventName] then
        local old_wait = rawget(_G, "Wait")
        rawset(_G, "Wait", function(ms) end)
        for _, h in ipairs(data.event_handlers[eventName]) do
            local ok, err = pcall(h, table.unpack(args))
            if not ok then
                -- silently log
            end
        end
        rawset(_G, "Wait", old_wait)
    end
end

-- ── Retorna os dados coletados ───────────────────────────────────────
function RT.get_data(env)
    return env.__deob_data
end

return RT
