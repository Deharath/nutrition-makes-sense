local source = debug.getinfo(1, "S").source
local scriptPath = string.sub(source, 2)
local testsDir = string.match(scriptPath, "(.*/)") or "./"
local rootDir = testsDir .. ".."

package.path = table.concat({
    rootDir .. "/common/media/lua/client/?.lua",
    rootDir .. "/common/media/lua/shared/?.lua",
    testsDir .. "?.lua",
    package.path,
}, ";")

local Support = require "support"

ItemTag = { HIDE_HUNGER_CHANGE = "HideHungerChange" }
getText = function(key) return key end
getTextManager = function()
    return {
        MeasureStringX = function(_, font, text)
            Support.assertEqual(font, "TooltipFont", "tooltip geometry uses the active font")
            if text == "0" then
                return 10
            end
            return 6 * #text
        end,
    }
end

local reflectionCalls = 0
getNumClassFields = function()
    reflectionCalls = reflectionCalls + 1
    error("Not in debug")
end
getClassField = getNumClassFields
getClassFieldVal = getNumClassFields

ISToolTipInv = nil
ISItemSlot = nil
Events = nil

local TooltipOverlay = require "NutritionMakesSense_TooltipOverlay"
TooltipOverlay.install()

local hiddenTags = {}
local tags = {}
function tags:add(tag) hiddenTags[tag] = true end
function tags:remove(tag) hiddenTags[tag] = nil end

local originalTooltipCalls = 0
local embeddedTooltipCalls = 0
local embeddedSawHiddenHunger = 0
local itemMethods = {
    isFood = function() return true end,
    getTags = function() return tags end,
    hasTag = function(_, tag) return hiddenTags[tag] == true end,
    getExtraItems = function() return { "Base.Apple" } end,
    getSpices = function() return nil end,
    getScriptItem = function()
        return { isCantEat = function() return false end }
    end,
    getModData = function() return {} end,
    getHungerChange = function() return -0.10 end,
    getCalories = function() return 200 end,
    getCarbohydrates = function() return 0 end,
    getLipids = function() return 0 end,
    getProteins = function() return 0 end,
    isPackaged = function() return false end,
    DoTooltip = function(_, tooltip)
        originalTooltipCalls = originalTooltipCalls + 1
        tooltip:setWidth(170)
        tooltip:setHeight(80)
    end,
    DoTooltipEmbedded = function(self, _, layout)
        embeddedTooltipCalls = embeddedTooltipCalls + 1
        if self:hasTag(ItemTag.HIDE_HUNGER_CHANGE) then
            embeddedSawHiddenHunger = embeddedSawHiddenHunger + 1
        else
            local hunger = layout:addItem()
            hunger:setLabel("Hunger:")
        end
        local weight = layout:addItem()
        weight:setLabel("Weight:")
        weight:setValue("0.2")
    end,
}
local item = setmetatable({}, { __index = itemMethods })

