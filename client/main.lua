-- client/main.lua :: interacao, menu (ox_lib context - parte do hibrido), lobby
-- NUI custom entra depois; por ora a UI de lobby/regiao usa ox_lib menus.

local pedSpawned = false
local lobbyPlayers = {}
local selectedRegion = false
local currentDiscipline = nil -- id da frente ativa no lobby

---------------------------------------------------------------------
-- NOTIFICACAO in-NUI (unifica client + server na NUI propria)
-- ntype no estilo ox_lib: 'error' | 'success' | 'inform' (-> info)
---------------------------------------------------------------------
function CityNotify(msg, ntype)
    SendNUIMessage({ action = 'NOTIFY', ntype = ntype or 'inform', message = msg })
end
-- o servidor (Framework.Notify) dispara este evento p/ cair na NUI
RegisterNetEvent('vp_cityworks:notify', function(msg, ntype) CityNotify(msg, ntype) end)

---------------------------------------------------------------------
-- PED + BLIP + TARGET
---------------------------------------------------------------------
CreateThread(function()
    -- blip
    if Config.Interaction.blip.enable then
        local b = Config.Interaction.blip
        local blip = AddBlipForCoord(Config.Interaction.coords.x, Config.Interaction.coords.y, Config.Interaction.coords.z)
        SetBlipSprite(blip, b.sprite)
        SetBlipColour(blip, b.color)
        SetBlipScale(blip, b.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(b.label)
        EndTextCommandSetBlipName(blip)
    end

    -- ped
    lib.requestModel(Config.Interaction.pedModel)
    local c = Config.Interaction.coords
    local ped = CreatePed(0, Config.Interaction.pedModel, c.x, c.y, c.z - 1.0, c.w, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetModelAsNoLongerNeeded(Config.Interaction.pedModel)
    pedSpawned = true

    -- ox_target
    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'vp_cityworks_open',
            icon = 'fas fa-bolt',
            label = locale('open_menu'),
            distance = Config.Interaction.targetDistance,
            onSelect = function() OpenMenu() end,
        },
    })
end)

---------------------------------------------------------------------
-- CHECK DE JOB
---------------------------------------------------------------------
local function canOpen()
    if Config.RequiredJob == 'all' then return true end
    local job = Framework.GetJob()
    for jobName, minGrade in pairs(Config.RequiredJob) do
        if job.name == jobName and job.grade >= minGrade then
            return true
        end
    end
    CityNotify(locale('wrong_job'), 'error')
    return false
end

---------------------------------------------------------------------
-- MENU (NUI custom)
---------------------------------------------------------------------
local menuOpen = false

