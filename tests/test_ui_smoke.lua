local source = debug.getinfo(1, "S").source
local testsDir = string.match(string.sub(source, 2), "(.*/)") or "./"
local rootDir = testsDir .. ".."
package.path = table.concat({
    rootDir .. "/common/media/lua/client/?.lua",
    rootDir .. "/common/media/lua/shared/?.lua",
    rootDir .. "/common/media/lua/server/?.lua",
    testsDir .. "?.lua",
    package.path,
}, ";")

local Support = require "support"

-- Render smoke: drive every NMS UI surface through representative states and fail on any
-- Lua error, missing translation key, or unformatted placeholder.
local worldHours, wallMs = 100, 0
function isServer() return false end
function isClient() return false end
function getTimestampMs() return wallMs end
function getGameTime()
    return {
        getWorldAgeHours = function() return worldHours end,
        getTimeOfDay = function() return worldHours % 24 end,
    }
end
CharacterStat = { HUNGER = "HUNGER", ENDURANCE = "ENDURANCE" }
CharacterTrait = { NUTRITIONIST = "NUTRITIONIST", NUTRITIONIST2 = "NUTRITIONIST2" }
SandboxVars = { Nutrition = true }
UIFont = { Small = "Small", Medium = "Medium" }
unpack = unpack or table.unpack

local handlers = {}
Events = setmetatable({}, {
    __index = function(_, name)
        return { Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
            Remove = function() end }
    end,
})
local function fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end

local translations = {}
local function loadJson(path)
    local f = assert(io.open(path, "r"))
    for key, value in f:read("*a"):gmatch('"([%w_]+)":%s*"(.-)"%s*[,\n}]') do
        translations[key] = value
    end
    f:close()
end
loadJson(rootDir .. "/common/media/lua/shared/Translate/EN/UI.json")
loadJson(rootDir .. "/common/media/lua/shared/Translate/EN/Moodles.json")
local missing = {}
function getText(key, ...)
    local text = translations[key]
    if not text then
        missing[key] = true
        return key
    end
    local args = { ... }
    for i = 1, 4 do
        if args[i] ~= nil then
            text = text:gsub("%%" .. i, (tostring(args[i]):gsub("%%", "%%%%")))
        end
    end
    return (text:gsub("%%%%", "%%"))
end
function getTextManager()
    return {
        getFontHeight = function() return 14 end,
        MeasureStringX = function(_, _, text) return 7 * #tostring(text) end,
    }
end
function getCore()
    return {
        getScreenWidth = function() return 1920 end,
        getOptionClock24Hour = function() return true end,
    }
end
function getTexture() return {} end

