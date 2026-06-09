-- client/towing.lua :: motor de reboque (frente kind='towing')
-- Carregar o veiculo quebrado no flatbed -> levar a um ponto -> entregar.
-- Usa globals de mission.lua: JobActive, CurrentMission, ActiveDiscipline,
-- MissionVehicles, DrawText3D.

local attached = {} -- targetId -> true (anexado localmente)

local function getFlatbedNear(coords, dist)
    for _, netId in ipairs(MissionVehicles or {}) do
        local fv = NetToVeh(netId)
        if fv and fv ~= 0 and DoesEntityExist(fv) and #(GetEntityCoords(fv) - coords) <= dist then
            return fv
        end
    end
end

-- pede controle de rede da entidade antes de mexer (evita dessync)
local function ensureControl(ent)
    if NetworkHasControlOfEntity(ent) then return true end
    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(ent), true)
    local t = 0
    while not NetworkHasControlOfEntity(ent) and t < 30 do
        NetworkRequestControlOfEntity(ent)
        Wait(15); t = t + 1
    end
    return NetworkHasControlOfEntity(ent)
end

-- offset do veiculo no flatbed: por-modelo > dinamico (GetModelDimensions) > padrao
local function flatbedOffset(disc, broken)
    local model = GetEntityModel(broken)
    local pos = disc.vehiclePositions and disc.vehiclePositions[model]
    if pos then return pos.x, pos.y, pos.z end
    local def = disc.attachOffset or { x = 0.0, y = -2.6, z = 1.0 }
    -- Z dinamico: assenta as rodas no leito usando a altura do modelo
    local minDim = GetModelDimensions(model)
    local z = def.z + (minDim and -minDim.z or 0.0)
    return def.x, def.y, z
end

-- veiculo carregado: SO o loader anexa (dono da entidade); OneSync replica
RegisterNetEvent('vp_cityworks:towLoaded', function(targetId, vehNet, flatbedNet, loaderId)
    if CurrentMission and CurrentMission.targets[targetId] then
        CurrentMission.targets[targetId].loaded = true
    end
    attached[targetId] = true
    SendNUIMessage({ action = 'SFX', sfx = 'winch', play = true })
    SetTimeout(2000, function() SendNUIMessage({ action = 'SFX', play = false }) end)

    if loaderId ~= cache.serverId then return end -- so quem carregou anexa
    local disc = ActiveDiscipline
    if not disc then return end
    local broken = NetToVeh(vehNet)
    local flatbed = NetToVeh(flatbedNet)
    if not broken or broken == 0 or not DoesEntityExist(broken) then return end
    if not flatbed or flatbed == 0 or not DoesEntityExist(flatbed) then return end
    if not ensureControl(broken) then return end

    local bone = GetEntityBoneIndexByName(flatbed, 'bodyshell')
    if bone == -1 then bone = 0 end
    local ox, oy, oz = flatbedOffset(disc, broken)
    SetVehicleEngineOn(broken, false, true, true)
    FreezeEntityPosition(broken, false)
    AttachEntityToEntity(broken, flatbed, bone, ox, oy, oz, 0.0, 0.0, 0.0,
        false, false, false, false, 2, true)
    SetEntityCollision(broken, false, true) -- nao briga com a fisica do flatbed
end)

-- entregue: o veiculo ja foi removido no server; só limpamos o estado local
RegisterNetEvent('vp_cityworks:towDelivered', function(targetId)
    attached[targetId] = nil
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if JobActive and CurrentMission and not CurrentMission.finished
            and ActiveDiscipline and ActiveDiscipline.kind == 'towing' then
            local disc = ActiveDiscipline
            local pc = GetEntityCoords(cache.ped)
            local loadDist = disc.loadDistance or 8.0
            for id, target in pairs(CurrentMission.targets) do
                if not target.fixed then
                    if not target.loaded then
                        -- carregar o veiculo quebrado
                        if target.vehicleNetId then
                            local bveh = NetToVeh(target.vehicleNetId)
                            if bveh and bveh ~= 0 and DoesEntityExist(bveh) then
                                local bcoords = GetEntityCoords(bveh)
                                if #(pc - bcoords) < loadDist then
                                    sleep = 0
                                    if getFlatbedNear(bcoords, loadDist + 4.0) then
                                        DrawText3D(bcoords, '[E] ' .. locale('tow_load_prompt'))
                                        if IsControlJustReleased(0, 38) then
                                            TriggerServerEvent('vp_cityworks:loadVehicle', id)
                                        end
                                    else
                                        DrawText3D(bcoords, locale('tow_need_flatbed'))
                                    end
                                end
                            end
                        end
                    else
                        -- entregar num ponto
                        for _, p in ipairs(disc.deliveryPoints or {}) do
                            local d = #(pc - p)
                            if d < 30.0 then
                                sleep = 0
                                DrawMarker(1, p.x, p.y, p.z - 1.0, 0,0,0, 0,0,0, 3.0,3.0,1.5,
                                    0,200,255,120, false,false,2,nil,nil,false)
                                if d < (disc.targetRadius.delivery or 12.0) then
                                    DrawText3D(p, '[E] ' .. locale('tow_deliver_prompt'))
                                    if IsControlJustReleased(0, 38) then
                                        TriggerServerEvent('vp_cityworks:deliverTow', id)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
