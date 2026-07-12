-- fivem_deob/luraph_lift/init.lua
-- Top-level entry point for the Luraph VM lifter / deobfuscator.
--
-- USAGE:
--   local lift = require("fivem_deob/luraph_lift/init")
--   local result = lift.deobfuscate(input_path, output_path, opts)
--   if result.ok then print("written to "..output_path)
--   else print("error: "..result.error) end
--
-- STANDALONE (CLI):
--   lua54 fivem_deob/luraph_lift/init.lua <input.lua> [output.lua]

local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[/\\])") or ""

-- Resolve module paths relative to this file's directory
local function require_local(name)
  local path = script_dir..name..".lua"
  local chunk, err = loadfile(path)
  if not chunk then
    -- Try as plain require fallback
    return require(name)
  end
  return chunk()
end

local parser   = require_local("parser")
local opcode_id = require_local("opcode_id")
local codegen  = require_local("codegen")

local M = {}

-- Main deobfuscation function.
-- input_path  : path to a .lua file obfuscated with Luraph
-- output_path : where to write the readable output (nil = return as string)
-- opts        : optional settings table:
--     opts.verbose  = bool  (print progress)
--     opts.stats    = bool  (include instruction count stats in output)
-- Returns: { ok=bool, output=string_or_nil, error=string_or_nil, stats=string_or_nil }
function M.deobfuscate(input_path, output_path, opts)
  opts = opts or {}
  local result = { ok=false }

  local function log(...)
    if opts.verbose then io.stderr:write(string.format(...), "\n") end
  end

  -- ── Step 1: Read and validate source ──────────────────────────────────────
  log("Reading: %s", input_path)
  local src, err = parser.read_source(input_path)
  if not src then
    result.error = "Cannot read file: "..tostring(err)
    return result
  end

  if not parser.is_luraph(src) then
    result.error = "Not a Luraph-obfuscated file (no VM dispatcher found)"
    return result
  end
  local luraph_ver = parser.luraph_version(src)
  log("Confirmed: Luraph obfuscation detected (%d bytes, version=%s)", #src, tostring(luraph_ver))

  -- ── Step 2: Extract executor body for opcode identification ───────────────
  -- Only v1 ("while true do local Z=...") has a parseable dispatch tree.
  -- v2 ("repeat local J=Z[V]") uses a binary if-tree; opcode_id.lua handles it separately.
  log("Extracting executor body...")
  local exec_body = parser.extract_executor_body(src)
  if not exec_body then
    -- v2 files often have no "while true do local Z=" pattern.
    -- We skip static opcode identification and go straight to runtime capture.
    log("No executor body found (v2 variant) -- skipping static opcode identification")
  else
    log("Executor body: %d chars", #exec_body)
  end

  -- ── Step 3: Identify opcodes from dispatch tree (v1 only) ─────────────────
  log("Identifying opcodes from dispatch tree...")
  local opmap, namemap = opcode_id.identify(exec_body or "")
  local n_ops = 0
  for _ in pairs(opmap) do n_ops = n_ops + 1 end
  log("Identified %d opcodes", n_ops)

  if opts.verbose and n_ops > 0 then
    io.stderr:write("Opcode map:\n"..opcode_id.dump(opmap).."\n")
  end

  -- ── Step 4: Execute and record instruction streams ────────────────────────
  log("Executing in recording mode to capture bytecode...")
  local protos, run_err = parser.execute_and_record(src)

  if protos and #protos > 0 then
    log("Captured %d prototype(s) via runtime interception", #protos)
  else
    -- 0 protos is expected for files with anti-tamper (bones.lua) or v2 files
    -- that call FiveM natives the sandbox can't satisfy (verificar.lua).
    -- Don't abort -- we still produce a useful partial output with the opcode map.
    local note = tostring(run_err)
    log("Runtime capture: 0 prototypes (%s) -- generating partial output", note)
    protos = {}
  end

  -- ── Step 5: Generate readable Lua ────────────────────────────────────────
  log("Generating readable Lua...")
  local output = codegen.generate(protos, opmap, input_path)

  -- Append stats if requested
  if opts.stats and #protos > 0 then
    local stats = codegen.stat_report(protos, opmap)
    output = output .."\n\n--[[\n"..stats.."\n]]\n"
  end

  -- Prepend a header note if no runtime capture happened
  if #protos == 0 then
    local ver_str = tostring(luraph_ver or "v2")
    output = "--[[ LURAPH "..ver_str..": partial output (0 VM prototypes captured at runtime)\n"
      .."--   File: "..input_path.."\n"
      .."--   Cause: anti-tamper triggered OR this "..ver_str.." file requires FiveM natives.\n"
      .."--   The opcode map (v1 only) and executor structure are extracted below.\n"
      .."--   For full deobfuscation of v2 files, run on a real FiveM server.\n"
      .."]]".."\n\n" .. output
  end

  -- Always append the opcode map as a comment
  output = output .."\n--[[ OPCODE MAP (this file):\n"..opcode_id.dump(opmap).."\n]]\n"

  -- ── Step 6: Write or return ───────────────────────────────────────────────
  if output_path then
    local f = io.open(output_path, "w")
    if not f then
      result.error = "Cannot write output: "..output_path
      return result
    end
    f:write(output)
    f:close()
    log("Written: %s (%d bytes)", output_path, #output)
  end

  result.ok     = true
  result.output = output
  result.opmap  = opmap
  result.protos = protos
  if opts.stats and #protos > 0 then
    result.stats = codegen.stat_report(protos, opmap)
  end
  return result
end

-- ============================================================
-- CLI ENTRY POINT
-- ============================================================

-- Detect if running as main script (NOT when required as a module).
--
-- ROOT CAUSE OF BUG: when deob.lua calls require("fivem_deob.luraph_lift"),
-- Lua loads this file but arg[0] = "deob.lua" and arg[1] = resource_dir.
-- The old check (source:find("init.lua$")) matched because debug.getinfo
-- returns THIS file's path — even when loaded as a module, not as main.
--
-- FIX: check arg[0] (the ACTUAL entry script). If it ends in "deob.lua"
-- or doesn't contain "init.lua" we are NOT the main script.
-- Also require arg[1] to look like a .lua file (ends in .lua), not a
-- directory path or a flag like "--output".
local _arg0 = arg and arg[0] and tostring(arg[0]):gsub("\\", "/") or ""
local is_main = arg ~= nil
  and _arg0:find("init%.lua$") ~= nil        -- arg[0] must end in init.lua
  and not _arg0:find("deob%.lua$")            -- NOT deob.lua running us as module
  and arg[1] ~= nil                           -- must have an input argument
  and arg[1]:find("%.lua$") ~= nil            -- arg[1] must be a .lua file path
  and arg[1]:sub(1, 2) ~= "--"               -- not a flag

if is_main then
  local input  = arg[1]
  local output = arg[2] or (input:gsub("%.lua$", "").."_deob.lua")

  local opts = {
    verbose = true,
    stats   = true,
  }

  io.stderr:write(string.format("[luraph_lift] %s  →  %s\n", input, output))
  local result = M.deobfuscate(input, output, opts)

  if result.ok then
    io.stderr:write(string.format("[luraph_lift] Done. %d protos, %d opcodes identified.\n",
      #(result.protos or {}), (function()
        local n=0; for _ in pairs(result.opmap or {}) do n=n+1 end; return n
      end)()))
    os.exit(0)
  else
    io.stderr:write("[luraph_lift] ERROR: "..tostring(result.error).."\n")
    -- Even on error, write partial output if we have it
    if result.output and output then
      local f = io.open(output, "w")
      if f then f:write(result.output); f:close() end
    end
    os.exit(1)
  end
end

return M
