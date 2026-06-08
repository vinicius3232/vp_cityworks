-- server/dispatch.lua :: serviço sob demanda
-- Cidadao chama um servico -> equipes EM SERVICO daquela frente sao avisadas.

local function isDispatchable(disciplineId)
    for _, id in ipairs(Config.Dispatch.disciplines or {}) do
        if id == disciplineId then return true end
    end
    return false
end

RegisterNetEvent('vp_cityworks:requestService', function(disciplineId)
    local src = source
    if not Config.Dispatch.enable then return end
    if not Security.canAct(src, 'requestService', 5000) then return end
    if type(disciplineId) ~= 'string' or not isDispatchable(disciplineId) then return end
    local disc = Config.Disciplines[disciplineId]
    if not disc then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local acc = Config.Dispatch.account
    if (player.PlayerData.money[acc] or 0) < Config.Dispatch.fee then
        return exports.qbx_core:Notify(src, locale('dispatch_no_money'), 'error')
    end

    local coords = GetEntityCoords(GetPlayerPed(src))
    local requester = vpPlayerName(src)

    -- avisa todas as equipes em servico daquela frente
    local sent = 0
    for _, lobby in pairs(Lobbies) do
        if lobby.started and lobby.disciplineId == disciplineId then
            for _, pl in pairs(lobby.players) do
                if pl.src ~= src then
                    TriggerClientEvent('vp_cityworks:serviceCall', pl.src, {
                        coords = coords, label = disc.label, requester = requester,
                    })
                    sent = sent + 1
                end
            end
        end
    end

    if sent == 0 then
        return exports.qbx_core:Notify(src, locale('dispatch_no_workers'), 'error')
    end

    player.Functions.RemoveMoney(acc, Config.Dispatch.fee, 'vp_cityworks-dispatch')
    exports.qbx_core:Notify(src, locale('dispatch_sent'), 'success')
end)
