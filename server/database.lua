-- server/database.lua :: queries centralizadas (oxmysql com ? - nunca concatena)
DB = {}

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
