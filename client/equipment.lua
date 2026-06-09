-- client/equipment.lua :: escada (estatica) e LIFT MOVEL (elevador)
-- LIFT: plataforma CONGELADA movida por SlideObject; o jogador sobe junto
-- POR COLISAO (sem teleportar o ped).
-- Controle: setas cima/baixo enquanto estiver sobre a plataforma. Sincronizado.

local spawnedEquipment = {} -- [targetId] = { kind, props={}, platform, lift={...}, sliding }
local building = false
local LIFT_SPEED = 0.05            -- velocidade do SlideObject
local CTRL_UP, CTRL_DOWN = 172, 173 -- setas cima/baixo

local function spawnProp(model, coords, heading, collision)
    if not IsModelInCdimage(model) then return end
    lib.requestModel(model)
    local obj = CreateObject(model, coords.x, coords.y, coords.z, false, true, false)
    SetEntityHeading(obj, heading or 0.0)
    if collision then SetEntityCollision(obj, true, true) end
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)
    return obj
end

local function groundZ(x, y, fallback)
    local found, z = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, (fallback or 0.0) + 0.0, false)
    if found then return z end
    return fallback or 0.0
end

--- Prompt para construir equipamento (chamado pelo loop de mission.lua)
function HandleEquipmentPrompt(target, kind)
    if spawnedEquipment[target.id] then return end
    local key = kind == 'ladder' and 'build_ladder' or 'build_lift'
    DrawText3D(target.coords, locale(key))
    if IsControlJustReleased(0, 38) and not building then -- E
        building = true
        local dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@'
        lib.requestAnimDict(dict)
        TaskPlayAnim(cache.ped, dict, 'machinic_loop_mechandplayer', 8.0, 1.0, 2500, 1, 0, false, false, false)
        Wait(2500)
        ClearPedTasks(cache.ped)
        TriggerServerEvent('vp_cityworks:buildEquipment', target.id, kind)
        building = false
    end
end

