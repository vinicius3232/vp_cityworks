-- server/towers.lua :: desgaste OPCIONAL das torres do vp_towers
-- Cria demanda natural para a frente "Manutencao de Torres" degradando
-- torres ao longo do tempo. Controlado por Config.TowerWear (default off).
-- O reparo em si (SetTowerHealth -> repairTo) acontece em server/missions.lua
-- quando o alvo da torre e concluido.

CreateThread(function()
    local cfg = Config.TowerWear
    if not cfg or not cfg.enable then return end
    local res = cfg.resource or 'vp_towers'

    print(('^2[vp_cityworks]^0 Desgaste de torres ATIVO (a cada %dms, -%d health).')
        :format(cfg.interval or 600000, cfg.amount or 15))

    while true do
        Wait(cfg.interval or 600000)
        if GetResourceState(res) == 'started' and math.random(100) <= (cfg.chance or 100) then
            local ok, towers = pcall(function() return exports[res]:GetTowers() end)
            if ok and type(towers) == 'table' then
                -- candidatas: torres ainda acima do minimo (podem perder health)
                local cand = {}
                for i, tw in ipairs(towers) do
                    if (tw.health or 100) > (cfg.minHealth or 0) then
                        cand[#cand + 1] = { i = i, h = tw.health or 100 }
                    end
                end
                if #cand > 0 then
                    local pick = cand[math.random(#cand)]
                    local newH = math.max(cfg.minHealth or 0, pick.h - (cfg.amount or 15))
                    pcall(function() exports[res]:SetTowerHealth(pick.i, newH) end)
                end
            end
        end
    end
end)
