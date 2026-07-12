#!/usr/bin/env lua5.4
-----------------------------------------------------------------------
-- fivem_deob/deob.lua
-- Ferramenta CLI para análise dinâmica e reconstrução de scripts
-- FiveM obfuscados (Luraph / Obfuscator).
--
-- Uso:
--   lua5.4 fivem_deob/deob.lua <resource_dir> [opções]
--
-- Opções:
--   --output <dir>       Diretório de saída (padrão: <resource_dir>/deob_output)
--   --verbose            Mostra todos os logs de simulação em tempo real
--   --log <arquivo>      Salva log bruto da simulação num arquivo
--   --max-ticks <n>      Iterações do pump de threads por etapa (padrão: 3)
--   --no-reconstruct     Apenas extrai dados, não gera arquivos reconstruídos
--   --help               Mostra esta ajuda
--
-- Exemplos:
--   lua5.4 fivem_deob/deob.lua .
--   lua5.4 fivem_deob/deob.lua /caminho/para/resource --verbose
--   lua5.4 fivem_deob/deob.lua . --output ./analise --log sim.log
--   lua5.4 fivem_deob/deob.lua . --no-reconstruct
-----------------------------------------------------------------------

-- ── Adiciona o diretório pai ao path do Lua ─────────────────────────
-- Necessário para que require("fivem_deob.X") funcione de qualquer dir
-- Normaliza \ → / para compatibilidade Windows/Unix
local script_path = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")  -- remove '@', normalize
local script_dir  = script_path:match("^(.+)/[^/]+$") or "."
local parent_dir  = script_dir:match("^(.+)/[^/]+$") or script_dir

-- Insere o diretório pai (que contém a pasta fivem_deob/) no início do path
package.path = parent_dir .. "/?.lua;"
            .. parent_dir .. "/?/init.lua;"
            .. script_dir .. "/?.lua;"
            .. package.path

-----------------------------------------------------------------------
-- Cores para terminal (ANSI) — usadas apenas quando stdout é um tty
-----------------------------------------------------------------------
local IS_TTY = io.type(io.stdout) == "file"  -- heurística simples
local function color(code, text)
    if IS_TTY then
        return "\27["..code.."m"..text.."\27[0m"
    end
    return text
end
local C = {
    bold    = function(s) return color("1",     s) end,
    green   = function(s) return color("32",    s) end,
    yellow  = function(s) return color("33",    s) end,
    red     = function(s) return color("31",    s) end,
    cyan    = function(s) return color("36",    s) end,
    dim     = function(s) return color("2",     s) end,
    reset   = function(s) return color("0",     s) end,
}

-----------------------------------------------------------------------
-- Banner
-----------------------------------------------------------------------
local function print_banner()
    print(C.cyan(C.bold([[
  _____ _           __  __   ____            _
 |  ___(_)_   _____| \/ |  |  _ \  ___  ___| |__
 | |_  | \ \ / / _ \ |\/| | | | |/ _ \/ _ \ '_ \
 |  _| | |\ V /  __/ |  | | |_| |  __/  __/ |_) |
 |_|   |_| \_/ \___|_|  |_||____/ \___|\___|_.__/
]])))
    print(C.dim("  FiveM Dynamic Analysis & Deobfuscation Tool"))
    print(C.dim("  github.com/RianHerbertMacielMachado/MathStoreDemon-v3"))
    print("")
end

