-- server/main.lua :: lobby coop, perfis, start/finish, veiculo
-- Modelo: o servidor e a unica fonte de verdade. Nunca confiamos em
-- owneridentifier/coords vindos do client; derivamos o lobby do proprio src.

Profiles = {}        -- [citizenid] = { xp, level }
Lobbies  = {}        -- [ownerCid]  = { ...estado... }
PlayerLobby = {}     -- [citizenid] = ownerCid  (lookup reverso)
PendingInvites = {}  -- [targetCid] = ownerCid

---------------------------------------------------------------------
-- PERFIL
---------------------------------------------------------------------
local function getProfile(citizenid)
    if not Profiles[citizenid] then
        Profiles[citizenid] = DB.loadProfile(citizenid)
    end
    return Profiles[citizenid]
end
exports('getProfile', getProfile) -- usado por rewards.lua

local function playerName(src)
    return Framework.GetFullName(src) or 'Unknown'
end
_G.vpPlayerName = playerName

---------------------------------------------------------------------
-- HELPERS DE LOBBY
---------------------------------------------------------------------
local function getLobbyBySrc(src)
    local player, cid = Security.getPlayer(src)
    if not cid then return end
    local ownerCid = PlayerLobby[cid]
    if not ownerCid then return end
    return Lobbies[ownerCid], cid
end
_G.vpGetLobbyBySrc = getLobbyBySrc

local function broadcast(lobby, event, ...)
    for cid, pl in pairs(lobby.players) do
        TriggerClientEvent(event, pl.src, ...)
    end
end
_G.vpBroadcast = broadcast

local function createLobby(src, cid)
    local prof = getProfile(cid)
    Lobbies[cid] = {
        owner = cid,
        ownerSrc = src,
        players = { [cid] = { src = src, name = playerName(src), level = prof.level } },
        started = false,
        finished = false,
        disciplineId = Config.DisciplineOrder[1], -- frente ativa (default = 1a)
        region = false,
        mission = nil,
        vehicles = {}, -- netIds
    }
    PlayerLobby[cid] = cid
    return Lobbies[cid]
end

local function destroyLobby(ownerCid)
    local lobby = Lobbies[ownerCid]
    if not lobby then return end
    for _, netId in ipairs(lobby.vehicles) do
        local veh = NetworkGetEntityFromNetworkId(netId)
        if veh and veh ~= 0 and DoesEntityExist(veh) then DeleteEntity(veh) end
    end
    -- guincho: limpa veiculos quebrados ainda spawnados
    if lobby.mission and lobby.mission.targets then
        for _, t in pairs(lobby.mission.targets) do
            if t.vehicleNetId then
                local bveh = NetworkGetEntityFromNetworkId(t.vehicleNetId)
                if bveh and bveh ~= 0 and DoesEntityExist(bveh) then DeleteEntity(bveh) end
            end
        end
    end
    for cid in pairs(lobby.players) do
        PlayerLobby[cid] = nil
    end
    Lobbies[ownerCid] = nil
end
_G.vpDestroyLobby = destroyLobby

---------------------------------------------------------------------
-- CALLBACKS (ox_lib)
---------------------------------------------------------------------
lib.callback.register('vp_cityworks:getProfile', function(src)
    local player, cid = Security.getPlayer(src)
    if not cid then return end
    local prof = getProfile(cid)
    prof.source = src
    -- se ja e dono ou convidado de algum lobby, usa esse; senao cria um proprio
    local existingOwner = PlayerLobby[cid]
    local lobby = (existingOwner and Lobbies[existingOwner]) or createLobby(src, cid)
    return {
        name = playerName(src),
        money = Framework.GetMoney(src, 'bank'),
        level = prof.level,
        xp = prof.xp,
        nextXp = Config.RequiredXP[prof.level] or 0,
        players = lobby.players,
        disciplineId = lobby.disciplineId,
        region = lobby.region,
        isOwner = (lobby.owner == cid),
        ownerCid = lobby.owner,
        maxPlayers = Config.MaxPlayersPerLobby,
    }
end)

-- trava de concorrencia + proximity ao abrir um alvo
lib.callback.register('vp_cityworks:openTarget', function(src, data)
    if type(data) ~= 'table' then return false end
    local lobby, cid = getLobbyBySrc(src)
    if not lobby or not lobby.started or not lobby.mission then return false end
    local disc = Utils.discipline(lobby.disciplineId)
    local target = lobby.mission.targets[data.targetId]
    if not target or target.fixed then return false end
    if not Security.isNear(src, target.coords, (disc.targetRadius[target.type]) or 3.0) then
        Security.logSuspicious(src, 'openTarget fora de alcance', data)
        return false
    end
    if target.openBy and target.openBy ~= cid then return false end -- ocupado por outro
    -- exige equipamento?
    local req = disc.requiresEquipment[target.type]
    if req and not target.equipped then return { needEquipment = req } end
    -- exige tensao desligada (2 papeis)?
    if disc.needsPower and disc.needsPower[target.type] and not target.powerCut then
        return { needPower = true }
    end
    target.openBy = cid
    target.openAt = GetGameTimer() -- anti-exploit: marca quando abriu
    return { ok = true, type = target.type }
end)

