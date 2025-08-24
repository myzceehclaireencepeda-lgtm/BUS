local config = require 'config.client'
local sharedConfig = require 'config.shared'
local settings = require 'settings'

-- State management
local State = {
    busBlip = nil,
    vehicleZone = nil,
    deliverZone = nil,
    pickupZone = nil,
    jobNpc = nil,
    exitNpc = nil
}

-- Enhanced job data structure with better organization
local BusJob = {
    -- Job status
    IsSideJob = true,
    IsActive = false,
    OnRoute = false,
    
    -- Location tracking
    CurrentPickupLocation = nil,
    CurrentDropoffLocation = nil,
    
    -- Passenger management
    Npcs = {},
    MaxPassengers = settings.MAX_PASSENGERS_PER_BUS,
    CurrentPassengers = 0,
    PassengersServed = 0,
    SpawnedNpcs = 0,
    WaitingForPassengers = false,
    BusFull = false,
    
    -- New milestone tracking
    PassengersServedSinceLastLocation = 0,
    LocationTriggered = false,
    
    -- Blip management
    NpcBlip = nil,
    DeliveryBlip = nil,
    
    -- Economy
    CurrentPay = 0,
    
    -- Timing
    StartTime = 0,
    NpcSpawnTimer = 0,
    DropoffWaitTimer = 0,
    WaitingForNewPickup = false,
    
    -- Constants from settings
    NPC_SPAWN_INTERVAL = settings.NPC_SPAWN_INTERVAL,
    PICKUP_RADIUS = settings.PICKUP_RADIUS,
    DROPOFF_RADIUS = settings.DROPOFF_RADIUS,
    STATION_RADIUS = settings.STATION_RADIUS,
    BOARDING_TIMEOUT = settings.BOARDING_TIMEOUT,
    SEATING_TIMEOUT = settings.SEATING_TIMEOUT,
    BASE_PAYMENT = settings.BASE_PAYMENT,
    PASSENGER_BONUS = settings.PASSENGER_BONUS,
    DROPOFF_WAIT_TIME = settings.DROPOFF_WAIT_TIME
}

local BusData = {
    Active = false,
}

-- Walking locations near each station where NPCs will come from
local walkingLocations = {
    [1] = { -- For station 1
        vec4(320.36, -750.56, 29.31, 252.09),
        vec4(310.36, -755.56, 29.31, 252.09),
        vec4(315.36, -760.56, 29.31, 252.09)
    },
    [2] = { -- For station 2
        vec4(-100.31, -1670.29, 29.31, 223.84),
        vec4(-105.31, -1675.29, 29.31, 223.84),
        vec4(-110.31, -1680.29, 29.31, 223.84)
    },
    [3] = { -- For station 3
        vec4(-700.83, -814.56, 23.54, 194.7),
        vec4(-705.83, -819.56, 23.54, 194.7),
        vec4(-710.83, -824.56, 23.54, 194.7)
    },
    [4] = { -- For station 4
        vec4(-682.63, -660.44, 30.86, 61.84),
        vec4(-687.63, -665.44, 30.86, 61.84),
        vec4(-692.63, -670.44, 30.86, 61.84)
    },
    [5] = { -- For station 5
        vec4(-240.14, -876.78, 30.63, 8.67),
        vec4(-245.14, -881.78, 30.63, 8.67),
        vec4(-250.14, -886.78, 30.63, 8.67)
    }
}

-- NPC Models for job manager
local jobNpcModels = {
    'a_m_m_business_01',
    'a_m_y_business_01',
    'a_m_y_business_02',
    's_m_m_cntrybar_01'
}

-- Utility Functions
local function safeDeleteEntity(entity)
    if DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, false, true)
        DeleteEntity(entity)
        return true
    end
    return false
end

local function safeRemoveBlip(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
        return true
    end
    return false
end

local function getDistance(pos1, pos2)
    return #(vector3(pos1.x or pos1[1], pos1.y or pos1[2], pos1.z or pos1[3]) - 
             vector3(pos2.x or pos2[1], pos2.y or pos2[2], pos2.z or pos2[3]))
end

local function isValidVehicle(vehicle)
    return vehicle and DoesEntityExist(vehicle) and not IsEntityDead(vehicle)
end