-----------------------------------------------------------------------
-- Ajuda
-----------------------------------------------------------------------
local function print_help()
    print_banner()
    print(C.bold("USO:"))
    print("  lua5.4 fivem_deob/deob.lua <resource_dir> [opções]")
    print("")
    print(C.bold("ARGUMENTOS:"))
    print("  <resource_dir>        Pasta do resource FiveM (deve conter fxmanifest.lua)")
    print("")
    print(C.bold("OPÇÕES:"))
    print("  --output <dir>        Diretório de saída (padrão: <resource_dir>/deob_output)")
    print("  --resource-name <n>   Sobrescreve o nome do resource (útil quando pasta tem nome diferente)")
    print("  --verbose             Mostra logs de simulação em tempo real")
    print("  --log <arquivo>       Salva log bruto num arquivo separado")
    print("  --max-ticks <n>       Iterações do thread pump (padrão: 3)")
    print("  --no-reconstruct      Apenas extrai, não gera arquivos Lua reconstruídos")
    print("  --help                Mostra esta ajuda")
    print("")
    print(C.bold("EXEMPLOS:"))
    print("  lua5.4 fivem_deob/deob.lua .")
    print("  lua5.4 fivem_deob/deob.lua /path/to/resource --verbose")
    print("  lua5.4 fivem_deob/deob.lua . --output ./analise --log sim.log --max-ticks 5")
    print("  lua5.4 fivem_deob/deob.lua . --no-reconstruct")
    print("")
    print(C.bold("SAÍDAS GERADAS:"))
    print("  deob_output/ANALYSIS_REPORT.md              Relatório completo em Markdown")
    print("  deob_output/shared/events_map.lua           Tabela E com nomes de eventos")
    print("  deob_output/shared/config_extracted.lua     Config lida dos scripts")
    print("  deob_output/server/main_reconstructed.lua   Estrutura do servidor")
    print("  deob_output/client/main_reconstructed.lua   Estrutura do cliente")
    print("")
end

-----------------------------------------------------------------------
-- Parse de argumentos da linha de comando
-----------------------------------------------------------------------
local function parse_args(argv)
    local opts = {
        resource_dir    = nil,
        output_dir      = nil,
        resource_name   = nil,   -- sobrescreve detecção automática do nome
        verbose         = false,
        log_file        = nil,
        max_ticks       = 3,
        no_reconstruct  = false,
    }

    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--help" or a == "-h" then
            print_help()
            os.exit(0)
        elseif a == "--verbose" or a == "-v" then
            opts.verbose = true
        elseif a == "--no-reconstruct" then
            opts.no_reconstruct = true
        elseif a == "--resource-name" or a == "--name" then
            i = i + 1
            opts.resource_name = argv[i]
            if not opts.resource_name then
                io.stderr:write("ERRO: --resource-name requer um argumento\n")
                os.exit(1)
            end
        elseif a == "--output" or a == "-o" then
            i = i + 1
            opts.output_dir = argv[i]
            if not opts.output_dir then
                io.stderr:write("ERRO: --output requer um argumento\n")
                os.exit(1)
            end
        elseif a == "--log" then
            i = i + 1
            opts.log_file = argv[i]
            if not opts.log_file then
                io.stderr:write("ERRO: --log requer um argumento\n")
                os.exit(1)
            end
        elseif a == "--max-ticks" then
            i = i + 1
            local n = tonumber(argv[i])
            if not n or n < 1 then
                io.stderr:write("ERRO: --max-ticks requer um número positivo\n")
                os.exit(1)
            end
            opts.max_ticks = math.floor(n)
        elseif a:sub(1,1) == "-" then
            io.stderr:write("ERRO: opção desconhecida: "..a.."\n")
            io.stderr:write("Use --help para ver as opções disponíveis.\n")
            os.exit(1)
        else
            -- primeiro argumento posicional = resource_dir
            if not opts.resource_dir then
                opts.resource_dir = a
            else
                io.stderr:write("ERRO: argumento inesperado: "..a.."\n")
                os.exit(1)
            end
        end
        i = i + 1
    end

    if not opts.resource_dir then
        io.stderr:write("ERRO: resource_dir é obrigatório.\n")
        io.stderr:write("Use --help para ver as opções disponíveis.\n")
        os.exit(1)
    end

    -- Normaliza o caminho
    opts.resource_dir = opts.resource_dir:gsub("/$","")

    -- Verifica se o fxmanifest existe
    local manifest_path = opts.resource_dir .. "/fxmanifest.lua"
    local alt_path      = opts.resource_dir .. "/__resource.lua"
    local f = io.open(manifest_path, "r") or io.open(alt_path, "r")
    if not f then
        io.stderr:write("ERRO: Nenhum fxmanifest.lua ou __resource.lua encontrado em: "
            ..opts.resource_dir.."\n")
        os.exit(1)
    end
    f:close()

    -- Diretório de saída padrão
    if not opts.output_dir then
        opts.output_dir = opts.resource_dir .. "/deob_output"
    end

    return opts
