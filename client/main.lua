-- client/main.lua :: interacao, menu (ox_lib context - parte do hibrido), lobby
-- NUI custom entra depois; por ora a UI de lobby/regiao usa ox_lib menus.

local pedSpawned = false
local lobbyPlayers = {}
local selectedRegion = false
local currentDiscipline = nil -- id da frente ativa no lobby

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
    lib.notify({ description = locale('wrong_job'), type = 'error' })
    return false
end

---------------------------------------------------------------------
-- MENU (ox_lib context)
---------------------------------------------------------------------
function OpenMenu()
    if not canOpen() then return end
    if JobActive then
        lib.notify({ description = locale('job_already_started'), type = 'inform' })
        return
    end
    local data = lib.callback.await('vp_cityworks:getProfile', false)
    if not data then return end
    lobbyPlayers = data.players or {}
    currentDiscipline = data.disciplineId or Config.DisciplineOrder[1]
    selectedRegion = data.region or false
    local disc = Config.Disciplines[currentDiscipline]

    local options = {
        {
            title = ('%s — Nivel %s'):format(data.name, data.level),
            description = ('XP: %s / %s  |  Banco: $%s'):format(data.xp, data.nextXp, data.money),
            icon = 'user',
            disabled = true,
        },
    }

    -- seletor de FRENTE (so aparece se houver mais de uma)
    if #Config.DisciplineOrder > 1 and data.isOwner then
        for _, dId in ipairs(Config.DisciplineOrder) do
            local d = Config.Disciplines[dId]
            local locked = data.level < (d.minLevel or 0)
            local cur = currentDiscipline == dId
            options[#options + 1] = {
                title = (cur and '➤ ' or '') .. 'Frente: ' .. d.label,
                description = locked and ('Nivel min: ' .. d.minLevel) or 'Selecionar esta frente',
                icon = d.icon or 'briefcase',
                disabled = locked or cur,
                onSelect = function()
                    TriggerServerEvent('vp_cityworks:selectDiscipline', dId)
                    Wait(150)
                    OpenMenu()
                end,
            }
        end
    end

    -- regioes da frente ativa
    for _, region in ipairs(disc.regions) do
        local locked = data.level < region.minLevel
        local sel = selectedRegion and selectedRegion.key == region.key
        options[#options + 1] = {
            title = (sel and '✓ ' or '') .. region.title,
            description = ('Recompensa: $%s + %s XP  |  Nivel min: %s')
                :format(region.awards.money, region.awards.xp, region.minLevel),
            icon = 'location-dot',
            disabled = locked,
            onSelect = function()
                TriggerServerEvent('vp_cityworks:selectMission', region.key)
                Wait(150)
                OpenMenu()
            end,
        }
    end

    -- convidar
    options[#options + 1] = {
        title = 'Convidar jogador',
        icon = 'user-plus',
        onSelect = function()
            local input = lib.inputDialog('Convidar', { { type = 'number', label = 'ID do jogador', required = true } })
            if input and input[1] then
                TriggerServerEvent('vp_cityworks:invite', input[1])
            end
        end,
    }

    -- dividir recompensa (boss split) - so dono, com 2+ membros
    local memberCids = {}
    for c in pairs(lobbyPlayers) do memberCids[#memberCids + 1] = c end
    if Config.BossRewardSplit and data.isOwner and #memberCids > 1 then
        options[#options + 1] = {
            title = 'Dividir recompensa',
            icon = 'percent',
            description = 'Defina a % de pagamento de cada membro',
            onSelect = function()
                local fields, def = {}, math.floor(100 / #memberCids)
                for _, c in ipairs(memberCids) do
                    fields[#fields + 1] = {
                        type = 'number', label = (lobbyPlayers[c].name or c) .. ' (%)',
                        default = def, min = 0, max = 100,
                    }
                end
                local input = lib.inputDialog('Dividir recompensa', fields)
                if input then
                    local split = {}
                    for i, c in ipairs(memberCids) do split[c] = tonumber(input[i]) or 0 end
                    TriggerServerEvent('vp_cityworks:setRewardSplit', split)
                end
            end,
        }
    end

    -- iniciar / resetar
    options[#options + 1] = {
        title = selectedRegion and 'INICIAR TRABALHO' or 'Selecione uma regiao',
        icon = 'play',
        disabled = not selectedRegion,
        onSelect = function() StartJobCheck() end,
    }

    lib.registerContext({ id = 'vp_cityworks_menu', title = 'Secretaria de Obras', options = options })
    lib.showContext('vp_cityworks_menu')
end

function StartJobCheck()
    if not selectedRegion then return end
    -- check client-side: zona de spawn livre (server revalida via spawn setter)
    TriggerServerEvent('vp_cityworks:startJob')
end

---------------------------------------------------------------------
-- EVENTOS DE LOBBY
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:refreshLobby', function(players, disciplineId, region)
    lobbyPlayers = players or {}
    currentDiscipline = disciplineId or currentDiscipline
    selectedRegion = region or false
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
