#!/usr/bin/env python3
"""
luac54_fivem_to_std.py  —  v4  (final)
=======================================
Converte bytecode Lua 5.4 do FiveM/CitizenFX para Lua 5.4 padrão
(compatível com Coldzer0 e luac5.4 -p).

=== DIFERENÇAS FiveM vs. Padrão (CitizenFX Lua 5.4) ===

Header (31 bytes):
  Ambos usam o mesmo header, incluindo sz_instr=8.
  O ÚNICO campo diferente é a presença do byte [31] "nups_extra" no FiveM.

Encoding interno do proto:
  IDÊNTICO ao padrão neste sistema (rev_uleb128, strings compactas, instrucões 4 bytes).
  O luac5.4 local (/usr/bin/luac5.4 e luac5.4 CX) ambos usam o formato CitizenFX.

Tipos de constante — ÚNICA diferença real:
  FiveM usa 0x05 para short string, padrão usa 0x04.
  FiveM usa 0x15 para long  string, padrão usa 0x14.
  Todos os outros tipos são idênticos.

O que o conversor faz:
  1. Copia o header byte-a-byte (sem alterações)
  2. Percorre o proto recursivamente via FiveM DumpSize (rev_uleb128)
  3. Remapeia 0x05→0x04 e 0x15→0x14 nos bytes de tipo de constante
  4. Copia TODO o resto literalmente (instruções, strings, debug info, etc.)

Por que isso basta:
  O Coldzer0 rejeita o bytecode FiveM original com "unknown constant type 0x5".
  Após remapear os tipos de constante, o arquivo é aceito pelo Coldzer0.
  O luac5.4 -p também passa.

Uso:
  python3 luac54_fivem_to_std.py <input.luac> [output.luac]
  python3 luac54_fivem_to_std.py <pasta/> [pasta_saida/]
"""

import sys
import os
import struct
import shutil


# ─── Encoding helpers ─────────────────────────────────────────────────────────

def read_dump_size(data: bytes, pos: int) -> tuple[int, int]:
    """
    CitizenFX DumpSize (ULEB128 invertido):
      bit7=1 → TERMINA, bit7=0 → CONTINUA
    Retorna (valor, nova_posição).
    """
    result = 0
    shift  = 0
    while True:
        b = data[pos]; pos += 1
        result |= (b & 0x7f) << shift
        if b & 0x80:
            break
        shift += 7
    return result, pos


def write_dump_size(buf: bytearray, value: int):
    """Escreve um inteiro em CitizenFX DumpSize (copia idêntica à leitura)."""
    # Precisamos reproduzir os mesmos bytes que foram lidos.
    # Para valores simples (< 128): um único byte com bit7=1 e val nos bits 0-6.
    # Isso é o que o CX escreve: basta escrever o valor com bit7 forçado.
    # PORÉM: para valores ≥ 128 o encoding é multi-byte e precisamos ser exatos.
    # Como copiamos a maioria do conteúdo literalmente, só usamos isso onde necessário.
    if value < 128:
        buf.append(value | 0x80)
    else:
        # Extrai 7 bits por vez; último byte tem bit7=1, outros têm bit7=0
        while True:
            chunk = value & 0x7f
            value >>= 7
            if value == 0:
                buf.append(chunk | 0x80)   # terminal
                break
            else:
                buf.append(chunk)          # continua


def read_fivem_string_span(data: bytes, pos: int) -> int:
    """
    Retorna o NÚMERO DE BYTES que a string FiveM ocupa (incluindo o byte de prefixo).
    Não decodifica o conteúdo — apenas mede para poder copiar.
    """
    b = data[pos]
    if b == 0x00:
        return 1
    if b == 0xff:
        slen = int.from_bytes(data[pos+1:pos+9], 'little')
        return 1 + 8 + (slen - 1 if slen > 0 else 0)
    # bit7 deve ser 1
    slen = (b & 0x7f) - 1
    return 1 + max(0, slen)


# ─── Conversor principal ──────────────────────────────────────────────────────

