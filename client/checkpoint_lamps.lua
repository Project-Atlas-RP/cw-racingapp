-----------------------
----   Checkpoint Lamps System   ----
----   Uses bzzz_lights_and_lamps world_of_lamps props   ----
-----------------------

-- Forward declare global functions (so they're available in main.lua)
ClearAllLamps = ClearAllLamps or function() end
UpdateRaceLamps = UpdateRaceLamps or function() end
StartLampUpdateThread = StartLampUpdateThread or function() end
StopLampUpdateThread = StopLampUpdateThread or function() end
IsNightTime = IsNightTime or function() return false end

-- Get configuration from shared config or use defaults
local function GetLampConfig()
    if Config and Config.CheckpointLamps then
        return Config.CheckpointLamps
    end
    
    -- Default fallback configuration
    return {
        enabled = true,
        nightOnly = true,
        nightStartHour = 20,
        nightEndHour = 6,
        startFinishColor = 'bzzz_world_of_lamps_green',
        checkpointColors = {
            'bzzz_world_of_lamps_blue',
            'bzzz_world_of_lamps_orange',
            'bzzz_world_of_lamps_purple',
            'bzzz_world_of_lamps_pink',
            'bzzz_world_of_lamps_yellow',
            'bzzz_world_of_lamps_red',
            'bzzz_world_of_lamps_white',
        },
    }
end

-- Store active lamp entities
local ActiveLamps = {}
local LampUpdateThread = false

-- Check if it's currently night time (global function for use in main.lua)
function IsNightTime()
    local LampConfig = GetLampConfig()
    
    if not LampConfig.nightOnly then
        return true
    end
    
    local hour = GetClockHours()
    
    -- Night time is between nightStartHour (e.g., 20/8PM) and nightEndHour (e.g., 6AM)
    if LampConfig.nightStartHour > LampConfig.nightEndHour then
        -- Crosses midnight (e.g., 20:00 to 06:00)
        return hour >= LampConfig.nightStartHour or hour < LampConfig.nightEndHour
    else
        -- Same day (e.g., 22:00 to 23:00)
        return hour >= LampConfig.nightStartHour and hour < LampConfig.nightEndHour
    end
end

-- Get the lamp model name based on checkpoint index and type
local function GetLampModel(checkpointIndex, isStartFinish, totalCheckpoints)
    local LampConfig = GetLampConfig()
    
    if isStartFinish then
        return LampConfig.startFinishColor
    end
    
    -- Alternate through colors based on checkpoint index
    local colorIndex = ((checkpointIndex - 1) % #LampConfig.checkpointColors) + 1
    return LampConfig.checkpointColors[colorIndex]
end

-- Load a model and wait for it
local function LoadLampModel(modelName)
    local model = joaat(modelName)
    if not IsModelValid(model) then
        print('^1[cw-racingapp] Invalid lamp model: ' .. modelName .. '^0')
        return nil
    end
    
    local timeout = 0
    while not HasModelLoaded(model) do
        RequestModel(model)
        Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then
            print('^1[cw-racingapp] Failed to load lamp model: ' .. modelName .. '^0')
            return nil
        end
    end
    
    return model
end

-- Create a lamp object at a position
local function CreateLampObject(coords, modelName)
    local model = LoadLampModel(modelName)
    if not model then return nil end
    
    local lamp = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    
    if lamp and DoesEntityExist(lamp) then
        PlaceObjectOnGroundProperly(lamp)
        FreezeEntityPosition(lamp, true)
        SetEntityAsMissionEntity(lamp, true, true)
        SetEntityCollision(lamp, false, true)
        SetEntityCanBeDamaged(lamp, false)
        SetEntityInvincible(lamp, true)
        SetEntityAlpha(lamp, 255, false)
        return lamp
    end
    
    return nil
end

-- Delete a lamp object
local function DeleteLampObject(lamp)
    if lamp and DoesEntityExist(lamp) then
        SetEntityAsMissionEntity(lamp, false, true)
        DeleteEntity(lamp)
    end
end

-- Clear all active lamps
function ClearAllLamps()
    for checkpointIndex, lampData in pairs(ActiveLamps) do
        if lampData then
            if lampData.left and DoesEntityExist(lampData.left) then
                DeleteLampObject(lampData.left)
                lampData.left = nil
            end
            if lampData.right and DoesEntityExist(lampData.right) then
                DeleteLampObject(lampData.right)
                lampData.right = nil
            end
        end
        ActiveLamps[checkpointIndex] = nil
    end
    ActiveLamps = {}
end

-- Spawn lamps for a specific checkpoint
local function SpawnCheckpointLamps(checkpointIndex, checkpointData, isStartFinish, totalCheckpoints)
    local LampConfig = GetLampConfig()
    
    if not LampConfig.enabled then return end
    if not IsNightTime() then return end
    
    local modelName = GetLampModel(checkpointIndex, isStartFinish, totalCheckpoints)
    
    local lampData = {
        left = nil,
        right = nil,
        checkpointIndex = checkpointIndex,
    }
    
    -- Spawn lamp on the left side
    if checkpointData.offset and checkpointData.offset.left then
        lampData.left = CreateLampObject(checkpointData.offset.left, modelName)
    end
    
    -- Spawn lamp on the right side
    if checkpointData.offset and checkpointData.offset.right then
        lampData.right = CreateLampObject(checkpointData.offset.right, modelName)
    end
    
    ActiveLamps[checkpointIndex] = lampData
end

-- Remove lamps for a specific checkpoint
local function RemoveCheckpointLamps(checkpointIndex)
    local lampData = ActiveLamps[checkpointIndex]
    if lampData then
        if lampData.left then
            DeleteLampObject(lampData.left)
        end
        if lampData.right then
            DeleteLampObject(lampData.right)
        end
        ActiveLamps[checkpointIndex] = nil
    end
end

-- Check if a checkpoint is start or finish
local function IsStartOrFinish(checkpointIndex, totalCheckpoints, totalLaps)
    if totalLaps == 0 then
        -- Sprint race: first checkpoint is start, last is finish
        return checkpointIndex == 1 or checkpointIndex == totalCheckpoints
    else
        -- Circuit race: only first checkpoint is start/finish
        return checkpointIndex == 1
    end
end

-- Update lamps based on current race state
function UpdateRaceLamps(checkpoints, currentCheckpoint, totalLaps, markAhead)
    local LampConfig = GetLampConfig()
    
    if not LampConfig.enabled then return end
    
    local totalCheckpoints = #checkpoints
    local isCircuit = totalLaps > 0
    markAhead = markAhead or Config.MarkAmountOfCheckpointsAhead or 5
    
    -- Note: ClearAllLamps is called by deleteAllCheckpoints before this function
    -- Only clear here if called directly (safety check)
    if next(ActiveLamps) ~= nil then
        ClearAllLamps()
    end
    
    -- Check if it's night time
    if not IsNightTime() then
        return
    end
    
    -- Calculate which checkpoints to show lamps for
    local lastCheckpoint = currentCheckpoint + markAhead - 1
    
    for i = currentCheckpoint, lastCheckpoint do
        local checkpointIndex = isCircuit and ((i - 1) % totalCheckpoints) + 1 or i
        
        if checkpointIndex > totalCheckpoints and not isCircuit then
            break
        end
        
        local checkpointData = checkpoints[checkpointIndex]
        if checkpointData then
            local isStartFinish = IsStartOrFinish(checkpointIndex, totalCheckpoints, totalLaps)
            SpawnCheckpointLamps(checkpointIndex, checkpointData, isStartFinish, totalCheckpoints)
        end
    end
end

-- Start the lamp update thread that checks for day/night transitions
function StartLampUpdateThread(getCurrentRaceData)
    if LampUpdateThread then return end
    
    LampUpdateThread = true
    
    CreateThread(function()
        local wasNight = IsNightTime()
        
        while LampUpdateThread do
            local isNight = IsNightTime()
            
            -- Check for day/night transition
            if wasNight ~= isNight then
                wasNight = isNight
                
                local raceData = getCurrentRaceData()
                if raceData and raceData.Checkpoints and #raceData.Checkpoints > 0 then
                    if isNight then
                        -- Night started, spawn lamps
                        UpdateRaceLamps(
                            raceData.Checkpoints,
                            raceData.CurrentCheckpoint or 1,
                            raceData.TotalLaps or 0
                        )
                    else
                        -- Day started, remove lamps
                        ClearAllLamps()
                    end
                end
            end
            
            Wait(10000) -- Check every 10 seconds for day/night changes
        end
    end)
end

-- Stop the lamp update thread
function StopLampUpdateThread()
    LampUpdateThread = false
    ClearAllLamps()
end

-- Export functions for use in main.lua
exports('UpdateRaceLamps', UpdateRaceLamps)
exports('ClearAllLamps', ClearAllLamps)
exports('StartLampUpdateThread', StartLampUpdateThread)
exports('StopLampUpdateThread', StopLampUpdateThread)
exports('IsNightTime', IsNightTime)
exports('GetLampConfig', GetLampConfig)
