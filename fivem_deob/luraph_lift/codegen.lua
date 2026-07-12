-- fivem_deob/luraph_lift/codegen.lua
-- Converts a decoded Luraph instruction stream into readable Lua source.
--
-- INPUT: prototype list from parser.lua, opcode map from opcode_id.lua
-- OUTPUT: readable Lua source string
--
-- APPROACH:
--   We do a linear pass over the instruction list, emitting one line per
--   instruction. A second pass reconstructs control-flow (if/else/while/for)
--   from the branch instructions.
--
-- LURAPH REGISTER CONVENTION:
--   B[0]         = first local variable (after params)
--   B[1..n]      = local variables
--   B[param_n+1] = first scratch register
--
-- INSTRUCTION FIELDS:
--   op = opcode value (randomized per file, mapped via opcode_id)
--   T  = field T (often: destination reg, or jump target)
--   N  = field N (often: src reg B, or constant index)
--   v  = field v (often: src reg C, or reg index)
--   d  = field d (often: constant value, inline K)
--   U  = field U (often: constant value 2)
--   C  = field C (often: constant value 3)

local M = {}

-- ============================================================
-- REGISTER NAME GENERATION
-- ============================================================

-- We use 'var_N' for unknown registers, or map low-numbered ones
-- to param names when we know the prototype signature.

local function reg_name(i, proto)
  if proto and proto.params then
    local params = proto.params
    if i >= 1 and i <= params then
      return "arg"..i
    end
  end
  if i == 0 then return "r0" end
  return "var_"..i
end

local function const_repr(v)
  if v == nil then return "nil" end
  if type(v) == "string" then
    -- Escape for Lua string literal
    local s = v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\0","\\0")
    if #s > 80 then s = s:sub(1,77).."..." end
    return '"'..s..'"'
  end
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 2^53 then
      return tostring(math.floor(v))
    end
    return tostring(v)
  end
  if type(v) == "boolean" then return tostring(v) end
  if type(v) == "table" then return "{...}" end
  return tostring(v)
end

-- ============================================================
-- SINGLE-INSTRUCTION EMITTER
-- ============================================================