---------------------------------------------------------------------
-- CONVITES
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:invite', function(targetId)
    local src = source
    if not Security.canAct(src, 'invite', Config.Cooldowns.invite) then return end
    targetId = tonumber(targetId)
    if not targetId then return end
    local lobby, cid = getLobbyBySrc(src)
    if not lobby or lobby.owner ~= cid then return end -- so o dono convida
    if lobby.started then return end
    local tPlayer, tCid = Security.getPlayer(targetId)
    if not tCid or tCid == cid then return end
    if lobby.players[tCid] then
        return Framework.Notify(src, locale('already_in_lobby'), 'error')
    end
    -- conta jogadores
    local count = 0; for _ in pairs(lobby.players) do count = count + 1 end
    if count >= Config.MaxPlayersPerLobby then
        return Framework.Notify(src, locale('lobby_full'), 'error')
    end
    -- proximity server-side
    if not Security.isNear(src, GetEntityCoords(GetPlayerPed(targetId)), Config.InviteMaxDistance) then
        return Framework.Notify(src, locale('player_far'), 'error')
    end
    PendingInvites[tCid] = cid
    TriggerClientEvent('vp_cityworks:receiveInvite', targetId, playerName(src), cid)
end)

RegisterNetEvent('vp_cityworks:acceptInvite', function()
    local src = source
    if not Security.canAct(src, 'acceptInvite', Config.Cooldowns.acceptInvite) then return end
    local player, cid = Security.getPlayer(src)
    if not cid then return end
    local ownerCid = PendingInvites[cid]
    PendingInvites[cid] = nil
    if not ownerCid then return end
    local lobby = Lobbies[ownerCid]
    if not lobby or lobby.started then return end
    local count = 0; for _ in pairs(lobby.players) do count = count + 1 end
    if count >= Config.MaxPlayersPerLobby then
        return Framework.Notify(src, locale('lobby_full'), 'error')
    end
    -- sai do lobby proprio (se tinha um vazio)
    if Lobbies[cid] and not Lobbies[cid].started then destroyLobby(cid) end
    local prof = getProfile(cid)
    lobby.players[cid] = { src = src, name = playerName(src), level = prof.level }
    PlayerLobby[cid] = ownerCid
    broadcast(lobby, 'vp_cityworks:refreshLobby', lobby.players, lobby.disciplineId, lobby.region)
end)

RegisterNetEvent('vp_cityworks:kickPlayer', function(targetCid)
    local src = source
    if not Security.canAct(src, 'kickPlayer', Config.Cooldowns.kickPlayer) then return end
    if type(targetCid) ~= 'string' then return end
    local lobby, cid = getLobbyBySrc(src)
    if not lobby or lobby.owner ~= cid then return end
    if targetCid == cid then return end
    local target = lobby.players[targetCid]
    if not target then return end
    local tSrc = target.src
    lobby.players[targetCid] = nil
    PlayerLobby[targetCid] = nil
    TriggerClientEvent('vp_cityworks:leftLobby', tSrc)
    broadcast(lobby, 'vp_cityworks:refreshLobby', lobby.players, lobby.disciplineId, lobby.region)
end)

---------------------------------------------------------------------
-- SELECIONAR FRENTE DE TRABALHO
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:selectDiscipline', function(disciplineId)
    local src = source
    if not Security.canAct(src, 'selectDiscipline', Config.Cooldowns.selectDiscipline) then return end
    if type(disciplineId) ~= 'string' then return end
    local lobby, cid = getLobbyBySrc(src)
    if not lobby or lobby.owner ~= cid or lobby.started then return end
    local disc = Config.Disciplines[disciplineId]
    if not disc then return end
    if getProfile(cid).level < (disc.minLevel or 0) then
        return Framework.Notify(src, locale('min_level', disc.minLevel), 'error')
    end
    lobby.disciplineId = disciplineId
    lobby.region = false -- troca de frente reseta a regiao
    broadcast(lobby, 'vp_cityworks:refreshLobby', lobby.players, lobby.disciplineId, false)
end)

