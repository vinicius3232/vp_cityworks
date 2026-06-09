-- client/dispatch.lua :: serviço sob demanda (lado do cidadao e do trabalhador)

-- Cidadao: /pedirservico -> escolhe a frente -> envia o chamado
RegisterCommand(Config.Dispatch.command or 'pedirservico', function()
    if not Config.Dispatch.enable then return end
    local options = {}
    for _, id in ipairs(Config.Dispatch.disciplines or {}) do
        local d = Config.Disciplines[id]
        if d then
            options[#options + 1] = {
                title = d.label,
                icon = d.icon or 'phone',
                description = locale('dispatch_fee', Config.Dispatch.fee),
                onSelect = function()
                    TriggerServerEvent('vp_cityworks:requestService', id)
                end,
            }
        end
    end
    if #options == 0 then return end
    lib.registerContext({ id = 'vp_cityworks_dispatch', title = locale('dispatch_title'), options = options })
    lib.showContext('vp_cityworks_dispatch')
end, false)

-- Trabalhador em servico: recebe o chamado (notify + blip com rota)
RegisterNetEvent('vp_cityworks:serviceCall', function(data)
    if not data or not data.coords then return end
    CityNotify(('%s: %s — %s'):format(locale('dispatch_call_title'), data.label or '', data.requester or ''), 'inform')
    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, 280)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.9)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(locale('dispatch_blip'))
    EndTextCommandSetBlipName(blip)
    SetTimeout(Config.Dispatch.blipTime or 180000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)
