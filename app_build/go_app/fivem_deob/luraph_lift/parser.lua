-- fivem_deob/luraph_lift/parser.lua
-- Loads a Luraph-obfuscated file and extracts the decoded instruction stream
-- by intercepting the VM executor at runtime via debug.sethook.
--
-- HOW IT WORKS:
--   Luraph stores coroutine.wrap as an obfuscated alias (s.u → x[0xD]),
--   so proxy __call interception does NOT work. Instead, we install a
--   debug.sethook("c") hook that fires on EVERY function call. When a call
--   matches the Luraph executor signature (nups >= 6, upvalue "V" is a table,
--   upvalue "j" is a number, source == "@luraph_input"), we capture the entire
--   instruction arrays before they run.
--
-- INSTRUCTION ARRAYS (pre-decoded by Luraph before executor runs):
--   V[j] = opcode  |  T[j], N[j], v[j], d[j], U[j], C[j] = fields
--   B[]  = register file  |  L[] = constants table
--   j    = instruction pointer (starts at 1)
--
-- DEDUPLICATION:
--   Same prototypes repeat when Luraph functions are called in loops.
--   We fingerprint each proto by table.concat(V[], ",") and only keep uniques.

local M = {}

-- ── Source helpers ────────────────────────────────────────────────────────────

function M.read_source(path)
  local f = io.open(path, "r")
  if not f then return nil, "cannot open: "..path end
  local src = f:read("*a")
  f:close()
  if not src or src == "" then return nil, "empty file: "..path end
  return src
end

function M.is_luraph(src)
  return src:find("local Z=(V[j])", 1, true) ~= nil
    or  src:find("local Z=%(V%[j%]%)") ~= nil
    or  src:find("while true do local Z=") ~= nil
end

function M.extract_executor_body(src)
  local s = src:find("local Z=(V[j])", 1, true)
  if not s then s = src:find("local Z=%(V%[j%]%)") end
  if not s then return nil end
  -- grab a generous window: 100 chars before + 25000 after
  return src:sub(math.max(1, s - 100), s + 25000)
end

-- ── Fingerprint helper ────────────────────────────────────────────────────────

