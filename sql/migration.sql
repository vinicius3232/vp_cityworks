-- vp_cityworks :: persistencia de XP/level por jogador
-- Diferente do original (longtext JSON sem indice): colunas tipadas + PRIMARY KEY.

CREATE TABLE IF NOT EXISTS `vp_cityworks` (
  `citizenid` VARCHAR(50) NOT NULL,
  `xp`        INT NOT NULL DEFAULT 0,
  `level`     INT NOT NULL DEFAULT 1,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
