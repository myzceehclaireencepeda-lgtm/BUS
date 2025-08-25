fx_version 'cerulean'
game 'gta5'

name 'qbx_animalfarmingv1'
version '1.0.0'
description 'Advanced Animal Farming System for QBX Framework'
author 'Myzcent_Cepeda'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/animal.lua'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql'
}