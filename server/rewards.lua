-- server/rewards.lua :: entrega do veiculo, pagamento, XP/level e persistencia

---------------------------------------------------------------------
-- ENTREGAR VEICULO -> paga recompensa
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:deliverVehicle', function()
    local src = source
    if not Security.canAct(src, 'deliverVehicle', Config.Cooldowns.deliverVehicle) then return end
    local lobby, cid = vpGetLobbyBySrc(src)
    if not lobby or not lobby.finished then
        return exports.qbx_core:Notify(src, locale('job_not_started'), 'error')
    end

    -- valida que ha um veiculo do job perto do ponto de entrega (server-side)
    local delivery = lobby.region.deliveryCoords
    local deliveryRadius = (Utils.discipline(lobby.disciplineId).targetRadius.delivery) or 10.0
    local anyNear = false
    for _, netId in ipairs(lobby.vehicles) do
        local veh = NetworkGetEntityFromNetworkId(netId)
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            if #(GetEntityCoords(veh) - delivery) <= deliveryRadius then
                anyNear = true
            end
        end
    end
    if not anyNear then
        Security.logSuspicious(src, 'deliverVehicle sem veiculo no ponto', nil)
        return
    end

    -- evita pagamento duplo
    if lobby.paid then return end
    lobby.paid = true

    local equalPay = math.ceil(lobby.rewardMoney / math.max(1, lobby.playerCount))
    local xp = lobby.rewardXp

    -- reembolsa o deposito ao DONO (se pagou)
    if lobby.depositPaid then
        local ownerPl = lobby.players[lobby.owner]
        if ownerPl then
            local op = exports.qbx_core:GetPlayer(ownerPl.src)
            if op then
                op.Functions.AddMoney(lobby.depositAccount or 'bank', lobby.deposit, 'vp_cityworks-deposit-refund')
                exports.qbx_core:Notify(ownerPl.src, locale('deposit_refunded', lobby.deposit), 'success')
            end
        end
        lobby.depositPaid = false
    end

    -- deleta veiculos
    for _, netId in ipairs(lobby.vehicles) do
        local veh = NetworkGetEntityFromNetworkId(netId)
        if veh and veh ~= 0 and DoesEntityExist(veh) then DeleteEntity(veh) end
    end

    -- paga cada player (boss split, se definido; senao divisao igual)
    for pcid, pl in pairs(lobby.players) do
        local pay = equalPay
        if lobby.split then
            pay = math.ceil(lobby.rewardMoney * (lobby.split[pcid] or 0) / 100)
        end
        local player = exports.qbx_core:GetPlayer(pl.src)
        if player then
            if pay > 0 then player.Functions.AddMoney('bank', pay, 'vp_cityworks-reward') end
            local prof = exports[GetCurrentResourceName()]:getProfile(pcid)
            local newLevel, newXp, leveledUp = Utils.applyXP(prof.level, prof.xp, xp, Config.RequiredXP, Config.MaxLevel)
            prof.level, prof.xp = newLevel, newXp
            DB.saveProfile(pcid, newXp, newLevel)
            exports.qbx_core:Notify(pl.src, locale('reward_received', pay, xp), 'success')
            if leveledUp then
                exports.qbx_core:Notify(pl.src, locale('level_up', newLevel), 'success')
            end
            TriggerClientEvent('vp_cityworks:rewardScreen', pl.src, {
                name = pl.name,
                money = pay,
                xp = xp,
                score = pl.score or 0,
            })
        end
    end

    sendRewardLog(lobby, lobby.rewardMoney)
    vpDestroyLobby(cid)
end)

---------------------------------------------------------------------
-- LOG (opcional - webhook por convar, sem token hardcoded)
---------------------------------------------------------------------
function sendRewardLog(lobby, totalPay)
    local url = GetConvar(Config.LogWebhookConvar, '')
    if url == '' then return end
    local names = {}
    for _, pl in pairs(lobby.players) do names[#names + 1] = pl.name end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = 'vp_cityworks',
        embeds = { {
            title = 'Job de Eletricista concluido',
            color = 5763719,
            fields = {
                { name = 'Regiao', value = lobby.region.title, inline = true },
                { name = 'Jogadores', value = table.concat(names, ', '), inline = false },
                { name = 'Pagamento total', value = ('$%s'):format(totalPay), inline = true },
            },
            footer = { text = os.date('%Y-%m-%d %H:%M:%S') },
        } },
    }), { ['Content-Type'] = 'application/json' })
end
