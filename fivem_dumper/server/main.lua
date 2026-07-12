-----------------------------------------------------------------------
-- fivem_dumper/server/main.lua  — v3.0  (deobfuscation pipeline)
--
-- Lê os arquivos de cada resource diretamente via LoadResourceFile,
-- passa pelo LuaJIT nativo do FiveM (que decodifica Luraph nativamente),
-- e escreve os bytecodes limpos (string.dump) no output.
--
-- NÃO usa monkey-patch, NÃO usa GetInvokingResource, NÃO usa io.open.
--
-- Fluxo por arquivo:
--   1. LoadResourceFile(res, rel_path)        → source (pode ser Luraph)
--   2. load(source, label, "bt", _ENV)        → fn  (LuaJIT decodifica Luraph)
--   3. string.dump(fn)                        → bytecode LuaJIT limpo
--   4. SaveResourceFile("fivem_dumper", out)  → arquivo no output/
--
-- Comandos:
--   /dump <resource>   — deobfusca um resource agora
--   /dumpall           — deobfusca todos os resources ativos
--   /dumplist          — lista recursos disponíveis
-----------------------------------------------------------------------

assert(WRITER, "[Dumper] server/writer.lua não carregado antes de main.lua")

local DUMPER_RES = GetCurrentResourceName()
local AUTO_DUMP  = true

