-- server/towing.lua :: motor de reboque (frente kind='towing')
-- Reimplementado do zero, inspirado no 0r-towtruck (open source).
-- Fluxo: carregar o veiculo quebrado no flatbed -> entregar num ponto -> pagar.

local function nearAnyDelivery(coords, disc, radius)
    for _, p in ipairs(disc.deliveryPoints or {}) do
        if #(coords - p) <= radius then return true end
    end
    return false
end

-- carregar o veiculo quebrado no flatbed
RegisterNetEvent('vp_cityworks:loadVehicle', function(targetId)
    local src = source
    if type(targetId) ~= 'number' then return end
    if not Security.canAct(src, 'loadVehicle', 1000) then return end
    local lobby, cid = vpGetLobbyBySrc(src)
    if not lobby or not lobby.started or not lobby.mission then return end
    local target = lobby.mission.targets[targetId]
    if not target or target.fixed or target.mode ~= 'tow' or target.loaded then return end
    local disc = Utils.discipline(lobby.disciplineId)
    local loadDist = disc.loadDistance or 8.0

    if not target.vehicleNetId then return end
    local bveh = NetworkGetEntityFromNetworkId(target.vehicleNetId)
    if not bveh or bveh == 0 or not DoesEntityExist(bveh) then return end
    if not Security.isNear(src, GetEntityCoords(bveh), loadDist) then
        Security.logSuspicious(src, 'loadVehicle fora de alcance', { targetId = targetId })
        return
    end

    -- precisa de um flatbed do job perto do veiculo quebrado
    local flatbedNet
    local bcoords = GetEntityCoords(bveh)
    for _, netId in ipairs(lobby.vehicles) do
        local fv = NetworkGetEntityFromNetworkId(netId)
        if fv and fv ~= 0 and DoesEntityExist(fv) and #(GetEntityCoords(fv) - bcoords) <= loadDist + 4.0 then
            flatbedNet = netId
            break
        end
    end
    if not flatbedNet then
        return Framework.Notify(src, locale('tow_need_flatbed'), 'error')
    end

    target.loaded = true
    target.flatbedNetId = flatbedNet
    vpBroadcast(lobby, 'vp_cityworks:towLoaded', target.id, target.vehicleNetId, flatbedNet)
end)

-- entregar o veiculo rebocado num ponto de entrega
RegisterNetEvent('vp_cityworks:deliverTow', function(targetId)
    local src = source
    if type(targetId) ~= 'number' then return end
    if not Security.canAct(src, 'deliverTow', 1000) then return end
    local lobby, cid = vpGetLobbyBySrc(src)
    if not lobby or not lobby.started or not lobby.mission then return end
    local target = lobby.mission.targets[targetId]
    if not target or target.fixed or target.mode ~= 'tow' or not target.loaded then return end
    local disc = Utils.discipline(lobby.disciplineId)

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    if not nearAnyDelivery(GetEntityCoords(ped), disc, (disc.targetRadius.delivery) or 12.0) then
        return Framework.Notify(src, locale('tow_go_delivery'), 'error')
    end

    -- remove o veiculo rebocado
    if target.vehicleNetId then
        local bveh = NetworkGetEntityFromNetworkId(target.vehicleNetId)
        if bveh and bveh ~= 0 and DoesEntityExist(bveh) then DeleteEntity(bveh) end
        target.vehicleNetId = nil
    end

    vpBroadcast(lobby, 'vp_cityworks:towDelivered', target.id)
    vpCompleteTarget(lobby, target, cid, src) -- progresso/score/recompensa/fim
end)
