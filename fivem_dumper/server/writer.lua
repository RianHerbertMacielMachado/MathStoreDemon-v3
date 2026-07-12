-----------------------------------------------------------------------
-- fivem_dumper/server/writer.lua  — v3.0
--
-- Responsável por escrever arquivos de output via SaveResourceFile.
--
-- ESTRATÉGIA para SaveResourceFile funcionar com subdirectórios:
--   SaveResourceFile só escreve em caminhos que já existem no disco.
--   Para criar o caminho "output/vrp/server/main.lua" precisamos que
--   os diretórios "output/", "output/vrp/", "output/vrp/server/"
--   existam FISICAMENTE. Tocamos um sentinel "._keep" em cada nível
--   para forçar o FiveM a criar o diretório.
--
--   Se mesmo assim falhar (alguns artifacts mais antigos ignoram o
--   ._keep e não criam o dir), usamos um caminho PLANO como fallback:
--   "output/<res>__<caminho_com_underscores>" na raiz do resource.
--
-- WRITER.write(rel_path, content) → true/false
-- WRITER.write_text(rel_path, text) → true/false
-----------------------------------------------------------------------

WRITER = {}

local _res = GetCurrentResourceName()

-----------------------------------------------------------------------
-- Cria estrutura de diretórios tocando um ._keep em cada nível.
-- Retorna true se o diretório final parece existir (sentinel escrito).
-----------------------------------------------------------------------
local function ensure_dirs(rel_dir)
    -- Garante que "output" existe primeiro
    -- (necessário antes de qualquer subdir)
    local acc = ""
    for seg in rel_dir:gmatch("[^/]+") do
        if acc == "" then
            acc = seg
        else
            acc = acc.."/"..seg
        end
        -- Escreve sentinel no nível acc
        local sentinel = acc.."/._keep"
        SaveResourceFile(_res, sentinel, "", 0)
    end
    -- Verifica se o sentinel do último nível foi criado
    -- (ReadResourceFile no próprio resource não existe, usamos LoadResourceFile)
    local check = LoadResourceFile(_res, rel_dir.."/._keep")
    return check ~= nil
end

-----------------------------------------------------------------------
-- Tenta escrever `content` em `rel_path` (relativo ao fivem_dumper).
-- Estratégia:
--   1. Cria os diretórios via ensure_dirs
--   2. Tenta SaveResourceFile no caminho original
--   3. Se falhar, tenta um caminho plano (flat fallback)
-- Retorna true se qualquer tentativa funcionou.
-----------------------------------------------------------------------
function WRITER.write(rel_path, content)
    -- ──────────────────────────────────────────────────────────────
    -- Tentativa 1: caminho hierárquico (output/res/server/file.luac)
    -- ──────────────────────────────────────────────────────────────
    local dir = rel_path:match("^(.+)/[^/]+$")
    if dir then
        ensure_dirs(dir)
    end

    local ok = SaveResourceFile(_res, rel_path, content, #content)
    if ok then
        return true
    end

    -- ──────────────────────────────────────────────────────────────
    -- Tentativa 2: caminho plano na raiz do resource
    -- output/vrp/server/main.lua  →  output_vrp__server__main.lua
    -- ──────────────────────────────────────────────────────────────
    local flat = rel_path:gsub("/", "__")
    ok = SaveResourceFile(_res, flat, content, #content)
    if ok then
        print(string.format(
            "^3[Dumper] AVISO: caminho plano usado para %s → %s^7",
            rel_path, flat))
        return true
    end

    -- ──────────────────────────────────────────────────────────────
    -- Tentativa 3: apenas "output/<res>__<filename>" (2 níveis → 1)
    -- ──────────────────────────────────────────────────────────────
    local fname = rel_path:match("[^/]+$") or "file.bin"
    local prefix = rel_path:match("^output/([^/]+)/") or "res"
    local ultra_flat = "output__"..prefix.."__"..fname
    ok = SaveResourceFile(_res, ultra_flat, content, #content)
    if ok then
        print(string.format(
            "^3[Dumper] AVISO: ultra-flat usado para %s → %s^7",
            rel_path, ultra_flat))
        return true
    end

    print(string.format("^1[Dumper] ERRO: não foi possível escrever: %s^7", rel_path))
    return false
end

-----------------------------------------------------------------------
-- Variante de escrita para conteúdo de texto (UTF-8).
-- Idêntico a WRITER.write mas documenta a intenção.
-----------------------------------------------------------------------
function WRITER.write_text(rel_path, text)
    return WRITER.write(rel_path, text)
end

-----------------------------------------------------------------------
-- Log de inicialização
-----------------------------------------------------------------------
print("^5[Dumper]^7 Writer v3.1 carregado — SaveResourceFile com tamanho explícito (#content).")
