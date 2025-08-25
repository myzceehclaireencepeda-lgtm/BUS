-- client/main.lua

local spawnedAnimals = {}
local activeLots = {}
local farmlotNPCs = {}
local animalNPCs = {}
local isFeeding = false
local isCollecting = false
local animalBlips = {}
local lotBlips = {}
local statusTextLabels = {}
local animalStates = {}

-- ✅ Utility: Show notification
local function notify(msg, type)
    lib.notify({
        title = 'Animal Farming',
        description = msg,
        type = type or 'inform',
        duration = 5000
    })
end

-- ✅ 3D Text for animal status
local function createStatusTextLabel(entity, text)
    local textLabel = lib.zones.text({
        coords = GetEntityCoords(entity),
        text = text,
        font = 4,
        scale = 0.5,
        color = { r = 255, g = 255, b = 255, a = 255 },
        background = { r = 0, g = 0, b = 0, a = 100 },
        radius = 5.0
    })
    
    statusTextLabels[entity] = textLabel
    return textLabel
end

-- ✅ Update animal status display
local function updateAnimalStatusDisplay(animalId, data)
    if spawnedAnimals[animalId] and DoesEntityExist(spawnedAnimals[animalId].ped) then
        local ped = spawnedAnimals[animalId].ped
        local statusText = string.format("%s (%s)\nH: %d%% | F: %d%% | W: %d%%", 
            spawnedAnimals[animalId].type:upper(), 
            spawnedAnimals[animalId].gender:upper(),
            data.health or 0, 
            data.hunger or 0, 
            data.thirst or 0
        )
        
        if statusTextLabels[ped] then
            statusTextLabels[ped]:remove()
        end
        
        if Config.ShowAnimalStatus then
            createStatusTextLabel(ped, statusText)
        end
    end
end

-- ✅ Spawn NPC helper
local function spawnNPC(model, coords, heading, scenario)
    lib.requestModel(model, 5000)
    local ped = CreatePed(0, model, coords.x, coords.y, coords.z - 1, heading, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    
    if scenario then
        TaskStartScenarioInPlace(ped, scenario, 0, true)
    end
    
    return ped
end

-- ✅ Create blips for farmlots
local function createFarmlotBlips()
    for lotId, lotData in pairs(activeLots) do
        if not lotBlips[lotId] then
            local blip = AddBlipForCoord(lotData.coords.x, lotData.coords.y, lotData.coords.z)
            SetBlipSprite(blip, 442) -- Ranch blip
            SetBlipColour(blip, 2) -- Green
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(lotData.label or ("Farm Lot #" .. lotId))
            EndTextCommandSetBlipName(blip)
            lotBlips[lotId] = blip
        end
    end
end

-- ✅ Setup NPCs with enhanced interactions
local function setupNPCs()
    -- Farmlot Sellers
    for i, npc in pairs(Config.FarmlotSellers) do
        local ped = spawnNPC(npc.model, npc.coords, npc.coords.w, 'WORLD_HUMAN_CLIPBOARD')
        farmlotNPCs[i] = ped

        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'farmlot_seller_' .. i,
                label = ('Buy %s Farmlot ($%s)'):format(npc.lotType or "Animal", npc.price),
                icon = 'fa-solid fa-tractor',
                onSelect = function()
                    local input = lib.inputDialog('Purchase Farmlot', {
                        {type = 'input', label = 'Lot Label', placeholder = 'My Farm', required = true},
                        {type = 'checkbox', label = 'Confirm Purchase'}
                    })
                    
                    if input and input[2] then
                        TriggerServerEvent('animal_farming:server:buyFarmlot', {
                            lotType = npc.lotType,
                            price = npc.price,
                            label = input[1]
                        })
                    end
                end
            }
        })
    end

    -- Animal Vendors
    for i, npc in pairs(Config.AnimalVendors) do
        local ped = spawnNPC(npc.model, npc.coords, npc.coords.w, 'WORLD_HUMAN_CLIPBOARD')
        animalNPCs[i] = ped

        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'animal_vendor_' .. i,
                label = 'Buy Animals',
                icon = 'fa-solid fa-paw',
                onSelect = function()
                    openAnimalShop()
                end
            },
            {
                name = 'animal_vendor_info_' .. i,
                label = 'Get Farming Info',
                icon = 'fa-solid fa-book',
                onSelect = function()
                    showFarmingGuide()
                end
            }
        })
    end
end

