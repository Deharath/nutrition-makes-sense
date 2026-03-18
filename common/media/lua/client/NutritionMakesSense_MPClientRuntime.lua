NutritionMakesSense = NutritionMakesSense or {}
NutritionMakesSense.MPClientRuntime = NutritionMakesSense.MPClientRuntime or {}

require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_MetabolismRuntime"
require "NutritionMakesSense_ItemAuthority"

local MP = NutritionMakesSense.MP or {}
local Metabolism = NutritionMakesSense.Metabolism or {}
local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
local MPClient = NutritionMakesSense.MPClientRuntime
local bootLogged = false
local latestSnapshot = nil
local lastRequestWallSecond = 0
local nextEventSequence = 0
local runtimeEventSessionId = nil
local CONSUME_EPSILON = 0.0001

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, result = pcall(method, target, ...)
    if not ok then
        return nil
    end

    return result
end

local function clamp01(value)
    local numeric = tonumber(value) or 0
    if numeric < 0 then
        return 0
    end
    if numeric > 1 then
        return 1
    end
    return numeric
end

local function getCharacterStatValue(stats, enumKey, getterName)
    if not stats then
        return nil
    end

    if CharacterStat and enumKey and CharacterStat[enumKey] then
        local value = safeCall(stats, "get", CharacterStat[enumKey])
        if value ~= nil then
            return tonumber(value)
        end
    end

    if getterName then
        return tonumber(safeCall(stats, getterName))
    end

    return nil
end

local function isClientRuntime()
    return type(isClient) == "function" and isClient() == true and not (type(isServer) == "function" and isServer() == true)
end

local function isLocalAuthorityRuntime()
    return not isClientRuntime()
end

local function getWorldAgeMinutes()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    if not gameTime then
        return 0
    end
    local ok, hours = pcall(gameTime.getWorldAgeHours, gameTime)
    if not ok then
        return 0
    end
    return math.floor((tonumber(hours) or 0) * 60)
end

local function getWallClockSeconds()
    if type(getTimestampMs) == "function" then
        local nowMs = tonumber(getTimestampMs())
        if nowMs ~= nil then
            return math.floor(nowMs / 1000)
        end
    end
    if type(getTimestamp) == "function" then
        local nowSecond = tonumber(getTimestamp())
        if nowSecond ~= nil then
            return math.floor(nowSecond)
        end
    end
    return 0
end

local function getPlayerLabel(playerObj, fallback)
    local username = safeCall(playerObj, "getUsername")
    if username and username ~= "" then
        return tostring(username)
    end
    local displayName = safeCall(playerObj, "getDisplayName")
    if displayName and displayName ~= "" then
        return tostring(displayName)
    end
    return tostring(fallback or playerObj or "unknown")
end

local function getLocalPlayer(playerIndex, playerObj)
    if playerObj then
        return playerObj
    end
    if type(getSpecificPlayer) == "function" and playerIndex ~= nil then
        local resolved = getSpecificPlayer(playerIndex)
        if resolved then
            return resolved
        end
    end
    if type(getPlayer) == "function" then
        return getPlayer()
    end
    return nil
end

local function normalizeIdComponent(value, fallback)
    local text = tostring(value or "")
    text = text:gsub("[^%w_.-]", "-")
    text = text:gsub("-+", "-")
    text = text:gsub("^%-", "")
    text = text:gsub("%-$", "")
    if text == "" then
        return tostring(fallback or "unknown")
    end
    return text
end

local function getRuntimeEventSessionId()
    if runtimeEventSessionId then
        return runtimeEventSessionId
    end

    local wallClockMs = tonumber(type(getTimestampMs) == "function" and getTimestampMs() or nil)
    if wallClockMs == nil then
        wallClockMs = (tonumber(getWallClockSeconds()) or 0) * 1000
    end

    local worldMinute = getWorldAgeMinutes()
    local uniqueToken = tostring({})
    local uniqueSuffix = uniqueToken:match("0x[%da-fA-F]+") or uniqueToken

    runtimeEventSessionId = string.format(
        "%s-%s-%s",
        normalizeIdComponent(wallClockMs, "0"),
        normalizeIdComponent(worldMinute, "0"),
        normalizeIdComponent(uniqueSuffix, "session")
    )
    return runtimeEventSessionId