end

-----------------------------------------------------------------------
-- Barra de progresso textual simples
-----------------------------------------------------------------------
local function progress(step, total, label)
    local pct   = math.floor(step / total * 100)
    local width = 30
    local filled = math.floor(width * step / total)
    local bar = string.rep("█", filled) .. string.rep("░", width - filled)
    io.write(string.format("\r  [%s] %3d%%  %s    ", bar, pct, label))
    io.flush()
end

-----------------------------------------------------------------------
-- Formata número com separador de milhar
-----------------------------------------------------------------------
local function fmt_num(n)
    local s = tostring(math.floor(n or 0))
    local result = ""
    local len = #s
    for i = 1, len do
        result = result .. s:sub(i,i)
        if (len - i) % 3 == 0 and i ~= len then
            result = result .. "."
        end
    end
    return result
end

-----------------------------------------------------------------------
-- Conta elementos de uma tabela (incluindo hashes)
-----------------------------------------------------------------------
local function tcount(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-----------------------------------------------------------------------
-- Imprime resumo da extração
-----------------------------------------------------------------------
local function print_summary(result, elapsed_ms)
    local sv  = result.server
    local cl  = result.client
    local E   = result.shared_globals.E or {}
    local cfg = result.shared_globals.Config or {}

    print("\n")
    print(C.bold(C.green("═══════════════════════════════════════════════════════")))
    print(C.bold(C.green("  EXTRAÇÃO CONCLUÍDA: "..result.resource)))
    print(C.bold(C.green("═══════════════════════════════════════════════════════")))
    print(string.format("  Tempo total: %s ms", fmt_num(elapsed_ms)))
    print("")

    -- Tabela E
    local e_count = tcount(E)
    print(C.bold("  Tabela E (eventos internos):  ") .. C.yellow(tostring(e_count) .. " entradas"))

    -- Config
    if type(cfg) == "table" and next(cfg) then
        print(C.bold("  Config:                       ") .. C.yellow("✓ encontrada"))
        if cfg.Framework then
            print(C.dim("    Framework: ") .. cfg.Framework)
        end
        if cfg.Commands and type(cfg.Commands) == "table" then
            local cmd_count = tcount(cfg.Commands)
            print(C.dim("    Commands: ") .. tostring(cmd_count) .. " entradas")
        end
    else
        print(C.bold("  Config:                       ") .. C.dim("não encontrada"))
    end
    print("")

    -- Server
    print(C.bold("  ── SERVIDOR ───────────────────────────────"))
    print(string.format("  %-35s %s",
        "Eventos registrados:",
        C.yellow(tostring(tcount(sv.event_handlers)))))
    print(string.format("  %-35s %s",
        "Eventos de rede (RegisterNetEvent):",
        C.yellow(tostring(tcount(sv.net_events)))))
    print(string.format("  %-35s %s",
        "Comandos registrados:",
        C.yellow(tostring(#sv.commands))))
    print(string.format("  %-35s %s",
        "TriggerClientEvent calls:",
        C.yellow(tostring(#sv.client_events))))
    print(string.format("  %-35s %s",
        "HTTP requests observadas:",
        C.yellow(tostring(#sv.http_requests))))
    if #sv.http_requests > 0 then
        for _, req in ipairs(sv.http_requests) do
            print(C.dim("    " .. tostring(req.method) .. " → " .. tostring(req.url)))
        end
    end
    print("")

    -- Client
    print(C.bold("  ── CLIENTE ────────────────────────────────"))
    print(string.format("  %-35s %s",
        "Eventos registrados:",
        C.yellow(tostring(tcount(cl.event_handlers)))))
    print(string.format("  %-35s %s",
        "Comandos registrados:",
        C.yellow(tostring(#cl.commands))))
    print(string.format("  %-35s %s",
        "NUI Callbacks:",
        C.yellow(tostring(#cl.nui_callbacks))))
    print(string.format("  %-35s %s",
        "Keybinds:",
        C.yellow(tostring(#cl.keybinds))))
    print(string.format("  %-35s %s",
        "TriggerServerEvent calls:",
        C.yellow(tostring(#cl.server_events))))
    print(string.format("  %-35s %s",
        "AnimDicts usados:",
        C.yellow(tostring(tcount(cl.anim_dicts)))))

    -- Lista os dicts
    if next(cl.anim_dicts) then
        local dicts = {}
        for d in pairs(cl.anim_dicts) do dicts[#dicts+1] = d end
        table.sort(dicts)
        for _, d in ipairs(dicts) do
            print(C.dim("    • " .. d))
        end
    end

    print(string.format("  %-35s %s",
        "Clips de animação:",
        C.yellow(tostring(#cl.anim_plays))))
    print(string.format("  %-35s %s",
        "Modelos (GetHashKey/RequestModel):",
        C.yellow(tostring(tcount(cl.models)))))
    print(string.format("  %-35s %s",
        "Bones usados:",
        C.yellow(tostring(tcount(cl.bones_used)))))
    print(string.format("  %-35s %s",
        "AttachEntityToEntity calls:",
        C.yellow(tostring(#cl.attach_calls))))
    print(string.format("  %-35s %s",
        "State bag handlers:",
        C.yellow(tostring(#cl.state_bag_keys))))
    print(string.format("  %-35s %s",
        "Exports chamados:",
        C.yellow(tostring(tcount(cl.exports_called)))))

    -- Keybinds detalhe
    if #cl.keybinds > 0 then
        print("")
        print(C.bold("  ── KEYBINDS ───────────────────────────────"))
        for _, kb in ipairs(cl.keybinds) do
            print(string.format("  %-20s %-35s [%s/%s]",
                C.cyan("/"..tostring(kb.command)),
                tostring(kb.description),
                tostring(kb.inputType),
                tostring(kb.inputName)))
        end
    end

    -- NUI callbacks
    if #cl.nui_callbacks > 0 then
        print("")
        print(C.bold("  ── NUI CALLBACKS ──────────────────────────"))
        for _, nui in ipairs(cl.nui_callbacks) do
            print("  • " .. C.cyan(nui.name))
        end
    end

    print("")
end

-----------------------------------------------------------------------
-- Imprime lista de arquivos gerados
-----------------------------------------------------------------------
local function print_files_written(files)
    print(C.bold("  ── ARQUIVOS GERADOS ───────────────────────"))
    for _, path in ipairs(files) do
        print("  " .. C.green("✓") .. "  " .. path)
    end
    print("")
end

-----------------------------------------------------------------------
-- Verifica se lua5.4 está disponível e versão é adequada
-----------------------------------------------------------------------
local function check_lua_version()
    local major, minor = _VERSION:match("Lua (%d+)%.(%d+)")
    major = tonumber(major) or 0
    minor = tonumber(minor) or 0
    if major < 5 or (major == 5 and minor < 4) then
        io.stderr:write("AVISO: Lua "..tostring(major).."."..tostring(minor)
            .." detectada. Recomendado Lua 5.4+\n")
    end
end

-----------------------------------------------------------------------
-- Main
-----------------------------------------------------------------------
local function main()
    check_lua_version()

    -- Parses args
    local opts = parse_args(arg)

    -- Imprime banner + info inicial
    print_banner()
    print(C.bold("  Resource:   ") .. opts.resource_dir)
    if opts.resource_name then
        print(C.bold("  Nome:       ") .. opts.resource_name)
    end
    print(C.bold("  Saída:      ") .. opts.output_dir)
    print(C.bold("  Max ticks:  ") .. tostring(opts.max_ticks))
    if opts.log_file then
        print(C.bold("  Log:        ") .. opts.log_file)
    end
    if opts.verbose then
        print(C.yellow("  [VERBOSE] logs de simulação ativos"))
    end
    print("")

    -- ── Carrega módulos ────────────────────────────────────────────
    local ok_ex, EX = pcall(require, "fivem_deob.extractor")
    if not ok_ex then
        io.stderr:write("ERRO ao carregar fivem_deob.extractor:\n"..tostring(EX).."\n")
        io.stderr:write("Certifique-se de rodar de dentro do diretório do resource ou\n")
        io.stderr:write("do diretório pai de fivem_deob/.\n")
        os.exit(1)
    end

    local ok_rec, REC = pcall(require, "fivem_deob.reconstructor")
    if not ok_rec then
        io.stderr:write("ERRO ao carregar fivem_deob.reconstructor:\n"..tostring(REC).."\n")
        os.exit(1)
    end

    -- Luraph lift é opcional — não aborta se não estiver disponível
    local LLIFT = nil
    local ok_ll, ll_mod = pcall(require, "fivem_deob.luraph_lift")
    if ok_ll then
        LLIFT = ll_mod
        print(C.dim("  [luraph_lift] módulo carregado ✓"))
    else
        print(C.dim("  [luraph_lift] módulo não disponível — " .. tostring(ll_mod):sub(1,80)))
    end

    -- ── Fase 1: Extração ──────────────────────────────────────────
    print(C.bold("  Iniciando simulação..."))
    if not opts.verbose then
        progress(0, 6, "Lendo manifest...")
    end

    local t_start = os.clock()

    -- Limpa log se existir
    if opts.log_file then
        local fh = io.open(opts.log_file, "w")
        if fh then
            fh:write("-- fivem_deob simulation log: "..os.date("%Y-%m-%d %H:%M:%S").."\n")
            fh:write("-- Resource: "..opts.resource_dir.."\n\n")
            fh:close()
        end
    end

    if not opts.verbose then progress(1, 6, "Carregando scripts servidor...") end

    local result, err = EX.run(opts.resource_dir, {
        verbose       = opts.verbose,
        log_file      = opts.log_file,
        max_ticks     = opts.max_ticks,
        resource_name = opts.resource_name,
        resources     = {},
    })

    if not opts.verbose then progress(5, 6, "Finalizando extração...") end

    if not result then
        print("\n")
        io.stderr:write(C.red("ERRO na extração: ") .. tostring(err) .. "\n")
        os.exit(1)
    end

    if not opts.verbose then progress(6, 6, "Concluído!") end

    local t_end    = os.clock()
    local elapsed  = math.floor((t_end - t_start) * 1000)

    -- ── Fase 2: Resumo ────────────────────────────────────────────
    print_summary(result, elapsed)

    -- ── Fase 3: Reconstrução ──────────────────────────────────────
    local files_written = {}
    if not opts.no_reconstruct then
        print(C.bold("  Gerando arquivos reconstruídos..."))
        local ok_gen, gen_result = pcall(REC.generate, result, opts.output_dir)
        if not ok_gen then
            io.stderr:write(C.red("ERRO na reconstrução: ") .. tostring(gen_result) .. "\n")
            -- Não aborta — a extração foi bem-sucedida
        else
            files_written = gen_result
            print_files_written(files_written)
        end
    else
        print(C.dim("  [--no-reconstruct] Geração de arquivos pulada."))
        print("")
    end

    -- ── Fase 4: Luraph VM Deobfuscation ──────────────────────────────
    -- Detecta arquivos Luraph entre todos os .lua do resource e
    -- gera código Lua legível em deob_output/luraph_lift/<arquivo>.lua
    local n_all_files = result.all_files and #result.all_files or 0
    if not LLIFT then
        -- mensagem já impressa acima
    elseif n_all_files == 0 then
        print(C.dim("  [luraph_lift] nenhum .lua encontrado no resource — pulando"))
    else
        local luraph_dir = opts.output_dir .. "/luraph_lift"
        local luraph_count = 0
        local luraph_files = {}

        -- Pré-detecta quais arquivos são Luraph
        local PARSER = require("fivem_deob.luraph_lift.parser")
        print(C.dim(string.format("  [luraph_lift] escaneando %d arquivos...", n_all_files)))
        for _, rel in ipairs(result.all_files) do
            -- Normaliza separadores: Windows usa \ mas concatenamos com /
            local abs_path = opts.resource_dir .. "/" .. rel
            abs_path = abs_path:gsub("\\\\", "/"):gsub("//", "/")
            local src, _ = PARSER.read_source(abs_path)
            if src and PARSER.is_luraph(src) then
                luraph_files[#luraph_files+1] = { rel=rel, abs=abs_path }
            end
        end

        if #luraph_files == 0 then
            print(C.dim(string.format("  [luraph_lift] 0/%d arquivos Luraph detectados", n_all_files)))
        end

        if #luraph_files > 0 then
            print(C.bold("  ── LURAPH DEOBFUSCATION ───────────────────"))
            print(string.format("  %s arquivos Luraph detectados — deobfuscando...",
                C.yellow(tostring(#luraph_files))))
            print("")

            -- Cria diretório de saída (portável: tenta mkdir -p no Unix, md no Windows)
            local IS_WIN = package.config:sub(1,1) == "\\"
            if IS_WIN then
                os.execute('md "' .. luraph_dir:gsub("/","\\") .. '" 2>nul')
            else
                os.execute('mkdir -p "' .. luraph_dir .. '"')
            end

            for idx, entry in ipairs(luraph_files) do
                -- Achata a estrutura de pastas: client/main.lua → client_main_deob.lua
                local out_flat = entry.rel:gsub("[/\\]", "_"):gsub("%.lua$", "_deob.lua")
                local out_path = luraph_dir .. "/" .. out_flat

                io.write(string.format("  [%d/%d] %s ... ", idx, #luraph_files,
                    C.cyan(entry.rel)))
                io.flush()

                local ok_deob, deob_err = pcall(function()
                    LLIFT.deobfuscate(entry.abs, out_path, { verbose = false })
                end)

                if ok_deob then
                    print(C.green("OK"))
                    luraph_count = luraph_count + 1
                    files_written[#files_written+1] = out_path
                else
                    print(C.red("FALHOU") .. C.dim(" — " .. tostring(deob_err)))
                end
            end

            print("")
            print(string.format("  %s/%s arquivos deobfuscados com sucesso.",
                C.yellow(tostring(luraph_count)), tostring(#luraph_files)))
            print(C.dim("  Arquivos legíveis em: " .. luraph_dir))
            print("")
        end
    end

    -- ── Mensagem final ────────────────────────────────────────────
    print(C.bold(C.green("  ✓ Análise concluída com sucesso!")))
    if #files_written > 0 then
        print(C.dim("    Revise os arquivos gerados em: " .. opts.output_dir))
        print(C.dim("    Comece pelo ANALYSIS_REPORT.md para um visão geral completa."))
    end
    print("")

    -- Código de saída 0 = sucesso
    os.exit(0)
end

-- ── Executa ──────────────────────────────────────────────────────────
local ok, err = xpcall(main, function(e)
    return debug.traceback(e, 2)
end)
if not ok then
    io.stderr:write("\n" .. C.red("ERRO FATAL:\n") .. tostring(err) .. "\n")
    os.exit(2)
end