-- Core Functions
local function resetJobState()
    -- Clean up NPCs with better error handling
    for i, npc in pairs(BusJob.Npcs) do
        if safeDeleteEntity(npc) then
            BusJob.Npcs[i] = nil
        end
    end
    
    -- Reset route state but keep milestone tracking
    BusJob.Npcs = {}
    BusJob.CurrentPassengers = 0
    BusJob.WaitingForPassengers = false
    BusJob.BusFull = false
    BusJob.SpawnedNpcs = 0
    BusJob.NpcSpawnTimer = 0
    BusJob.OnRoute = false
    BusJob.CurrentPickupLocation = nil
    BusJob.CurrentDropoffLocation = nil
    BusJob.WaitingForNewPickup = false
    BusJob.DropoffWaitTimer = 0
end

local function removeBusBlip()
    if safeRemoveBlip(State.busBlip) then
        State.busBlip = nil
    end
end

local function removeNPCBlips()
    if safeRemoveBlip(BusJob.DeliveryBlip) then
        BusJob.DeliveryBlip = nil
    end
    
    if safeRemoveBlip(BusJob.NpcBlip) then
        BusJob.NpcBlip = nil
    end
end

local function createBlip(coords, sprite, color, text, isRoute)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    if not blip then return nil end
    
    SetBlipSprite(blip, sprite or 1)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.6)
    SetBlipAsShortRange(blip, true)
    SetBlipColour(blip, color or 0)
    
    if isRoute then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, color or 0)
    end
    
    if text then
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandSetBlipName(blip)
    end
    
    return blip
end

local function updateMainBlip()
    if not State.busBlip then
        local coords = sharedConfig.location
        State.busBlip = createBlip(coords, 513, settings.DEPOT_BLIP_COLOR, "Bus Depot (Side Job)", false)
    end
end

local function isPlayerVehicleABus()
    if not cache.vehicle then return false end
    local model = GetEntityModel(cache.vehicle)

    -- Check configured vehicles
    for _, vehicle in ipairs(config.allowedVehicles) do
        if model == vehicle.model then
            return true
        end
    end

    -- Check dynasty model
    return model == joaat('dynasty')
end