end

function MPClient.getRuntimeEventSessionId()
    return getRuntimeEventSessionId()
end

local function makeEventId(playerObj, itemId, reason)
    nextEventSequence = nextEventSequence + 1
    return string.format(
        "%s:%s:%s:%s:%d",
        tostring(getPlayerLabel(playerObj, "player")),
        tostring(getRuntimeEventSessionId()),
        tostring(itemId or "item"),
        tostring(reason or "consume"),
        tonumber(nextEventSequence)
    )
end

local function resolveEatFraction(item, percentage)
    local percent = clamp01(percentage or 1)
    local baseHunger = tonumber(safeCall(item, "getBaseHunger") or 0) or 0
    local hungerChange = tonumber(safeCall(item, "getHungChange") or safeCall(item, "getHungerChange") or 0) or 0

    if baseHunger ~= 0 and hungerChange ~= 0 then
        local hungerToConsume = baseHunger * percent
        local usedPercent = hungerToConsume / hungerChange
        percent = clamp01(usedPercent)
    end

    if hungerChange < 0 and hungerChange * (1.0 - percent) > -0.01 then
        percent = 1.0
    end

    local thirstChange = tonumber(safeCall(item, "getThirstChange") or 0) or 0
    if hungerChange == 0 and thirstChange < 0 and thirstChange * (1.0 - percent) > -0.01 then
        percent = 1.0
    end

    return clamp01(percent)
end

function MPClient.getSnapshot()
    return latestSnapshot
end

function MPClient.clearSnapshot()
    latestSnapshot = nil
end

function MPClient.requestSnapshot(reason, force)
    if not isClientRuntime() or type(sendClientCommand) ~= "function" then
        return false
    end

    local nowSecond = getWallClockSeconds()
    if (not force) and (nowSecond - lastRequestWallSecond) < 1 then
        return false
    end
    lastRequestWallSecond = nowSecond

    local args = {
        reason = tostring(reason or "client-request"),
        worldMinute = getWorldAgeMinutes(),
    }
    return pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.REQUEST_SNAPSHOT_COMMAND), args)
end

function MPClient.queueConsume(playerObj, item, fraction, reason, consumedValues, immediateHunger)
    if not isClientRuntime() or type(sendClientCommand) ~= "function" then
        return false
    end

    local consumedFraction = clamp01(fraction or 0)
    if consumedFraction <= CONSUME_EPSILON then
        return false
    end

    local itemId = ItemAuthority.getItemId and ItemAuthority.getItemId(item) or tonumber(safeCall(item, "getID") or item and item.id or nil)
    local fullType = safeCall(item, "getFullType") or item and (item.fullType or item.id) or nil
    if itemId == nil or not fullType then
        return false
    end

    if not latestSnapshot then
        MPClient.requestSnapshot("pre-consume-bootstrap", true)
    end

    local eventId = makeEventId(playerObj, itemId, reason)
    local args = {
        eventId = eventId,
        itemId = itemId,
        fullType = tostring(fullType),
        fraction = consumedFraction,
        reason = tostring(reason or "consume"),
        worldMinute = getWorldAgeMinutes(),
    }
    if type(consumedValues) == "table" then
        args.consumed = {
            hunger = tonumber(consumedValues.hunger) or 0,
            baseHunger = tonumber(consumedValues.baseHunger or consumedValues.hunger) or 0,
            kcal = tonumber(consumedValues.kcal) or 0,
            carbs = tonumber(consumedValues.carbs) or 0,
            fats = tonumber(consumedValues.fats) or 0,
            proteins = tonumber(consumedValues.proteins) or 0,
        }
    end
    if type(immediateHunger) == "table" then
        args.immediateHungerDrop = tonumber(immediateHunger.drop) or 0
        args.preVisibleHunger = tonumber(immediateHunger.preVisibleHunger) or 0
    elseif immediateHunger ~= nil then
        args.immediateHungerDrop = tonumber(immediateHunger) or 0
    end

    local ok = pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.CONSUME_COMMAND), args)
    if ok then
        log(string.format(
            "[CLIENT_CONSUME_REQUEST] event=%s item=%s fraction=%.3f reason=%s payload=%s",
            tostring(eventId),
            tostring(fullType),
            consumedFraction,
            tostring(reason or "consume"),
            tostring(args.consumed ~= nil)
        ))
    end
    return ok, eventId, args
