-----------------------
----   Variables   ----
-----------------------
local TraderPed

ShowGpsRoute = Config.ShowGpsRoute or false
IgnoreRoadsForGps = Config.IgnoreRoadsForGps or false
UseUglyWaypoint = Config.UseUglyWaypoint or false
UseDrawTextWaypoint = Config.UseDrawTextWaypoint or false
CheckDistance = Config.CheckDistance or false

local CreatorObjectLeft, CreatorObjectRight
CheckpointPileModel = joaat(Config.CheckpointPileModel)
StartAndFinishModel = joaat(Config.StartAndFinishModel)

local startTime = 0
local lapStartTime = 0
local RandomRaceVehicleModels
local RandomRaceVehicleCategoryOptions

local CreatorData = {
    RaceName = nil,
    RacerName = nil,
    RacerId = nil,
    Checkpoints = {},
    TireDistance = 3.0,
    ConfirmDelete = false,
    IsEdit = false,
    RaceId = nil
}

RegisterNetEvent('cw-racingapp:client:notify', function(message, type)
    NotifyHandler(message, type)
end)

function DebugLog(message, message2, message3, message4)
    if UseDebug then
        print('^2CW-RACINGAPP DEBUG:^0')
        print(message)
        if message2 then
            print(message2)
        end
        if message3 then
            print(message3)
        end
        if message4 then
            print(message4)
        end
    end
end

local function updateRaceUi()
    SendNUIMessage({
        action = "update",
        type = "race",
        data = {
            currentCheckpoint = CurrentRaceData.CurrentCheckpoint,
            totalCheckpoints = #CurrentRaceData.Checkpoints,
            totalLaps = CurrentRaceData.TotalLaps,
            currentLap = CurrentRaceData.Lap,
            raceStarted = CurrentRaceData.Started,
            raceName = CurrentRaceData.RaceName,
            time = CurrentRaceData.RaceTime,
            totalTime = CurrentRaceData.TotalTime,
            bestLap = CurrentRaceData.BestLap,
            position = CurrentRaceData.Position,
            positions = CurrentRaceData.Positions,
            totalRacers = CurrentRaceData.TotalRacers,
            ghosted = CurrentRaceData.Ghosted,
        },
        racedata = RaceData,
        active = true
    })
end

RegisterNetEvent('cw-racingapp:client:updateUiData', function(dataType, data)
    if hasGps() then
        UpdateUiData(dataType, data)
    end
end)

RegisterNetEvent('cw-racingapp:client:updateUserData', function(dataType, data)
    CurrentUserData[dataType] = data
end)

-----------------------
----   Functions   ----
-----------------------
local function reverseTable(tbl)
    local len = #tbl
    local mid = math.floor(len / 2)
    for i = 1, mid do
        local temp = tbl[i]
        tbl[i] = tbl[len - i + 1]
        tbl[len - i + 1] = temp
    end
    return tbl
end

local timeWhenLastCheckpointWasPassed = 0
-- Racing

local function checkCheckPointTime()
    if GetTimeDifference(GetGameTimer(), timeWhenLastCheckpointWasPassed) > Config.KickTime then
        DebugLog('Getting kicked for idling')
        if not Kicked then
            Kicked = true
            NotifyHandler(Lang('kicked_idling'), 'error')
            TriggerServerEvent("cw-racingapp:server:leaveRace", CurrentRaceData, 'idling')
        end
    end
end

local function getMaxDistance(center, offsetCoords)
    local distance = #(vector3(center.x, center.y, center.z) -
        vector3(offsetCoords.left.x, offsetCoords.left.y, offsetCoords.left.z))

    return distance + (Config.CheckpointBuffer or 0)
end

local function genericBlip(blip)
    SetBlipScale(blip, Config.Blips.Generic.Size)
    SetBlipColour(blip, Config.Blips.Generic.Color)
end

local function nextBlip(blip)
    SetBlipScale(blip, Config.Blips.Next.Size)
    SetBlipColour(blip, Config.Blips.Next.Color)
end

local function passedBlip(blip)
    SetBlipScale(blip, Config.Blips.Passed.Size)
    SetBlipColour(blip, Config.Blips.Passed.Color)
end

local function resetBlips()
    for _, checkpoint in pairs(CurrentRaceData.Checkpoints) do
        genericBlip(checkpoint.blip)
    end
end


local function showNonLoopParticle(dict, particleName, coords, scale, time)
    while not HasNamedPtfxAssetLoaded(dict) do
        RequestNamedPtfxAsset(dict)
        Wait(0)
    end

    UseParticleFxAssetNextCall(dict)

    local particleHandle = StartParticleFxLoopedAtCoord(particleName, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0,
        scale, false, false, false, 0)
    SetParticleFxLoopedColour(particleHandle, 0.0, 0.0, 1.0)
    return particleHandle
end

local function handleFlare(checkpoint)
    local Size = 1.0
    local left = showNonLoopParticle('core', 'exp_grd_flare',
        CurrentRaceData.Checkpoints[checkpoint].offset.left, Size)
    local right = showNonLoopParticle('core', 'exp_grd_flare',
        CurrentRaceData.Checkpoints[checkpoint].offset.right, Size)

    SetTimeout(Config.FlareTime, function()
        StopParticleFxLooped(left, false)
        StopParticleFxLooped(right, false)
    end)
end

local function doPilePfx()
    if CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1] ~= nil then
        handleFlare(CurrentRaceData.CurrentCheckpoint + 1)
    end
    if CurrentRaceData.CurrentCheckpoint == 1 then -- start
        DebugLog('start')
        handleFlare(CurrentRaceData.CurrentCheckpoint)
    end
    if CurrentRaceData.TotalLaps > 0 and CurrentRaceData.CurrentCheckpoint == #CurrentRaceData.Checkpoints then -- finish
        DebugLog('finish')
        handleFlare(1)
        if CurrentRaceData.Lap ~= CurrentRaceData.TotalLaps then
            DebugLog('not last lap')
            handleFlare(2)
        end
    end
end

local function loadModel(model)
    while not HasModelLoaded(model) do
        RequestModel(model)
        Wait(10)
    end
end

local function isAllowedRandomRaceVehicle(model)
    if IsThisModelAHeli(model) or IsThisModelAPlane(model) then
        return false
    end

    return IsThisModelACar(model) or IsThisModelABike(model) or IsThisModelAQuadbike(model) or
        IsThisModelABicycle(model)
end

local function getSmallresourcesBlacklistedVehicles()
    if GetResourceState('qbx_smallresources') ~= 'started' then
        return {}
    end

    local success, blacklistedVehicles = pcall(function()
        return exports.qbx_smallresources:GetBlacklistedVehicles()
    end)

    if not success or type(blacklistedVehicles) ~= 'table' then
        DebugLog('Unable to read qbx_smallresources vehicle blacklist for random race vehicles')
        return {}
    end

    return blacklistedVehicles
end

local function getRandomRaceVehicleModels()
    if RandomRaceVehicleModels then
        return RandomRaceVehicleModels
    end

    RandomRaceVehicleModels = {}
    local blacklistedVehicles = getSmallresourcesBlacklistedVehicles()
    local vehicles = exports.qbx_core:GetVehiclesByName()

    for modelName, vehicleData in pairs(vehicles) do
        local model = vehicleData.model or modelName
        local hash = vehicleData.hash or joaat(model)
        local category = vehicleData.category or 'other'
        local isEligible = model and not blacklistedVehicles[hash] and IsModelInCdimage(hash) and
            IsModelAVehicle(hash) and isAllowedRandomRaceVehicle(hash)

        if isEligible then
            RandomRaceVehicleModels[#RandomRaceVehicleModels + 1] = {
                model = model,
                hash = hash,
                category = category,
            }
        end
    end

    return RandomRaceVehicleModels
end

local function formatRandomVehicleCategoryLabel(category)
    local label = category:gsub('[_%-]+', ' ')
    return (label:gsub('(%a)([%w]*)', function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end))
end

local function getRandomRaceVehicleCategoryOptions()
    if RandomRaceVehicleCategoryOptions then
        return RandomRaceVehicleCategoryOptions
    end

    RandomRaceVehicleCategoryOptions = {}
    local seenCategories = {}

    for _, vehicleData in ipairs(getRandomRaceVehicleModels()) do
        if vehicleData.category and not seenCategories[vehicleData.category] then
            seenCategories[vehicleData.category] = true
            RandomRaceVehicleCategoryOptions[#RandomRaceVehicleCategoryOptions + 1] = {
                value = vehicleData.category,
                text = formatRandomVehicleCategoryLabel(vehicleData.category),
            }
        end
    end

    table.sort(RandomRaceVehicleCategoryOptions, function(a, b)
        return a.text < b.text
    end)

    return RandomRaceVehicleCategoryOptions
end

