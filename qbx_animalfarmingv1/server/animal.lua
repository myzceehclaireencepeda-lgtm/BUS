-- server/main.lua
-- Animal Farming (Server) — QBX + ox_lib + ox_inventory + oxmysql

local lib = exports.ox_lib
local oxmysql = exports.oxmysql

-- NOTE: If your core export name is different, adjust here.
-- Some servers use 'qbx-core' / 'qb-core' as the resource name.
local CORE = 'qbx_core'

-- Helpers
local function getPlayer(src)
    local ok, player = pcall(function() return exports[CORE]:GetPlayer(src) end)
    if not ok or not player then return nil end
    return player
end

local function debugPrint(...)
    if Config.Debug then
        print('[animal_farming]', ...)
    end
end

-- Quick JSON helpers
local function encode(v)
    return json.encode(v)
end

local function decode(v)
    return json.decode(v)
end

local function nowUtc()
    return os.time(os.date('!*t'))
end

-- Cache config lookups for speed
local DB = Config.Database or {
    farmlots = "animal_farmlots",
    livestock = "animal_livestock",
    water = "animal_water_troughs",
    transactions = "animal_transactions",
    production_log = "animal_production_log",
    death_log = "animal_death_log"
}

-- ============================
--         OX_LIB RPCs
-- ============================
-- Get player lots
lib.callback.register('animal_farming:server:getFarmlots', function(source)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    local citizenid = player.PlayerData.citizenid

    local rows = oxmysql:executeSync(string.format([[ 
        SELECT * FROM %s WHERE citizenid = ? ORDER BY id ASC 
    ]], DB.farmlots), { citizenid })
    return true, rows or {}
end)