def remap_constants(data: bytes, pos: int, buf: bytearray) -> int:
    """
    Percorre as constantes de um proto, remapeando os bytes de tipo.
    Retorna a nova posição após as constantes.
    """
    n_const, pos = read_dump_size(data, pos)
    write_dump_size(buf, n_const)

    for _ in range(n_const):
        tt = data[pos]

        # Remapeia tipo de string FiveM → padrão
        if   tt == 0x05:  buf.append(0x04); pos += 1   # short string: 0x05 → 0x04
        elif tt == 0x15:  buf.append(0x14); pos += 1   # long  string: 0x15 → 0x14
        else:             buf.append(tt);   pos += 1   # outros tipos: cópia literal

        # Payload da constante (cópia literal)
        base = tt & 0x0F
        if base == 0:                    # nil / false / true — sem payload
            pass
        elif base == 1:                  # nil / bool — sem payload
            pass
        elif base == 3:                  # número (float 0x03/0x14 ou int 0x13): 8 bytes
            buf.extend(data[pos:pos+8]); pos += 8
        elif base in (4, 5):             # string (0x04/0x05/0x14/0x15): string compacta
            span = read_fivem_string_span(data, pos)
            buf.extend(data[pos:pos+span]); pos += span
        else:
            raise ValueError(
                f"Tipo de constante desconhecido: 0x{tt:02x} na pos {pos-1}")

    return pos


def convert_proto(data: bytes, pos: int, buf: bytearray) -> int:
    """
    Converte recursivamente um proto FiveM → padrão.
    Copia tudo literalmente exceto os tipos de constante.
    Retorna nova posição.
    """

    # 1. source name (copia literal)
    span = read_fivem_string_span(data, pos)
    buf.extend(data[pos:pos+span]); pos += span

    # 2. linedefined (rev_uleb128)
    ld, pos_new = read_dump_size(data, pos)
    buf.extend(data[pos:pos_new]); pos = pos_new

    # 3. lastlinedefined (rev_uleb128)
    lld, pos_new = read_dump_size(data, pos)
    buf.extend(data[pos:pos_new]); pos = pos_new

    # 4. numparams, 5. is_vararg, 6. maxstacksize (1 byte cada)
    buf.extend(data[pos:pos+3]); pos += 3

    # 7-8. n_code + instruções (4 bytes cada)
    n_code_start = pos
    n_code, pos_new = read_dump_size(data, pos)
    buf.extend(data[pos:pos_new]); pos = pos_new   # escreve n_code
    buf.extend(data[pos:pos + n_code * 4])          # escreve instruções
    pos += n_code * 4

    # 9-10. n_const + constantes (COM remapeamento de tipo)
    pos = remap_constants(data, pos, buf)

    # 11-12. n_upvalues + upvalues (3 bytes por upvalue)
    n_upv_start = pos
    n_upv, pos_new = read_dump_size(data, pos)
    buf.extend(data[pos:pos_new]); pos = pos_new
    buf.extend(data[pos:pos + n_upv * 3]); pos += n_upv * 3

    # 13-14. n_protos + sub-protos (recursivo)
    n_proto_start = pos
    n_proto, pos_new = read_dump_size(data, pos)
    buf.extend(data[pos:pos_new]); pos = pos_new
    for _ in range(n_proto):
        pos = convert_proto(data, pos, buf)

    # 15-16. n_lineinfo + lineinfo (1 byte por instrução)
    n_li, pos_new = read_dump_size(data, pos)
    buf.extend(data[pos:pos_new]); pos = pos_new
    buf.extend(data[pos:pos + n_li]); pos += n_li

    # 17-18. n_abslineinfo + abslineinfo (pairs de rev_uleb128: pc, line)
    n_ali, pos_new = read_dump_size(data, pos)
    buf.extend(data[pos:pos_new]); pos = pos_new
    for _ in range(n_ali):
        # pc
        _, pos_new2 = read_dump_size(data, pos)
        buf.extend(data[pos:pos_new2]); pos = pos_new2
        # line
        _, pos_new2 = read_dump_size(data, pos)
        buf.extend(data[pos:pos_new2]); pos = pos_new2

    # 19-20. n_locvars + locvars
    n_lv, pos_new = read_dump_size(data, pos)
    buf.extend(data[pos:pos_new]); pos = pos_new
    for _ in range(n_lv):
        span = read_fivem_string_span(data, pos)
        buf.extend(data[pos:pos+span]); pos += span
        # startpc
        _, pos_new = read_dump_size(data, pos)
        buf.extend(data[pos:pos_new]); pos = pos_new
        # endpc
        _, pos_new = read_dump_size(data, pos)
        buf.extend(data[pos:pos_new]); pos = pos_new

    # 21-22. n_upvaluenames + upvalue names
    n_uvn, pos_new = read_dump_size(data, pos)
    buf.extend(data[pos:pos_new]); pos = pos_new
    for _ in range(n_uvn):
        span = read_fivem_string_span(data, pos)
        buf.extend(data[pos:pos+span]); pos += span

    return pos


class ObfuscatedBytecodeError(Exception):
    """Levantada quando o bytecode contém opcodes inválidos (obfuscação extra)."""
    pass


