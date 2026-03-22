NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_TooltipLogic"

local TooltipOverlay = NutritionMakesSense.TooltipOverlay or {}
NutritionMakesSense.TooltipOverlay = TooltipOverlay

local CoreUtils = NutritionMakesSense.CoreUtils or {}
local TooltipLogic = NutritionMakesSense.TooltipLogic or {}
local loggedMessages = {}
local safeCall = CoreUtils.safeCall

local function logOnce(key, message)
    if loggedMessages[key] then
        return
    end
    loggedMessages[key] = true
    if NutritionMakesSense.log then
        NutritionMakesSense.log(message)
    end
end

local function addLayoutTextRow(layout, label, value)
    local layoutItem = safeCall(layout, "addItem")
    if not layoutItem then
        return nil
    end

    safeCall(layoutItem, "setLabel", label or "", 1.0, 1.0, 0.8, 1.0)
    if value ~= nil then
        safeCall(layoutItem, "setValue", tostring(value), 1.0, 1.0, 1.0, 1.0)
    end
    return layoutItem
end

local function addLayoutProgressRow(layout, label, fraction, r, g, b)
    local layoutItem = safeCall(layout, "addItem")
    if not layoutItem then
        return nil
    end

    safeCall(layoutItem, "setLabel", label or "", 1.0, 1.0, 0.8, 1.0)
    safeCall(layoutItem, "setProgress", fraction or 0, r or 1, g or 1, b or 1, 1.0)
    return layoutItem
end

local function getItemDisplayName(item, tooltip)
    local character = tooltip and safeCall(tooltip, "getCharacter") or nil
    local name = nil
    if character then
        name = safeCall(item, "getName", character)
    end
    if not name then
        name = safeCall(item, "getName")
    end
    return tostring(name or "")
end

local function getCleanWeightString(item, value)
    local cleaned = safeCall(item, "getCleanString", value)
    if cleaned ~= nil then
        return tostring(cleaned)
    end
    local numeric = tonumber(value) or 0
    numeric = math.floor((numeric + 0.005) * 100) / 100
    return tostring(numeric)
end

local function appendBaseFoodRows(layout, item, tooltip)
    if SandboxOptions and SandboxOptions.instance and SandboxOptions.instance.isUnstableScriptNameSpam and SandboxOptions.instance:isUnstableScriptNameSpam() then
        local reportItem = safeCall(layout, "addItem")
        if reportItem then
            safeCall(reportItem, "setLabel", getText("Item Report") .. ":", 1.0, 0.4, 0.7, 1.0)
            safeCall(reportItem, "setValue", tostring(safeCall(item, "getFullType") or ""), 1.0, 1.0, 0.8, 1.0)
        end
    end

    local weight = tonumber(safeCall(item, "getUnequippedWeight")) or tonumber(safeCall(item, "getWeight")) or 0
    if weight > 0 and weight < 0.01 then
        weight = 0.01
    end
    addLayoutTextRow(layout, getText("Tooltip_item_Weight") .. ":", getCleanWeightString(item, weight))

    local stackWeight = tonumber(tooltip and safeCall(tooltip, "getWeightOfStack")) or 0
    if stackWeight > 0 then
        if stackWeight < 0.01 then
            stackWeight = 0.01
        end
        local layoutItem = safeCall(layout, "addItem")
        if layoutItem then
            safeCall(layoutItem, "setLabel", getText("Tooltip_item_StackWeight") .. ":", 1.0, 1.0, 0.8, 1.0)
            safeCall(layoutItem, "setValueRightNoPlus", stackWeight)
        end
    end

    TooltipLogic.appendDescriptorRowsToLayoutForViewer(layout, item, safeCall(tooltip, "getCharacter"))

    if safeCall(item, "isTainted") == true and SandboxOptions and SandboxOptions.instance and SandboxOptions.instance.enableTaintedWaterText and SandboxOptions.instance.enableTaintedWaterText:getValue() then
        local taintedKey = safeCall(item, "hasMetal") and "Tooltip_item_TaintedWater_Plastic" or "Tooltip_item_TaintedWater"
        local taintedItem = safeCall(layout, "addItem")
        if taintedItem then
            safeCall(taintedItem, "setLabel", getText(taintedKey), 1.0, 0.5, 0.5, 1.0)
        end
    end

    local fatigueChange = tonumber(safeCall(item, "getFatigueChange")) or 0
    if fatigueChange ~= 0 then
        local good = getCore():getGoodHighlitedColor()
        local bad = getCore():getBadHighlitedColor()
        if fatigueChange < 0 then
            addLayoutProgressRow(layout, getText("Tooltip_item_Fatigue") .. ": ", -fatigueChange, good:getR(), good:getG(), good:getB())
        else
            addLayoutProgressRow(layout, getText("Tooltip_item_Fatigue") .. ": ", fatigueChange, bad:getR(), bad:getG(), bad:getB())
        end
    end
end