-- Purchase farmlot
lib.callback.register('animal_farming:server:buyFarmlot', function(source, data)
    local player = getPlayer(source)
    if not player then 
        return false, 'player not found' 
    end

    local citizenid = player.PlayerData.citizenid

    -- Lot type validation
    local lotType = (data and data.lotType) and tostring(data.lotType) or ''
    if lotType ~= 'cow' and lotType ~= 'pig' and lotType ~= 'chicken' then
        return false, 'invalid lot type'
    end

    -- Enforce max lots per player
    if Config.MaxFarmlotsPerPlayer and type(Config.MaxFarmlotsPerPlayer) == 'number' then
        local count = oxmysql:scalarSync(string.format([[ 
            SELECT COUNT(*) FROM %s WHERE citizenid = ? 
        ]], DB.farmlots), { citizenid }) or 0

        if count >= Config.MaxFarmlotsPerPlayer then
            return false, ('max lots reached (%d)'):format(Config.MaxFarmlotsPerPlayer)
        end
    end

    -- Safely get price with proper Lua syntax
    local price = 0
    if data and data.price then
        price = tonumber(data.price) or 0
    end
    if price < 0 then price = 0 end

    -- Money check
    if price > 0 then
        if not player.Functions.RemoveMoney('cash', price, 'buy_farmlot') then
            return false, 'not enough cash'
        end
    end

    -- Safely prepare values with proper Lua syntax
    local coords = {x = 0, y = 0, z = 0, w = 0}
    if data and data.coords then
        coords = data.coords
    end

    local bounds = nil
    if data and data.bounds then
        bounds = data.bounds
    end

    local label = lotType .. ' Farmlot'
    if data and data.label then
        label = data.label
    end

    -- Insert farmlot
    local insertId = oxmysql:insertSync(string.format([[
        INSERT INTO %s (citizenid, lot_type, label, coords, bounds, price)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], DB.farmlots), {
        citizenid, lotType, label, encode(coords), bounds and encode(bounds) or nil, price
    })

    if not insertId then
        if price > 0 then
            player.Functions.AddMoney('cash', price, 'buy_farmlot_refund')
        end
        return false, 'db insert failed'
    end

    -- Transaction log
    oxmysql:insert(string.format([[
        INSERT INTO %s (citizenid, `type`, ref_id, animal_type, amount, meta)
        VALUES (?, 'buy_lot', ?, ?, ?, ?)
    ]], DB.transactions), {
        citizenid, insertId, lotType, price, encode({label = label})
    })

    debugPrint(('Player %s bought %s lot #%d'):format(citizenid, lotType, insertId))
    
    return true, {
        id = insertId,
        lotType = lotType,
        price = price,
        coords = coords,
        bounds = bounds,
        label = label
    }
end)

-- List animals owned by player (optionally by lot)
lib.callback.register('animal_farming:server:getAnimals', function(source, filter)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    local citizenid = player.PlayerData.citizenid

    -- FIXED: Replace optional chaining with proper Lua syntax
    local lotId = 0
    if filter and filter.lot_id then
        lotId = tonumber(filter.lot_id) or 0
    end

    local query, params
    if lotId and lotId > 0 then
        query = string.format([[ SELECT * FROM %s WHERE owner_cid = ? AND lot_id = ? ORDER BY id ASC ]], DB.livestock)
        params = { citizenid, lotId }
    else
        query = string.format([[ SELECT * FROM %s WHERE owner_cid = ? ORDER BY id ASC ]], DB.livestock)
        params = { citizenid }
    end
    local rows = oxmysql:executeSync(query, params)
    return true, rows or {}
end)

-- Buy animal for a specific lot
-- Expects: lot_id, animal_type
lib.callback.register('animal_farming:server:buyAnimal', function(source, data)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    local citizenid = player.PlayerData.citizenid
    
    -- FIXED: Replace optional chaining with proper Lua syntax
    local lotId = 0
    if data and data.lot_id then
        lotId = tonumber(data.lot_id) or 0
    end
    
    local atype = ''
    if data and data.animal_type then
        atype = tostring(data.animal_type)
    end

    local cfg = Config.Animals[atype]
    if not cfg then return false, 'invalid animal type' end

    -- Validate owned lot & type restriction
    local lot = oxmysql:executeSync(string.format([[
        SELECT * FROM %s WHERE id = ? AND citizenid = ?
    ]], DB.farmlots), { lotId, citizenid })

    if not lot or not lot[1] then
        return false, 'invalid lot or not owner'
    end
    lot = lot[1]
    if lot.lot_type ~= atype and (cfg.lotRestricted ~= false) then
        return false, 'lot type mismatch'
    end

    -- Optional: limit per lot
    if Config.MaxAnimalsPerLot and type(Config.MaxAnimalsPerLot) == 'number' then
        local cnt = oxmysql:scalarSync(string.format([[
            SELECT COUNT(*) FROM %s WHERE lot_id = ?
        ]], DB.livestock), { lotId }) or 0
        if cnt >= Config.MaxAnimalsPerLot then
            return false, 'lot animal limit reached'
        end
    end

    -- Money
    local price = tonumber(cfg.price or 0) or 0
    if price > 0 then
        if not player.Functions.RemoveMoney('cash', price, 'buy_animal') then
            return false, 'not enough cash'
        end
    end

    -- Gender roll
    local femaleChance = tonumber(cfg.femaleChance or 20) or 20
    local gender = (math.random(1,100) <= femaleChance) and 'female' or 'male'

    -- Base stats
    local stats = cfg.stats or {health=100,hunger=100,thirst=100}

    -- Insert animal
    local animalId = oxmysql:insertSync(string.format([[
        INSERT INTO %s (owner_cid, lot_id, animal_type, gender, health, hunger, thirst, spawned, coords)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, NULL)
    ]], DB.livestock), {
        citizenid, lotId, atype, gender,
        tonumber(stats.health or 100), tonumber(stats.hunger or 100), tonumber(stats.thirst or 100)
    })

    if not animalId then
        if price > 0 then player.Functions.AddMoney('cash', price, 'buy_animal_refund') end
        return false, 'db insert failed'
    end

    oxmysql:insert(string.format([[
        INSERT INTO %s (citizenid, `type`, ref_id, animal_type, amount)
        VALUES (?, 'buy_animal', ?, ?, ?)
    ]], DB.transactions), { citizenid, animalId, atype, price })

    debugPrint(('Player %s bought %s animal #%d on lot %d'):format(citizenid, atype, animalId, lotId))
    return true, { id = animalId, gender = gender, stats = stats }
end)

