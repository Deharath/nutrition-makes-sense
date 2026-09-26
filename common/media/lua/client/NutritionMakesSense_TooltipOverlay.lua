NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_TooltipLogic"
require "ui/NutritionMakesSense_Draw"
require "ui/NutritionMakesSense_UIHelpers"

local TooltipOverlay = NutritionMakesSense.TooltipOverlay or {}
NutritionMakesSense.TooltipOverlay = TooltipOverlay

local CoreUtils = NutritionMakesSense.CoreUtils or {}
local TooltipLogic = NutritionMakesSense.TooltipLogic or {}
local Draw = NutritionMakesSense.Draw
local UIHelpers = NutritionMakesSense.UIHelpers
local safeCall = CoreUtils.safeCall
local loggedMessages = {}

local TOOLTIP_MIN_LABEL_WIDTH = 80
local TOOLTIP_MIN_VALUE_WIDTH = 80
local TOOLTIP_MIN_WIDTH = 150
local TOOLTIP_TITLE_GAP = 5
local PIP_BLOCK_GAP = 3
local LABEL_COLOR = { r = 1.0, g = 1.0, b = 0.8 }

-- Labels vanilla food tooltips can emit; the shared label column must clear all of them so
-- NMS pips line up with vanilla values.
local VANILLA_LABEL_KEYS = {
    "Tooltip_item_Weight", "Tooltip_item_StackWeight", "Tooltip_food_Hunger", "Tooltip_food_Thirst",
    "Tooltip_food_Endurance", "Tooltip_food_Stress", "Tooltip_food_Boredom", "Tooltip_food_Unhappiness",
    "Tooltip_food_Calories", "Tooltip_food_Carbs", "Tooltip_food_Prots", "Tooltip_food_Fat",
    "Tooltip_item_Fatigue", "Tooltip_item_Discomfort", "Tooltip_food_MinutesToCook",
}
local PIP_COLOR_KEYS = { satiety = "stomach", energy = "energy", protein = "protein" }

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

local function labelColumnWidth(font, rows)
    local width = TOOLTIP_MIN_LABEL_WIDTH
    for _, key in ipairs(VANILLA_LABEL_KEYS) do
        local text = getText(key)
        if text and text ~= key then
            width = math.max(width, Draw.textWidth(font, text .. ":"))
        end
    end
    for _, row in ipairs(rows) do
        width = math.max(width, Draw.textWidth(font, row.label .. ":"))
    end
    return width
end

-- NMS rows sit under the vanilla layout, drawn directly so each row can carry a pip strip.
local function renderPipBlock(tooltip, rows, padLeft, top, labelColumn)
    local font = safeCall(tooltip, "getFont")
    local lineSpacing = tonumber(safeCall(tooltip, "getLineSpacing")) or 14
    local measureOnly = safeCall(tooltip, "isMeasureOnly") == true
    local padX = math.max(Draw.textWidth(font, "W"), 8)
    local valueX = padLeft + labelColumn + padX
    local size, gap = Draw.pipGeometry(lineSpacing)
    local count = TooltipLogic.PIP_COUNT
    local stripWidth = Draw.pipStripWidth(count, size, gap)
    local sink = (not measureOnly) and Draw.tooltipSink(tooltip) or nil
    local detailed = UIHelpers.isDetailed(getPlayer and getPlayer() or nil)
    local right = valueX + stripWidth
    local y = top + PIP_BLOCK_GAP

    for _, row in ipairs(rows) do
        local color = Draw.C[PIP_COLOR_KEYS[row.key] or "text"]
        local pips = row.pips
        if not detailed and not row.debugText then
            -- An untrained eye judges in whole portions: round, keep a trace visible, never show overflow.
            pips = math.min(count, math.max(pips >= 0.25 and 1 or 0, math.floor(pips + 0.5)))
        end
        local extra = pips > count and "+" or nil
        if row.debugText then
            extra = (extra or "") .. " " .. row.debugText
        end
        if sink then
            tooltip:DrawText(font, row.label .. ":", padLeft, y, LABEL_COLOR.r, LABEL_COLOR.g, LABEL_COLOR.b, 1)
            Draw.pips(sink, valueX, y + math.floor((lineSpacing - size) / 2), count, pips, size, gap, color)
            if extra then
                tooltip:DrawText(font, extra, valueX + stripWidth + 3, y, color.r, color.g, color.b, 1)
            end
        end
        if extra then
            right = math.max(right, valueX + stripWidth + 3 + Draw.textWidth(font, extra))
        end
        y = y + lineSpacing
    end
    return y, right
end

local function renderCombinedTooltip(tooltip, item)
    local layout = safeCall(tooltip, "beginLayout")
    if not layout then
        return false
    end

    local rows = TooltipLogic.buildPipRows(item)
    local labelColumn = labelColumnWidth(safeCall(tooltip, "getFont"), rows)
    safeCall(layout, "setMinLabelWidth", labelColumn)
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

    local padLeft, contentY, padBottom = tooltipLayoutGeometry(tooltip, item)
    local height = tonumber(safeCall(layout, "render", padLeft, contentY, tooltip)) or contentY
    safeCall(tooltip, "endLayout", layout)

    local right = 0
    if #rows > 0 then
        height, right = renderPipBlock(tooltip, rows, padLeft, height, labelColumn)
    end
    safeCall(tooltip, "setHeight", math.floor(height + padBottom))

    local width = tonumber(safeCall(tooltip, "getWidth")) or 0
    local needed = math.max(TOOLTIP_MIN_WIDTH, right + padLeft)
    if width < needed then
        safeCall(tooltip, "setWidth", needed)
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

-- One persistent DoTooltip wrapper per item class. It only takes over while a
-- patched owner has published a matching item/tooltip pair, so other mods
-- that wrap DoTooltip never capture or restore a transient NMS closure.
TooltipOverlay._wrappedMethods = TooltipOverlay._wrappedMethods or {}

local function ensureDoTooltipWrapped(item)
    local methods = getItemMethods(item)
    if not methods or TooltipOverlay._wrappedMethods[methods] then
        return methods ~= nil
    end
    local original = methods.DoTooltip
    if type(original) ~= "function" then
        return false
    end
    TooltipOverlay._wrappedMethods[methods] = original
    methods.DoTooltip = function(target, targetTooltip, ...)
        local active = TooltipOverlay._active
        if active and active.item == target and active.tooltip == targetTooltip then
            return renderCombinedTooltip(targetTooltip, target)
        end
        return original(target, targetTooltip, ...)
    end
    return true
end

local function withFoodTooltipExtension(item, tooltip, delegateToController, callback)
    if not item or not tooltip or not TooltipLogic.isFoodItem(item) then
        return callback()
    end
    if delegateToController and providerOwnsFoodTooltips() then
        return callback()
    end
    if not ensureDoTooltipWrapped(item) then
        return callback()
    end

    local previous = TooltipOverlay._active
    TooltipOverlay._active = { item = item, tooltip = tooltip }
    local ok, result = pcall(callback)
    TooltipOverlay._active = previous
    if not ok then
        error(result, 0)
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
