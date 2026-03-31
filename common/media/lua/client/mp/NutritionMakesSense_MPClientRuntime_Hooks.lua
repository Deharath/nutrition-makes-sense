NutritionMakesSense = NutritionMakesSense or {}

local MPClient = NutritionMakesSense.MPClientRuntime or {}
NutritionMakesSense.MPClientRuntime = MPClient

local Runtime = MPClient.Runtime or {}
local ItemAuthority = MPClient.ItemAuthority or {}
local CONSUME_EPSILON = MPClient.CONSUME_EPSILON or 0.0001
local log = MPClient.log
local safeCall = MPClient.safeCall
local isLocalAuthorityRuntime = MPClient.isLocalAuthorityRuntime
local resolveEatFraction = MPClient.resolveEatFraction
local getVisibleHunger = MPClient.getVisibleHunger
local resolveConsumedContext = MPClient.resolveConsumedContext
local collectItems = MPClient.collectItems
local applyLocalConsume = MPClient.applyLocalConsume

local function refreshBindings()
    MPClient = NutritionMakesSense.MPClientRuntime or MPClient
    NutritionMakesSense.MPClientRuntime = MPClient
    Runtime = MPClient.Runtime or NutritionMakesSense.MetabolismRuntime or Runtime
    ItemAuthority = MPClient.ItemAuthority or NutritionMakesSense.ItemAuthority or ItemAuthority
    CONSUME_EPSILON = MPClient.CONSUME_EPSILON or CONSUME_EPSILON
    log = MPClient.log or log
    safeCall = MPClient.safeCall or safeCall
    isLocalAuthorityRuntime = MPClient.isLocalAuthorityRuntime or isLocalAuthorityRuntime
    resolveEatFraction = MPClient.resolveEatFraction or resolveEatFraction
    getVisibleHunger = MPClient.getVisibleHunger or getVisibleHunger
    resolveConsumedContext = MPClient.resolveConsumedContext or resolveConsumedContext
    collectItems = MPClient.collectItems or collectItems
    applyLocalConsume = MPClient.applyLocalConsume or applyLocalConsume
end

local function getResolveConsumedContext()
    refreshBindings()
    return MPClient.resolveConsumedContext or resolveConsumedContext
end

local function getApplyLocalConsume()
    refreshBindings()
    return MPClient.applyLocalConsume or applyLocalConsume
end

local function resolveConsumeFullType(item, action)
    refreshBindings()
    local hinted = action and action._nmsConsumeFullType or nil
    if hinted and tostring(hinted) ~= "" then
        return tostring(hinted)
    end
    if type(MPClient.resolveConsumeFullType) == "function" then
        return MPClient.resolveConsumeFullType(item)
    end
    return tostring(safeCall(item, "getFullType") or "")
end

local function raiseConsumeHardFail(reason, itemOrFullType, fraction, detail)
    error(string.format(
        "[NMS_CONSUME_HARD_FAIL] item=%s reason=%s fraction=%.3f detail=%s",
        tostring(itemOrFullType or "unknown"),
        tostring(reason or "unknown"),
        tonumber(fraction or 0),
        tostring(detail or "unknown")
    ))
end

local function applyConsumeOrHardFail(kind, character, item, consumedContext, fraction, fullTypeHint, applyConsume, missingReason)
    if not consumedContext then
        raiseConsumeHardFail(
            kind,
            fullTypeHint or safeCall(item, "getFullType") or item or "unknown",
            fraction,
            missingReason or "context-missing"
        )
    end

    if type(applyConsume) ~= "function" then
        raiseConsumeHardFail(
            kind,
            fullTypeHint or safeCall(item, "getFullType") or item or "unknown",
            fraction,
            "apply-missing"
        )
    end

    if applyConsume(character, item, consumedContext, fraction, kind) == false then
        raiseConsumeHardFail(
            kind,
            fullTypeHint or safeCall(item, "getFullType") or item or "unknown",
            fraction,
            "apply-failed"
        )
    end
end

local function hasMeaningfulMacroValues(values)
    if type(values) ~= "table" then
        return false
    end
    return math.abs(tonumber(values.kcal) or 0) > CONSUME_EPSILON
        or math.abs(tonumber(values.carbs) or 0) > CONSUME_EPSILON
        or math.abs(tonumber(values.fats) or 0) > CONSUME_EPSILON
        or math.abs(tonumber(values.proteins) or 0) > CONSUME_EPSILON
end

local function requiresMeasuredEvolvedDelta(item, values)
    if type(values) ~= "table" then
        return false
    end

    if safeCall(item, "isSpice") == true then
        return hasMeaningfulMacroValues(values)
    end

    return math.abs(tonumber(values.hunger) or 0) > CONSUME_EPSILON
        or math.abs(tonumber(values.baseHunger) or 0) > CONSUME_EPSILON
        or hasMeaningfulMacroValues(values)
