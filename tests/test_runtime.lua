local Support = require "support"

-- Minimal PZ surface: vanilla owns the values, NMS reads and corrects them.
local worldHours = 100
local wallMs = 0
local serverMode, clientMode = false, false

function isServer() return serverMode end
function isClient() return clientMode end
function getTimestampMs() return wallMs end
function getGameTime()
    return { getWorldAgeHours = function() return worldHours end }
end
CharacterStat = { HUNGER = "HUNGER", ENDURANCE = "ENDURANCE" }
CharacterTrait = { WEIGHT_LOSS = "WEIGHT_LOSS", WEIGHT_GAIN = "WEIGHT_GAIN", HEARTY_APPETITE = "HEARTY_APPETITE", LIGHT_EATER = "LIGHT_EATER" }
SandboxVars = {}
local handlers = {}
Events = setmetatable({}, {
    __index = function(_, name)
        return { Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end }
    end,
})

local function newPlayer(opts)
    opts = opts or {}
    local statValues = { HUNGER = opts.hunger or 0.2, ENDURANCE = 1 }
    local nutrition = {
        calories = opts.calories or 800, proteins = opts.proteins or 0, lipids = 0, carbs = 0, weight = opts.weight or 80,
        traitCalls = 0,
    }
    function nutrition:getCalories() return self.calories end
    function nutrition:setCalories(v) self.calories = v end
    function nutrition:getProteins() return self.proteins end
    function nutrition:setProteins(v) self.proteins = v end
    function nutrition:getLipids() return self.lipids end
    function nutrition:setLipids(v) self.lipids = v end
    function nutrition:getCarbohydrates() return self.carbs end
    function nutrition:setCarbohydrates(v) self.carbs = v end
    function nutrition:getWeight() return self.weight end
    function nutrition:setWeight(v) self.weight = v end
    function nutrition:applyTraitFromWeight() self.traitCalls = self.traitCalls + 1 end
    local stats = {}
    function stats:get(stat) return statValues[stat] end
    function stats:set(stat, v) statValues[stat] = v end
    local body = { timer = opts.timer or 0, healthFromFood = 0.015, standard = 0.002, reduced = 0.0013, severe = 0.0008 }
    function body:getHealthFromFoodTimer() return self.timer end
    function body:setHealthFromFoodTimer(v) self.timer = v end
    function body:getHealthFromFood() return self.healthFromFood end
    function body:setHealthFromFood(v) self.healthFromFood = v end
    function body:getStandardHealthAddition() return self.standard end
    function body:setStandardHealthAddition(v) self.standard = v end
    function body:getReducedHealthAddition() return self.reduced end
    function body:setReducedHealthAddition(v) self.reduced = v end
    function body:getSeverlyReducedHealthAddition() return self.severe end
    function body:setSeverlyReducedHealthAddition(v) self.severe = v end
    function body:getThermoregulator() return nil end
    local modData = opts.modData or {}
    local player = { statValues = statValues, nutrition = nutrition, body = body, modData = modData }
    function player:getStats() return stats end
    function player:getNutrition() return nutrition end
    function player:getBodyDamage() return body end
    function player:getModData() return modData end
    function player:isLocalPlayer() return true end
    function player:isDead() return false end
    function player:isAsleep() return false end
    function player:hasTrait() return false end
    function player:hasTimedActions() return false end
    function player:getUsername() return "tester" end
    return player
end

local function advance(player, hours, runtime)
    local steps = math.floor(hours / 0.01 + 0.5)
    for _ = 1, steps do
        worldHours = worldHours + 0.01
        wallMs = wallMs + 300
        -- Vanilla's own passive drift, which NMS must override.
        player.statValues.HUNGER = math.min(1, player.statValues.HUNGER + 0.0004)
        player.nutrition.calories = player.nutrition.calories - 0.6
        player.nutrition.weight = player.nutrition.weight + 0.00001
        player.body.timer = math.max(0, player.body.timer - 30)
        runtime.tick(player, false)
    end
