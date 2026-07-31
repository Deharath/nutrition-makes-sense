NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_TooltipLogic"

local TooltipOverlay = NutritionMakesSense.TooltipOverlay or {}
NutritionMakesSense.TooltipOverlay = TooltipOverlay

local CoreUtils = NutritionMakesSense.CoreUtils or {}
local TooltipLogic = NutritionMakesSense.TooltipLogic or {}
local safeCall = CoreUtils.safeCall
local loggedMessages = {}

local TOOLTIP_MIN_LABEL_WIDTH = 80
local TOOLTIP_MIN_VALUE_WIDTH = 80
local TOOLTIP_MIN_WIDTH = 150
local TOOLTIP_TITLE_GAP = 5

local function logOnce(key, message)
    if loggedMessages[key] then
        return
    end
    loggedMessages[key] = true
    if NutritionMakesSense.log then
        NutritionMakesSense.log(message)
    end
end

local function listHasEntries(list)
    if not list then
        return false
    end

    local size = tonumber(safeCall(list, "size"))
    if size ~= nil then
        return size > 0
    end
    return type(list) == "table" and next(list) ~= nil
end

local function ingredientRowCount(item)
    local count = listHasEntries(safeCall(item, "getExtraItems")) and 1 or 0
    if listHasEntries(safeCall(item, "getSpices")) then
        count = count + 1
    end
    return count
end

local function getTextManagerSafe()
    if type(getTextManager) == "function" then
        local ok, value = pcall(getTextManager)
        if ok and value then
            return value
        end
    end
    return _G.TextManager and TextManager.instance or nil
end

local function tooltipLayoutGeometry(tooltip, item)
    local lineSpacing = tonumber(safeCall(tooltip, "getLineSpacing")) or 14
    local font = safeCall(tooltip, "getFont")
    local digitWidth = tonumber(safeCall(getTextManagerSafe(), "MeasureStringX", font, "0")) or 5
    if digitWidth < 1 then
        digitWidth = 5
    end

    local horizontalPad = math.max(0, math.floor(digitWidth))
    local verticalPad = math.max(0, math.floor(digitWidth / 2))
    local contentY = verticalPad + lineSpacing + TOOLTIP_TITLE_GAP
    contentY = contentY + ingredientRowCount(item) * (lineSpacing + TOOLTIP_TITLE_GAP)
    return horizontalPad, contentY, verticalPad
end

local function withHiddenVanillaHunger(item, callback)
    local hideTag = ItemTag and ItemTag.HIDE_HUNGER_CHANGE or nil
    local tags = hideTag and safeCall(item, "getTags") or nil
    local addedTag = false

    if hideTag and tags and safeCall(item, "hasTag", hideTag) ~= true then
        safeCall(tags, "add", hideTag)
        addedTag = safeCall(item, "hasTag", hideTag) == true
    end

    local ok, result = pcall(callback)

    if addedTag then
        safeCall(tags, "remove", hideTag)
    end
    return ok, result
end

local function renderCombinedTooltip(tooltip, item)
    local layout = safeCall(tooltip, "beginLayout")
    if not layout then
        return false
    end

    safeCall(layout, "setMinLabelWidth", TOOLTIP_MIN_LABEL_WIDTH)
    safeCall(layout, "setMinValueWidth", TOOLTIP_MIN_VALUE_WIDTH)

    local embedded = item and item.DoTooltipEmbedded or nil
    if type(embedded) ~= "function" then
        safeCall(tooltip, "endLayout", layout)
        error("B42 tooltip contract missing InventoryItem.DoTooltipEmbedded")
    end

    local ok, failure = withHiddenVanillaHunger(item, function()
        return embedded(item, tooltip, layout, 0)
    end)
    if not ok then
        safeCall(tooltip, "endLayout", layout)
        error(failure)
    end

    TooltipLogic.appendDescriptorRowsToLayoutForViewer(
        layout,
        item,
        safeCall(tooltip, "getCharacter")
    )

    local padLeft, contentY, padBottom = tooltipLayoutGeometry(tooltip, item)
    local height = tonumber(safeCall(layout, "render", padLeft, contentY, tooltip)) or contentY
    safeCall(tooltip, "endLayout", layout)
    safeCall(tooltip, "setHeight", math.floor(height + padBottom))

    local width = tonumber(safeCall(tooltip, "getWidth")) or 0
    if width < TOOLTIP_MIN_WIDTH then
        safeCall(tooltip, "setWidth", TOOLTIP_MIN_WIDTH)
    end
    return true
end

local function getItemMethods(item)
    local ok, metatable = pcall(getmetatable, item)
    if not ok or type(metatable) ~= "table" or type(metatable.__index) ~= "table" then
        return nil
    end
    return metatable.__index
end

local function providerOwnsFoodTooltips()
    local controller = rawget(_G, "EuryTooltipController")
    return controller ~= nil
        and controller.installed == true
        and TooltipOverlay._registeredController == controller
        and type(controller.providers) == "table"
        and controller.providers.NutritionMakesSense == TooltipOverlay._provider
