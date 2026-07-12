-- fivem_deob/luraph_lift/opcode_id.lua
-- Identifies Luraph opcodes from the dispatch tree by pattern-matching.
--
-- The Luraph VM uses randomized opcode numbers per compilation, so we
-- cannot hardcode opcode values. Instead we:
--   1. Extract the executor function body as source text
--   2. Pattern-match each known semantic operation
--   3. Find the Z comparison value immediately preceding each pattern
--   4. Build a map: opcode_value → semantic_name
--
-- Known Luraph instruction semantics (based on analysis of bridge/shared.lua):
--
--   MOVE        i=B; n=v[j]                        (sets up register file ptr)
--   MOVE2       i=B; n=N[j]                        (alternate register ptr setup)
--   LOADK       B[v[j]]=L[T[j]]                    (load constant)
--   LOADK_d     E=d[j]; i[n]=E                     (load constant via state)
--   LOADK_U     E=U[j]; i[n]=E                     (load constant via state)
--   LOADSELF    B[v[j]]=s                           (load self)
--   LOADBOOL_C  n=C[j]                              (load bool immediate)
--   LOADNIL     for u=T[j],N[j] do B[u]=(nil)      (clear registers)
--   GETUPVAL    B[N[j]]=(L[T[j]][d[j]])            (upvalue read)
--   SETUPVAL    (x[3])[v[j]]=B[T[j]]               (upvalue write)
--   GETTABLE_RR B[v[j]]=(B[N[j]][B[T[j]]])         (table read R[R])
--   GETTABLE_EQ n=n[E]                              (table chain step)
--   GETTABLE_chain i=i[n]                           (table chain step 2)
--   SETTABLE_RR B[v[j]][B[T[j]]]=B[N[j]]           (table write R[R]=R)
--   SETTABLE_KR B[N[j]][B[T[j]]]=d[j]              (table write R[R]=K)
--   SETTABLEKS  B[T[j]][C[j]]=B[v[j]]              (table write R[K]=R)
--   NEWTABLE    B[v[j]]=({})                        (create table)
--   SELF        i=L[T[j]]; B[v[j]]=i[3][i[2]][B[N[j]]] (method lookup)
--   ADD_RR      B[v[j]]=B[T[j]]+B[N[j]]            (add registers)
--   ADD_KK      B[N[j]]=U[j]+d[j]                  (add constants)
--   SUB_RR      B[N[j]]=B[T[j]]-B[v[j]]            (subtract registers)
--   MUL_RR      B[v[j]]=B[T[j]]*B[N[j]]            (multiply registers)
--   DIV_RR      B[v[j]]=B[N[j]]/B[T[j]]            (divide registers)
--   DIV_RK      B[T[j]]=B[v[j]]/C[j]               (divide R by K)
--   MOD_RR      B[T[j]]=(B[v[j]]%B[N[j]])          (modulo registers)
--   MOD_RK      B[v[j]]=(B[N[j]]%U[j])             (modulo R/K)
--   UNM         B[v[j]]=(-B[T[j]])                  (unary minus)
--   LEN         B[T[j]]=#B[N[j]]                    (length operator)
--   CONCAT_KR   B[N[j]]=d[j]..B[T[j]]              (concat K..R)
--   CONCAT_RR   B[T[j]]=B[N[j]]..B[v[j]]           (concat R..R)
--   NOT         B[v[j]]=not B[N[j]]                 (boolean not)
--   GT_RR       B[T[j]]=(B[N[j]]>B[v[j]])          (greater than R>R)
--   LT_KK       B[N[j]]=U[j]<d[j]                  (less than K<K)
--   LE_KK       B[N[j]]=(U[j]<=d[j])               (less equal K<=K)
--   GE_RR       B[T[j]]=B[v[j]]>=B[N[j]]           (greater equal R>=R)
--   EQ_KK_d     B[T[j]]=d[j]==C[j]                 (equal K==K)
--   NE_RR       B[v[j]]=(B[N[j]]~=B[T[j]])         (not equal R~=R)
--   NE_RK       B[v[j]]=(B[N[j]]~=U[j])            (not equal R~=K)
--   BXOR_RK     B[T[j]]=B[v[j]]~C[j]               (bitwise xor R~K)
--   BXOR_KK2    B[T[j]]=d[j]~C[j]                  (bitwise xor K~K)
--   BOR_KK      B[v[j]]=C[j]|U[j]                  (bitwise or K|K)
--   BAND_KK     B[v[j]]=(U[j]&C[j])                (bitwise and K&K)
--   BXOR_RR     B[T[j]]=(B[N[j]]~B[v[j]])          (bitwise xor R~R)
--   SHR_RK      B[v[j]]=C[j]>>U[j]                 (shift right K>>K)
--   EQ_JMP      if B[v[j]]==B[N[j]] then j=T[j]    (eq branch)
--   LE_K_JMP    if not(B[T[j]]<=d[j]) then j=N[j]  (le const branch)
--   LT_RK_JMP   if not(B[v[j]]<U[j]) then j=N[j]  (lt const branch)
--   LT_JMP_inv  if not(B[N[j]]<B[v[j]]) then j=T[j](inverted lt branch)
--   FORPREP     p=save; P=N[j]; W=B[P]; ...         (numeric for setup)
--   FORLOOP     complex step + branch               (numeric for loop)
--   TFORLOOP    save state, set up call              (generic for)
--   CALL_MR     B[i]=B[i](x[1](B,i+1,P)); P=i      (call multi-ret)
--   CALL_0      E=B                                  (call setup)
--   CALL_1      B[i](B[i+1]); P=i-1                (call 1 arg)
--   TAILCALL    B[i](x[1](B,i+1,P)); P=i-1         (tail call)
--   RETURN      return                               (function return)
--   RETURN_close close + return true,v[j],0         (return with upval close)
--   CLOSE_ret   close upvals r[], return            (return with r close)
--   VARARG      load varargs into regs               (vararg)
--   CLOSURE     create closure from proto            (closure creation)
--   LOADARG     for u=1,v[j] do B[u]=O[u]           (load args to regs)