end

local function getVisibleHunger(playerObj)
    local stats = playerObj and safeCall(playerObj, "getStats") or nil
    return getCharacterStatValue(stats, "HUNGER", "getHunger") or 0
end

local function resolveImmediateHunger(consumedValues, preVisibleHunger)
    if type(consumedValues) ~= "table" or not Metabolism then
        return nil
    end

    local drop = type(Metabolism.getImmediateHungerDrop) == "function"
        and tonumber(Metabolism.getImmediateHungerDrop(consumedValues, 1))
        or nil
    if drop == nil then
        return nil
    end

    return {
        drop = drop,
        preVisibleHunger = tonumber(preVisibleHunger) or 0,
        targetVisibleHunger = math.max(0, (tonumber(preVisibleHunger) or 0) - drop),
        mechanical = math.abs(tonumber(consumedValues.hunger) or 0),
    }
end

local function resolveConsumedValues(item, fraction)
    if not item or not ItemAuthority or type(ItemAuthority.getConsumedValues) ~= "function" then
        return nil
    end

    local consumedFraction = clamp01(fraction or 0)
    if consumedFraction <= CONSUME_EPSILON then
        return nil
    end

    local values = ItemAuthority.getConsumedValues(item, consumedFraction)
    if type(values) ~= "table" then
        return nil
    end

    local kcal = tonumber(values.kcal) or 0
    local carbs = tonumber(values.carbs) or 0
    local fats = tonumber(values.fats) or 0
    local proteins = tonumber(values.proteins) or 0
    local hunger = math.abs(tonumber(values.hunger) or 0)
    if kcal <= CONSUME_EPSILON
        and carbs <= CONSUME_EPSILON
        and fats <= CONSUME_EPSILON
        and proteins <= CONSUME_EPSILON
        and hunger <= CONSUME_EPSILON then
        return nil
    end

    return values
end

local function getBurntNutritionMultiplier(item)
    if safeCall(item, "isBurnt") == true then
        return 0.2
    end
    return 1
end

local function subtractConsumedValues(beforeValues, afterValues, item)
    if type(beforeValues) ~= "table" then
        return nil
    end

    local after = type(afterValues) == "table" and afterValues or nil
    local multiplier = getBurntNutritionMultiplier(item)
    local consumed = {
        hunger = math.max(0, (tonumber(beforeValues.hunger) or 0) - (tonumber(after and after.hunger) or 0)),
        baseHunger = tonumber(beforeValues.baseHunger) or tonumber(beforeValues.hunger) or 0,
        kcal = math.max(0, (tonumber(beforeValues.kcal) or 0) - (tonumber(after and after.kcal) or 0)) * multiplier,
        carbs = math.max(0, (tonumber(beforeValues.carbs) or 0) - (tonumber(after and after.carbs) or 0)) * multiplier,
        fats = math.max(0, (tonumber(beforeValues.fats) or 0) - (tonumber(after and after.fats) or 0)) * multiplier,
        proteins = math.max(0, (tonumber(beforeValues.proteins) or 0) - (tonumber(after and after.proteins) or 0)) * multiplier,
    }

    if consumed.kcal <= CONSUME_EPSILON
        and consumed.carbs <= CONSUME_EPSILON
        and consumed.fats <= CONSUME_EPSILON
        and consumed.proteins <= CONSUME_EPSILON then
        return nil
    end

    return consumed