--- Monta o payload do menu a partir do getProfile + Config.Disciplines.
local function buildMenuPayload(data)
    local discId = data.disciplineId or Config.DisciplineOrder[1]
    local disc = Config.Disciplines[discId]
    local disciplines = {}
    for _, id in ipairs(Config.DisciplineOrder) do
        local d = Config.Disciplines[id]
        disciplines[#disciplines + 1] = { id = id, label = d.label, icon = d.icon, locked = data.level < (d.minLevel or 0) }
    end
    -- monta a lista de tarefas de uma regiao (usa Config, que e shared)
    local function regionTasks(d, r)
        local tasks = {}
        if d.kind == 'towing' then
            tasks[#tasks + 1] = { count = r.towCount or 3, label = d.taskLabels.tow or 'Reboque' }
        elseif d.kind == 'towers' then
            tasks[#tasks + 1] = { count = r.towCount or 3, label = d.taskLabels.fix or 'Reparar Torre' }
        elseif r.jobTasks then
            for _, t in ipairs(r.jobTasks) do
                tasks[#tasks + 1] = { count = t.count, label = (d.taskLabels and d.taskLabels[t.name]) or t.name }
            end
        end
        return tasks
    end
    local regions = {}
    if disc then
        for _, r in ipairs(disc.regions) do
            regions[#regions + 1] = {
                key = r.key, title = r.title, money = r.awards.money, xp = r.awards.xp, minLevel = r.minLevel,
                maxPlayers = r.maxPlayers or 4,
                locked = data.level < r.minLevel,
                selected = (data.region and data.region.key == r.key) or false,
                tasks = regionTasks(disc, r),
            }
        end
    end
    local players = {}
    for cid, p in pairs(data.players or {}) do
        players[#players + 1] = { cid = cid, name = p.name, level = p.level, owner = (cid == data.ownerCid) }
    end
    -- itens de recompensa (global) p/ o painel de detalhes
    local rewardItems = {}
    for _, ri in ipairs(Config.RewardItems or {}) do
        if ri.item then rewardItems[#rewardItems + 1] = { item = ri.item, amount = ri.amount or 1, chance = ri.chance or 0 } end
    end
    return {
        name = data.name, level = data.level, xp = data.xp, nextXp = data.nextXp, money = data.money,
        isOwner = data.isOwner, maxPlayers = data.maxPlayers or Config.MaxPlayersPerLobby,
        bossSplit = Config.BossRewardSplit,
        disciplines = disciplines, currentDiscipline = discId, disciplineLabel = disc and disc.label or '',
        disciplineIcon = disc and disc.icon or '', regions = regions, players = players,
        selectedRegion = data.region and data.region.key or nil,
        rewardItems = rewardItems,
        requiredItem = (Config.RequiredItem and Config.RequiredItem.enable) and Config.RequiredItem.name or nil,
    }
end

--- Busca dados frescos e envia ao NUI (OPEN_MENU ou MENU_UPDATE).
local function fetchAndSend(action)
    local data = lib.callback.await('vp_cityworks:getProfile', false)
    if not data then return end
    lobbyPlayers = data.players or {}
    currentDiscipline = data.disciplineId or Config.DisciplineOrder[1]
    selectedRegion = data.region or false
    SendNUIMessage({ action = action, data = buildMenuPayload(data) })
    return true
end

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'CLOSE_MENU' })
end

function OpenMenu()
    if not canOpen() then return end
    if JobActive then
        CityNotify(locale('job_already_started'), 'inform')
        return
    end
    if not fetchAndSend('OPEN_MENU') then return end
    menuOpen = true
    SetNuiFocus(true, true)
end

function StartJobCheck()
    TriggerServerEvent('vp_cityworks:startJob') -- server revalida regiao/nivel/zona
end

-- callbacks do NUI do menu (o refreshLobby do server atualiza o menu ao vivo)
RegisterNUICallback('menuDiscipline', function(d, cb) TriggerServerEvent('vp_cityworks:selectDiscipline', d.id); cb('ok') end)
RegisterNUICallback('menuMission', function(d, cb) TriggerServerEvent('vp_cityworks:selectMission', d.key); cb('ok') end)
RegisterNUICallback('menuInvite', function(d, cb) if d.id then TriggerServerEvent('vp_cityworks:invite', d.id) end; cb('ok') end)
RegisterNUICallback('menuKick', function(d, cb) if d.cid then TriggerServerEvent('vp_cityworks:kickPlayer', d.cid) end; cb('ok') end)
RegisterNUICallback('menuSplit', function(d, cb) if type(d.split) == 'table' then TriggerServerEvent('vp_cityworks:setRewardSplit', d.split) end; cb('ok') end)
RegisterNUICallback('menuStart', function(d, cb) closeMenu(); StartJobCheck(); cb('ok') end)
RegisterNUICallback('menuClose', function(d, cb) menuOpen = false; SetNuiFocus(false, false); cb('ok') end)

---------------------------------------------------------------------
-- EVENTOS DE LOBBY
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:refreshLobby', function(players, disciplineId, region)
    lobbyPlayers = players or {}
    currentDiscipline = disciplineId or currentDiscipline
    selectedRegion = region or false
    if menuOpen then fetchAndSend('MENU_UPDATE') end -- atualiza o menu ao vivo
end)

RegisterNetEvent('vp_cityworks:receiveInvite', function(hostName, hostCid)
    local accept = lib.alertDialog({
        header = 'Convite - Secretaria de Obras',
        content = ('%s convidou voce para um trabalho. Aceitar?'):format(hostName),
        centered = true,
        cancel = true,
    })
    if accept == 'confirm' then
        TriggerServerEvent('vp_cityworks:acceptInvite')
    end
end)

RegisterNetEvent('vp_cityworks:leftLobby', function()
    selectedRegion = false
    lobbyPlayers = {}
    closeMenu()
end)

RegisterNetEvent('vp_cityworks:rewardScreen', function(info)
    SendNUIMessage({ action = 'REWARD', data = info })
end)

-- comando p/ resetar o job em andamento (so o dono reseta; server valida)
RegisterCommand(Config.JobResetCommand, function()
    if JobActive then
        TriggerServerEvent('vp_cityworks:resetJob')
    end
end, false)