local function getFilteredRandomRaceVehicleModels(selectedCategories)
    local availableVehicles = getRandomRaceVehicleModels()

    if not selectedCategories or #selectedCategories == 0 then
        return availableVehicles
    end

    local allowedCategories = {}
    for _, category in ipairs(selectedCategories) do
        allowedCategories[category] = true
    end

    local filteredVehicles = {}
    for _, vehicleData in ipairs(availableVehicles) do
        if allowedCategories[vehicleData.category] then
            filteredVehicles[#filteredVehicles + 1] = vehicleData
        end
    end

    if #filteredVehicles == 0 then
        return availableVehicles
    end

    return filteredVehicles
end

local function requestControlOfEntity(entity, timeout)
    local expiresAt = GetGameTimer() + (timeout or 1000)

    while DoesEntityExist(entity) and not NetworkHasControlOfEntity(entity) and GetGameTimer() < expiresAt do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end

    return not DoesEntityExist(entity) or NetworkHasControlOfEntity(entity)
end

local function giveKeysForRaceSwapVehicle(vehicle)
    local expiresAt = GetGameTimer() + 4000
    local netId = 0

    while DoesEntityExist(vehicle) and netId == 0 and GetGameTimer() < expiresAt do
        netId = NetworkGetNetworkIdFromEntity(vehicle)
        if netId == 0 then
            Wait(0)
        end
    end

    if netId == 0 then
        DebugLog('Failed to get network id for swapped race vehicle keys grant')
        return false
    end

    local success = false
    while DoesEntityExist(vehicle) and not success and GetGameTimer() < expiresAt do
        success = lib.callback.await('qbx_vehiclekeys:server:giveKeys', false, netId)
        if not success then
            Wait(100)
        end
    end

    if not success then
        DebugLog('Failed to grant keys for swapped race vehicle', netId)
    end

    return success
end

local function repairRaceSwapVehicle(vehicle)
    SetVehicleUndriveable(vehicle, false)
    WashDecalsFromVehicle(vehicle, 1.0)
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleDeformationFixed(vehicle)
    SetVehicleFixed(vehicle)

    for i = 0, 5 do
        SetVehicleTyreFixed(vehicle, i)
    end

    for i = 0, 7 do
        FixVehicleWindow(vehicle, i)
        if IsVehicleDoorDamaged(vehicle, i) then
            SetVehicleDoorBroken(vehicle, i, false)
        end
        SetVehicleDoorCanBreak(vehicle, i, true)
        SetVehicleDoorShut(vehicle, i, true)
    end

    SetVehicleFuelLevel(vehicle, 100.0)
end

local function setVehicleModToMax(vehicle, modType)
    local maxMod = GetNumVehicleMods(vehicle, modType) - 1
    if maxMod > -1 then
        SetVehicleMod(vehicle, modType, maxMod, false)
    end
end

local function setVehicleModToRandom(vehicle, modType)
    local maxMod = GetNumVehicleMods(vehicle, modType) - 1
    if maxMod > -1 then
        SetVehicleMod(vehicle, modType, math.random(0, maxMod), false)
    end
end

local function applyRaceSwapVehicleEffects(vehicle)
    SetVehicleModKit(vehicle, 0)
    repairRaceSwapVehicle(vehicle)

    local bodyMods = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true }
    for modType in pairs(bodyMods) do
        setVehicleModToMax(vehicle, modType)
    end

    local maxEngine = GetNumVehicleMods(vehicle, 11) - 1
    if maxEngine >= 2 then
        SetVehicleMod(vehicle, 11, 2, false)
    elseif maxEngine > -1 then
        SetVehicleMod(vehicle, 11, maxEngine, false)
    end

    local maxBrakes = GetNumVehicleMods(vehicle, 12) - 1
    if maxBrakes >= 1 then
        SetVehicleMod(vehicle, 12, 1, false)
    elseif maxBrakes > -1 then
        SetVehicleMod(vehicle, 12, maxBrakes, false)
    end

    setVehicleModToMax(vehicle, 15)

    local performanceMods = { [11] = true, [12] = true, [13] = true, [15] = true, [16] = true }
    for modType = 0, 49 do
        if not performanceMods[modType] and not bodyMods[modType] then
            setVehicleModToRandom(vehicle, modType)
        end
    end

    ToggleVehicleMod(vehicle, 17, true)
    ToggleVehicleMod(vehicle, 18, true)
    ToggleVehicleMod(vehicle, 20, true)
    ToggleVehicleMod(vehicle, 21, true)
    ToggleVehicleMod(vehicle, 22, true)
    SetVehicleTyresCanBurst(vehicle, false)

    local neonColors = {
        { 255, 0, 0 },
        { 0, 255, 0 },
        { 0, 0, 255 },
        { 255, 0, 255 },
        { 255, 255, 0 },
        { 0, 255, 255 },
        { 255, 255, 255 },
    }
    local randomNeon = neonColors[math.random(#neonColors)]
    SetVehicleNeonLightsColour(vehicle, randomNeon[1], randomNeon[2], randomNeon[3])

    SetVehicleWindowTint(vehicle, math.random(0, 6))

    local maxColor = 160
    SetVehicleColours(vehicle, math.random(0, maxColor), math.random(0, maxColor))
    SetVehicleExtraColours(vehicle, math.random(0, maxColor), math.random(0, maxColor))

    local wheelTypes = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
    local randomWheelType = wheelTypes[math.random(#wheelTypes)]
    SetVehicleWheelType(vehicle, randomWheelType)

    local maxWheels = GetNumVehicleMods(vehicle, 23)
    if maxWheels > 0 then
        SetVehicleMod(vehicle, 23, math.random(0, maxWheels - 1), true)
    end

    SetVehicleNumberPlateTextIndex(vehicle, math.random(0, 5))

    local maxLivery = GetNumVehicleMods(vehicle, 48) - 1
    if maxLivery > -1 then
        SetVehicleMod(vehicle, 48, math.random(0, maxLivery), false)
    end

    local maxHorn = GetNumVehicleMods(vehicle, 14) - 1
    if maxHorn > -1 then
        SetVehicleMod(vehicle, 14, math.random(0, maxHorn), false)
    end
end

local function buildSharedCategorySequence()
    local seen = {}
    local categories = {}
    local source = CurrentRaceData.RandomVehicleCategories
    if source and #source > 0 then
        for _, category in ipairs(source) do
            if not seen[category] then
                seen[category] = true
                categories[#categories + 1] = category
            end
        end
    else
        for _, option in ipairs(getRandomRaceVehicleCategoryOptions()) do
            if option.value and not seen[option.value] then
                seen[option.value] = true
                categories[#categories + 1] = option.value
            end
        end
    end

    -- Fisher-Yates: every racer shuffles their own copy independently so they
    -- end up covering the same set of categories in a different order.
    for i = #categories, 2, -1 do
        local j = math.random(i)
        categories[i], categories[j] = categories[j], categories[i]
    end

    return categories
end

local function swapToRandomRaceVehicle()
    local ped = PlayerPedId()
    local currentVehicle = GetVehiclePedIsIn(ped, false)

    if currentVehicle == 0 or not IsDriver(currentVehicle) then
        DebugLog('Skipping random race vehicle swap because racer is not driving')
        return false
    end

    local availableVehicles = getFilteredRandomRaceVehicleModels(CurrentRaceData.RandomVehicleCategories)
    if #availableVehicles == 0 then
        DebugLog('No eligible random race vehicles available for swapping')
        return false
    end

    local currentHash = GetEntityModel(currentVehicle)
    local currentCategory
    if CurrentRaceData.NoSameRandomVehicle or CurrentRaceData.NoSameRandomCategory then
        for _, vehicleData in ipairs(getRandomRaceVehicleModels()) do
            if vehicleData.hash == currentHash then
                currentCategory = vehicleData.category
                break
            end
        end
    end

    local function applyExclusions(pool, usedCategories)
        local filtered = {}
        for _, vehicleData in ipairs(pool) do
            local sameVehicle = CurrentRaceData.NoSameRandomVehicle and vehicleData.hash == currentHash
            local sameCategory = CurrentRaceData.NoSameRandomCategory and currentCategory and
                vehicleData.category == currentCategory
            local usedCategory = CurrentRaceData.UniqueRandomCategory and usedCategories[vehicleData.category]
            if not sameVehicle and not sameCategory and not usedCategory then
                filtered[#filtered + 1] = vehicleData
            end
        end
        return filtered
    end

    if CurrentRaceData.SharedRandomCategories then
        -- Build the racer's personal shuffled rotation lazily. Every racer draws
        -- from the same enabled category set (host config), so shuffling
        -- independently means everyone covers the same categories in different
        -- orders. Vehicle pick within a category stays random per racer.
        local sequence = CurrentRaceData.SharedCategorySequence or {}
        local index = (CurrentRaceData.SharedCategorySequenceIndex or 0) + 1
        if #sequence == 0 or index > #sequence then
            sequence = buildSharedCategorySequence()
            index = 1
        end
        CurrentRaceData.SharedCategorySequence = sequence
        CurrentRaceData.SharedCategorySequenceIndex = index

        local nextCategory = sequence[index]
        if nextCategory then
            local categoryPool = {}
            for _, vehicleData in ipairs(availableVehicles) do
                if vehicleData.category == nextCategory then
                    categoryPool[#categoryPool + 1] = vehicleData
                end
            end
            -- Honor noSameRandomVehicle within the chosen category. Other category
            -- exclusions don't apply: the rotation already dictates the category.
            if CurrentRaceData.NoSameRandomVehicle and #categoryPool > 1 then
                local pruned = {}
                for _, vehicleData in ipairs(categoryPool) do
                    if vehicleData.hash ~= currentHash then
                        pruned[#pruned + 1] = vehicleData
                    end
                end
                if #pruned > 0 then categoryPool = pruned end
            end
            if #categoryPool > 0 then
                availableVehicles = categoryPool
            else
                DebugLog('Shared rotation: category "' .. nextCategory .. '" has no eligible vehicles, falling back')
            end
        end
    elseif CurrentRaceData.UniqueRandomCategory then
        CurrentRaceData.UsedRandomCategories = CurrentRaceData.UsedRandomCategories or {}
        local filtered = applyExclusions(availableVehicles, CurrentRaceData.UsedRandomCategories)
        if #filtered == 0 then
            -- All categories exhausted (or filters too tight): reset rotation and retry.
            CurrentRaceData.UsedRandomCategories = {}
            filtered = applyExclusions(availableVehicles, CurrentRaceData.UsedRandomCategories)
        end
        if #filtered > 0 then
            availableVehicles = filtered
        else
            DebugLog('No vehicles left after exclusions; keeping unfiltered pool')
        end
    elseif CurrentRaceData.NoSameRandomVehicle or CurrentRaceData.NoSameRandomCategory then
        local filtered = applyExclusions(availableVehicles, {})
        if #filtered > 0 then
            availableVehicles = filtered
        else
            DebugLog('No vehicles left after no-same exclusions; keeping unfiltered pool')
        end
    end

    local selection = availableVehicles[math.random(#availableVehicles)]
    if CurrentRaceData.UniqueRandomCategory and selection and selection.category then
        CurrentRaceData.UsedRandomCategories = CurrentRaceData.UsedRandomCategories or {}
        CurrentRaceData.UsedRandomCategories[selection.category] = true
    end
    -- Load the model BEFORE snapshotting position/momentum. Previously the
    -- snapshot was taken first, then loadModel yielded for 10-100s of ms
    -- while RequestModel cycled. When the model was uncached the player
    -- drove on during the yield and the new vehicle spawned behind them;
    -- when the model was cached loadModel returned immediately and the new
    -- vehicle spawned exactly on top of the old one, which is what the
    -- physics engine resolves by launching one car skyward or burying it.
    -- Snapshotting after the load eliminates both cases.
    loadModel(selection.hash)

    local coords = GetEntityCoords(currentVehicle)
    local heading = GetEntityHeading(currentVehicle)
    local speed = GetEntitySpeed(currentVehicle)
    local velocity = GetEntityVelocity(currentVehicle)
    local vx, vy, vz = velocity.x, velocity.y, velocity.z
    -- Drop any upward component so SetVehicleForwardSpeed along the vehicle's
    -- pitched forward axis can't launch the new car off a crest.
    if vz > 0.0 then vz = 0.0 end

    -- Resolve a safe spawn Z. Spawning at the old vehicle's exact origin can
    -- bury the new vehicle when their chassis-center-to-wheel offsets differ
    -- (low-slung supercar to SUV puts the SUV origin below ground), and
    -- SetVehicleOnGroundProperly raycasting from inside terrain doesn't
    -- always recover. Float a small buffer above true ground so the snap-down
    -- has clean geometry; preserve old Z if the racer is airborne.
    local groundFound, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 3.0, false)
    local spawnZ = coords.z
    if groundFound then
        spawnZ = math.max(coords.z, groundZ + 1.0)
    end

    -- Delete the OLD vehicle before spawning the new one. SetEntityNoCollisionEntity
    -- isn't enough — a freshly spawned vehicle's first physics tick still
    -- reacts to terrain occluded by the old vehicle, and the gear/RPM init
    -- runs through corrupted state. Freeze the ped briefly so it doesn't
    -- ragdoll out during the single frame between vehicle delete and ped
    -- re-seat; invincibility blocks any one-tick fall damage.
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    if requestControlOfEntity(currentVehicle) then
        SetEntityAsMissionEntity(currentVehicle, true, true)
        DeleteVehicle(currentVehicle)
    end
    if DoesEntityExist(currentVehicle) then
        DeleteEntity(currentVehicle)
    end

    local newVehicle = CreateVehicle(selection.hash, coords.x, coords.y, spawnZ, heading, true, true)
    SetModelAsNoLongerNeeded(selection.hash)

    if newVehicle == 0 then
        DebugLog('Failed to create random race vehicle', selection.model)
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
        return false
    end

    SetEntityAsMissionEntity(newVehicle, true, true)
    SetVehicleOnGroundProperly(newVehicle)
    SetPedIntoVehicle(ped, newVehicle, -1)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)

    applyRaceSwapVehicleEffects(newVehicle)
    SetVehicleEngineOn(newVehicle, true, true, false)
    SetVehicleUndriveable(newVehicle, false)
    SetVehicleHandbrake(newVehicle, false)
    SetVehRadioStation(newVehicle, 'OFF')

    if speed > 0.1 then
        -- SetVehicleForwardSpeed spins the wheels to match speed; SetEntityVelocity
        -- then overwrites the rigid-body velocity with the pre-swap horizontal
        -- trajectory so the car keeps going where the player was heading.
        SetVehicleForwardSpeed(newVehicle, speed)
        SetEntityVelocity(newVehicle, vx, vy, vz)
        SetVehicleCurrentRpm(newVehicle, 1.0)

        -- Feed throttle input for ~30 frames after the swap. A freshly
        -- spawned vehicle starts in 1st gear; in 1st gear at 80mph the
        -- engine is rev-limited and produces no useful torque — which is
        -- the "stuck until you slow under 20mph" symptom. The auto-trans
        -- WILL upshift when it sees RPM-at-redline with throttle applied,
        -- but a just-swapped racer isn't giving throttle yet, so the sim
        -- sits in 1st gear forever. SetVehicleCurrentGear doesn't stick
        -- (auto-trans overrides it next tick); pinning the throttle does,
        -- because it's the natural upshift trigger.
        local pinVehicle = newVehicle
        local pinSpeed = speed
        CreateThread(function()
            for _ = 1, 30 do
                Wait(0)
                if not DoesEntityExist(pinVehicle) then return end
                if GetVehiclePedIsIn(PlayerPedId(), false) ~= pinVehicle then return end
                SetControlNormal(0, 71, 1.0) -- INPUT_VEH_ACCELERATE
                SetVehicleForwardSpeed(pinVehicle, pinSpeed)
                SetVehicleCurrentRpm(pinVehicle, 1.0)
            end
        end)
    end

    -- Grant keys asynchronously so the callback await doesn't kill momentum.
    CreateThread(function()
        giveKeysForRaceSwapVehicle(newVehicle)
    end)

    return true
end

local function cleanupObjects()
    DeleteObject(CreatorObjectLeft)
    DeleteObject(CreatorObjectRight)
    CreatorObjectLeft, CreatorObjectRight = nil, nil
end

local function deleteClosestObject(coords, model)
    local Obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, 5.0, model, 0, 0, 0)
    DeleteObject(Obj)
    ClearAreaOfObjects(coords.x, coords.y, coords.z, 50.0, 0)
end

local function createPile(offset, model)
    if model then
        loadModel(model)
        local Obj = CreateObject(model, offset.x, offset.y, offset.z, 0, 0, 0) -- CHANGE ONE OF THESE TO MAKE NETWORKED???
        PlaceObjectOnGroundProperly(Obj)
        FreezeEntityPosition(Obj, 1)
        SetEntityAsMissionEntity(Obj, 1, 1)
        SetEntityCollision(Obj, false, true)
        SetEntityCanBeDamaged(Obj, false)
        SetEntityInvincible(Obj, true)

        return Obj
    end
end

local function isPlayerNearby(playerCoords, otherPlayerCoords, maxDistance)
    return #(playerCoords - otherPlayerCoords) <= maxDistance
end

local function unGhostPlayer()
    SetLocalPlayerAsGhost(false)
    SetGhostedEntityAlpha(254)
    CurrentRaceData.Ghosted = false
end

local function ghostPlayer()
    SetLocalPlayerAsGhost(true)
    SetGhostedEntityAlpha(Config.Ghosting.Alpha)
    CurrentRaceData.Ghosted = true
end

local function checkAndDisableGhosting()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local vehicle = GetVehiclePedIsIn(playerPed, false)

    if not IsDriver(vehicle) then
        DebugLog('Racer was not the driver')
        unGhostPlayer()
        return
    end

    local racerSources = {}
    for _, racerData in pairs(CurrentRaceData.Racers) do
        racerSources[racerData.RacerSource] = true
    end

    local nearbyPlayersFound = false
    local activePlayers = GetActivePlayers()

    for i = 1, #activePlayers do
        local playerId = activePlayers[i]
        local serverId = GetPlayerServerId(playerId)

        if not racerSources[serverId] then
            local otherPed = GetPlayerPed(playerId)
            local otherPlayerVehicle = GetVehiclePedIsIn(otherPed, false)

            if otherPlayerVehicle ~= 0 and GetPedInVehicleSeat(otherPlayerVehicle, -1) == otherPed then
                local otherPlayerCoords = GetEntityCoords(otherPed)
                if isPlayerNearby(playerCoords, otherPlayerCoords, Config.Ghosting.DeGhostDistance) then
                    nearbyPlayersFound = true
                    break
                end
            end
        end
    end

    if nearbyPlayersFound then
        unGhostPlayer()
    else
        ghostPlayer()
    end
end

local function initGhosting()
    -- Initial ghosting setup
    ghostPlayer()

    -- Create a thread to continuously check for nearby players
    CreateThread(function()
        while CurrentRaceData.Started do
            if CurrentRaceData.GhostingTime > 0 and CurrentRaceData.GhostingTime < CurrentRaceData.RaceTime then
                DebugLog('Breaking Ghosting Due to timer')
                unGhostPlayer()
                break;
            end
            checkAndDisableGhosting()
            Wait(Config.Ghosting.DistanceLoopTime)
        end
    end)
end

local function isFinishOrStart(checkpoint)
    if CurrentRaceData.TotalLaps == 0 then
        if checkpoint == 1 or checkpoint == #CurrentRaceData.Checkpoints then
            return true
        else
            return false
        end
    else
        if checkpoint == 1 then
            return true
        else
            return false
        end
    end
end



function IsInRace()
    local retval = false
    if RaceData.InRace then
        retval = true
    end
    return retval
end

exports('IsInRace', IsInRace)


function IsInEditor()
    local retval = false
    if RaceData.InCreator then
        retval = true
    end
    return retval
end

exports('IsInEditor', IsInEditor)


function DrawText3Ds(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

local function markWithUglyWaypoint()
    if UseUglyWaypoint then
        if #CurrentRaceData.Checkpoints == CurrentRaceData.CurrentCheckpoint then
            SetNewWaypoint(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].coords.x,
                CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].coords.y)
        elseif #CurrentRaceData.Checkpoints > CurrentRaceData.CurrentCheckpoint + 1 then
            SetNewWaypoint(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 2].coords.x,
                CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 2].coords.y)
        else
            SetNewWaypoint(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.x,
                CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.y)
        end
    end
end

local function deleteCurrentRaceCheckpoints()
    -- Clear checkpoint lamps
    if ClearAllLamps then ClearAllLamps() end
    if StopLampUpdateThread then StopLampUpdateThread() end
    
    for _, checkpointData in pairs(CurrentRaceData.Checkpoints) do
        local blip = checkpointData.blip
        if blip then
            RemoveBlip(blip)
        end

        if checkpointData.pileleft then
            deleteClosestObject(checkpointData.offset.left, StartAndFinishModel)
            deleteClosestObject(checkpointData.offset.left, CheckpointPileModel)
        end

        if checkpointData.pileright then
            deleteClosestObject(checkpointData.offset.right, StartAndFinishModel)
            deleteClosestObject(checkpointData.offset.right, CheckpointPileModel)
        end
    end

    CurrentRaceData.RaceName = nil
    CurrentRaceData.Checkpoints = {}
    CurrentRaceData.Started = false
    CurrentRaceData.CurrentCheckpoint = 0
    CurrentRaceData.TotalLaps = 0
    CurrentRaceData.Lap = 0
    CurrentRaceData.RaceTime = 0
    CurrentRaceData.TotalTime = 0
    CurrentRaceData.BestLap = 0
    CurrentRaceData.FirstPerson = false
    CurrentRaceData.RandomVehicleSwapping = false
    CurrentRaceData.RandomVehicleCategories = {}
    CurrentRaceData.NoSameRandomVehicle = false
    CurrentRaceData.NoSameRandomCategory = false
    CurrentRaceData.UniqueRandomCategory = false
    CurrentRaceData.UsedRandomCategories = {}
    CurrentRaceData.SharedRandomCategories = false
    CurrentRaceData.SharedCategorySequence = {}
    CurrentRaceData.SharedCategorySequenceIndex = 0
    CurrentRaceData.RacerName = nil
    RaceData.InRace = false
end

local function updateCountdown(value)
    AnimpostfxPlay('CrossLineOut', 0, false)
    SendNUIMessage({
        type = 'race',
        action = "countdown",
        data = {
            value = value
        },
        active = true
    })
end

local function finishRace()
    if CurrentRaceData.RaceId == nil then
        return
    end
    local PlayerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(PlayerPed, false)
    if not IsDriver(vehicle) then
        NotifyHandler(Lang('kicked_cheese'), 'error')
        TriggerServerEvent("cw-racingapp:server:leaveRace", CurrentRaceData, 'cheeseing')
        return
    end

    local class = getVehicleClass(vehicle)
    local vehicleModel = getVehicleModel(vehicle)
    DebugLog('Best lap:', CurrentRaceData.BestLap, 'Total:', CurrentRaceData.TotalTime)
    local driftScore = 0
    if CurrentRaceData.Drift then
        ForceDriftScore()
        driftScore = GetCurrentDriftScore()
        PauseDriftScoring()
    end
    TriggerServerEvent('cw-racingapp:server:finishPlayer', CurrentRaceData, CurrentRaceData.TotalTime or 0,
        CurrentRaceData.TotalLaps, CurrentRaceData.BestLap or 0, class, vehicleModel, CurrentUserData.ranking, CurrentUserData.crew, driftScore or 0)
    unGhostPlayer()
    if IgnoreRoadsForGps then
        ClearGpsCustomRoute()
    else
        ClearGpsMultiRoute()
    end
    updateRaceUi()
    deleteCurrentRaceCheckpoints()
    SetTimeout(2000, function()
        CurrentRaceData.RaceId = nil
        if CurrentRaceData.Drift then
            StopDriftSystem()
        end
    end)
end

RegisterNetEvent('cw-racingapp:client:forceFinish', function()
    DebugLog('Focing Finish')
    resetBlips()
    AnimpostfxPlay('CrossLineOut', 0, false)
    PlayAudio(Config.Sounds.Finish.lib, Config.Sounds.Finish.sound)
    finishRace()

    -- Reset Race
    if IgnoreRoadsForGps then
        ClearGpsCustomRoute()
    else
        ClearGpsMultiRoute()
    end
    Countdown = 10
    HideTrack()
    updateCountdown(-1)
    unGhostPlayer()
    deleteCurrentRaceCheckpoints()
end)


local function getIndex(positions)
    for k, v in pairs(positions) do
        if v.RacerName == CurrentRaceData.RacerName then return k end
    end
end

local function clearBlips()
    for _, checkPointData in pairs(CurrentRaceData.Checkpoints) do
        if checkPointData then
            local Blip = checkPointData.blip
            if Blip then
                RemoveBlip(Blip)
            end
        end
    end
end

local function deleteAllCheckpoints()
    -- Clear any active checkpoint lamps first
    if ClearAllLamps then ClearAllLamps() end
    
    for _, checkPointData in pairs(CreatorData.Checkpoints) do
        if checkPointData then
            if checkPointData.pileleft then
                deleteClosestObject(checkPointData.offset.left, StartAndFinishModel)
                deleteClosestObject(checkPointData.offset.left, CheckpointPileModel)
            end
            if checkPointData.pileright then
                deleteClosestObject(checkPointData.offset.right, StartAndFinishModel)
                deleteClosestObject(checkPointData.offset.right, CheckpointPileModel)
            end
            local Blip = checkPointData.blip
            if Blip then
                RemoveBlip(Blip)
            end
        end
    end

    for _, checkPointData in pairs(CurrentRaceData.Checkpoints) do
        if checkPointData then
            if checkPointData.pileleft then
                deleteClosestObject(checkPointData.offset.left, StartAndFinishModel)
                deleteClosestObject(checkPointData.offset.left, CheckpointPileModel)
            end

            if checkPointData.pileright then
                deleteClosestObject(checkPointData.offset.right, StartAndFinishModel)
                deleteClosestObject(checkPointData.offset.right, CheckpointPileModel)
            end
        end
    end
end

function CreateCheckpointBlip(coords, id)
    local Blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    SetBlipSprite(Blip, 1)
    SetBlipDisplay(Blip, 4)
    SetBlipScale(Blip, Config.Blips.Generic.Size)
    SetBlipAsShortRange(Blip, true)
    SetBlipColour(Blip, Config.Blips.Generic.Color)
    ShowNumberOnBlip(Blip, id)
    SetBlipShowCone(Blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName("Checkpoint: " .. id)
    EndTextCommandSetBlipName(Blip)

    return Blip
end


local function updateGpsForRace(started)
    deleteAllCheckpoints()

    if IgnoreRoadsForGps then
        ClearGpsCustomRoute()
        StartGpsCustomRoute(Config.Gps.color, true, true)
    else
        ClearGpsMultiRoute()
        StartGpsMultiRoute(Config.Gps.color, true, true)
    end

    local currentCheckpoint = CurrentRaceData.CurrentCheckpoint or 1
    local lastCheckpoint = currentCheckpoint + Config.MarkAmountOfCheckpointsAhead - 1
    local totalCheckpoints = #CurrentRaceData.Checkpoints
    local isCircuit = CurrentRaceData.TotalLaps > 0

    for i = currentCheckpoint, lastCheckpoint do
        local checkpointIndex = isCircuit and ((i - 1) % totalCheckpoints) + 1 or i
        if checkpointIndex > totalCheckpoints and not isCircuit then break end

        local checkpointData = CurrentRaceData.Checkpoints[checkpointIndex]
        local coords = checkpointData.coords

        if IgnoreRoadsForGps then
            AddPointToGpsCustomRoute(coords.x, coords.y, coords.z or 0.0)
        else
            AddPointToGpsMultiRoute(coords.x, coords.y, coords.z or 0.0)
        end

        local isStartFinish = isFinishOrStart(checkpointIndex)
        local isNight = IsNightTime and IsNightTime() or false
        
        -- Skip flag prop at start/finish during nighttime (lamps will be used instead)
        if not (isStartFinish and isNight) then
            local pileModel = isStartFinish and StartAndFinishModel or CheckpointPileModel
            checkpointData.pileleft = createPile(checkpointData.offset.left, pileModel)
            checkpointData.pileright = createPile(checkpointData.offset.right, pileModel)
        end

        if checkpointData.blip then
            SetBlipDisplay(checkpointData.blip, 2) 
            ShowHeightOnBlip(checkpointData.blip, true) 
        end
    end

    if IgnoreRoadsForGps then
        SetGpsCustomRouteRender(ShowGpsRoute, 16, 16)
    else
        SetGpsMultiRouteRender(ShowGpsRoute, 16, 16)
    end
    
    -- Update checkpoint lamps (only visible at night)
    if UpdateRaceLamps then
        UpdateRaceLamps(CurrentRaceData.Checkpoints, currentCheckpoint, CurrentRaceData.TotalLaps, Config.MarkAmountOfCheckpointsAhead)
    end
end

local function setupBlipsForRace(started)
    clearBlips()
    if started and CurrentRaceData.TotalLaps > 0 then
        for k = 1, #CurrentRaceData.Checkpoints, 1 do
            if k > 1 then
                CurrentRaceData.Checkpoints[k].blip = CreateCheckpointBlip(CurrentRaceData.Checkpoints[k].coords, k)
            end
        end
        CurrentRaceData.Checkpoints[1].blip = CreateCheckpointBlip(CurrentRaceData.Checkpoints[1].coords,
            #CurrentRaceData.Checkpoints + 1)
    else
        -- First Lap setup
        for k, v in pairs(CurrentRaceData.Checkpoints) do
            CurrentRaceData.Checkpoints[k].blip = CreateCheckpointBlip(v.coords, k)
        end
    end
end

local function deleteClosestCheckpoint()
    local newCheckpoints = {}
    if RaceData.ClosestCheckpoint ~= 0 then
        local ClosestCheckpoint = CreatorData.Checkpoints[RaceData.ClosestCheckpoint]

        if ClosestCheckpoint then
            if ClosestCheckpoint.blip then
                RemoveBlip(ClosestCheckpoint.blip)
            end

            if ClosestCheckpoint.pileleft then
                deleteClosestObject(ClosestCheckpoint.offset.left, StartAndFinishModel)
                deleteClosestObject(ClosestCheckpoint.offset.left, CheckpointPileModel)
                PileLeft = nil
            end

            if ClosestCheckpoint.pileright then
                deleteClosestObject(ClosestCheckpoint.offset.right, StartAndFinishModel)
                deleteClosestObject(ClosestCheckpoint.offset.right, CheckpointPileModel)
            end

            for id, data in pairs(CreatorData.Checkpoints) do
                if id ~= RaceData.ClosestCheckpoint then
                    newCheckpoints[#newCheckpoints + 1] = data
                end
            end
            CreatorData.Checkpoints = newCheckpoints
        else
            NotifyHandler(Lang("slow_down"), 'error')
        end
    else
        NotifyHandler(Lang("slow_down"), 'error')
    end
end

local function deleteCreatorCheckpoints()
    for id, _ in pairs(CreatorData.Checkpoints) do
        local currentCheckpoint = CreatorData.Checkpoints[id]

        local blip = currentCheckpoint.blip
        if blip then
            RemoveBlip(blip)
        end

        if currentCheckpoint then
            if currentCheckpoint.pileleft then
                deleteClosestObject(currentCheckpoint.offset.left, CheckpointPileModel)
                deleteClosestObject(currentCheckpoint.offset.left, StartAndFinishModel)
                PileLeft = nil
            end

            if currentCheckpoint.pileright then
                deleteClosestObject(currentCheckpoint.offset.right, CheckpointPileModel)
                deleteClosestObject(currentCheckpoint.offset.right, StartAndFinishModel)
            end
        end
    end
end

local function setupPiles()
    for k, v in pairs(CreatorData.Checkpoints) do
        if not CreatorData.Checkpoints[k].pileleft then
            CreatorData.Checkpoints[k].pileleft = createPile(v.offset.left, CheckpointPileModel)
        end

        if not CreatorData.Checkpoints[k].pileright then
            CreatorData.Checkpoints[k].pileright = createPile(v.offset.right, CheckpointPileModel)
        end
    end
end

local function saveTrack()
    local raceDistance = 0

    for k, v in pairs(CreatorData.Checkpoints) do
        if k + 1 <= #CreatorData.Checkpoints then
            local checkpointdistance = #(vector3(v.coords.x, v.coords.y, v.coords.z) -
                vector3(CreatorData.Checkpoints[k + 1].coords.x,
                    CreatorData.Checkpoints[k + 1].coords.y, CreatorData.Checkpoints[k + 1].coords.z))
            raceDistance = raceDistance + checkpointdistance
        end
    end

    CreatorData.RaceDistance = raceDistance
    TriggerServerEvent('cw-racingapp:server:saveTrack', CreatorData)
    Lang("slow_down")
    NotifyHandler(Lang("race_saved") .. '(' .. CreatorData.RaceName .. ')', 'success')

    deleteCreatorCheckpoints()
    cleanupObjects()

    RaceData.InCreator = false
    CreatorData.RaceName = nil
    CreatorData.RacerId = nil
    CreatorData.RacerName = nil
    CreatorData.Checkpoints = {}
    CreatorData.IsEdit = false
    CreatorData.TrackId = nil
end

local function getClosestCheckpoint()
    local pos = GetEntityCoords(PlayerPedId(), true)
    local current = nil
    local dist = nil
    for id, _ in ipairs(CreatorData.Checkpoints) do
        if current ~= nil then
            if #(pos -
                    vector3(CreatorData.Checkpoints[id].coords.x, CreatorData.Checkpoints[id].coords.y,
                        CreatorData.Checkpoints[id].coords.z)) < dist then
                current = id
                dist = #(pos -
                    vector3(CreatorData.Checkpoints[id].coords.x, CreatorData.Checkpoints[id].coords.y,
                        CreatorData.Checkpoints[id].coords.z))
            end
        else
            dist = #(pos -
                vector3(CreatorData.Checkpoints[id].coords.x, CreatorData.Checkpoints[id].coords.y,
                    CreatorData.Checkpoints[id].coords.z))
            current = id
        end
    end
    RaceData.ClosestCheckpoint = current
    CreatorData.ClosestCheckpoint = current
end

local function startCreatorUIThread()
    CreateThread(function()
        while true do
            if RaceData.InCreator then
                SendNUIMessage({
                    action = "update",
                    type = "creator",
                    data = CreatorData,
                    racedata = RaceData,
                    buttons = Config.Buttons,
                    active = true
                })
            else
                SendNUIMessage({
                    action = "update",
                    type = "creator",
                    data = CreatorData,
                    racedata = RaceData,
                    buttons = Config.Buttons,
                    active = false
                })
                break
            end
            Wait(200)
        end
    end)
end

local function redrawBlips()
    for id, CheckpointData in pairs(CreatorData.Checkpoints) do
        RemoveBlip(CheckpointData.blip)
        CheckpointData.blip = CreateCheckpointBlip(CheckpointData.coords, id)
    end
end

local function addCheckpoint(checkpointId)
    local PlayerPed = PlayerPedId()
    local PlayerPos = GetEntityCoords(PlayerPed)
    local PlayerVeh = GetVehiclePedIsIn(PlayerPed, false)
    local Offset = {
        left = {
            x = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).x,
            y = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).y,
            z = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).z
        },
        right = {
            x = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).x,
            y = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).y,
            z = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).z
        }
    }
    if checkpointId ~= nil then
        RemoveBlip(tonumber(CreatorData.Checkpoints[tonumber(checkpointId)].blip))
        local PileLeft = CreatorData.Checkpoints[tonumber(checkpointId)].pileleft
        if PileLeft then
            deleteClosestObject(CreatorData.Checkpoints[tonumber(checkpointId)].offset.left, StartAndFinishModel)
            deleteClosestObject(CreatorData.Checkpoints[tonumber(checkpointId)].offset.left, CheckpointPileModel)
        end

        local PileRight = CreatorData.Checkpoints[tonumber(checkpointId)].pileright
        if PileRight then
            deleteClosestObject(CreatorData.Checkpoints[tonumber(checkpointId)].offset.right, StartAndFinishModel)
            deleteClosestObject(CreatorData.Checkpoints[tonumber(checkpointId)].offset.right, CheckpointPileModel)
        end

        CreatorData.Checkpoints[tonumber(checkpointId)] = {
            coords = {
                x = PlayerPos.x,
                y = PlayerPos.y,
                z = PlayerPos.z
            },
            offset = Offset
        }
    else
        CreatorData.Checkpoints[#CreatorData.Checkpoints + 1] = {
            coords = {
                x = PlayerPos.x,
                y = PlayerPos.y,
                z = PlayerPos.z
            },
            offset = Offset
        }
    end
    if #CreatorData.Checkpoints > Config.MaxCheckpoints then
        NotifyHandler(Lang("max_checkpoints") .. Config.MaxCheckpoints, 'error')
    end
    redrawBlips()
