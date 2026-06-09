-- shared/framework.lua :: adaptador multi-framework (QBox / QBCore / ESX)
-- Auto-detecta o core e expõe uma API unica. ox_lib / ox_inventory / ox_fuel /
-- ox_target são comuns aos 3, então só o core (player/dinheiro/job/nome) e as
-- chaves de veiculo precisam de abstracao.

Framework = { name = 'unknown' }

local function detect()
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'unknown'
end
Framework.name = detect()

-- core object (qb/esx). qbx usa exports diretos.
local core
local function getCore()
    if core then return core end
    if Framework.name == 'qb' then
        local ok, c = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok then core = c end
    elseif Framework.name == 'esx' then
        local ok, c = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok then core = c end
    end
    return core
end

-- normaliza conta: esx usa 'money' p/ dinheiro vivo
local function esxAccount(account) return account == 'cash' and 'money' or account end

if IsDuplicityVersion() then
    -------------------------------------------------------------- SERVER
    --- @return table|nil player object do core
    local function getPlayer(src)
        if Framework.name == 'qbx' then
            return exports.qbx_core:GetPlayer(src)
        elseif Framework.name == 'qb' then
            local c = getCore(); return c and c.Functions.GetPlayer(src)
        elseif Framework.name == 'esx' then
            local c = getCore(); return c and c.GetPlayerFromId(src)
        end
    end
    Framework.GetPlayer = getPlayer

    function Framework.GetCitizenId(src)
        local p = getPlayer(src)
        if not p then return nil end
        if Framework.name == 'esx' then return p.identifier end
        return p.PlayerData and p.PlayerData.citizenid
    end

    function Framework.GetFullName(src)
        local p = getPlayer(src)
        if not p then return GetPlayerName(src) or ('ID ' .. src) end
        if Framework.name == 'esx' then return p.getName() end
        local ci = p.PlayerData.charinfo
        return ci and (ci.firstname .. ' ' .. ci.lastname) or (GetPlayerName(src) or '')
    end

    function Framework.GetMoney(src, account)
        local p = getPlayer(src); if not p then return 0 end
        if Framework.name == 'esx' then
            if account == 'cash' then return p.getMoney() end
            local acc = p.getAccount(account); return acc and acc.money or 0
        end
        return (p.PlayerData.money and p.PlayerData.money[account]) or 0
    end

    function Framework.AddMoney(src, account, amount, reason)
        local p = getPlayer(src); if not p then return end
        if Framework.name == 'esx' then
            if account == 'cash' then p.addMoney(amount) else p.addAccountMoney(esxAccount(account), amount) end
        else
            p.Functions.AddMoney(account, amount, reason)
        end
    end

    function Framework.RemoveMoney(src, account, amount, reason)
        local p = getPlayer(src); if not p then return end
        if Framework.name == 'esx' then
            if account == 'cash' then p.removeMoney(amount) else p.removeAccountMoney(esxAccount(account), amount) end
        else
            p.Functions.RemoveMoney(account, amount, reason)
        end
    end

    function Framework.Notify(src, msg, ntype)
        if Framework.name == 'qbx' then
            exports.qbx_core:Notify(src, msg, ntype)
        elseif Framework.name == 'qb' then
            TriggerClientEvent('QBCore:Notify', src, msg, ntype)
        elseif Framework.name == 'esx' then
            TriggerClientEvent('esx:showNotification', src, msg)
        else
            TriggerClientEvent('ox_lib:notify', src, { description = msg, type = ntype })
        end
    end

    --- Da chave do veiculo ao player (auto: qbx_vehiclekeys, qb-vehiclekeys; senao Config.GiveKeysFn)
    function Framework.GiveKeys(src, vehicle)
        if Config.GiveKeysFn then return Config.GiveKeysFn(src, vehicle) end
        if GetResourceState('qbx_vehiclekeys') == 'started' then
            return exports.qbx_vehiclekeys:GiveKeys(src, vehicle, true)
        end
        local plate = GetVehicleNumberPlateText(vehicle)
        if GetResourceState('qb-vehiclekeys') == 'started' then
            return TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
        end
        if GetResourceState('wasabi_carlock') == 'started' then
            return exports.wasabi_carlock:GiveKey(src, plate)
        end
        -- sem sistema de chaves detectado: no-op (config pode sobrescrever)
    end
else
    -------------------------------------------------------------- CLIENT
    --- @return table { name=string, grade=number }
    function Framework.GetJob()
        if Framework.name == 'qbx' then
            local d = exports.qbx_core:GetPlayerData()
            local j = d and d.job
            return j and { name = j.name, grade = (j.grade and j.grade.level) or 0 } or { name = 'unemployed', grade = 0 }
        elseif Framework.name == 'qb' then
            local c = getCore(); local d = c and c.Functions.GetPlayerData()
            local j = d and d.job
            return j and { name = j.name, grade = (j.grade and j.grade.level) or 0 } or { name = 'unemployed', grade = 0 }
        elseif Framework.name == 'esx' then
            local c = getCore(); local d = c and c.GetPlayerData()
            local j = d and d.job
            return j and { name = j.name, grade = j.grade or 0 } or { name = 'unemployed', grade = 0 }
        end
        return { name = 'unknown', grade = 0 }
    end
end