---------------------------------------------------------------------
-- SELECIONAR MISSAO (regiao dentro da frente)
---------------------------------------------------------------------
RegisterNetEvent('vp_cityworks:selectMission', function(regionKey)
    local src = source
    if not Security.canAct(src, 'selectMission', Config.Cooldowns.selectMission) then return end
    local lobby, cid = getLobbyBySrc(src)
    if not lobby or lobby.owner ~= cid or lobby.started then return end
    if regionKey == false then
        lobby.region = false
        return broadcast(lobby, 'vp_cityworks:refreshLobby', lobby.players, lobby.disciplineId, false)
    end
    local disc = Utils.discipline(lobby.disciplineId)
    local region = Utils.region(disc, regionKey)
    if not region then return end
    -- gate de nivel (validado no SERVIDOR, nao so no menu)
    local prof = getProfile(cid)
    if prof.level < (region.minLevel or 0) then
        return Framework.Notify(src, locale('min_level', region.minLevel), 'error')
    end
    lobby.region = region
    broadcast(lobby, 'vp_cityworks:refreshLobby', lobby.players, lobby.disciplineId, region)
end)

---------------------------------------------------------------------
-- INICIAR JOB
---------------------------------------------------------------------
local function generateMission(disc, region)
    local mission = { targets = {}, progress = {}, remaining = 0 }
    local nextId = 0

    -- GUINCHO: alvos sao veiculos a rebocar (modo 'tow')
    if disc.kind == 'towing' then
        local picked = Utils.pickRandom(disc.variants, region.towCount or 3)
        mission.progress['tow'] = { count = #picked, made = 0, label = disc.taskLabels.tow or 'Reboque' }
        for _, v in ipairs(picked) do
            nextId = nextId + 1
            mission.targets[nextId] = {
                id = nextId, type = 'tow', mode = 'tow',
                coords = vec3(v.coords.x, v.coords.y, v.coords.z),
                variant = v, vehicleNetId = nil, loaded = false, fixed = false,
            }
            mission.remaining = mission.remaining + 1
        end
        return mission
    end

    for _, task in ipairs(region.jobTasks) do
        local pool = region.pools[task.name] or {}
        local picked = Utils.pickRandom(pool, task.count)
        local mode = (disc.taskMode and disc.taskMode[task.name]) or 'minigame'
        mission.progress[task.name] = { count = #picked, made = 0, label = disc.taskLabels[task.name] or task.name }
        for _, coords in ipairs(picked) do
            nextId = nextId + 1
            local hp
            if mode == 'drill' then
                hp = (disc.drill and disc.drill[task.name] and disc.drill[task.name].health) or 4
            end
            mission.targets[nextId] = {
                id = nextId,
                type = task.name,
                coords = coords,
                mode = mode,
                health = hp,
                fixed = false,
                openBy = nil,
                equipped = disc.requiresEquipment[task.name] == nil, -- ja "ok" se nao exige
            }
            mission.remaining = mission.remaining + 1
        end
    end
    return mission
end

RegisterNetEvent('vp_cityworks:startJob', function()
    local src = source
    if not Security.canAct(src, 'startJob', Config.Cooldowns.startJob) then return end
    local lobby, cid = getLobbyBySrc(src)
    if not lobby or lobby.owner ~= cid then return end
    if lobby.started then
        return Framework.Notify(src, locale('job_already_started'), 'error')
    end
    if not lobby.region then
        return Framework.Notify(src, locale('mission_not_selected'), 'error')
    end
    if getProfile(cid).level < (lobby.region.minLevel or 0) then
        return Framework.Notify(src, locale('min_level', lobby.region.minLevel), 'error')
    end

    -- item obrigatorio (ox_inventory)
    if Config.RequiredItem.enable then
        local function hasItem(s) return (exports.ox_inventory:GetItemCount(s, Config.RequiredItem.name) or 0) > 0 end
        if Config.RequiredItem.wholeTeam then
            for _, pl in pairs(lobby.players) do
                if not hasItem(pl.src) then return Framework.Notify(src, locale('need_item'), 'error') end
            end
        elseif not hasItem(src) then
            return Framework.Notify(src, locale('need_item'), 'error')
        end
    end

    -- deposito do veiculo (cobrado do DONO)
    if Config.VehicleDeposit.enable then
        local acc = Config.VehicleDeposit.account
        local amount = Config.VehicleDeposit.amount
        if Framework.GetMoney(src, acc) < amount then
            return Framework.Notify(src, locale('dont_have_deposit', amount), 'error')
        end
        Framework.RemoveMoney(src, acc, amount, 'vp_cityworks-deposit')
        lobby.depositPaid = true
        lobby.deposit = amount
        lobby.depositAccount = acc
        Framework.Notify(src, locale('deposit_charged', amount), 'inform')
    end

    -- consome item obrigatorio (do dono) apos confirmar
    if Config.RequiredItem.enable and Config.RequiredItem.consume then
        exports.ox_inventory:RemoveItem(src, Config.RequiredItem.name, 1)
    end

    local disc = Utils.discipline(lobby.disciplineId)
    lobby.started = true
    lobby.finished = false
    lobby.mission = generateMission(disc, lobby.region)

    -- conta players p/ recompensa e 2o veiculo
    local count = 0; for _ in pairs(lobby.players) do count = count + 1 end
    lobby.playerCount = count
    lobby.rewardMoney = Utils.calcReward(lobby.region.awards.money, lobby.region.awards.coopMultiplier, count)
    lobby.rewardXp = lobby.region.awards.xp

    -- spawn de veiculo(s) server-side
    local sp = lobby.region.spawnCoords
    local function spawnVeh(model, c)
        local veh = CreateVehicleServerSetter(model, 'automobile', c.x, c.y, c.z, c.w)
        local t = 0
        while not DoesEntityExist(veh) and t < 100 do Wait(10); t = t + 1 end
        if not DoesEntityExist(veh) then return end
        Entity(veh).state:set('fuel', disc.vehicle.fuel, true) -- ox_fuel statebag
        lobby.vehicles[#lobby.vehicles + 1] = NetworkGetNetworkIdFromEntity(veh)
        -- da chave a todos do lobby
        for _, pl in pairs(lobby.players) do
            Framework.GiveKeys(pl.src, veh)
        end
    end
    spawnVeh(disc.vehicle.primary, sp[1])
    if count > 2 and sp[2] then spawnVeh(disc.vehicle.secondary, sp[2]) end

    -- GUINCHO: spawna os veiculos quebrados a rebocar
    if disc.kind == 'towing' then
        for _, t in pairs(lobby.mission.targets) do
            local v = t.variant
            local bveh = CreateVehicleServerSetter(v.model, 'automobile', v.coords.x, v.coords.y, v.coords.z, v.coords.w)
            local tt = 0
            while not DoesEntityExist(bveh) and tt < 100 do Wait(10); tt = tt + 1 end
            if DoesEntityExist(bveh) then
                t.vehicleNetId = NetworkGetNetworkIdFromEntity(bveh)
            end
        end
    end

    broadcast(lobby, 'vp_cityworks:jobStarted', {
        disciplineId = lobby.disciplineId,
        region = lobby.region,
        mission = lobby.mission,
        vehicles = lobby.vehicles,
        progress = lobby.mission.progress,
        players = lobby.players,
    })
end)

-- boss split: dono define a % de pagamento de cada membro
RegisterNetEvent('vp_cityworks:setRewardSplit', function(split)
    local src = source
    if not Config.BossRewardSplit then return end
    if not Security.canAct(src, 'setRewardSplit', 1000) then return end
    if type(split) ~= 'table' then return end
    local lobby, cid = getLobbyBySrc(src)
    if not lobby or lobby.owner ~= cid then return end
    local sum = 0
    for k, v in pairs(split) do
        if type(k) ~= 'string' or type(v) ~= 'number' or v < 0 or v > 100 then
            return Framework.Notify(src, locale('split_invalid'), 'error')
        end
        if not lobby.players[k] then return end -- cid invalido
        sum = sum + v
    end
    if sum > 100 then
        return Framework.Notify(src, locale('split_invalid'), 'error')
    end
    lobby.split = split
    Framework.Notify(src, locale('split_set'), 'success')
end)

RegisterNetEvent('vp_cityworks:resetJob', function()
    local src = source
    if not Security.canAct(src, 'resetJob', Config.Cooldowns.resetJob) then return end
    local lobby, cid = getLobbyBySrc(src)
    if not lobby then return end
    if lobby.owner ~= cid then
        return Framework.Notify(src, locale('not_owner'), 'error')
    end
    -- abandono sem entregar = deposito perdido
    if lobby.depositPaid then
        Framework.Notify(src, locale('deposit_lost', lobby.deposit), 'error')
        lobby.depositPaid = false
    end
    broadcast(lobby, 'vp_cityworks:jobReset')
    destroyLobby(cid)
end)

---------------------------------------------------------------------
-- LIMPEZA
---------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    local lobby, cid = getLobbyBySrc(src)
    if not lobby then return end
    if cid == lobby.owner then
        -- dono saiu: encerra missao p/ todos
        for pcid, pl in pairs(lobby.players) do
            if pcid ~= cid then
                TriggerClientEvent('vp_cityworks:jobReset', pl.src)
                Framework.Notify(pl.src, locale('left_lobby'), 'error')
            end
        end
        destroyLobby(cid)
    else
        lobby.players[cid] = nil
        PlayerLobby[cid] = nil
        if lobby.started then
            broadcast(lobby, 'vp_cityworks:refreshLobby', lobby.players, lobby.disciplineId, lobby.region)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for ownerCid in pairs(Lobbies) do
        destroyLobby(ownerCid)
    end
end)