end


local function moveCheckpoint()
    local dialog

    if Config.OxInput then
        dialog = lib.inputDialog(Lang("edit_checkpoint_header"), {
            {
                label = "Checkpoint number", -- text you want to be displayed as a place holder
                name = "number",            -- name of the input should be unique otherwise it might override
                type = "number",            -- type of the input - number will not allow non-number characters in the field so only accepts 0-9
                isRequired = true,          -- Optional [accepted values: true | false] but will submit the form if no value is inputted
            },
        })
    else
        dialog = exports['qb-input']:ShowInput({
            header = Lang("edit_checkpoint_header"),
            submitText = Lang("confirm"),
            inputs = {
                {
                    text = "Checkpoint number", -- text you want to be displayed as a place holder
                    name = "number",            -- name of the input should be unique otherwise it might override
                    type = "number",            -- type of the input - number will not allow non-number characters in the field so only accepts 0-9
                    isRequired = true,          -- Optional [accepted values: true | false] but will submit the form if no value is inputted
                },
            },
        })
    end

    if dialog ~= nil then
        if UseDebug then
            print('Moving checkpoint', dialog.number or dialog[1])
        end
        addCheckpoint(dialog.number or dialog[1])
    end
end

local function clickAddCheckpoint()
    addCheckpoint()
