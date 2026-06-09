-- client/toolbox.lua :: RASCUNHO — caixa de ferramentas carregavel (estilo gg)
-- ⚠️ bone/offset/anim em Config.Toolbox.attach sao PLACEHOLDER: afine in-game.
-- Opt-in: Config.Toolbox.enable + discipline.requiresToolbox = true.
-- Expoe globais: CarryToolbox(), DropToolbox(), IsCarryingToolbox().
-- Usa globais de outros arquivos: JobActive, MissionVehicles, CityNotify.

local carrying = false
local toolProp = nil

function IsCarryingToolbox() return carrying end

local function attachProp()
    local cfg = Config.Toolbox
    if not IsModelInCdimage(cfg.prop) then return end
    lib.requestModel(cfg.prop)
    local pc = GetEntityCoords(cache.ped)
    toolProp = CreateObject(cfg.prop, pc.x, pc.y, pc.z, true, true, false)
    local o = cfg.attach
    AttachEntityToEntity(toolProp, cache.ped, GetPedBoneIndex(cache.ped, o.bone),
        o.x, o.y, o.z, o.rx, o.ry, o.rz, false, false, false, false, 2, true)
    SetModelAsNoLongerNeeded(cfg.prop)
end

local function hasItem()
    local cfg = Config.Toolbox
    if not cfg.item then return true end
    local ok, n = pcall(function() return exports.ox_inventory:Search('count', cfg.item) end)
    return ok and (n or 0) >= 1
end

function CarryToolbox()
    local cfg = Config.Toolbox
    if not cfg or not cfg.enable or carrying then return end
    if not hasItem() then
        if CityNotify then CityNotify(('Voce precisa de %s.'):format(cfg.item), 'error') end
        return
    end
    -- anim de pegar
    local p = cfg.anim.pickup
    lib.requestAnimDict(p.dict)
    TaskPlayAnim(cache.ped, p.dict, p.clip, 8.0, 1.0, p.time or 700, 49, 0, false, false, false)
    Wait(p.time or 700)
    ClearPedTasks(cache.ped)
    attachProp()
    carrying = true
    -- loop: mantem a anim de carregar + debuffs (sem correr/pular, anda devagar)
    CreateThread(function()
        local c = cfg.anim.carry
        lib.requestAnimDict(c.dict)
        while carrying do
            if not IsEntityPlayingAnim(cache.ped, c.dict, c.clip, 3) then
                TaskPlayAnim(cache.ped, c.dict, c.clip, 8.0, 1.0, -1, 49, 0, false, false, false)
            end
            DisableControlAction(0, 21, true) -- sprint
            DisableControlAction(0, 22, true) -- jump
            SetPedMoveRateOverride(cache.ped, cfg.walkRate or 0.85)
            Wait(0)
        end
    end)
end

function DropToolbox()
    if not carrying then return end
    carrying = false
    if toolProp and DoesEntityExist(toolProp) then DeleteEntity(toolProp) end
    toolProp = nil
    ClearPedTasks(cache.ped)
end

-- comando p/ pegar/largar (precisa estar perto de um veiculo do job)
CreateThread(function()
    local cfg = Config.Toolbox
    if not cfg or not cfg.enable or not cfg.command then return end
    RegisterCommand(cfg.command, function()
        if not JobActive then return end
        if carrying then return DropToolbox() end
        local pc = GetEntityCoords(cache.ped)
        local near = false
        for _, netId in ipairs(MissionVehicles or {}) do
            local v = NetToVeh(netId)
            if v and v ~= 0 and DoesEntityExist(v) and #(GetEntityCoords(v) - pc) <= (cfg.grabDistance or 6.0) then
                near = true; break
            end
        end
        if not near then
            if CityNotify then CityNotify('Aproxime-se do caminhao para pegar a caixa.', 'error') end
            return
        end
        CarryToolbox()
    end, false)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then DropToolbox() end
end)
