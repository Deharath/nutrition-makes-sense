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

    return ItemAuthority
end

return ItemAuthority