end

local function clickDeleteCheckpoint()
    if CreatorData.Checkpoints and next(CreatorData.Checkpoints) then
        deleteClosestCheckpoint()
    else
        NotifyHandler(Lang("no_checkpoints_to_delete"), 'error')
    end
end

local function clickMoveCheckpoint()
    if CreatorData.Checkpoints and next(CreatorData.Checkpoints) then
        moveCheckpoint()
    else
        NotifyHandler(Lang("no_checkpoints_to_edit"), 'error')
    end
end

local function clickSaveRace()
    if CreatorData.Checkpoints and #CreatorData.Checkpoints >= Config.MinimumCheckpoints then
        saveTrack()
    else
        NotifyHandler(Lang("not_enough_checkpoints") .. '(' .. Config.MinimumCheckpoints .. ')', 'error')
    end
end

local function clickIncreaseDistance()
    if CreatorData.TireDistance < Config.MaxTireDistance then
        CreatorData.TireDistance = CreatorData.TireDistance + 1.0
    else
        NotifyHandler(Lang("max_tire_distance") .. Config.MaxTireDistance)
    end
end

local function clickDecreaseDistance()
    if CreatorData.TireDistance > Config.MinTireDistance then
        CreatorData.TireDistance = CreatorData.TireDistance - 1.0
    else
        NotifyHandler(Lang("min_tire_distance") .. Config.MinTireDistance)
    end
end

local function clickExit()
    if not CreatorData.ConfirmDelete then
        CreatorData.ConfirmDelete = true
        NotifyHandler(Lang("editor_confirm"), 'error')
    else
        deleteCreatorCheckpoints()

        cleanupObjects()
        RaceData.InCreator = false
        CreatorData.RaceName = nil
        CreatorData.Checkpoints = {}
        NotifyHandler(Lang("editor_canceled"), 'error')
        CreatorData.ConfirmDelete = false
    end
end

local function startCreatorLoopThread()
    CreateThread(function()
        while RaceData.InCreator do
            local PlayerPed = PlayerPedId()
            local PlayerVeh = GetVehiclePedIsIn(PlayerPed, false)

            if PlayerVeh == 0 then
                local coords = GetEntityCoords(PlayerPedId())
                DrawText3Ds(coords.x, coords.y, coords.z, Lang("get_in_vehicle"))
            end
            Wait(10)
        end
    end)
    CreateThread(function()
        while RaceData.InCreator do
            getClosestCheckpoint()
            setupPiles()
            Wait(1000)
        end
        DebugLog('Exiting Closest Checkpoint check and pile setup thread')
    end)
    -- Creator
    CreateThread(function()
        while RaceData.InCreator do
            local PlayerPed = PlayerPedId()
            local PlayerVeh = GetVehiclePedIsIn(PlayerPed, false)
            if CreatorObjectLeft and CreatorObjectRight ~= nil then
                cleanupObjects()
            end
            CreatorCheckpointObject = CheckpointPileModel

            if PlayerVeh ~= 0 then
                local Offset = {
                    left = {
                        x = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).x,
                        y = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).y,
                        z = (GetOffsetFromEntityInWorldCoords(PlayerVeh, -CreatorData.TireDistance, 0.0, 0.0)).z
                    },
                    right = {
                        x = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).x,
                        y = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).y,
                        z = (GetOffsetFromEntityInWorldCoords(PlayerVeh, CreatorData.TireDistance, 0.0, 0.0)).z
                    }
                }
                DrawMarker(22, Offset.left.x, Offset.left.y, Offset.left.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 2.5, 1.5,
                    255, 150, 0, 255, 0, 1, 0, 0, 0, 0, 0)
                DrawMarker(22, Offset.right.x, Offset.right.y, Offset.right.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 2.5,
                    1.5, 255, 150, 0, 255, 0, 1, 0, 0, 0, 0, 0)
            end
            Wait(0)
        end
    end)
end

local function startRaceUi()
    CreateThread(function()
        while true do
            if CurrentRaceData.Checkpoints ~= nil and next(CurrentRaceData.Checkpoints) ~= nil then
                if CurrentRaceData.Started then
                    CurrentRaceData.RaceTime = GetTimeDifference(GetGameTimer(), lapStartTime)
                    CurrentRaceData.TotalTime = GetTimeDifference(GetGameTimer(), startTime)
                end
                updateRaceUi()
            else
                if not FinishedUITimeout then
                    FinishedUITimeout = true
                    SetTimeout(10000, function()
                        FinishedUITimeout = false
                        SendNUIMessage({
                            action = "update",
                            type = "race",
                            data = {},
                            racedata = RaceData,
                            active = false
                        })
                    end)
                end
                break
            end
            Wait(100)
        end
    end)
end

