-- shared/config.lua

Config = {}

-- 🔧 Debug Settings
Config.Debug = false -- true = enable console logging

-- 🏡 Farmlot Ownership
Config.MaxFarmlotsPerPlayer = false -- false = unlimited
Config.FarmlotSellers = {
    {
        name = "Farmlot Manager",
        model = "a_m_m_farmer_01",
        coords = vec4(2308.5225, 4882.7617, 41.8083, 45.7139),
        price = 5000,
        lotType = "cow"
    }
}

-- 🐄 Animal Vendors
Config.AnimalVendors = {
    {
        name = "Animal Vendor",
        model = "a_m_m_farmer_01",
        coords = vec4(2320.2, 4885.6, 40.2, 180.0)
    }
}

-- 🐖🐄🐔 Animal Management
Config.Animals = {
    cow = {
        label = "Cow",
        model = `a_c_cow`,
        price = 1500,
        spawnDelay = {10, 15}, -- seconds (min, max)
        lotRestricted = true, -- cow-only lot
        femaleChance = 20, -- % chance female
        wanderDistance = 15.0,
        blip = 141,
        stats = {health = 100, hunger = 100, thirst = 100},
        products = {
            female = {
                milk = {
                    item = "milk",
                    cooldown = 3 * 24 * 60 * 60, -- 3 days
                    minYield = 1,
                    maxYield = 3
                }
            }
        }
    },
    pig = {
        label = "Pig",
        model = `a_c_pig`,
        price = 1000,
        spawnDelay = {10, 15},
        lotRestricted = true,
        femaleChance = 20,
        wanderDistance = 10.0,
        blip = 141,
        stats = {health = 100, hunger = 100, thirst = 100},
        products = {
            meat = {
                item = "raw_pork",
                cooldown = 2 * 60 * 60, -- 2 hours
                minYield = 1,
                maxYield = 2
            }
        }
    },
    chicken = {
        label = "Chicken",
        model = `a_c_hen`,
        price = 500,
        spawnDelay = {10, 15},
        lotRestricted = true,
        femaleChance = 50,
        wanderDistance = 8.0,
        blip = 141,
        stats = {health = 100, hunger = 100, thirst = 100},
        products = {
            eggs = {
                item = "eggs",
                cooldown = 30 * 60, -- 30 minutes
                minYield = 1,
                maxYield = 4
            }
        }
    }
}

-- 📊 Animal Stats System
Config.StatDecay = {
    hunger = 1,   -- hunger loss per minute
    thirst = 1,   -- thirst loss per minute
    health = 0.5  -- health loss per minute if hunger/thirst is 0
}

-- Optional 3D Status Display
Config.Status3D = true
Config.ShowAnimalStatus = true

-- Optional roaming AI inside lot
Config.WanderingAI = true

-- 🍎 Feeding System
Config.FeedItem = "animal_feed"
Config.Feeding = {
    hungerBoost = 40, -- how much hunger is restored
    healthBoost = 10, -- how much health is restored
    animationTime = 5 -- seconds
}

-- 🚰 Water Trough System
Config.WaterTrough = {
    enabled = true,
    hydrationBoost = 5, -- thirst restored per tick
    tickInterval = 60 -- every 60 seconds
}

-- 🥛 Product Collection Conditions
Config.Requirements = {
    minHealth = 50,
    minHunger = 40,
    minThirst = 40
}

-- 🔪 Butchering System
Config.Butchering = {
    enabled = true,
    requiredItem = "knife",
    minigameTime = 30, -- seconds
    yields = {
        cow = { item = "raw_meat", min = 2, max = 5 },
        pig = { item = "raw_pork", min = 2, max = 4 },
        chicken = { item = "raw_meat", min = 1, max = 2 }
    }
}

-- 🎯 ox_target Settings
Config.Target = {
    distance = 2.5
}

-- 🗄️ Database Tables
Config.Database = {
    farmlots = "animal_farmlots",
    livestock = "animal_livestock",
    water = "animal_water_troughs",
    transactions = "animal_transactions",
    production_log = "animal_production_log",
    death_log = "animal_death_log"
}

-- 👨‍💻 Admin Settings
Config.Admin = {
    canForceDespawn = true,
    canForceSpawn = true
}

-- Limits
Config.MaxAnimalsPerLot = 10
Config.MaxTroughsPerLot = 3