-----------------------------------------------------------------------
-- Lê o fxmanifest.lua (ou __resource.lua) e extrai os scripts
-- server-side e shared declarados no resource.
-- Retorna: { { side="server"|"shared", path="rel/path.lua" }, ... }
-----------------------------------------------------------------------
local function get_resource_scripts(res_name)
    local scripts = {}

    -- Tenta fxmanifest.lua primeiro, depois __resource.lua (legado)
    local manifest = LoadResourceFile(res_name, "fxmanifest.lua")
                  or LoadResourceFile(res_name, "__resource.lua")
    if not manifest then return scripts end

    -- Extrai blocos: server_scripts { ... } e shared_scripts { ... }
    -- Suporta strings simples, globs com *, e caminhos em bloco multi-linha.
    local function extract_block(keyword)
        -- Padrão: keyword 'valor' ou keyword "valor" (entrada simples)
        -- e keyword { ... } (bloco)
        local results = {}

        -- Strings simples fora de bloco: server_script 'x.lua'
        for s in manifest:gmatch(keyword.."[s]?%s+['\"]([^'\"]+)['\"]") do
            results[#results+1] = s
        end

        -- Blocos: server_scripts { 'a.lua', "b.lua", ... }
        for block in manifest:gmatch(keyword.."[s]?%s*{([^}]*)}") do
            for s in block:gmatch("['\"]([^'\"]+)['\"]") do
                results[#results+1] = s
            end
        end
        return results
    end

    local server_list = extract_block("server_script")
    local shared_list = extract_block("shared_script")

    -- Filtra: só arquivos .lua sem glob
    local function is_plain_lua(p)
        return p:match("%.lua$") and not p:match("[*?]")
    end

    for _, p in ipairs(server_list) do
        if is_plain_lua(p) then
            scripts[#scripts+1] = { side = "server", path = p }
        end
    end
    for _, p in ipairs(shared_list) do
        if is_plain_lua(p) then
            scripts[#scripts+1] = { side = "shared", path = p }
        end
    end

    return scripts
end

-----------------------------------------------------------------------
-- Deobfusca um único arquivo e salva no output/.
-- Retorna "ok", "skip" (arquivo já é texto), "fail" ou "nofile".
-----------------------------------------------------------------------
local function deob_file(res_name, rel_path, out_base)
    -- 1. Lê o arquivo fonte
    local src = LoadResourceFile(res_name, rel_path)
    if not src or src == "" then
        return "nofile", "arquivo vazio ou não encontrado"
    end

    -- 2. Tenta carregar com LuaJIT do FiveM ("bt" = binário ou texto)
    --    Se for Luraph, o LuaJIT do FiveM vai decodificar nativamente.
    --    Se for Lua texto normal, também funciona.
    local fn, err = load(src, "@"..res_name.."/"..rel_path, "bt", _ENV)
    if not fn then
        -- load falhou: arquivo inválido / não é Lua
        return "fail", tostring(err)
    end

    -- 3. string.dump() → bytecode LuaJIT limpo (sem Luraph)
    local ok_dump, bytecode = pcall(string.dump, fn)
    if not ok_dump or not bytecode or bytecode == "" then
        return "fail", "string.dump falhou: "..(bytecode or "nil")
    end

    -- 4. Determina o caminho de saída
    --    output/<res>/<rel_path_com_dirs_flat>
    --    Mantém a estrutura de pastas: server/main.lua → output/res/server/main.lua
    local out_path = out_base.."/"..rel_path  -- ex: output/vrp/server/main.lua

    -- 5. Escreve o bytecode limpo
    local wrote = WRITER.write(out_path, bytecode)
    if wrote then
        return "ok", #bytecode
    else
        return "fail", "SaveResourceFile retornou false para: "..out_path
    end
end

-----------------------------------------------------------------------
-- Deobfusca todos os scripts de um resource.
-- Retorna: ok_count, fail_count, skip_count
-----------------------------------------------------------------------
local function do_dump(res_name, source_player)
    if res_name == DUMPER_RES then
        print("^3[Dumper] Não é possível fazer dump do próprio fivem_dumper.^7")
        return
    end

    -- Verifica se o resource existe/está rodando
    local state = GetResourceState(res_name)
    if state ~= "started" and state ~= "starting" then
        print(string.format(
            "^3[Dumper] Resource '%s' não está rodando (state=%s).^7",
            res_name, tostring(state)))
        return
    end

    print(string.format("^5[Dumper]^7 Iniciando deobfuscação de ^3%s^7...", res_name))

    local scripts = get_resource_scripts(res_name)
    if #scripts == 0 then
        print(string.format(
            "^3[Dumper] '%s' não tem scripts server/shared declarados no manifest.^7",
            res_name))
        return
    end

    local out_base = "output/"..res_name
    local ok_n, fail_n, skip_n = 0, 0, 0

    for _, entry in ipairs(scripts) do
        local status, info = deob_file(res_name, entry.path, out_base)
        if status == "ok" then
            ok_n = ok_n + 1
            print(string.format(
                "^2[Dumper]^7 ✓ [%s] %s  (%d bytes bytecode)",
                entry.side, entry.path, info))
        elseif status == "skip" then
            skip_n = skip_n + 1
            print(string.format(
                "^3[Dumper]^7 ~ [%s] %s  (skip: %s)",
                entry.side, entry.path, tostring(info)))
        elseif status == "nofile" then
            skip_n = skip_n + 1
            print(string.format(
                "^3[Dumper]^7 ? [%s] %s  (não encontrado)",
                entry.side, entry.path))
        else
            fail_n = fail_n + 1
            print(string.format(
                "^1[Dumper]^7 ✗ [%s] %s  ERRO: %s",
                entry.side, entry.path, tostring(info)))
        end
        Wait(0)  -- cede o tick para não travar o servidor
    end

    print(string.format(
        "^2[Dumper]^7 ✓ ^3%s^7 concluído — %d deobfuscados, %d erros, %d ignorados | output/%s/",
        res_name, ok_n, fail_n, skip_n, res_name))

    -- Notifica o cliente que requisitou
    if source_player and source_player > 0 then
        TriggerClientEvent(DUMPER_EV_CLIENT_REPORT, source_player, {
            resource = res_name,
            ok       = ok_n,
            fail     = fail_n,
            skip     = skip_n,
        })
    end
end

-----------------------------------------------------------------------
-- COMANDO: /dump <resourceName>
-----------------------------------------------------------------------
RegisterCommand("dump", function(source, args)
    local res = args[1]
    if not res or res == "" then
        print("^3[Dumper] Uso: /dump <resourceName>^7")
        print("^3[Dumper] Exemplo: /dump MathStoreDemon-v3^7")
        return
    end
    print(string.format("^5[Dumper] /dump: ^3%s^7 (source=%s)", res, tostring(source)))
    do_dump(res, tonumber(source) or 0)
end, true)

-----------------------------------------------------------------------
-- COMANDO: /dumpall
-- Deobfusca todos os resources ativos (exceto o próprio dumper e
-- os resources internos do FiveM).
-----------------------------------------------------------------------
local SKIP_RESOURCES = {
    ["fivem"]          = true,
    ["mapmanager"]     = true,
    ["sessionmanager"] = true,
    ["spawnmanager"]   = true,
    ["chat"]           = true,
    ["yarn"]           = true,
    ["webpack"]        = true,
}

RegisterCommand("dumpall", function(source, args)
    local count = GetNumResources()
    local list  = {}
    for i = 0, count - 1 do
        local name = GetResourceByFindIndex(i)
        if name
            and name ~= DUMPER_RES
            and not SKIP_RESOURCES[name]
            and GetResourceState(name) == "started"
        then
            list[#list+1] = name
        end
    end

    if #list == 0 then
        print("^3[Dumper] /dumpall: nenhum resource encontrado.^7")
        return
    end

    print(string.format("^5[Dumper] /dumpall: processando %d resources...^7", #list))
    for _, name in ipairs(list) do
        do_dump(name, 0)
        Wait(0)
    end
    print("^2[Dumper] /dumpall concluído.^7")
end, true)

-----------------------------------------------------------------------
-- COMANDO: /dumplist
-- Lista todos os resources ativos com seu estado.
-----------------------------------------------------------------------
RegisterCommand("dumplist", function(source, args)
    local count = GetNumResources()
    print("^5[Dumper] Resources ativos:^7")
    local listed = 0
    for i = 0, count - 1 do
        local name = GetResourceByFindIndex(i)
        if name and name ~= DUMPER_RES and GetResourceState(name) == "started" then
            local scripts = get_resource_scripts(name)
            print(string.format(
                "^5[Dumper]^7   ^3%-40s^7  scripts_server=%d",
                name, #scripts))
            listed = listed + 1
        end
    end
    print(string.format("^5[Dumper]^7 Total: %d resources. Use /dump <nome> ou /dumpall.", listed))
end, true)

-----------------------------------------------------------------------
-- AUTO-DUMP: deobfusca automaticamente quando qualquer resource inicia
-----------------------------------------------------------------------
AddEventHandler("onResourceStart", function(started_resource)
    if started_resource == DUMPER_RES then return end
    if not AUTO_DUMP then return end

    CreateThread(function()
        Wait(500)   -- aguarda o resource terminar de inicializar
        do_dump(started_resource, 0)
    end)
end)

-----------------------------------------------------------------------
-- Banner
-----------------------------------------------------------------------
print(string.format("^5[Dumper]^7 FiveM Dumper v%s iniciado.", DUMPER_VERSION))
print("^5[Dumper]^7 Modo: ^2deobfuscação nativa^7 (LoadResourceFile → load() → string.dump())")
print("^5[Dumper]^7 Funciona com Luraph, bytecode, e scripts Lua normais.")
print("^5[Dumper]^7 Comandos:")
print("^5[Dumper]^7   ^3/dump <resource>^7   — deobfusca um resource")
print("^5[Dumper]^7   ^3/dumpall^7            — deobfusca todos os resources ativos")
print("^5[Dumper]^7   ^3/dumplist^7           — lista resources disponíveis")
print(string.format("^5[Dumper]^7 Auto-dump: ^%s%s^7",
    AUTO_DUMP and "2" or "1", AUTO_DUMP and "ATIVO" or "INATIVO"))
