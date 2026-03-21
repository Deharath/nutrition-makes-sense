NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_ItemAuthority"
require "NutritionMakesSense_Metabolism"

local TooltipLogic = NutritionMakesSense.TooltipLogic or {}
NutritionMakesSense.TooltipLogic = TooltipLogic
local Metabolism = NutritionMakesSense.Metabolism

local TT_LABEL_DEFAULT = { 1.0, 1.0, 0.8, 1.0 }
local TT_VALUE_DEFAULT = { 1.0, 1.0, 1.0, 1.0 }

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

local function clamp(value, minValue, maxValue)
    local numeric = tonumber(value) or minValue
    if numeric < minValue then
        return minValue
    end
    if numeric > maxValue then
        return maxValue
    end
    return numeric
end

local function getTooltipPadding(tooltip)
    local padLeft = tonumber(tooltip and tooltip.padLeft)
    local padRight = tonumber(tooltip and tooltip.padRight)
    local padTop = tonumber(tooltip and tooltip.padTop)
    local padBottom = tonumber(tooltip and tooltip.padBottom)
    if padLeft and padRight and padTop and padBottom then
        return padLeft, padRight, padTop, padBottom
    end

    local font = tooltip and safeCall(tooltip, "getFont") or nil
    local textManager = _G.TextManager and TextManager.instance or nil
    local charWidth = tonumber(textManager and font and safeCall(textManager, "MeasureStringX", font, "1") or nil) or 5
    if charWidth < 1 then
        charWidth = 5
    end
    charWidth = charWidth + 2
    local verticalPad = math.floor(charWidth / 2)
    if verticalPad < 1 then
        verticalPad = 2
    end
    return charWidth + 1, charWidth, verticalPad, verticalPad
end

local function addLayoutRow(layout, payload)
    local layoutItem = safeCall(layout, "addItem")
    if not layoutItem then
        return nil
    end

    local labelColor = payload.labelColor or TT_LABEL_DEFAULT
    safeCall(layoutItem, "setLabel", payload.label or "", labelColor[1], labelColor[2], labelColor[3], labelColor[4])

    if payload.value ~= nil then
        local valueColor = payload.valueColor or TT_VALUE_DEFAULT
        safeCall(layoutItem, "setValue", tostring(payload.value), valueColor[1], valueColor[2], valueColor[3], valueColor[4])
    end

    return layoutItem
end

local function getLayoutItems(layout)
    if not layout then
        return nil
    end

    local items = layout.items
    if items ~= nil then
        return items
    end
    if type(layout) == "table" then
        return layout["items"]
    end
    return nil
end

