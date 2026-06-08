-- vp_cityworks :: script feito por LORD32 aka Vini32 e Dooc
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vp_cityworks'
author 'LORD32 aka Vini32 e Dooc'
version '1.0.0'
description 'Job cooperativo de eletricista por regiao para QBox (nativo ox)'

-- Dependencias reais deste servidor (versoes confirmadas):
--  qbx_core 1.23.0 | ox_lib 3.32.2 | ox_inventory 2.44.8 | ox_target | ox_fuel | qbx_vehiclekeys | oxmysql
dependencies {
    'qbx_core',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'ox_fuel',          -- combustivel via statebag 'fuel'
    'qbx_vehiclekeys',  -- exports.qbx_vehiclekeys:GiveKeys
    'oxmysql',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/main.lua',
    'client/mission.lua',
    'client/equipment.lua',
    'client/minigames.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/security.lua',
    'server/main.lua',
    'server/missions.lua',
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
