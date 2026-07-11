-----------------------------------------------------------------------
-- config/config_internal.lua — MathStoreDemon-v3
-- Configurações internas do script (não editáveis pelo cliente final)
-- Contém: modelos, bones, dicts de animação, offsets, limites
-----------------------------------------------------------------------

ConfigInternal = {}

-----------------------------------------------------------------------
-- Modelos das asas por cor (índice = número da cor)
-- Nomes devem bater exatamente com os arquivos em stream/
-----------------------------------------------------------------------
ConfigInternal.WingModels = {
    [1] = 'mts_dm3_1',
    [2] = 'mts_dm3_2',
    [3] = 'mts_dm3_3',
}

-----------------------------------------------------------------------
-- Modelos da cauda por cor
-----------------------------------------------------------------------
ConfigInternal.TailModels = {
    [1] = 'mts_dmcd3_1',
    [2] = 'mts_dmcd3_2',
    [3] = 'mts_dmcd3_3',
}

-----------------------------------------------------------------------
-- Bones do ped para attach dos props
-- Referência: https://wiki.rage.mp/index.php?title=Bones
-----------------------------------------------------------------------
ConfigInternal.Bones = {
    wing = 24816,   -- SKEL_Spine2  (costas centrais)
    tail = 11816,   -- SKEL_Pelvis  (cintura/base da coluna)
}

-----------------------------------------------------------------------
-- Offsets de posição e rotação para AttachEntityToEntity
-- Ajuste fino se o prop desalinhar visualmente no ped
-- pos = {x, y, z}   rot = {x, y, z}  (em graus)
-----------------------------------------------------------------------
ConfigInternal.WingOffset = {
    pos = { x = 0.0,  y = 0.0,  z = 0.0 },
    rot = { x = 0.0,  y = 0.0,  z = 0.0 },
}

ConfigInternal.TailOffset = {
    pos = { x = 0.0,  y = 0.0,  z = -0.10 },
    rot = { x = 0.0,  y = 0.0,  z = 0.0  },
}

-----------------------------------------------------------------------
-- Dicionários de animação (devem estar em stream/ como .ycd)
-----------------------------------------------------------------------
ConfigInternal.AnimDicts = {
    wing = 'mts_dm3',
    tail = 'mts_dmcd3',
}

-----------------------------------------------------------------------
-- Clipes de animação das asas
-- Chave = nome amigável usado em PlayWingAnimation()
-----------------------------------------------------------------------
ConfigInternal.WingClips = {
    open           = 'mts_dm3_op_1',
    close          = 'mts_dm3_cl_1',
    flap           = 'mts_dm3_bt_1',
    loopfly        = 'mts_dm3_loopfly',
    open_to_close  = 'mts_dm3_op_to_cl',
    open_to_flap   = 'mts_dm3_op_to_bt',
    close_to_open  = 'mts_dm3_cl_to_op',
    close_to_flap  = 'mts_dm3_cl_to_bt',
    flap_to_open   = 'mts_dm3_bt_to_op',
    flap_to_close  = 'mts_dm3_bt_to_cl',
}

-----------------------------------------------------------------------
-- Clipes de animação da cauda
-----------------------------------------------------------------------
ConfigInternal.TailClips = {
    flap          = 'mts_dmcd3_bt',
    wrap          = 'mts_dmcd3_enrl',
    straight      = 'mts_dmcd3_cl',
    flap_to_wrap  = 'mts_dmcd3_bt_to_enrl',
}

-----------------------------------------------------------------------
-- Limites do sistema de voo
-----------------------------------------------------------------------
ConfigInternal.Flight = {
    velMax      = 2.5,    -- velocidade máxima (m/s por tick)
    velAcel     = 0.05,   -- aceleração por tick
    velDesacel  = 0.08,   -- desaceleração por tick
    alturaMin   = 0.3,    -- altura mínima acima do chão (m)
    velVertical = 0.6,    -- velocidade vertical ao subir (Space)
    velDescer   = 0.4,    -- velocidade vertical ao descer (C)
}

-----------------------------------------------------------------------
-- Limites gerais
-----------------------------------------------------------------------
ConfigInternal.MaxColors     = 3   -- número máximo de cores de asas
ConfigInternal.MaxTailColors = 3   -- número máximo de cores de cauda

-----------------------------------------------------------------------
-- Raio de limpeza local (cleanup2)
-----------------------------------------------------------------------
ConfigInternal.CleanupRadius = 10.0  -- metros ao redor do jogador

-----------------------------------------------------------------------
-- Intervalo dos loops de verificação de integridade (ms)
-----------------------------------------------------------------------
ConfigInternal.TickVerify    = 1000   -- loop de integridade dos props
ConfigInternal.TickFlyIdle   = 500    -- loop de voo quando desativado