end

require "NutritionMakesSense_Runtime"
local Runtime = NutritionMakesSense.Runtime
local Model = NutritionMakesSense.Model

-- SP authority: first tick seeds from vanilla without writing anything.
local player = newPlayer({ hunger = 0.3 })
Runtime.tick(player, true)
local state = player.modData[Runtime.STATE_KEY]
Support.assertTrue(type(state) == "table" and state.version == 2, "authority creates the 2.0 persisted state")
Support.assertClose(player.statValues.HUNGER, 0.3, 1e-9, "seeding does not rewrite hunger")

advance(player, 1, Runtime)
Support.assertTrue(player.nutrition.weight < 80.00005, "vanilla weight drift is reverted")
local burnedFromVanilla = 800 - player.nutrition.calories
Support.assertTrue(burnedFromVanilla > 70 and burnedFromVanilla < 80,
    "calories follow the NMS burn (~75/h at rest), not vanilla's drift")

-- Eating: vanilla deposits calories, drops hunger, and sets its own Well Fed increment.
local caloriesBefore = player.nutrition.calories
local hungerBefore = player.statValues.HUNGER
player.nutrition.calories = caloriesBefore + 450
player.nutrition.proteins = player.nutrition.proteins + 25
player.nutrition.lipids = player.nutrition.lipids + 18
player.statValues.HUNGER = math.max(0, hungerBefore - 0.30)
player.body.timer = 3900
worldHours = worldHours + 0.001
Runtime.afterEat(player)
local expectedHunger = hungerBefore - 0.30 * Model.HUNGER_DROP_SCALE
Support.assertClose(player.statValues.HUNGER, expectedHunger, 0.002, "the eat-time hunger drop is scaled immediately")
local fill = Model.fillHours(450, 18, 25) * Model.STOMACH_UNITS_PER_HOUR
Support.assertClose(player.body.timer, fill, 20, "the Well Fed timer is re-clocked from meal energy and composition")

advance(player, 1, Runtime)
Support.assertTrue(player.body.timer < fill - 900 and player.body.timer > fill - 1100,
    "the stomach empties at ~1000 units per game hour")
Support.assertTrue(player.body.healthFromFood < 0.0011, "Well Fed healing is toned down")

-- Clock jumps (save reload, reconnect) resume without catch-up.
local hungerAtGap = player.statValues.HUNGER
worldHours = worldHours + 5
wallMs = wallMs + 1000
Runtime.tick(player, false)
Support.assertClose(player.statValues.HUNGER, hungerAtGap, 1e-9, "a large clock gap re-seeds instead of applying hours at once")

-- External weight edits are respected and re-apply weight traits.
local traitCalls = player.nutrition.traitCalls
player.nutrition.weight = 65
advance(player, 0.05, Runtime)
Support.assertTrue(math.abs(player.nutrition.weight - 65) < 0.01, "admin weight edits are kept")
Support.assertTrue(player.nutrition.traitCalls > traitCalls, "weight traits are refreshed after a weight change")

-- Vanilla calorie drops are NMS-owned burn; a bogus huge drop must not poison the burn estimate.
local caloriesBeforeDrop = player.nutrition.calories
player.nutrition.calories = caloriesBeforeDrop - 3000
advance(player, 0.01, Runtime)
Support.assertTrue(player.nutrition.calories > caloriesBeforeDrop - 5, "vanilla-side calorie drops are reverted")

-- Malnutrition from a depleted reserve slows endurance regen and natural recovery.
player = newPlayer({ calories = -1500 })
Runtime.tick(player, true)
state = player.modData[Runtime.STATE_KEY]
advance(player, 24, Runtime)
Support.assertTrue(state.malnutrition > 0.3, "a depleted reserve builds malnutrition over a day")
Support.assertTrue(player.body.standard < 0.002, "malnutrition slows natural recovery")
local display = Runtime.getDisplay(player)
Support.assertEqual(display.cause, "calories", "display reports the calorie cause")
Support.assertEqual(display.reserveZone, "Depleted", "display reports the reserve zone")