end

local function withFoodTooltipExtension(item, tooltip, delegateToController, callback)
    if not item or not tooltip or not TooltipLogic.isFoodItem(item) then
        return callback()
    end
    if delegateToController and providerOwnsFoodTooltips() then
        return callback()
    end

    local methods = getItemMethods(item)
    local originalDoTooltip = methods and methods.DoTooltip or nil
    if type(originalDoTooltip) ~= "function" then
        return callback()
    end

    local replacement
    replacement = function(target, targetTooltip, ...)
        if target == item and targetTooltip == tooltip then
            return renderCombinedTooltip(targetTooltip, target)
        end
        return originalDoTooltip(target, targetTooltip, ...)
    end
    methods.DoTooltip = replacement

    local ok, result = pcall(callback)
    if methods.DoTooltip == replacement then
        methods.DoTooltip = originalDoTooltip
    end
    if not ok then
        error(result)
    end
    return result
end

local function registerProvider()
    local controller = rawget(_G, "EuryTooltipController")
    if type(controller) ~= "table" or type(controller.registerProvider) ~= "function" then
        return false
    end

    TooltipOverlay._provider = TooltipOverlay._provider or {
        priority = 80,
        ownsTooltip = function(_, ctx)
            return TooltipLogic.isFoodItem(ctx and ctx.item)
        end,
        renderMain = function(_, ctx)
            return renderCombinedTooltip(ctx and ctx.tooltip, ctx and ctx.item)
        end,
    }

    local ok = pcall(
        controller.registerProvider,
        controller,
        "NutritionMakesSense",
        TooltipOverlay._provider
    )
    if ok then
        TooltipOverlay._registeredController = controller
        logOnce("tooltip_provider_installed", "[TOOLTIP] NMS registered as the shared food-tooltip provider.")
    end
    return ok
end

local function installInventoryTooltipPatch()
    if not ISToolTipInv or type(ISToolTipInv.render) ~= "function" then
        return false
    end
    if ISToolTipInv.render == ISToolTipInv._nmsTooltipRenderWrapper then
        return true
    end

    local originalRender = ISToolTipInv.render
    local wrapper = function(self)
        if self and self._nmsTooltipRenderActive == true then
            return originalRender(self)
        end

        self._nmsTooltipRenderActive = true
        local ok, result = pcall(function()
            return withFoodTooltipExtension(self.item, self.tooltip, true, function()
                return originalRender(self)
            end)
        end)
        self._nmsTooltipRenderActive = nil
        if not ok then
            error(result)
        end
        return result
    end

    ISToolTipInv._nmsTooltipRenderWrapper = wrapper
    ISToolTipInv.render = wrapper
    logOnce("tooltip_inventory_patch_installed", "[TOOLTIP] NMS rows registered around the inventory tooltip owner.")
    return true
end

local function installItemSlotTooltipPatch()
    if not ISItemSlot or type(ISItemSlot.drawTooltip) ~= "function" then
        return false
    end
    if ISItemSlot.drawTooltip == ISItemSlot._nmsTooltipDrawWrapper then
        return true
    end

    local originalDrawTooltip = ISItemSlot.drawTooltip
    local wrapper = function(itemSlot, tooltip)
        if itemSlot and itemSlot._nmsTooltipDrawActive == true then
            return originalDrawTooltip(itemSlot, tooltip)
        end

        itemSlot._nmsTooltipDrawActive = true
        local item = itemSlot and (itemSlot.resource or itemSlot.storedItem) or nil
        local ok, result = pcall(function()
            return withFoodTooltipExtension(item, tooltip, false, function()
                return originalDrawTooltip(itemSlot, tooltip)
            end)
        end)
        itemSlot._nmsTooltipDrawActive = nil
        if not ok then
            error(result)
        end
        return result
    end

    ISItemSlot._nmsTooltipDrawWrapper = wrapper
    ISItemSlot.drawTooltip = wrapper
    logOnce("tooltip_item_slot_patch_installed", "[TOOLTIP] NMS rows registered around the item-slot tooltip owner.")
    return true
end

function TooltipOverlay.install()
    registerProvider()
    local inventoryReady = installInventoryTooltipPatch()
    local itemSlotReady = installItemSlotTooltipPatch()

    if not TooltipOverlay._retryEventsInstalled then
        TooltipOverlay._retryEventsInstalled = true
        if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
            Events.OnGameBoot.Add(TooltipOverlay.install)
        end
        if Events and Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
            Events.OnGameStart.Add(TooltipOverlay.install)
        end
        if Events and Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
            Events.OnCreatePlayer.Add(TooltipOverlay.install)
        end
    end

    return inventoryReady or itemSlotReady
end

TooltipOverlay.renderCombinedTooltip = renderCombinedTooltip

return TooltipOverlay