local function copyWihoutId(original)
    local copy = {}
    for _, value in pairs(original) do
        copy[#copy + 1] = value
    end
    return copy
end

local function bothOpponentsHaveDefinedPositions(aSrc, bSrc)
    local currentPlayer = GetPlayerPed(-1)
    local currentPlayerCoords = GetEntityCoords(currentPlayer)

    local aPly = GetPlayerFromServerId(aSrc)
    local aTarget = GetPlayerPed(aPly)
    local aCoords = GetEntityCoords(aTarget)

    local bPly = GetPlayerFromServerId(bSrc)
    local bTarget = GetPlayerPed(bPly)
    local bCoords = GetEntityCoords(bTarget)

    if currentPlayer == aTarget then
        return #(currentPlayerCoords - bCoords) > 0 -- not defined if 0
    elseif currentPlayer == bTarget then
        return #(currentPlayerCoords - aCoords) > 0 -- not defined if 0
    else
        if #(currentPlayerCoords - aCoords) == 0 then
            return false
        elseif #(currentPlayerCoords - bCoords) == 0 then
            return false
        else
            return #(bCoords - aCoords) > 0
        end
    end
end

local function distanceToCheckpoint(src, checkpoint)
    local ped = GetPlayerFromServerId(src)
    local target = GetPlayerPed(ped)
    local pos = GetEntityCoords(target)
    local next
    if checkpoint + 1 > #CurrentRaceData.Checkpoints then
        next = CurrentRaceData.Checkpoints[1]
    else
        next = CurrentRaceData.Checkpoints[checkpoint + 1]
    end

    local distanceToNext = #(pos - vector3(next.coords.x, next.coords.y, next.coords.z))
    return distanceToNext
end

local function placements()
    local tempPositions = copyWihoutId(CurrentRaceData.Racers)
    if #tempPositions > 1 then
        table.sort(tempPositions, function(a, b)
            if a.Lap > b.Lap then
                return true
            elseif a.Lap < b.Lap then
                return false
            elseif a.Lap == b.Lap then
                if a.Checkpoint > b.Checkpoint then
                    return true
                elseif a.Checkpoint < b.Checkpoint then
                    return false
                elseif a.Checkpoint == b.Checkpoint then
                    if CheckDistance and bothOpponentsHaveDefinedPositions(a.RacerSource, b.RacerSource) and not (a.Finished or b.Finished)  then
                        return distanceToCheckpoint(a.RacerSource, a.Checkpoint) <
                            distanceToCheckpoint(b.RacerSource, b.Checkpoint)
                    else
                        if a.RaceTime ~= nil and b.RaceTime ~= nil and a.RaceTime < b.RaceTime then
                            return true
                        else
                            return false
                        end
                    end
                end
            end
        end)
    end
    return tempPositions
end

local function positionThread()
    CreateThread(function()
        while true do
            if CurrentRaceData.Checkpoints ~= nil and next(CurrentRaceData.Checkpoints) ~= nil then
                local positions = placements()
                local MyPosition = getIndex(positions)
                CurrentRaceData.Position = MyPosition
                CurrentRaceData.Positions = positions
            else
                break
            end
            Wait(1000)
        end
    end)
end

MarkerType = Config.DrawTextSetup.markerType or 1 -- Vertical cylinder
MinHeight = Config.DrawTextSetup.minHeight or 1.0
MaxHeight = Config.DrawTextSetup.maxHeight or 100.0
BaseSize = Config.DrawTextSetup.baseSize or 0.1                                          -- Thin pillar
MarkerColor = Config.DrawTextSetup.markerColor or { r = 255, g = 255, b = 255, a = 200 } -- White, semi-transparent
DistanceColor = Config.DrawTextSetup.distanceColor or { r = 0, g = 255, b = 0, a = 255 } -- Cyan
PrimaryColor = Config.DrawTextSetup.primaryColor or { r = 255, g = 0, b = 250, a = 255 } -- White

local function getFinishLabel(totalCheckpoints, index)
    if CurrentRaceData.TotalLaps == 0 and totalCheckpoints == index then -- if sprint
        return Lang('finish')
    elseif index - 1 == totalCheckpoints then                            -- if laps
        if CurrentRaceData.Lap == CurrentRaceData.TotalLaps then
            return Lang('finish')
        else
            return Lang('next_lap')
        end
    end
    return nil
end

local function getCheckpointCoord(index, totalCheckpoints)
    if CurrentRaceData.TotalLaps == 0 and index > #CurrentRaceData.Checkpoints then
        return nil
    end
    if CurrentRaceData.Lap > 0 and CurrentRaceData.Lap == CurrentRaceData.TotalLaps then
        if index - 1 == totalCheckpoints then
            return vector3(
                CurrentRaceData.Checkpoints[1].coords.x,
                CurrentRaceData.Checkpoints[1].coords.y,
                CurrentRaceData.Checkpoints[1].coords.z
            )
        elseif index > totalCheckpoints and CurrentRaceData.Lap + 1 > CurrentRaceData.TotalLaps then
            return nil
        end
    end
    index = (index - 1) % totalCheckpoints + 1
    return vector3(
        CurrentRaceData.Checkpoints[index].coords.x,
        CurrentRaceData.Checkpoints[index].coords.y,
        CurrentRaceData.Checkpoints[index].coords.z
    )
end

local function getUpcomingCheckpoints()
    local coord1, coord2, coord3
    local coord1Label, coord2Label, coord3Label
    local totalCheckpoints = #CurrentRaceData.Checkpoints
    local currentIndex = CurrentRaceData.CurrentCheckpoint + 1
    local checkpoints = {}

    if CurrentRaceData.Lap < 2 and CurrentRaceData.CurrentCheckpoint == 1 then
        checkpoints[1] = {
            coord = vector3(
                CurrentRaceData.Checkpoints[1].coords.x,
                CurrentRaceData.Checkpoints[1].coords.y,
                CurrentRaceData.Checkpoints[1].coords.z
            ),
            label = Lang('starting_line')
        }
    end

    coord1 = getCheckpointCoord(currentIndex, totalCheckpoints)
    coord2 = getCheckpointCoord(currentIndex + 1, totalCheckpoints)
    coord3 = getCheckpointCoord(currentIndex + 2, totalCheckpoints)

    coord1Label = getFinishLabel(totalCheckpoints, currentIndex) or Lang("checkpoint_next")
    coord2Label = getFinishLabel(totalCheckpoints, currentIndex + 1) or Lang("checkpoint_2nd")
    coord3Label = getFinishLabel(totalCheckpoints, currentIndex + 2) or Lang("checkpoint_3rd")

    if coord1 then checkpoints[#checkpoints + 1] = { coord = coord1, label = coord1Label } end
    if coord2 then checkpoints[#checkpoints + 1] = { coord = coord2, label = coord2Label } end
    if coord3 then checkpoints[#checkpoints + 1] = { coord = coord3, label = coord3Label } end
    return checkpoints
end

function Draw3DText(coords, text, scale, color)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)

    if onScreen then
        SetTextScale(scale, scale)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(color.r, color.g, color.b, color.a)
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(x, y)
    end
end

function DrawRacingMarker(coords, height)
    DrawMarker(
        MarkerType,
        coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0,                  -- Direction
        0.0, 0.0, 0.0,                  -- Rotation
        BaseSize, BaseSize, height,     -- Scale
        MarkerColor.r, MarkerColor.g, MarkerColor.b, MarkerColor.a,
        false, true, 2, nil, nil, false -- Bob, face camera, rotate
    )
end

local function markWithDrawTextWaypoint()
    if UseDrawTextWaypoint then
        CreateThread(function()
            while true and RaceData.InRace do
                local playerPed = PlayerPedId()
                local playerCoords = GetEntityCoords(playerPed)

                local checkpoints = getUpcomingCheckpoints()

                for i, checkpoint in ipairs(checkpoints) do
                    local distance = #(playerCoords - checkpoint.coord)
                    local height = math.min(MaxHeight, math.max(MinHeight, distance / 2.5))

                    -- Draw the marker
                    DrawRacingMarker(checkpoint.coord, height)

                    -- Calculate text positions
                    local baseTextHeight = checkpoint.coord.z + height
                    local labelHeight = baseTextHeight + 0.7 + height * 0.05
                    local distanceHeight = baseTextHeight + 0.5

                    local color = DistanceColor
                    if i == 1 or i == 2 and #checkpoints > 3 then color = PrimaryColor end

                    -- Draw checkpoint label
                    local labelCoords = vector3(checkpoint.coord.x, checkpoint.coord.y, labelHeight)
                    Draw3DText(labelCoords, checkpoint.label, 0.25, color)

                    -- Draw distance
                    local distanceCoords = vector3(checkpoint.coord.x, checkpoint.coord.y, distanceHeight)
                    Draw3DText(distanceCoords, string.format("%.0fm", distance), 0.5, DistanceColor)
                end

                Wait(0)
            end
        end)
    end
end

local function sendRacerUpdate(finished)
    if not CurrentRaceData or not CurrentRaceData.RaceId then return end
    local evt = CurrentRaceData.Drift and 'cw-racingapp:server:updateRacerDataDrift' or 'cw-racingapp:server:updateRacerData'
    if CurrentRaceData.Drift then
        local driftScore = GetCurrentDriftScore()
        TriggerServerEvent(evt, CurrentRaceData.RaceId, CurrentRaceData.CurrentCheckpoint, CurrentRaceData.Lap, finished, CurrentRaceData.TotalTime, driftScore)
    else
        TriggerServerEvent(evt, CurrentRaceData.RaceId, CurrentRaceData.CurrentCheckpoint, CurrentRaceData.Lap, finished, CurrentRaceData.TotalTime)
    end
end

local function initRacingHudThread()
    CreateThread(function()
        while not Kicked and CurrentRaceData.RaceName ~= nil do
            if CurrentRaceData.Started then
                local ped = PlayerPedId()
                local pos = GetEntityCoords(ped)
                local checkpointId
                if CurrentRaceData.CurrentCheckpoint + 1 > #CurrentRaceData.Checkpoints then
                    checkpointId = 1
                else
                    checkpointId = CurrentRaceData.CurrentCheckpoint + 1
                end
                local data = CurrentRaceData.Checkpoints[checkpointId]
                local currentCheckpointCenterCoords = vector3(data.coords.x, data.coords.y, data.coords.z)
                local CheckpointDistance = #(pos - currentCheckpointCenterCoords)
                local MaxDistance = getMaxDistance(currentCheckpointCenterCoords, CurrentRaceData.Checkpoints[checkpointId].offset)
                if CheckpointDistance < MaxDistance then
                    if CurrentRaceData.TotalLaps == 0 then                                               -- Sprint
                        if CurrentRaceData.CurrentCheckpoint + 1 < #CurrentRaceData.Checkpoints then     -- passed checkpoint
                            CurrentRaceData.CurrentCheckpoint = CurrentRaceData.CurrentCheckpoint + 1
                            sendRacerUpdate(false)
                            doPilePfx()
                            PlayAudio(Config.Sounds.Checkpoint.lib, Config.Sounds.Checkpoint.sound)
                            passedBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].blip)
                            nextBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].blip)
                            updateGpsForRace(true)
                            markWithUglyWaypoint()
                        else     -- finished
                            doPilePfx()
                            CurrentRaceData.CurrentCheckpoint = CurrentRaceData.CurrentCheckpoint + 1
                            sendRacerUpdate(true)
                            PlayAudio(Config.Sounds.Finish.lib, Config.Sounds.Finish.sound)
                            finishRace()
                        end
                        timeWhenLastCheckpointWasPassed = GetGameTimer()
                    else                                                                                 -- Circuit
                        if CurrentRaceData.CurrentCheckpoint + 1 > #CurrentRaceData.Checkpoints then     -- If new lap
                            if CurrentRaceData.Lap + 1 > CurrentRaceData.TotalLaps then                  -- if finish
                                doPilePfx()
                                if CurrentRaceData.RaceTime < CurrentRaceData.BestLap then
                                    CurrentRaceData.BestLap = CurrentRaceData.RaceTime
                                    DebugLog('racetime less than bestlap',
                                        CurrentRaceData.RaceTime < CurrentRaceData.BestLap, CurrentRaceData.RaceTime,
                                        CurrentRaceData.BestLap)
                                elseif CurrentRaceData.BestLap == 0 then
                                    DebugLog('bestlap == 0', CurrentRaceData.BestLap)
                                    CurrentRaceData.BestLap = CurrentRaceData.RaceTime
                                end
                                CurrentRaceData.CurrentCheckpoint = CurrentRaceData.CurrentCheckpoint + 1
                                sendRacerUpdate(true)
                                finishRace()
                                AnimpostfxPlay('CrossLineOut', 0, false)
                                PlayAudio(Config.Sounds.Finish.lib, Config.Sounds.Finish.sound)
                            else     -- if next lap
                                doPilePfx()
                                resetBlips()
                                PlayAudio(Config.Sounds.Checkpoint.lib, Config.Sounds.Checkpoint.sound)
                                if CurrentRaceData.RaceTime < CurrentRaceData.BestLap then
                                    DebugLog('racetime less than bestlap',
                                        CurrentRaceData.RaceTime < CurrentRaceData.BestLap, CurrentRaceData.RaceTime,
                                        CurrentRaceData.BestLap)
                                    CurrentRaceData.BestLap = CurrentRaceData.RaceTime
                                elseif CurrentRaceData.BestLap == 0 then
                                    DebugLog('bestlap == 0', CurrentRaceData.BestLap)
                                    CurrentRaceData.BestLap = CurrentRaceData.RaceTime
                                end
                                lapStartTime = GetGameTimer()
                                CurrentRaceData.Lap = CurrentRaceData.Lap + 1
                                CurrentRaceData.CurrentCheckpoint = 1
                                sendRacerUpdate(false)
                                if CurrentRaceData.RandomVehicleSwapping then
                                    swapToRandomRaceVehicle()
                                end

                                passedBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].blip)
                                nextBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].blip)
                                markWithUglyWaypoint()
                                updateGpsForRace(true)
                            end
                            timeWhenLastCheckpointWasPassed = GetGameTimer()
                        else     -- if next checkpoint
                            CurrentRaceData.CurrentCheckpoint = CurrentRaceData.CurrentCheckpoint + 1
                            if CurrentRaceData.CurrentCheckpoint ~= #CurrentRaceData.Checkpoints then
                                sendRacerUpdate(false)
                                passedBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].blip)
                                nextBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].blip)
                                markWithUglyWaypoint()
                            else
                                sendRacerUpdate(false)
                                passedBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint].blip)
                                nextBlip(CurrentRaceData.Checkpoints[1].blip)
                                markWithUglyWaypoint()
                            end
                            timeWhenLastCheckpointWasPassed = GetGameTimer()
                            doPilePfx()
                            updateGpsForRace(true)
                            PlayAudio(Config.Sounds.Checkpoint.lib, Config.Sounds.Checkpoint.sound)
                        end
                    end
                else
                    checkCheckPointTime()
                end
            else
                local data = CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint]
                DrawMarker(4, data.coords.x, data.coords.y, data.coords.z + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.9, 1.5,
                    1.5, 255, 255, 255, 255, 0, 1, 0, 0, 0, 0, 0)
                nextBlip(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].blip)
            end
            Wait(0)
        end
        DebugLog('Breaking racing hud thread')
    end)
