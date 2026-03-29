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

local function drawTooltipTexture(tooltip, texture, x, y, width, height)
    if not tooltip or not texture then
        return 0
    end

    safeCall(tooltip, "DrawTextureScaledAspect", texture, x, y, width, height, 1.0, 1.0, 1.0, 1.0)

    local texWidth = tonumber(safeCall(texture, "getWidth")) or 0
    local texHeight = tonumber(safeCall(texture, "getHeight")) or 0
    local texWidthOrig = tonumber(safeCall(texture, "getWidthOrig")) or texWidth
    local texHeightOrig = tonumber(safeCall(texture, "getHeightOrig")) or texHeight
    if texWidth > 0 and texHeight > 0 and texWidthOrig > 0 and texHeightOrig > 0 then
        local ratio = math.min(width / texWidthOrig, height / texHeightOrig)
        return math.ceil(texWidth * ratio)
    end

    return width
end

local function eachListEntry(list, callback)
    if type(callback) ~= "function" or not list then
        return
    end

    local size = tonumber(safeCall(list, "size")) or 0
    if size > 0 then
        for index = 0, size - 1 do
            callback(safeCall(list, "get", index), index)
        end
        return
    end

    if type(list) == "table" then
        for index, entry in ipairs(list) do
            callback(entry, index - 1)
        end
    end
end