local function renderTooltipLayoutForItem(item, tooltip, originalDoTooltip)
    if not item or not tooltip or type(originalDoTooltip) ~= "function" then
        return false
    end

    local layout = safeCall(tooltip, "beginLayout")
    if not layout then
        return false
    end

    local ok, err = pcall(function()
        safeCall(tooltip, "render")
        safeCall(layout, "setMinLabelWidth", 80)
        safeCall(layout, "setMinValueWidth", 80)

        local padLeft, _, padTop, padBottom = TooltipLogic.getTooltipPadding(tooltip)
        local lineSpacing = tonumber(safeCall(tooltip, "getLineSpacing")) or 14
        local top = padTop
        local font = safeCall(tooltip, "getFont")
        local displayName = getItemDisplayName(item, tooltip)
        if displayName ~= "" then
            safeCall(tooltip, "DrawText", font, displayName, padLeft, top, 1.0, 1.0, 0.8, 1.0)
            safeCall(tooltip, "adjustWidth", padLeft, displayName)
        end
        top = top + lineSpacing + 5

        appendBaseFoodRows(layout, item, tooltip)

        local originalHungChange = safeCall(item, "getHungChange")
        local suppressible = originalHungChange ~= nil and type(item.setHungChange) == "function"
        if suppressible then
            item:setHungChange(0)
        end
        originalDoTooltip(item, tooltip, layout)
        if suppressible then
            item:setHungChange(originalHungChange)
        end

        local height = tonumber(safeCall(layout, "render", padLeft, top, tooltip)) or top
        safeCall(tooltip, "endLayout", layout)

        local width = tonumber(safeCall(tooltip, "getWidth")) or 0
        if width < 150 then
            width = 150
        end

        safeCall(tooltip, "setHeight", math.floor(height + padBottom))
        safeCall(tooltip, "setWidth", math.floor(width))
    end)

    if not ok then
        logOnce("tooltip_render_layout_failed", string.format("[TOOLTIP] Embedded layout render failed: %s", tostring(err)))
        pcall(function()
            safeCall(tooltip, "endLayout", layout)
        end)
        return false
    end

    return true
end

local function getItemIndexTable(item)
    local itemMt = nil
    local mtOk, mtValue = pcall(getmetatable, item)
    if mtOk and type(mtValue) == "table" then
        itemMt = mtValue
    end
    return itemMt and type(itemMt.__index) == "table" and itemMt.__index or nil
end

local function patchInventoryTooltip()
    if not ISToolTipInv or TooltipOverlay._inventoryTooltipPatched then
        return
    end

    TooltipOverlay._inventoryTooltipPatched = true
    local originalRender = ISToolTipInv.render
    ISToolTipInv.render = function(self)
        local item = self and self.item or nil
        if not item or not TooltipLogic.isFoodItem(item) then
            return originalRender(self)
        end

        local itemIndex = getItemIndexTable(item)
        local originalDoTooltip = itemIndex and itemIndex.DoTooltip or nil
        if type(originalDoTooltip) ~= "function" then
            logOnce("tooltip_missing_doTooltip", "[TOOLTIP] Item metatable DoTooltip unavailable; using vanilla render.")
            return originalRender(self)
        end

        itemIndex.DoTooltip = function(overriddenItem, tooltip)
            if not renderTooltipLayoutForItem(overriddenItem, tooltip, originalDoTooltip) then
                return originalDoTooltip(overriddenItem, tooltip)
            end
        end

        local ok, result = pcall(originalRender, self)
        itemIndex.DoTooltip = originalDoTooltip
        if not ok then
            error(result)
        end
        return result
    end
end

local function patchItemSlotTooltip()
    if not ISItemSlot or TooltipOverlay._itemSlotTooltipPatched then
        return
    end

    TooltipOverlay._itemSlotTooltipPatched = true
    local originalDrawTooltip = ISItemSlot.drawTooltip

    ISItemSlot.drawTooltip = function(itemSlot, tooltip)
        local item = itemSlot and (itemSlot.resource or itemSlot.storedItem) or nil
        if not item or not TooltipLogic.isFoodItem(item) then
            if originalDrawTooltip then
                return originalDrawTooltip(itemSlot, tooltip)
            end
            return
        end

        local itemIndex = getItemIndexTable(item)
        local originalDoTooltip = itemIndex and itemIndex.DoTooltip or nil
        if type(originalDoTooltip) ~= "function" then
            logOnce("tooltip_slot_missing_doTooltip", "[TOOLTIP] ISItemSlot item metatable DoTooltip unavailable; using vanilla slot tooltip.")
            if originalDrawTooltip then
                return originalDrawTooltip(itemSlot, tooltip)
            end
            return
        end

        itemIndex.DoTooltip = function(overriddenItem, tooltipUi)
            if not renderTooltipLayoutForItem(overriddenItem, tooltipUi, originalDoTooltip) then
                return originalDoTooltip(overriddenItem, tooltipUi)
            end
        end

        local ok, result = pcall(originalDrawTooltip, itemSlot, tooltip)
        itemIndex.DoTooltip = originalDoTooltip
        if not ok then
            error(result)
        end
        return result
    end
end

function TooltipOverlay.install()
    if TooltipOverlay._installed then
        return TooltipOverlay
    end
    TooltipOverlay._installed = true

    patchInventoryTooltip()
    patchItemSlotTooltip()

    if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
        Events.OnGameBoot.Add(function()
            patchInventoryTooltip()
            patchItemSlotTooltip()
        end)
    end

    return TooltipOverlay
end

return TooltipOverlay
