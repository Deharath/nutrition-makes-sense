NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local isDedicatedServerRuntime = Runtime.isDedicatedServerRuntime or function()
    return type(isServer) == "function" and isServer() == true
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
                    Runtime.observePlayerWorkload(playerObj, "player-update")
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