local function getRandomLocation()
    return math.random(1, #sharedConfig.npcLocations.locations)
end

local function getDifferentLocation(currentLocation)
    if #sharedConfig.npcLocations.locations <= 1 then
        return currentLocation
    end
    
    local newLocation
    repeat
        newLocation = getRandomLocation()
    until newLocation ~= currentLocation
    
    return newLocation
end

local function scheduleNPCRemoval(ped, delay)
    delay = delay or settings.NPC_REMOVAL_DELAY
    SetTimeout(delay, function()
        safeDeleteEntity(ped)
    end)
end

local function showEarningsSummary()
    local timeWorked = math.floor((GetGameTimer() - BusJob.StartTime) / 60000)
    lib.notify({
        title = 'Bus Job Summary',
        description = string.format('Served %d passengers, earned $%d in %d minutes', 
                                   BusJob.PassengersServed, BusJob.CurrentPay, timeWorked),
        type = 'success',
        duration = 8000
    })
end

-- Check if milestone reached for location trigger
local function checkMilestone()
    if BusJob.PassengersServedSinceLastLocation >= settings.PASSENGERS_FOR_LOCATION_TRIGGER and not BusJob.LocationTriggered then
        BusJob.LocationTriggered = true
        BusJob.PassengersServedSinceLastLocation = 0
        
        -- Give location bonus
        BusJob.CurrentPay = BusJob.CurrentPay + settings.LOCATION_BONUS
        
        lib.notify({
            title = 'Milestone Achieved!',
            description = string.format('Served %d passengers! Bonus: $%d. New pickup location incoming!', 
                                       settings.PASSENGERS_FOR_LOCATION_TRIGGER, settings.LOCATION_BONUS),
            type = 'success',
            duration = 10000
        })
        
        -- Trigger new route after current passengers are dropped off
        if not BusJob.OnRoute then
            SetTimeout(2000, function()
                if BusJob.IsActive then
                    startNewRoute()
                end
            end)
        end
    end
end

local function dropOffPassengers()
    if not isValidVehicle(cache.vehicle) then return end
    
    local destination = sharedConfig.npcLocations.locations[BusJob.CurrentDropoffLocation]
    local inRange = false
    local shownTextUI = false
    
    if State.deliverZone then
        State.deliverZone:remove()
    end
    
    State.deliverZone = lib.zones.sphere({
        name = "qbx_busjob_bus_deliver",
        coords = vec3(destination.x, destination.y, destination.z),
        radius = BusJob.STATION_RADIUS,
        debug = config.debugPoly,
        onEnter = function()
            inRange = true
            if not shownTextUI then
                lib.showTextUI('[E] - Drop Off Passengers')
                shownTextUI = true
            end
            
            CreateThread(function()
                while inRange do
                    if IsControlJustPressed(0, 38) then
                        -- Calculate payment ($10 per passenger)
                        local payment = BusJob.CurrentPassengers * settings.PASSENGER_PAYMENT
                        
                        -- Process passenger exit
                        local exitedCount = 0
                        for i, npc in pairs(BusJob.Npcs) do
                            if DoesEntityExist(npc) and IsPedInVehicle(npc, cache.vehicle, false) then
                                TaskLeaveVehicle(npc, cache.vehicle, 0)
                                exitedCount = exitedCount + 1
                                
                                -- Schedule walking away and cleanup
                                SetTimeout(2000, function()
                                    if DoesEntityExist(npc) then
                                        local walkTarget = vector3(
                                            destination.x + math.random(-10, 10),
                                            destination.y + math.random(-10, 10),
                                            destination.z
                                        )
                                        TaskGoStraightToCoord(npc, walkTarget.x, walkTarget.y, walkTarget.z, 1.0, -1, 0.0, 0.0)
                                        scheduleNPCRemoval(npc, 30000)
                                    end
                                end)
                            else
                                safeDeleteEntity(npc)
                            end
                            BusJob.Npcs[i] = nil
                        end
                        
                        -- Update earnings and passenger tracking
                        BusJob.CurrentPay = BusJob.CurrentPay + payment
                        BusJob.PassengersServed = BusJob.PassengersServed + exitedCount
                        BusJob.PassengersServedSinceLastLocation = BusJob.PassengersServedSinceLastLocation + exitedCount
                        
                        lib.notify({
                            title = 'Bus Job',
                            description = string.format('Dropped off %d passengers! Earned $%d', exitedCount, payment),
                            type = 'success'
                        })
                        
                        -- Check milestone achievement
                        checkMilestone()
                        
                        -- Clean up current route
                        removeNPCBlips()
                        resetJobState()
                        
                        -- Start waiting period before new pickup
                        BusJob.WaitingForNewPickup = true
                        BusJob.DropoffWaitTimer = GetGameTimer()
                        
                        lib.notify({
                            title = 'Bus Job',
                            description = string.format('Waiting %d minutes before next pickup location...', 
                                                       settings.DROPOFF_WAIT_TIME / 60000),
                            type = 'info',
                            duration = 5000
                        })
                        
                        lib.hideTextUI()
                        shownTextUI = false
                        inRange = false
                        State.deliverZone:remove()
                        State.deliverZone = nil
                        break
                    end
                    Wait(0)
                end
            end)
        end,
        onExit = function()
            lib.hideTextUI()
            shownTextUI = false
            inRange = false
        end
    })
end

-- NPC Creation and Management
local function createJobNPC()
    if State.jobNpc and DoesEntityExist(State.jobNpc) then
        return State.jobNpc
    end
    
    local coords = sharedConfig.location
    local model = joaat(jobNpcModels[math.random(1, #jobNpcModels)])
    
    if not lib.requestModel(model, 5000) then
        return nil
    end
    
    State.jobNpc = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetModelAsNoLongerNeeded(model)
    
    if not DoesEntityExist(State.jobNpc) then
        return nil
    end
    
    -- Configure NPC
    FreezeEntityPosition(State.jobNpc, true)
    SetEntityInvincible(State.jobNpc, true)
    SetBlockingOfNonTemporaryEvents(State.jobNpc, true)
    SetPedCanPlayAmbientAnims(State.jobNpc, true)
    SetPedCanRagdollFromPlayerImpact(State.jobNpc, false)
    SetEntityAsMissionEntity(State.jobNpc, true, true)
    
    return State.jobNpc
end

local function showBusGarage()
    if not BusJob.IsActive then
        lib.notify({
            title = 'Bus Job',
            description = 'You need to start the bus job first!',
            type = 'error'
        })
        return
    end

    -- Generate the menu options
    local vehicleMenu = {
        {
            title = 'Coach Bus',
            description = 'Large capacity bus - comes with keys',
            icon = 'bus',
            onSelect = function()
                TriggerEvent("qbx_busjob:client:TakeVehicle", { model = "coach" })
            end
        },
        
    }

    lib.registerContext({
        id = 'qbx_busjob_garage_menu',
        title = 'Bus Garage',
        options = vehicleMenu
    })

    lib.showContext('qbx_busjob_garage_menu')
end

local function setupJobNPCTargets()
    local npc = createJobNPC()
    if not npc then return end
    
    -- Remove existing targets first to prevent warnings
    if State.jobNpc then
        exports.ox_target:removeLocalEntity(State.jobNpc)
    end
    
    exports.ox_target:addLocalEntity(npc, {
        {
            name = 'bus_job_start',
            icon = 'fas fa-bus',
            label = BusJob.IsActive and 'End Bus Job' or 'Start Bus Job',
            onSelect = function()
                if BusJob.IsActive then
                    -- Confirmation para mag-end ng job
                    local alert = lib.alertDialog({
                        header = 'End Bus Job',
                        content = 'Are you sure you want to end the bus job?',
                        centered = true,
                        cancel = true,
                        labels = {
                            confirm = 'Yes, End Job',
                            cancel = 'Cancel'
                        }
                    })
                    
                    if alert == 'confirm' then
                        TriggerEvent('qbx_busjob:client:ToggleActive', false)
                    end
                else
                    -- Confirmation para mag-start ng job
                    local alert = lib.alertDialog({
                        header = 'Start Bus Job',
                        content = 'Are you sure you want to start the bus job?',
                        centered = true,
                        cancel = true,
                        labels = {
                            confirm = 'Yes, Start Job',
                            cancel = 'Cancel'
                        }
                    })
                    
                    if alert == 'confirm' then
                        TriggerEvent('qbx_busjob:client:ToggleActive', true)
                    end
                end
            end,
            distance = 2.5
        },
        {
            name = 'bus_job_garage',
            icon = 'fas fa-warehouse',
            label = 'Access Garage',
            onSelect = function()
                showBusGarage()
            end,
            canInteract = function()
                return BusJob.IsActive
            end,
            distance = 2.5
        },
        {
            name = 'bus_job_check_earnings',
            icon = 'fas fa-dollar-sign',
            label = 'Check Earnings',
            onSelect = function()
                TriggerEvent('qbx_busjob:client:CheckEarnings')
            end,
            canInteract = function()
                return BusJob.IsActive
            end,
            distance = 2.5
        }
    })
end

local function createExitNPC()
    if not isPlayerVehicleABus() then return end
    if State.exitNpc and DoesEntityExist(State.exitNpc) then return end
    
    -- Get a seat position for the exit NPC (usually passenger seat)
    local vehicle = cache.vehicle
    local seatPos = GetWorldPositionOfEntityBone(vehicle, GetEntityBoneIndexByName(vehicle, "seat_pside_f"))
    
    -- If no specific seat bone, use vehicle position with offset
    if seatPos.x == 0.0 and seatPos.y == 0.0 and seatPos.z == 0.0 then
        seatPos = GetEntityCoords(vehicle)
        local heading = GetEntityHeading(vehicle)
        local forwardX = math.sin(math.rad(-heading))
        local forwardY = math.cos(math.rad(-heading))
        seatPos = vector3(seatPos.x + forwardX * 1.5, seatPos.y + forwardY * 1.5, seatPos.z)
    end
    
    local model = joaat('s_m_m_pilot_01') -- Pilot/driver looking NPC
    
    if not lib.requestModel(model, 5000) then
        return nil
    end
    
    State.exitNpc = CreatePed(4, model, seatPos.x, seatPos.y, seatPos.z, 0.0, false, true)
    SetModelAsNoLongerNeeded(model)
    
    if not DoesEntityExist(State.exitNpc) then
        return nil
    end
    
    -- Configure NPC
    SetEntityInvincible(State.exitNpc, true)
    SetBlockingOfNonTemporaryEvents(State.exitNpc, true)
    SetPedCanPlayAmbientAnims(State.exitNpc, true)
    SetPedCanRagdollFromPlayerImpact(State.exitNpc, false)
    SetEntityAsMissionEntity(State.exitNpc, true, true)
    
    -- Make NPC invisible and non-collidable but targetable
    SetEntityAlpha(State.exitNpc, 0, false)
    SetEntityCollision(State.exitNpc, false, false)
    
    -- Setup ox_target for exit
    exports.ox_target:addLocalEntity(State.exitNpc, {
        {
            name = 'bus_exit_vehicle',
            icon = 'fas fa-door-open',
            label = 'Exit Bus',
            onSelect = function()
                TaskLeaveVehicle(cache.ped, cache.vehicle, 0)
                removeExitNPC()
            end,
            distance = 5.0
        },
        {
            name = 'bus_park_vehicle',
            icon = 'fas fa-parking',
            label = BusJob.OnRoute and 'Complete Route First' or 'Park Bus',
            onSelect = function()
                if BusJob.OnRoute then
                    lib.notify({
                        title = 'Bus Job',
                        description = 'Complete your current route first!',
                        type = 'error'
                    })
                else
                    local playerCoords = GetEntityCoords(cache.ped)
                    local depotCoords = sharedConfig.location
                    
                    if getDistance(playerCoords, depotCoords) < 50.0 then
                        if isValidVehicle(cache.vehicle) then
                            BusData.Active = false
                            DeleteVehicle(cache.vehicle)
                            removeNPCBlips()
                            resetJobState()
                            removeExitNPC()
                            
                            lib.notify({
                                title = 'Bus Job',
                                description = 'Bus parked successfully!',
                                type = 'success'
                            })
                        end
                    else
                        lib.notify({
                            title = 'Bus Job',
                            description = 'You need to be near the depot to park!',
                            type = 'error'
                        })
                    end
                end
            end,
            distance = 5.0
        }
    })
    
    return State.exitNpc
end

local function removeExitNPC()
    if State.exitNpc then
        exports.ox_target:removeLocalEntity(State.exitNpc)
        safeDeleteEntity(State.exitNpc)
        State.exitNpc = nil
    end
end

local function createWalkingNPC(stationIndex, walkFromIndex)
    if not walkingLocations[stationIndex] or not walkingLocations[stationIndex][walkFromIndex] then
        return nil
    end
    
    local walkFrom = walkingLocations[stationIndex][walkFromIndex]
    local station = sharedConfig.npcLocations.locations[stationIndex]
    
    if not station then return nil end
    
    -- Get random NPC model
    local genderIndex = math.random(1, #config.npcSkins)
    local skinIndex = math.random(1, #config.npcSkins[genderIndex])
    local model = joaat(config.npcSkins[genderIndex][skinIndex])
    
    -- Request model with timeout
    if not lib.requestModel(model, 5000) then
        return nil
    end
    
    local npc = CreatePed(4, model, walkFrom.x, walkFrom.y, walkFrom.z, walkFrom.w, false, true)
    SetModelAsNoLongerNeeded(model)
    
    if not DoesEntityExist(npc) then return nil end
    
    -- Configure NPC
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetPedCanPlayAmbientAnims(npc, true)
    SetPedCanRagdollFromPlayerImpact(npc, false)
    SetEntityAsMissionEntity(npc, true, true)
    
    -- Make NPC walk to station
    TaskGoStraightToCoord(npc, station.x, station.y, station.z, 1.0, -1, 0.0, 0.0)
    
    return npc
end

local function findFreeSeat()
    if not isValidVehicle(cache.vehicle) then return nil end
    
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(cache.vehicle))
    
    -- Start from back seats and work forward (excluding driver seat)
    for i = maxSeats - 2, 0, -1 do
        if IsVehicleSeatFree(cache.vehicle, i) then
            return i
        end
    end
    
    return nil
end

local function boardPassenger(npc, seatIndex)
    if not isValidVehicle(cache.vehicle) or not DoesEntityExist(npc) then
        return false
    end
    
    ClearPedTasksImmediately(npc)
    
    -- Move to vehicle first
    TaskGoToEntity(npc, cache.vehicle, -1, 2.0, 1.0, 0, 0)
    
    local startTime = GetGameTimer()
    local approached = false
    
    -- Wait for NPC to approach vehicle
    while GetGameTimer() - startTime < BusJob.BOARDING_TIMEOUT and DoesEntityExist(npc) do
        local npcCoords = GetEntityCoords(npc)
        local vehicleCoords = GetEntityCoords(cache.vehicle)
        
        if getDistance(npcCoords, vehicleCoords) < 3.0 then
            approached = true
            break
        end
        
        Wait(500)
    end
    
    if not approached then
        safeDeleteEntity(npc)
        return false
    end
    
    -- Start boarding
    TaskEnterVehicle(npc, cache.vehicle, -1, seatIndex, 1.0, 1)
    
    startTime = GetGameTimer()
    
    -- Wait for boarding completion
    while GetGameTimer() - startTime < BusJob.SEATING_TIMEOUT and DoesEntityExist(npc) do
        if IsPedInVehicle(npc, cache.vehicle, false) then
            SetEntityInvincible(npc, false)
            return true
        end
        Wait(500)
    end
    
    -- Boarding failed
    safeDeleteEntity(npc)
    return false
end

local function startNewRoute()
    if not BusJob.IsActive then return end
    
    -- Get new locations
    BusJob.CurrentPickupLocation = getRandomLocation()
    BusJob.CurrentDropoffLocation = getDifferentLocation(BusJob.CurrentPickupLocation)
    
    -- Create pickup blip
    removeNPCBlips()
    local pickup = sharedConfig.npcLocations.locations[BusJob.CurrentPickupLocation]
    BusJob.NpcBlip = createBlip(pickup, 1, settings.PICKUP_BLIP_COLOR, "Pickup Location", true)
    
    -- Reset route state
    BusJob.WaitingForPassengers = false
    BusJob.CurrentPassengers = 0
    BusJob.SpawnedNpcs = 0
    BusJob.BusFull = false
    BusJob.OnRoute = false
    BusJob.WaitingForNewPickup = false
    BusJob.LocationTriggered = false
    
    lib.notify({
        title = 'Bus Job',
        description = string.format('New route: Station %d → Station %d', 
                                   BusJob.CurrentPickupLocation, BusJob.CurrentDropoffLocation),
        type = 'info'
    })
end

local function calculatePassengerCount()
    if not isValidVehicle(cache.vehicle) then return 0 end
    
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(cache.vehicle))
    local availableSeats = math.max(0, maxSeats - 1) -- Exclude driver seat
    
    return math.random(3, math.min(BusJob.MaxPassengers, availableSeats))
end

local function startPassengerBoarding()
    if not isValidVehicle(cache.vehicle) then return end
    
    BusJob.WaitingForPassengers = true
    BusJob.CurrentPassengers = 0
    BusJob.SpawnedNpcs = 0
    BusJob.NpcSpawnTimer = GetGameTimer()
    
    local passengerCount = calculatePassengerCount()
    
    lib.notify({
        title = 'Bus Job',
        description = string.format('Waiting for up to %d passengers...', passengerCount),
        type = 'info',
        duration = 5000
    })
end

local function processNPCSpawning()
    if not BusJob.WaitingForPassengers or not isValidVehicle(cache.vehicle) then return end
    
    local currentTime = GetGameTimer()
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(cache.vehicle))
    local maxPassengers = math.min(BusJob.MaxPassengers, maxSeats - 1)
    
    -- Check spawn timing and limits
    if currentTime - BusJob.NpcSpawnTimer < BusJob.NPC_SPAWN_INTERVAL or 
       BusJob.SpawnedNpcs >= maxPassengers then
        return
    end
    
    BusJob.NpcSpawnTimer = currentTime
    
    -- Spawn NPC
    local walkFromIndex = math.random(1, #walkingLocations[BusJob.CurrentPickupLocation])
    local npc = createWalkingNPC(BusJob.CurrentPickupLocation, walkFromIndex)
    
    if not npc then return end
    
    BusJob.SpawnedNpcs = BusJob.SpawnedNpcs + 1
    BusJob.Npcs[BusJob.SpawnedNpcs] = npc
    
    lib.notify({
        title = 'Bus Job',
        description = string.format('Passenger %d approaching station...', BusJob.SpawnedNpcs),
        type = 'info',
        duration = 3000
    })
    
    -- Schedule boarding attempt
    SetTimeout(20000, function()
        if not DoesEntityExist(npc) or IsPedInVehicle(npc, cache.vehicle, false) then
            return
        end
        
        local freeSeat = findFreeSeat()
        if not freeSeat then return end
        
        if boardPassenger(npc, freeSeat) then
            BusJob.CurrentPassengers = BusJob.CurrentPassengers + 1
            
            lib.notify({
                title = 'Bus Job',
                description = string.format('Passenger boarded! (%d/%d)', 
                                           BusJob.CurrentPassengers, maxPassengers),
                type = 'success',
                duration = 3000
            })
            
            -- Check if bus is full
            if BusJob.CurrentPassengers >= maxPassengers or 
               BusJob.CurrentPassengers >= BusJob.SpawnedNpcs then
                BusJob.WaitingForPassengers = false
                BusJob.BusFull = true
                BusJob.OnRoute = true
                
                -- Create dropoff blip
                removeNPCBlips()
                local destination = sharedConfig.npcLocations.locations[BusJob.CurrentDropoffLocation]
                BusJob.DeliveryBlip = createBlip(destination, 1, settings.DROPOFF_BLIP_COLOR, "Dropoff Location", true)
                
                lib.notify({
                    title = 'Bus Job',
                    description = string.format('Bus is full! Drive to Station %d to drop off passengers', 
                                               BusJob.CurrentDropoffLocation),
                    type = 'success'
                })
            end
        end
    end)
end

-- Event Handlers
RegisterNetEvent("qbx_busjob:client:ToggleActive", function(startActive)
    if startActive then
        BusJob.IsActive = true
        BusJob.StartTime = GetGameTimer()
        BusJob.CurrentPay = 0
        BusJob.PassengersServed = 0
        BusJob.PassengersServedSinceLastLocation = 0
        BusJob.LocationTriggered = false
        
        lib.notify({
            title = 'Bus Job',
            description = 'Job started! Access the garage to get a bus.',
            type = 'success'
        })
    else
        BusJob.IsActive = false
        
        if BusJob.CurrentPay > 0 then
            showEarningsSummary()
            TriggerServerEvent('qbx_busjob:server:ReceivePayment', BusJob.CurrentPay)
            BusJob.CurrentPay = 0
            BusJob.PassengersServed = 0
            BusJob.PassengersServedSinceLastLocation = 0
        end
        
        resetJobState()
        removeNPCBlips()
        removeExitNPC()
        
        lib.notify({
            title = 'Bus Job',
            description = 'Job ended. Thanks for your service!',
            type = 'info'
        })
    end
    
    -- Refresh NPC targets
    setupJobNPCTargets()
end)

RegisterNetEvent("qbx_busjob:client:CheckEarnings", function()
    local timeWorked = math.floor((GetGameTimer() - BusJob.StartTime) / 60000)
    local passengersToMilestone = settings.PASSENGERS_FOR_LOCATION_TRIGGER - BusJob.PassengersServedSinceLastLocation
    
    lib.notify({
        title = 'Current Earnings',
        description = string.format('$%d from %d passengers (%d min)\nMilestone: %d passengers to go', 
                                   BusJob.CurrentPay, BusJob.PassengersServed, timeWorked, passengersToMilestone),
        type = 'info',
        duration = 8000
    })
end)

RegisterNetEvent("qbx_busjob:client:TakeVehicle", function(data)
    if not BusJob.IsActive then
        lib.notify({
            title = 'Bus Job',
            description = 'Start the bus job first!',
            type = 'error'
        })
        return
    end

    if BusData.Active then
        lib.notify({
            title = 'Bus Job',
            description = 'You already have a bus spawned!',
            type = 'error'
        })
        return
    end

    local netId = lib.callback.await('qbx_busjob:server:spawnBus', false, data.model)
    Wait(500)
    
    if not netId or netId == 0 or not NetworkDoesEntityExistWithNetworkId(netId) then
        lib.notify({
            title = 'Bus Job',
            description = 'Failed to spawn bus. Please try again.',
            type = 'error'
        })
        return
    end

    local vehicle = NetToVeh(netId)
    if not isValidVehicle(vehicle) then
        lib.notify({
            title = 'Bus Job',
            description = 'Vehicle spawn failed. Please try again.',
            type = 'error'
        })
        return
    end

    -- Configure vehicle with keys
    SetVehicleFuelLevel(vehicle, settings.FUEL_LEVEL)
    if settings.AUTO_START_ENGINE then
        SetVehicleEngineOn(vehicle, true, true, false)
    end
    
    -- Give vehicle keys if setting enabled
    if settings.GIVE_VEHICLE_KEYS then
        TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(vehicle))
    end
    
    BusData.Active = true
    
    -- Start first route
    startNewRoute()
    
    lib.hideContext()
    
    lib.notify({
        title = 'Bus Job',
        description = 'Bus spawned with keys! Follow the GPS to your first pickup location.',
        type = 'success'
    })
end)

-- Vehicle enter/exit detection
CreateThread(function()
    local wasInBus = false
    
    while true do
        local isInBus = isPlayerVehicleABus()
        
        -- Player entered bus
        if isInBus and not wasInBus and BusJob.IsActive then
            createExitNPC()
        -- Player exited bus
        elseif not isInBus and wasInBus then
            removeExitNPC()
        end
        
        wasInBus = isInBus
        Wait(1000)
    end
end)

-- Resource lifecycle events
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    updateMainBlip()
    setupJobNPCTargets()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Cleanup
    resetJobState()
    removeNPCBlips()
    removeBusBlip()
    removeExitNPC()
    
    if State.jobNpc then
        exports.ox_target:removeLocalEntity(State.jobNpc)
        safeDeleteEntity(State.jobNpc)
    end
    
    if State.deliverZone then State.deliverZone:remove() end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    updateMainBlip()
    setupJobNPCTargets()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    resetJobState()
    removeNPCBlips()
    removeExitNPC()
end)

-- Station proximity handler
local function handleStationArrival()
    if not BusJob.IsActive or not BusData.Active or not isValidVehicle(cache.vehicle) then
        return
    end
    
    local playerCoords = GetEntityCoords(cache.ped)
    
    -- Handle pickup location
    if not BusJob.WaitingForPassengers and not BusJob.OnRoute and BusJob.CurrentPickupLocation then
        local pickupCoords = sharedConfig.npcLocations.locations[BusJob.CurrentPickupLocation]
        if getDistance(playerCoords, pickupCoords) < BusJob.PICKUP_RADIUS then
            startPassengerBoarding()
        end
    end
    
    -- Handle dropoff location
    if BusJob.OnRoute and BusJob.BusFull and BusJob.CurrentDropoffLocation then
        local dropoffCoords = sharedConfig.npcLocations.locations[BusJob.CurrentDropoffLocation]
        if getDistance(playerCoords, dropoffCoords) < BusJob.DROPOFF_RADIUS then
            dropOffPassengers()
        end
    end
end

-- Handle waiting period after dropoff
local function handleDropoffWaitTimer()
    if not BusJob.WaitingForNewPickup then return end
    
    local currentTime = GetGameTimer()
    if currentTime - BusJob.DropoffWaitTimer >= BusJob.DROPOFF_WAIT_TIME then
        BusJob.WaitingForNewPickup = false
        
        if BusJob.IsActive then
            startNewRoute()
            lib.notify({
                title = 'Bus Job',
                description = 'New pickup location assigned! Head to the station.',
                type = 'success'
            })
        end
    end
end

-- Main game loop
CreateThread(function()
    while true do
        if BusJob.IsActive and BusData.Active and isValidVehicle(cache.vehicle) then
            handleStationArrival()
            handleDropoffWaitTimer()
            
            -- Process NPC spawning
            if BusJob.WaitingForPassengers and not BusJob.OnRoute then
                processNPCSpawning()
            end
        end
        Wait(1000)
    end
end)

-- Commands
RegisterCommand('busearnings', function()
    if BusJob.IsActive then
        TriggerEvent("qbx_busjob:client:CheckEarnings")
    else
        lib.notify({
            title = 'Bus Job',
            description = 'You are not currently working as a bus driver.',
            type = 'error'
        })
    end
end, false)

RegisterCommand('busreset', function()
    if BusJob.IsActive then
        resetJobState()
        removeNPCBlips()
        lib.notify({
            title = 'Bus Job',
            description = 'Job state reset successfully.',
            type = 'info'
        })
    end
end, false)

-- Debug command (only works if debug is enabled)
RegisterCommand('busdebug', function()
    if config.debugPoly then
        print('Bus Job Debug Info:')
        print('- IsActive:', BusJob.IsActive)
        print('- OnRoute:', BusJob.OnRoute)
        print('- Current Passengers:', BusJob.CurrentPassengers)
        print('- Spawned NPCs:', BusJob.SpawnedNpcs)
        print('- Current Pay:', BusJob.CurrentPay)
        print('- Pickup Location:', BusJob.CurrentPickupLocation)
        print('- Dropoff Location:', BusJob.CurrentDropoffLocation)
        print('- Waiting for Passengers:', BusJob.WaitingForPassengers)
        print('- Bus Full:', BusJob.BusFull)
        print('- Passengers Since Last Location:', BusJob.PassengersServedSinceLastLocation)
        print('- Location Triggered:', BusJob.LocationTriggered)
        print('- Waiting for New Pickup:', BusJob.WaitingForNewPickup)
        
        lib.notify({
            title = 'Bus Job Debug',
            description = 'Debug info printed to console.',
            type = 'info'
        })
    else
        lib.notify({
            title = 'Bus Job',
            description = 'Debug mode is disabled.',
            type = 'error'
        })
    end
end, false)