local function getLayoutItemsSnapshot(layout)
    if not layout or not layout.items then
        return {}
    end

    local snapshot = {}
    eachListEntry(layout.items, function(layoutItem)
        snapshot[#snapshot + 1] = layoutItem
    end)
    return snapshot
end

local function removeLayoutItem(layout, targetItem)
    if not layout or not targetItem then
        return false
    end

    local sizeBefore = nil
    if layout.items then
        sizeBefore = tonumber(safeCall(layout.items, "size"))
    end

    if type(layout.removeItem) == "function" then
        safeCall(layout, "removeItem", targetItem)
        local sizeAfter = layout.items and tonumber(safeCall(layout.items, "size")) or nil
        if sizeBefore ~= nil and sizeAfter ~= nil and sizeAfter < sizeBefore then
            return true
        end
    end

    if layout.items then
        safeCall(layout.items, "remove", targetItem)
        local sizeAfterByObject = tonumber(safeCall(layout.items, "size"))
        if sizeBefore ~= nil and sizeAfterByObject ~= nil and sizeAfterByObject < sizeBefore then
            return true
        end

        local size = tonumber(safeCall(layout.items, "size")) or 0
        for index = size - 1, 0, -1 do
            local entry = safeCall(layout.items, "get", index)
            if entry == targetItem then
                safeCall(layout.items, "remove", index)
                local sizeAfter = tonumber(safeCall(layout.items, "size")) or size
                if sizeAfter < size then
                    return true
                end
            end
        end
    end

    if type(layout.items) == "table" then
        for index = #layout.items, 1, -1 do
            if layout.items[index] == targetItem then
                table.remove(layout.items, index)
                return true
            end
        end
    end

    return false
end

local function normalizeTooltipText(value)
    local text = tostring(value or "")
    text = string.lower(text)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function withHiddenVanillaHunger(item, callback)
    if not item or type(callback) ~= "function" then
        return false, nil
    end

    local hideTag = ItemTag and ItemTag.HIDE_HUNGER_CHANGE or nil
    local tags = hideTag and safeCall(item, "getTags") or nil
    local addedTag = false

    if hideTag and tags then
        local alreadyHidden = safeCall(item, "hasTag", hideTag) == true
        if not alreadyHidden then
            safeCall(tags, "add", hideTag)
            addedTag = safeCall(item, "hasTag", hideTag) == true
        end
    end

    local ok, result = pcall(callback)

    if addedTag and tags and hideTag then
        safeCall(tags, "remove", hideTag)
    end

    return ok, result
end

local function removeVanillaHungerRow(layout, item)
    if not layout or not layout.items or not item then
        return
    end

    local hungerTokens = {
        normalizeTooltipText(getText and getText("Tooltip_food_Hunger") or "Hunger"),
        "hunger",
    }
    local removedAny = false
    local size = tonumber(safeCall(layout.items, "size")) or 0
    for index = size - 1, 0, -1 do
        local layoutItem = safeCall(layout.items, "get", index)
        if layoutItem then
            local label = normalizeTooltipText(layoutItem.label)
            local matchesLabel = false
            for _, token in ipairs(hungerTokens) do
                if token ~= "" and string.find(label, token, 1, true) then
                    matchesLabel = true
                    break
                end
            end

            if matchesLabel then
                local before = tonumber(safeCall(layout.items, "size")) or 0
                safeCall(layout.items, "remove", index)
                local after = tonumber(safeCall(layout.items, "size")) or before
                if after < before then
                    removedAny = true
                    break
                end
            end
        end
    end

    return removedAny
end

local function getTooltipValueColumnX(tooltip, layout, labelColumnX)
    local padLeft = tonumber(labelColumnX)
    if padLeft == nil then
        padLeft = tonumber(tooltip and tooltip.padLeft) or 0
    end
    local font = safeCall(tooltip, "getFont")
    local textManager = _G.TextManager and TextManager.instance or nil
    local wWidth = tonumber(textManager and font and safeCall(textManager, "MeasureStringX", font, "W") or nil) or 0
    local padX = math.max(wWidth, 8)
    local maxLabelWidth = tonumber(layout and layout.minLabelWidth) or 80

    if layout and layout.items and textManager and font then
        eachListEntry(layout.items, function(layoutItem)
            if not layoutItem or layoutItem.hasValue ~= true then
                return
            end

            local labelText = layoutItem.label
            if labelText == nil then
                return
            end

            local measured = tonumber(safeCall(textManager, "MeasureStringX", font, tostring(labelText))) or 0
            if measured > maxLabelWidth then
                maxLabelWidth = measured
            end
        end)
    end

    return padLeft + maxLabelWidth + padX
end

local function getEntryItemId(entry)
    if entry == nil then
        return nil
    end

    if type(entry) == "string" then
        local text = tostring(entry)
        if text ~= "" then
            return text
        end
        return nil
    end

    local fullType = safeCall(entry, "getFullType")
    if fullType and tostring(fullType) ~= "" then
        return tostring(fullType)
    end

    local moduleName = safeCall(entry, "getModule")
    local typeName = safeCall(entry, "getType")
    if moduleName and moduleName ~= "" and typeName and typeName ~= "" then
        return tostring(moduleName) .. "." .. tostring(typeName)
    end

    local fallback = tostring(entry)
    if fallback ~= "" and fallback ~= "nil" and string.find(fallback, "%.") then
        return fallback
    end

    return nil
end

local function tryCreateInventoryItem(itemId)
    if itemId == nil or itemId == "" then
        return nil
    end
    if not InventoryItemFactory or type(InventoryItemFactory.CreateItem) ~= "function" then
        return nil
    end

    local ok, created = pcall(InventoryItemFactory.CreateItem, itemId)
    if not ok then
        return nil
    end
    return created
end

local function getScriptItemTexture(itemId)
    if itemId == nil or itemId == "" then
        return nil
    end

    local scriptManager = nil
    if type(getScriptManager) == "function" then
        scriptManager = getScriptManager()
    end
    if not scriptManager and ScriptManager and ScriptManager.instance then
        scriptManager = ScriptManager.instance
    end
    if not scriptManager then
        return nil
    end

    local scriptItem = safeCall(scriptManager, "getItem", itemId)
    if not scriptItem then
        scriptItem = safeCall(scriptManager, "FindItem", itemId, true)
    end
    if not scriptItem then
        return nil
    end

    local texture = safeCall(scriptItem, "getNormalTexture") or scriptItem.normalTexture
    if texture then
        return texture
    end

    local iconName = safeCall(scriptItem, "getIcon")
    if iconName == nil or tostring(iconName) == "" or type(getTexture) ~= "function" then
        return nil
    end

    local iconPath = tostring(iconName)
    local iconTexture = getTexture(iconPath)
    if iconTexture then
        return iconTexture
    end

    if not string.find(iconPath, "^Item_") then
        iconPath = "Item_" .. iconPath
    end

    iconTexture = getTexture(iconPath)
    if iconTexture then
        return iconTexture
    end

    return nil
end

local function getInventoryItemTexture(item)
    if not item then
        return nil
    end

    local texture = safeCall(item, "getTex")
    if texture then
        return texture
    end

    texture = safeCall(item, "getTexture")
    if texture then
        return texture
    end

    texture = safeCall(item, "getIcon")
    if texture then
        return texture
    end

    local scriptItem = safeCall(item, "getScriptItem")
    if scriptItem then
        texture = safeCall(scriptItem, "getNormalTexture") or scriptItem.normalTexture
        if texture then
            return texture
        end
    end

    return nil
end

local function applyIngredientCookState(baseItem, ingredientItem)
    if not ingredientItem then
        return
    end

    local ingredientCookable = safeCall(ingredientItem, "isCookable") == true
    if not ingredientCookable then
        return
    end

    local baseCookable = safeCall(baseItem, "isCookable") == true
    local baseCooked = safeCall(baseItem, "isCooked") == true
    if (not baseCookable and ingredientCookable) or (baseCooked and ingredientCookable) then
        safeCall(ingredientItem, "setCooked", true)
    end
end

local function resolveTooltipIconTexture(baseItem, entry)
    if entry == nil then
        return nil
    end

    local texture = getInventoryItemTexture(entry)
    if texture then
        return texture
    end

    local itemId = getEntryItemId(entry)
    local iconItem = tryCreateInventoryItem(itemId)
    if iconItem then
        applyIngredientCookState(baseItem, iconItem)
        texture = getInventoryItemTexture(iconItem)
        if texture then
            return texture
        end
    end

    return getScriptItemTexture(itemId)
end

local function appendIconStripRow(baseItem, tooltip, label, iconEntries, top, lineSpacing, labelColumnX, valueColumnX)
    if not tooltip or type(iconEntries) ~= "table" or #iconEntries <= 0 then
        return top
    end

    local font = safeCall(tooltip, "getFont")
    local padLeft = tonumber(labelColumnX)
    if padLeft == nil then
        padLeft = tonumber(tooltip and tooltip.padLeft) or 0
    end
    local y = top
    safeCall(tooltip, "DrawText", font, label, padLeft, y, 1.0, 1.0, 0.8, 1.0)
    safeCall(tooltip, "adjustWidth", padLeft, label)

    local iconX = valueColumnX or getTooltipValueColumnX(tooltip, nil, padLeft)

    for _, entry in ipairs(iconEntries) do
        local texture = resolveTooltipIconTexture(baseItem, entry)
        local drawn = drawTooltipTexture(tooltip, texture, iconX, y, lineSpacing, lineSpacing)
        if drawn > 0 then
            iconX = iconX + drawn + 2
        end
    end

    safeCall(tooltip, "adjustWidth", iconX, "")
    return y + lineSpacing + 5
end

local function collectIngredientRows(item)
    local rows = {}

    local extraEntries = {}
    eachListEntry(safeCall(item, "getExtraItems"), function(entry)
        if entry ~= nil then
            extraEntries[#extraEntries + 1] = entry
        end
    end)
    if #extraEntries > 0 then
        rows[#rows + 1] = {
            label = getText("Tooltip_item_Contains"),
            entries = extraEntries,
        }
    end

    local spiceEntries = {}
    eachListEntry(safeCall(item, "getSpices"), function(entry)
        if entry ~= nil then
            spiceEntries[#spiceEntries + 1] = entry
        end
    end)
    if #spiceEntries > 0 then
        rows[#rows + 1] = {
            label = getText("Tooltip_item_Spices"),
            entries = spiceEntries,
        }
    end

    return rows
end

local function getIngredientRowsHeight(rows, lineSpacing)
    if type(rows) ~= "table" or #rows <= 0 then
        return 0
    end
    return #rows * (lineSpacing + 5)
end

local function appendIngredientRows(item, tooltip, ingredientRows, top, lineSpacing, labelColumnX, valueColumnX)
    local y = top
    if type(ingredientRows) ~= "table" or #ingredientRows <= 0 then
        return y
    end

    for _, row in ipairs(ingredientRows) do
        local entries = type(row) == "table" and row.entries or nil
        if type(entries) == "table" and #entries > 0 then
            y = appendIconStripRow(item, tooltip, row.label, entries, y, lineSpacing, labelColumnX, valueColumnX)
        end
    end

    return y
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
        local layoutPadLeft = tonumber(tooltip and tooltip.padLeft) or padLeft
        local lineSpacing = tonumber(safeCall(tooltip, "getLineSpacing")) or 14
        local ingredientRows = collectIngredientRows(item)
        local ingredientRowsHeight = getIngredientRowsHeight(ingredientRows, lineSpacing)
        local top = padTop
        local font = safeCall(tooltip, "getFont")
        local displayName = getItemDisplayName(item, tooltip)
        if displayName ~= "" then
            safeCall(tooltip, "DrawText", font, displayName, layoutPadLeft, top, 1.0, 1.0, 0.8, 1.0)
            safeCall(tooltip, "adjustWidth", layoutPadLeft, displayName)
        end
        top = top + lineSpacing + 5
        local layoutTop = top + ingredientRowsHeight

        appendBaseFoodRows(layout, item, tooltip)

        local tooltipOk, tooltipErr = withHiddenVanillaHunger(item, function()
            return originalDoTooltip(item, tooltip, layout)
        end)
        if not tooltipOk then
            error(tooltipErr)
        end
        removeVanillaHungerRow(layout, item)

        local labelColumnX = layoutPadLeft
        local valueColumnX = getTooltipValueColumnX(tooltip, layout, labelColumnX)
        top = appendIngredientRows(item, tooltip, ingredientRows, top, lineSpacing, labelColumnX, valueColumnX)

        local height = tonumber(safeCall(layout, "render", layoutPadLeft, layoutTop, tooltip)) or layoutTop
        safeCall(tooltip, "endLayout", layout)
        local width = tonumber(safeCall(tooltip, "getWidth")) or 0
        if width < 150 then
            width = 150
        end

        safeCall(tooltip, "setHeight", math.floor(height + padBottom))
        safeCall(tooltip, "setWidth", math.floor(width))
    end)

    if not ok then
        logOnce("tooltip_render_layout_failed", string.format("[TOOLTIP] Tooltip layout render failed: %s", tostring(err)))
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
                local ok, result = withHiddenVanillaHunger(overriddenItem, function()
                    return originalDoTooltip(overriddenItem, tooltip)
                end)
                if not ok then
                    error(result)
                end
                return result
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
                local ok, result = withHiddenVanillaHunger(overriddenItem, function()
                    return originalDoTooltip(overriddenItem, tooltipUi)
                end)
                if not ok then
                    error(result)
                end
                return result
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