-- Legacy 1.x state seeds vanilla counters once and is removed.
local legacy = newPlayer({ calories = 800, proteins = 0, modData = {
    NutritionMakesSenseState = { fuel = 1200, weightKg = 72, proteins = 64 * 4, deprivation = 0.4 },
} })
Runtime.tick(legacy, true)
Support.assertNil(legacy.modData.NutritionMakesSenseState, "legacy state key is removed")
Support.assertClose(legacy.nutrition.weight, 72, 1e-9, "legacy weight carries over")
Support.assertClose(legacy.modData[Runtime.STATE_KEY].malnutrition, 0.4, 1e-9, "legacy deprivation carries over")
Support.assertTrue(legacy.nutrition.calories > 900 and legacy.nutrition.calories < 1100, "legacy fuel maps into the reserve band")

-- MP client never writes vanilla values.
clientMode = true
local remote = newPlayer({ hunger = 0.5 })
Support.assertEqual(Runtime.tick(remote, true), false, "MP clients do not run the authority tick")
advance(remote, 0.1, Runtime)
Support.assertNil(remote.modData[Runtime.STATE_KEY], "MP clients do not create authority state")
Runtime.importDisplaySnapshot(remote, { malnutrition = 0.5, malnutritionTarget = 0.6, calorieTarget = 0.6, proteinTarget = 0 })
display = Runtime.getDisplay(remote)
Support.assertClose(display.malnutrition, 0.5, 1e-9, "MP clients display the server snapshot")
Support.assertClose(display.hunger, remote.statValues.HUNGER, 1e-9, "MP clients read replicated vanilla hunger")
clientMode = false

-- Dedicated server: connected players are remote, so OnPlayerUpdate never fires for them there.
-- The server must drive the authority tick and snapshots from EveryOneMinute.
local testsDir = string.match(string.sub(debug.getinfo(1, "S").source, 2), "(.*/)") or "./"
package.path = testsDir .. "../common/media/lua/server/?.lua;" .. package.path
serverMode = true
local online = newPlayer({ hunger = 0.3 })
function online:getOnlineID() return 7 end
function getOnlinePlayers()
    return { size = function() return 1 end, get = function(_, i) return i == 0 and online or nil end }
end
function getPlayerByOnlineID(id) return id == 7 and online or nil end
local sent = {}
function sendServerCommand(target, module, command, args) sent[#sent + 1] = { target = target, command = command } end
handlers.OnPlayerUpdate, handlers.EveryOneMinute = nil, nil
Runtime._installed = nil
Runtime.install()
Support.assertNil(handlers.OnPlayerUpdate, "the server does not rely on OnPlayerUpdate for the authority tick")
require "NutritionMakesSense_MPServer"
NutritionMakesSense.MPServer.install()
Support.assertTrue(handlers.EveryOneMinute ~= nil, "the server ticks players from EveryOneMinute")
local function fireMinute()
    worldHours = worldHours + 1 / 60
    wallMs = wallMs + 2500
    online.statValues.HUNGER = math.min(1, online.statValues.HUNGER + 0.0006)
    for _, fn in ipairs(handlers.EveryOneMinute) do fn() end
end
fireMinute()
Support.assertTrue(type(online.modData[Runtime.STATE_KEY]) == "table", "the server minute tick seeds connected players")
for _ = 1, 60 do fireMinute() end
Support.assertTrue(online.nutrition.calories < 800 - 60, "the server minute tick burns calories for connected players")
Support.assertTrue(#sent > 0 and sent[1].target == online, "the server minute tick pushes display snapshots")
serverMode = false

print("nms runtime characterization passed")