-- Enhanced feeding system with animations and progressive benefits
lib.callback.register('animal_farming:server:feedAnimal', function(source, animalId)
    local src = source
    local player = getPlayer(src)
    if not player then return false, 'player not found' end
    animalId = tonumber(animalId or 0) or 0
    if animalId <= 0 then return false, 'invalid animal id' end

    local citizenid = player.PlayerData.citizenid

    -- Verify ownership & alive
    local rows = oxmysql:executeSync(string.format([[
        SELECT id, owner_cid, is_dead, health, hunger, thirst FROM %s WHERE id = ?
    ]], DB.livestock), { animalId })
    if not rows or not rows[1] then return false, 'animal not found' end
    local a = rows[1]
    if a.owner_cid ~= citizenid then return false, 'not owner' end
    if a.is_dead == 1 then return false, 'animal is dead' end

    -- Check if animal is already at max hunger
    if (tonumber(a.hunger or 0) >= 95) then
        return false, 'animal is already full'
    end

    -- Remove feed item
    local removed = exports.ox_inventory:RemoveItem(src, Config.FeedItem or 'animal_feed', 1)
    if not removed then
        return false, 'missing animal feed'
    end

    -- Progressive feeding benefits based on animal type
    local cfg = Config.Animals[a.animal_type] or {}
    local feedingCfg = Config.Feeding or {}
    
    local baseHungerBoost = feedingCfg.hungerBoost or 40
    local baseHealthBoost = feedingCfg.healthBoost or 10
    
    -- Type-specific bonuses
    local typeBonus = cfg.feedingBonus or 1.0
    local hungerBoost = math.floor(baseHungerBoost * typeBonus)
    local healthBoost = math.floor(baseHealthBoost * typeBonus)

    local newHunger = math.min(100.0, (tonumber(a.hunger or 0) + hungerBoost))
    local newHealth = math.min(100.0, (tonumber(a.health or 0) + healthBoost))

    oxmysql:update(string.format([[
        UPDATE %s SET hunger = ?, health = ?, last_fed = NOW() WHERE id = ?
    ]], DB.livestock), { newHunger, newHealth, animalId })

    -- Log feeding activity
    oxmysql:insert(string.format([[
        INSERT INTO %s (animal_id, owner_cid, action, details)
        VALUES (?, ?, 'feed', ?)
    ]], 'animal_activity_log'), {
        animalId, citizenid, encode({hungerBoost = hungerBoost, healthBoost = healthBoost})
    })

    return true, { hunger = newHunger, health = newHealth }
end)

