-- client/minigames.lua :: camada HIBRIDA de minigame
--   'skillcheck' -> lib.skillCheck (ox_lib, sem NUI)
--   'welding' | 'panel' | 'wiring' -> NUI custom (html/)

local nuiCb = nil -- callback pendente do minigame NUI ativo

-- mapeia tipo de minigame NUI -> action + tabela de settings no Config
local NUI_GAMES = {
    welding = { action = 'START_WELD',   cfg = 'welding' },
    panel   = { action = 'START_PANEL',  cfg = 'panel' },
    wiring  = { action = 'START_WIRING', cfg = 'wiring' },
    hammer  = { action = 'START_HAMMER', cfg = 'hammer' },
}

--- Roda um minigame NUI ESPECIFICO com settings explicitas (ex.: BuildTask -> hammer).
--- @param kind string   ex.: 'hammer'
--- @param settings table
--- @param cb fun(success: boolean)
function StartNamedMinigame(kind, settings, cb)
    local nui = NUI_GAMES[kind]
    if not nui then return StartSkillcheck(nil, cb) end
    nuiCb = cb
    PlayWorkAnim()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = nui.action, settings = settings or {} })
end

--- Roda o minigame da tarefa e chama cb(success).
--- @param taskType string  ex.: 'fixStreetLamp'
--- @param cb fun(success: boolean)
-- config de minigames da frente ativa
local function discMinigames()
    return (ActiveDiscipline and ActiveDiscipline.minigames) or {}
end

function StartMinigame(taskType, cb)
    local mg = discMinigames()
    local kind = (mg.byTask and mg.byTask[taskType]) or 'skillcheck'

    -- 1) minigame de lib EXTERNA (opt-in via Config.ExternalMinigames)
    local ext = Config.ExternalMinigames
    if ext and ext.enable and ext.games and ext.games[kind] then
        return StartExternal(ext.games[kind], taskType, cb)
    end

    -- 2) NUI custom (solda/painel/fiacao)
    local nui = NUI_GAMES[kind]
    if nui then
        return StartNuiGame(nui, taskType, cb)
    end

    -- 3) fallback: skillcheck do ox_lib
    return StartSkillcheck(taskType, cb)
end

---------------------------------------------------------------------
-- PONTE p/ MINIGAME EXTERNO (bl_ui / glitch / etc.)
-- spec = { resource, export, iterations, config }. Chama o export real
-- e trata o retorno booleano. Se a lib nao estiver ligada ou o export
-- falhar, cai no skillcheck (o jogador NUNCA fica preso).
---------------------------------------------------------------------
function StartExternal(spec, taskType, cb)
    if type(spec) ~= 'table' or not spec.resource or not spec.export then
        return StartSkillcheck(taskType, cb)
    end
    if GetResourceState(spec.resource) ~= 'started' then
        print(('^3[vp_cityworks]^0 minigame externo "%s" indisponivel (%s nao iniciado); usando skillcheck.')
            :format(spec.export, spec.resource))
        return StartSkillcheck(taskType, cb)
    end

    PlayWorkAnim()
    local ok, ret = pcall(function()
        local fn = exports[spec.resource][spec.export]
        return fn(spec.iterations or 1, spec.config or {})
    end)
    StopWorkAnim()

    if not ok then
        print(('^1[vp_cityworks]^0 erro no minigame externo %s:%s — caindo no skillcheck.')
            :format(spec.resource, spec.export))
        return StartSkillcheck(taskType, cb)
    end
    cb(ret == true)
end

---------------------------------------------------------------------
-- SKILLCHECK (ox_lib) - fallback
---------------------------------------------------------------------
function StartSkillcheck(taskType, cb)
    local sc = discMinigames().skillchecks or {}
    local checks = sc[taskType] or sc.default or { 'easy', 'medium' }
    PlayWorkAnim()
    local success = lib.skillCheck(checks)
    StopWorkAnim()
    cb(success)
end

---------------------------------------------------------------------
-- NUI (solda / painel / fiacao)
---------------------------------------------------------------------
function StartNuiGame(nui, taskType, cb)
    local tbl = discMinigames()[nui.cfg] or {}
    local settings = tbl[taskType] or tbl.default or {}
    -- injeta o maxWrong global no painel (copia, sem mutar a config)
    if nui.cfg == 'panel' and Config.Minigames.panelMaxWrong ~= nil then
        local c = {}; for k, v in pairs(settings) do c[k] = v end
        c.maxWrong = Config.Minigames.panelMaxWrong
        settings = c
    end
    nuiCb = cb
    PlayWorkAnim()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = nui.action, settings = settings })
end

RegisterNUICallback('minigameResult', function(data, cb)
    SetNuiFocus(false, false)
    StopWorkAnim()
    local fn = nuiCb
    nuiCb = nil
    if fn then fn(data and data.success == true) end
    cb('ok')
end)

---------------------------------------------------------------------
-- ANIMACAO DE TRABALHO
---------------------------------------------------------------------
function PlayWorkAnim()
    FreezeEntityPosition(cache.ped, true)
    local dict = 'amb@world_human_welding@male@base'
    lib.requestAnimDict(dict)
    TaskPlayAnim(cache.ped, dict, 'base', 8.0, 1.0, -1, 1, 0, false, false, false)
end

function StopWorkAnim()
    ClearPedTasks(cache.ped)
    FreezeEntityPosition(cache.ped, false)
end

---------------------------------------------------------------------
-- DANO DE CHOQUE (falha)
---------------------------------------------------------------------
function ApplyShockDamage()
    local dmg = math.random(Config.Minigames.failDamage.min, Config.Minigames.failDamage.max)
    local dict = 'ragdoll@human'
    lib.requestAnimDict(dict)
    TaskPlayAnim(cache.ped, dict, 'electrocute', 8.0, 1.0, -1, 1, 0, false, false, false)
    FreezeEntityPosition(cache.ped, true)
    SetTimeout(2500, function()
        ClearPedTasksImmediately(cache.ped)
        FreezeEntityPosition(cache.ped, false)
    end)
    local health = GetEntityHealth(cache.ped)
    SetEntityHealth(cache.ped, math.max(1, health - dmg))
end

-- seguranca: libera foco se o resource parar com a NUI aberta
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and nuiCb then
        SetNuiFocus(false, false)
        nuiCb = nil
    end
end)