end

local function handleActiveRace(raceData, trackCheckpoints, Laps)
    DebugLog('Race being setup:', json.encode(raceData))
    local checkpoints = trackCheckpoints
    if raceData.Reversed then checkpoints = reverseTable(checkpoints) end
    CurrentRaceData = {
        TrackId = raceData.TrackId,
        RaceId = raceData.RaceId,
        Creator = raceData.Creator,
        SetupCitizenId = raceData.SetupCitizenId,
        SetupRacerName = raceData.SetupRacerName,
        RacerName = raceData.RacerName,
        RacerId = raceData.RacerId,
        RaceName = raceData.RaceName,
        Ghosting = raceData.Ghosting,
        GhostingTime = raceData.GhostingTime,
        Ranked = raceData.Ranked,
        Reversed = raceData.Reversed,
        FirstPerson = raceData.FirstPerson,
        Started = false,
        CurrentCheckpoint = 1,
        TotalLaps = Laps,
        Lap = 1,
        RaceTime = 0,
        TotalTime = 0,
        BestLap = 0,
        MaxClass = raceData.MaxClass,
        Racers = {},
        Position = 0,
        Drift = raceData.Drift or false,
        RandomVehicleSwapping = raceData.RandomVehicleSwapping or false,
        RandomVehicleCategories = raceData.RandomVehicleCategories or {},
        NoSameRandomVehicle = raceData.NoSameRandomVehicle or false,
        NoSameRandomCategory = raceData.NoSameRandomCategory or false,
        UniqueRandomCategory = raceData.UniqueRandomCategory or false,
        UsedRandomCategories = {},
        SharedRandomCategories = raceData.SharedRandomCategories or false,
        SharedCategorySequence = {},
        SharedCategorySequenceIndex = 0,
        ItemPayoutData = raceData.ItemPayoutData or nil,
    }
    DebugLog('Race Was setup:', json.encode(CurrentRaceData, { indent = true }))
    CurrentRaceData.Checkpoints = checkpoints
    initRacingHudThread()
    DisplayTrack(CurrentRaceData)
    startRaceUi()
    markWithDrawTextWaypoint()
    
    -- Start the lamp update thread for day/night transitions
    -- Note: Lamps are spawned via updateGpsForRace() which is called by DisplayTrack
    if StartLampUpdateThread then
        StartLampUpdateThread(function()
            return CurrentRaceData
        end)
    end
end

-----------------------
---- Client Events ----
-----------------------

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if IgnoreRoadsForGps then
            ClearGpsCustomRoute()
        else
            ClearGpsMultiRoute()
        end
        deleteAllCheckpoints()
        clearBlips()
        -- Clear lamps on resource stop
        if ClearAllLamps then ClearAllLamps() end
        if StopLampUpdateThread then StopLampUpdateThread() end
    end
end)

RegisterNetEvent('cw-racingapp:client:readyJoinRace', function(raceData)
    local PlayerPed = PlayerPedId()
    local PlayerIsInVehicle = IsPedInAnyVehicle(PlayerPed, false)
    local class
    if PlayerIsInVehicle then
        class = getVehicleClass(GetVehiclePedIsIn(PlayerPed, false))
    else
        NotifyHandler(Lang('not_in_a_vehicle'), 'error')
        return
    end

    if MyCarClassIsAllowed(raceData.MaxClass, class) then
        raceData.RacerName = CurrentUserData.racername
        raceData.RacerCrew = CurrentUserData.crew
        raceData.RacerId = CurrentUserData.racerid
        raceData.PlayerVehicleEntity = GetVehiclePedIsIn(PlayerPed, false)
        TriggerServerEvent('cw-racingapp:server:joinRace', raceData)
    else
        NotifyHandler(Lang('incorrect_class'), 'error')
    end
end)

local function openCreatorUi()
    startCreatorUIThread()
    redrawBlips()
    startCreatorLoopThread()
end

RegisterNetEvent('cw-racingapp:client:startRaceEditor', function(raceName, racerName, racerid, trackId, checkpoints)
    if not RaceData.InCreator then
        CreatorData.RaceName = raceName
        CreatorData.RacerName = racerName
        CreatorData.RacerId = racerid
        RaceData.InCreator = true
        if type(checkpoints) == 'table' then
            DebugLog('Using shared, checkpoint existed')
            CreatorData.Checkpoints = checkpoints
            clickSaveRace()
            return
        end
        if trackId then
            DebugLog('Opening RaceTrack Editor')
            local result = cwCallback.await('cw-racingapp:server:getTrackData', trackId)
            if result then
                CreatorData.RaceName = raceName
                CreatorData.RacerName = racerName
                CreatorData.RacerId = racerid
                CreatorData.TrackId = trackId
                CreatorData.Checkpoints = {}
                CreatorData.TireDistance = 3.0
                CreatorData.ConfirmDelete = false
                CreatorData.IsEdit = true
                DebugLog('Checkpoints in track:', #result.Checkpoints or 0)
                for _, checkpoint in pairs(result.Checkpoints) do
                    CreatorData.Checkpoints[#CreatorData.Checkpoints + 1] = checkpoint
                end
                openCreatorUi()
            else
                print('^1Something went wrong with fetching this track')
                DebugLog(json.encode(result, { indent = true }))
            end
        else
            CreatorData.IsEdit = false
            openCreatorUi()
        end
    else
        NotifyHandler(Lang("already_making_race"), 'error')
    end
end)

-- Exampl
local function checkElimination()
    local currentPlayerIsLast = true
    local lastCompletedLap = 0
    -- Find the last completed lap and racer
    for citizenId, data in pairs(CurrentRaceData.Racers) do
        if getCitizenId() ~= citizenId then
            if not data.Finished and data.Lap <= CurrentRaceData.Lap then
                currentPlayerIsLast = false -- someone was worse
            end
            if lastCompletedLap < data.Lap then
                lastCompletedLap = data.Lap
            end
        end
    end
    DebugLog('Is Last racer', currentPlayerIsLast, 'lap:', lastCompletedLap)
    -- Check if the current racer is the last one who completed the lap
    if currentPlayerIsLast and lastCompletedLap >= CurrentRaceData.Lap then
        DebugLog("Eliminating racer: " .. getCitizenId())
        TriggerServerEvent("cw-racingapp:server:leaveRace", CurrentRaceData, 'elimination')
        NotifyHandler(Lang("eliminated"), 'error')
    end
end

RegisterNetEvent('cw-racingapp:client:updateRaceRacerData', function(raceId, citizenid, racerData)
    if (CurrentRaceData.RaceId ~= nil) and CurrentRaceData.RaceId == raceId then
        DebugLog('Race is Elimination:', CurrentRaceData.IsElimination)
        CurrentRaceData.Racers[citizenid] = racerData
        if CurrentRaceData.IsElimination then
            checkElimination()
        end
    end
end)

RegisterNetEvent('cw-racingapp:client:joinRace', function(data, checkpoints, laps)
    DebugLog('Joining', json.encode(data, {indent=true}))
    if not RaceData.InRace then
        data.RacerName = CurrentUserData.racername
        data.RacerId  = CurrentUserData.racerid
        RaceData.InRace = true
        handleActiveRace(data, checkpoints, laps)
        NotifyHandler(Lang("race_joined"))
        TriggerServerEvent('cw-racingapp:server:updateRaceState', CurrentRaceData.RaceId, false, true)
    else
        NotifyHandler(Lang("already_in_race"), 'error')
    end
end)

RegisterNetEvent('cw-racingapp:client:updateActiveRacers', function(raceId, racers)
    if CurrentRaceData.RaceId == raceId then
        CurrentRaceData.Racers = racers
    end
end)


RegisterNetEvent('cw-racingapp:client:updateOrganizer', function(RaceId, organizer)
    if CurrentRaceData.RaceId == RaceId then
        DebugLog('updating organizer')
        CurrentRaceData.SetupCitizenId = organizer
    end
end)

RegisterNetEvent('cw-racingapp:client:leaveRace', function()
    if IgnoreRoadsForGps then
        ClearGpsCustomRoute()
    else
        ClearGpsMultiRoute()
    end
    Countdown = 10
    HideTrack()
    updateCountdown(-1)
    unGhostPlayer()
    deleteCurrentRaceCheckpoints()
    FreezeEntityPosition(GetVehiclePedIsIn(PlayerPedId(), false), false)
    RaceData.InRace = false
    LocalPlayer.state:set('inRace', false, true)
    LocalPlayer.state:set('raceId', nil, true)
    CurrentRaceData.RaceId = nil
    SendNUIMessage({
        type = "race",
        action = "update",
        data = {},
        racedata = RaceData,
        active = false
    })
end)

RegisterNetEvent("cw-racingapp:client:DeletetrackConfirmed", function(data)
    NotifyHandler(data.RaceName .. " " .. Lang("has_been_removed"))
    TriggerServerEvent("cw-racingapp:server:deleteTrack", data.RaceId)
end)

RegisterNetEvent("cw-racingapp:client:clearLeaderboardConfirmed", function(data)
    NotifyHandler(data.RaceName .. " " .. Lang("leaderboard_has_been_cleared"))
    TriggerServerEvent("cw-racingapp:server:clearLeaderboard", data.RaceId)
end)

RegisterNetEvent("cw-racingapp:client:editTrack", function(data)
    TriggerEvent("cw-racingapp:client:startRaceEditor", data.RaceName, data.name, data.TrackId)
end)

local function isPositionCheating()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local current = CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint]
    local next = CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1]

    local distanceToNext = #(pos - vector3(next.coords.x, next.coords.y, next.coords.z))

    local distanceBetween = #(vector3(next.coords.x, next.coords.y, next.coords.z) - vector3(current.coords.x, current.coords.y, current.coords.z))

    return distanceBetween > distanceToNext + (Config.PositionCheatBuffer or 0)
end

local function forceFirstPerson()
    DebugLog('Race has forced first person:', CurrentRaceData.FirstPerson)
    local originalCam = GetFollowVehicleCamViewMode()
    CreateThread(function()
        while CurrentRaceData and CurrentRaceData.RaceId and CurrentRaceData.FirstPerson do
            local inVeh = GetVehiclePedIsIn(PlayerPedId(), false)
            local sleep = 1000
            if inVeh then
                sleep = 1
                SetFollowVehicleCamViewMode(4)
            end
            Wait(sleep)
        end
        SetFollowVehicleCamViewMode(originalCam or 2)
    end)
end

