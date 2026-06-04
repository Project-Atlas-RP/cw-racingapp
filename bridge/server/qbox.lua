if GetResourceState('qbx_core') ~= 'started' then return end

exports.qbx_core:CreateUseableItem(Config.ItemName.gps, function(source, item)
    openRacingApp(source)
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

-- Fetches the CitizenId by Source
function getCitizenId(src)
    local player = exports.qbx_core:GetPlayer(tonumber(src))
    return player.PlayerData.citizenid
end

-- Fetches the Source of an online player by citizenid
function getSrcOfPlayerByCitizenId(citizenId)
    return exports.qbx_core:GetPlayerByCitizenId(citizenId).PlayerData.source
end