end

local function formatN(value)
    local n = tonumber(value)
    if n == nil then
        return "nil"
    end
    return string.format("%.3f", n)
end

local function formatPayload(values)
    if type(values) ~= "table" then
        return "nil"
    end
    return string.format(
        "h=%s kcal=%s c=%s f=%s p=%s",
        formatN(values.hunger),
        formatN(values.kcal),
        formatN(values.carbs),
        formatN(values.fats),
        formatN(values.proteins)
    )
end

local function formatDelta(beforeValues, afterValues)
    local function d(key)
        return (tonumber(afterValues and afterValues[key]) or 0) - (tonumber(beforeValues and beforeValues[key]) or 0)
    end
    return string.format(
        "dh=%s dkcal=%s dc=%s df=%s dp=%s",
        formatN(d("hunger")),
        formatN(d("kcal")),
        formatN(d("carbs")),
        formatN(d("fats")),
        formatN(d("proteins"))
    )
end

local function assertConsumeRuntimeReady(where)
    refreshBindings()
    local resolverReady = type(getResolveConsumedContext()) == "function"
    local authorityReady = type(ItemAuthority) == "table"
        and (type(ItemAuthority.resolveGameplayConsumeContext) == "function"
            or type(ItemAuthority.resolveConsumedPayload) == "function")
    if resolverReady and authorityReady then
        return
    end

    error(string.format(
        "[NMS_BOOT_HARD_FAIL] where=%s resolver=%s authority=%s gameplay=%s legacy=%s",
        tostring(where or "unknown"),
        tostring(resolverReady),
        tostring(type(ItemAuthority) == "table"),
        tostring(type(ItemAuthority) == "table" and type(ItemAuthority.resolveGameplayConsumeContext) == "function"),
        tostring(type(ItemAuthority) == "table" and type(ItemAuthority.resolveConsumedPayload) == "function")
    ))
end

local function assertHandcraftRuntimeReady(where)
    refreshBindings()
    local authorityReady = type(ItemAuthority) == "table"
        and type(ItemAuthority.sumConsumedPayload) == "function"
        and type(ItemAuthority.seedDynamicOutputs) == "function"
    if authorityReady then
        return
    end

    error(string.format(
        "[NMS_BOOT_HARD_FAIL] where=%s authority=%s sum=%s seed=%s",
        tostring(where or "unknown"),
        tostring(type(ItemAuthority) == "table"),
        tostring(type(ItemAuthority) == "table" and type(ItemAuthority.sumConsumedPayload) == "function"),
        tostring(type(ItemAuthority) == "table" and type(ItemAuthority.seedDynamicOutputs) == "function")
    ))
end

function MPClient.wrapDrinkFluidAction()
    assertConsumeRuntimeReady("wrap-drink")
    if NutritionMakesSense._drinkFluidWrapped then
        return
    end

    require "TimedActions/ISDrinkFluidAction"
    if type(ISDrinkFluidAction) ~= "table" or type(ISDrinkFluidAction.updateEat) ~= "function" then
        error("[NMS_BOOT_HARD_FAIL] missing TimedActions/ISDrinkFluidAction.updateEat")
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

        local resolveConsumed = getResolveConsumedContext()
        local applyConsume = getApplyLocalConsume()
        local consumedContext = type(resolveConsumed) == "function" and resolveConsumed(item, consumedFraction, preVisibleHunger) or nil
        if type(consumedContext) == "table" and consumedContext.skip == true then
            return
        end
        if not consumedContext then
            raiseConsumeHardFail(
                "drink-fluid",
                safeCall(item, "getFullType") or item,
                consumedFraction,
                type(resolveConsumed) == "function" and "context-missing" or "resolver-missing"
            )
            return
        end
        applyConsumeOrHardFail(
            "drink-fluid",
            character,
            item,
            consumedContext,
            consumedFraction,
            safeCall(item, "getFullType") or item,
            applyConsume,
            "context-missing"
        )
    end

    NutritionMakesSense._drinkFluidWrapped = true
end

