-----------------------------------------------------------------------
-- client/bones.lua — MathStoreDemon-v3
-- Gerencia props de asas e cauda: spawn, attach, animações, remoção
--
-- Modelos (stream/):
--   Asas  → mts_dm3      (YTYP: mts_dm3.ytyp)
--   Cauda → mts_dmcd3    (YTYP: mts_dmcd3_1.ytyp)
--
-- Dicionários de animação (stream/):
--   Asas  → mts_dm3      (abertura, fechamento, batida, voo)
--   Cauda → mts_dmcd3    (batida, enrolar, reta)
--
-- Bones usados:
--   SKEL_Spine2  (índice 24816) — attach das asas nas costas
--   SKEL_Pelvis  (índice 11816) — attach da cauda na cintura
-----------------------------------------------------------------------

local resourceName = GetCurrentResourceName()

-----------------------------------------------------------------------
-- Constantes de bones
-----------------------------------------------------------------------
local BONE_SPINE2  = 24816   -- costas (asas)
local BONE_PELVIS  = 11816   -- cintura (cauda)

-----------------------------------------------------------------------
-- Modelos dos props
-- Cada entrada da tabela corresponde a uma cor (índice = cor)
-----------------------------------------------------------------------
local WING_MODELS = {
    [1] = 'mts_dm3_1',    -- cor 1 (padrão / preto)
    [2] = 'mts_dm3_2',    -- cor 2
    [3] = 'mts_dm3_3',    -- cor 3
}

local TAIL_MODELS = {
    [1] = 'mts_dmcd3_1',  -- cor 1
    [2] = 'mts_dmcd3_2',  -- cor 2
    [3] = 'mts_dmcd3_3',  -- cor 3
}

-----------------------------------------------------------------------
-- Dicionários e clipes de animação
-----------------------------------------------------------------------
local ANIM_DICT_WING  = 'mts_dm3'
local ANIM_DICT_TAIL  = 'mts_dmcd3'

-- Clipes de asas
local WING_ANIMS = {
    open    = 'mts_dm3_op_1',         -- abrir asas (chão)
    close   = 'mts_dm3_cl_1',         -- fechar asas (chão)
    flap    = 'mts_dm3_bt_1',         -- bater asas (chão)
    open_to_close  = 'mts_dm3_op_to_cl',
    open_to_bat    = 'mts_dm3_op_to_bt',
    close_to_open  = 'mts_dm3_cl_to_op',
    close_to_bat   = 'mts_dm3_cl_to_bt',
    bat_to_open    = 'mts_dm3_bt_to_op',
    bat_to_close   = 'mts_dm3_bt_to_cl',
    loopfly = 'mts_dm3_loopfly',      -- voo em loop
}

-- Clipes de cauda
local TAIL_ANIMS = {
    flap     = 'mts_dmcd3_bt',            -- bater cauda
    wrap     = 'mts_dmcd3_enrl',          -- enrolar cauda
    straight = 'mts_dmcd3_cl',            -- cauda reta
    bat_to_wrap = 'mts_dmcd3_bt_to_enrl', -- transição bater → enrolar
}

-----------------------------------------------------------------------
-- Offsets de posição/rotação do attach
-- Ajuste fino se o prop desalinhar com o ped
-----------------------------------------------------------------------
local WING_OFFSET = {
    pos = vector3(0.0, 0.0, 0.0),
    rot = vector3(0.0, 0.0, 0.0),
}

local TAIL_OFFSET = {
    pos = vector3(0.0,  0.0, -0.1),
    rot = vector3(0.0,  0.0,  0.0),
}

-----------------------------------------------------------------------
-- Estado interno dos props
-----------------------------------------------------------------------
local wingProp     = nil   -- handle da entidade da asa
local tailProp     = nil   -- handle da entidade da cauda
local flyMode      = false -- flag de voo (lida por verificar.lua)
local wingState    = 'closed'  -- 'open' | 'closed' | 'flap'

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

--- Carrega um dicionário de animação de forma síncrona
local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) do
        Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then
            print('^1[' .. resourceName .. '] Timeout ao carregar animDict: ' .. dict .. '^0')
            return false
        end
    end
    return true
