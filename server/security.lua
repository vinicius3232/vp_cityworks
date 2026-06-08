-- server/security.lua :: validacao de fonte, rate limit, proximity, log
-- SEMPRE incluido (padrao do servidor). Toda entrada de rede passa por aqui.
Security = {}

local cooldowns = {} -- [src][action] = lastTimeMs

--- Fonte valida = jogador realmente conectado e com Player object.
--- @param src number
--- @return table|nil player (qbx player), string|nil citizenid
function Security.getPlayer(src)
    if type(src) ~= 'number' or src <= 0 then return end
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    return player, player.PlayerData.citizenid
end

--- Rate limit por acao. Retorna true se PODE agir (e marca o tempo).
--- @param src number
--- @param action string
--- @param ms number intervalo minimo
function Security.canAct(src, action, ms)
    local now = GetGameTimer()
    cooldowns[src] = cooldowns[src] or {}
    local last = cooldowns[src][action]
    if last and (now - last) < ms then
        return false
    end
    cooldowns[src][action] = now
    return true
end

--- Proximity check SERVER-SIDE (regra nº5). Nunca confiar so no client.
--- @param src number
--- @param coords vector3
--- @param maxDist number
function Security.isNear(src, coords, maxDist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pc = GetEntityCoords(ped)
    return #(pc - coords) <= (maxDist + 1.0) -- +1m de folga p/ latencia
end

--- Log de atividade suspeita (webhook OPCIONAL via convar, sem token hardcoded).
function Security.logSuspicious(src, reason, extra)
    local citizenid
    local player = exports.qbx_core:GetPlayer(src)
    if player then citizenid = player.PlayerData.citizenid end
    print(('[vp_cityworks][SUSPEITO] src=%s cid=%s motivo=%s extra=%s')
        :format(src, citizenid or '?', reason, extra and json.encode(extra) or ''))

    local url = GetConvar(Config.LogWebhookConvar, '')
    if url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = 'vp_cityworks',
        embeds = { {
            title = 'Atividade suspeita',
            color = 15158332,
            fields = {
                { name = 'Source', value = tostring(src), inline = true },
                { name = 'CitizenID', value = tostring(citizenid or '?'), inline = true },
                { name = 'Motivo', value = reason, inline = false },
            },
            footer = { text = os.date('%Y-%m-%d %H:%M:%S') },
        } },
    }), { ['Content-Type'] = 'application/json' })
end

-- limpeza de cooldowns ao sair
AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
end)
