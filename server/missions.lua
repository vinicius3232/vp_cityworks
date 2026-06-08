-- server/missions.lua :: validacao de conserto de alvos + equipamento sincronizado

---------------------------------------------------------------------
-- COMPLETAR UM ALVO
-- O client roda o minigame e ENVIA o resultado, mas o servidor revalida
-- tudo (lobby, alvo aberto por este player, proximity, cooldown) e e quem
-- decide se a missao acabou e libera a recompensa.
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:completeTarget', function(targetId, success)
    local src = source
    if type(targetId) ~= 'number' then return end
    if not Security.canAct(src, 'completeTarget', Config.Cooldowns.completeTarget) then return end
    local lobby, cid = vpGetLobbyBySrc(src)
    if not lobby or not lobby.started or not lobby.mission then return end

    local target = lobby.mission.targets[targetId]
    if not target or target.fixed then return end
    if target.openBy ~= cid then
        Security.logSuspicious(src, 'completeTarget de alvo nao aberto por ele', { targetId = targetId })
        return
    end
    local disc = Utils.discipline(lobby.disciplineId)
    if not Security.isNear(src, target.coords, (disc.targetRadius[target.type]) or 3.0) then
        Security.logSuspicious(src, 'completeTarget fora de alcance', { targetId = targetId })
        target.openBy = nil
        return
    end

    -- anti-exploit: rejeita conclusao rapida demais (bot pulando o minigame)
    local minMs = (Config.Minigames.minSeconds or 1.5) * 1000
    if not target.openAt or (GetGameTimer() - target.openAt) < minMs then
        Security.logSuspicious(src, 'completeTarget rapido demais (minigame pulado?)', { targetId = targetId })
        target.openBy = nil
        target.openAt = nil
        return
    end

    target.openBy = nil
    target.openAt = nil

    if not success then
        -- falhou: libera o alvo (dano e aplicado no client)
        vpBroadcast(lobby, 'vp_cityworks:targetUpdated', target.id, false, false)
        return
    end

    target.fixed = true
    lobby.mission.remaining = lobby.mission.remaining - 1

    local prog = lobby.mission.progress[target.type]
    if prog then prog.made = prog.made + 1 end

    -- credita score do jogador (para o scoreboard)
    lobby.players[cid].score = (lobby.players[cid].score or 0) + 1

    -- itens de recompensa por reparo (chance %) -> vao para quem consertou
    for _, ri in ipairs(Config.RewardItems) do
        if ri.item and math.random(100) <= (ri.chance or 0) then
            exports.ox_inventory:AddItem(src, ri.item, ri.amount or 1)
        end
    end

    vpBroadcast(lobby, 'vp_cityworks:targetUpdated', target.id, true, lobby.mission.progress)
    vpBroadcast(lobby, 'vp_cityworks:refreshScore', lobby.players)

    if lobby.mission.remaining <= 0 then
        lobby.finished = true
        vpBroadcast(lobby, 'vp_cityworks:jobComplete', lobby.region.deliveryCoords)
    end
end)

-- Liberar alvo sem concluir (jogador fechou/cancelou)
RegisterNetEvent('vp_cityworks:closeTarget', function(targetId)
    local src = source
    if type(targetId) ~= 'number' then return end
    local lobby, cid = vpGetLobbyBySrc(src)
    if not lobby or not lobby.mission then return end
    local target = lobby.mission.targets[targetId]
    if target and target.openBy == cid then
        target.openBy = nil
    end
end)

---------------------------------------------------------------------
-- EQUIPAMENTO (escada / lift) - props sincronizados
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:buildEquipment', function(targetId, kind)
    local src = source
    if type(targetId) ~= 'number' or type(kind) ~= 'string' then return end
    if not Security.canAct(src, 'build', Config.Cooldowns.build) then return end
    local lobby, cid = vpGetLobbyBySrc(src)
    if not lobby or not lobby.started or not lobby.mission then return end
    local target = lobby.mission.targets[targetId]
    if not target or target.fixed then return end
    if Utils.discipline(lobby.disciplineId).requiresEquipment[target.type] ~= kind then return end
    if not Security.isNear(src, target.coords, Config.Equipment.buildDistance) then
        Security.logSuspicious(src, 'buildEquipment fora de alcance', { targetId = targetId, kind = kind })
        return
    end
    target.equipped = true
    target.equipment = kind
    vpBroadcast(lobby, 'vp_cityworks:equipmentBuilt', target.id, kind, target.coords)
end)

RegisterNetEvent('vp_cityworks:removeEquipment', function(targetId)
    local src = source
    if type(targetId) ~= 'number' then return end
    if not Security.canAct(src, 'removeEquipment', Config.Cooldowns.removeEquipment) then return end
    local lobby, cid = vpGetLobbyBySrc(src)
    if not lobby or not lobby.mission then return end
    local target = lobby.mission.targets[targetId]
    if not target then return end
    target.equipped = (Utils.discipline(lobby.disciplineId).requiresEquipment[target.type] == nil)
    target.equipment = nil
    vpBroadcast(lobby, 'vp_cityworks:equipmentRemoved', target.id)
end)

-- movimento do lift: estado (dir/toggle) repassado a TODOS do lobby (inclusive
-- quem enviou), que rodam o mesmo SlideObject localmente — igual ao script base.
RegisterNetEvent('vp_cityworks:moveLift', function(targetId, dir, toggle)
    local src = source
    if type(targetId) ~= 'number' then return end
    if dir ~= 'up' and dir ~= 'down' then return end
    if type(toggle) ~= 'boolean' then return end
    local lobby, cid = vpGetLobbyBySrc(src)
    if not lobby or not lobby.mission then return end
    local target = lobby.mission.targets[targetId]
    if not target or target.equipment ~= 'lift' then return end
    vpBroadcast(lobby, 'vp_cityworks:liftMove', targetId, dir, toggle)
end)
