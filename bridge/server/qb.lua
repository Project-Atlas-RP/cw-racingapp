if GetResourceState('qb-core') ~= 'started' or GetResourceState('qbx_core') == 'started' then return end

QBCore = exports['qb-core']:GetCoreObject()
QBCore.Functions.CreateUseableItem(Config.ItemName.gps, function(source, item)
    openRacingApp(source)
end)


-- Adds money to user
function addMoney(src, moneyType, amount)
    local Player = QBCore.Functions.GetPlayer(src)
    Player.Functions.AddMoney(moneyType, math.floor(amount), 'cw-racingapp:winnings')
end

-- Removes money from user
function removeMoney(src, moneyType, amount, reason)
    local Player = QBCore.Functions.GetPlayer(src)
    return Player.Functions.RemoveMoney(moneyType, math.floor(amount), reason or 'cw-racingapp')
end

-- Checks that user can pay
function canPay(src, moneyType, cost)
    local Player = QBCore.Functions.GetPlayer(src)
    return Player.PlayerData.money[moneyType] >= cost
end

-- Gives an item to a player
function giveItem(src, itemName, amount, metadata)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    return Player.Functions.AddItem(itemName, amount, nil, metadata)
end

-- Fetches the CitizenId by Source
function getCitizenId(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        print('^1[ERROR][cw-racingapp] getCitizenId: QBCore.Functions.GetPlayer returned nil for src: ' .. tostring(src) .. '^0')
        return nil
    end
    return Player.PlayerData.citizenid
end

-- Fetches the Source of an online player by citizenid
function getSrcOfPlayerByCitizenId(citizenId)
    if not citizenId then
        print('^1[ERROR][cw-racingapp] getSrcOfPlayerByCitizenId: citizenId is nil^0')
        return nil
    end
    local player = QBCore.Functions.GetPlayerByCitizenId(citizenId)
    if not player then
        print('^3[WARN][cw-racingapp] getSrcOfPlayerByCitizenId: no online player found for citizenId: ' .. tostring(citizenId) .. '^0')
        return nil
    end
    return player.PlayerData.source
end