local function fingerprint_V(V)
  -- Build a short hash from the opcode sequence
  local parts = {}
  for i = 1, math.min(#V, 50) do
    parts[i] = tostring(V[i])
  end
  parts[#parts+1] = tostring(#V)
  return table.concat(parts, ",")
end

-- ── Sandbox environment ───────────────────────────────────────────────────────
-- Luraph needs real Lua stdlib; FiveM globals get deep-proxy stubs.

local function make_proxy(name)
  local mt = {}
  mt.__index = function(t, k)
    local child = make_proxy((name or "?").."."..tostring(k))
    rawset(t, k, child)
    return child
  end
  mt.__newindex  = rawset
  mt.__call      = function(t, ...) return make_proxy((name or "?").."()") end
  mt.__tostring  = function() return "<proxy:"..(name or "?")..">" end
  mt.__len       = function() return 0 end
  mt.__concat    = function(a, b) return tostring(a)..tostring(b) end
  mt.__add       = function() return 0 end
  mt.__sub       = function() return 0 end
  mt.__mul       = function() return 0 end
  mt.__div       = function() return 1 end
  mt.__mod       = function() return 0 end
  mt.__pow       = function() return 1 end
  mt.__unm       = function() return 0 end
  mt.__idiv      = function() return 0 end
  mt.__band      = function() return 0 end
  mt.__bor       = function() return 0 end
  mt.__bxor      = function() return 0 end
  mt.__bnot      = function() return 0 end
  mt.__shl       = function() return 0 end
  mt.__shr       = function() return 0 end
  mt.__lt        = function() return false end
  mt.__le        = function() return false end
  mt.__eq        = function() return false end
  return setmetatable({}, mt)
end

local function build_sandbox()
  local env = {}
  setmetatable(env, {
    __index    = function(t, k) local p = make_proxy(k); rawset(t,k,p); return p end,
    __newindex = rawset,
  })

  -- Real Lua stdlib (Luraph internals need these)
  env.tostring     = tostring
  env.tonumber     = tonumber
  env.type         = type
  env.pairs        = pairs
  env.ipairs       = ipairs
  env.next         = next
  env.select       = select
  env.unpack       = table.unpack or unpack
  env.rawget       = rawget
  env.rawset       = rawset
  env.rawequal     = rawequal
  env.rawlen       = rawlen
  env.setmetatable = setmetatable
  env.getmetatable = getmetatable
  env.pcall        = pcall
  env.xpcall       = xpcall
  env.error        = error
  env.assert       = assert
  env.load         = load
  env.loadstring   = load
  env.require      = function() return make_proxy("require") end
  env.print        = function() end
  env.math         = math
  env.string       = string
  env.table        = table
  env.bit32        = bit32
  env.utf8         = utf8
  env.os           = { clock=os.clock, time=os.time, date=os.date, difftime=os.difftime }
  env.debug        = debug   -- needed for sethook inside chunk
  env._G           = env
  env._VERSION     = _VERSION

  env.coroutine = {
    wrap        = coroutine.wrap,
    create      = coroutine.create,
    resume      = coroutine.resume,
    yield       = coroutine.yield,
    status      = coroutine.status,
    running     = coroutine.running,
    isyieldable = coroutine.isyieldable,
    close       = coroutine.close,
  }

  env.io = {
    open   = function() return nil, "blocked" end,
    write  = function() end,
    read   = function() return "" end,
    close  = function() end,
    lines  = function() return function() end end,
    stdin  = make_proxy("io.stdin"),
    stdout = make_proxy("io.stdout"),
    stderr = make_proxy("io.stderr"),
  }

  -- Common FiveM / framework globals as proxies
  local fivem_names = {
    "exports","Citizen","ESX","QBCore","Config","Bridge","Framework",
    "ox","lib","MySQL","RegisterNetEvent","AddEventHandler",
    "TriggerEvent","TriggerNetEvent","TriggerServerEvent",
    "TriggerClientEvent","GetPlayerPed","GetEntityCoords",
    "NetworkGetEntityOwner","IsEntityDead","Wait","CreateThread",
    "SetTimeout","GetGameTimer","IsDuplicityVersion","Cache",
    "PlayerData","LocalPlayer","Entity","NetworkGetPlayerIndex",
  }
  for _, nm in ipairs(fivem_names) do
    env[nm] = make_proxy(nm)
  end
  env.AddEventHandler  = function() end
  env.RegisterNetEvent = function() end

  return env
end

-- ── Core: debug.sethook capture ──────────────────────────────────────────────

function M.execute_and_record(src)
  local all_protos = {}
  local seen_fns   = {}    -- fn pointer → true (avoid re-capturing same closure)
  local seen_fps   = {}    -- fingerprint → true (deduplication by V[] content)

  -- Install the hook BEFORE loading the chunk so we catch the very first call
  debug.sethook(function(event)
    -- level 2 = the function being called
    local info = debug.getinfo(2, "Sf")
    if not info then return end

    -- Only intercept functions whose source is our sandboxed chunk
    if info.source ~= "@luraph_input" then return end

    local fn = info.func
    if not fn or type(fn) ~= "function" then return end
    if seen_fns[fn] then return end
    seen_fns[fn] = true

    -- Check upvalue count (Luraph executor has many upvalues: V,T,N,v,d,U,C,L,B,j,r,x,...)
    local finfo = debug.getinfo(fn, "u")
    if not finfo or finfo.nups < 6 then return end

    -- Read all upvalues by name
    local up = {}
    for i = 1, finfo.nups do
      local n, v = debug.getupvalue(fn, i)
      if n then up[n] = v end
    end

    -- Must have V (table of opcodes) and j (instruction pointer, number)
    local V = up["V"]
    if type(V) ~= "table" or #V < 3 then return end
    if type(up["j"]) ~= "number" then return end

    -- Deduplicate by fingerprint
    local fp = fingerprint_V(V)
    if seen_fps[fp] then return end
    seen_fps[fp] = true

    -- Build proto record
    local proto = {
      instrs    = {},
      consts    = up["L"] or {},
      params    = 0,
      is_vararg = false,
      _nups     = finfo.nups,
    }

    for j = 1, #V do
      proto.instrs[j] = {
        j  = j,
        op = V[j],
        T  = up["T"] and up["T"][j],
        N  = up["N"] and up["N"][j],
        v  = up["v"] and up["v"][j],
        d  = up["d"] and up["d"][j],
        U  = up["U"] and up["U"][j],
        C  = up["C"] and up["C"][j],
      }
    end

    all_protos[#all_protos + 1] = proto
  end, "c")

  -- Load and run the obfuscated chunk inside the sandbox
  local env = build_sandbox()
  local chunk, err = load(src, "@luraph_input", "t", env)

  if not chunk then
    debug.sethook()   -- remove hook
    return nil, "load error: "..tostring(err)
  end

  local ok, run_err = pcall(chunk)
  debug.sethook()   -- always remove hook after execution

  if #all_protos == 0 then
    local msg = ok
      and "no executor captured — file may use unsupported Luraph variant"
      or  "exec error: "..tostring(run_err)
    return {}, msg
  end

  -- Sort protos by instruction count descending (main proto first)
  table.sort(all_protos, function(a, b)
    return #a.instrs > #b.instrs
  end)

  return all_protos, nil
end

-- ── Static fallback ──────────────────────────────────────────────────────────
-- Used when runtime capture fails entirely.

function M.static_extract_arrays(src)
  local arrays = {}
  for arr_str in src:gmatch("{([%d,0-9xXa-fA-F %.,%-]+)}") do
    local nums, valid = {}, true
    for tok in arr_str:gmatch("[^,]+") do
      local n = tonumber(tok:match("^%s*(.-)%s*$"))
      if n then nums[#nums+1] = n else valid = false; break end
    end
    if valid and #nums > 10 then arrays[#arrays+1] = nums end
  end
  table.sort(arrays, function(a,b) return #a > #b end)
  return arrays
end

-- ── Top-level parse entry point ───────────────────────────────────────────────

function M.parse(path)
  local result = {
    is_luraph     = false,
    executor_body = nil,
    protos        = {},
    arrays        = {},
    error         = nil,
  }

  local src, err = M.read_source(path)
  if not src then result.error = err; return result end

  result.is_luraph = M.is_luraph(src)
  if not result.is_luraph then
    result.error = "not a Luraph-obfuscated file"
    return result
  end

  result.executor_body = M.extract_executor_body(src)

  local protos, run_err = M.execute_and_record(src)
  if protos and #protos > 0 then
    result.protos = protos
  else
    result.error  = run_err
    result.arrays = M.static_extract_arrays(src)
  end

  return result
end

return M
