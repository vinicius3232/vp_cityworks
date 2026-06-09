-- client/mission.lua :: gameplay da missao (blips, markers, fumaca, alvos, entrega)

JobActive       = false
CurrentMission  = nil   -- { targets = {...}, progress = {...} }
MissionRegion   = nil
MissionVehicles = {}
ActiveDiscipline = nil  -- config da frente ativa (Config.Disciplines[id])

local missionBlips = {}
local smokeFx = {}      -- [targetId] = ptfxHandle
local deliveryBlip = nil
local vehicleBlips = {} -- blips que seguem os veiculos do job
local savedClothes = nil -- componentes originais p/ restaurar (cloakroom)
local buildProps = {}   -- props spawnados no modo build

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local function addBlip(coords, label, sprite, color)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 354)
    SetBlipColour(blip, color or 5)
    SetBlipScale(blip, 0.8)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or 'Reparo')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function startSmoke(targetId, coords)
    if smokeFx[targetId] then return end
    lib.requestNamedPtfxAsset('core')
    UseParticleFxAssetNextCall('core')
    local fx = StartParticleFxLoopedAtCoord('ent_dst_elec_fire_sp',
        coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
    smokeFx[targetId] = fx
end

local function stopSmoke(targetId)
    if smokeFx[targetId] then
        StopParticleFxLooped(smokeFx[targetId], 0)
        smokeFx[targetId] = nil
    end
end

--- Roupa de trabalho: salva os componentes atuais e aplica os da frente.
local function applyWorkClothes()
    if not Config.WorkClothes.enable or not ActiveDiscipline or not ActiveDiscipline.clothes then return end
    local ped = cache.ped
    local set = IsPedMale(ped) and ActiveDiscipline.clothes.male or ActiveDiscipline.clothes.female
    if not set or #set == 0 then return end
    savedClothes = {}
    for _, c in ipairs(set) do
        savedClothes[#savedClothes + 1] = {
            id = c.componentId,
            drawable = GetPedDrawableVariation(ped, c.componentId),
            texture = GetPedTextureVariation(ped, c.componentId),
        }
        SetPedComponentVariation(ped, c.componentId, c.drawable, c.texture, 0)
    end
end

--- MODO BUILD: spawna o prop construido no alvo (global p/ uso no handler).
function spawnBuildProp(target)
    local b = (ActiveDiscipline and ActiveDiscipline.build and ActiveDiscipline.build[target.type]) or {}
    if not b.prop then return end
    lib.requestModel(b.prop)
    local obj = CreateObject(b.prop, target.coords.x, target.coords.y, target.coords.z - (b.zOffset or 1.0),
        false, true, false)
    SetEntityHeading(obj, b.heading or 0.0)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(b.prop)
    buildProps[#buildProps + 1] = obj
end

--- Restaura os componentes salvos (fim/reset do job).
local function restoreClothes()
    if not savedClothes then return end
    local ped = cache.ped
    for _, c in ipairs(savedClothes) do
        SetPedComponentVariation(ped, c.id, c.drawable, c.texture, 0)
    end
    savedClothes = nil
end

--- Cria um blip por veiculo do job e o mantem seguindo o carro.
function StartVehicleBlips()
    for _, netId in ipairs(MissionVehicles) do
        local blip = AddBlipForCoord(0.0, 0.0, 0.0)
        SetBlipSprite(blip, 85)
        SetBlipColour(blip, 5)
        SetBlipScale(blip, 0.8)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Caminhao - ' .. ((ActiveDiscipline and ActiveDiscipline.label) or 'Obras'))
        EndTextCommandSetBlipName(blip)
        vehicleBlips[#vehicleBlips + 1] = { blip = blip, netId = netId }
    end
    CreateThread(function()
        while JobActive and #vehicleBlips > 0 do
            for _, vb in ipairs(vehicleBlips) do
                local veh = NetworkGetEntityFromNetworkId(vb.netId)
                if veh and veh ~= 0 and DoesEntityExist(veh) then
                    local c = GetEntityCoords(veh)
                    SetBlipCoords(vb.blip, c.x, c.y, c.z)
                end
            end
            Wait(1500)
        end
    end)
end

local function clearMission()
    JobActive = false
    for _, blip in pairs(missionBlips) do RemoveBlip(blip) end
    missionBlips = {}
    for _, vb in ipairs(vehicleBlips) do RemoveBlip(vb.blip) end
    vehicleBlips = {}
    for id in pairs(smokeFx) do stopSmoke(id) end
    if deliveryBlip then RemoveBlip(deliveryBlip); deliveryBlip = nil end
    for _, obj in ipairs(buildProps) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    buildProps = {}
    ClearEquipment() -- equipment.lua
    restoreClothes() -- cloakroom
    SendNUIMessage({ action = 'HUD_HIDE' })
    CurrentMission = nil
    MissionRegion = nil
    MissionVehicles = {}
    ActiveDiscipline = nil
end

---------------------------------------------------------------------
-- EVENTOS
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:jobStarted', function(data)
    JobActive = true
    CurrentMission = data.mission
    MissionRegion = data.region
    MissionVehicles = data.vehicles or {}
    ActiveDiscipline = Config.Disciplines[data.disciplineId] or Utils.discipline()

    for id, target in pairs(CurrentMission.targets) do
        missionBlips[id] = addBlip(target.coords, ActiveDiscipline.taskLabels[target.type] or target.type, 354, 5)
    end
    -- blip(s) seguindo o(s) veiculo(s) do job
    StartVehicleBlips()
    -- roupa de trabalho (cloakroom)
    applyWorkClothes()
    -- HUD ao vivo
    SendNUIMessage({ action = 'HUD_SHOW', tasks = data.progress, players = data.players })
    CityNotify(MissionRegion.title, 'inform')
end)

RegisterNetEvent('vp_cityworks:targetUpdated', function(targetId, fixed, progress)
    if not CurrentMission then return end
    local target = CurrentMission.targets[targetId]
    if not target then return end
    if fixed then
        target.fixed = true
        if missionBlips[targetId] then RemoveBlip(missionBlips[targetId]); missionBlips[targetId] = nil end
        stopSmoke(targetId)
        -- MODO BUILD: spawna o prop construido
        if target.mode == 'build' then spawnBuildProp(target) end
        if progress then
            CurrentMission.progress = progress
            SendNUIMessage({ action = 'HUD_TASKS', tasks = progress })
        end
    end
end)

RegisterNetEvent('vp_cityworks:refreshScore', function(players)
    SendNUIMessage({ action = 'HUD_PLAYERS', players = players })
end)

-- MODO DRILL: vida do alvo atualizada (feedback)
RegisterNetEvent('vp_cityworks:targetHit', function(targetId, health)
    if CurrentMission and CurrentMission.targets[targetId] then
        CurrentMission.targets[targetId].health = health
    end
end)

-- 2 papeis: tensao desligada por alguem da equipe
RegisterNetEvent('vp_cityworks:powerCut', function(targetId)
    if CurrentMission and CurrentMission.targets[targetId] then
        CurrentMission.targets[targetId].powerCut = true
    end
end)

RegisterNetEvent('vp_cityworks:jobComplete', function(deliveryCoords)
    CityNotify(locale('job_complete'), 'success')
    if deliveryBlip then RemoveBlip(deliveryBlip) end
    deliveryBlip = addBlip(deliveryCoords, locale('deliver_vehicle'), 1, 29)
    SetNewWaypoint(deliveryCoords.x, deliveryCoords.y)
    CurrentMission.deliveryCoords = deliveryCoords
    CurrentMission.finished = true
end)

RegisterNetEvent('vp_cityworks:jobReset', function()
    clearMission()
    CityNotify(locale('reset_job'), 'inform')
end)

---------------------------------------------------------------------
-- LOOP DE INTERACAO COM ALVOS
---------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        if JobActive and CurrentMission and not CurrentMission.finished
            and not (ActiveDiscipline and ActiveDiscipline.kind == 'towing') then
            local pc = GetEntityCoords(cache.ped)
            for id, target in pairs(CurrentMission.targets) do
                if not target.fixed then
                    local dist = #(pc - target.coords)
                    local radius = (ActiveDiscipline and ActiveDiscipline.targetRadius[target.type]) or 3.0
                    -- seta vermelha alta (visivel de longe)
                    if Config.RedArrowMarker and dist < 35.0 then
                        sleep = 0
                        DrawMarker(0, target.coords.x, target.coords.y, target.coords.z + 2.4,
                            0,0,0, 0,0,0, 1.2,1.2,1.2, 220,30,30,200, true,true,2,nil,nil,false)
                    end
                    -- semaforo defeituoso pisca (entidade cacheada + throttle 250ms)
                    if target.type == 'fixTrafficLamp' and dist < 30.0 then
                        sleep = 0
                        local now = GetGameTimer()
                        if (target._nextFlicker or 0) <= now then
                            target._nextFlicker = now + 250
                            if not target._light or not DoesEntityExist(target._light) then
                                local models = (ActiveDiscipline and ActiveDiscipline.trafficLightModels) or {}
                                for _, model in ipairs(models) do
                                    local l = GetClosestObjectOfType(target.coords.x, target.coords.y, target.coords.z, 8.0, model, false, false, false)
                                    if l ~= 0 then target._light = l break end
                                end
                            end
                            if target._light then SetEntityTrafficlightOverride(target._light, math.random(0, 2)) end
                        end
                    end
                    local mode = target.mode or 'minigame'
                    if dist < 20.0 then
                        sleep = 0
                        if mode == 'minigame' then startSmoke(id, target.coords) end
                        DrawMarker(2, target.coords.x, target.coords.y, target.coords.z + 1.0,
                            0,0,0, 0,0,0, 0.5,0.5,0.5, 0,255,0,180, false,false,2,nil,nil,false)
                        if dist < radius then
                            if mode == 'drill' then
                                -- alvo com vida: bater ate zerar
                                DrawText3D(target.coords, ('[E] %s (%s)'):format(locale('drill_prompt'), target.health or '?'))
                                if IsControlJustReleased(0, 38) then DrillTarget(target) end
                            elseif mode == 'build' then
                                DrawText3D(target.coords, ('[E] %s'):format(locale('build_prompt')))
                                if IsControlJustReleased(0, 38) then BuildTask(target) end
                            else
                                local req = ActiveDiscipline and ActiveDiscipline.requiresEquipment[target.type]
                                local needsPower = ActiveDiscipline and ActiveDiscipline.needsPower
                                    and ActiveDiscipline.needsPower[target.type] and not target.powerCut
                                if req and not target.equipped then
                                    HandleEquipmentPrompt(target, req)
                                elseif needsPower then
                                    DrawText3D(target.coords, locale('cut_power_prompt'))
                                    if IsControlJustReleased(0, 38) then CutPower(target) end
                                else
                                    local label = (ActiveDiscipline and ActiveDiscipline.taskLabels[target.type]) or target.type
                                    DrawText3D(target.coords, ('[E] %s'):format(label))
                                    if IsControlJustReleased(0, 38) then TryOpenTarget(target) end
                                end
                            end
                        end
                    else
                        stopSmoke(id)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

--- 2 papeis: desliga a tensao do alvo (progressbar) antes do reparo.
function CutPower(target)
    local time = (ActiveDiscipline and ActiveDiscipline.powerCutTime) or 4000
    local ok = lib.progressBar({
        duration = time,
        label = locale('cutting_power'),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_player' },
    })
    if ok then
        TriggerServerEvent('vp_cityworks:cutPower', target.id)
    end
end

function TryOpenTarget(target)
    local res = lib.callback.await('vp_cityworks:openTarget', false, { targetId = target.id })
    if not res then
        CityNotify(locale('target_busy'), 'error')
        return
    end
    if res.needEquipment then
        local key = res.needEquipment == 'ladder' and 'need_ladder' or 'need_lift'
        CityNotify(locale(key), 'error')
        return
    end
    if res.needPower then
        CityNotify(locale('need_power'), 'error')
        return
    end
    -- roda o minigame (minigames.lua) e envia resultado ao server
    StartMinigame(target.type, function(success)
        if not success then
            ApplyShockDamage() -- minigames.lua
        end
        TriggerServerEvent('vp_cityworks:completeTarget', target.id, success)
    end)
end

--- MODO DRILL: bate no alvo (progressbar). Servidor decrementa a vida.
function DrillTarget(target)
    local d = (ActiveDiscipline and ActiveDiscipline.drill and ActiveDiscipline.drill[target.type]) or {}
    SendNUIMessage({ action = 'SFX', sfx = 'drill', play = true })
    local ok = lib.progressBar({
        duration = d.hitTime or 1600,
        label = locale('drilling'),
        useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'melee@large_wpn@streamed_core', clip = 'ground_attack_on_spot' },
    })
    SendNUIMessage({ action = 'SFX', play = false })
    if ok then TriggerServerEvent('vp_cityworks:hitTarget', target.id) end
end

--- MODO BUILD: progressbar -> conclui (prop spawna via targetUpdated).
function BuildTask(target)
    local res = lib.callback.await('vp_cityworks:openTarget', false, { targetId = target.id })
    if not res or res.needEquipment or res.needPower then
        CityNotify(locale('target_busy'), 'error')
        return
    end
    local b = (ActiveDiscipline and ActiveDiscipline.build and ActiveDiscipline.build[target.type]) or {}

    -- minigame do Construtor (martelar pregos) antes de erguer o prop, se configurado
    if b.minigame then
        StartNamedMinigame(b.minigame, { nails = b.nails or 3, time = b.minigameTime or 22, maxFails = b.maxFails or 4 }, function(ok)
            if ok then
                TriggerServerEvent('vp_cityworks:completeTarget', target.id, true)
            else
                TriggerServerEvent('vp_cityworks:closeTarget', target.id)
            end
        end)
        return
    end

    SendNUIMessage({ action = 'SFX', sfx = 'build', play = true })
    local ok = lib.progressBar({
        duration = b.time or 6000,
        label = locale('building'),
        useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
    })
    SendNUIMessage({ action = 'SFX', play = false })
    if ok then
        TriggerServerEvent('vp_cityworks:completeTarget', target.id, true)
    else
        TriggerServerEvent('vp_cityworks:closeTarget', target.id)
    end
end

---------------------------------------------------------------------
-- ENTREGA DO VEICULO
---------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        if JobActive and CurrentMission and CurrentMission.finished and CurrentMission.deliveryCoords then
            local ped = cache.ped
            if IsPedInAnyVehicle(ped, false) then
                local dc = CurrentMission.deliveryCoords
                local dist = #(GetEntityCoords(ped) - dc)
                if dist < 25.0 then
                    sleep = 0
                    DrawMarker(2, dc.x, dc.y, dc.z + 1.0, 0,0,0, 0,0,0, 0.6,0.6,0.6, 255,255,0,180, false,false,2,nil,nil,false)
                    if dist < ((ActiveDiscipline and ActiveDiscipline.targetRadius.delivery) or 10.0) then
                        DrawText3D(dc, locale('deliver_vehicle'))
                        if IsControlJustReleased(0, 38) then
                            TriggerServerEvent('vp_cityworks:deliverVehicle')
                            Wait(2000)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------
-- DrawText3D util
---------------------------------------------------------------------
function DrawText3D(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z + 1.0, 0)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearMission() end
end)