local M = {}

-- Semantic pattern database
-- Each entry: { name, pattern_in_body, field_A, field_B, ... }
-- We search for the pattern string in the executor body near a Z comparison

M.PATTERNS = {
  -- === REGISTER LOADS ===
  { "LOADK",      "B%[v%[j%]%]=L%[T%[j%]%]" },
  { "LOADNIL",    "for u=T%[j%],N%[j%]" },
  { "LOADSELF",   "B%[v%[j%]%]%=(s)" },
  { "LOADARG",    "for u=1,v%[j%]" },
  -- === MOVES ===
  { "MOVE",       "i=B;n=v%[j%]" },         -- sets up i=B, n=reg
  { "MOVE2",      "i=B;n=N%[j%]" },
  { "MOVE_R",     "B%[v%[j%]%]=B%[T%[j%]%]" },
  -- === TABLE OPS ===
  { "NEWTABLE",   "B%[v%[j%]%]=%(%{%}%)" },
  { "GETTABLE_RR","B%[v%[j%]%]=%(%B%[N%[j%]%]%[B%[T%[j%]%]%]%)" },
  { "SETTABLE_RR","B%[v%[j%]%]%[B%[T%[j%]%]%]=B%[N%[j%]%]" },
  { "SETTABLE_KR","B%[N%[j%]%]%[B%[T%[j%]%]%]=d%[j%]" },
  { "SETTABLEKS", "B%[T%[j%]%]%[C%[j%]%]=B%[v%[j%]%]" },
  -- === UPVALUE OPS ===
  { "GETUPVAL",   "B%[N%[j%]%]=%(%L%[T%[j%]%]%[d%[j%]%]%)" },
  { "SETUPVAL",   "%(x%[3%]%)%[v%[j%]%]=B%[T%[j%]%]" },
  -- === ARITHMETIC ===
  { "ADD_RR",     "B%[v%[j%]%]=B%[T%[j%]%]%+B%[N%[j%]%]" },
  { "ADD_KK",     "B%[N%[j%]%]=U%[j%]%+d%[j%]" },
  { "SUB_RR",     "B%[N%[j%]%]=B%[T%[j%]%]%-B%[v%[j%]%]" },
  { "MUL_RR",     "B%[v%[j%]%]=B%[T%[j%]%]%*B%[N%[j%]%]" },
  { "DIV_RR",     "B%[v%[j%]%]=B%[N%[j%]%]/B%[T%[j%]%]" },
  { "DIV_RK",     "B%[T%[j%]%]=%(%B%[v%[j%]%]/C%[j%]%)" },
  { "MOD_RR",     "B%[T%[j%]%]=%(%B%[v%[j%]%]%%B%[N%[j%]%]%)" },
  { "MOD_RK",     "B%[v%[j%]%]=%(%B%[N%[j%]%]%%U%[j%]%)" },
  { "UNM",        "B%[v%[j%]%]=%(%-B%[T%[j%]%]%)" },
  { "LEN",        "B%[T%[j%]%]=#B%[N%[j%]%]" },
  { "CONCAT_KR",  "B%[N%[j%]%]=d%[j%]%.%.B%[T%[j%]%]" },
  { "CONCAT_RR",  "B%[T%[j%]%]=B%[N%[j%]%]%.%.B%[v%[j%]%]" },
  -- === COMPARISON ===
  { "NOT",        "B%[v%[j%]%]=not B%[N%[j%]%]" },
  { "EQ_RR",      "B%[N%[j%]%]=B%[v%[j%]%]==B%[T%[j%]%]" },
  { "GT_RR",      "B%[T%[j%]%]=%(%B%[N%[j%]%]>B%[v%[j%]%]%)" },
  { "LT_RR",      "B%[N%[j%]%]=%(%B%[T%[j%]%]<B%[v%[j%]%]%)" },
  { "LE_RR",      "B%[T%[j%]%]=B%[v%[j%]%]<=B%[N%[j%]%]" },
  { "GE_RR",      "B%[T%[j%]%]=B%[v%[j%]%]>=B%[N%[j%]%]" },
  { "NE_RR",      "B%[v%[j%]%]=%(%B%[N%[j%]%]~=B%[T%[j%]%]%)" },
  { "NE_RK",      "B%[v%[j%]%]=%(%B%[N%[j%]%]~=U%[j%]%)" },
  { "LT_KK",      "B%[N%[j%]%]=U%[j%]<d%[j%]" },
  { "LE_KK",      "B%[N%[j%]%]=%(%U%[j%]<=d%[j%]%)" },
  { "EQ_KK_d",    "B%[T%[j%]%]=d%[j%]==C%[j%]" },
  { "NE_KK_d",    "B%[T%[j%]%]=d%[j%]~=C%[j%]" },
  -- === BITWISE ===
  { "BOR_KK",     "B%[v%[j%]%]=C%[j%]|U%[j%]" },
  { "BAND_KK",    "B%[v%[j%]%]=%(%U%[j%]&C%[j%]%)" },
  { "BXOR_RR",    "B%[T%[j%]%]=%(%B%[N%[j%]%]~B%[v%[j%]%]%)" },
  { "BXOR_RK",    "B%[T%[j%]%]=B%[v%[j%]%]~C%[j%]" },
  { "BXOR_KK2",   "B%[T%[j%]%]=d%[j%]~C%[j%]" },
  { "SHR_RK",     "B%[v%[j%]%]=C%[j%]>>U%[j%]" },
  -- === BRANCHES ===
  { "EQ_JMP",     "if B%[v%[j%]%]==B%[N%[j%]%]then j=T%[j%]" },
  { "LE_K_JMP",   "if not%(B%[T%[j%]%]<=d%[j%]%)then j=%(N%[j%]%)" },
  { "LT_RK_JMP",  "if not%(B%[v%[j%]%]<U%[j%]%)then j=N%[j%]" },
  { "LT_JMP_inv", "if not%(not%(B%[N%[j%]%]<B%[v%[j%]%]%)%)then" },
  { "LT_JMP_inv2","if not%(B%[N%[j%]%]<B%[v%[j%]%]%)then j=T%[j%]" },
  { "TEST_JMP",   "j=%(v%[j%]%)" },  -- fallback for conditional jumps
  -- === CALLS ===
  { "CALL_1R",    "B%[i%]=B%[i%]%(B%[i%+1%]%);P=%(" },
  { "CALL_1_NR",  "%(B%[i%]%)%(B%[i%+1%]%);P=i%-" },
  { "CALL_MR",    "B%[i%]=B%[i%]%(x%[0x1%]%(B,i%+0X01,P%)" },
  { "CALL_MR2",   "B%[i%]=B%[i%]%(x%[1%]%(B,i%+1,P%)" },
  { "TAILCALL",   "B%[i%]%(x%[0x1%]%(B,i%+0X1,P%)" },
  -- === RETURNS ===
  { "RETURN",     ";return;" },
  { "RETURN_V",   "return true,v%[j%]" },
  { "CLOSE_RET",  ";return;" },  -- same pattern, context differs
  -- === LOOPS ===
  { "FORPREP",    "p={%[2%]=X" },
  { "FORLOOP",    "%(V%)%[j%]=%(" },    -- writes back to bytecode
  { "TFORLOOP",   "K=false;j=%(v%[j%]%)" },
  -- === MISC ===
  { "VARARG",     "for u=i,i%+n" },
  { "JMP",        "j=T%[j%]" },
  { "CLOSE",      "for s,L in x%[34%]" },  -- close upvalues loop
}