-- ✅ Enhanced animal shop interface
function openAnimalShop()
    local ownedLots = lib.callback.await('animal_farming:server:getFarmlots', false)
    
    if not ownedLots or #ownedLots == 0 then
        notify('You need to own a farmlot first!', 'error')
        return
    end

    local options = {}
    for animalType, animalData in pairs(Config.Animals) do
        table.insert(options, {
            title = animalData.label or animalType:upper(),
            description = ('Price: $%s | Requires: %s Lot'):format(animalData.price, animalType:upper()),
            metadata = {
                {label = 'Health', value = animalData.stats.health},
                {label = 'Female Chance', value = animalData.femaleChance .. '%'},
                {label = 'Produces', value = getProductInfo(animalType)}
            },
            onSelect = function()
                selectLotForAnimal(animalType, animalData.price)
            end
        })
    end

    lib.registerMenu({
        id = 'animal_shop_menu',
        title = 'Animal Shop',
        position = 'top-right',
        options = options
    }, function(selected, scrollIndex, args)
        lib.showMenu('animal_shop_menu')
    end)

    lib.showMenu('animal_shop_menu')
end

function getProductInfo(animalType)
    local cfg = Config.Animals[animalType]
    if animalType == 'cow' then
        return 'Milk (Female only)'
    elseif animalType == 'chicken' then
        return 'Eggs'
    elseif animalType == 'pig' then
        return 'Raw Pork'
    end
    return 'Unknown'
end

function selectLotForAnimal(animalType, price)
    local ownedLots = lib.callback.await('animal_farming:server:getFarmlots', false)
    local lotOptions = {}
    
    for _, lot in ipairs(ownedLots) do
        if lot.lot_type == animalType then
            table.insert(lotOptions, {
                title = lot.label or ('Lot #' .. lot.id),
                description = ('Location: %s'):format(vector3(lot.coords.x, lot.coords.y, lot.coords.z)),
                onSelect = function()
                    confirmAnimalPurchase(animalType, price, lot.id)
                end
            })
        end
    end

    if #lotOptions == 0 then
        notify('No suitable lots available for this animal type!', 'error')
        return
    end

    lib.registerMenu({
        id = 'select_lot_menu',
        title = 'Select Farmlot',
        position = 'top-right',
        options = lotOptions
    }, function(selected, scrollIndex, args)
        lib.showMenu('select_lot_menu')
    end)

    lib.showMenu('select_lot_menu')
end

function confirmAnimalPurchase(animalType, price, lotId)
    local confirm = lib.alertDialog({
        header = 'Confirm Purchase',
        content = ('Buy %s for $%s?'):format(animalType, price),
        centered = true,
        cancel = true
    })
    
    if confirm == 'confirm' then
        TriggerServerEvent('animal_farming:server:buyAnimal', {
            animal_type = animalType,
            lot_id = lotId
        })
    end
end

