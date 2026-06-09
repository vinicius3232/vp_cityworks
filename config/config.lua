-- vp_cityworks :: Secretaria de Obras (SADOT-style) — multi-frente
-- Script feito por LORD32 aka Vini32 e Dooc
--
-- ESTRUTURA: tudo que e COMPARTILHADO fica em Config.* (global).
-- Cada FRENTE de trabalho (eletricista, asfalto, etc.) fica em
-- Config.Disciplines[id], com suas regioes/tarefas/minigames/veiculo.
-- O motor (lobby/coop/recompensa/etc.) e generico e resolve a frente ativa.

Config = {}
Config.Debug = false

---------------------------------------------------------------------
-- INTERACAO / NPC (compartilhado — a "central de obras")
---------------------------------------------------------------------
Config.Interaction = {
    coords   = vec4(528.77, -1603.26, 29.34, 46.59),
    pedModel = `s_m_y_construct_01`,
    blip     = { enable = true, sprite = 566, color = 47, scale = 0.8, label = 'Secretaria de Obras' },
    targetDistance = 2.0,
}

Config.RequiredJob = 'all' -- 'all' ou { obras = 0 } (nome do job = grade minimo)

Config.MaxPlayersPerLobby = 4
Config.InviteMaxDistance  = 8.0
Config.JobResetCommand    = 'obrasreset'

---------------------------------------------------------------------
-- COOLDOWNS / RATE LIMIT (compartilhado)
---------------------------------------------------------------------
Config.Cooldowns = {
    selectMission    = 1000,
    selectDiscipline = 800,
    completeTarget   = 2000,
    build            = 1500,
    invite           = 1000,
    acceptInvite     = 1000,
    kickPlayer       = 1000,
    startJob         = 2000,
    resetJob         = 2000,
    deliverVehicle   = 2000,
    removeEquipment  = 800,
    -- moveLift NAO tem cooldown de proposito
}

---------------------------------------------------------------------
-- ECONOMIA / ITENS (compartilhado entre frentes)
---------------------------------------------------------------------
Config.VehicleDeposit = { enable = true, amount = 500, account = 'bank' }
Config.RequiredItem   = { enable = false, name = 'tool_box', consume = false, wholeTeam = false }
Config.RewardItems    = {
    -- { item = 'scrapmetal', chance = 50, amount = 1 },
}
Config.BossRewardSplit = true

-- Dispatch sob demanda: cidadao chama um servico; equipes EM SERVICO daquela
-- frente recebem um chamado (blip + notify) no local do cidadao.
Config.Dispatch = {
    enable      = true,
    command     = 'pedirservico',
    fee         = 200,           -- cobrado do cidadao
    account     = 'bank',
    blipTime    = 180000,        -- ms que o blip do chamado dura
    disciplines = { 'towing', 'electrician' }, -- frentes que aceitam chamado
}

---------------------------------------------------------------------
-- EQUIPAMENTO (props sincronizados — usado por frentes que precisarem)
---------------------------------------------------------------------
Config.Equipment = {
    ladder = { model = `hw1_06_ldr_02`, limit = `prop_wallbrick_01` },
    lift   = { model = `prop_dock_crane_lift`, rail = `prop_conslift_rail` },
    buildDistance = 8.0,
}

-- Roupa de trabalho (cloakroom): troca a roupa ao iniciar, restaura ao terminar.
-- As pecas ficam em cada frente (discipline.clothes). Restauracao salva/repoe
-- os componentes alterados (sem depender do sistema de skin do framework).
Config.WorkClothes = { enable = true }

-- Seta vermelha alta sobre os alvos (visivel de longe).
Config.RedArrowMarker = true

---------------------------------------------------------------------
-- MINIGAMES (compartilhado: dano + anti-skip). O mapeamento por tarefa
-- fica em cada frente (discipline.minigames).
---------------------------------------------------------------------
Config.Minigames = {
    failDamage = { min = 10, max = 25 },
    minSeconds = 1.5, -- tempo minimo entre abrir e concluir um alvo (anti-bot)
    panelMaxWrong = 2, -- voltimetro: cliques errados tolerados antes do choque (0 = falha no 1o erro)
}

