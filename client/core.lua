local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = GetCurrentResourceName
L0_1 = L0_1()
L1_1 = false
L2_1 = CreateThread
function L3_1()
  local L0_2, L1_2, L2_2
  while true do
    L0_2 = NetworkIsSessionStarted
    L0_2 = L0_2()
    if L0_2 then
      break
    end
    L0_2 = Wait
    L1_2 = 100
    L0_2(L1_2)
  end
  L0_2 = true
  L1_1 = L0_2
  L0_2 = TriggerEvent
  L1_2 = L0_1
  L2_2 = ":coreClientReady"
  L1_2 = L1_2 .. L2_2
  L0_2(L1_2)
end
L2_1(L3_1)
function L2_1()
  local L0_2, L1_2
  L0_2 = L1_1
  return L0_2
end
IsCoreReady = L2_1
L2_1 = AddEventHandler
L3_1 = "onResourceStop"
function L4_1(A0_2)
  local L1_2
  L1_2 = L0_1
  if A0_2 == L1_2 then
    L1_2 = false
    L1_1 = L1_2
  end
end
L2_1(L3_1, L4_1)