-- ✅ Enhanced animal spawning with wandering behavior
RegisterNetEvent('animal_farming:client:spawnAnimal', function(data)
    local animalId, animalType, coords, gender, stats = data.id, data.type, data.coords, data.gender, data.stats
    
    if spawnedAnimals[animalId] then
        notify('Animal already spawned!', 'warning')
        return
    end

    lib.requestModel(Config.Animals[animalType].model, 10000)
    
    local ped = CreatePed(28, Config.Animals[animalType].model, coords.x, coords.y, coords.z, 0.0, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedRelationshipGroupHash(ped, `DOMESTIC_ANIMAL`)

    -- Enhanced wandering behavior based on animal type
    local wanderDistance = Config.Animals[animalType].wanderDistance or 10.0
    TaskWanderInArea(ped, coords.x, coords.y, coords.z, wanderDistance, 0.0, 0)

    spawnedAnimals[animalId] = {
        ped = ped,
        type = animalType,
        gender = gender,
        stats = stats or { health = 100, hunger = 100, thirst = 100 },
        coords = coords
    }

    animalStates[animalId] = 'wandering'

    -- Create animal blip
    local blip = AddBlipForEntity(ped)
    SetBlipSprite(blip, Config.Animals[animalType].blip or 141)
    SetBlipColour(blip, gender == 'female' and 8 or 1) -- Pink for female, blue for male
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(('%s (%s)'):format(animalType:upper(), gender:upper()))
    EndTextCommandSetBlipName(blip)
    animalBlips[animalId] = blip

    -- Setup target options
    setupAnimalTargetOptions(animalId, ped)

    -- Status display
    if Config.ShowAnimalStatus then
        updateAnimalStatusDisplay(animalId, stats)
    end

    notify(("Spawned a %s (%s)"):format(animalType, gender), 'success')
end)

-- ✅ Enhanced target options with conditions
function setupAnimalTargetOptions(animalId, ped)
    local options = {
        {
            name = 'animal_farming:feed_' .. animalId,
            label = 'Feed Animal',
            icon = 'fa-solid fa-wheat-alt',
            canInteract = function()
                return not isFeeding and spawnedAnimals[animalId] and spawnedAnimals[animalId].stats.hunger < 90
            end,
            onSelect = function()
                feedAnimal(animalId)
            end
        },
        {
            name = 'animal_farming:collect_' .. animalId,
            label = 'Collect Product',
            icon = 'fa-solid fa-bucket',
            canInteract = function()
                return not isCollecting and canCollectProduct(animalId)
            end,
            onSelect = function()
                collectProduct(animalId)
            end
        },
        {
            name = 'animal_farming:stats_' .. animalId,
            label = 'Check Stats',
            icon = 'fa-solid fa-chart-line',
            onSelect = function()
                checkAnimalStats(animalId)
            end
        },
        {
            name = 'animal_farming:butcher_' .. animalId,
            label = 'Butcher Animal',
            icon = 'fa-solid fa-knife',
            canInteract = function()
                return spawnedAnimals[animalId] and spawnedAnimals[animalId].stats.health <= 0
            end,
            onSelect = function()
                butcherAnimal(animalId)
            end
        }
    }

    exports.ox_target:addLocalEntity(ped, options)
end

function canCollectProduct(animalId)
    local animal = spawnedAnimals[animalId]
    if not animal or animal.stats.health <= 0 then return false end
    
    -- Check gender-specific conditions
    if animal.type == 'cow' and animal.gender ~= 'female' then
        return false
    end
    
    return animal.stats.health >= 50 and animal.stats.hunger >= 40
end

-- ✅ Enhanced feeding with animations
function feedAnimal(animalId)
    if isFeeding then return end
    isFeeding = true

    local animal = spawnedAnimals[animalId]
    if not animal then
        isFeeding = false
        return
    end

    -- Play feeding animation
    local playerPed = PlayerPedId()
    TaskTurnPedToFaceEntity(playerPed, animal.ped, 1000)
    Wait(1000)
    
    lib.requestAnimDict('amb@medic@standing@tendtodead@idle_a', 1000)
    TaskPlayAnim(playerPed, 'amb@medic@standing@tendtodead@idle_a', 'idle_a', 8.0, -8.0, -1, 1, 0, false, false, false)

    lib.progressCircle({
        duration = 5000,
        label = 'Feeding Animal...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true
        },
        anim = {
            dict = 'amb@medic@standing@tendtodead@idle_a',
            clip = 'idle_a'
        }
    })

    ClearPedTasks(playerPed)
    TriggerServerEvent('animal_farming:server:feedAnimal', animalId)
    isFeeding = false
end

-- ✅ Enhanced product collection
function collectProduct(animalId)
    if isCollecting then return end
    isCollecting = true

    local animal = spawnedAnimals[animalId]
    if not animal then
        isCollecting = false
        return
    end

    -- Play collection animation based on animal type
    local animDict = animal.type == 'cow' and 'amb@medic@standing@tendtodead@idle_a' or 'mp_common'
    
    -- FIXED: Replace ternary operator with if/else
    local animClip
    if animal.type == 'cow' then
        animClip = 'idle_a'
    else
        animClip = 'givetake1_a'
    end

    lib.requestAnimDict(animDict, 1000)
    TaskPlayAnim(PlayerPedId(), animDict, animClip, 8.0, -8.0, -1, 1, 0, false, false, false)

    lib.progressCircle({
        duration = 3000,
        label = 'Collecting...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true
        }
    })

    ClearPedTasks(PlayerPedId())
    TriggerServerEvent('animal_farming:server:collectProduct', animalId)
    isCollecting = false
end

-- ✅ Enhanced stats checking
function checkAnimalStats(animalId)
    local animal = spawnedAnimals[animalId]
    if not animal then return end

    local stats = lib.callback.await('animal_farming:server:getAnimalStatus', false, animalId)
    
    if stats then
        lib.showTextUI(string.format(
            "Animal: %s (%s)\nHealth: %d%%\nHunger: %d%%\nThirst: %d%%\nStatus: %s",
            animal.type:upper(), animal.gender:upper(),
            stats.health, stats.hunger, stats.thirst,
            stats.status
        ))
        
        -- Hide text after 5 seconds
        SetTimeout(5000, function()
            lib.hideTextUI()
        end)
    end
end

-- ✅ Enhanced butchering with skill game
function butcherAnimal(animalId)
    local success = lib.skillCheck({'easy', 'easy', 'medium', 'medium'}, {'w', 'a', 's', 'd'})
    
    if success then
        TriggerServerEvent('animal_farming:server:butcherAnimal', animalId, math.random(1, 10)) -- Random skill level
    else
        notify('Butchering failed! Try again.', 'error')
    end