RegisterNetEvent('cw-racingapp:client:raceCountdown', function(TotalRacers)
    HideTrack()
    setupBlipsForRace(true)
    updateGpsForRace(true)
    Kicked = false
    TriggerServerEvent('cw-racingapp:server:updateRaceState', CurrentRaceData.RaceId, true, false)
    CurrentRaceData.TotalRacers = TotalRacers
    positionThread()
    if CurrentRaceData.TotalLaps == -1 then
        DebugLog('^3Race is Elimination! setting laps to:', CurrentRaceData.TotalRacers - 1)
        CurrentRaceData.TotalLaps = CurrentRaceData.TotalRacers - 1
        CurrentRaceData.IsElimination = true
    end
    if CurrentRaceData.RandomVehicleSwapping then
        swapToRandomRaceVehicle()
    end
    if CurrentRaceData.RaceId ~= nil then
        while Countdown ~= 0 do
            if CurrentRaceData.RaceName ~= nil then
                if Countdown == 10 then
                    updateCountdown(10)
                    PlayAudio(Config.Sounds.Countdown.start.lib, Config.Sounds.Countdown.start.sound)
                elseif Countdown <= 5 then
                    FreezeEntityPosition(GetVehiclePedIsIn(PlayerPedId(), true), true)
                    if Countdown == 5 then forceFirstPerson() end
                    updateCountdown(Countdown)
                    PlayAudio(Config.Sounds.Countdown.number.lib, Config.Sounds.Countdown.number.sound)
                end
                Countdown = Countdown - 1
            else
                break
            end
            Wait(1000)
        end
        if CurrentRaceData.RaceName ~= nil then
            if CurrentRaceData.Drift then
                StartDriftSystem()
            end

            updateCountdown(0)
            PlayAudio(Config.Sounds.Countdown.go.lib, Config.Sounds.Countdown.go.sound)
            if isPositionCheating() then
                TriggerServerEvent("cw-racingapp:server:leaveRace", CurrentRaceData, 'positionCheat')
                NotifyHandler(Lang("kicked_line"), 'error')
                FreezeEntityPosition(GetVehiclePedIsIn(PlayerPedId(), true), false)
                return
            end
            if IgnoreRoadsForGps then
                AddPointToGpsCustomRoute(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.x,
                    CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.y)
            else
                AddPointToGpsMultiRoute(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.x,
                    CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].coords.y)
            end
            markWithUglyWaypoint()
            SetBlipScale(CurrentRaceData.Checkpoints[CurrentRaceData.CurrentCheckpoint + 1].blip,
                Config.Blips.Generic.Size)
            FreezeEntityPosition(GetVehiclePedIsIn(PlayerPedId(), true), false)
            doPilePfx()
            CurrentRaceData.Started = true
            if Config.Ghosting.Enabled and CurrentRaceData.Ghosting then
                initGhosting()
            end
            lapStartTime = GetGameTimer()
            startTime = GetGameTimer()
            timeWhenLastCheckpointWasPassed = GetGameTimer()
            Countdown = 10
        else
            FreezeEntityPosition(GetVehiclePedIsIn(PlayerPedId(), true), false)
            Countdown = 10
        end
    else
        NotifyHandler(Lang("already_in_race"), 'error')
    end
end)

RegisterNetEvent('cw-racingapp:client:playerFinish', function(RaceId, Place, RacerName)
    if CurrentRaceData.RaceId ~= nil then
        if CurrentRaceData.RaceId == RaceId then
            NotifyHandler(RacerName .. " " .. Lang("racer_finished_place") .. Place, 'primary')
        end
    end
end)

local function notCloseEnough(x, y)
    NotifyHandler(Lang('not_close_enough_to_join'), 'error')
    SetNewWaypoint(x, y)
end

RegisterNetEvent('cw-racingapp:client:notCloseEnough', function(x, y)
    notCloseEnough(x, y)
end)

local function racerNameIsValid(name)
    if #name > Config.MinRacerNameLength then
        if #name < Config.MaxRacerNameLength then
            return true
        else
            NotifyHandler(Lang('name_too_long'), 'error')
        end
    else
        NotifyHandler(Lang('name_too_short'), 'error')
    end
    return false
end

local function hasPermission(userType)
    if CurrentUserData.auth == 'god' then
        return true
    elseif userType == 'racer' and Config.AllowRacerCreationForAnyone then
        return true
    elseif CurrentUserData.auth == 'master' and (userType == 'creator' or userType == 'racer') then
        return true
    end
    return false
end

function HasAuth(tradeType, userType)
    DebugLog('current auth', CurrentUserData.auth)
    if CurrentUserData.auth and Config.Permissions[CurrentUserData.auth] and Config.Permissions[CurrentUserData.auth].controlAll then
        DebugLog('User has controlall auth')
        return true
    end

    if tradeType.jobRequirement[userType] == true then
        DebugLog('job requirement exists for', userType)
        local jobName = getPlayerJobName()
        local playerHasJob = jobName and Config.AllowedJobs[jobName]
        local jobGradeReq
        if UseDebug then
            print('Player job: ', jobName)
        end
        if playerHasJob then
            local jobLevel = getPlayerJobLevel()
            DebugLog('Player job level: ', jobLevel)
            if Config.AllowedJobs[jobName] ~= nil then
                jobGradeReq = Config.AllowedJobs[jobName][userType]
                if UseDebug then
                    print('Required job grade: ', jobGradeReq)
                end
                if jobGradeReq ~= nil then
                    if jobLevel >= jobGradeReq then
                        return hasPermission(userType)
                    end
                end
            end
        end
        return false
    elseif tradeType.jobRequirement[userType] == nil then
        DebugLog('Requiement is nil for', userType)
        return false
    else
        DebugLog('Requiement is false for', userType)
        return hasPermission(userType)
    end
end

local function racerNameExists(listOfNames, racerName)
    for _, data in pairs(listOfNames) do
        if data.racername == racerName then
            return true
        end
    end
    return false
end