---------------------------------------------------------------------
-- MINIGAMES EXTERNOS (ponte opcional p/ libs de terceiros) ----------
---------------------------------------------------------------------
-- Permite que qualquer tarefa use um minigame de uma lib externa via
-- export, sem nova dependencia obrigatoria. Se desligado (ou a lib
-- ausente / export com erro), cai no fallback (lib.skillCheck do ox_lib)
-- e o jogador NUNCA trava. O servidor continua validando tudo
-- (proximity, cooldown, minSeconds) — a ponte e so client-side.
--
-- Como usar:
--   1) instale a lib (ex.: bl_ui) e de ensure;
--   2) Config.ExternalMinigames.enable = true;
--   3) aponte a tarefa: discipline.minigames.byTask[task] = 'bl_untangle'
--      (a chave abaixo em .games). Ex. ja preparado: frente "towers".
--
-- ⚠️ ANTI-ALUCINACAO: as assinaturas abaixo foram tiradas do CODIGO REAL
-- do bl_ui (MIT) — cada jogo e `exports.bl_ui:Nome(iterations, config)` e
-- retorna boolean (Citizen.Await sincrono). Para OUTRAS libs (glitch etc.)
-- confirme a assinatura na versao instalada antes de habilitar.
--
-- Tipos de config do bl_ui (referencia, confirme em docs.byte-labs.net):
--   DifficultyConfig    = { difficulty=number }
--   KeyDifficultyConfig = { difficulty=number, numberOfKeys=number }
--   LengthConfig        = { length=number, duration=number }
--   LevelConfig         = { level=number, duration=number }
--   GridConfig          = { grid=number, duration=number, target=number }
--   NodeConfig          = { numberOfNodes=number, duration=number, previewDuration?=number }
Config.ExternalMinigames = {
    enable = false, -- liga o uso de libs externas

    -- chave -> spec de chamada (data-only; provider-agnostic).
    -- A ponte chama: exports[resource][export](iterations, config) -> boolean
    games = {
        -- bl_ui (MIT) — assinaturas confirmadas no codigo-fonte:
        bl_untangle  = { resource = 'bl_ui', export = 'Untangle',  iterations = 1, config = { numberOfNodes = 6, duration = 20 } },
        bl_circlesum = { resource = 'bl_ui', export = 'CircleSum',  iterations = 3, config = { length = 5, duration = 10 } },
        bl_lightsout = { resource = 'bl_ui', export = 'LightsOut',  iterations = 1, config = { level = 3, duration = 30 } },
        bl_keyspam   = { resource = 'bl_ui', export = 'KeySpam',    iterations = 1, config = { difficulty = 3, numberOfKeys = 4 } },

        -- glitch-minigames (GPL-3.0) — exemplo; ⚠️ confirme assinatura/retorno
        -- na versao instalada antes de usar:
        -- glitch_circuit = { resource = 'glitch-minigames', export = 'StartCircuitRumble', iterations = 1, config = {} },
    },
}

---------------------------------------------------------------------
-- PROGRESSAO (compartilhada entre frentes)
---------------------------------------------------------------------
Config.MaxLevel = 70
Config.RequiredXP = {}
for i = 1, Config.MaxLevel do
    Config.RequiredXP[i] = 1000 + (i - 1) * 500
end

---------------------------------------------------------------------
-- LOG (opcional, via convar)
---------------------------------------------------------------------
Config.LogWebhookConvar = 'vp_cityworks_webhook'

-- Plug & play: cria a tabela MySQL sozinho ao iniciar (sem importar SQL na mao).
Config.AutoCreateTable = true

