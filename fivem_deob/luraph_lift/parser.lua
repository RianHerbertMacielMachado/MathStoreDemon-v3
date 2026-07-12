-- fivem_deob/luraph_lift/parser.lua
-- Loads a Luraph-obfuscated file and extracts the decoded instruction stream
-- by intercepting the VM executor at runtime via debug.sethook.
--
-- SUPPORTS TWO LURAPH VERSIONS:
--
--   v1 (bridge/shared.lua style):
--     "while true do local Z=(V[j])"
--     Upvalues: V=opcodes(table), j=IP(number), T/N/v/d/U/C=field arrays, L=consts
--
--   v2 (client/main.lua style):
--     "repeat local J=Z[V]" inside nested closures
--     Upvalues: Z=opcodes(table,num), Y/u/o/x=field arrays, L=consts, V=IP(number)
--
-- CAPTURE METHOD: debug.sethook("c") fires on every function call.
-- We detect the Luraph executor closure by its upvalue signature.
-- Deduplication by fingerprint of opcode array prevents repeated captures.

local M = {}

-- Version constants
M.V1 = "v1"  -- while true do local Z=(V[j])
M.V2 = "v2"  -- repeat local J=Z[V]

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
  -- v1 detection
  if src:find("local Z=(V[j])", 1, true) then return true end
  if src:find("local Z=%(V%[j%]%)") then return true end
  if src:find("while true do local Z=") then return true end
  -- v2 detection: repeat local J=Z[V]  (any single-letter variable name)
  if src:find("repeat local %a=Z%[V%]") then return true end
  -- v2/v3 top-level method table signature: return({tK=function... or return({z=function
  if src:find("^%s*return%(%{%a%a=function") then return true end
  if src:find("^%s*return%({%a%a=function") then return true end
  if src:find("^%s*return%(%{z=function") then return true end
  if src:find("^%s*return%({z=function") then return true end
  return false
end

function M.luraph_version(src)
  if src:find("local Z=(V[j])", 1, true)
  or src:find("local Z=%(V%[j%]%)")
  or src:find("while true do local Z=") then
    return M.V1
  end
  if src:find("repeat local %a=Z%[V%]")
  or src:find("^%s*return%(%{z=function")
  or src:find("^%s*return%({z=function")
  or src:find("^%s*return%(%{%a%a=function")
  or src:find("^%s*return%({%a%a=function") then
    return M.V2
  end
  return nil
end

function M.extract_executor_body(src)
  -- v1
  local s = src:find("local Z=(V[j])", 1, true)
  if not s then s = src:find("local Z=%(V%[j%]%)") end
  if s then
    return src:sub(math.max(1, s - 100), s + 25000)
  end
  -- v2
  s = src:find("repeat local %a=Z%[V%]")
  if s then
    return src:sub(math.max(1, s - 200), s + 30000)
  end
  return nil
end

-- ── Fingerprint helper ────────────────────────────────────────────────────────

local function fingerprint_V(arr)
  local parts = {}
  for i = 1, math.min(#arr, 50) do
    parts[i] = tostring(arr[i])
  end
  parts[#parts+1] = tostring(#arr)
  return table.concat(parts, ",")
end

-- ── Sandbox environment ───────────────────────────────────────────────────────

local function make_proxy(name)
  local mt = {}
  mt.__index    = function(t, k) local c = make_proxy((name or "?").."."..tostring(k)); rawset(t,k,c); return c end
  mt.__newindex = rawset
  mt.__call     = function(t, ...) return make_proxy((name or "?").."()") end
  mt.__tostring = function() return "<proxy:"..(name or "?")..">" end
  mt.__len      = function() return 0 end
  mt.__concat   = function(a, b) return tostring(a)..tostring(b) end
  mt.__add      = function() return 0 end  mt.__sub  = function() return 0 end
  mt.__mul      = function() return 0 end  mt.__div  = function() return 1 end
  mt.__mod      = function() return 0 end  mt.__pow  = function() return 1 end
  mt.__unm      = function() return 0 end  mt.__idiv = function() return 0 end
  mt.__band     = function() return 0 end  mt.__bor  = function() return 0 end
  mt.__bxor     = function() return 0 end  mt.__bnot = function() return 0 end
  mt.__shl      = function() return 0 end  mt.__shr  = function() return 0 end
  mt.__lt       = function() return false end
  mt.__le       = function() return false end
  mt.__eq       = function() return false end
  return setmetatable({}, mt)
end

local function build_sandbox()
  local env = {}
  setmetatable(env, {
    __index    = function(t, k) local p = make_proxy(k); rawset(t,k,p); return p end,
    __newindex = rawset,
  })
  env.tostring = tostring; env.tonumber = tonumber; env.type = type
  env.pairs = pairs; env.ipairs = ipairs; env.next = next; env.select = select
  env.unpack = table.unpack or unpack
  env.rawget = rawget; env.rawset = rawset; env.rawequal = rawequal; env.rawlen = rawlen
  env.setmetatable = setmetatable; env.getmetatable = getmetatable
  env.pcall = pcall; env.xpcall = xpcall; env.error = error; env.assert = assert
  env.load = load; env.loadstring = load
  env.require = function() return make_proxy("require") end
  env.print = function() end
  env.math = math; env.string = string; env.table = table
  env.bit32 = bit32; env.utf8 = utf8
  env.os = { clock=os.clock, time=os.time, date=os.date, difftime=os.difftime }
  env.debug = debug
  env._G = env; env._VERSION = _VERSION
  env.coroutine = {
    wrap=coroutine.wrap, create=coroutine.create, resume=coroutine.resume,
    yield=coroutine.yield, status=coroutine.status, running=coroutine.running,
    isyieldable=coroutine.isyieldable, close=coroutine.close,
  }
  env.io = {
    open=function() return nil,"blocked" end, write=function() end,
    read=function() return "" end, close=function() end,
    lines=function() return function() end end,
    stdin=make_proxy("io.stdin"), stdout=make_proxy("io.stdout"), stderr=make_proxy("io.stderr"),
  }
  local fivem_names = {
    "exports","Citizen","ESX","QBCore","Config","Bridge","Framework",
    "ox","lib","MySQL","RegisterNetEvent","AddEventHandler",
    "TriggerEvent","TriggerNetEvent","TriggerServerEvent","TriggerClientEvent",
    "GetPlayerPed","GetEntityCoords","NetworkGetEntityOwner","IsEntityDead",
    "Wait","CreateThread","SetTimeout","GetGameTimer","IsDuplicityVersion",
    "Cache","PlayerData","LocalPlayer","Entity","NetworkGetPlayerIndex",
  }
  for _, nm in ipairs(fivem_names) do env[nm] = make_proxy(nm) end
  env.AddEventHandler = function() end; env.RegisterNetEvent = function() end
  return env
end

-- ── v2 executor detector ──────────────────────────────────────────────────────
-- v2 signature: Z=table(num,#N), V=number(IP), Y or u = table(num,#N same size)

local function try_capture_v2(up, finfo)
  local Z = up["Z"]
  if type(Z) ~= "table" or #Z < 3 then return nil end
  if type(Z[1]) ~= "number" then return nil end
  if type(up["V"]) ~= "number" then return nil end
  -- Needs at least one companion array of same size
  local companion = up["Y"] or up["u"] or up["o"]
  if type(companion) ~= "table" or #companion ~= #Z then return nil end

  local proto = {
    instrs    = {},
    consts    = up["L"] or {},
    params    = 0,
    is_vararg = false,
    _nups     = finfo.nups,
    _version  = "v2",
  }
  for j = 1, #Z do
    proto.instrs[j] = {
      j  = j,
      op = Z[j],
      T  = up["Y"] and up["Y"][j],   -- A-field
      N  = up["u"] and up["u"][j],   -- B-field
      v  = up["o"] and up["o"][j],   -- C-field
      d  = up["x"] and up["x"][j],   -- D-field
      U  = nil,
      C  = nil,
    }
  end
  return proto
end

-- ── Core: debug.sethook capture ──────────────────────────────────────────────

function M.execute_and_record(src)
  local all_protos = {}
  local seen_fns   = {}
  local seen_fps   = {}
  local ver        = M.luraph_version(src)

  debug.sethook(function()
    local info = debug.getinfo(2, "Sf")
    if not info or info.source ~= "@luraph_input" then return end
    local fn = info.func
    if not fn or type(fn) ~= "function" then return end
    if seen_fns[fn] then return end
    seen_fns[fn] = true

    local finfo = debug.getinfo(fn, "u")
    if not finfo or finfo.nups < 6 then return end

    local up = {}
    for i = 1, finfo.nups do
      local n, v = debug.getupvalue(fn, i)
      if n then up[n] = v end
    end

    local proto = nil

    -- ── Try v1: V=table(opcodes), j=number(IP) ────────────────────────────
    if ver == M.V1 or ver == nil then
      local V = up["V"]
      if type(V) == "table" and #V >= 3
      and type(V[1]) == "number"
      and type(up["j"]) == "number" then
        local fp = fingerprint_V(V)
        if not seen_fps[fp] then
          seen_fps[fp] = true
          proto = {
            instrs = {}, consts = up["L"] or {},
            params = 0, is_vararg = false,
            _nups = finfo.nups, _version = "v1",
          }
          for j = 1, #V do
            proto.instrs[j] = {
              j=j, op=V[j],
              T  = up["T"] and up["T"][j],
              N  = up["N"] and up["N"][j],
              v  = up["v"] and up["v"][j],
              d  = up["d"] and up["d"][j],
              U  = up["U"] and up["U"][j],
              C  = up["C"] and up["C"][j],
            }
          end
        end
      end
    end

    -- ── Try v2: Z=table(opcodes), V=number(IP) ────────────────────────────
    if not proto and (ver == M.V2 or ver == nil) then
      local v2 = try_capture_v2(up, finfo)
      if v2 then
        -- Build fingerprint from opcode sequence
        local ops = {}
        for _, ins in ipairs(v2.instrs) do ops[#ops+1] = ins.op end
        local fp = fingerprint_V(ops)
        if not seen_fps[fp] then
          seen_fps[fp] = true
          proto = v2
        end
      end
    end

    if proto then
      all_protos[#all_protos + 1] = proto
    end
  end, "c")

  local env   = build_sandbox()
  local chunk, err = load(src, "@luraph_input", "t", env)
  if not chunk then
    debug.sethook()
    return nil, "load error: "..tostring(err)
  end

  local ok, run_err = pcall(chunk)
  debug.sethook()

  if #all_protos == 0 then
    local msg = ok
      and "no executor captured — unsupported Luraph variant"
      or  "exec error: "..tostring(run_err)
    return {}, msg
  end

  -- Sort by instruction count descending (main/largest proto first)
  table.sort(all_protos, function(a, b) return #a.instrs > #b.instrs end)
  return all_protos, nil
end

-- ── Static fallback ───────────────────────────────────────────────────────────

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
  local result = { is_luraph=false, executor_body=nil, protos={}, arrays={}, error=nil }
  local src, err = M.read_source(path)
  if not src then result.error = err; return result end

  result.is_luraph = M.is_luraph(src)
  if not result.is_luraph then
    result.error = "not a Luraph-obfuscated file"
    return result
  end

  result.executor_body = M.extract_executor_body(src)
  result.version       = M.luraph_version(src)

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