local completedLayouts = {}
local tooltipWidth = 50
local tooltipHeight = 0
local function newLayout()
    local layout = { rows = {}, minLabelWidth = 0, minValueWidth = 0 }
    function layout:setMinLabelWidth(value) self.minLabelWidth = value end
    function layout:setMinValueWidth(value) self.minValueWidth = value end
    function layout:addItem()
        local row = {}
        function row:setLabel(value) self.label = value end
        function row:setValue(value) self.value = value end
        function row:setProgress(value) self.progress = value end
        self.rows[#self.rows + 1] = row
        return row
    end
    function layout:render(x, y)
        self.renderX = x
        self.renderY = y
        return y + (#self.rows * 14)
    end
    return layout
end

local tooltip = {}
function tooltip:beginLayout()
    local layout = newLayout()
    completedLayouts[#completedLayouts + 1] = layout
    return layout
end
function tooltip:endLayout() end
function tooltip:getFont() return "TooltipFont" end
function tooltip:getLineSpacing() return 20 end
function tooltip:getCharacter() return nil end
function tooltip:getWidth() return tooltipWidth end
function tooltip:getHeight() return tooltipHeight end
function tooltip:setWidth(value) tooltipWidth = value end
function tooltip:setHeight(value) tooltipHeight = value end
local drawnLabels = {}
local pipRects = 0
local measureOnly = false
function tooltip:isMeasureOnly() return measureOnly end
function tooltip:DrawText(_, text) drawnLabels[#drawnLabels + 1] = text end
function tooltip:DrawTextureScaledColor() pipRects = pipRects + 1 end

local vanillaDoTooltip = itemMethods.DoTooltip
local originalRender = function(panel)
    panel.item:DoTooltip(panel.tooltip)
    panel.item:DoTooltip(panel.tooltip)
end
ISToolTipInv = { render = originalRender }
TooltipOverlay.install()

local panel = { item = item, tooltip = tooltip }
ISToolTipInv.render(panel)

Support.assertTrue(itemMethods.DoTooltip ~= vanillaDoTooltip, "NMS installs one persistent class wrapper")
Support.assertEqual(TooltipOverlay._active, nil, "active render cleared after the owner render")
Support.assertEqual(originalTooltipCalls, 0, "standalone NMS routes food through the embedded tooltip contract")
Support.assertEqual(embeddedTooltipCalls, 2, "NMS preserves every owner render pass")
Support.assertEqual(embeddedSawHiddenHunger, 2, "the vanilla numeric hunger row is hidden during embedded rendering")
Support.assertEqual(hiddenTags[ItemTag.HIDE_HUNGER_CHANGE], nil, "temporary hunger suppression is restored")
Support.assertEqual(#completedLayouts, 2, "each owner pass receives one combined layout")
for _, layout in ipairs(completedLayouts) do
    Support.assertEqual(layout.minLabelWidth, 80, "the shared label column keeps the vanilla minimum")
    Support.assertEqual(layout.minValueWidth, 80, "combined layout preserves the vanilla minimum value width")
    Support.assertEqual(#layout.rows, 1, "vanilla rows own the layout")
    Support.assertEqual(layout.rows[1].label, "Weight:", "vanilla rows remain first")
    Support.assertEqual(layout.renderX, 10, "layout uses font-derived left padding")
    Support.assertEqual(layout.renderY, 55, "layout accounts for the vanilla title and ingredient strip")
end
Support.assertEqual(table.concat(drawnLabels, ","), "Satiety:,Energy:,Protein:,Satiety:,Energy:,Protein:",
    "each pass draws satiety, energy and protein pip rows under the vanilla layout")
Support.assertEqual(pipRects, 2 * (15 + 2), "five track pips per row plus fills for the two non-empty rows")
Support.assertEqual(tooltipWidth, 174, "the tooltip widens to fit the pip strip")
Support.assertEqual(tooltipHeight, 137, "pip rows extend the final height")
Support.assertEqual(reflectionCalls, 0, "release rendering avoids debug-only reflection")
local sizeW, sizeH = tooltipWidth, tooltipHeight
item:DoTooltip(tooltip)
Support.assertEqual(originalTooltipCalls, 1, "outside an NMS render the wrapper defers to vanilla")
originalTooltipCalls = 0
tooltipWidth, tooltipHeight = sizeW, sizeH

local previousWrapper = ISToolTipInv.render
local competitor = function(self)
    return previousWrapper(self)
end
ISToolTipInv.render = competitor
for _ = 1, 50 do TooltipOverlay.install() end
Support.assertEqual(ISToolTipInv.render, competitor, "install does not re-wrap over another mod's wrapper")
ISToolTipInv.render(panel)
Support.assertEqual(embeddedTooltipCalls, 4, "a competing owner on top preserves the embedded path")

EuryTooltipController = {
    installed = true,
    providers = {},
    registerProvider = function(self, id, provider)
        self.providers[id] = provider
    end,
}
TooltipOverlay.install()
local provider = EuryTooltipController.providers.NutritionMakesSense
Support.assertEqual(provider, TooltipOverlay._provider, "NMS registers with the shared tooltip controller")
Support.assertTrue(provider:ownsTooltip({ item = item }), "the shared provider owns food tooltips")

local embeddedBeforeDelegation = embeddedTooltipCalls
local originalBeforeDelegation = originalTooltipCalls
ISToolTipInv.render(panel)
Support.assertEqual(embeddedTooltipCalls, embeddedBeforeDelegation, "standalone wrapper yields when the controller owns food")
Support.assertEqual(originalTooltipCalls, originalBeforeDelegation + 2, "controller ownership preserves the wrapped owner")

provider:renderMain({ item = item, tooltip = tooltip })
Support.assertEqual(embeddedTooltipCalls, embeddedBeforeDelegation + 1, "the shared owner renders one combined food layout")

EuryTooltipController = nil
local slotOriginalCalls = 0
ISItemSlot = {
    drawTooltip = function(slot, targetTooltip)
        slotOriginalCalls = slotOriginalCalls + 1
        slot.resource:DoTooltip(targetTooltip)
    end,
}
TooltipOverlay.install()
local slotWrapper = ISItemSlot.drawTooltip
local slotCompetitor = function(slot, targetTooltip) return slotWrapper(slot, targetTooltip) end
ISItemSlot.drawTooltip = slotCompetitor
for _ = 1, 50 do TooltipOverlay.install() end
Support.assertEqual(ISItemSlot.drawTooltip, slotCompetitor, "item-slot install does not re-wrap over another mod")
ISItemSlot.drawTooltip({ resource = item }, tooltip)
Support.assertEqual(slotOriginalCalls, 1, "item-slot ownership remains intact")
Support.assertEqual(originalTooltipCalls, originalBeforeDelegation + 2, "item slots use the embedded path instead of the legacy food renderer")
Support.assertEqual(embeddedTooltipCalls, embeddedBeforeDelegation + 2, "item slots share the combined food layout")

print("nms tooltip overlay lifecycle checks passed")