def _detect_obfuscated(data: bytes) -> bool:
    """
    Heurística rápida: lê as instruções do proto de nível superior e verifica se
    algum opcode está fora do intervalo 0-82 (Lua 5.4 padrão).
    Retorna True se o bytecode parecer obfuscado/cifrado.
    """
    import struct
    try:
        b = data[32]
        if b == 0x00:
            pos = 33
        elif b == 0xff:
            slen = int.from_bytes(data[33:41], 'little')
            pos = 33 + 8 + (slen - 1 if slen > 0 else 0)
        else:
            slen = (b & 0x7f) - 1
            pos = 33 + max(0, slen)
        _, pos = read_dump_size(data, pos)   # linedefined
        _, pos = read_dump_size(data, pos)   # lastlinedefined
        pos += 3                             # numparams, is_vararg, maxstack
        n_code, pos = read_dump_size(data, pos)
        if n_code > 500_000:
            return True  # absurdamente grande → misparse por obfuscação
        for i in range(min(n_code, 4096)):
            instr = struct.unpack_from('<I', data, pos + i * 4)[0]
            if (instr & 0x7f) > 82:
                return True
        return False
    except Exception:
        return True   # erro de parse → tratar como obfuscado


def convert_chunk(data: bytes) -> bytes:
    """
    Converte chunk FiveM → padrão.
    Retorna bytes convertidos.
    Lança ObfuscatedBytecodeError se o bytecode estiver obfuscado/cifrado.
    """
    if len(data) < 32:
        raise ValueError("Arquivo muito pequeno para ser Lua 5.4 bytecode")
    if data[0:4] != b'\x1bLua':
        raise ValueError("Magic inválido (não é Lua bytecode)")
    if data[4] != 0x54:
        raise ValueError(f"Não é Lua 5.4 (version byte = 0x{data[4]:02x})")

    # Detecta obfuscação antes de tentar parsear
    if _detect_obfuscated(data):
        raise ObfuscatedBytecodeError(
            "Bytecode com obfuscação adicional detectada: opcodes fora do intervalo "
            "Lua 5.4 padrão (>82). O servidor aplica uma camada de cifra extra neste "
            "arquivo — não é possível converter nem decompilação com ferramentas padrão."
        )

    buf = bytearray()
    buf.extend(data[0:32])   # copia header inteiro (bytes 0-31)

    pos = 32
    try:
        pos = convert_proto(data, pos, buf)
    except Exception as e:
        raise ValueError(f"Erro ao parsear proto na pos {pos}: {e}") from e

    if pos != len(data):
        leftover = len(data) - pos
        print(f"  [AVISO] {leftover} bytes não consumidos após proto (pos={pos}/{len(data)})",
              file=sys.stderr)

    return bytes(buf)


def convert_file(src: str, dst: str) -> bool:
    try:
        data = open(src, 'rb').read()
    except OSError as e:
        print(f"[ERRO]  Leitura {src}: {e}", file=sys.stderr)
        return False

    if len(data) < 5 or data[0:4] != b'\x1bLua' or data[4] != 0x54:
        print(f"[SKIP]  {src} — não é Lua 5.4 bytecode")
        return False

    try:
        result = convert_chunk(data)
    except ObfuscatedBytecodeError as e:
        print(f"[OBFS]  {src}: {e}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"[ERRO]  {src}: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return False

    try:
        os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
        open(dst, 'wb').write(result)
        print(f"[CONV]  {src} → {dst}  ({len(data)} → {len(result)} bytes)")
        return True
    except OSError as e:
        print(f"[ERRO]  Escrita {dst}: {e}", file=sys.stderr)
        return False


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    src  = sys.argv[1]
    dst  = sys.argv[2] if len(sys.argv) > 2 else None

    if os.path.isdir(src):
        dst = dst or (src.rstrip('/\\') + '_std')
        ok = fail = 0
        for root, _, files in os.walk(src):
            for fn in sorted(files):
                sp = os.path.join(root, fn)
                dp = os.path.join(dst, os.path.relpath(sp, src))
                if convert_file(sp, dp):
                    ok += 1
                else:
                    fail += 1
        print(f"\nTotal: {ok} convertidos, {fail} erros/skips")
    else:
        if dst is None:
            base, ext = os.path.splitext(src)
            dst = base + '_std' + (ext or '.luac')
        if convert_file(src, dst):
            print(f"\nPara decompilação:")
            print(f"  /home/user/coldzer0_bin/cLuaDecompiler {dst}")


if __name__ == '__main__':
    main()