end

--- Carrega um modelo de forma síncrona
local function loadModel(modelName)
    local hash = GetHashKey(modelName)
    if not IsModelValid(hash) then
        print('^1[' .. resourceName .. '] Modelo invalido: ' .. modelName .. '^0')
        return nil
    end
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        local timeout = 0
        while not HasModelLoaded(hash) do
            Wait(10)
            timeout = timeout + 10
            if timeout > 10000 then
                print('^1[' .. resourceName .. '] Timeout ao carregar modelo: ' .. modelName .. '^0')
                return nil
            end
        end
    end
    return hash
end

--- Deleta um prop com segurança
local function deleteProp(handle)
    if handle and DoesEntityExist(handle) then
        DeleteEntity(handle)
    end
    return nil
end

--- Cria e attacha um prop no bone do ped
local function attachProp(modelName, bone, offsetPos, offsetRot)
    local ped  = PlayerPedId()
    local hash = loadModel(modelName)
    if not hash then return nil end

    local prop = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
    if not DoesEntityExist(prop) then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    AttachEntityToEntity(
        prop, ped,
        GetPedBoneIndex(ped, bone),
        offsetPos.x, offsetPos.y, offsetPos.z,
        offsetRot.x, offsetRot.y, offsetRot.z,
        true, true, false, true, 1, true
    )

    SetModelAsNoLongerNeeded(hash)
    return prop
end

-----------------------------------------------------------------------
-- API pública — Asas
-----------------------------------------------------------------------

--- Spawna e attacha as asas na cor indicada
function SpawnWings(cor)
    -- Remove asas antigas se existirem
    wingProp = deleteProp(wingProp)

    local maxCores = Config.MaxColors or #WING_MODELS
    cor = math.max(1, math.min(cor or 1, maxCores))
    local modelName = WING_MODELS[cor] or WING_MODELS[1]

    wingProp   = attachProp(modelName, BONE_SPINE2, WING_OFFSET.pos, WING_OFFSET.rot)
    wingState  = 'closed'

    if wingProp then
        -- Carrega dicionário de animação
        loadAnimDict(ANIM_DICT_WING)
    else
        print('^1[' .. resourceName .. '] Falha ao spawnar asas (cor ' .. cor .. ').^0')
    end
end

--- Remove as asas do ped
function RemoveWings()
    wingProp  = deleteProp(wingProp)
    wingState = 'closed'
    flyMode   = false
end

--- Atualiza a cor das asas (re-spawna com outro modelo)
function UpdateWingColor(cor)
    if not wingProp then return end
    SpawnWings(cor)
end

--- Retorna true se o prop de asa existe e está válido
function AreWingsValid()
    return wingProp ~= nil and DoesEntityExist(wingProp)
end

--- Retorna true se asas estão attachadas (prop foi criado)
function GetWingsAttached()
    return wingProp ~= nil
end

--- Re-attacha as asas (chamado por verificar.lua se o prop morreu)
function ReattachWings()
    local cor = 1  -- usa cor padrão na re-attachagem
    SpawnWings(cor)
end

-----------------------------------------------------------------------
-- API pública — Cauda
-----------------------------------------------------------------------

--- Spawna e attacha a cauda na cor indicada
function SpawnTail(cor)
    tailProp = deleteProp(tailProp)

    local maxCores = Config.MaxTailColors or Config.MaxColors or #TAIL_MODELS
    cor = math.max(1, math.min(cor or 1, maxCores))
    local modelName = TAIL_MODELS[cor] or TAIL_MODELS[1]

    tailProp = attachProp(modelName, BONE_PELVIS, TAIL_OFFSET.pos, TAIL_OFFSET.rot)

    if tailProp then
        loadAnimDict(ANIM_DICT_TAIL)
    else
        print('^1[' .. resourceName .. '] Falha ao spawnar cauda (cor ' .. cor .. ').^0')
    end
end

--- Remove a cauda do ped
function RemoveTail()
    tailProp = deleteProp(tailProp)
