-- vp_cityworks :: script feito por LORD32 aka Vini32 e Dooc
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vp_cityworks'
author 'LORD32 aka Vini32 e Dooc'
version '1.0.0'
description 'Secretaria de Obras (SADOT) multi-frente — multi-framework (QBox/QBCore/ESX)'

-- Dependencias COMUNS aos 3 frameworks (ox stack). O core (qbx_core/qb-core/
-- es_extended) e as chaves de veiculo sao auto-detectados em runtime
-- (shared/framework.lua), por isso NAO entram como dependencia obrigatoria.
dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/utils.lua',
    'shared/framework.lua',
}

client_scripts {
    'client/main.lua',
    'client/mission.lua',
    'client/equipment.lua',
    'client/minigames.lua',
    'client/towing.lua',
    'client/dispatch.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/security.lua',
    'server/main.lua',
    'server/missions.lua',
    'server/towing.lua',
    'server/dispatch.lua',
    'server/rewards.lua',
}

-- Locales via ox_lib (pt-br padrao)
files {
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

ui_page 'html/index.html'
