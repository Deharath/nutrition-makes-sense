NutritionMakesSense = NutritionMakesSense or {}

local MPClient = NutritionMakesSense.MPClientRuntime or {}

local Runtime = MPClient.Runtime or {}
local ItemAuthority = MPClient.ItemAuthority or {}
local CONSUME_EPSILON = MPClient.CONSUME_EPSILON or 0.0001
local log = MPClient.log
local safeCall = MPClient.safeCall
local clamp01 = MPClient.clamp01
local isClientRuntime = MPClient.isClientRuntime
local isLocalAuthorityRuntime = MPClient.isLocalAuthorityRuntime
local resolveEatFraction = MPClient.resolveEatFraction
local getVisibleHunger = MPClient.getVisibleHunger
local resolveConsumedContext = MPClient.resolveConsumedContext
local measureConsumedPayload = MPClient.measureConsumedPayload
local getDebugSnapshot = MPClient.getDebugSnapshot
local usesCustomMpConsume = MPClient.usesCustomMpConsume
local collectItems = MPClient.collectItems
local applyLocalConsume = MPClient.applyLocalConsume

function MPClient.wrapDrinkFluidAction()
    if NutritionMakesSense._drinkFluidWrapped then
        return
    end

    pcall(require, "TimedActions/ISDrinkFluidAction")
    if type(ISDrinkFluidAction) ~= "table" or type(ISDrinkFluidAction.updateEat) ~= "function" then
        return
    end

    local originalUpdateEat = ISDrinkFluidAction.updateEat
    ISDrinkFluidAction.updateEat = function(self, delta)
        local item = self and self.item or nil
        local character = self and self.character or nil
        local preVisibleHunger = getVisibleHunger(character)
        local fluidContainer = item and safeCall(item, "getFluidContainer") or nil
        local beforeRatio = fluidContainer and tonumber(safeCall(fluidContainer, "getFilledRatio") or 0) or nil

        originalUpdateEat(self, delta)

        local afterRatio = fluidContainer and tonumber(safeCall(fluidContainer, "getFilledRatio") or 0) or nil
        if beforeRatio == nil or afterRatio == nil then
            return
        end

        local consumedFraction = math.max(0, beforeRatio - afterRatio)
        if consumedFraction <= CONSUME_EPSILON then
            return
        end

        if usesCustomMpConsume(item) then
            local consumedContext = resolveConsumedContext(item, consumedFraction, preVisibleHunger)
            if consumedContext and consumedContext.values then
                MPClient.queueConsume(character, item, consumedFraction, "drink-fluid", consumedContext.values, consumedContext.immediateHunger)
                if consumedContext.immediateHunger and type(Runtime.applyVisibleHungerTarget) == "function" then
                    Runtime.applyVisibleHungerTarget(character, consumedContext.immediateHunger.targetVisibleHunger, "drink-fluid-client")
                end
            end
            return
        end

        if isLocalAuthorityRuntime() then
            local consumedContext = resolveConsumedContext(item, consumedFraction, preVisibleHunger)
            if consumedContext then
                applyLocalConsume(character, item, consumedContext, consumedFraction, "drink-fluid")
            end
        end
    end

    NutritionMakesSense._drinkFluidWrapped = true
    log("wrapped ISDrinkFluidAction.updateEat for MP authority")
end

function MPClient.wrapEatFoodAction()
    if NutritionMakesSense._eatFoodWrapped then
        return
    end

    pcall(require, "TimedActions/ISEatFoodAction")
    if type(ISEatFoodAction) ~= "table" or type(ISEatFoodAction.complete) ~= "function" then
        return
    end

    local originalComplete = ISEatFoodAction.complete

    ISEatFoodAction.complete = function(self)
        local item = self and self.item or nil
        local character = self and self.character or nil
        local preVisibleHunger = getVisibleHunger(character)
        local fraction = item and resolveEatFraction(item, self and self.percentage or 1) or 0
        local debugBefore = nil
        local consumedContext = nil

        if fraction > CONSUME_EPSILON then
            consumedContext = resolveConsumedContext(item, fraction, preVisibleHunger)
        end

        if isLocalAuthorityRuntime() and item then
            local snapshot = getDebugSnapshot(item)
            debugBefore = snapshot and snapshot.display or nil
        elseif isClientRuntime() and fraction > CONSUME_EPSILON then
            if usesCustomMpConsume(item) then
                if consumedContext and consumedContext.values then
                    MPClient.queueConsume(character, item, fraction, "eat-food", consumedContext.values, consumedContext.immediateHunger)
                end
            end
        end

        local result = originalComplete(self)
        if consumedContext and consumedContext.immediateHunger and type(Runtime.applyVisibleHungerTarget) == "function" and isClientRuntime() then
            Runtime.applyVisibleHungerTarget(character, consumedContext.immediateHunger.targetVisibleHunger, "eat-food-client")
        end
        if consumedContext then
            applyLocalConsume(character, item, consumedContext, fraction, "eat-food")
        elseif isLocalAuthorityRuntime() and debugBefore and ItemAuthority and item then
            local snapshot = getDebugSnapshot(item)
            local measuredValues = measureConsumedPayload(item, debugBefore, snapshot and snapshot.current or nil)
            if measuredValues and type(ItemAuthority.resolveConsumedPayload) == "function" then
                local measuredFraction = fraction
                local baseHunger = math.abs(tonumber(debugBefore.baseHunger) or tonumber(debugBefore.hunger) or 0)
                local consumedHunger = math.abs(tonumber(measuredValues.hunger) or 0)
                if baseHunger > CONSUME_EPSILON and consumedHunger > CONSUME_EPSILON then
                    measuredFraction = clamp01(consumedHunger / baseHunger)
                end
                local measuredContext = {
                    values = measuredValues,
                    source = ItemAuthority.getResolvedNutritionSource and ItemAuthority.getResolvedNutritionSource(item) or nil,
                    immediateHunger = consumedContext and consumedContext.immediateHunger or nil,
                }
                applyLocalConsume(character, item, measuredContext, measuredFraction, "eat-food-measured")
            end
        end
        return result
    end

    NutritionMakesSense._eatFoodWrapped = true
    log("wrapped ISEatFoodAction.complete for MP authority")