end

local function summarizeNutritionValues(values)
    if type(values) ~= "table" then
        return "nil"
    end
    return string.format(
        "hunger=%.4f base=%.4f kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f",
        tonumber(values.hunger or 0),
        tonumber(values.baseHunger or values.hunger or 0),
        tonumber(values.kcal or 0),
        tonumber(values.carbs or 0),
        tonumber(values.fats or 0),
        tonumber(values.proteins or 0)
    )
end

local function resolveConsumeAuthoritySource(item)
    if not item or not ItemAuthority then
        return ""
    end
    if type(ItemAuthority.getResolvedNutritionSource) == "function" then
        return tostring(ItemAuthority.getResolvedNutritionSource(item) or "")
    end

    local stored = type(ItemAuthority.readStoredSnapshot) == "function" and ItemAuthority.readStoredSnapshot(item) or nil
    if stored then
        return "computed"
    end
    return "authored"
end

local function usesCustomMpConsume(item)
    return isClientRuntime() and resolveConsumeAuthoritySource(item) ~= ""
end

local function collectItems(listLike)
    local items = {}
    if not listLike then
        return items
    end

    local size = safeCall(listLike, "size")
    if type(size) == "number" then
        for index = 0, size - 1 do
            items[#items + 1] = safeCall(listLike, "get", index)
        end
        return items
    end

    if type(listLike) == "table" then
        for _, item in ipairs(listLike) do
            items[#items + 1] = item
        end
    end
    return items
end

local function applyLocalConsume(playerObj, item, consumedValues, fraction, reason, preVisibleHunger)
    if not isLocalAuthorityRuntime() or not Runtime or type(Runtime.applyAuthoritativeDeposit) ~= "function" then
        return false
    end

    local fullType = safeCall(item, "getFullType") or item and (item.fullType or item.id) or "unknown"
    local itemId = ItemAuthority.getItemId and ItemAuthority.getItemId(item) or tonumber(safeCall(item, "getID") or item and item.id or nil)
    local eventId = makeEventId(playerObj, itemId, reason)
    local immediateHunger = resolveImmediateHunger(consumedValues, preVisibleHunger)
    local report = Runtime.applyAuthoritativeDeposit(playerObj, consumedValues, reason or "local-consume", {
        eventId = eventId,
    })
    if not report then
        return false
    end
    if immediateHunger and type(Runtime.applyVisibleHungerTarget) == "function" then
        Runtime.applyVisibleHungerTarget(playerObj, immediateHunger.targetVisibleHunger, (reason or "local-consume") .. "-hunger")
    end

    local DevPanel = NutritionMakesSense.DevPanel
    if DevPanel and type(DevPanel.noteConsumeEvent) == "function" then
        DevPanel.noteConsumeEvent({
            reason = reason or "local-consume",
            item = fullType,
            consume_source = resolveConsumeAuthoritySource(item),
            fraction = fraction,
            kcal = consumedValues.kcal,
            carbs = consumedValues.carbs,
            fats = consumedValues.fats,
            proteins = consumedValues.proteins,
            immediate_hunger_drop = immediateHunger and immediateHunger.drop or nil,
            immediate_hunger_mechanical = immediateHunger and immediateHunger.mechanical or nil,
            pre_visible_hunger = immediateHunger and immediateHunger.preVisibleHunger or nil,
            target_visible_hunger = immediateHunger and immediateHunger.targetVisibleHunger or nil,
        })
    end

    log(string.format(
        "[LOCAL_CONSUME] event=%s item=%s fraction=%.3f kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f hunger_drop=%.4f",
        tostring(eventId),
        tostring(fullType),
        tonumber(fraction or 0),
        tonumber(consumedValues.kcal or 0),
        tonumber(consumedValues.carbs or 0),
        tonumber(consumedValues.fats or 0),
        tonumber(consumedValues.proteins or 0),
        tonumber(immediateHunger and immediateHunger.drop or 0)
    ))
    return true
end

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
        local preVisibleHunger = getVisibleHunger(self and self.character or nil)
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
            local consumedValues = resolveConsumedValues(item, consumedFraction)
            if consumedValues then
                local immediateHunger = resolveImmediateHunger(consumedValues, preVisibleHunger)
                MPClient.queueConsume(self and self.character or nil, item, consumedFraction, "drink-fluid", consumedValues, immediateHunger)
                if immediateHunger and type(Runtime.applyVisibleHungerTarget) == "function" then
                    Runtime.applyVisibleHungerTarget(self and self.character or nil, immediateHunger.targetVisibleHunger, "drink-fluid-client")
                end
            end
            return
        end

        if isLocalAuthorityRuntime() then
            local consumedValues = resolveConsumedValues(item, consumedFraction)
            if consumedValues then
                applyLocalConsume(self and self.character or nil, item, consumedValues, consumedFraction, "drink-fluid", preVisibleHunger)
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
        local fullType = tostring(safeCall(item, "getFullType") or item and item.fullType or "unknown")
        local beforeValues = nil
        local consumedValues = nil
        local clientImmediateHunger = nil
        if isLocalAuthorityRuntime() and item and ItemAuthority and type(ItemAuthority.getDisplayValues) == "function" then
            beforeValues = ItemAuthority.getDisplayValues(item)
            log(string.format(
                "[EAT_DEBUG] phase=before item=%s requested=%.3f before=%s",
                fullType,
                tonumber(fraction or 0),
                summarizeNutritionValues(beforeValues)
            ))
            if fraction > CONSUME_EPSILON then
                consumedValues = resolveConsumedValues(item, fraction)
                if consumedValues then
                    log(string.format(
                        "[EAT_DEBUG] phase=predicted item=%s fraction=%.3f consumed=%s",
                        fullType,
                        tonumber(fraction or 0),
                        summarizeNutritionValues(consumedValues)
                    ))
                else
                    log(string.format(
                        "[EAT_DEBUG] phase=predicted-miss item=%s fraction=%.3f",
                        fullType,
                        tonumber(fraction or 0)
                    ))
                end
            end
        elseif isClientRuntime() and fraction > CONSUME_EPSILON then
            if usesCustomMpConsume(item) then
                local mpConsumedValues = resolveConsumedValues(item, fraction)
                if mpConsumedValues then
                    clientImmediateHunger = resolveImmediateHunger(mpConsumedValues, preVisibleHunger)
                    MPClient.queueConsume(character, item, fraction, "eat-food", mpConsumedValues, clientImmediateHunger)
                end
            end
        end

        local result = originalComplete(self)
        log(string.format(
            "[EAT_DEBUG] phase=after-complete item=%s result=%s item_exists=%s hung=%s base=%s",
            fullType,
            tostring(result),
            tostring(item ~= nil),
            tostring(item and safeCall(item, "getHungChange") or "nil"),
            tostring(item and safeCall(item, "getBaseHunger") or "nil")
        ))
        if clientImmediateHunger and type(Runtime.applyVisibleHungerTarget) == "function" then
            Runtime.applyVisibleHungerTarget(character, clientImmediateHunger.targetVisibleHunger, "eat-food-client")
        end
        if consumedValues then
            applyLocalConsume(character, item, consumedValues, fraction, "eat-food", preVisibleHunger)
        elseif isLocalAuthorityRuntime() and beforeValues and ItemAuthority and item then
            local afterValues = type(ItemAuthority.readCurrentValues) == "function" and ItemAuthority.readCurrentValues(item) or nil
            log(string.format(
                "[EAT_DEBUG] phase=after-capture item=%s after=%s",
                fullType,
                summarizeNutritionValues(afterValues)
            ))
            local measuredValues = subtractConsumedValues(beforeValues, afterValues, item)
            if measuredValues then
                local measuredFraction = fraction
                local baseHunger = math.abs(tonumber(beforeValues.baseHunger) or tonumber(beforeValues.hunger) or 0)
                local consumedHunger = math.abs(tonumber(measuredValues.hunger) or 0)
                if baseHunger > CONSUME_EPSILON and consumedHunger > CONSUME_EPSILON then
                    measuredFraction = clamp01(consumedHunger / baseHunger)
                end
                log(string.format(
                    "[LOCAL_CONSUME_MEASURED] item=%s fraction=%.3f kcal=%.1f carbs=%.1f fats=%.1f proteins=%.1f",
                    tostring(safeCall(item, "getFullType") or item and item.fullType or "unknown"),
                    tonumber(measuredFraction or 0),
                    tonumber(measuredValues.kcal or 0),
                    tonumber(measuredValues.carbs or 0),
                    tonumber(measuredValues.fats or 0),
                    tonumber(measuredValues.proteins or 0)
                ))
                applyLocalConsume(character, item, measuredValues, measuredFraction, "eat-food-measured", preVisibleHunger)
            else
                log(string.format(
                    "[EAT_DEBUG] phase=measured-miss item=%s before=%s after=%s",
                    fullType,
                    summarizeNutritionValues(beforeValues),
                    summarizeNutritionValues(afterValues)
                ))
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
        local addedValues = nil
        local usedFullType = safeCall(usedItem, "getFullType") or tostring(usedItem)
        if isLocalAuthorityRuntime() then
            addedValues = resolveConsumedValues(usedItem, 1)
        end

        local result = originalComplete(self)

        local baseItem = self and self.baseItem or nil
        if isLocalAuthorityRuntime() and addedValues and ItemAuthority and type(ItemAuthority.accumulateDynamicPayload) == "function" then
            log(string.format(
                "[DYNAMIC_HOOK] hook=evolved-add used=%s base=%s payload_kcal=%.1f",
                tostring(usedFullType or "unknown"),
                tostring(safeCall(baseItem, "getFullType") or baseItem or "unknown"),
                tonumber(addedValues.kcal or 0)
            ))
            ItemAuthority.accumulateDynamicPayload(baseItem, addedValues, "evolved-add-item")
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

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) ~= tostring(MP.STATE_SNAPSHOT_COMMAND) then
        return
    end
    if not isClientRuntime() or type(args) ~= "table" then
        return
    end

    latestSnapshot = args
    local playerObj = getLocalPlayer(0, nil)
    if playerObj and Runtime.importStateSnapshot then
        Runtime.importStateSnapshot(playerObj, args, args.reason or "mp-server")
    end

    log(string.format(
        "[CLIENT_SNAPSHOT] reason=%s bootstrap=%s event=%s fuel=%.1f zone=%s",
        tostring(args.reason or "server"),
        tostring(args.bootstrap == true),
        tostring(args.eventId or "none"),
        tonumber(args.state and args.state.fuel or 0),
        tostring(args.state and args.state.lastZone or "unknown")
    ))
end

local function onCreatePlayer(playerIndex, playerObj)
    registerHooks()

    if not isClientRuntime() then
        return
    end

    MPClient.requestSnapshot("create-player", true)

    if bootLogged then
        return
    end
    bootLogged = true

    log(string.format(
        "[CLIENT_READY] player=%s version=%s module=%s",
        tostring(getPlayerLabel(playerObj, playerIndex)),
        tostring(MP.SCRIPT_VERSION or "0.1.0"),
        tostring(MP.NET_MODULE or "NutritionMakesSenseRuntime")
    ))
end

local function onGameBoot()
    registerHooks()
end

if Events then
    if Events.OnServerCommand and type(Events.OnServerCommand.Add) == "function" then
        Events.OnServerCommand.Add(onServerCommand)
    end
    if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
        Events.OnCreatePlayer.Add(onCreatePlayer)
    end
    if Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
        Events.OnGameBoot.Add(onGameBoot)
    elseif Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(onGameBoot)
    end
end

return MPClient
