-- Bus Job Settings Configuration
local Settings = {
    -- Passenger Management
    PASSENGERS_FOR_LOCATION_TRIGGER = 30, -- After serving 30 passengers, trigger location
    PASSENGER_PAYMENT = 10, -- $10 per passenger
    MAX_PASSENGERS_PER_BUS = 10,
    
    -- Timing Settings
    NPC_SPAWN_INTERVAL = 15000, -- 15 seconds between NPC spawns
    BOARDING_TIMEOUT = 15000, -- 15 seconds for passenger boarding
    SEATING_TIMEOUT = 10000, -- 10 seconds for passenger seating
    DROPOFF_WAIT_TIME = 180000, -- 3 minutes wait after dropoff before new pickup
    
    -- Distance Settings
    PICKUP_RADIUS = 20.0,
    DROPOFF_RADIUS = 30.0,
    STATION_RADIUS = 15.0,
    
    -- Payment Settings
    BASE_PAYMENT = 0, -- No base payment, only passenger payment
    PASSENGER_BONUS = 10, -- $10 per passenger
    LOCATION_BONUS = 500, -- Bonus when reaching 30 passengers milestone
    
    -- Vehicle Settings
    FUEL_LEVEL = 100.0,
    AUTO_START_ENGINE = true,
    GIVE_VEHICLE_KEYS = true,
    
    -- NPC Cleanup
    NPC_REMOVAL_DELAY = 30000, -- 30 seconds after dropoff
    
    -- Blip Settings
    PICKUP_BLIP_COLOR = 3, -- Yellow
    DROPOFF_BLIP_COLOR = 1, -- Red
    DEPOT_BLIP_COLOR = 49, -- Blue
    
    -- Debug
    DEBUG_NOTIFICATIONS = true,
    DEBUG_CONSOLE_LOGS = false
}

return Settings