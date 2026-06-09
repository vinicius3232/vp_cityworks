-- server/database.lua :: queries centralizadas (oxmysql com ? - nunca concatena)
DB = {}

--- PLUG & PLAY: cria a tabela automaticamente ao iniciar o resource.
--- (CREATE TABLE IF NOT EXISTS = idempotente; nao precisa importar SQL na mao)
CreateThread(function()
    if Config.AutoCreateTable == false then return end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `vp_cityworks` (
            `citizenid` VARCHAR(50) NOT NULL,
            `xp`        INT NOT NULL DEFAULT 0,
            `level`     INT NOT NULL DEFAULT 1,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    print('^2[vp_cityworks]^0 tabela `vp_cityworks` pronta (auto-create).')
end)

--- Garante a tabela e carrega/cria o perfil do jogador.
--- @param citizenid string
--- @return table { xp, level }
function DB.loadProfile(citizenid)
    local row = MySQL.single.await('SELECT xp, level FROM vp_cityworks WHERE citizenid = ?', { citizenid })
    if row then
        return { xp = row.xp, level = row.level }
    end
    MySQL.insert.await('INSERT INTO vp_cityworks (citizenid, xp, level) VALUES (?, ?, ?)', { citizenid, 0, 1 })
    return { xp = 0, level = 1 }
end

--- Persiste xp/level.
function DB.saveProfile(citizenid, xp, level)
    MySQL.update('UPDATE vp_cityworks SET xp = ?, level = ? WHERE citizenid = ?', { xp, level, citizenid })
end