-- Enhanced product collection with quality system
lib.callback.register('animal_farming:server:collectProduct', function(source, animalId)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    animalId = tonumber(animalId or 0) or 0
    if animalId <= 0 then return false, 'invalid animal id' end
    local src = source
    local citizenid = player.PlayerData.citizenid

    local rows = oxmysql:executeSync(string.format([[
        SELECT * FROM %s WHERE id = ?
    ]], DB.livestock), { animalId })

    if not rows or not rows[1] then return false, 'not found' end
    local a = rows[1]
    if a.owner_cid ~= citizenid then return false, 'not owner' end
    if a.is_dead == 1 then return false, 'animal dead' end

    local atype = a.animal_type
    local cfg = Config.Animals[atype]
    if not cfg then return false, 'invalid type' end

    -- Enhanced requirements with quality scaling
    local req = Config.Requirements or { minHealth=50, minHunger=40, minThirst=40 }
    local currentHealth, currentHunger, currentThirst = tonumber(a.health or 0), tonumber(a.hunger or 0), tonumber(a.thirst or 0)
    
    if currentHealth < req.minHealth or currentHunger < req.minHunger or currentThirst < req.minThirst then
        return false, 'animal is not in condition'
    end

    -- Quality multiplier based on animal condition
    local qualityMultiplier = math.min(1.0, (currentHealth * 0.6 + currentHunger * 0.2 + currentThirst * 0.2) / 100)

    -- Determine product + cooldown
    local productItem, minY, maxY, cooldown
    if atype == 'cow' then
        if a.gender ~= 'female' then return false, 'male cows do not produce milk' end
        local p = cfg.products and cfg.products.female and cfg.products.female.milk
        if not p then return false, 'no product defined' end
        productItem = p.item or 'milk'
        minY, maxY = tonumber(p.minYield or 1), tonumber(p.maxYield or 1)
        cooldown = tonumber(p.cooldown or (3*24*60*60))
    elseif atype == 'chicken' then
        local p = cfg.products and cfg.products.eggs
        if not p then return false, 'no product defined' end
        productItem = p.item or 'eggs'
        minY, maxY = tonumber(p.minYield or 1), tonumber(p.maxYield or 1)
        cooldown = tonumber(p.cooldown or (30*60))
    elseif atype == 'pig' then
        local p = cfg.products and cfg.products.meat
        if not p then return false, 'no product defined' end
        productItem = p.item or 'raw_pork'
        minY, maxY = tonumber(p.minYield or 1), tonumber(p.maxYield or 1)
        cooldown = tonumber(p.cooldown or (2*60*60))
    else
        return false, 'no product for this animal'
    end

    -- Cooldown check
    local last = a.last_product
    if last then
        local secondsSince = oxmysql:scalarSync('SELECT TIMESTAMPDIFF(SECOND, ?, NOW())', { last }) or 0
        if secondsSince < cooldown then
            local remain = cooldown - secondsSince
            return false, ('cooldown: %ds remaining'):format(remain)
        end
    end

    -- Quality-based yield calculation
    local baseAmount = math.random(minY, maxY)
    local qualityAmount = math.floor(baseAmount * qualityMultiplier)
    local amount = math.max(1, qualityAmount)

    -- Give item with quality metadata
    local metadata = {
        quality = math.floor(qualityMultiplier * 100),
        source = ('%s_%s'):format(atype, a.gender),
        collected = os.date('%Y-%m-%d %H:%M:%S')
    }

    local added = exports.ox_inventory:AddItem(src, productItem, amount, metadata)
    if not added then
        return false, 'inventory full'
    end

    -- Update last_product + log with quality info
    oxmysql:update(string.format([[
        UPDATE %s SET last_product = NOW() WHERE id = ?
    ]], DB.livestock), { animalId })

    oxmysql:insert(string.format([[
        INSERT INTO %s (animal_id, owner_cid, product, amount, quality, at_health, at_hunger, at_thirst)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], DB.production_log), { 
        animalId, citizenid, productItem, amount, math.floor(qualityMultiplier * 100), 
        currentHealth, currentHunger, currentThirst 
    })

    return true, { 
        item = productItem, 
        amount = amount, 
        quality = math.floor(qualityMultiplier * 100) 
    }
end)

-- Enhanced butchering system with skill-based yields
lib.callback.register('animal_farming:server:butcherAnimal', function(source, animalId, skillLevel)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    animalId = tonumber(animalId or 0) or 0
    if animalId <= 0 then return false, 'invalid animal id' end

    local src = source
    local citizenid = player.PlayerData.citizenid

    local rows = oxmysql:executeSync(string.format([[
        SELECT * FROM %s WHERE id = ?
    ]], DB.livestock), { animalId })
    if not rows or not rows[1] then return false, 'not found' end
    local a = rows[1]
    if a.owner_cid ~= citizenid then return false, 'not owner' end
    if tonumber(a.is_dead or 0) ~= 1 then return false, 'animal must be dead' end

    -- Check knife
    local required = (Config.Butchering and Config.Butchering.requiredItem) or 'knife'
    if exports.ox_inventory:GetItem(src, required, false, true) < 1 then
        return false, 'missing knife'
    end

    local byType = Config.Butchering and Config.Butchering.yields and Config.Butchering.yields[a.animal_type]
    if not byType then return false, 'no yield configured' end

    -- Skill-based yield calculation
    local skillMultiplier = math.min(2.0, 1.0 + (tonumber(skillLevel or 0) * 0.1))
    local baseMin, baseMax = tonumber(byType.min or 1), tonumber(byType.max or 1)
    local minY = math.floor(baseMin * skillMultiplier)
    local maxY = math.floor(baseMax * skillMultiplier)
    
    local item = byType.item or 'raw_meat'
    local amount = math.random(minY, maxY)
    if amount <= 0 then amount = 1 end

    -- Quality metadata based on skill
    local metadata = {
        butcher_skill = tonumber(skillLevel or 0),
        source = a.animal_type,
        butchered = os.date('%Y-%m-%d %H:%M:%S')
    }

    -- Give item
    local ok = exports.ox_inventory:AddItem(src, item, amount, metadata)
    if not ok then return false, 'inventory full' end

    -- Log & cleanup
    oxmysql:insert(string.format([[
        INSERT INTO %s (animal_id, owner_cid, cause, by_cid, yields_json, skill_level)
        VALUES (?, ?, 'butchered', ?, ?, ?)
    ]], DB.death_log), { 
        animalId, citizenid, citizenid, encode({ item = item, amount = amount }), skillLevel 
    })

    -- Remove from active table
    oxmysql:execute(string.format('DELETE FROM %s WHERE id = ?', DB.livestock), { animalId })

    debugPrint(('Player %s butchered animal #%d yielding %dx %s (skill: %d)'):format(citizenid, animalId, amount, item, skillLevel))
    return true, { item = item, amount = amount, skill = skillLevel }
end)

-- Animal status monitoring system
lib.callback.register('animal_farming:server:getAnimalStatus', function(source, animalId)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    animalId = tonumber(animalId or 0) or 0
    if animalId <= 0 then return false, 'invalid animal id' end

    local citizenid = player.PlayerData.citizenid

    local rows = oxmysql:executeSync(string.format([[
        SELECT * FROM %s WHERE id = ? AND owner_cid = ?
    ]], DB.livestock), { animalId, citizenid })
    
    if not rows or not rows[1] then return false, 'not found or not owner' end
    local animal = rows[1]

    -- Calculate status indicators
    local status = 'healthy'
    local health, hunger, thirst = tonumber(animal.health or 0), tonumber(animal.hunger or 0), tonumber(animal.thirst or 0)
    
    if health < 30 then status = 'critical'
    elseif health < 60 then status = 'sick'
    elseif hunger < 30 or thirst < 30 then status = 'neglected'
    end

    -- Calculate time since last fed/produced
    local lastFed = animal.last_fed and oxmysql:scalarSync('SELECT TIMESTAMPDIFF(MINUTE, ?, NOW())', { animal.last_fed }) or 'unknown'
    local lastProduct = animal.last_product and oxmysql:scalarSync('SELECT TIMESTAMPDIFF(MINUTE, ?, NOW())', { animal.last_product }) or 'unknown'

    return true, {
        status = status,
        health = health,
        hunger = hunger,
        thirst = thirst,
        gender = animal.gender,
        lastFed = lastFed,
        lastProduct = lastProduct,
        isDead = tonumber(animal.is_dead or 0) == 1
    }
end)

-- Bulk operations for multiple animals
lib.callback.register('animal_farming:server:bulkFeedAnimals', function(source, lotId)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    local citizenid = player.PlayerData.citizenid
    lotId = tonumber(lotId or 0) or 0

    -- Get all animals in the lot that need feeding
    local animals = oxmysql:executeSync(string.format([[
        SELECT id, hunger FROM %s 
        WHERE owner_cid = ? AND lot_id = ? AND is_dead = 0 AND hunger < 90
    ]], DB.livestock), { citizenid, lotId }) or {}

    if #animals == 0 then
        return false, 'no animals need feeding'
    end

    -- Calculate required feed
    local feedNeeded = #animals
    local feedAvailable = exports.ox_inventory:GetItem(source, Config.FeedItem or 'animal_feed', false, true) or 0

    if feedAvailable < feedNeeded then
        return false, ('need %d feed, only have %d'):format(feedNeeded, feedAvailable)
    end

    -- Remove feed items
    local removed = exports.ox_inventory:RemoveItem(source, Config.FeedItem or 'animal_feed', feedNeeded)
    if not removed then
        return false, 'failed to remove feed'
    end

    -- Feed all animals
    local fedCount = 0
    for _, animal in ipairs(animals) do
        local newHunger = math.min(100, tonumber(animal.hunger or 0) + (Config.Feeding.hungerBoost or 40))
        oxmysql:update(string.format([[
            UPDATE %s SET hunger = ?, last_fed = NOW() WHERE id = ?
        ]], DB.livestock), { newHunger, animal.id })
        fedCount = fedCount + 1
    end

    return true, { fedCount = fedCount, feedUsed = feedNeeded }
end)

-- Admin management system
lib.callback.register('animal_farming:server:adminGetAllAnimals', function(source)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    
    -- Add admin check here
    -- if not IsPlayerAceAllowed(source, 'animal_farming.admin') then return false, 'no permission' end

    local rows = oxmysql:executeSync(string.format([[
        SELECT l.*, f.label as farm_name, f.citizenid as owner_citizenid 
        FROM %s l 
        LEFT JOIN %s f ON l.lot_id = f.id 
        ORDER BY l.owner_cid, l.lot_id
    ]], DB.livestock, DB.farmlots))

    return true, rows or {}
end)

-- Admin: heal all animals in a lot
lib.callback.register('animal_farming:server:adminHealLot', function(source, lotId)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    
    -- Add admin check here
    lotId = tonumber(lotId or 0) or 0

    local affected = oxmysql:update(string.format([[
        UPDATE %s 
        SET health = 100, hunger = 100, thirst = 100, updated_at = NOW() 
        WHERE lot_id = ? AND is_dead = 0
    ]], DB.livestock), { lotId })

    return true, { affected = affected }
end)

-- ============================
--   LOGIN / LOGOUT HANDLERS
-- ============================

-- On player loaded: mark their animals as "should spawn" and send to client to spawn.
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    -- FIXED: Replace optional chaining with proper Lua syntax
    local citizenid
    if Player and Player.PlayerData and Player.PlayerData.citizenid then
        citizenid = Player.PlayerData.citizenid
    end
    if not citizenid then return end

    -- Get animals to spawn (owned & alive)
    local animals = oxmysql:executeSync(string.format([[
        SELECT * FROM %s WHERE owner_cid = ? AND is_dead = 0
    ]], DB.livestock), { citizenid }) or {}

    -- Mark spawned flag false (client will flip true as they spawn them)
    oxmysql:update(string.format([[
        UPDATE %s SET spawned = 0 WHERE owner_cid = ? AND is_dead = 0
    ]], DB.livestock), { citizenid })

    debugPrint(('Player %s loaded with %d animals'):format(citizenid, #animals))

    -- Let client handle actual entity spawn
    local src = Player.PlayerData.source
    TriggerClientEvent('animal_farming:client:spawnOwnedAnimals', src, animals)
end)

-- On player unload: mark animals spawned=0 (client should despawn entities)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    local player = getPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid
    oxmysql:update(string.format([[
        UPDATE %s SET spawned = 0 WHERE owner_cid = ?
    ]], DB.livestock), { citizenid })
    debugPrint(('Player %s unloaded; animals marked unspawned'):format(citizenid))
end)

-- Client informs server when a specific animal has been successfully spawned/despawned client-side
RegisterNetEvent('animal_farming:server:setSpawned', function(animalId, spawned, coords)
    local src = source
    local player = getPlayer(src)
    if not player then return end
    animalId = tonumber(animalId or 0) or 0
    if animalId <= 0 then return end

    -- quick ownership check
    local rows = oxmysql:executeSync(string.format('SELECT owner_cid FROM %s WHERE id = ?', DB.livestock), { animalId })
    if not rows or not rows[1] then return end
    if rows[1].owner_cid ~= player.PlayerData.citizenid then return end

    oxmysql:update(string.format([[
        UPDATE %s SET spawned = ?, coords = ?, updated_at = NOW() WHERE id = ?
    ]], DB.livestock), { (spawned and 1 or 0), coords and encode(coords) or nil, animalId })
end)

-- ============================
--   STATS DECAY + WATER TROUGH
-- ============================

-- Enhanced stat decay system with environmental factors
CreateThread(function()
    while true do
        Wait(60 * 1000)

        local hdec = (Config.StatDecay and tonumber(Config.StatDecay.hunger or 1)) or 1
        local tdec = (Config.StatDecay and tonumber(Config.StatDecay.thirst or 1)) or 1
        local hldec = (Config.StatDecay and tonumber(Config.StatDecay.health or 0.5)) or 0.5

        -- Environmental factors (season/weather could be implemented here)
        local weatherMultiplier = 1.0 -- Could be adjusted based on server weather

        -- Hunger/thirst drop with environmental factors
        oxmysql:execute(string.format([[
            UPDATE %s
            SET hunger = GREATEST(hunger - ?, 0),
                thirst = GREATEST(thirst - ?, 0),
                updated_at = NOW()
            WHERE is_dead = 0
        ]], DB.livestock), { hdec * weatherMultiplier, tdec * weatherMultiplier })

        -- Health decay where needed
        oxmysql:execute(string.format([[
            UPDATE %s
            SET health = GREATEST(health - ?, 0),
                updated_at = NOW()
            WHERE is_dead = 0 AND (hunger <= 0 OR thirst <= 0)
        ]], DB.livestock), { hldec * weatherMultiplier })

        -- Mark animals dead (health <= 0)
        local deadIds = oxmysql:executeSync(string.format([[
            SELECT id, owner_cid FROM %s WHERE is_dead = 0 AND health <= 0
        ]], DB.livestock))
        if deadIds and #deadIds > 0 then
            local ids = {}
            for _, r in ipairs(deadIds) do ids[#ids+1] = r.id end
            oxmysql:execute(string.format('UPDATE %s SET is_dead = 1 WHERE id IN (%s)', DB.livestock, table.concat(ids, ',')))
            for _, r in ipairs(deadIds) do
                oxmysql:insert(string.format([[
                    INSERT INTO %s (animal_id, owner_cid, cause)
                    VALUES (?, ?, 'neglect')
                ]], DB.death_log), { r.id, r.owner_cid })
            end
            debugPrint(('Marked %d animals as dead due to neglect'):format(#deadIds))
        end

        -- Water trough: passive hydration tick
        if Config.WaterTrough and Config.WaterTrough.enabled then
            local boost = tonumber(Config.WaterTrough.hydrationBoost or 5) or 5
            local every = tonumber(Config.WaterTrough.tickInterval or 60) or 60
            if every == 60 then
                oxmysql:execute(string.format([[
                    UPDATE %s l
                    JOIN %s t ON t.lot_id = l.lot_id
                    SET l.thirst = LEAST(l.thirst + ?, 100),
                        l.updated_at = NOW()
                    WHERE l.is_dead = 0 AND t.water_level > 0
                ]], DB.livestock, DB.water), { boost })

                oxmysql:execute(string.format([[
                    UPDATE %s SET water_level = GREATEST(water_level - 1, 0), last_refilled = NOW()
                    WHERE water_level > 0
                ]], DB.water))
            end
        end
    end
end)

-- ============================
--   TROUGH MANAGEMENT
-- ============================

-- Get/Set troughs per lot
lib.callback.register('animal_farming:server:getTroughs', function(source, lotId)
    lotId = tonumber(lotId or 0) or 0
    if lotId <= 0 then return true, {} end
    local rows = oxmysql:executeSync(string.format('SELECT * FROM %s WHERE lot_id = ?', DB.water), { lotId }) or {}
    return true, rows
end)

lib.callback.register('animal_farming:server:placeTrough', function(source, lotId, coords)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    local citizenid = player.PlayerData.citizenid
    lotId = tonumber(lotId or 0) or 0
    if lotId <= 0 then return false, 'invalid lot' end

    -- Ownership check
    local lot = oxmysql:executeSync(string.format('SELECT * FROM %s WHERE id = ? AND citizenid = ?', DB.farmlots), { lotId, citizenid })
    if not lot or not lot[1] then return false, 'not your lot' end

    -- Check max troughs per lot
    local troughCount = oxmysql:scalarSync(string.format('SELECT COUNT(*) FROM %s WHERE lot_id = ?', DB.water), { lotId }) or 0
    if troughCount >= (Config.MaxTroughsPerLot or 3) then
        return false, 'max troughs reached for this lot'
    end

    local id = oxmysql:insertSync(string.format('INSERT INTO %s (lot_id, coords, water_level) VALUES (?, ?, 100)', DB.water), { lotId, encode(coords) })
    if not id then return false, 'db failed' end
    return true, { id = id, water_level = 100 }
end)

RegisterNetEvent('animal_farming:server:refillTrough', function(troughId, amount)
    local src = source
    local player = getPlayer(src)
    if not player then return end

    troughId = tonumber(troughId or 0) or 0
    local amt = tonumber(amount or 100) or 100
    if troughId <= 0 then return end

    oxmysql:execute(string.format([[
        UPDATE %s SET water_level = LEAST(water_level + ?, 100), last_refilled = NOW() WHERE id = ?
    ]], DB.water), { amt, troughId })
end)

-- ============================
--   ADMIN / DEBUG COMMANDS
-- ============================

lib.addCommand('af_list', {
    help = 'List your animals',
}, function(source, args)
    local player = getPlayer(source)
    if not player then return end
    local ok, animals = lib.callback.await('animal_farming:server:getAnimals', source, {})
    if not ok then
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = tostring(animals) })
        return
    end
    TriggerClientEvent('ox_lib:notify', source, { type = 'inform', description = ('You have %d animals.'):format(#animals) })
end)

lib.addCommand('af_stats', {
    help = 'Check animal stats',
}, function(source, args)
    local player = getPlayer(source)
    if not player then return end
    -- Implementation for checking specific animal stats
end)

-- ============================
--   SAFETY GUARDS
-- ============================

-- Ensure config defaults exist to avoid nil issues
Config.Feeding = Config.Feeding or { hungerBoost = 40, healthBoost = 10, animationTime = 5 }
Config.Requirements = Config.Requirements or { minHealth = 50, minHunger = 40, minThirst = 40 }
Config.WaterTrough = Config.WaterTrough or { enabled = true, hydrationBoost = 5, tickInterval = 60 }
Config.StatDecay = Config.StatDecay or { hunger = 1, thirst = 1, health = 0.5 }
Config.Butchering = Config.Butchering or { requiredItem = 'knife', yields = {} }
Config.MaxTroughsPerLot = Config.MaxTroughsPerLot or 3

-- Initialize database tables if they don't exist
CreateThread(function()
    Wait(5000) -- Wait for resources to load
    debugPrint('Initializing animal farming database...')
    -- You could add table creation queries here if needed
end)

-- Emergency recovery system for stuck animals
lib.callback.register('animal_farming:server:recoverAnimals', function(source)
    local player = getPlayer(source)
    if not player then return false, 'player not found' end
    local citizenid = player.PlayerData.citizenid

    local recovered = oxmysql:update(string.format([[
        UPDATE %s SET spawned = 0 WHERE owner_cid = ? AND spawned = 1
    ]], DB.livestock), { citizenid })

    return true, { recovered = recovered }
end)