end

-- ✅ Handle animal stats updates
RegisterNetEvent('animal_farming:client:updateStats', function(animalId, stats)
    if spawnedAnimals[animalId] then
        spawnedAnimals[animalId].stats = stats
        updateAnimalStatusDisplay(animalId, stats)
        
        -- Update animal behavior based on stats
        updateAnimalBehavior(animalId, stats)
    end
end)

function updateAnimalBehavior(animalId, stats)
    local animal = spawnedAnimals[animalId]
    if not animal or not DoesEntityExist(animal.ped) then return end

    -- Change behavior based on hunger/thirst
    if stats.hunger < 30 or stats.thirst < 30 then
        animalStates[animalId] = 'distressed'
        TaskAnimalFlee(animal.ped, PlayerPedId(), -1)
    elseif stats.health < 50 then
        animalStates[animalId] = 'sick'
        ClearPedTasks(animal.ped)
        TaskStandStill(animal.ped, -1)
    else
        animalStates[animalId] = 'wandering'
        TaskWanderInArea(animal.ped, animal.coords.x, animal.coords.y, animal.coords.z, 
                         Config.Animals[animal.type].wanderDistance or 10.0, 0.0, 0)
    end
end

-- ✅ Handle animal despawn
RegisterNetEvent('animal_farming:client:despawnAnimal', function(animalId)
    if spawnedAnimals[animalId] then
        if DoesEntityExist(spawnedAnimals[animalId].ped) then
            DeleteEntity(spawnedAnimals[animalId].ped)
        end
        
        if animalBlips[animalId] then
            RemoveBlip(animalBlips[animalId])
            animalBlips[animalId] = nil
        end
        
        if statusTextLabels[spawnedAnimals[animalId].ped] then
            statusTextLabels[spawnedAnimals[animalId].ped]:remove()
            statusTextLabels[spawnedAnimals[animalId].ped] = nil
        end
        
        spawnedAnimals[animalId] = nil
        animalStates[animalId] = nil
        notify("Animal despawned.", 'inform')
    end
end)

-- ✅ Handle farmlot updates
RegisterNetEvent('animal_farming:client:updateFarmlots', function(lots)
    activeLots = lots
    createFarmlotBlips()
end)

-- ✅ Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for animalId, animalData in pairs(spawnedAnimals) do
            if DoesEntityExist(animalData.ped) then
                DeleteEntity(animalData.ped)
            end
        end
        
        for _, blip in pairs(animalBlips) do
            RemoveBlip(blip)
        end
        
        for _, blip in pairs(lotBlips) do
            RemoveBlip(blip)
        end
        
        for _, textLabel in pairs(statusTextLabels) do
            textLabel:remove()
        end
    end
end)

-- ✅ Initialize
CreateThread(function()
    Wait(1000) -- Wait for resources to load
    setupNPCs()
    
    -- Request initial farmlot data
    TriggerServerEvent('animal_farming:server:requestFarmlots')
    
    -- Periodic animal status updates
    while true do
        Wait(30000) -- Update every 30 seconds
        for animalId, animalData in pairs(spawnedAnimals) do
            if DoesEntityExist(animalData.ped) then
                TriggerServerEvent('animal_farming:server:updateAnimalPosition', animalId, GetEntityCoords(animalData.ped))
            end
        end
    end
end)

-- ✅ Show farming guide
function showFarmingGuide()
    lib.alertDialog({
        header = 'Animal Farming Guide',
        content = [[
        **Animal Care Guide:**
        - Feed animals regularly to keep them healthy
        - Ensure they have access to water
        - Collect products when available
        - Different animals have different needs
        
        **Production:**
        - Cows: Milk (Females only, every 3 days)
        - Chickens: Eggs (every 30 minutes)
        - Pigs: Raw Pork (every 2 hours)
        
        **Tips:**
        - Keep animals above 50% health for production
        - Use water troughs for automatic hydration
        - Butcher dead animals for meat
        ]],
        centered = true,
        cancel = false
    })
end

-- ✅ Debug commands
if Config.Debug then
    RegisterCommand('af_debug', function()
        print('=== ANIMAL FARMING DEBUG ===')
        print('Spawned Animals:', #spawnedAnimals)
        for id, animal in pairs(spawnedAnimals) do
            print(string.format('Animal %d: %s (%s) - H:%d F:%d W:%d', 
                id, animal.type, animal.gender, 
                animal.stats.health, animal.stats.hunger, animal.stats.thirst))
        end
    end)
end