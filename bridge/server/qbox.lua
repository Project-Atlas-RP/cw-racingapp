if GetResourceState('qbx_core') ~= 'started' then return end

AddEventHandler('ox_inventory:usedItem', function(playerId, name, slotId, metadata)
    if UseDebug then print('opening ui') end

    if name == Config.ItemName.gps then
        openRacingApp(playerId)
    end
end)

-- Adds money to user
function addMoney(src, moneyType, amount)
    local player = exports.qbx_core:GetPlayer(tonumber(src))
    player.Functions.AddMoney(moneyType, math.floor(amount), 'cw-racingapp:winnings')
end

-- Removes money from user
function removeMoney(src, moneyType, amount, reason)
    local player = exports.qbx_core:GetPlayer(tonumber(src))
    if not player then
        print('[DEBUG] removeMoney: player is nil for src:', src)
        return false
    end
    local result = player.Functions.RemoveMoney(moneyType, math.floor(amount), reason or 'cw-racingapp')
    print('[DEBUG] removeMoney result:', result, 'src:', src, 'type:', moneyType, 'amount:', amount)
    return result
end

-- Checks that user can pay
function canPay(src, moneyType, cost)
    local player = exports.qbx_core:GetPlayer(tonumber(src))
    return player.PlayerData.money[moneyType] >= cost
end

-- Gives an item to a player
function giveItem(src, itemName, amount, metadata)
    local player = exports.qbx_core:GetPlayer(tonumber(src))
    if not player then return false end
    return player.Functions.AddItem(itemName, amount, nil, metadata)
end

-- Fetches the CitizenId by Source
function getCitizenId(src)
    local player = exports.qbx_core:GetPlayer(tonumber(src))
    if not player then
        print('^1[ERROR][cw-racingapp] getCitizenId: qbx_core:GetPlayer returned nil for src: ' .. tostring(src) .. '^0')
        return nil
    end
    return player.PlayerData.citizenid
end

-- Fetches the Source of an online player by citizenid
function getSrcOfPlayerByCitizenId(citizenId)
    if not citizenId then
        print('^1[ERROR][cw-racingapp] getSrcOfPlayerByCitizenId: citizenId is nil^0')
        return nil
    end
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenId)
    if not player then
        print('^3[WARN][cw-racingapp] getSrcOfPlayerByCitizenId: no online player found for citizenId: ' .. tostring(citizenId) .. '^0')
        return nil
    end
    return player.PlayerData.source
end