local function getListSize(list)
    if not list then
        return 0
    end

    local size = safeCall(list, "size")
    if size ~= nil then
        return tonumber(size) or 0
    end

    return tonumber(#list) or 0
end

local function getListEntry(list, index)
    if not list then
        return nil
    end

    local entry = safeCall(list, "get", index)
    if entry ~= nil then
        return entry
    end

    return list[index + 1]
end

local function removeListEntry(list, index)
    if not list then
        return nil
    end

    local removed = safeCall(list, "remove", index)
    if removed ~= nil then
        return removed
    end

    if type(list) == "table" then
        return table.remove(list, index + 1)
    end

    return nil
end

local function insertListEntry(list, index, entry)
    if not list or entry == nil then
        return false
    end

    local inserted = safeCall(list, "add", index, entry)
    if inserted ~= nil then
        return true
    end

    if type(list) == "table" then
        table.insert(list, index + 1, entry)
        return true
    end

    return false
end

local function rawLookup(tableLike, key)
    if not tableLike then
        return nil
    end
    if type(tableLike.rawget) == "function" then
        local ok, value = pcall(tableLike.rawget, tableLike, key)
        if ok then
            return value
        end
    end
    if type(tableLike) == "table" then
        return tableLike[key]
    end
    return nil
end

local function getModData(item)
    if not item then
        return nil
    end
    return safeCall(item, "getModData") or item.modData
end

local function getLabelPrefix(textKey)
    return tostring(getText(textKey) or "") .. ":"
end

local function labelStartsWith(layoutItem, prefix)
    local label = tostring(layoutItem and layoutItem.label or "")
    return prefix ~= "" and label:sub(1, #prefix) == prefix
end

local LAYOUT_ITEM_FIELDS = {
    "label",
    "r0",
    "g0",
    "b0",
    "a0",
    "hasValue",
    "couldHaveValue",
    "value",
    "rightJustify",
    "r1",
    "g1",
    "b1",
    "a1",
    "progressFraction",
    "labelWidth",
    "valueWidth",
    "valueWidthRight",
    "progressWidth",
    "height",
}

local function snapshotLayoutItem(layoutItem)
    if not layoutItem then
        return nil
    end

    local snapshot = {}
    for _, fieldName in ipairs(LAYOUT_ITEM_FIELDS) do
        snapshot[fieldName] = layoutItem[fieldName]
    end
    return snapshot
end

local function applyLayoutItemSnapshot(layoutItem, snapshot)
    if not layoutItem or not snapshot then
        return false
    end

    for _, fieldName in ipairs(LAYOUT_ITEM_FIELDS) do
        layoutItem[fieldName] = snapshot[fieldName]
    end
    return true
end

local function bubbleLayoutItemToIndex(items, sourceIndex, targetIndex)
    if not items or sourceIndex == nil or targetIndex == nil or sourceIndex <= targetIndex then
        return false
    end

    local movingItem = getListEntry(items, sourceIndex)
    if not movingItem then
        return false
    end

    local movingSnapshot = snapshotLayoutItem(movingItem)
    if not movingSnapshot then
        return false
    end

    for index = sourceIndex, targetIndex + 1, -1 do
        local current = getListEntry(items, index)
        local previous = getListEntry(items, index - 1)
        if current and previous then
            applyLayoutItemSnapshot(current, snapshotLayoutItem(previous))
        end
    end

    local targetItem = getListEntry(items, targetIndex)
    if not targetItem then
        return false
    end

    applyLayoutItemSnapshot(targetItem, movingSnapshot)
    return true
end

local function hasTrait(character, traitName, traitEnum)
    if not character then
        return false
    end
    if traitEnum and _G.CharacterTrait and CharacterTrait[traitEnum] ~= nil then
        return safeCall(character, "hasTrait", CharacterTrait[traitEnum]) == true
    end
    return safeCall(character, "hasTrait", traitName) == true
end

local function normalizeHungerValue(rawHunger)
    local hunger = math.abs(tonumber(rawHunger) or 0)
    if hunger <= 1 then
        return hunger * 100
    end
    return hunger
end

local function normalizeAuthorityHungerValue(rawHunger)
    return math.abs(tonumber(rawHunger) or 0)
end

local function readFoodValues(item)
    local authorityValues = NutritionMakesSense.ItemAuthority
        and NutritionMakesSense.ItemAuthority.getDisplayValues
        and NutritionMakesSense.ItemAuthority.getDisplayValues(item)
    if authorityValues then
        return {
            hunger = normalizeAuthorityHungerValue(authorityValues.hunger),
            kcal = math.max(0, tonumber(authorityValues.kcal) or 0),
            carbs = math.max(0, tonumber(authorityValues.carbs) or 0),
            fats = math.max(0, tonumber(authorityValues.fats) or 0),
            proteins = math.max(0, tonumber(authorityValues.proteins) or 0),
        }
    end

    local hunger = safeCall(item, "getHungerChange")
    if hunger == nil then
        hunger = safeCall(item, "getHungChange")
    end

    return {
        hunger = normalizeHungerValue(hunger or item.hunger),
        kcal = math.max(0, tonumber(safeCall(item, "getCalories") or item.kcal) or 0),
        carbs = math.max(0, tonumber(safeCall(item, "getCarbohydrates") or item.carbs) or 0),
        fats = math.max(0, tonumber(safeCall(item, "getLipids") or item.fats) or 0),
        proteins = math.max(0, tonumber(safeCall(item, "getProteins") or item.proteins) or 0),
    }
end

local function resolveViewer(viewer)
    local character = viewer
    if type(viewer) == "table" and viewer.character ~= nil then
        character = viewer.character
    end

    local illiterate = false
    local nutritionist = false
    local tooDark = false

    if type(viewer) == "table" then
        if viewer.illiterate ~= nil then
            illiterate = viewer.illiterate == true
        end
        if viewer.nutritionist ~= nil then
            nutritionist = viewer.nutritionist == true
        end
        if viewer.tooDark ~= nil then
            tooDark = viewer.tooDark == true
        end
    end

    illiterate = illiterate or hasTrait(character, "Illiterate", "ILLITERATE")
    nutritionist = nutritionist
        or hasTrait(character, "Nutritionist", "NUTRITIONIST")
        or hasTrait(character, "Nutritionist2", "NUTRITIONIST2")
    tooDark = tooDark or (safeCall(character, "tooDarkToRead") == true)

    return {
        character = character,
        hasCharacter = character ~= nil,
        illiterate = illiterate,
        nutritionist = nutritionist,
        tooDark = tooDark,
    }
end

local function isDebugTooltipMode()
    local clientOptions = NutritionMakesSense and NutritionMakesSense.ClientOptions or nil
    if clientOptions and type(clientOptions.getShowDebugFoodTooltips) == "function" then
        local override = clientOptions.getShowDebugFoodTooltips()
        if override ~= nil then
            return override == true
        end
    end

    local devSupport = NutritionMakesSense and NutritionMakesSense.DevSupport or nil
    if devSupport and type(devSupport.isDebugLaunch) == "function" and devSupport.isDebugLaunch() then
        return true
    end

    if type(isClient) == "function" and isClient() and type(getAccessLevel) == "function" then
        local ok, accessLevel = pcall(getAccessLevel)
        if ok and (accessLevel == "admin" or accessLevel == "moderator") then
            return true
        end
    end

    return false
end

local function formatDebugNumber(value, decimals)
    local numeric = tonumber(value) or 0
    return string.format("%." .. tostring(decimals or 1) .. "f", numeric)
end

function TooltipLogic.isFoodItem(item)
    if not item then
        return false
    end

    local isFood = safeCall(item, "isFood")
    if isFood == nil then
        isFood = safeCall(item, "IsFood")
    end
    if isFood ~= nil then
        return isFood == true
    end

    return safeCall(item, "getCalories") ~= nil
        or safeCall(item, "getCarbohydrates") ~= nil
        or safeCall(item, "getLipids") ~= nil
        or safeCall(item, "getProteins") ~= nil
end

function TooltipLogic.getVanillaNutritionVisibility(item, viewer)
    if not TooltipLogic.isFoodItem(item) then
        return {
            exactNumbersVisible = false,
            reason = "not_food",
            blocker = nil,
            packaged = false,
        }
    end

    local resolvedViewer = resolveViewer(viewer)
    local packaged = safeCall(item, "isPackaged") == true or item.packaged == true
    local noLabel = rawLookup(getModData(item), "NoLabel") ~= nil or item.noLabel == true

    if resolvedViewer.nutritionist then
        return {
            exactNumbersVisible = true,
            reason = "nutritionist",
            blocker = nil,
            packaged = packaged,
        }
    end

    local canReadPackage = packaged
        and resolvedViewer.hasCharacter
        and not resolvedViewer.illiterate
        and not resolvedViewer.tooDark
        and not noLabel

    if canReadPackage then
        return {
            exactNumbersVisible = true,
            reason = "packaged_label",
            blocker = nil,
            packaged = packaged,
        }
    end

    if packaged and resolvedViewer.illiterate then
        return {
            exactNumbersVisible = false,
            reason = "packaged_blocked",
            blocker = "illiterate",
            packaged = packaged,
        }
    end

    if packaged and resolvedViewer.tooDark then
        return {
            exactNumbersVisible = false,
            reason = "packaged_blocked",
            blocker = "too_dark",
            packaged = packaged,
        }
    end

    if packaged and noLabel then
        return {
            exactNumbersVisible = false,
            reason = "packaged_blocked",
            blocker = "no_label",
            packaged = packaged,
        }
    end

    return {
        exactNumbersVisible = false,
        reason = "descriptors_only",
        blocker = nil,
        packaged = packaged,
    }
end

function TooltipLogic.getSatietyDescriptor(values)
    local hungerDrop = nil
    if Metabolism and type(Metabolism.getImmediateHungerDrop) == "function" then
        hungerDrop = tonumber(Metabolism.getImmediateHungerDrop(values, 1))
    end
    if hungerDrop == nil then
        hungerDrop = normalizeHungerValue(values and values.hunger) * 0.01
    end

    if hungerDrop >= 0.18 then
        return "Hearty"
    end
    if hungerDrop >= 0.11 then
        return "Filling"
    end
    if hungerDrop >= 0.05 then
        return "Light"
    end
    if hungerDrop > 0 then
        return "Minimal"
    end
    return nil
end

function TooltipLogic.getEnergyDescriptor(values)
    local kcal = math.max(0, tonumber(values and values.kcal) or 0)
    if kcal >= 450 then
        return "Very high"
    end
    if kcal >= 200 then
        return "Moderate"
    end
    if kcal >= 60 then
        return "Low"
    end
    if kcal > 0 then
        return "Trace"
    end
    return nil
end

function TooltipLogic.getDominantMacroDescriptor(values)
    local carbKcal = math.max(0, tonumber(values and values.carbs) or 0) * 4
    local fatKcal = math.max(0, tonumber(values and values.fats) or 0) * 9
    local proteinKcal = math.max(0, tonumber(values and values.proteins) or 0) * 4
    local total = carbKcal + fatKcal + proteinKcal
    if total < 40 then
        return nil
    end

    local ranked = {
        { key = "carbs", label = "Mostly carbs", share = carbKcal / total },
        { key = "fats", label = "Mostly fat", share = fatKcal / total },
        { key = "proteins", label = "Mostly protein", share = proteinKcal / total },
    }

    table.sort(ranked, function(a, b)
        return a.share > b.share
    end)

    local top = ranked[1]
    local second = ranked[2]
    if top.share < 0.55 then
        return nil
    end
    if (top.share - second.share) < 0.15 then
        return nil
    end
    return top.label
end

function TooltipLogic.buildDescriptorRows(item, viewer)
    if not TooltipLogic.isFoodItem(item) then
        return {}
    end

    local values = readFoodValues(item)
    local rows = {}
    local debugMode = isDebugTooltipMode()
    local visibility = TooltipLogic.getVanillaNutritionVisibility(item, viewer)

    local satiety = TooltipLogic.getSatietyDescriptor(values)
    if satiety then
        local label = "Satiety"
        if debugMode and Metabolism and type(Metabolism.getImmediateHungerDrop) == "function" then
            label = string.format("Satiety [%s]", formatDebugNumber(Metabolism.getImmediateHungerDrop(values, 1), 2))
        end
        rows[#rows + 1] = { label = label, value = satiety }
    end

    if debugMode and Metabolism and type(Metabolism.getSatietyContribution) == "function" then
        rows[#rows + 1] = {
            label = "Satiety Buffer",
            value = formatDebugNumber(Metabolism.getSatietyContribution(values, 1), 2),
        }
    end

    local energy = TooltipLogic.getEnergyDescriptor(values)
    if energy then
        local label = "Energy Content"
        if debugMode then
            label = string.format("Energy Content [%s kcal]", formatDebugNumber(values.kcal, 0))
        end
        rows[#rows + 1] = { label = label, value = energy }
    end

    local macro = TooltipLogic.getDominantMacroDescriptor(values)
    if macro and not visibility.exactNumbersVisible then
        local label = "Macro"
        if debugMode then
            label = string.format(
                "Macro [%sc/%sf/%sp]",
                formatDebugNumber(values.carbs, 1),
                formatDebugNumber(values.fats, 1),
                formatDebugNumber(values.proteins, 1)
            )
        end
        rows[#rows + 1] = { label = label, value = macro }
    end

    return rows
end

function TooltipLogic.buildFixtureSnapshot(item, viewer)
    local visibility = TooltipLogic.getVanillaNutritionVisibility(item, viewer)
    return {
        fullType = safeCall(item, "getFullType") or item.id or item.fullType,
        visibility = visibility.reason,
        blocker = visibility.blocker,
        exactNumbersVisible = visibility.exactNumbersVisible,
        descriptors = TooltipLogic.buildDescriptorRows(item, viewer),
    }
end

function TooltipLogic.injectDescriptorRowsIntoEmbeddedLayout(layout, item)
    if not layout or not item or not TooltipLogic.isFoodItem(item) then
        return false, "not_food"
    end

    local rows = TooltipLogic.buildDescriptorRows(item)
    if #rows == 0 then
        return false, "no_rows"
    end

    local items = getLayoutItems(layout)
    if not items then
        return false, "items_inaccessible"
    end

    local hungerLabel = getLabelPrefix("Tooltip_food_Hunger")
    local firstFoodPrefixes = {
        hungerLabel,
        getLabelPrefix("Tooltip_food_Thirst"),
        getLabelPrefix("Tooltip_food_Endurance"),
        getLabelPrefix("Tooltip_food_Stress"),
        getLabelPrefix("Tooltip_food_Boredom"),
        getLabelPrefix("Tooltip_food_Unhappiness"),
        getLabelPrefix("Tooltip_food_MinutesToCook"),
        tostring(getText("IGUI_invpanel_Cooking") or "") .. ":",
        tostring(getText("IGUI_invpanel_Burning") or "") .. ":",
        tostring(getText("IGUI_invpanel_FreezingTime") or "") .. ":",
        getLabelPrefix("Tooltip_food_Nutrition"),
    }

    local insertionIndex = nil
    local hungerIndex = nil
    local size = getListSize(items)

    for index = 0, size - 1 do
        local layoutItem = getListEntry(items, index)
        if layoutItem then
            if hungerIndex == nil and labelStartsWith(layoutItem, hungerLabel) then
                hungerIndex = index
            end
            if insertionIndex == nil then
                for _, prefix in ipairs(firstFoodPrefixes) do
                    if labelStartsWith(layoutItem, prefix) then
                        insertionIndex = index
                        break
                    end
                end
            end
        end
    end

    if insertionIndex == nil then
        insertionIndex = getListSize(items)
    end

    local rowInsertIndex = insertionIndex

    if hungerIndex ~= nil then
        rowInsertIndex = hungerIndex
    end

    for _, row in ipairs(rows) do
        local layoutItem = addLayoutRow(layout, {
            label = tostring(row.label) .. ":",
            value = tostring(row.value),
        })
        if not layoutItem then
            return false, "add_row_failed"
        end

        local sourceIndex = getListSize(items) - 1
        if sourceIndex > rowInsertIndex then
            if not bubbleLayoutItemToIndex(items, sourceIndex, rowInsertIndex) then
                return false, "bubble_failed"
            end
        end
        rowInsertIndex = rowInsertIndex + 1
    end

    if hungerIndex ~= nil then
        local removalIndex = hungerIndex + #rows
        removeListEntry(items, removalIndex)
    end

    return true, "embedded"
end

function TooltipLogic.appendDescriptorRowsToLayout(layout, item)
    return TooltipLogic.appendDescriptorRowsToLayoutForViewer(layout, item, nil)
end

function TooltipLogic.appendDescriptorRowsToLayoutForViewer(layout, item, viewer)
    if not layout or not item or not TooltipLogic.isFoodItem(item) then
        return false
    end

    local rows = TooltipLogic.buildDescriptorRows(item, viewer)
    if #rows == 0 then
        return false
    end

    for _, row in ipairs(rows) do
        addLayoutRow(layout, {
            label = tostring(row.label) .. ":",
            value = tostring(row.value),
        })
    end

    return true
end

function TooltipLogic.appendDescriptorsToTooltip(tooltip, item)
    if not tooltip or not item then
        return false
    end

    local layout = safeCall(tooltip, "beginLayout")
    if not layout then
        return false
    end
    safeCall(layout, "setMinLabelWidth", 80)
    safeCall(layout, "setMinValueWidth", 80)

    local viewer = safeCall(tooltip, "getCharacter")
    if not TooltipLogic.appendDescriptorRowsToLayoutForViewer(layout, item, viewer) then
        safeCall(tooltip, "endLayout", layout)
        return false
    end

    local padLeft, _, _, padBottom = getTooltipPadding(tooltip)
    local startY = math.max(0, (tonumber(safeCall(tooltip, "getHeight")) or 0) - padBottom)
    local y = tonumber(safeCall(layout, "render", padLeft, startY, tooltip)) or startY
    safeCall(tooltip, "endLayout", layout)
    safeCall(tooltip, "setHeight", math.floor(y + padBottom))
    local width = tonumber(safeCall(tooltip, "getWidth")) or 0
    if width < 150 then
        safeCall(tooltip, "setWidth", 150)
    end

    return true
end

return TooltipLogic