function MPClient.wrapEatFoodAction()
    assertConsumeRuntimeReady("wrap-eat")
    if NutritionMakesSense._eatFoodWrapped then
        return
    end

    require "TimedActions/ISEatFoodAction"
    if type(ISEatFoodAction) ~= "table" or type(ISEatFoodAction.complete) ~= "function" then
        error("[NMS_BOOT_HARD_FAIL] missing TimedActions/ISEatFoodAction.complete")
    end

    local originalStart = ISEatFoodAction.start
    ISEatFoodAction.start = function(self)
        if self and self.item then
            self._nmsConsumeFullType = resolveConsumeFullType(self.item, self)
        end
        if type(originalStart) == "function" then
            return originalStart(self)
        end
        return nil
    end

    local originalComplete = ISEatFoodAction.complete
    ISEatFoodAction.complete = function(self)
        local item = self and self.item or nil
        local character = self and self.character or nil
        local fullTypeHint = resolveConsumeFullType(item, self)
        local preVisibleHunger = type(getVisibleHunger) == "function" and getVisibleHunger(character) or 0
        local fraction = item and resolveEatFraction(item, self and self.percentage or 1) or 0
        local consumedContext = nil
        local resolveConsumed = getResolveConsumedContext()
        local applyConsume = getApplyLocalConsume()

        if fraction > CONSUME_EPSILON and type(resolveConsumed) == "function" then
            consumedContext = resolveConsumed(item, fraction, preVisibleHunger, fullTypeHint)
        end

        local result = type(originalComplete) == "function" and originalComplete(self) or true
        if type(consumedContext) == "table" and consumedContext.skip == true then
            return result
        end
        if not consumedContext then
            local reason = "unknown"
            if fraction <= CONSUME_EPSILON then
                return result
            elseif type(resolveConsumed) ~= "function" then
                reason = "resolver-missing"
            elseif type(ItemAuthority) ~= "table" then
                reason = "authority-missing"
            elseif type(ItemAuthority.resolveGameplayConsumeContext) ~= "function"
                and type(ItemAuthority.resolveConsumedPayload) ~= "function"
            then
                reason = "authority-consume-api-missing"
            else
                reason = "context-missing"
            end
            raiseConsumeHardFail(
                "eat-food",
                fullTypeHint or safeCall(item, "getFullType") or item or "unknown",
                fraction,
                reason
            )
        end

        applyConsumeOrHardFail(
            "eat-food",
            character,
            item,
            consumedContext,
            fraction,
            fullTypeHint,
            applyConsume,
            "context-missing"
        )
        return result
    end

    NutritionMakesSense._eatFoodWrapped = true
    log(string.format(
        "[NMS_HOOK_WRAP] hook=eat resolver=%s authority=%s gameplay=%s legacy=%s",
        tostring(type(getResolveConsumedContext()) == "function"),
        tostring(type(ItemAuthority) == "table"),
        tostring(type(ItemAuthority) == "table" and type(ItemAuthority.resolveGameplayConsumeContext) == "function"),
        tostring(type(ItemAuthority) == "table" and type(ItemAuthority.resolveConsumedPayload) == "function")
    ))
end

function MPClient.wrapHandcraftAction()
    assertHandcraftRuntimeReady("wrap-handcraft")
    if NutritionMakesSense._handcraftWrapped then
        return
    end

    require "Entity/TimedActions/ISHandcraftAction"
    if type(ISHandcraftAction) ~= "table" or type(ISHandcraftAction.performRecipe) ~= "function" then
        error("[NMS_BOOT_HARD_FAIL] missing Entity/TimedActions/ISHandcraftAction.performRecipe")
    end

    local originalPerformRecipe = ISHandcraftAction.performRecipe
    ISHandcraftAction.performRecipe = function(self)
        local payloadValues = nil
        local consumedCount = 0
        if ItemAuthority and type(ItemAuthority.sumConsumedPayload) == "function" then
            local recipeData = self and self.logic and safeCall(self.logic, "getRecipeData") or nil
            local consumedItems = recipeData and safeCall(recipeData, "getAllConsumedItems") or nil
            local consumedList = collectItems(consumedItems)
            consumedCount = #consumedList
            payloadValues = ItemAuthority.sumConsumedPayload(consumedItems)
        end

        local result = originalPerformRecipe(self)

        if payloadValues and ItemAuthority and type(ItemAuthority.seedDynamicOutputs) == "function" then
            local created = {}
            if self and self.logic and type(self.logic.getCreatedOutputItems) == "function" and ArrayList then
                local createdList = ArrayList.new()
                local ok = pcall(self.logic.getCreatedOutputItems, self.logic, createdList)
                if ok then
                    created = collectItems(createdList)
                end
            end
            ItemAuthority.seedDynamicOutputs(created, payloadValues, "handcraft-create")
        end

        return result
    end

    NutritionMakesSense._handcraftWrapped = true
end

