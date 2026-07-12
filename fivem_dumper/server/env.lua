-----------------------------------------------------------------------
-- fivem_dumper/server/env.lua
--
-- Cria um ambiente Lua instrumentado que captura TUDO que um script
-- FiveM faz quando é carregado:
--   • AddEventHandler / RegisterNetEvent / RegisterCommand
--   • TriggerServerEvent / TriggerClientEvent / TriggerEvent
--   • RegisterKeyMapping / RegisterNuiCallback
--   • GetHashKey / RequestModel / RequestAnimDict / TaskPlayAnim
--   • AttachEntityToEntity / GetPedBoneIndex
--   • exports, StateBag, HTTP, etc.
--
-- Usa as funções REAIS do FiveM onde possível (GetHashKey, etc.)
-- e proxies para as que precisam de contexto de jogador (ped, vehicle).
--
-- A chave da abordagem: load(bytecode, label, "bt", env)
-- O LuaJIT do FiveM executa bytecode Luraph diretamente — sem precisar
-- de nenhum parser customizado. O env instrumentado captura tudo.
-----------------------------------------------------------------------

ENV = {}  -- módulo global acessível por main.lua e writer.lua

-----------------------------------------------------------------------
-- Serializer seguro (sem ciclos, sem explosão em tabelas grandes)
-----------------------------------------------------------------------
local function ser(v, depth, seen)
    depth = depth or 0
    seen  = seen  or {}
    if depth > 4 then return "..." end
    local t = type(v)
    if t == "nil"      then return "nil" end
    if t == "boolean"  then return tostring(v) end
    if t == "number"   then return tostring(v) end
    if t == "string"   then
        local s = v:gsub("\n","\\n"):gsub("\r","\\r")
        return '"'..(#s > 120 and s:sub(1,120).."…" or s)..'"'
    end
    if t == "function" then return "<fn>" end
    if t == "table" then
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 16 then parts[#parts+1] = "..."; break end
            local ks = type(k) == "string" and k or ("["..tostring(k).."]")
            parts[#parts+1] = ks.."="..ser(val, depth+1, seen)
        end
        seen[v] = nil
        return "{"..table.concat(parts, ", ").."}"
    end
    return "<"..t..">"
end
ENV.ser = ser

-----------------------------------------------------------------------
-- Cria proxy universal para globals desconhecidos
-- Evita "attempt to call a nil value" em código obfuscado
-----------------------------------------------------------------------
local _proxy_cache = {}
local function make_proxy(name)
    if _proxy_cache[name] then return _proxy_cache[name] end
    local mt = {}
    mt.__index    = function(t, k)
        return make_proxy((name or "?").."."..tostring(k))
    end
    mt.__newindex = rawset
    mt.__call     = function(t, ...)
        return make_proxy((name or "?").."()")
    end
    mt.__tostring = function() return "<proxy:"..(name or "?")..">" end
    mt.__len      = function() return 0 end
    mt.__concat   = function(a, b) return tostring(a)..tostring(b) end
    mt.__add      = function() return 0 end
    mt.__sub      = function() return 0 end
    mt.__mul      = function() return 0 end
    mt.__div      = function() return 1 end
    mt.__mod      = function() return 0 end
    mt.__pow      = function() return 1 end
    mt.__unm      = function() return 0 end
    mt.__idiv     = function() return 0 end
    mt.__band     = function() return 0 end
    mt.__bor      = function() return 0 end
    mt.__bxor     = function() return 0 end
    mt.__bnot     = function() return 0 end
    mt.__shl      = function() return 0 end
    mt.__shr      = function() return 0 end
    mt.__lt       = function() return false end
    mt.__le       = function() return false end
    mt.__eq       = function() return false end
    local p = setmetatable({}, mt)
    _proxy_cache[name] = p
    return p
end

-----------------------------------------------------------------------
-- Novo ambiente instrumentado para um resource
-- resource_name : nome do resource alvo (para GetCurrentResourceName)
-- log_fn        : function(tag, msg) — callback de log
-----------------------------------------------------------------------
function ENV.new(resource_name, log_fn)
    log_fn = log_fn or function() end

    -- ── Dados coletados ────────────────────────────────────────────
    local data = {
        resource         = resource_name,
        side             = "SERVER",  -- será "CLIENT" para scripts client
        events           = {},        -- { name, fired_count }
        net_events       = {},        -- set [name]=true
        commands         = {},        -- { name, restricted }
        nui_callbacks    = {},        -- { name }
        server_events    = {},        -- TriggerServerEvent calls
        client_events    = {},        -- TriggerClientEvent calls
        natives_called   = {},        -- [name] = count
        models           = {},        -- [name] = true
        anim_dicts       = {},        -- [name] = true
        anim_plays       = {},        -- { dict, clip, flag }
        keybinds         = {},        -- { command, description, inputType, inputName }
        state_bag_keys   = {},        -- { key, bag }
        http_requests    = {},        -- { method, url }
        exports_called   = {},        -- [resource][fn] = true
        attach_calls     = {},        -- { entity, entityTo, bone, offset, rot }
        bones_used       = {},        -- [id] = true
        convars_read     = {},        -- [name] = default
        globals_set      = {},        -- [name] = value (primitivos)
        event_handlers   = {},        -- [name] = { fn, ... }
        handler_calls    = {},        -- [eventName] = { natives, triggers_server, triggers_client, models, anims, ... }
        threads          = {},
        thread_count     = 0,
        _log_fn          = log_fn,
    }

    local _current_handler = nil

    local function track(category, value)
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc[category] = hc[category] or {}
                table.insert(hc[category], value)
            end
        end
    end

    local function native(name, ...)
        data.natives_called[name] = (data.natives_called[name] or 0) + 1
        log_fn("NATIVE", name.."("..ser({...},1)..")")
        track("natives", { name=name, args={...} })
    end

    -- ── Constrói env base copiando _G ─────────────────────────────
    local env = {}
    for k, v in pairs(_G) do env[k] = v end

    -- Chaves que NÃO propagamos de/para _G
    local _skip = { _G=true, package=true, io=true, os=true, debug=true }

    -- Funções FiveM críticas — protegidas contra sobrescrita por scripts
    local _protected = {
        Wait=true, CreateThread=true, Citizen=true,
        AddEventHandler=true, RegisterNetEvent=true, RegisterCommand=true,
        TriggerEvent=true, TriggerServerEvent=true, TriggerClientEvent=true,
        TriggerLatentClientEvent=true, RegisterKeyMapping=true,
        RegisterNuiCallback=true, SendNuiMessage=true,
        exports=true, GetCurrentResourceName=true,
    }

    setmetatable(env, {
        __index = function(t, k)
            local v = rawget(t, k)
            if v ~= nil then return v end
            if not _protected[k] then
                -- Tenta _G real (funções nativas do FiveM como GetGameTimer, etc.)
                v = rawget(_G, k)
                if v ~= nil then return v end
            end
            return make_proxy(tostring(k))
        end,
        __newindex = function(t, k, v)
            if _protected[k] then
                local cur = rawget(t, k)
                if type(cur) == "function" then return end
            end
            rawset(t, k, v)
            -- Globals primitivos: registra para análise
            if not _skip[k] and not _protected[k] then
                local tv = type(v)
                if tv == "string" or tv == "number" or tv == "boolean" then
                    data.globals_set[k] = v
                end
            end
        end,
    })

    -- Metadados internos
    env.__dumper_data = data

    -- ── GetCurrentResourceName ─────────────────────────────────────
    -- Retorna o nome do resource ALVO (não "fivem_dumper")
    env.GetCurrentResourceName = function() return resource_name end
    env.GetResourceState = function(name)
        -- Considera todos os resources como "started" para não bloquear guards
        return "started"
    end

    -- ── Wait / Threads ─────────────────────────────────────────────
    -- Wait real: dentro de um coroutine, yield; fora, no-op seguro
    env.Wait = function(ms)
        local co = coroutine.running()
        if co then
            coroutine.yield(ms)
        end
    end

    env.CreateThread = function(fn)
        data.thread_count = data.thread_count + 1
        local id = data.thread_count
        log_fn("CreateThread", "#"..id)
        local co = coroutine.create(function()
            local ok, err = pcall(fn)
            if not ok then
                log_fn("Thread.ERROR", "#"..id.." "..tostring(err))
            end
        end)
        data.threads[#data.threads+1] = { id=id, co=co, ticks_run=0 }
        return co
    end

    env.Citizen = {
        CreateThread = env.CreateThread,
        Wait         = env.Wait,
        Trace        = function(msg) log_fn("Citizen.Trace", tostring(msg)) end,
        SetTimeout   = function(ms, fn)
            -- Executa imediatamente para capturar o conteúdo
            local ok, err = pcall(fn)
            if not ok then log_fn("SetTimeout.ERROR", tostring(err)) end
        end,
    }

    -- ── Eventos ────────────────────────────────────────────────────
    env.AddEventHandler = function(eventName, handler)
        log_fn("AddEventHandler", '"'..tostring(eventName)..'"')
        if not data.event_handlers[eventName] then
            data.event_handlers[eventName] = {}
            data.events[#data.events+1] = { name=eventName, fired_count=0 }
            data.handler_calls[eventName] = {
                natives          = {},
                triggers_server  = {},
                triggers_client  = {},
                models           = {},
                anims            = {},
                anims_played     = {},
                entities_created = 0,
                entities_deleted = 0,
                attach_calls     = {},
                http_calls       = {},
                nui_messages     = {},
                convars          = {},
            }
        end
        -- Wrap: rastreia chamadas durante execução do handler
        local orig    = handler
        local wrapped = function(...)
            local prev = _current_handler
            _current_handler = eventName
            local ok, err = pcall(orig, ...)
            _current_handler = prev
            if not ok then
                log_fn("Handler.ERROR", '"'..tostring(eventName)..'" '..tostring(err))
            end
        end
        table.insert(data.event_handlers[eventName], wrapped)
    end

    env.RegisterNetEvent = function(eventName, handler)
        log_fn("RegisterNetEvent", '"'..tostring(eventName)..'"')
        data.net_events[eventName] = true
        if handler then env.AddEventHandler(eventName, handler) end
    end

    local function fire_handlers(eventName, args)
        if data.event_handlers[eventName] then
            for _, h in ipairs(data.event_handlers[eventName]) do
                local ok, err = pcall(h, table.unpack(args))
                if not ok then
                    log_fn("Event.ERROR", '"'..tostring(eventName)..'" '..tostring(err))
                end
            end
        end
    end

    env.TriggerEvent = function(eventName, ...)
        log_fn("TriggerEvent", '"'..tostring(eventName)..'"')
        fire_handlers(eventName, {...})
    end

    env.TriggerServerEvent = function(eventName, ...)
        local a = {...}
        log_fn("TriggerServerEvent", '"'..tostring(eventName)..'" args='..ser(a,2))
        data.server_events[#data.server_events+1] = { name=eventName, args=a }
        track("triggers_server", { name=eventName, args=a })
    end

    env.TriggerClientEvent = function(eventName, target, ...)
        local a   = {...}
        local tgt = (target == -1) and "ALL" or tostring(target)
        log_fn("TriggerClientEvent", '"'..tostring(eventName)..'" tgt='..tgt)
        data.client_events[#data.client_events+1] = { name=eventName, target=tgt, args=a }
        track("triggers_client", { name=eventName, target=tgt, args=a })
        fire_handlers(eventName, a)
    end

    env.TriggerLatentClientEvent = function(eventName, target, bps, ...)
        log_fn("TriggerLatentClientEvent", '"'..tostring(eventName)..'"')
        track("triggers_client", { name=eventName, target=tostring(target), latent=true })
    end

    -- ── Comandos ───────────────────────────────────────────────────
    env.RegisterCommand = function(name, handler, restricted)
        log_fn("RegisterCommand", '"/'..tostring(name)..'" restricted='..tostring(restricted))
        data.commands[#data.commands+1] = { name=name, restricted=restricted or false }
        -- Executa com args vazios para capturar lógica interna
        local ok, err = pcall(handler, 0, {}, false)
        if not ok then log_fn("Command.PROBE", '/'..name..' → '..tostring(err)) end
    end

    -- ── NUI ────────────────────────────────────────────────────────
    env.RegisterNuiCallback = function(name, handler)
        log_fn("RegisterNuiCallback", '"'..tostring(name)..'"')
        data.nui_callbacks[#data.nui_callbacks+1] = { name=name }
    end
    env.RegisterNUICallback = env.RegisterNuiCallback
    env.SendNuiMessage = function(json_str)
        log_fn("SendNuiMessage", tostring(json_str):sub(1, 200))
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.nui_messages = hc.nui_messages or {}
                table.insert(hc.nui_messages, tostring(json_str))
            end
        end
    end
    env.SetNuiFocus          = function(...) native("SetNuiFocus", ...) end
    env.SetNuiFocusKeepInput = function(...) native("SetNuiFocusKeepInput", ...) end

    -- ── HTTP ───────────────────────────────────────────────────────
    env.PerformHttpRequest = function(url, cb, method, body, headers)
        local req = { url=url, method=method or "GET", body=body }
        log_fn("PerformHttpRequest", (method or "GET").." "..tostring(url))
        data.http_requests[#data.http_requests+1] = req
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.http_calls = hc.http_calls or {}
                table.insert(hc.http_calls, req)
            end
        end
        -- Chama callback com resposta fake para continuar execução
        if cb then
            pcall(cb, 200, '{"status":"ok","authorized":true}', {})
        end
    end

    -- ── Modelos / Streaming ────────────────────────────────────────
    -- GetHashKey REAL do FiveM — retorna o hash correto
    env.GetHashKey = function(model)
        if type(model) == "string" then
            data.models[model] = true
            log_fn("GetHashKey", '"'..model..'"')
            track("models", model)
        end
        -- Usa GetHashKey real se disponível, senão calcula localmente
        local real = _G.GetHashKey
        if real then return real(model) end
        if type(model) == "string" then
            local h = 0
            for i = 1, #model do
                h = (h * 31 + string.byte(model, i)) & 0xFFFFFFFF
            end
            return h
        end
        return model
    end

    env.RequestModel        = function(model)
        data.models[ser(model,0)] = true
        log_fn("RequestModel", ser(model,0))
        track("models", ser(model,0))
    end
    env.HasModelLoaded      = function() return true end
    env.IsModelValid        = function() return true end
    env.SetModelAsNoLongerNeeded = function() end

    -- ── Animações ─────────────────────────────────────────────────
    env.RequestAnimDict = function(dict)
        if type(dict) == "string" and dict ~= "" then
            data.anim_dicts[dict] = true
            log_fn("RequestAnimDict", '"'..dict..'"')
            if _current_handler then
                local hc = data.handler_calls[_current_handler]
                if hc then
                    hc.anims = hc.anims or {}
                    local found = false
                    for _, v in ipairs(hc.anims) do
                        if v == dict then found = true; break end
                    end
                    if not found then table.insert(hc.anims, dict) end
                end
            end
        end
    end
    env.HasAnimDictLoaded   = function() return true end
    env.RemoveAnimDict      = function(d)
        if type(d) == "string" and d ~= "" then
            data.anim_dicts[d] = true
        end
    end
    env.TaskPlayAnim = function(ped, animDict, animName, blendIn, blendOut, duration, flag, ...)
        local play = { dict=animDict, clip=animName, ped=ped, flag=flag, duration=duration }
        data.anim_plays[#data.anim_plays+1] = play
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.anims_played = hc.anims_played or {}
                table.insert(hc.anims_played, play)
            end
        end
        log_fn("TaskPlayAnim", string.format('ped=%s dict="%s" clip="%s"',
            tostring(ped), tostring(animDict), tostring(animName)))
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
    end
    env.IsEntityPlayingAnim     = function() return false end
    env.StopAnimTask            = function(...) end
    env.GetAnimCurrentTime      = function() return 0.0 end
    env.GetAnimDuration         = function() return 2.0 end
    env.RequestAnimSet          = function() end
    env.HasAnimSetLoaded        = function() return true end
    env.SetPedMovementClipset   = function(...) native("SetPedMovementClipset", ...) end
    env.ResetPedMovementClipset = function(...) end

    -- ── Entidades ─────────────────────────────────────────────────
    local _eid = 5000
    env.CreateObject = function(model, ...)
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
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then hc.entities_deleted = (hc.entities_deleted or 0) + 1 end
        end
    end
    env.DeleteObject               = env.DeleteEntity
    env.DoesEntityExist            = function(e) return (e or 0) > 0 end
    env.IsEntityAttached           = function() return false end
    env.DetachEntity               = function(...) end
    env.SetEntityVisible           = function(...) end
    env.SetEntityCollision         = function(...) end
    env.SetEntityAsMissionEntity   = function(...) end
    env.IsEntityAMissionEntity     = function() return true end
    env.SetEntityAlpha             = function(...) end
    env.SetEntityCoords            = function(e, x, y, z, ...) native("SetEntityCoords", e, x, y, z) end
    env.SetEntityCoordsNoOffset    = function(...) end
    env.SetEntityHeading           = function(...) end
    env.FreezeEntityPosition       = function(...) end
    env.SetEntityVelocity          = function(...) end
    env.GetEntityVelocity          = function() return vec3(0,0,0) end
    env.GetEntityCoords            = function() return vec3(100, 200, 30) end
    env.GetEntityRotation          = function() return vec3(0,0,0) end
    env.SetEntityRotation          = function(...) end
    env.GetEntityType              = function() return 1 end
    env.GetEntityModel             = function() return 0 end
    env.GetEntitySpeed             = function() return 0.0 end
    env.GetEntityHeading           = function() return 0.0 end
    env.GetEntityForwardVector     = function() return vec3(0,1,0) end
    env.GetEntityBoneIndexByName   = function() return 0 end
    env.GetWorldPositionOfEntityBone = function() return vec3(0,0,0) end
    env.GetOffsetFromEntityInWorldCoords = function(e,x,y,z) return x or 0, y or 0, z or 0 end
    env.IsEntityInAir              = function() return false end
    env.IsEntityDead               = function() return false end
    env.IsEntityAnObject           = function() return true end
    env.IsEntityAPed               = function() return false end
    env.IsEntityAVehicle           = function() return false end
    env.PlaceObjectOnGroundProperly = function() end
    env.SetEntityNoCollisionEntity = function(...) end
    env.ApplyForceToEntity         = function(...) end
    env.NetworkGetNetworkIdFromEntity = function(e) return (e or 0)+10000 end
    env.NetworkGetEntityFromNetworkId = function(n) return (n or 0)-10000 end
    env.NetworkDoesEntityExistWithNetworkId = function() return true end
    env.SetNetworkIdCanMigrate     = function(...) end
    env.SetNetworkIdExistsOnAllMachines = function(...) end

    env.AttachEntityToEntity = function(entity, entityTo, boneIndex, ox, oy, oz, rx, ry, rz, ...)
        local call = {
            entity   = entity,
            entityTo = entityTo,
            bone     = boneIndex,
            offset   = { ox or 0, oy or 0, oz or 0 },
            rot      = { rx or 0, ry or 0, rz or 0 },
        }
        data.attach_calls[#data.attach_calls+1] = call
        if _current_handler then
            local hc = data.handler_calls[_current_handler]
            if hc then
                hc.attach_calls = hc.attach_calls or {}
                table.insert(hc.attach_calls, call)
            end
        end
        log_fn("AttachEntityToEntity", string.format(
            "eid=%s to=%s bone=%s off=(%.2f,%.2f,%.2f) rot=(%.2f,%.2f,%.2f)",
            tostring(entity), tostring(entityTo), tostring(boneIndex),
            ox or 0, oy or 0, oz or 0, rx or 0, ry or 0, rz or 0))
    end

    -- ── Ped ────────────────────────────────────────────────────────
    env.GetPedBoneIndex = function(ped, boneId)
        data.bones_used[tostring(boneId)] = true
        log_fn("GetPedBoneIndex", "ped="..tostring(ped).." boneId="..tostring(boneId))
        return boneId
    end
    env.GetPedBoneCoords        = function() return vec3(0,0,0) end
    env.IsPedInAnyVehicle       = function() return false end
    env.IsPedOnFoot             = function() return true end
    env.IsPedFalling            = function() return false end
    env.IsPedSwimming           = function() return false end
    env.IsPedRunning            = function() return false end
    env.IsPedSprinting          = function() return false end
    env.IsPedStill              = function() return true end
    env.IsPedJumping            = function() return false end
    env.IsPedMale               = function() return true end
    env.GetVehiclePedIsIn       = function() return 0 end
    env.PlayerPedId             = function() return 1001 end
    env.PlayerId                = function() return 1 end
    env.GetPlayerPed            = function(src) return 1000 + (tonumber(src) or 0) end
    env.GetPlayerServerId       = function() return 1 end
    env.GetPlayerFromServerId   = function(sid) return tonumber(sid) or 0 end
    env.SetPedToRagdoll         = function(...) end
    env.SetPedComponentVariation = function(...) end
    env.SetPedGravity           = function(...) native("SetPedGravity", ...) end
    env.SetPedConfigFlag        = function(...) end
    env.GetPedConfigFlag        = function() return false end
    env.ClearPedTasks           = function(...) native("ClearPedTasks", ...) end
    env.ClearPedTasksImmediately = function(...) native("ClearPedTasksImmediately", ...) end
    env.GetSelectedPedWeapon    = function() return 0 end

    -- ── Jogadores ─────────────────────────────────────────────────
    local _players = {
        { id=1, name="TestPlayer", identifiers={"license:abc123","steam:110000100000001"} },
    }
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
            if p.id == tonumber(src) then return p.identifiers[idx+1] end
        end
        return nil
    end

    -- ── Permissões ────────────────────────────────────────────────
    env.IsPlayerAceAllowed    = function() return false end
    env.IsPrincipalAceAllowed = function() return false end

    -- ── StateBag ──────────────────────────────────────────────────
    local _sbags = {}
    env.AddStateBagChangeHandler = function(keyname, bagName, handler)
        log_fn("AddStateBagChangeHandler", tostring(keyname).."/"..tostring(bagName))
        data.state_bag_keys[#data.state_bag_keys+1] = {
            key = keyname, bag = tostring(bagName or '')
        }
    end
    env.LocalPlayer = { state = setmetatable({}, { __index=_sbags, __newindex=rawset }) }
    env.Player      = function(id) return { state = setmetatable({}, { __index=_sbags, __newindex=rawset }) } end

    -- ── Keybinds ──────────────────────────────────────────────────
    env.RegisterKeyMapping = function(command, description, inputType, inputName)
        log_fn("RegisterKeyMapping", string.format(
            'cmd="/%s" desc="%s" type="%s" key="%s"',
            tostring(command), tostring(description),
            tostring(inputType), tostring(inputName)))
        data.keybinds[#data.keybinds+1] = {
            command=command, description=description,
            inputType=inputType, inputName=inputName,
        }
    end

    -- ── Controles ─────────────────────────────────────────────────
    env.IsControlPressed          = function() return false end
    env.IsControlJustPressed      = function() return false end
    env.IsDisabledControlPressed  = function() return false end
    env.IsControlJustReleased     = function() return false end
    env.DisableControlAction      = function(...) end
    env.EnableControlAction       = function(...) end
    env.DisableAllControlActions  = function(...) end

    -- ── Camera ────────────────────────────────────────────────────
    env.GetFollowPedCamHeading          = function() return 0.0 end
    env.GetGameplayCamRelativePitch     = function() return 0.0 end
    env.GetGameplayCamRelativeHeading   = function() return 0.0 end
    env.SetGameplayCamRelativeHeading   = function(...) end
    env.SetGameplayCamRelativePitch     = function(...) end
    env.GetFinalRenderedCamCoord        = function() return vec3(0,0,0) end
    env.GetFinalRenderedCamRot          = function() return vec3(0,0,0) end

    -- ── HUD / Screen ──────────────────────────────────────────────
    env.IsScreenFadedOut    = function() return false end
    env.SetTextScale        = function(...) end
    env.SetTextFont         = function(...) end
    env.SetTextColour       = function(...) end
    env.SetTextEntry        = function(...) end
    env.SetTextCentre       = function(...) end
    env.DrawText            = function(...) end
    env.DrawText3D          = function(...) end
    env.BeginTextCommandDisplayText  = function(...) end
    env.EndTextCommandDisplayText    = function(...) end
    env.BeginTextCommandGetWidth     = function(...) end
    env.EndTextCommandGetWidth       = function() return 0.1 end
    env.DrawNotification             = function(...) end
    env.BeginTextCommandDisplayHelp  = function(...) end
    env.EndTextCommandDisplayHelp    = function(...) end
    env.ThefeedSetNextPostBackgroundColor = function(...) end

    -- ── Gameplay / Misc ───────────────────────────────────────────
    env.GetGameTimer        = function() return GetGameTimer and GetGameTimer() or 0 end
    env.GetFrameTime        = function() return 0.016 end
    env.GetNetworkTime      = function() return GetGameTimer and GetGameTimer() or 0 end
    env.SetGravityLevel     = function(level) native("SetGravityLevel", level) end
    env.GetGravityLevel     = function() return 9 end
    env.GetGroundZFor_3dCoord = function(x,y,z,...) return true, (z or 0)-1.0 end
    env.GetVehicleModel     = function() return 0 end
    env.Vdist               = function(x1,y1,z1,x2,y2,z2)
        local dx,dy,dz=(x2 or 0)-(x1 or 0),(y2 or 0)-(y1 or 0),(z2 or 0)-(z1 or 0)
        return math.sqrt(dx*dx+dy*dy+dz*dz)
    end
    env.Vdist2              = function(x1,y1,z1,x2,y2,z2)
        local dx,dy,dz=(x2 or 0)-(x1 or 0),(y2 or 0)-(y1 or 0),(z2 or 0)-(z1 or 0)
        return dx*dx+dy*dy+dz*dz
    end

    -- ── Partículas ────────────────────────────────────────────────
    env.RequestNamedPtfxAsset    = function() end
    env.HasNamedPtfxAssetLoaded  = function() return true end
    env.UseParticleFxAssetNextCall = function() end
    env.StartParticleFxLoopedAtCoord = function(...) return 0 end
    env.StopParticleFxLooped     = function(...) end
    env.RemoveParticleFx         = function(...) end

    -- ── Convars ───────────────────────────────────────────────────
    env.GetConvar    = function(name, default)
        data.convars_read[name] = default
        -- Tenta o GetConvar real primeiro
        if _G.GetConvar then
            local v = _G.GetConvar(name, default or "")
            if v and v ~= "" then return v end
        end
        return default or ""
    end
    env.GetConvarInt = function(name, default)
        data.convars_read[name] = default
        return default or 0
    end

    -- ── Resource lifecycle ────────────────────────────────────────
    env.GetResourceMetadata = function(r, k, i) return nil end
    env.StopResource        = function(name) log_fn("StopResource", tostring(name)) end
    env.LoadResourceFile    = function(res, file)
        -- Tenta ler o arquivo real do disco
        local paths = {
            ("resources/%s/%s"):format(res, file),
            ("../resources/%s/%s"):format(res, file),
            ("%s/%s"):format(res, file),
        }
        for _, p in ipairs(paths) do
            local f = io.open(p, "r")
            if f then
                local content = f:read("*a")
                f:close()
                if content and content ~= "" then
                    log_fn("LoadResourceFile.REAL", p)
                    return content
                end
            end
        end
        return ""
    end

    -- ── vRP / ox_lib stubs ────────────────────────────────────────
    env.vRP = {
        getUserId     = function() return 1 end,
        hasPermission = function() return true end,
        hasGroup      = function() return true end,
    }

    -- ── exports ───────────────────────────────────────────────────
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

    -- ── JSON ──────────────────────────────────────────────────────
    -- Usa json do FiveM se disponível, senão implementação mínima
    if _G.json then
        env.json = _G.json
    else
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
                    n = n+1
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
        env.json = {
            encode = json_encode,
            decode = function(s)
                if not s or s=="" or s=="null" then return nil end
                local fn = load("return "..s:gsub("null","false"))
                if fn then local ok,v = pcall(fn); if ok then return v end end
                return nil
            end,
        }
    end

    -- ── msgpack ───────────────────────────────────────────────────
    env.msgpack = _G.msgpack or {
        pack   = function(v) return tostring(v) end,
        unpack = function(v) return v end,
    }

    -- ── Stdlib Lua garantida ───────────────────────────────────────
    env.math      = math
    env.string    = string
    env.table     = table
    env.pairs     = pairs
    env.ipairs    = ipairs
    env.next      = next
    env.type      = type
    env.tostring  = tostring
    env.tonumber  = tonumber
    env.pcall     = pcall
    env.xpcall    = xpcall
    env.error     = error
    env.assert    = assert
    env.select    = select
    env.unpack    = table.unpack
    env.rawget    = rawget
    env.rawset    = rawset
    env.rawequal  = rawequal
    env.setmetatable = setmetatable
    env.getmetatable = getmetatable
    env.load      = load
    env.loadstring = load
    env.coroutine = coroutine
    env.io        = io
    env.os        = os
    env.require   = require
    env.module    = function(name, ...) end
    env.print     = function(...)
        local parts = {}
        for _, v in ipairs({...}) do parts[#parts+1] = tostring(v) end
        log_fn("print", table.concat(parts, "\t"))
    end

    -- Cache típico de scripts FiveM
    env.cache = {
        ped       = 1001,
        vehicle   = nil,
        seat      = nil,
        serverId  = 1,
        resource  = resource_name,
    }

    return env
end

-----------------------------------------------------------------------
-- Pump de threads instrumentadas
-- MAX_TOTAL_TICKS: mata threads Wait(0)-loop que sobrevivem entre calls
-----------------------------------------------------------------------
local MAX_TOTAL_TICKS = 30
local MAX_INSTRS      = 500000

function ENV.run_threads(env, max_ticks)
    max_ticks    = max_ticks or 4
    local data   = env.__dumper_data
    if not data or #data.threads == 0 then return end
    local log_fn = data._log_fn or function() end

    for tick = 1, max_ticks do
        local alive = {}
        for _, entry in ipairs(data.threads) do
            if coroutine.status(entry.co) ~= "dead" then
                entry.ticks_run = (entry.ticks_run or 0) + 1
                if entry.ticks_run > MAX_TOTAL_TICKS then
                    log_fn("Thread.KILLED", "#"..entry.id
                        .." (loop persistente — "..entry.ticks_run.." ticks)")
                    goto continue_thread
                end

                local instr_count = 0
                local killed      = false
                local function budget_hook()
                    instr_count = instr_count + 1
                    if instr_count >= MAX_INSTRS then
                        killed = true
                        error("__budget__", 2)
                    end
                end
                pcall(debug.sethook, entry.co, budget_hook, "", 1000)
                local ok, w = coroutine.resume(entry.co)
                pcall(debug.sethook, entry.co, nil)

                if not ok then
                    if killed or (type(w)=="string" and w:find("__budget__")) then
                        log_fn("Thread.KILLED", "#"..entry.id.." (busy-loop)")
                    else
                        log_fn("Thread.ERROR", "#"..entry.id.." "..tostring(w))
                    end
                elseif coroutine.status(entry.co) ~= "dead" then
                    alive[#alive+1] = entry
                end

                ::continue_thread::
            end
        end
        data.threads = alive
        if #data.threads == 0 then break end
    end
end

-----------------------------------------------------------------------
-- Carrega um arquivo .lua (texto ou bytecode Luraph) no env
-- Retorna true ou false, errmsg
-----------------------------------------------------------------------
function ENV.load_file(path, env, label)
    label = label or path
    local f, ferr = io.open(path, "rb")
    if not f then return false, "cannot open: "..tostring(ferr) end
    local src = f:read("*a")
    f:close()

    -- Remove BOM UTF-8
    if src:sub(1,3) == "\xEF\xBB\xBF" then src = src:sub(4) end

    -- Tenta como texto primeiro; "bt" aceita ambos (bytecode LuaJIT incluso)
    local fn, cerr = load(src, "@"..label, "bt", env)
    if not fn then
        -- Segunda tentativa: força bytecode puro
        fn, cerr = load(src, "@"..label, "b", env)
    end
    if not fn then return false, "compile: "..tostring(cerr) end

    local ok, rerr = pcall(fn)
    if not ok then return false, "runtime: "..tostring(rerr) end
    return true
end

-----------------------------------------------------------------------
-- Dispara um evento no env instrumentado
-----------------------------------------------------------------------
function ENV.fire_event(env, eventName, ...)
    local data = env.__dumper_data
    if not data then return end
    if data.event_handlers[eventName] then
        local args = {...}
        for _, h in ipairs(data.event_handlers[eventName]) do
            local ok, err = pcall(h, table.unpack(args))
            if not ok then
                local log_fn = data._log_fn or function() end
                log_fn("Event.ERROR", '"'..tostring(eventName)..'" '..tostring(err))
            end
        end
    end
end
