# fivem_dumper

Analisa qualquer resource FiveM *dentro* do próprio servidor — sem precisar do FiveM_Deob.exe nem de ferramenta externa.

## Como funciona

O dumper carrega os `.lua` do resource alvo (incluindo bytecode Luraph) em um ambiente instrumentado.
O **LuaJIT do FiveM executa o bytecode Luraph nativamente** — sem precisar de nenhum parser customizado.
Tudo que o script faz é capturado: AddEventHandler, TriggerServerEvent, GetHashKey, RequestAnimDict, etc.

## Instalação

1. Copie a pasta `fivem_dumper` para dentro de `resources/` do seu servidor
2. No `server.cfg`, adicione:
   ```
   ensure fivem_dumper
   ```
3. Configure permissão para o comando `/dump` (execute no console do servidor ou adicione ao server.cfg):
   ```
   add_ace group.admin command.dump allow
   ```
4. Inicie o servidor normalmente

## Uso

### Automático (recomendado)

O dumper analisa **automaticamente** qualquer resource que for iniciado após o `fivem_dumper`.

Apenas certifique-se de que `fivem_dumper` está na lista de `ensure` **antes** dos resources que você quer analisar:
```
ensure fivem_dumper
ensure MathStoreFairyWingv6   # ← será analisado automaticamente
ensure outro_resource          # ← idem
```

### Manual (comando)

No console do servidor (ou in-game, se tiver permissão `command.dump`):

```
/dump MathStoreFairyWingv6
/dump MathStoreFairyWingv6 verbose   # com logs detalhados
```

> O `/dump` funciona em qualquer resource que esteja `started` — mesmo que não tenha sido analisado no auto-mode.

## Output

Os arquivos são gerados em:
```
resources/fivem_dumper/output/<resourceName>/
├── server/
│   └── main_reconstructed.lua      ← handlers servidor reconstruídos
├── client/
│   └── main_reconstructed.lua      ← handlers cliente reconstruídos
├── shared/
│   ├── events_map.lua               ← tabela E com todos os eventos
│   └── config_extracted.lua         ← globals / Config capturados
└── ANALYSIS_REPORT.md               ← relatório completo em Markdown
```

## Configuração

No topo de `server/main.lua` você pode ajustar:

```lua
local MAX_TICKS  = 30    -- pump de threads por etapa (aumentar para resources pesados)
local AUTO_DUMP  = true  -- false = só analisa via /dump manual
```

## Diferença em relação ao FiveM_Deob.exe

| | FiveM_Deob.exe | fivem_dumper |
|---|---|---|
| Onde roda | Windows (fora do servidor) | Dentro do servidor FiveM |
| Luraph | Parser customizado (Lua 5.4) | **LuaJIT nativo** — executa direto |
| Valores capturados | Simulados | **Valores reais** de runtime |
| Dependência | Precisa do exe | Só o resource |
| Plataforma | Windows | Windows / Linux |

## Permissões

O comando `/dump` requer `ace` `command.dump`. Para habilitar:

```
# server.cfg
add_ace group.admin command.dump allow
add_principal identifier.license:SEU_LICENSE group.admin
```

Ou, para testes, habilitar para todos (não recomendado em produção):
```
add_ace builtin.everyone command.dump allow
```