function MPClient.wrapAddItemInRecipeAction()
    assertConsumeRuntimeReady("wrap-evolved")
    if NutritionMakesSense._addItemRecipeWrapped then
        return
    end

    require "TimedActions/ISAddItemInRecipe"
    if type(ISAddItemInRecipe) ~= "table" or type(ISAddItemInRecipe.complete) ~= "function" then
        error("[NMS_BOOT_HARD_FAIL] missing TimedActions/ISAddItemInRecipe.complete")
    end

    local originalComplete = ISAddItemInRecipe.complete
    ISAddItemInRecipe.complete = function(self)
        refreshBindings()
        local usedItem = self and self.usedItem or nil
        local usedEntry, usedFullType = nil, nil
        if type(ItemAuthority.getFoodEntry) == "function" then
            usedEntry, usedFullType = ItemAuthority.getFoodEntry(usedItem)
        end
        local usedCurrent = usedItem and usedFullType
            and type(ItemAuthority.readCurrentValuesPrivate) == "function"
            and ItemAuthority.readCurrentValuesPrivate(usedItem, usedFullType, usedEntry) or nil
        local baseItemBefore = self and self.baseItem or nil
        local beforeEntry, beforeFullType = nil, nil
        if type(ItemAuthority.getFoodEntry) == "function" then
            beforeEntry, beforeFullType = ItemAuthority.getFoodEntry(baseItemBefore)
        end
        local beforeCurrent = baseItemBefore and beforeFullType
            and type(ItemAuthority.readCurrentValuesPrivate) == "function"
            and ItemAuthority.readCurrentValuesPrivate(baseItemBefore, beforeFullType, beforeEntry) or nil

        local result = originalComplete(self)

        local baseItem = self and self.baseItem or baseItemBefore
        local afterEntry, afterFullType = nil, nil
        if type(ItemAuthority.getFoodEntry) == "function" then
            afterEntry, afterFullType = ItemAuthority.getFoodEntry(baseItem)
        end
        local afterCurrent = baseItem and afterFullType
            and type(ItemAuthority.readCurrentValuesPrivate) == "function"
            and ItemAuthority.readCurrentValuesPrivate(baseItem, afterFullType, afterEntry) or nil
        local measureEntry = afterEntry
        local measureFullType = afterFullType
        if not measureEntry or not measureFullType then
            measureEntry = beforeEntry
            measureFullType = beforeFullType
        end
        local addedValues = type(ItemAuthority.measureAccumulatedPayload) == "function"
            and ItemAuthority.measureAccumulatedPayload(measureFullType, measureEntry, beforeCurrent, afterCurrent)
            or nil

        if addedValues and type(ItemAuthority.accumulateDynamicPayload) == "function" then
            ItemAuthority.accumulateDynamicPayload(baseItem, addedValues, "evolved-add-item")
            local debugSnapshot = type(ItemAuthority.getDebugSnapshot) == "function" and ItemAuthority.getDebugSnapshot(baseItem) or nil
            local storedAfter = debugSnapshot and debugSnapshot.stored or nil
            local displayAfter = debugSnapshot and debugSnapshot.display or nil
            log(string.format(
                "[NMS_EVOLVED_ADD] base=%s ingredient=%s before={%s} after={%s} delta={%s} added={%s} stored_after={%s} display_after={%s}",
                tostring(afterFullType or beforeFullType or safeCall(baseItem, "getFullType") or "unknown"),
                tostring(usedFullType or safeCall(usedItem, "getFullType") or usedItem or "unknown"),
                tostring(formatPayload(beforeCurrent)),
                tostring(formatPayload(afterCurrent)),
                tostring(formatDelta(beforeCurrent, afterCurrent)),
                tostring(formatPayload(addedValues)),
                tostring(formatPayload(storedAfter)),
                tostring(formatPayload(displayAfter))
            ))
        elseif requiresMeasuredEvolvedDelta(usedItem, usedCurrent) then
            error(string.format(
                "[NMS_EVOLVED_ADD_HARD_FAIL] base=%s ingredient=%s detail=delta-missing before=%s after=%s used=%s",
                tostring(afterFullType or beforeFullType or safeCall(baseItem, "getFullType") or "unknown"),
                tostring(usedFullType or safeCall(usedItem, "getFullType") or usedItem or "unknown"),
                tostring(formatPayload(beforeCurrent)),
                tostring(formatPayload(afterCurrent)),
                tostring(formatPayload(usedCurrent))
            ))
        else
            log(string.format(
                "[NMS_EVOLVED_ADD_SKIP] base=%s ingredient=%s before={%s} after={%s} used={%s} detail=no-delta-required",
                tostring(afterFullType or beforeFullType or safeCall(baseItem, "getFullType") or "unknown"),
                tostring(usedFullType or safeCall(usedItem, "getFullType") or usedItem or "unknown"),
                tostring(formatPayload(beforeCurrent)),
                tostring(formatPayload(afterCurrent)),
                tostring(formatPayload(usedCurrent))
            ))
        end

        return result
    end

    NutritionMakesSense._addItemRecipeWrapped = true
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
