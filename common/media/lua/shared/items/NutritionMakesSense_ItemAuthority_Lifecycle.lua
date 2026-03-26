NutritionMakesSense = NutritionMakesSense or {}

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
NutritionMakesSense.ItemAuthority = ItemAuthority

local log = ItemAuthority.log or function(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local function isMpClientRuntime()
    return type(isClient) == "function" and isClient() == true
        and not (type(isServer) == "function" and isServer() == true)
end

function ItemAuthority.install()
    if ItemAuthority._installed then
        return ItemAuthority
    end
    ItemAuthority._installed = true

    if Events then
        if Events.OnLoad and type(Events.OnLoad.Add) == "function" then
            Events.OnLoad.Add(function()
                if isMpClientRuntime() then
                    return
                end
                ItemAuthority.syncPersistenceSurfaces("on-load", "restore")
            end)
        end

        if Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
            Events.OnGameStart.Add(function()
                if isMpClientRuntime() then
                    return
                end
                ItemAuthority.syncPlayerInventories("game-start", "restore")
            end)
        end

        if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
            Events.OnCreatePlayer.Add(function()
                if isMpClientRuntime() then
                    return
                end
                ItemAuthority.syncPlayerInventories("create-player", "restore")
            end)
        end

        if Events.OnContainerUpdate and type(Events.OnContainerUpdate.Add) == "function" then
            Events.OnContainerUpdate.Add(function(item)
                if isMpClientRuntime() then
                    return
                end
                if item then
                    ItemAuthority.restoreItem(item, "container-update-item")
                elseif type(ItemAuthority.syncPlayerInventories) == "function" then
                    ItemAuthority.syncPlayerInventories("container-update-refresh", "restore")
                end
            end)
        end
    end

    return ItemAuthority
end

return ItemAuthority