end

function MPClient.wrapHandcraftAction()
    if NutritionMakesSense._handcraftWrapped then
        return
    end

    pcall(require, "Entity/TimedActions/ISHandcraftAction")
    if type(ISHandcraftAction) ~= "table" or type(ISHandcraftAction.performRecipe) ~= "function" then
        return
    end

    local originalPerformRecipe = ISHandcraftAction.performRecipe
    ISHandcraftAction.performRecipe = function(self)
        local payloadValues = nil
        local consumedCount = 0
        if isLocalAuthorityRuntime() and ItemAuthority and type(ItemAuthority.sumConsumedPayload) == "function" then
            local recipeData = self and self.logic and safeCall(self.logic, "getRecipeData") or nil
            local consumedItems = recipeData and safeCall(recipeData, "getAllConsumedItems") or nil
            local consumedList = collectItems(consumedItems)
            consumedCount = #consumedList
            payloadValues = ItemAuthority.sumConsumedPayload(consumedItems)
        end

        local result = originalPerformRecipe(self)

        if isLocalAuthorityRuntime() and payloadValues and ItemAuthority and type(ItemAuthority.seedDynamicOutputs) == "function" then
            local created = {}
            if self and self.logic and type(self.logic.getCreatedOutputItems) == "function" and ArrayList then
                local createdList = ArrayList.new()
                local ok = pcall(self.logic.getCreatedOutputItems, self.logic, createdList)
                if ok then
                    created = collectItems(createdList)
                end
            end
            log(string.format(
                "[DYNAMIC_HOOK] hook=handcraft consumed=%d created=%d payload_kcal=%.1f",
                tonumber(consumedCount or 0),
                tonumber(#created or 0),
                tonumber(payloadValues.kcal or 0)
            ))
            ItemAuthority.seedDynamicOutputs(created, payloadValues, "handcraft-create")
        end

        return result
    end

    NutritionMakesSense._handcraftWrapped = true
    log("wrapped ISHandcraftAction.performRecipe for dynamic payload seeding")
end

function MPClient.wrapAddItemInRecipeAction()
    if NutritionMakesSense._addItemRecipeWrapped then
        return
    end

    pcall(require, "TimedActions/ISAddItemInRecipe")
    if type(ISAddItemInRecipe) ~= "table" or type(ISAddItemInRecipe.complete) ~= "function" then
        return
    end

    local originalComplete = ISAddItemInRecipe.complete
    ISAddItemInRecipe.complete = function(self)
        local usedItem = self and self.usedItem or nil
        local addedContext = nil
        local usedFullType = safeCall(usedItem, "getFullType") or tostring(usedItem)
        if isLocalAuthorityRuntime() then
            addedContext = resolveConsumedContext(usedItem, 1, nil)
        end

        local result = originalComplete(self)

        local baseItem = self and self.baseItem or nil
        if isLocalAuthorityRuntime() and addedContext and addedContext.values and ItemAuthority and type(ItemAuthority.accumulateDynamicPayload) == "function" then
            log(string.format(
                "[DYNAMIC_HOOK] hook=evolved-add used=%s base=%s payload_kcal=%.1f",
                tostring(usedFullType or "unknown"),
                tostring(safeCall(baseItem, "getFullType") or baseItem or "unknown"),
                tonumber(addedContext.values.kcal or 0)
            ))
            ItemAuthority.accumulateDynamicPayload(baseItem, addedContext.values, "evolved-add-item")
        end

        return result
    end

    NutritionMakesSense._addItemRecipeWrapped = true
    log("wrapped ISAddItemInRecipe.complete for dynamic payload accumulation")
end

local function registerHooks()
    MPClient.wrapDrinkFluidAction()
    MPClient.wrapEatFoodAction()
    MPClient.wrapHandcraftAction()
    MPClient.wrapAddItemInRecipeAction()
end

function MPClient.installHooks()
    registerHooks()
    return MPClient
end
MPClient.registerHooks = registerHooks

return MPClient