-- Extract Z comparison value that immediately precedes a pattern match
-- Returns integer opcode value or nil
local function find_z_before(body, pat_start, window)
  window = window or 200
  local ctx = body:sub(math.max(1, pat_start - window), pat_start)
  -- Find the last Z== or Z~= before this position
  local best_pos, best_val = 0, nil
  for prefix, hex, dec in ctx:gmatch("Z([~=]=)0[xX]([0-9a-fA-F]+)") do
    local v = tonumber(hex, 16)
    if v then best_val = v end
  end
  if best_val then return best_val end
  -- Try decimal
  for prefix, dec in ctx:gmatch("Z([~=]=)(%d+)") do
    local v = tonumber(dec)
    if v then best_val = v end
  end
  return best_val
end

-- Main identification function
-- body: the executor function source as string
-- Returns: table mapping opcode_value(int) → semantic_name(string)
function M.identify(body)
  local opmap = {}       -- val → name
  local namemap = {}     -- name → val (first found)

  for _, entry in ipairs(M.PATTERNS) do
    local name, pat = entry[1], entry[2]
    local s = body:find(pat)
    if s then
      local val = find_z_before(body, s, 250)
      if val and not opmap[val] then
        opmap[val] = name
        namemap[name] = val
      end
    end
  end

  return opmap, namemap
end

-- Pretty-print the opcode map (for debugging)
function M.dump(opmap)
  local keys = {}
  for k in pairs(opmap) do keys[#keys+1] = k end
  table.sort(keys)
  local lines = {}
  for _, k in ipairs(keys) do
    lines[#lines+1] = string.format("  0x%02X (%3d)  %s", k, k, opmap[k])
  end
  return table.concat(lines, "\n")
end

return M