local function emit_instr(instr, opmap, proto, consts)
  local op = instr.op
  local T, N, v, d, U, C = instr.T, instr.N, instr.v, instr.d, instr.U, instr.C
  local j = instr.j
  local name = opmap and opmap[op] or ("OP_"..tostring(op))

  local function R(i) return reg_name(i, proto) end
  local function K(i)
    if consts and consts[i] ~= nil then return const_repr(consts[i]) end
    return "K["..tostring(i).."]"
  end
  local function Kd() return const_repr(d) end
  local function KU() return const_repr(U) end
  local function KC() return const_repr(C) end

  -- Emit based on opcode name
  if name == "LOADK" then
    return string.format("  local %s = %s", R(v), K(T))
  elseif name == "LOADK_d" or name == "LOADK_U" then
    -- These use state variables i,n to select dest
    return string.format("  -- LOADK (state) d=%s U=%s C=%s", Kd(), KU(), KC())
  elseif name == "LOADNIL" then
    local regs = {}
    if T and N then
      for i = T, N do regs[#regs+1] = R(i) end
    end
    return string.format("  local %s = nil", table.concat(regs, ", "))
  elseif name == "LOADSELF" then
    return string.format("  local %s = self", R(v))
  elseif name == "LOADARG" then
    return string.format("  -- LOADARG: load %s arg(s) from vararg", tostring(v))
  elseif name == "LOADBOOL_C" then
    return string.format("  -- LOADBOOL C=%s", KC())

  elseif name == "MOVE" or name == "MOVE2" or name == "MOVE_R" then
    if name == "MOVE_R" and v and T then
      return string.format("  %s = %s", R(v), R(T))
    end
    return string.format("  -- MOVE setup (state i/n)")

  elseif name == "GETUPVAL" then
    return string.format("  %s = upval[%s][%s]", R(N), tostring(T), Kd())
  elseif name == "SETUPVAL" then
    return string.format("  upval[%s] = %s", R(v), R(T))

  elseif name == "NEWTABLE" then
    return string.format("  local %s = {}", R(v))

  elseif name == "GETTABLE_RR" then
    return string.format("  %s = %s[%s]", R(v), R(N), R(T))
  elseif name == "SETTABLE_RR" then
    return string.format("  %s[%s] = %s", R(v), R(T), R(N))
  elseif name == "SETTABLE_KR" then
    return string.format("  %s[%s] = %s", R(N), R(T), Kd())
  elseif name == "SETTABLEKS" then
    return string.format("  %s[%s] = %s", R(T), KC(), R(v))

  elseif name == "SELF" then
    -- SELF: B[v] = L[T][2][B[N]] (method lookup)
    return string.format("  %s = %s:%s(%s)", R(v), "upval_obj", "method", R(N))

  elseif name == "ADD_RR" then
    return string.format("  %s = %s + %s", R(v), R(T), R(N))
  elseif name == "ADD_KK" then
    return string.format("  %s = %s + %s", R(N), KU(), Kd())
  elseif name == "SUB_RR" then
    return string.format("  %s = %s - %s", R(N), R(T), R(v))
  elseif name == "MUL_RR" then
    return string.format("  %s = %s * %s", R(v), R(T), R(N))
  elseif name == "DIV_RR" then
    return string.format("  %s = %s / %s", R(v), R(N), R(T))
  elseif name == "DIV_RK" then
    return string.format("  %s = %s / %s", R(T), R(v), KC())
  elseif name == "MOD_RR" then
    return string.format("  %s = %s %% %s", R(T), R(v), R(N))
  elseif name == "MOD_RK" then
    return string.format("  %s = %s %% %s", R(v), R(N), KU())
  elseif name == "UNM" then
    return string.format("  %s = -%s", R(v), R(T))
  elseif name == "LEN" then
    return string.format("  %s = #%s", R(T), R(N))
  elseif name == "CONCAT_KR" then
    return string.format("  %s = %s .. %s", R(N), Kd(), R(T))
  elseif name == "CONCAT_RR" then
    return string.format("  %s = %s .. %s", R(T), R(N), R(v))

  elseif name == "NOT" then
    return string.format("  %s = not %s", R(v), R(N))
  elseif name == "EQ_RR" then
    return string.format("  %s = (%s == %s)", R(N), R(v), R(T))
  elseif name == "GT_RR" then
    return string.format("  %s = (%s > %s)", R(T), R(N), R(v))
  elseif name == "LT_RR" then
    return string.format("  %s = (%s < %s)", R(N), R(T), R(v))
  elseif name == "LE_RR" then
    return string.format("  %s = (%s <= %s)", R(T), R(v), R(N))
  elseif name == "GE_RR" then
    return string.format("  %s = (%s >= %s)", R(T), R(v), R(N))
  elseif name == "NE_RR" then
    return string.format("  %s = (%s ~= %s)", R(v), R(N), R(T))
  elseif name == "NE_RK" then
    return string.format("  %s = (%s ~= %s)", R(v), R(N), KU())
  elseif name == "LT_KK" then
    return string.format("  %s = (%s < %s)", R(N), KU(), Kd())
  elseif name == "LE_KK" then
    return string.format("  %s = (%s <= %s)", R(N), KU(), Kd())
  elseif name == "EQ_KK_d" then
    return string.format("  %s = (%s == %s)", R(T), Kd(), KC())
  elseif name == "NE_KK_d" then
    return string.format("  %s = (%s ~= %s)", R(T), Kd(), KC())

  elseif name == "BOR_KK" then
    return string.format("  %s = %s | %s", R(v), KC(), KU())
  elseif name == "BAND_KK" then
    return string.format("  %s = %s & %s", R(v), KU(), KC())
  elseif name == "BXOR_RR" then
    return string.format("  %s = %s ~ %s", R(T), R(N), R(v))
  elseif name == "BXOR_RK" then
    return string.format("  %s = %s ~ %s", R(T), R(v), KC())
  elseif name == "BXOR_KK2" then
    return string.format("  %s = %s ~ %s", R(T), Kd(), KC())
  elseif name == "SHR_RK" then
    return string.format("  %s = %s >> %s", R(v), KC(), KU())

  elseif name == "EQ_JMP" then
    return string.format("  if %s == %s then goto pc_%s end", R(v), R(N), tostring(T))
  elseif name == "LE_K_JMP" then
    return string.format("  if %s <= %s then goto pc_%s end -- (inverted: jmp if NOT)", R(T), Kd(), tostring(N))
  elseif name == "LT_RK_JMP" then
    return string.format("  if not (%s < %s) then goto pc_%s end", R(v), KU(), tostring(N))
  elseif name == "LT_JMP_inv" or name == "LT_JMP_inv2" then
    return string.format("  if not (%s < %s) then goto pc_%s end", R(N), R(v), tostring(T))
  elseif name == "TEST_JMP" then
    return string.format("  if [cond] then goto pc_%s end", tostring(v))
  elseif name == "JMP" then
    return string.format("  goto pc_%s", tostring(T))

  elseif name == "CALL_MR" then
    local base = v or T
    return string.format("  %s = %s(...) -- CALL multi-ret, base=%s", R(base), R(base), tostring(base))
  elseif name == "CALL_MR2" then
    local base = T
    return string.format("  %s = %s(...) -- CALL2 multi-ret, base=%s", R(base), R(base), tostring(base))
  elseif name == "CALL_1R" or name == "CALL_1_NR" then
    local base = N or T
    return string.format("  %s(%s) -- CALL 1 arg", R(base), R(base and base+1 or 0))
  elseif name == "TAILCALL" then
    local base = v or T
    return string.format("  return %s(...) -- TAILCALL base=%s", R(base), tostring(base))
  elseif name == "CALL_0" then
    return string.format("  -- CALL setup E=B")

  elseif name == "RETURN" or name == "CLOSE_RET" then
    return "  return"
  elseif name == "RETURN_V" then
    return string.format("  return %s -- return at reg %s", R(v), tostring(v))
  elseif name == "CLOSE" then
    return "  -- CLOSE upvalues"

  elseif name == "FORPREP" then
    return string.format("  -- FORPREP: for loop init at B[%s], jump to pc_%s", tostring(N), tostring(v))
  elseif name == "FORLOOP" then
    return string.format("  -- FORLOOP step")
  elseif name == "TFORLOOP" then
    return string.format("  -- TFORLOOP (generic for), base=%s, jump=%s", tostring(N), tostring(v))

  elseif name == "VARARG" then
    return string.format("  local %s, ... = ... -- VARARG into %s regs", R(T), tostring(v))
  elseif name == "CLOSURE" then
    return string.format("  local %s = function(...) --[[proto %s]] end", R(N), Kd())

  else
    -- Unknown / state-machine step: emit raw data
    return string.format("  -- %s  T=%s N=%s v=%s d=%s U=%s C=%s",
      name,
      tostring(T), tostring(N), tostring(v),
      const_repr(d), const_repr(U), const_repr(C))
  end
end

-- ============================================================
-- PROTOTYPE EMITTER
-- ============================================================

-- Emit a full prototype as a Lua function body
local function emit_proto(proto, opmap, indent, proto_id)
  indent = indent or 0
  proto_id = proto_id or 0
  local pad = string.rep("  ", indent)
  local lines = {}

  local function add(s) lines[#lines+1] = pad..s end

  -- Header comment
  add(string.format("-- [[ Prototype %d | params=%s | vararg=%s | instrs=%d ]]",
    proto_id,
    tostring(proto.params or "?"),
    tostring(proto.is_vararg or false),
    proto.instrs and #proto.instrs or 0))

  -- Build a set of jump targets for label placement
  local jump_targets = {}
  if proto.instrs then
    for _, instr in ipairs(proto.instrs) do
      local op = instr.op
      local name = opmap and opmap[op] or ""
      if name:find("JMP") or name == "FORPREP" or name == "FORLOOP" or name == "TFORLOOP" then
        if instr.T then jump_targets[instr.T] = true end
        if instr.N then jump_targets[instr.N] = true end
        if instr.v then jump_targets[instr.v] = true end
      end
    end
  end

  -- Emit each instruction
  local consts = proto.consts
  if proto.instrs then
    for _, instr in ipairs(proto.instrs) do
      -- Emit label if this PC is a jump target
      if jump_targets[instr.j] then
        add(string.format("  ::pc_%d::", instr.j))
      end
      local line = emit_instr(instr, opmap, proto, consts)
      if line then
        add(line)
      end
    end
  else
    add("  -- (no instructions captured)")
  end

  return table.concat(lines, "\n")
end

-- ============================================================
-- MAIN CODEGEN ENTRY POINT
-- ============================================================

-- Generate readable Lua from parsed prototypes + opcode map.
-- protos: list from parser.M.parse(path).protos
-- opmap:  table from opcode_id.M.identify(executor_body)
-- Returns: Lua source string
function M.generate(protos, opmap, filename)
  filename = filename or "unknown"
  local sections = {}

  -- Header
  sections[#sections+1] = string.format(
    "-- Deobfuscated by luraph_lift\n-- Source: %s\n-- Prototypes: %d\n",
    filename, #protos)

  if #protos == 0 then
    sections[#sections+1] = "-- WARNING: No prototypes were captured.\n"
    sections[#sections+1] = "-- The static analysis could not extract bytecode.\n"
    sections[#sections+1] = "-- Check parser.lua for errors.\n"
    return table.concat(sections, "\n")
  end

  -- Emit each prototype
  for i, proto in ipairs(protos) do
    sections[#sections+1] = "\n"
    sections[#sections+1] = string.format("-- ====== PROTOTYPE %d ======\n", i)
    sections[#sections+1] = "local function proto_"..i.."(...)\n"
    sections[#sections+1] = emit_proto(proto, opmap, 0, i)
    sections[#sections+1] = "\nend\n"
  end

  return table.concat(sections)
end

-- ============================================================
-- OPCODE STAT REPORTER
-- ============================================================

-- Report how many instructions of each semantic type appear
function M.stat_report(protos, opmap)
  local counts = {}
  local total = 0
  for _, proto in ipairs(protos) do
    if proto.instrs then
      for _, instr in ipairs(proto.instrs) do
        local name = opmap and opmap[instr.op] or ("OP_"..tostring(instr.op))
        counts[name] = (counts[name] or 0) + 1
        total = total + 1
      end
    end
  end
  local sorted = {}
  for k,v in pairs(counts) do sorted[#sorted+1] = {k,v} end
  table.sort(sorted, function(a,b) return a[2] > b[2] end)
  local lines = {string.format("Total instructions: %d", total)}
  for _, kv in ipairs(sorted) do
    lines[#lines+1] = string.format("  %-25s %5d  (%.1f%%)", kv[1], kv[2], kv[2]/total*100)
  end
  return table.concat(lines, "\n")
end

return M
