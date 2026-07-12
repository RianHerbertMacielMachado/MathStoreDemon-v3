-- fivem_deob/luraph_lift/parser.lua
-- Loads a Luraph-obfuscated file and extracts the decoded instruction stream
-- by intercepting the VM executor at runtime.
--
-- STRATEGY:
--   Luraph's executor (`while true do local Z=(V[j])...`) runs in a closure
--   that has access to pre-decoded arrays T[], N[], v[], d[], U[], C[], V[].
--   We replace the coroutine-runner (x[0xD]) so when the VM tries to create
--   the executor coroutine, it gets our "recording" version instead.
--   The recording version iterates over V[] directly and logs every (Z, T, N,
--   v, d, U, C) tuple without executing any side-effects.
--
-- OUTPUT: a list of prototype tables, each with:
--   {
--     id       = integer,  -- prototype index
--     params   = integer,  -- parameter count
--     is_vararg= bool,
--     instrs   = {         -- instruction list
--       { op=Z_val, T=T[j], N=N[j], v=v[j], d=d[j], U=U[j], C=C[j] }
--     },
--     consts   = { ... },  -- L[] (constants/upvalues table)
--     upvals   = { ... },  -- upvalue descriptors
--     protos   = { ... },  -- nested prototypes (child list)
--   }

local M = {}

-- Load the Luraph file source
-- Returns: source string, or nil+err
function M.read_source(path)
  local f = io.open(path, "r")
  if not f then return nil, "cannot open: "..path end
  local src = f:read("*a")
  f:close()
  if not src or src == "" then return nil, "empty file: "..path end
  return src
end

-- Detect whether a source file is Luraph-obfuscated.
-- Returns true if the file has the characteristic Luraph VM dispatcher.
function M.is_luraph(src)
  return src:find("local Z=%(%V%[j%]%)") ~= nil
    or src:find("local Z=%(V%[j%]%)") ~= nil
    or src:find("while true do local Z=") ~= nil
end

-- Extract the executor function body (the while-true loop with local Z=(V[j]))
-- Returns the body substring or nil
function M.extract_executor_body(src)
  local s = src:find("local Z=(V[j])", 1, true)
  if not s then
    s = src:find("local Z=%(V%[j%]%)")
  end
  if not s then return nil end
  -- Return 20000 chars (enough for any Luraph variant)
  return src:sub(math.max(1, s-50), s+20000)
end

-- ============================================================
-- RUNTIME INTERCEPTION ENGINE
-- ============================================================
--
-- We execute the Luraph file in a carefully constrained environment.
-- Key trick: we intercept the coroutine wrapper (x[0xD] = coroutine.wrap)
-- so that when the VM tries to create its executor coroutine, we get
-- control instead.
--
-- The executor closure captures these upvalues:
--   V   = opcode array (V[j] gives opcode for instruction j)
--   T,N,v,d,U,C = pre-decoded field arrays indexed by instruction PC
--   B   = register file
--   L   = constants/upvalues table  (L[i] = constant/upvalue)
--   j   = instruction pointer (mutable, starts at 1)
--
-- By injecting a fake coroutine.wrap we capture the executor closure,
-- then we can iterate V[] ourselves to reconstruct each instruction.

-- Build the recording environment
-- Returns: env table, recorded_protos list
-- Create a deep-proxy table: any key access returns another proxy.
-- This allows obfuscated code to access arbitrary globals without erroring.
local function make_deep_proxy(name)
  name = name or "proxy"
  local mt = {}
  mt.__index = function(t, k)
    -- Return a child proxy for any key access
    local child = make_deep_proxy(name.."."..tostring(k))
    rawset(t, k, child)
    return child
  end
  mt.__newindex = function(t, k, v)
    rawset(t, k, v)
  end
  mt.__call = function(t, ...) return t end  -- calling a proxy returns itself
  mt.__tostring = function(t) return "<proxy:"..name..">" end
  mt.__len = function(t) return 0 end
  mt.__concat = function(a, b) return tostring(a)..tostring(b) end
  mt.__add = function(a, b) return 0 end
  mt.__sub = function(a, b) return 0 end
  mt.__mul = function(a, b) return 0 end
  mt.__div = function(a, b) return 0 end
  mt.__mod = function(a, b) return 0 end
  mt.__unm = function(a) return 0 end
  mt.__lt  = function(a, b) return false end
  mt.__le  = function(a, b) return false end
  mt.__eq  = function(a, b) return false end
  return setmetatable({}, mt)
