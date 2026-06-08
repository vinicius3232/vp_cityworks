-- client/minigames.lua :: camada HIBRIDA de minigame
--   'skillcheck' -> lib.skillCheck (ox_lib, sem NUI)
--   'welding' | 'panel' | 'wiring' -> NUI custom (html/)

local nuiCb = nil -- callback pendente do minigame NUI ativo

-- mapeia tipo de minigame NUI -> action + tabela de settings no Config
local NUI_GAMES = {
    welding = { action = 'START_WELD',   cfg = 'welding' },
    panel   = { action = 'START_PANEL',  cfg = 'panel' },
    wiring  = { action = 'START_WIRING', cfg = 'wiring' },
}

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
    local nui = NUI_GAMES[kind]
    if nui then
        return StartNuiGame(nui, taskType, cb)
    end
    return StartSkillcheck(taskType, cb)
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