local drawn = {}
local function recordText(text)
    Support.assertTrue(type(text) == "string", "drawn text is a string")
    Support.assertTrue(not text:find("%%%d"), "unformatted placeholder in: " .. text)
    Support.assertTrue(not text:find("UI_NMS_"), "missing translation in: " .. text)
    drawn[#drawn + 1] = text
end

local Element = {}
Element.__index = Element
function Element:derive(name)
    local cls = setmetatable({}, { __index = self })
    cls.__index = cls
    cls.Type = name
    return cls
end
function Element.new(cls, x, y, w, h)
    return setmetatable({ x = x, y = y, width = w, height = h, children = {}, visible = true }, cls)
end
function Element:initialise() end
function Element:instantiate() self:createChildren() end
function Element:createChildren() end
function Element:prerender() end
function Element:addToUIManager() self.inUI = true end
function Element:removeFromUIManager() self.inUI = false end
function Element:bringToTop() end
function Element:setVisible(v) self.visible = v end
function Element:isReallyVisible() return self.visible and self.inUI end
function Element:setWidth(w) self.width = w end
function Element:setHeight(h) self.height = h end
function Element:getX() return self.x end
function Element:getY() return self.y end
function Element:addChild(c) self.children[#self.children + 1] = c end
function Element:setTitle(t) self.title = t end
function Element:setResizable() end
function Element:setInfo(t) self.info = t end
function Element:titleBarHeight() return 16 end
function Element:drawText(text) recordText(text) end
function Element:drawTextRight(text) recordText(text) end
function Element:drawRect(x, y, w, h, a, r, g, b)
    for _, v in ipairs({ x, y, w, h, a, r, g, b }) do
        Support.assertTrue(type(v) == "number" and v == v, "drawRect args are numbers")
    end
end
function Element:drawRectBorder() end
function Element:drawTextureScaled() end
function Element:onMouseDown() end
function Element:onMouseUp() end
ISCollapsableWindow = Element:derive("ISCollapsableWindow")
ISPanel = Element:derive("ISPanel")
ISButton = Element:derive("ISButton")
function ISButton:new(x, y, w, h, title, target, onclick)
    local o = Element.new(self, x, y, w, h)
    o.title, o.target, o.onclick = title, target, onclick
    return o
end
package.loaded["ISUI/ISCollapsableWindow"] = true
package.loaded["ISUI/ISPanel"] = true
package.loaded["ISUI/ISButton"] = true

local halos = {}
HaloTextHelper = {
    addGoodText = function(_, text) halos[#halos + 1] = { good = true, text = text } end,
    addBadText = function(_, text) halos[#halos + 1] = { good = false, text = text } end,
}

local function newPlayer()
    local statValues = { HUNGER = 0.2, ENDURANCE = 1 }
    local nutrition = { calories = 800, proteins = 0, lipids = 0, carbs = 0, weight = 80 }
    for _, f in ipairs({ { "Calories", "calories" }, { "Proteins", "proteins" }, { "Lipids", "lipids" },
        { "Carbohydrates", "carbs" }, { "Weight", "weight" } }) do
        nutrition["get" .. f[1]] = function(self) return self[f[2]] end
        nutrition["set" .. f[1]] = function(self, v) self[f[2]] = v end
    end
    function nutrition:applyTraitFromWeight() end
    local stats = {}
    function stats:get(stat) return statValues[stat] end
    function stats:set(stat, v) statValues[stat] = v end
    local body = { timer = 0, healthFromFood = 0.015, health = 100, standard = 0.002, reduced = 0.0013, severe = 0.0008 }
    function body:getHealthFromFoodTimer() return self.timer end
    function body:setHealthFromFoodTimer(v) self.timer = v end
    function body:getHealthFromFood() return self.healthFromFood end
    function body:setHealthFromFood(v) self.healthFromFood = v end
    function body:getOverallBodyHealth() return self.health end
    function body:getStandardHealthAddition() return self.standard end
    function body:setStandardHealthAddition(v) self.standard = v end
    function body:getReducedHealthAddition() return self.reduced end
    function body:setReducedHealthAddition(v) self.reduced = v end
    function body:getSeverlyReducedHealthAddition() return self.severe end
    function body:setSeverlyReducedHealthAddition(v) self.severe = v end
    function body:getThermoregulator() return nil end
    local modData = {}
    local inventory = { items = {} }
    function inventory:AddItem(t) self.items[#self.items + 1] = t; return t end
    local player = { statValues = statValues, nutrition = nutrition, body = body, modData = modData, inventory = inventory }
    function player:getStats() return stats end
    function player:getNutrition() return nutrition end
    function player:getBodyDamage() return body end
    function player:getModData() return modData end
    function player:getInventory() return inventory end
    function player:isLocalPlayer() return true end
    function player:isDead() return false end
    function player:isAsleep() return false end
    function player:hasTrait() return false end
    function player:hasTimedActions() return false end
    function player:getUsername() return "tester" end
    return player
end

local player = newPlayer()
function getPlayer() return player end
function getSpecificPlayer() return player end

require "NutritionMakesSense_Runtime"
local Runtime = NutritionMakesSense.Runtime
local Model = NutritionMakesSense.Model
ISEatFoodAction = { complete = function() end }
Runtime.install()
fire("OnGameStart")
local NutritionWindow = require "NutritionMakesSense_NutritionWindow"
require "dev/NutritionMakesSense_DevTools"
require "dev/NutritionMakesSense_DevHud"
local DevPanel = require "dev/NutritionMakesSense_DevPanel"
local DevTools = NutritionMakesSense.DevTools
local DevHud = NutritionMakesSense.DevHud

local function tick(hours)
    local steps = math.floor(hours / 0.02 + 0.5)
    for _ = 1, steps do
        worldHours = worldHours + 0.02
        wallMs = wallMs + 600
        Runtime.tick(player, false)
        fire("OnPlayerUpdate", player)
    end
end

fire("OnCreatePlayer", 0)
tick(0.5)
NutritionWindow.show()
DevPanel.show()

-- The window instance is local to its module; reach it through the upvalue of show().
local function upvalue(fn, name)
    local i = 1
    while true do
        local n, v = debug.getupvalue(fn, i)
        if not n then return nil end
        if n == name then return v end
        i = i + 1
    end
end
local window = upvalue(NutritionWindow.show, "instance")
local devPanel = upvalue(DevPanel.show, "instance")
Support.assertTrue(window ~= nil and devPanel ~= nil, "windows open")
Support.assertTrue(window.info ~= nil and window.info:find("<H1>") ~= nil, "window help is rich text")
Support.assertEqual(#devPanel.children, 15, "dev panel has every tool button")

local detailedMode = false
NutritionMakesSense.ClientOptions.isDetailedDisplay = function() return detailedMode end

-- Renders both display modes; returns immersive text, detailed text.
local function render(label)
    local out = {}
    for i, mode in ipairs({ false, true }) do
        detailedMode = mode
        drawn = {}
        window:prerender()
        Support.assertTrue(#drawn > 15, label .. ": window drew content")
        Support.assertTrue(window.height > 150, label .. ": window fits its content")
        out[i] = table.concat(drawn, "\n")
        drawn = {}
        devPanel:prerender()
        Support.assertTrue(#drawn > 15, label .. ": dev panel drew content")
    end
    detailedMode = false
    return out[1], out[2]
end

local function has(text, needle) return text:find(needle, 1, true) ~= nil end

-- Fresh, fine. Immersive hides amounts and clock times; detailed shows them.
local out, detailed = render("fresh")
Support.assertTrue(has(out, "Doing fine") and has(detailed, "Doing fine"), "fresh verdict")
Support.assertTrue(has(out, "Well nourished"), "no malnourishment shown as well nourished")
Support.assertTrue(has(detailed, "kcal/h") and not has(out, "kcal"), "burn rate only when detailed")
Support.assertTrue(has(detailed, "Hungry around") and (has(out, "Hungry by ") or has(out, "Hungry soon")), "hunger forecast per mode")
Support.assertTrue(not out:find("%d h"), "no exact durations when immersive")

-- A meal: meal log halo with the 0.7 drop ratio, no flags.
local before = #halos
player.nutrition.calories = player.nutrition.calories + 420
player.nutrition.proteins = player.nutrition.proteins + 20
player.nutrition.lipids = player.nutrition.lipids + 12
player.statValues.HUNGER = math.max(0, player.statValues.HUNGER - 0.17)
player.body.health = 80
Runtime.afterEat(player)
tick(0.5)
local mealHalo = halos[before + 1]
Support.assertTrue(mealHalo and mealHalo.good and mealHalo.text:find("Ate 420 kcal", 1, true) ~= nil,
    "meal log halos the meal: " .. tostring(mealHalo and mealHalo.text))
out, detailed = render("fed")
Support.assertTrue(has(out, "Full for about an hour") or has(out, "Full for a little while"), "rough stomach forecast: " .. out)
Support.assertTrue(has(detailed, "Full for ~1 h"), "exact stomach forecast")
Support.assertTrue(has(out, "Healing faster"), "well fed healing shown when hurt")

-- Load check ran and passed.
tick(10)
local sawLoad = false
for _, h in ipairs(halos) do
    if h.text:find("NMS dev:", 1, true) then
        sawLoad = h.good
    end
end
Support.assertTrue(sawLoad, "load check halos OK")
Support.assertTrue(DevHud.allOk(), "all dev checks pass")

-- Starving and wasting on both causes; worsening chevron path.
DevHud.sendTool("calories", -1400)
DevHud.sendTool("proteins", -450)
DevHud.sendTool("malnutrition", 0.35)
DevHud.sendTool("hunger", 0.8)
tick(1)
out, detailed = render("wasting")
Support.assertTrue(has(out, "Your body is wasting"), "wasting verdict")
Support.assertTrue(has(out, "Tiring faster") and has(detailed, "Stamina recovery -"), "effects line per mode")
Support.assertTrue(has(out, "Deficient"), "protein deficient")
Support.assertTrue(has(detailed, "Moderate  3") and not has(out, "%"), "malnourishment percent only when detailed")
Support.assertTrue(not has(detailed, "%%"), "percent escapes resolved")

-- Recovery: clears-in forecast.
DevHud.sendTool("calories", 900)
DevHud.sendTool("proteins", 200)
DevHud.sendTool("hunger", 0.1)
tick(1)
out, detailed = render("recovering")
Support.assertTrue(has(out, "Clears in about a day") or has(out, "Clears in a few days"), "rough recovery forecast: " .. out)
Support.assertTrue(has(detailed, "Clears in ~"), "exact recovery forecast")

-- Weight trending towards a trait boundary.
DevHud.sendTool("malnutrition", 0)
player.modData[Runtime.STATE_KEY].trendKgPerWeek = -0.8
DevHud.sendTool("weightDelta", -4)
tick(0.2)
player.modData[Runtime.STATE_KEY].trendKgPerWeek = -0.8
out, detailed = render("losing weight")
Support.assertTrue(has(out, "Losing weight  Underweight in a week or so"), "felt weight forecast: " .. out)
Support.assertTrue(has(detailed, "-0.80 kg/week  Underweight in ~9 d"), "exact weight forecast")

-- Nutritionists read the body precisely even in immersive mode.
player.hasTrait = function(_, trait) return trait == CharacterTrait.NUTRITIONIST end
drawn = {}
window:prerender()
Support.assertTrue(has(table.concat(drawn, "\n"), "kg/week"), "nutritionist sees detail")
player.hasTrait = function() return false end

-- Every tool button runs.
for _, button in ipairs(devPanel.children) do
    button.onclick(button.target, button)
    tick(0.05)
    render("tool " .. button.title)
end
Support.assertTrue(#player.inventory.items >= #DevTools.SPAWN_FOODS, "spawn adds test foods")

-- Health panel lines.
local HealthPanelHook = require "NutritionMakesSense_HealthPanelHook"
DevHud.sendTool("malnutrition", 0.4)
DevHud.sendTool("calories", -800)
tick(0.5)
local lines = HealthPanelHook.collectLines(player, Runtime.getDisplay(player))
Support.assertTrue(#lines >= 2, "health panel shows malnourishment and effects")
Support.assertTrue(lines[1].chevron ~= nil and lines[1].chevron.up, "worsening chevron")
Support.assertEqual(lines[1].suffixText, "Too few calories", "cause suffix")
Support.assertEqual(lines[1].valueText, "Moderate", "immersive health panel names the level")
detailedMode = true
Support.assertEqual(HealthPanelHook.collectLines(player, Runtime.getDisplay(player))[1].valueText, "40%", "detailed health panel percent")
detailedMode = false
for _, line in ipairs(lines) do
    recordText(line.text .. (line.valueText or "") .. (line.suffixText or ""))
end

local keys = {}
for key in pairs(missing) do keys[#keys + 1] = key end
Support.assertEqual(#keys, 0, "missing translation keys: " .. table.concat(keys, ", "))

print("nms ui smoke passed")