end

local function make_recording_env()
  local protos = {}       -- collected prototype data
  local proto_stack = {}  -- stack of currently-open prototypes

  -- When Luraph calls x[0xD](executor_fn), we capture the closure
  local function intercept_coroutine_wrap(fn)
    -- We know fn is the executor inner closure:
    --   function() local Q,D,E,A,n,i,R; while true do local Z=(V[j]) ...
    -- We return a fake coroutine that, when called, records instructions
    -- instead of executing them.

    local captured = {
      fn         = fn,
      instrs     = {},
      consts     = {},
      params     = 0,
      is_vararg  = false,
    }

    -- The fake "coroutine" is just a function that the VM will call
    -- with the usual coroutine.resume semantics (ignored here)
    local function fake_coro(...)
      -- We cannot easily introspect the closed-over V[], T[], N[] etc.
      -- without debug library access. We use debug.getupvalue to extract them.
      local dbg = debug
      if not dbg then return end

      local upvals = {}
      local i = 1
      while true do
        local name, val = dbg.getupvalue(fn, i)
        if not name then break end
        upvals[name] = val
        i = i + 1
      end

      -- Extract the key arrays
      local V_arr = upvals["V"]   -- opcode array
      local T_arr = upvals["T"]   -- field T
      local N_arr = upvals["N"]   -- field N
      local v_arr = upvals["v"]   -- field v (lowercase)
      local d_arr = upvals["d"]   -- field d
      local U_arr = upvals["U"]   -- field U
      local C_arr = upvals["C"]   -- field C
      local L_tbl = upvals["L"]   -- constants/upvalues table

      if not V_arr then return end

      -- Record constants
      captured.consts = L_tbl or {}

      -- Record all instructions by walking V[]
      local instrs = {}
      for j = 1, #V_arr do
        instrs[j] = {
          j = j,
          op = V_arr[j],
          T  = T_arr and T_arr[j],
          N  = N_arr and N_arr[j],
          v  = v_arr and v_arr[j],
          d  = d_arr and d_arr[j],
          U  = U_arr and U_arr[j],
          C  = C_arr and C_arr[j],
        }
      end
      captured.instrs = instrs

      protos[#protos + 1] = captured
    end

    -- Return fake coroutine object
    return fake_coro
  end

  -- Build a safe environment for running Luraph.
  -- Uses a deep proxy as fallback for unknown globals so that
  -- obfuscated scripts which access FiveM-specific globals (Bridge, Config, etc.)
  -- don't crash with "attempt to index nil".
  local env = {}

  -- Fallback: return a deep proxy for any unknown global
  setmetatable(env, {
    __index = function(t, k)
      local p = make_deep_proxy(tostring(k))
      rawset(t, k, p)
      return p
    end,
    __newindex = rawset,
  })

  -- Core Lua globals (exact references needed for Luraph internals)
  env.tostring   = tostring
  env.tonumber   = tonumber
  env.type       = type
  env.pairs      = pairs
  env.ipairs     = ipairs
  env.next       = next
  env.select     = select
  env.unpack     = table.unpack or unpack
  env.rawget     = rawget
  env.rawset     = rawset
  env.rawequal   = rawequal
  env.rawlen     = rawlen
  env.setmetatable = setmetatable
  env.getmetatable = getmetatable
  env.pcall      = pcall
  env.xpcall     = xpcall
  env.error      = error
  env.assert     = assert
  env.load       = load
  env.loadstring = loadstring
  env.require    = function() return make_deep_proxy("require_result") end
  env.print      = function() end  -- suppress output
  env.math       = math
  env.string     = string
  env.table      = table
  env.bit32      = bit32
  env.utf8       = utf8
  env.os         = { clock=os.clock, time=os.time, date=os.date, difftime=os.difftime }
  env.io         = {  -- Provide safe io stubs (Luraph uses io for binary reading)
    open  = function() return nil end,
    read  = function() return "" end,
    write = function() end,
    close = function() end,
    lines = function() return function() end end,
    stdin  = make_deep_proxy("io.stdin"),
    stdout = make_deep_proxy("io.stdout"),
    stderr = make_deep_proxy("io.stderr"),
  }
  env.debug      = debug  -- needed for getupvalue in recording
  env.coroutine  = {
    wrap     = intercept_coroutine_wrap,
    create   = coroutine.create,
    resume   = coroutine.resume,
    yield    = coroutine.yield,
    status   = coroutine.status,
    running  = coroutine.running,
    isyieldable = coroutine.isyieldable,
    close    = coroutine.close,
  }
  env._G       = env
  env._VERSION = _VERSION

  -- FiveM / GTA stubs (common globals accessed by obfuscated scripts)
  env.exports          = make_deep_proxy("exports")
  env.AddEventHandler  = function() end
  env.TriggerEvent     = function() end
  env.TriggerNetEvent  = function() end
  env.RegisterNetEvent = function() end
  env.Citizen          = make_deep_proxy("Citizen")
  env.ESX              = make_deep_proxy("ESX")
  env.QBCore           = make_deep_proxy("QBCore")
  env.Config           = make_deep_proxy("Config")
  env.Bridge           = make_deep_proxy("Bridge")
  env.Framework        = make_deep_proxy("Framework")
  env.ox               = make_deep_proxy("ox")
  env.lib              = make_deep_proxy("lib")
  env.MySQL            = make_deep_proxy("MySQL")

  return env, protos
end

-- Execute a Luraph source in recording mode.
-- Returns: protos list, error_string
function M.execute_and_record(src)
  local env, protos = make_recording_env()

  -- Wrap source to capture errors
  local chunk, err = load(src, "@luraph_input", "t", env)
  if not chunk then
    return nil, "load error: "..tostring(err)
  end

  -- Run in protected mode; we expect some errors (missing FiveM globals etc.)
  local ok, run_err = pcall(chunk)
  -- Even if it errors out, we may have already captured prototypes

  if #protos == 0 and not ok then
    return nil, "execution error (no protos captured): "..tostring(run_err)
  end

  return protos, nil
end

-- ============================================================
-- ALTERNATIVE: STATIC EXTRACTION
-- ============================================================
-- If runtime interception fails (e.g. Luraph uses checks against sandbox),
-- we extract instruction data purely statically from the source text.
-- This gives less information but is always possible.

-- Parse integer/hex literal from Lua source
local function parse_num(s)
  if s:match("^0[xX]") then return tonumber(s) end
  return tonumber(s)
end

-- Extract all array literals from the Luraph source.
-- Luraph stores bytecode as long table constructors like:
--   {7,10,12,15,...}
-- We look for the largest numeric arrays.
function M.static_extract_arrays(src)
  -- Find the largest consecutive integer array (that's the opcode stream V[])
  local arrays = {}
  for arr_str in src:gmatch("{([%d,0-9xXa-fA-F %.,%-]+)}") do
    local nums = {}
    local valid = true
    for tok in arr_str:gmatch("[^,]+") do
      tok = tok:match("^%s*(.-)%s*$")
      local n = tonumber(tok)
      if n then
        nums[#nums+1] = n
      else
        valid = false; break
      end
    end
    if valid and #nums > 10 then
      arrays[#arrays+1] = nums
    end
  end
  -- Sort by size descending
  table.sort(arrays, function(a,b) return #a > #b end)
  return arrays
end

-- Main parse entry point.
-- path: path to Luraph .lua file
-- Returns: result table with:
--   {
--     is_luraph     = bool,
--     executor_body = string,
--     protos        = list (from runtime), may be empty,
--     arrays        = list (from static extraction),
--     error         = string or nil,
--   }
function M.parse(path)
  local result = {
    is_luraph     = false,
    executor_body = nil,
    protos        = {},
    arrays        = {},
    error         = nil,
  }

  local src, err = M.read_source(path)
  if not src then
    result.error = err
    return result
  end

  result.is_luraph = M.is_luraph(src)
  if not result.is_luraph then
    result.error = "not a Luraph-obfuscated file"
    return result
  end

  result.executor_body = M.extract_executor_body(src)

  -- Try runtime extraction first
  local protos, run_err = M.execute_and_record(src)
  if protos and #protos > 0 then
    result.protos = protos
  else
    result.error = run_err
    -- Fall back to static extraction
    result.arrays = M.static_extract_arrays(src)
  end

  return result
end

return M
