NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}

local ClientHooks = NutritionMakesSense.ClientHooks or {}
NutritionMakesSense.ClientHooks = ClientHooks

local UPDATE_INTERVAL_SECONDS = 0.25
local lastUpdateSecond = 0

local function getWallClockSeconds()
    if type(getTimestampMs) == "function" then
        return (tonumber(getTimestampMs()) or 0) / 1000
    end
    if type(getTimestamp) == "function" then
        return tonumber(getTimestamp()) or 0
    end
    return 0
end

local function onPlayerUpdate(playerObj)
    if not playerObj then
        return
    end
    if type(getPlayer) == "function" and playerObj ~= getPlayer() then
        return
    end

    local nowSecond = getWallClockSeconds()
    if (nowSecond - lastUpdateSecond) < UPDATE_INTERVAL_SECONDS then
        return
    end
    lastUpdateSecond = nowSecond

    if Runtime and type(Runtime.syncVisibleIndicators) == "function" then
        Runtime.syncVisibleIndicators(playerObj, "client-player-update")
    end
end

local function install()
    if ClientHooks._installed then
        return ClientHooks
    end
    ClientHooks._installed = true

    if Events then
        if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
            Events.OnPlayerUpdate.Add(onPlayerUpdate)
        end
    end

    return ClientHooks
end

ClientHooks.install = install

return ClientHooks
