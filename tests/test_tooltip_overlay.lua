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
            Support.assertEqual(text, "0", "tooltip geometry derives padding from a public font metric")
            return 10
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

local originalRender = function(panel)
    panel.item:DoTooltip(panel.tooltip)
    panel.item:DoTooltip(panel.tooltip)
end
ISToolTipInv = { render = originalRender }
TooltipOverlay.install()

local panel = { item = item, tooltip = tooltip }
ISToolTipInv.render(panel)

Support.assertEqual(itemMethods.DoTooltip, getmetatable(item).__index.DoTooltip, "NMS restores the item method after rendering")
Support.assertEqual(originalTooltipCalls, 0, "standalone NMS routes food through the embedded tooltip contract")
Support.assertEqual(embeddedTooltipCalls, 2, "NMS preserves every owner render pass")
Support.assertEqual(embeddedSawHiddenHunger, 2, "the vanilla numeric hunger row is hidden during embedded rendering")
Support.assertEqual(hiddenTags[ItemTag.HIDE_HUNGER_CHANGE], nil, "temporary hunger suppression is restored")
Support.assertEqual(#completedLayouts, 2, "each owner pass receives one combined layout")
for _, layout in ipairs(completedLayouts) do
    Support.assertEqual(layout.minLabelWidth, 80, "combined layout preserves the vanilla minimum label width")
    Support.assertEqual(layout.minValueWidth, 80, "combined layout preserves the vanilla minimum value width")
    Support.assertEqual(#layout.rows, 3, "vanilla and NMS rows share one layout")
    Support.assertEqual(layout.rows[1].label, "Weight:", "vanilla rows remain first")
    Support.assertEqual(layout.rows[2].label, "Satiety:", "NMS satiety follows vanilla rows")
    Support.assertEqual(layout.rows[3].label, "Energy Content:", "NMS energy follows satiety")
    Support.assertEqual(layout.renderX, 10, "layout uses font-derived left padding")
    Support.assertEqual(layout.renderY, 55, "layout accounts for the vanilla title and ingredient strip")
end
Support.assertEqual(tooltipWidth, 150, "combined tooltip enforces the vanilla minimum width")
Support.assertEqual(tooltipHeight, 102, "combined layout owns the final height")
Support.assertEqual(reflectionCalls, 0, "release rendering avoids debug-only reflection")

local previousWrapper = ISToolTipInv.render
ISToolTipInv.render = function(self)
    return previousWrapper(self)
end
TooltipOverlay.install()
ISToolTipInv.render(panel)
Support.assertEqual(embeddedTooltipCalls, 4, "rewrapping a competing owner preserves the embedded path")

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
ISItemSlot.drawTooltip({ resource = item }, tooltip)
Support.assertEqual(slotOriginalCalls, 1, "item-slot ownership remains intact")
Support.assertEqual(originalTooltipCalls, originalBeforeDelegation + 2, "item slots use the embedded path instead of the legacy food renderer")
Support.assertEqual(embeddedTooltipCalls, embeddedBeforeDelegation + 2, "item slots share the combined food layout")

print("nms tooltip overlay lifecycle checks passed")