---------------------------------------------------------------------
-- FRENTES DE TRABALHO (disciplinas)
-- Cada uma traz: label/icon/minLevel, veiculo, rotulos, equipamento,
-- raios, minigames e regioes. O eletricista e a 1a frente (Fase 1).
---------------------------------------------------------------------
Config.Disciplines = {
    electrician = {
        id        = 'electrician',
        label     = 'Eletricista',
        icon      = 'bolt',
        minLevel  = 0, -- nivel p/ acessar a frente
        vehicle   = { primary = `utillitruck2`, secondary = `utillitruck3`, fuel = 100.0 },

        taskLabels = {
            fixTrafo       = 'Reparar Transformador',
            fixHouseBoard  = 'Reparar Quadro de Luz',
            fixStreetLamp  = 'Reparar Poste de Luz',
            phonePole      = 'Reparar Poste Telefonico',
            fixTrafficLamp = 'Reparar Semaforo',
        },
        requiresEquipment = {
            fixStreetLamp = 'ladder',
            phonePole     = 'lift',
        },
        -- 2 PAPEIS: tarefas que exigem DESLIGAR A TENSAO antes do reparo.
        -- Um colega corta a energia (progressbar) e ai o reparo libera.
        needsPower    = { fixTrafo = true, fixHouseBoard = true },
        powerCutTime  = 4000, -- ms do progressbar de desligar a tensao
        -- Roupa de trabalho aplicada ao iniciar (cloakroom)
        clothes = {
            male = {
                { componentId = 4, drawable = 129, texture = 3 },  -- pants
                { componentId = 6, drawable = 57,  texture = 6 },  -- shoes
                { componentId = 8, drawable = 15,  texture = 0 },  -- undershirt
                { componentId = 11, drawable = 241, texture = 0 }, -- torso (jaqueta refletiva)
                { componentId = 3, drawable = 19,  texture = 0 },  -- arms
            },
            female = {
                { componentId = 4, drawable = 130, texture = 0 },
                { componentId = 6, drawable = 25,  texture = 0 },
                { componentId = 8, drawable = 15,  texture = 0 },
                { componentId = 11, drawable = 247, texture = 0 },
                { componentId = 3, drawable = 75,  texture = 0 },
            },
        },
        targetRadius = {
            fixTrafo = 2.5, fixHouseBoard = 2.5, fixStreetLamp = 3.0,
            phonePole = 3.0, fixTrafficLamp = 2.5, delivery = 10.0,
        },
        -- bandeira de gameplay: piscar semaforos defeituosos
        trafficLightModels = {
            `prop_traffic_03a`, `prop_traffic_02a`, `prop_traffic_01a`,
            `prop_traffic_01d`, `prop_traffic_lightset_01`, `prop_traffic_01b`, `prop_traffic_03b`,
        },
        minigames = {
            byTask = {
                fixTrafo       = 'panel',
                fixHouseBoard  = 'panel',
                fixStreetLamp  = 'welding',
                phonePole      = 'welding',
                fixTrafficLamp = 'wiring',
            },
            skillchecks = { default = { 'easy', 'medium' } },
            welding = {
                fixStreetLamp = { wireCount = 4, maxFails = 3, time = 60 },
                phonePole     = { wireCount = 5, maxFails = 3, time = 70 },
                default       = { wireCount = 4, maxFails = 3, time = 60 },
            },
            panel = {
                -- FOTO real do disjuntor (DEP3, feita pelo dono) em html/img/disjuntor.png.
                -- Para voltar ao disjuntor desenhado, remova o campo image.
                fixTrafo      = { panels = 12, image = 'nui://vp_cityworks/html/img/disjuntor.png' },
                fixHouseBoard = { panels = 9,  image = 'nui://vp_cityworks/html/img/disjuntor.png' },
                default       = { panels = 12, image = 'nui://vp_cityworks/html/img/disjuntor.png' },
            },
            wiring = {
                fixTrafficLamp = { count = 4 },
                default        = { count = 4 },
            },
        },

        regions = {
            {
                key = 1, title = 'Los Santos - Mission Row', minLevel = 0, maxPlayers = 4,
                awards = { money = 5000, xp = 1000, coopMultiplier = 1.5 },
                spawnCoords = { vec4(533.26, -1595.88, 28.52, 136.32), vec4(522.83, -1606.42, 28.64, 320.61) },
                deliveryCoords = vec3(533.26, -1595.88, 28.52),
                jobTasks = {
                    { name = 'fixTrafo', count = 1 }, { name = 'fixHouseBoard', count = 1 },
                    { name = 'fixStreetLamp', count = 1 }, { name = 'fixTrafficLamp', count = 1 },
                    { name = 'phonePole', count = 2 },
                },
                pools = {
                    fixTrafo = { vec3(-36.78, -1577.22, 29.52), vec3(-93.2, -1530.56, 34.0), vec3(-115.57, -1553.29, 34.33) },
                    fixHouseBoard = { vec3(215.55, -143.54, 58.55), vec3(229.16, -112.05, 69.73), vec3(151.14, -90.72, 64.27), vec3(57.32, -77.21, 62.26) },
                    fixStreetLamp = { vec3(296.49, -348.94, 49.62), vec3(300.07, -339.12, 50.92), vec3(303.89, -329.46, 51.08), vec3(268.28, -316.47, 51.2) },
                    phonePole = { vec3(-40.54, -1379.22, 40.37), vec3(0.73, -1378.96, 38.61), vec3(-5.01, -1355.6, 39.46), vec3(-45.92, -1355.53, 38.78) },
                    fixTrafficLamp = { vec3(202.47, -325.59, 42.97), vec3(179.57, -323.06, 42.97), vec3(165.74, -349.88, 43.03), vec3(202.9, -358.29, 43.01) },
                },
            },
            {
                key = 2, title = 'Los Santos - Vespucci', minLevel = 2, maxPlayers = 4,
                awards = { money = 7500, xp = 1250, coopMultiplier = 1.5 },
                spawnCoords = { vec4(533.26, -1595.88, 28.52, 136.32), vec4(522.83, -1606.42, 28.64, 320.61) },
                deliveryCoords = vec3(533.26, -1595.88, 28.52),
                jobTasks = {
                    { name = 'fixTrafo', count = 2 }, { name = 'fixHouseBoard', count = 2 },
                    { name = 'fixStreetLamp', count = 2 }, { name = 'fixTrafficLamp', count = 2 },
                    { name = 'phonePole', count = 2 },
                },
                pools = {
                    fixTrafo = { vec3(971.73, -1810.68, 31.03), vec3(963.1, -1828.73, 30.96), vec3(961.2, -1808.28, 30.99) },
                    fixHouseBoard = { vec3(709.88, -2139.19, 29.07), vec3(709.05, -2149.26, 28.96), vec3(708.18, -2158.47, 29.45), vec3(707.28, -2168.47, 28.75) },
                    fixStreetLamp = { vec3(825.12, -2247.5, 36.11), vec3(859.92, -2250.55, 36.17), vec3(910.08, -2236.19, 36.55), vec3(923.31, -2257.48, 36.27) },
                    phonePole = { vec3(830.6, -2248.05, 40.53), vec3(894.94, -2253.68, 40.58), vec3(776.15, -2284.71, 38.18) },
                    fixTrafficLamp = { vec3(850.0, -1766.74, 29.17), vec3(847.65, -1728.46, 30.06), vec3(806.26, -1766.21, 29.67), vec3(802.22, -1732.87, 29.37) },
                },
            },
            {
                key = 3, title = 'Los Santos - Del Perro', minLevel = 4, maxPlayers = 4,
                awards = { money = 10000, xp = 1500, coopMultiplier = 1.5 },
                spawnCoords = { vec4(533.26, -1595.88, 28.52, 136.32), vec4(522.83, -1606.42, 28.64, 320.61) },
                deliveryCoords = vec3(533.26, -1595.88, 28.52),
                jobTasks = {
                    { name = 'fixTrafo', count = 2 }, { name = 'fixHouseBoard', count = 2 },
                    { name = 'fixStreetLamp', count = 2 }, { name = 'fixTrafficLamp', count = 2 },
                    { name = 'phonePole', count = 2 },
                },
                pools = {
                    fixTrafo = { vec3(-1266.89, -1120.51, 7.17), vec3(-1255.37, -1153.72, 7.9), vec3(-1248.24, -1193.38, 8.43) },
                    fixHouseBoard = { vec3(-1114.89, -1218.55, 2.82), vec3(-1108.51, -1223.37, 2.73), vec3(-1114.95, -1260.07, 7.12) },
                    fixStreetLamp = { vec3(-1136.04, -1317.53, 10.8), vec3(-1098.24, -1324.26, 11.02), vec3(-1077.21, -1333.9, 11.91) },
                    phonePole = { vec3(-1268.56, -1034.12, 19.06), vec3(-1281.57, -1070.53, 16.77), vec3(-1295.11, -1077.0, 17.07) },
                    fixTrafficLamp = { vec3(-1292.26, -1177.19, 4.65), vec3(-1280.68, -1192.81, 4.73), vec3(-1296.91, -1207.0, 4.68), vec3(-1312.14, -1192.63, 4.79) },
                },
            },
            {
                key = 4, title = 'Los Santos - Rockford', minLevel = 6, maxPlayers = 4,
                awards = { money = 15000, xp = 2000, coopMultiplier = 1.5 },
                spawnCoords = { vec4(533.26, -1595.88, 28.52, 136.32), vec4(522.83, -1606.42, 28.64, 320.61) },
                deliveryCoords = vec3(533.26, -1595.88, 28.52),
                jobTasks = {
                    { name = 'fixTrafo', count = 3 }, { name = 'fixHouseBoard', count = 3 },
                    { name = 'fixStreetLamp', count = 3 }, { name = 'fixTrafficLamp', count = 2 },
                    { name = 'phonePole', count = 3 },
                },
                pools = {
                    fixTrafo = { vec3(-1311.33, -162.08, 45.38), vec3(-1310.36, -177.1, 43.78), vec3(-1350.07, -207.32, 43.82) },
                    fixHouseBoard = { vec3(-1160.88, -214.45, 37.63), vec3(-1146.97, -361.66, 38.08), vec3(-678.76, -176.53, 37.67) },
                    fixStreetLamp = { vec3(-288.16, -340.08, 35.44), vec3(-307.27, -320.6, 36.54), vec3(-326.56, -292.77, 37.17) },
                    phonePole = { vec3(-1650.41, -354.58, 60.19), vec3(-1669.68, -368.92, 60.02), vec3(-1702.68, -406.54, 57.31) },
                    fixTrafficLamp = { vec3(-679.53, -220.59, 37.06), vec3(-695.05, -205.35, 37.41), vec3(-723.64, -228.71, 37.38), vec3(-704.67, -246.78, 37.21) },
                },
            },
        },
    },

    -----------------------------------------------------------------
    -- ASFALTO / VIAS (modo DRILL — alvo com vida, britadeira)
    -----------------------------------------------------------------
    roadwork = {
        id = 'roadwork', label = 'Asfalto / Vias', icon = 'road', minLevel = 0,
        vehicle = { primary = `tiptruck`, secondary = `tiptruck`, fuel = 100.0 },
        taskLabels = { pothole = 'Tapar Buraco', roadblock = 'Remover Bloqueio' },
        requiresEquipment = {},
        targetRadius = { pothole = 2.5, roadblock = 3.0, delivery = 10.0 },
        taskMode = { pothole = 'drill', roadblock = 'drill' },
        drill = {
            pothole   = { health = 4, hitTime = 1500 },
            roadblock = { health = 6, hitTime = 1500 },
        },
        regions = {
            {
                key = 1, title = 'Vias - Centro', minLevel = 0, maxPlayers = 4,
                awards = { money = 6000, xp = 1100, coopMultiplier = 1.5 },
                spawnCoords = { vec4(533.26, -1595.88, 28.52, 136.32), vec4(522.83, -1606.42, 28.64, 320.61) },
                deliveryCoords = vec3(533.26, -1595.88, 28.52),
                jobTasks = { { name = 'pothole', count = 3 }, { name = 'roadblock', count = 2 } },
                pools = {
                    pothole = { vec3(215.0, -810.0, 30.7), vec3(120.0, -1040.0, 29.0), vec3(-260.0, -690.0, 33.5), vec3(40.0, -1290.0, 29.2) },
                    roadblock = { vec3(180.0, -930.0, 30.6), vec3(-70.0, -800.0, 44.0), vec3(300.0, -1150.0, 29.2) },
                },
            },
        },
    },

    -----------------------------------------------------------------
    -- CONSTRUCAO / OBRA (modo BUILD — progressbar + props)
    -----------------------------------------------------------------
    construction = {
        id = 'construction', label = 'Construcao / Obra', icon = 'helmet-safety', minLevel = 3,
        vehicle = { primary = `mixer`, secondary = `flatbed`, fuel = 100.0 },
        taskLabels = { scaffold = 'Montar Andaime', wall = 'Levantar Muro' },
        requiresEquipment = {},
        targetRadius = { scaffold = 3.0, wall = 3.0, delivery = 10.0 },
        taskMode = { scaffold = 'build', wall = 'build' },
        build = {
            -- minigame = 'hammer' -> roda o NUI do Construtor (martelar pregos)
            -- antes de erguer o prop. nails = qtde de pregos. Remova p/ usar so progressbar.
            scaffold = { time = 8000, prop = `prop_scaffold_02a`, zOffset = 1.0, heading = 0.0, minigame = 'hammer', nails = 4 },
            wall     = { time = 6000, prop = `prop_barrier_work05`, zOffset = 1.0, heading = 0.0, minigame = 'hammer', nails = 3 },
        },
        regions = {
            {
                key = 1, title = 'Obra - Zona Sul', minLevel = 3, maxPlayers = 4,
                awards = { money = 9000, xp = 1600, coopMultiplier = 1.5 },
                spawnCoords = { vec4(533.26, -1595.88, 28.52, 136.32), vec4(522.83, -1606.42, 28.64, 320.61) },
                deliveryCoords = vec3(533.26, -1595.88, 28.52),
                jobTasks = { { name = 'scaffold', count = 2 }, { name = 'wall', count = 3 } },
                pools = {
                    scaffold = { vec3(-140.0, -970.0, 28.0), vec3(-120.0, -1010.0, 28.0), vec3(-90.0, -980.0, 28.0) },
                    wall = { vec3(-150.0, -1000.0, 28.0), vec3(-110.0, -1030.0, 28.0), vec3(-80.0, -1000.0, 28.0), vec3(-130.0, -950.0, 28.0) },
                },
            },
        },
    },

    -----------------------------------------------------------------
    -- SINALIZACAO (BUILD: instalar placa | MINIGAME: pintar faixa)
    -----------------------------------------------------------------
    signage = {
        id = 'signage', label = 'Sinalizacao', icon = 'sign-hanging', minLevel = 1,
        vehicle = { primary = `utillitruck2`, secondary = `utillitruck3`, fuel = 100.0 },
        taskLabels = { sign = 'Instalar Placa', paint = 'Pintar Faixa' },
        requiresEquipment = {},
        targetRadius = { sign = 2.5, paint = 2.5, delivery = 10.0 },
        taskMode = { sign = 'build', paint = 'minigame' },
        build = { sign = { time = 5000, prop = `prop_consign_01a`, zOffset = 1.0, heading = 0.0 } },
        minigames = {
            byTask = { paint = 'skillcheck' },
            skillchecks = { paint = { 'easy', 'medium' }, default = { 'easy', 'medium' } },
        },
        regions = {
            {
                key = 1, title = 'Sinalizacao - Centro', minLevel = 1, maxPlayers = 4,
                awards = { money = 5500, xp = 1000, coopMultiplier = 1.5 },
                spawnCoords = { vec4(533.26, -1595.88, 28.52, 136.32), vec4(522.83, -1606.42, 28.64, 320.61) },
                deliveryCoords = vec3(533.26, -1595.88, 28.52),
                jobTasks = { { name = 'sign', count = 2 }, { name = 'paint', count = 3 } },
                pools = {
                    sign = { vec3(230.0, -870.0, 30.6), vec3(110.0, -1090.0, 29.2), vec3(-300.0, -710.0, 33.5) },
                    paint = { vec3(200.0, -900.0, 30.6), vec3(90.0, -1110.0, 29.2), vec3(-280.0, -730.0, 33.5), vec3(60.0, -1270.0, 29.2) },
                },
            },
        },
    },

    -----------------------------------------------------------------
    -- ILUMINACAO PUBLICA (MINIGAME — trocar lampada, sem lift)
    -----------------------------------------------------------------
    streetlight = {
        id = 'streetlight', label = 'Iluminacao', icon = 'lightbulb', minLevel = 0,
        vehicle = { primary = `utillitruck2`, secondary = `utillitruck3`, fuel = 100.0 },
        taskLabels = { bulb = 'Trocar Lampada' },
        requiresEquipment = {},
        targetRadius = { bulb = 2.5, delivery = 10.0 },
        taskMode = { bulb = 'minigame' },
        minigames = {
            byTask = { bulb = 'panel' },
            panel = { bulb = { panels = 9 }, default = { panels = 9 } },
        },
        regions = {
            {
                key = 1, title = 'Iluminacao - Centro', minLevel = 0, maxPlayers = 4,
                awards = { money = 4500, xp = 900, coopMultiplier = 1.5 },
                spawnCoords = { vec4(533.26, -1595.88, 28.52, 136.32), vec4(522.83, -1606.42, 28.64, 320.61) },
                deliveryCoords = vec3(533.26, -1595.88, 28.52),
                jobTasks = { { name = 'bulb', count = 4 } },
                pools = {
                    bulb = { vec3(296.49, -348.94, 49.62), vec3(300.07, -339.12, 50.92), vec3(303.89, -329.46, 51.08), vec3(268.28, -316.47, 51.2), vec3(286.73, -323.17, 50.03) },
                },
            },
        },
    },

    -----------------------------------------------------------------
    -- GUINCHO / REBOQUE (kind = 'towing' — fluxo proprio)
    -- Reimplementado do zero (inspirado no 0r-towtruck, open source).
    -----------------------------------------------------------------
    towing = {
        id = 'towing', label = 'Guincho', icon = 'truck-pickup', minLevel = 0,
        kind = 'towing', -- ativa o motor de reboque (client/server towing.lua)
        vehicle = { primary = `flatbed`, secondary = `flatbed`, fuel = 100.0 },
        taskLabels = { tow = 'Rebocar Veiculo' },
        targetRadius = { delivery = 12.0 },
        loadDistance = 8.0,       -- distancia (flatbed<->veiculo) p/ carregar
        attachOffset = { x = 0.0, y = -2.6, z = 1.0 }, -- posicao padrao do veiculo no flatbed
        -- offset por MODELO (sobrescreve o padrao). Z = altura do leito p/ as rodas
        -- assentarem. Ajuste fino in-game. Fallback dinamico via GetModelDimensions.
        vehiclePositions = {
            -- [`baller`] = { x = 0.0, y = -2.6, z = 1.1 },
            -- [`prairie`] = { x = 0.0, y = -2.6, z = 1.0 },
        },
        -- pontos de entrega dos veiculos rebocados
        deliveryPoints = {
            vec3(-217.97, 6253.78, 30.49),
            vec3(2414.78, 3100.86, 46.53),
            vec3(421.17, -1635.85, 27.66),
        },
        -- pool de veiculos quebrados (sorteados por servico)
        variants = {
            { model = `baller`,    coords = vec4(1332.75, 602.34, 79.16, 324.17),  reason = 'Falha no motor' },
            { model = `prairie`,   coords = vec4(-1467.01, -880.62, 9.16, 71.59),  reason = 'Pneu furado' },
            { model = `tailgater`, coords = vec4(11.39, -152.17, 54.44, 252.64),   reason = 'Mal estacionado' },
            { model = `kuruma`,    coords = vec4(2396.71, 5192.42, 51.21, 359.28), reason = 'Falha no motor' },
            { model = `futo`,      coords = vec4(-693.47, -646.7, 29.47, 87.89),   reason = 'Sem combustivel' },
            { model = `sultan`,    coords = vec4(-1070.57, -1422.62, 3.72, 166.36),reason = 'Mal estacionado' },
        },
        regions = {
            {
                key = 1, title = 'Guincho - Los Santos', minLevel = 0, maxPlayers = 4,
                awards = { money = 8000, xp = 1400, coopMultiplier = 1.5 },
                spawnCoords = { vec4(409.64, -1652.71, 28.38, 319.72), vec4(405.24, -1648.4, 28.38, 320.08) },
                deliveryCoords = vec3(409.64, -1652.71, 28.38), -- depot p/ devolver o flatbed
                towCount = 3, -- quantos veiculos rebocar no servico
            },
        },
    },

    -----------------------------------------------------------------
    -- MANUTENCAO DE TORRES (kind = 'towers' — integra com vp_towers)
    -- Conserta as torres de radio do vp_towers (SetTowerHealth -> 100).
    -- Os alvos sao GERADOS dinamicamente a partir das torres danificadas
    -- (health < repairThreshold). Reparo no solo (base da torre), minigame
    -- de fiacao "reconfigurar a antena". Requer o resource vp_towers ligado.
    -----------------------------------------------------------------
    towers = {
        id = 'towers', label = 'Manutencao de Torres', icon = 'tower-broadcast', minLevel = 2,
        kind = 'towers', -- ativa a geracao dinamica de alvos (server/main.lua)
        vehicle = { primary = `utillitruck2`, secondary = `utillitruck3`, fuel = 100.0 },
        taskLabels = { fix = 'Reparar Torre' },
        targetRadius = { fix = 5.0, delivery = 12.0 },
        requiresEquipment = {}, -- reparo no solo (base da torre); sem escada/lift
        taskMode = { fix = 'minigame' },
        minigames = {
            -- 'wiring' = nosso NUI de fiacao. Para um "hack de antena" com lib
            -- externa, ligue Config.ExternalMinigames.enable e troque por uma
            -- chave de .games, ex.: byTask = { fix = 'bl_untangle' }.
            byTask = { fix = 'wiring' },
            wiring = { fix = { count = 5 }, default = { count = 4 } },
        },
        -- INTEGRACAO com vp_towers (resource separado; exports server-side)
        integration = {
            resource        = 'vp_towers',
            repairThreshold = 100,  -- torre conta como "danificada" se health < isto
            repairTo        = 100,  -- health restaurado ao concluir o reparo
            simulateDamage  = true, -- se faltar torre danificada, danifica algumas p/ gerar trabalho
            damagedHealth   = 20,   -- health aplicado ao simular dano
        },
        regions = {
            {
                key = 1, title = 'Torres - Regiao Metropolitana', minLevel = 2, maxPlayers = 4,
                awards = { money = 9500, xp = 1600, coopMultiplier = 1.5 },
                spawnCoords = { vec4(533.26, -1595.88, 28.52, 136.32), vec4(522.83, -1606.42, 28.64, 320.61) },
                deliveryCoords = vec3(533.26, -1595.88, 28.52), -- depot p/ devolver o veiculo
                towCount = 3, -- quantas torres reparar no servico (limite de alvos)
            },
        },
    },
}

-- Ordem das frentes no menu
Config.DisciplineOrder = { 'electrician', 'roadwork', 'construction', 'signage', 'streetlight', 'towing', 'towers' }

-- ── Desgaste de torres (OPCIONAL) ─────────────────────────────────
-- Sistema de fundo que danifica torres do vp_towers ao longo do tempo,
-- criando demanda natural para a frente "Manutencao de Torres".
-- Desativado por padrao: ligar afeta a cobertura de sinal usada por
-- vp_crimescene/vp_policejob. A frente tambem funciona sem isto graças
-- ao simulateDamage da integracao (gera trabalho ao iniciar o servico).
Config.TowerWear = {
    enable    = false,       -- true p/ degradar torres automaticamente
    resource  = 'vp_towers', -- resource alvo
    interval  = 600000,      -- ms entre desgastes (10 min)
    amount    = 15,          -- quanto de health remove por tick
    minHealth = 0,           -- nao baixa abaixo disto
    chance    = 50,          -- % de chance de ocorrer desgaste a cada tick
}
