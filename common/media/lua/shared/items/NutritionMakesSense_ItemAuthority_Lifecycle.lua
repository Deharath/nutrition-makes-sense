NutritionMakesSense = NutritionMakesSense or {}

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}

function ItemAuthority.install()
    if ItemAuthority._installed then
        return ItemAuthority
    end
    ItemAuthority._installed = true

    if Events then
        if Events.OnLoad and type(Events.OnLoad.Add) == "function" then
            Events.OnLoad.Add(function()
                ItemAuthority.syncPersistenceSurfaces("on-load", "restore")
            end)
        end

        if Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
            Events.OnGameStart.Add(function()
                ItemAuthority.syncPlayerInventories("game-start", "restore")
            end)
        end

        if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
            Events.OnCreatePlayer.Add(function()
                ItemAuthority.syncPlayerInventories("create-player", "restore")
            end)
        end

        if Events.OnContainerUpdate and type(Events.OnContainerUpdate.Add) == "function" then
            Events.OnContainerUpdate.Add(function(item)
                if item then
                    ItemAuthority.restoreItem(item, "container-update-item")
                end
            end)
        end
    end

    return ItemAuthority
end

return ItemAuthority
