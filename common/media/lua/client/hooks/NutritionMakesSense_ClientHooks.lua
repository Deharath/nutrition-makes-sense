NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}

local ClientHooks = NutritionMakesSense.ClientHooks or {}
NutritionMakesSense.ClientHooks = ClientHooks

local function onPlayerUpdate(playerObj)
    if not playerObj then
        return
    end
    if type(getPlayer) == "function" and playerObj ~= getPlayer() then
        return
    end

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