local function createOxInput(fobType, purchaseType)
    if not lib then
        print(
            '^1OxInput is enabled but no lib was found. Might be missing from fxmanifest or the dev is not able to read the config')
    else
        local options = { { type = 'input', label = 'Racer Name', required = true } }

        if not purchaseType.useSlimmed then
            options[#options + 1] = { type = 'input', label = 'Paypal/temp id (leave empty if for you)', required = false }
        end
        local FobInput = lib.inputDialog('Creating a [' .. fobType .. '] type user', options)
        return FobInput
    end
end

local function createQbInput(fobType, purchaseType)
    local inputs = {
        {
            text = 'Racer Name', -- text you want to be displayed as a place holder
            name = "racerName",  -- name of the input should be unique otherwise it might override
            type = "text",       -- type of the input - number will not allow non-number characters in the field so only accepts 0-9
        },
    }

    if not purchaseType.useSlimmed then
        inputs[#inputs + 1] = {
            text = 'Paypal/temp id (leave empty if for you)', -- text you want to be displayed as a place holder
            name = "racerId",                                 -- name of the input should be unique otherwise it might override
            type = "text",                                    -- type of the input - number will not allow non-number characters in the field so only accepts 0-9
        }
    end
    local dialog = exports['qb-input']:ShowInput({
        header = 'Creating a [' .. fobType .. '] type user',
        submitText = 'Submit',
        inputs = inputs
    })
    return dialog
end

function AttemptCreateUser(racerName, racerId, fobType, purchaseType)
    print('[DEBUG] AttemptCreateUser called')
    if UseDebug then
        print('Racername', racerName)
        print('RacerId', racerId)
        print('fobType', json.encode(fobType, { indent = true }))
        print('purchaseType', json.encode(purchaseType, { indent = true }))
    end
    if racerId == nil or racerId == '' then
        racerId = GetPlayerServerId(PlayerId())
        print('[DEBUG] Set racerId to:', racerId)
    end
    print('[DEBUG] Checking if racerName is valid:', racerName)
    if racerNameIsValid(racerName) then
        print('[DEBUG] racerName is valid, fetching player names...')
        local playerNames = cwCallback.await('cw-racingapp:server:getRacerNamesByPlayer', racerId)
        print('[DEBUG] playerNames result:', json.encode(playerNames))

        DebugLog('player names', #playerNames, json.encode(playerNames))
        local maxRacerNames = Config.MaxRacerNames
        if Config.UseNameValidation and #playerNames > 1 and playerNames[1].citizenid and Config.CustomAmounts[playerNames[1].citizenid] then
            maxRacerNames = Config.CustomAmounts[playerNames[1].citizenid]
        end

        DebugLog('Racer names allowed for id ' .. racerId, maxRacerNames)
        if playerNames == nil or racerNameExists(playerNames, StrictSanitize(racerName)) or #playerNames < maxRacerNames then
            local nameIsNotTaken = cwCallback.await('cw-racingapp:server:nameIsAvailable', racerName, racerId)

            if nameIsNotTaken then
                TriggerServerEvent('cw-racingapp:server:createRacerName', racerId, racerName, fobType, purchaseType,
                    CurrentUserData.racername)
                return true
            else
                NotifyHandler(Lang("name_is_used") .. racerName, 'error')
                return false
            end
        else
            NotifyHandler(Lang("to_many_names"), 'error')
            return false
        end
    end
end

RegisterNetEvent("cw-racingapp:client:openFobInput", function(data)
    local purchaseType = data.purchaseType
    local fobType = data.fobType

    print('[DEBUG] openFobInput triggered, fobType:', fobType)

    NotifyHandler(Lang("max_uniques") .. " " .. Config.MaxRacerNames)

    local dialog
    local racerName
    local racerId
    if Config.OxInput then
        dialog = createOxInput(fobType, purchaseType)
        print('[DEBUG] OxInput dialog result:', json.encode(dialog))
        if dialog then
            racerName = dialog[1]
            racerId = dialog[2]
            print('[DEBUG] racerName:', racerName, 'racerId:', racerId)
        end
    else
        dialog = createQbInput(fobType, purchaseType)
        if dialog then
            racerName = dialog['racerName']
            racerId = dialog['racerId']
        end
    end

    if dialog ~= nil then
        print('[DEBUG] Calling AttemptCreateUser')
        AttemptCreateUser(racerName, racerId, fobType, purchaseType)
    else
        print('[DEBUG] Dialog was nil, not calling AttemptCreateUser')
        TriggerEvent('animations:client:EmoteCommandStart', { "c" })
    end
end)

-- Replacement Racing GPS — for racers who lost theirs. Confirms the price, then
-- lets the server validate (already has one / has an account / can afford) and
-- hand over the item. The cost is read server-side from Config so it can't be
-- spoofed; `purchaseSource` just says which buy point ('trader'/'laptop') was used.
RegisterNetEvent('cw-racingapp:client:buyReplacementGps', function(data)
    local purchaseSource = (data and data.purchaseSource) or 'trader'
    local cfg = (purchaseSource == 'laptop') and Config.Laptop or Config.Trader
    local currency
    if cfg.moneyType == 'cash' or cfg.moneyType == 'bank' then
        currency = '$'
    else
        currency = Config.Payments.cryptoType
    end
    local cost = cfg.gpsCost or 0

    if hasGps() then
        NotifyHandler('You already have a Racing GPS.', 'error')
        return
    end

    if lib then
        local accepted = lib.alertDialog({
            header = 'Replacement Racing GPS',
            content = ('Buy a new Racing GPS for **%s%s**?'):format(currency, cost),
            centered = true,
            cancel = true,
        })
        if accepted ~= 'confirm' then return end
    end

    TriggerServerEvent('cw-racingapp:server:buyReplacementGps', purchaseSource)
end)

if Config.Trader.active then
    local trader = Config.Trader
    CreateThread(function()
        local animation
        if trader.animation then
            animation = trader.animation
        else
            animation = "WORLD_HUMAN_STAND_IMPATIENT"
        end

        local currency
        if trader.moneyType == 'cash' or trader.moneyType == 'bank' then
            currency = '$'
        else
            currency = Config.Payments.cryptoType
        end

        local options = {}

        for authName, _ in pairs(Config.Permissions) do
            local option = {
                type = "client",
                event = "cw-racingapp:client:openFobInput",
                icon = "fas fa-flag-checkered",
                label = 'Create a new ' .. authName .. ' user (' .. currency .. trader.racingUserCosts[authName] .. ')',
                purchaseType = trader,
                fobType = authName,
                canInteract = function()
                    return HasAuth(trader, authName)
                end
            }
            options[#options + 1] = option
        end

        -- Replacement GPS — only shows when the player isn't already holding one.
        options[#options + 1] = {
            type = "client",
            event = "cw-racingapp:client:buyReplacementGps",
            icon = "fas fa-location-dot",
            label = 'Buy a replacement Racing GPS (' .. currency .. (trader.gpsCost or 0) .. ')',
            purchaseSource = 'trader',
            canInteract = function()
                return not hasGps()
            end
        }

        RequestModel(trader.model)
        while not HasModelLoaded(trader.model) do
            Wait(0)
        end

        TraderPed = CreatePed(4, trader.model, trader.location, false, false)
        SetEntityAsMissionEntity(TraderPed, true, true)
        SetPedHearingRange(TraderPed, 0.0)
        SetPedSeeingRange(TraderPed, 0.0)
        SetPedAlertness(TraderPed, 0.0)
        SetPedFleeAttributes(TraderPed, 0, 0)
        SetBlockingOfNonTemporaryEvents(TraderPed, true)
        SetPedCombatAttributes(TraderPed, 46, true)
        TaskStartScenarioInPlace(TraderPed, animation, 0, true)
        SetEntityInvincible(TraderPed, true)
        SetEntityCanBeDamaged(TraderPed, false)
        SetEntityProofs(TraderPed, true, true, true, true, true, true, 1, true)
        FreezeEntityPosition(TraderPed, true)

        if Config.UseOxTarget then
            exports.ox_target:addLocalEntity(TraderPed, options)
        else
            exports['qb-target']:AddTargetEntity(TraderPed, {
                options = options,
                distance = 2.0
            })
        end

        Entities[#Entities + 1] = TraderPed
    end)
end

local laptopEntity
if Config.Laptop.active then
    CreateThread(function()
        local laptop = Config.Laptop
        local currency
        if laptop.moneyType == 'cash' or laptop.moneyType == 'bank' then
            currency = '$'
        else
            currency = Config.Payments.cryptoType
        end

        local options = {}
        for authName, _ in pairs(Config.Permissions) do
            local option = {
                type = "client",
                event = "cw-racingapp:client:openFobInput",
                icon = "fas fa-flag-checkered",
                label = 'Create a new ' .. authName .. ' user (' .. currency .. laptop.racingUserCosts[authName] .. ')',
                purchaseType = laptop,
                fobType = authName,
                canInteract = function()
                    return HasAuth(laptop, authName)
                end
            }
            options[#options + 1] = option
        end

        -- Replacement GPS — only shows when the player isn't already holding one.
        options[#options + 1] = {
            type = "client",
            event = "cw-racingapp:client:buyReplacementGps",
            icon = "fas fa-location-dot",
            label = 'Buy a replacement Racing GPS (' .. currency .. (laptop.gpsCost or 0) .. ')',
            purchaseSource = 'laptop',
            canInteract = function()
                return not hasGps()
            end
        }

        laptopEntity = CreateObject(laptop.model, laptop.location.x, laptop.location.y, laptop.location.z, false, false,
            true)
        SetEntityHeading(laptopEntity, laptop.location.w)
        FreezeEntityPosition(laptopEntity, true)
        Entities[#Entities + 1] = laptopEntity

        if Config.UseOxTarget then
            exports.ox_target:addLocalEntity(laptopEntity, options)
        else
            exports['qb-target']:AddTargetEntity(laptopEntity, {
                options = options,
                distance = 3.0
            })
        end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entity in pairs(Entities) do
        DebugLog('Racing app cleanup: ^2', entity)
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
end)
--- CREATOR BUTTONS
if Config.UseOxLibForKeybind then
    if not lib then
        print('^1UseOxLibForKeybind is enabled but no lib was found. Might be missing from fxmanifest')
    else
        lib.addKeybind({
            name = 'clickAddCheckpoint',
            description = '[Track Creator] Add checkpoint',
            defaultKey = Config.Buttons.AddCheckpoint,
            onPressed = function(self)
                if RaceData.InCreator then
                    clickAddCheckpoint()
                end
            end
        })
        lib.addKeybind({
            name = 'clickDeleteCheckpoint',
            description = '[Track Creator] Remove checkpoint',
            defaultKey = Config.Buttons.DeleteCheckpoint,
            onPressed = function(self)
                if RaceData.InCreator then
                    clickDeleteCheckpoint()
                end
            end
        })
        lib.addKeybind({
            name = 'clickMoveCheckpoint',
            description = '[Track Creator] Move checkpoint',
            defaultKey = Config.Buttons.MoveCheckpoint,
            onPressed = function(self)
                if RaceData.InCreator then
                    clickMoveCheckpoint()
                end
            end
        })
        lib.addKeybind({
            name = 'clickSaveRace',
            description = '[Track Creator] Save track',
            defaultKey = Config.Buttons.SaveRace,
            onPressed = function(self)
                if RaceData.InCreator then
                    clickSaveRace()
                end
            end
        })
        lib.addKeybind({
            name = 'clickIncreaseDistance',
            description = '[Track Creator] Increase Checkpoint Size',
            defaultKey = Config.Buttons.IncreaseDistance,
            onPressed = function(self)
                if RaceData.InCreator then
                    clickIncreaseDistance()
                end
            end
        })
        lib.addKeybind({
            name = 'clickDecreaseDistance',
            description = '[Track Creator] Decrease Checkpoint Size',
            defaultKey = Config.Buttons.DecreaseDistance,
            onPressed = function(self)
                if RaceData.InCreator then
                    clickDecreaseDistance()
                end
            end
        })
        lib.addKeybind({
            name = 'clickExit',
            description = '[Track Creator] Exit track creation',
            defaultKey = Config.Buttons.Exit,
            onPressed = function(self)
                if RaceData.InCreator then
                    clickExit()
                end
            end
        })
    end
else
    RegisterCommand("clickAddCheckpoint", function()
        if RaceData.InCreator then
            local Player = PlayerPedId()
            local vehicle = GetVehiclePedIsUsing(Player)
            if vehicle ~= 0 then
                clickAddCheckpoint()
            end
        end
    end, false)

    RegisterKeyMapping("clickAddCheckpoint", "[Track Creator] Add checkpoint", "keyboard", Config.Buttons.AddCheckpoint)

    RegisterCommand("clickDeleteCheckpoint", function()
        if RaceData.InCreator then
            local Player = PlayerPedId()
            local vehicle = GetVehiclePedIsUsing(Player)
            if vehicle ~= 0 then
                clickDeleteCheckpoint()
            end
        end
    end, false)

    RegisterKeyMapping("clickDeleteCheckpoint", "[Track Creator] Remove checkpoint", "keyboard",
        Config.Buttons.DeleteCheckpoint)

    RegisterCommand("clickMoveCheckpoint", function()
        if RaceData.InCreator then
            local Player = PlayerPedId()
            local vehicle = GetVehiclePedIsUsing(Player)
            if vehicle ~= 0 then
                clickMoveCheckpoint()
            end
        end
    end, false)

    RegisterKeyMapping("clickMoveCheckpoint", "[Track Creator] Move checkpoint", "keyboard",
        Config.Buttons.MoveCheckpoint)

    RegisterCommand("clickSaveRace", function()
        if RaceData.InCreator then
            local Player = PlayerPedId()
            local vehicle = GetVehiclePedIsUsing(Player)
            if vehicle ~= 0 then
                clickSaveRace()
            end
        end
    end, false)

    RegisterKeyMapping("clickSaveRace", "[Track Creator] Save track", "keyboard", Config.Buttons.SaveRace)

    RegisterCommand("clickIncreaseDistance", function()
        if RaceData.InCreator then
            local Player = PlayerPedId()
            local vehicle = GetVehiclePedIsUsing(Player)
            if vehicle ~= 0 then
                clickIncreaseDistance()
            end
        end
    end, false)

    RegisterKeyMapping("clickIncreaseDistance", "[Track Creator] Increase Checkpoint Size", "keyboard",
        Config.Buttons.IncreaseDistance)

    RegisterCommand("clickDecreaseDistance", function()
        if RaceData.InCreator then
            local Player = PlayerPedId()
            local vehicle = GetVehiclePedIsUsing(Player)
            if vehicle ~= 0 then
                clickDecreaseDistance()
            end
        end
    end, false)

    RegisterKeyMapping("clickDecreaseDistance", "[Track Creator] Decrease Checkpoint Size", "keyboard",
        Config.Buttons.DecreaseDistance)

    RegisterCommand("clickExit", function()
        if RaceData.InCreator then
            local Player = PlayerPedId()
            local vehicle = GetVehiclePedIsUsing(Player)
            if vehicle ~= 0 then
                clickExit()
            end
        end
    end, false)

    RegisterKeyMapping("clickExit", "[Track Creator] Exit track creation", "keyboard", Config.Buttons.Exit)
end

-- Custom UI

function GetBaseDataObject()
    local classes = { { value = '', text = Lang("no_class_limit"), number = 9000 } }
    for i, _ in pairs(Classes) do
        if UseDebug then
            print(i, Classes[i])
        end
        classes[#classes + 1] = { value = i, text = i, number = Classes[i] }
    end

    table.sort(classes, function(a, b)
        return a.number > b.number
    end)

    local currentVehicle = nil
    local Player = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(Player, false)
    if vehicle and vehicle ~= 0 then
        currentVehicle = {
            model = getVehicleModel(vehicle),
            class = getVehicleClass(vehicle)
        }
    end

    local setup = {
        classes = classes,
        currentVehicle = currentVehicle;
        randomVehicleCategoryOptions = getRandomRaceVehicleCategoryOptions(),
        laps = Config.Options.Laps,
        buyIns = Config.Options.BuyIns,
        participationCurrencyOptions = Config.Options.participationCurrencyOptions,
        moneyType = Config.Payments.racing,
        cryptoType = Config.Payments.cryptoType,
        ghostingEnabled = Config.Ghosting.Enabled,
        ghostingTimes = Config.Ghosting.Options,
        allowShare = Config.AllowCreateFromShare,
        racerNames = MyRacerNames,
        currentRacerName = CurrentUserData.racername,
        currentRacerAuth = CurrentUserData.auth,
        currentCrewName = CurrentUserData.crew,
        currentRanking = CurrentUserData.ranking,
        currentCrypto = CurrentUserData.crypto or 0,
        isUsingRacingCrypto = Config.Payments.useRacingCrypto,
        cryptoConversionRate = Config.Options.conversionRate,
        allowBuyingCrypto = Config.Options.allowBuyingCrypto,
        allowSellingCrypto = Config.Options.allowSellingCrypto,
        allowTransferCrypto = Config.Options.allowTransferCrypto,
        showH2H = Config.ShowH2H,
        sellCharge = Config.Options.sellCharge,
        auth = Config.Permissions[CurrentUserData.auth],
        hudSettings = Config.HUDSettings,
        translations = Config.Locale,
        primaryColor = Config.PrimaryUiColor,
        anyoneCanCreate = Config.AllowAnyoneToCreateUserInApp,
        isFirstUser = IsFirstUser,
        payments = Config.Payments,
        hideMap = Config.HideMapInTablet,
        allAuthorities = Config.Permissions,
        dashboardSettings = Config.Dashboard,
        driftingIsEnabled = ConfigDrift.useDrift,
        driftChallengeIsEnabled = ConfigDrift.useDriftChallenges,
        driftChallengeSettings = ConfigDrift.driftChallengeSettings,
    }
    return setup
end

RegisterNetEvent("cw-racingapp:client:notifyRacers", function(text)
    if hasGps() then
        NotifyHandler(text)
    end
end)

RegisterNetEvent("cw-racingapp:client:updateRanking", function(change, newRank)
    local type = 'success'
    if change < 0 then type = 'error' end
    NotifyHandler(Lang("rank_update") .. " " .. change .. ". " .. Lang("new_rank") .. newRank, type)
end)

function GetActiveRacerName()
    local amountOfNames = 0
    for _, user in pairs(MyRacerNames) do
        amountOfNames = amountOfNames + 1
        if user.active == 1 then return user end
    end

    if amountOfNames > 0 then
        DebugLog('No active racer, returning first one')
        cwCallback.await('cw-racingapp:server:setActiveRacerUser', MyRacerNames[1].racerid)
        return MyRacerNames[1]
    end
end

RegisterNetEvent('cw-racingapp:client:setCurrentRacingCrew', function(crew)
    CurrentUserData.crew = crew
    if crew == nil then 
        NotifyHandler(Lang('left_crew'))
    end
end)

RegisterNetEvent("cw-racingapp:client:updateRacerNames", function()
    Wait(2000)
    local playerNames = cwCallback.await('cw-racingapp:server:getRacerNamesByPlayer')
    MyRacerNames = playerNames
    
    local currentRacer = GetActiveRacerName()
    DebugLog('Current racer after change', json.encode(currentRacer, { indent = true }))
    DebugLog('All player names', json.encode(MyRacerNames, { indent = true }))

    if #MyRacerNames == 1 then
        currentRacer = MyRacerNames[1]
    end
    CurrentUserData = currentRacer or {}

    NotifyHandler(Lang("user_list_updated"))
    DebugLog('current user', json.encode(currentRacer, { indent = true }))
    if CurrentUserData.racername and currentRacer and currentRacer.revoked == 1 then
        NotifyHandler(Lang("revoked_access"), 'error')
        Wait(2000)
        if UiIsOpen then
            SendNUIMessage({ type = 'toggleApp', open = false })
            CloseUi()
        end
    elseif CurrentUserData.racername and not currentRacer then
        DebugLog('Race user was deleted')
        NotifyHandler(Lang('removed_user'), 'error')
        Wait(2000)
        if UiIsOpen then
            SendNUIMessage({ type = 'toggleApp', open = false })
            CloseUi()
        end
    else
        SendNUIMessage({ type = 'updateBaseData' })
    end
end)

RegisterNetEvent('cw-racingapp:client:leaveCurrentRace', function()
    LeaveCurrentRace()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if UseDebug then
        print('^3--- Debug is on for Racingapp --- ')

        print('^2Inventory is set to ', Config.Inventory)
        print('^2Using Oxlib for keybinds ', Config.UseOxLibForKeybind)
        print('^2Using Racing App Crypto ', Config.Payments.useRacingCrypto)

        print('^2Permissions:', json.encode(Config.Permissions))
        print('^2Classes: ', json.encode(Classes))
    end
    InitialRacingAppSetup()
end)