end

--- Atualiza a cor da cauda
function UpdateTailColor(cor)
    if not tailProp then return end
    SpawnTail(cor)
end

--- Retorna true se o prop de cauda existe e está válido
function IsTailValid()
    return tailProp ~= nil and DoesEntityExist(tailProp)
end

--- Retorna true se cauda está attachada
function GetTailAttached()
    return tailProp ~= nil
end

--- Re-attacha a cauda
function ReattachTail()
    SpawnTail(1)
end

-----------------------------------------------------------------------
-- API pública — Animações de asas
-----------------------------------------------------------------------

--- Toca uma animação de asas no ped
--- @param tipo string  'open' | 'close' | 'flap' | 'loopfly'
function PlayWingAnimation(tipo)
    local ped  = PlayerPedId()
    local clip = WING_ANIMS[tipo]
    if not clip then return end
    if not loadAnimDict(ANIM_DICT_WING) then return end

    -- Para animação anterior antes de iniciar a nova
    local flag = 1  -- loop
    if tipo == 'loopfly' then
        flag = 1 + 16  -- loop + afeta only upper body
    else
        flag = 0  -- sem loop para animações de chão
    end

    TaskPlayAnim(ped, ANIM_DICT_WING, clip, 3.0, -3.0, -1, flag, 0, false, false, false)
    wingState = tipo
end

--- Para a animação de voo em loop
function StopFlyAnim()
    local ped = PlayerPedId()
    if HasAnimDictLoaded(ANIM_DICT_WING) then
        StopAnimTask(ped, ANIM_DICT_WING, WING_ANIMS.loopfly, -2.0)
    end
end

-----------------------------------------------------------------------
-- API pública — Animações de cauda
-----------------------------------------------------------------------

--- Toca uma animação de cauda no ped
--- @param tipo string  'flap' | 'wrap' | 'straight'
function PlayTailAnimation(tipo)
    local ped  = PlayerPedId()
    local clip = TAIL_ANIMS[tipo]
    if not clip then return end
    if not loadAnimDict(ANIM_DICT_TAIL) then return end

    local flag = 0  -- sem loop por padrão
    if tipo == 'flap' then flag = 1 end  -- batida em loop

    TaskPlayAnim(ped, ANIM_DICT_TAIL, clip, 3.0, -3.0, -1, flag, 0, false, false, false)
end

-----------------------------------------------------------------------
-- API pública — Modo de voo
-----------------------------------------------------------------------

--- Define o estado do modo de voo
--- @param estado boolean
function SetFlyMode(estado)
    flyMode = estado == true
    if not flyMode then
        StopFlyAnim()
    end
end

--- Retorna o estado atual do modo de voo
--- @return boolean
function GetFlyMode()
    return flyMode
end

-----------------------------------------------------------------------
-- API pública — Limpeza de props próximos (cleanup local)
-----------------------------------------------------------------------

--- Remove objetos com hashes dos modelos de asas/cauda próximos ao ped
--- Útil para limpar props bugados que não têm dono registrado
function CleanupNearbyProps()
    local ped    = PlayerPedId()
    local pos    = GetEntityCoords(ped)
    local radius = 10.0

    -- Monta lista de hashes a buscar
    local hashes = {}
    for _, m in pairs(WING_MODELS) do
        table.insert(hashes, GetHashKey(m))
    end
    for _, m in pairs(TAIL_MODELS) do
        table.insert(hashes, GetHashKey(m))
    end

    -- Varre todos os objetos no raio
    local obj = GetFirstObject()
    local found
    obj, found = GetFirstObject()
    while found do
        if DoesEntityExist(obj) then
            local objModel = GetEntityModel(obj)
            for _, h in ipairs(hashes) do
                if objModel == h then
                    local objPos = GetEntityCoords(obj)
                    if #(pos - objPos) <= radius then
                        DeleteEntity(obj)
                    end
                    break
                end
            end
        end
        obj, found = GetNextObject(obj)
    end
end

print('^3[' .. resourceName .. '] client/bones.lua carregado.^0')
