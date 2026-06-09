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

-- veiculo carregado: anexa o quebrado ao flatbed
RegisterNetEvent('vp_cityworks:towLoaded', function(targetId, vehNet, flatbedNet)
    local disc = ActiveDiscipline
    if not disc then return end
    local broken = NetToVeh(vehNet)
    local flatbed = NetToVeh(flatbedNet)
    if not broken or broken == 0 or not DoesEntityExist(broken) then return end
    if not flatbed or flatbed == 0 or not DoesEntityExist(flatbed) then return end
    local o = disc.attachOffset or { x = 0.0, y = -2.6, z = 1.0 }
    local bone = GetEntityBoneIndexByName(flatbed, 'bodyshell')
    if bone == -1 then bone = 0 end
    AttachEntityToEntity(broken, flatbed, bone, o.x, o.y, o.z, 0.0, 0.0, 0.0,
        false, false, false, false, 2, true)
    if CurrentMission and CurrentMission.targets[targetId] then
        CurrentMission.targets[targetId].loaded = true
    end
    attached[targetId] = true
    -- som do guincho por ~2s
    SendNUIMessage({ action = 'SFX', sfx = 'winch', play = true })
    SetTimeout(2000, function() SendNUIMessage({ action = 'SFX', play = false }) end)
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