---------------------------------------------------------------------
-- CONSTRUCAO SINCRONIZADA
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:equipmentBuilt', function(targetId, kind, coords)
    if spawnedEquipment[targetId] then return end
    if kind == 'ladder' then
        local props = {}
        props[#props + 1] = spawnProp(Config.Equipment.ladder.model,
            vec3(coords.x, coords.y, coords.z - 6.0), 0.0)
        local limit = spawnProp(Config.Equipment.ladder.limit,
            vec3(coords.x, coords.y + 0.5, coords.z + 4.0), 0.0)
        if limit then SetEntityAlpha(limit, 0); props[#props + 1] = limit end
        spawnedEquipment[targetId] = { kind = 'ladder', props = props }
    elseif kind == 'lift' then
        local base = groundZ(coords.x, coords.y, coords.z - 8.0)
        local minH = base                  -- plataforma no chao (player sobe nela)
        local maxH = (coords.z - 1.0)       -- topo: junto ao poste
        if maxH < minH + 2.0 then maxH = minH + 2.0 end
        -- trilhos (visual)
        local rails, h = {}, base
        while h < maxH do
            local r = spawnProp(Config.Equipment.lift.rail, vec3(coords.x, coords.y, h), 0.0)
            if r then rails[#rails + 1] = r end
            h = h + 5.0
        end
        -- plataforma congelada COM colisao (o player fica em pe nela)
        local platform = spawnProp(Config.Equipment.lift.model, vec3(coords.x, coords.y, minH), 0.0, true)
        spawnedEquipment[targetId] = {
            kind = 'lift', props = rails, platform = platform,
            lift = { x = coords.x, y = coords.y, min = minH, max = maxH, moving = false, dir = nil },
            sliding = false,
        }
    end

    if CurrentMission and CurrentMission.targets[targetId] then
        CurrentMission.targets[targetId].equipped = true
    end
end)

RegisterNetEvent('vp_cityworks:equipmentRemoved', function(targetId)
    DestroyEquipment(targetId)
    if CurrentMission and CurrentMission.targets[targetId] then
        CurrentMission.targets[targetId].equipped = false
    end
end)

-- estado de movimento do lift sincronizado (vem do servidor p/ TODOS, inclusive quem mandou)
RegisterNetEvent('vp_cityworks:liftMove', function(targetId, dir, toggle)
    local eq = spawnedEquipment[targetId]
    if not eq or eq.kind ~= 'lift' then return end
    eq.lift.moving = toggle
    eq.lift.dir = toggle and dir or nil
    StartLiftSlide(eq)
end)

--- Thread que desliza a plataforma enquanto moving==true (SlideObject + colisao).
function StartLiftSlide(eq)
    if eq.sliding then return end
    eq.sliding = true
    CreateThread(function()
        while eq.lift.moving and eq.platform and DoesEntityExist(eq.platform) do
            local targetZ = eq.lift.dir == 'up' and eq.lift.max or eq.lift.min
            SlideObject(eq.platform, eq.lift.x, eq.lift.y, targetZ,
                LIFT_SPEED, LIFT_SPEED, LIFT_SPEED, true)
            Wait(0)
        end
        eq.sliding = false
    end)
end

function DestroyEquipment(targetId)
    local eq = spawnedEquipment[targetId]
    if not eq then return end
    if eq.pedAttached then DetachEntity(cache.ped, true, true); eq.pedAttached = false end
    if eq.lift then eq.lift.moving = false end
    for _, obj in ipairs(eq.props) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    if eq.platform and DoesEntityExist(eq.platform) then DeleteEntity(eq.platform) end
    spawnedEquipment[targetId] = nil
end

function ClearEquipment()
    for id in pairs(spawnedEquipment) do DestroyEquipment(id) end
    spawnedEquipment = {}
end

---------------------------------------------------------------------
-- CONTROLE DO LIFT (setas) + REMOCAO (G)
---------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        if JobActive and next(spawnedEquipment) then
            local pc = GetEntityCoords(cache.ped)
            for id, eq in pairs(spawnedEquipment) do
                local target = CurrentMission and CurrentMission.targets[id]
                if target and not target.fixed then
                    if eq.kind == 'lift' and eq.platform and DoesEntityExist(eq.platform) then
                        -- so processa (e poll de teclas a 0ms) quando perto do lift
                        if #(pc - vec3(eq.lift.x, eq.lift.y, pc.z)) < 25.0 then
                            sleep = 0
                            ControlLift(id, eq, pc)
                        end
                    elseif #(pc - target.coords) < 4.0 then
                        sleep = 0
                        DrawText3D(target.coords, locale('remove_equipment'))
                        if IsControlJustReleased(0, 47) then -- G
                            TriggerServerEvent('vp_cityworks:removeEquipment', id)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

--- Player em pe na plataforma controla a altura com as setas.
--- NAO teleporta o ped: ele sobe por colisao (igual ao script base).
local function detachRider(eq)
    if eq.pedAttached then
        DetachEntity(cache.ped, true, true)
        eq.pedAttached = false
    end
end

function ControlLift(id, eq, pc)
    local platCoords = GetEntityCoords(eq.platform)
    local distXY = #(vec2(pc.x, pc.y) - vec2(platCoords.x, platCoords.y))
    local onPlatform = eq.pedAttached or (distXY < 1.8 and (pc.z - platCoords.z) > -0.5 and (pc.z - platCoords.z) < 2.5)
    local distGround = #(pc - vec3(eq.lift.x, eq.lift.y, pc.z))

    if onPlatform or distGround < 3.0 then
        DrawText3D(vec3(eq.lift.x, eq.lift.y, platCoords.z + 1.2), '↑/↓ controlar  •  [G] remover')
    end

    -- remover perto da base
    if distGround < 3.5 and IsControlJustReleased(0, 47) then -- G
        detachRider(eq)
        eq.lift.moving = false
        TriggerServerEvent('vp_cityworks:removeEquipment', id)
        return
    end

    if not onPlatform then return end

    -- ANTI-QUEDA/DESSYNC: anexa o ped a plataforma enquanto ela se move
    -- (sobe junto perfeitamente) e solta quando parar (pode andar/reparar).
    local up, down = IsControlPressed(0, CTRL_UP), IsControlPressed(0, CTRL_DOWN)
    if (up or down) and not eq.pedAttached then
        AttachEntityToEntity(cache.ped, eq.platform, 0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
            false, false, false, false, 2, true)
        eq.pedAttached = true
    elseif not up and not down and eq.pedAttached then
        detachRider(eq)
    end

    if IsControlJustPressed(0, CTRL_UP) then
        TriggerServerEvent('vp_cityworks:moveLift', id, 'up', true)
    elseif IsControlJustReleased(0, CTRL_UP) then
        TriggerServerEvent('vp_cityworks:moveLift', id, 'up', false)
    end
    if IsControlJustPressed(0, CTRL_DOWN) then
        TriggerServerEvent('vp_cityworks:moveLift', id, 'down', true)
    elseif IsControlJustReleased(0, CTRL_DOWN) then
        TriggerServerEvent('vp_cityworks:moveLift', id, 'down', false)
    end
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then ClearEquipment() end
end)
