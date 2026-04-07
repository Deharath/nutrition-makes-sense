NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local isDedicatedServerRuntime = Runtime.isDedicatedServerRuntime or function()
    return type(isServer) == "function" and isServer() == true
end
local shouldRunAuthoritativeUpdates = Runtime.shouldRunAuthoritativeUpdates or function()
    return true
end
local getPlayerCacheKey = Runtime.getPlayerCacheKey

local LOCAL_AUTHORITY_UPDATE_INTERVAL_SECONDS = 0.25
local lastLocalAuthorityUpdateByPlayerKey = {}

local function getWallClockSeconds()
    if type(getTimestampMs) == "function" then
        local nowMs = tonumber(getTimestampMs())
        if nowMs ~= nil then
            return nowMs / 1000
        end
    end
    if type(getTimestamp) == "function" then
        local nowSeconds = tonumber(getTimestamp())
        if nowSeconds ~= nil then
            return nowSeconds
        end
    end
    local getWorldHours = Runtime.getWorldHours
    return (tonumber(getWorldHours and getWorldHours() or 0) or 0) * 3600
end

function Runtime.install()
    if Runtime._installed then
        return Runtime
    end
    Runtime._installed = true
    if type(Runtime.installProteinXpHooks) == "function" then
        Runtime.installProteinXpHooks()
    end

    if Events then
        if Events.OnLoad and type(Events.OnLoad.Add) == "function" then
            Events.OnLoad.Add(function()
                Runtime.bootstrapKnownPlayers("on-load")
            end)
        end

        if Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
            Events.OnGameStart.Add(function()
                Runtime.bootstrapKnownPlayers("game-start")
            end)
        end

        if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
            Events.OnCreatePlayer.Add(function(_, playerObj)
                Runtime.bootstrapPlayer(playerObj, "create-player")
            end)
        end

        if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
            Events.OnPlayerUpdate.Add(function(playerObj)
                if not isDedicatedServerRuntime() then
                    local ranFastAuthoritativeUpdate = false
                    if shouldRunAuthoritativeUpdates() and type(Runtime.updatePlayer) == "function" then
                        local playerKey = getPlayerCacheKey and getPlayerCacheKey(playerObj) or nil
                        local nowSecond = getWallClockSeconds()
                        local previousSecond = tonumber(playerKey and lastLocalAuthorityUpdateByPlayerKey[playerKey]) or 0
                        if playerKey ~= nil and (nowSecond - previousSecond) >= LOCAL_AUTHORITY_UPDATE_INTERVAL_SECONDS then
                            lastLocalAuthorityUpdateByPlayerKey[playerKey] = nowSecond
                            Runtime.updatePlayer(playerObj, "player-update-fastpath")
                            ranFastAuthoritativeUpdate = true
                        end
                    end
                    if (not ranFastAuthoritativeUpdate) and type(Runtime.observePlayerWorkload) == "function" then
                        Runtime.observePlayerWorkload(playerObj, "player-update")
                    end
                end
            end)
        end

        if Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
            Events.EveryOneMinute.Add(function()
                if not isDedicatedServerRuntime() then
                    Runtime.refreshKnownPlayers("every-one-minute")
                end
            end)
        end
    end

    return Runtime
end

return Runtime
