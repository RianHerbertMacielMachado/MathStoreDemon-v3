-----------------------------------------------------------------------
-- fivem_deob/manifest.lua
-- Lê fxmanifest.lua e extrai a ordem dos scripts.
-- Funciona com fxmanifest.lua e __resource.lua (formato legado).
-----------------------------------------------------------------------

local M = {}

-- ── Lê o fxmanifest e retorna { shared={}, server={}, client={} } ──
function M.parse(path)
    path = path or "fxmanifest.lua"
    local f, err = io.open(path, "r")
    if not f then
        return nil, "Cannot open manifest: "..tostring(err)
    end
    local src = f:read("*a"); f:close()

    local result = {
        shared  = {},
        server  = {},
        client  = {},
        ui_page = nil,
        name    = nil,
        version = nil,
    }

    -- ── Ambiente mínimo para executar o manifest ─────────────────────
    local env = setmetatable({}, { __index = _G })

    -- Captura as diretivas do manifest
    local function capture_list(target)
        return function(...)
            local args = {...}
            -- aceita: fn({"a","b"}) ou fn("a","b")
            if type(args[1]) == "table" then
                for _, v in ipairs(args[1]) do
                    if type(v) == "string" then target[#target+1] = v end
                end
            else
                for _, v in ipairs(args) do
                    if type(v) == "string" then target[#target+1] = v end
                end
            end
        end
    end

    -- Diretivas de script
    env.shared_scripts   = capture_list(result.shared)
    env.shared_script    = function(v) result.shared[#result.shared+1] = v end
    env.server_scripts   = capture_list(result.server)
    env.server_script    = function(v) result.server[#result.server+1] = v end
    env.client_scripts   = capture_list(result.client)
    env.client_script    = function(v) result.client[#result.client+1] = v end

    -- Diretivas de metadados (ignoradas silenciosamente)
    env.fx_version       = function(...) end
    env.game             = function(...) end
    env.lua54            = function(...) end
    env.author           = function(v) result.author = v end
    env.description      = function(v) result.description = v end
    env.version          = function(v) result.version = v end
    env.dependency       = function(...) end
    env.dependencies     = function(...) end
    env.ui_page          = function(v) result.ui_page = v end
    env.files            = function(...) end
    env.file             = function(...) end
    -- data_file aceita chamada em cadeia: data_file 'type' 'path'
    -- em Lua isso é data_file('type')('path') — retorna função no-op
    env.data_file        = function(...) return function(...) end end
    env.escrow_ignore    = function(...) end
    env.export           = function(...) end
    env.exports          = function(...) end
    env.server_export    = function(...) end
    env.server_exports   = function(...) end
    env.provide          = function(...) end
    env.after_map_loaded = function(...) end
    env.loadscreen       = function(...) end

    -- Executa o manifest no ambiente isolado
    local fn, err2 = load(src, "@"..path, "t", env)
    if not fn then
        return nil, "Manifest parse error: "..tostring(err2)
    end
    local ok, err3 = pcall(fn)
    if not ok then
        return nil, "Manifest runtime error: "..tostring(err3)
    end

    return result
end

-- ── Resolve globs simples (apenas *.lua e **/*.lua) ─────────────────
function M.resolve_globs(patterns, base_dir)
    base_dir = base_dir or "."
    local resolved = {}
    for _, pat in ipairs(patterns) do
        -- Se não tem wildcard, inclui diretamente
        if not pat:find("[*?]") then
            resolved[#resolved+1] = pat
        else
            -- Glob simples: varre com find
            local dir_pat, file_pat = pat:match("^(.-)([^/]+)$")
            dir_pat = dir_pat or ""
            file_pat = file_pat or pat
            -- Converte *.lua → %.lua e **/*.lua
            if pat:find("^%*%*/") or pat == "**" then
                -- recursivo — pula (streaming, etc.)
            elseif file_pat == "*.lua" then
                -- Apenas no diretório especificado
                local dir = base_dir.."/"..dir_pat
                dir = dir:gsub("//","/"):gsub("/$","")
                local p = io.popen('find "'..dir..'" -maxdepth 1 -name "*.lua" 2>/dev/null | sort')
                if p then
                    for line in p:lines() do
                        local rel = line:gsub("^"..base_dir.."/", "")
                        resolved[#resolved+1] = rel
                    end
                    p:close()
                end
            else
                resolved[#resolved+1] = pat
            end
        end
    end
    return resolved
end

-- ── Determina se um arquivo existe ──────────────────────────────────
function M.file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

return M
