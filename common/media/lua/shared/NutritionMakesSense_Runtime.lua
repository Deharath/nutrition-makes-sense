NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"
require "NutritionMakesSense_Settings"
require "NutritionMakesSense_MPCompat"
require "NutritionMakesSense_Model"
require "NutritionMakesSense_Workload"

-- Authority-side steering of vanilla nutrition. Vanilla owns every value (hunger, calories, macros,
-- weight, Well Fed timer); each tick NMS reads them, runs Model.step, and writes the corrections back.
-- Authority = dedicated server in MP, the local player in SP. MP clients only display.
local Runtime = NutritionMakesSense.Runtime or {}
NutritionMakesSense.Runtime = Runtime

local CoreUtils = NutritionMakesSense.CoreUtils
local Settings = NutritionMakesSense.Settings
local MP = NutritionMakesSense.MP
local Model = NutritionMakesSense.Model
local Workload = NutritionMakesSense.Workload
local safeCall = CoreUtils.safeCall
local clamp = Model.clamp

Runtime.STATE_KEY = "NutritionMakesSense2"
Runtime.STATE_VERSION = 2
Runtime.LEGACY_STATE_KEY = MP.MOD_STATE_KEY
Runtime.TICK_SECONDS = 0.25
Runtime.STEP_HOURS = 0.1
Runtime.GAP_HOURS = 2.0
Runtime.TREND_HOURS = 24
Runtime.TRAIT_WEIGHT_STEP_KG = 0.05

local WRITE_EPSILON = 0.00001
local memoryByPlayer = setmetatable({}, { __mode = "k" })
local displayByPlayer = setmetatable({}, { __mode = "k" })
local recoveryByBodyDamage = setmetatable({}, { __mode = "k" })

local RECOVERY_FIELDS = {
    { get = "getStandardHealthAddition", set = "setStandardHealthAddition" },
    { get = "getReducedHealthAddition", set = "setReducedHealthAddition" },
    { get = "getSeverlyReducedHealthAddition", set = "setSeverlyReducedHealthAddition" },
}

local function log(msg)
    print("[NutritionMakesSense] " .. tostring(msg))
end

function Runtime.isAuthority()
    local server = type(isServer) == "function" and isServer()
    local client = type(isClient) == "function" and isClient()
    return server or not client
end

function Runtime.isMPClient()
    return type(isClient) == "function" and isClient() == true
end

local function readTraits(playerObj)
    return {
        fastMetabolism = CoreUtils.hasTrait(playerObj, "Fast Metabolism", "WEIGHT_LOSS"),
        slowMetabolism = CoreUtils.hasTrait(playerObj, "Slow Metabolism", "WEIGHT_GAIN"),
        heartyAppetite = CoreUtils.hasTrait(playerObj, "Hearty Appetite", "HEARTY_APPETITE"),
        lightEater = CoreUtils.hasTrait(playerObj, "Light Eater", "LIGHT_EATER"),
    }
end
Runtime.readTraits = readTraits

local function readVanilla(playerObj)
    local stats = CoreUtils.getPlayerStats(playerObj)
    local nutrition = CoreUtils.getPlayerNutrition(playerObj)
    local bodyDamage = CoreUtils.getPlayerBodyDamage(playerObj)
    if not stats or not nutrition or not bodyDamage then
        return nil
    end
    return {
        stats = stats,
        nutrition = nutrition,
        bodyDamage = bodyDamage,
        hunger = CoreUtils.getCharacterStatValue(stats, "HUNGER", "getHunger") or 0,
        calories = tonumber(safeCall(nutrition, "getCalories")) or Model.RESERVE_SET_POINT,
        proteins = tonumber(safeCall(nutrition, "getProteins")) or 0,
        fats = tonumber(safeCall(nutrition, "getLipids")) or 0,
        carbs = tonumber(safeCall(nutrition, "getCarbohydrates")) or 0,
        weight = tonumber(safeCall(nutrition, "getWeight")) or Model.DEFAULT_WEIGHT_KG,
        timer = tonumber(safeCall(bodyDamage, "getHealthFromFoodTimer")) or 0,
        endurance = CoreUtils.getCharacterStatValue(stats, "ENDURANCE", "getEndurance"),
    }
end
Runtime.readVanilla = readVanilla

local function setStat(stats, enumKey, value)
    if CharacterStat and CharacterStat[enumKey] then
        safeCall(stats, "set", CharacterStat[enumKey], value)
    end
end

local function getPersisted(playerObj)
    local modData = safeCall(playerObj, "getModData")
    if type(modData) ~= "table" and type(modData) ~= "userdata" then
        return nil, nil
    end
    local state = modData[Runtime.STATE_KEY]
    if type(state) ~= "table" then
        state = nil
    end
    return state, modData
end

-- Old 1.x saves anchored vanilla counters to constants, so their calories/macros are meaningless.
-- Seed the vanilla counters from the old NMS state once, then drop the old key.
local function migrateLegacy(playerObj, modData, reads)
    local legacy = modData[Runtime.LEGACY_STATE_KEY]
    if type(legacy) ~= "table" then
        return nil
    end
    local weight = clamp(tonumber(legacy.weightKg) or reads.weight, Model.WEIGHT_MIN_KG, Model.WEIGHT_MAX_KG)
    local fuel = tonumber(legacy.fuel) or 800
    local calories = clamp(Model.legacyFuelToCalories(fuel), Model.CALORIES_MIN, Model.CALORIES_MAX)
    local needPerDay = clamp(weight * 0.8, 40, 120)
    local proteinDays = (tonumber(legacy.proteins) or needPerDay * 4) / needPerDay
    local proteins = clamp((proteinDays - 2) / 2 * 300, -500, 300)

    safeCall(reads.nutrition, "setCalories", calories)
    safeCall(reads.nutrition, "setWeight", weight)
    safeCall(reads.nutrition, "setProteins", proteins)
    safeCall(reads.nutrition, "setLipids", 0)
    safeCall(reads.nutrition, "setCarbohydrates", 0)
    safeCall(reads.nutrition, "applyTraitFromWeight")
    modData[Runtime.LEGACY_STATE_KEY] = nil

    log(string.format("[MIGRATE] player=%s fuel=%.0f -> calories=%.0f weight=%.1f protein=%.0f",
        CoreUtils.getPlayerLabel(playerObj), fuel, calories, weight, proteins))
    return clamp(tonumber(legacy.deprivation) or 0, 0, 1)
end

local function ensurePersisted(playerObj, reads)
    local state, modData = getPersisted(playerObj)
    if state then
        return state
    end
    if not modData then
        return nil
    end
    local migratedM = migrateLegacy(playerObj, modData, reads)
    state = {
        version = Runtime.STATE_VERSION,
        malnutrition = migratedM or 0,
        trendKgPerWeek = 0,
        migratedFromLegacy = migratedM ~= nil or nil,
    }
    modData[Runtime.STATE_KEY] = state
    return state
end

local function seedMemory(mem, reads, worldHours)
    mem.prev = {
        calories = reads.calories,
        hunger = reads.hunger,
        timer = reads.timer,
        weight = reads.weight,
    }
    mem.prevFats = reads.fats
    mem.prevProteins = reads.proteins
    mem.lastWorldHours = worldHours
    mem.lastEndurance = reads.endurance
    mem.traitWeight = mem.traitWeight or reads.weight
end

local function ensureMemory(playerObj)
    local mem = memoryByPlayer[playerObj]
    if mem then
        return mem
    end
    local reads = readVanilla(playerObj)
    local worldHours = CoreUtils.getWorldHours()
    if not reads or not worldHours then
        return nil
    end
    local persisted = ensurePersisted(playerObj, reads)
    if not persisted then
        return nil
    end
    reads = readVanilla(playerObj)
    mem = {
        vanillaBurnPerHour = Model.VANILLA_BURN_DEFAULT_PER_HOUR,
        lastTickWall = 0,
        last = {},
    }
    seedMemory(mem, reads, worldHours)
    memoryByPlayer[playerObj] = mem
    return mem
end

function Runtime.forget(playerObj)
    memoryByPlayer[playerObj] = nil
    displayByPlayer[playerObj] = nil
    Workload.forget(playerObj)
end

-- Baseline capture keeps other mods' natural-recovery edits: a field changed externally is left alone.
local function applyNaturalRecovery(bodyDamage, multiplier)
    local fields = recoveryByBodyDamage[bodyDamage]
    if not fields then
        fields = {}
        recoveryByBodyDamage[bodyDamage] = fields
    end
    for _, field in ipairs(RECOVERY_FIELDS) do
        local current = tonumber(safeCall(bodyDamage, field.get))
        if current and current >= 0 then
            local entry = fields[field.get]
            if not entry then
                entry = { baseline = current }
                fields[field.get] = entry
            elseif entry.applied and math.abs(current - entry.applied) > 0.000001 then
                entry.external = true
            end
            if not entry.external then
                local desired = entry.baseline * multiplier
                if math.abs(current - desired) > 0.0000001 then
                    safeCall(bodyDamage, field.set, desired)
                end
                entry.applied = desired
            end
        end
    end
end

function Runtime.applyBodyTuning(bodyDamage, malnutrition)
    if not bodyDamage then
        return
    end
    local healing = Model.wellFedHealing(malnutrition)
    if math.abs((tonumber(safeCall(bodyDamage, "getHealthFromFood")) or 0) - healing) > 0.0000001 then
        safeCall(bodyDamage, "setHealthFromFood", healing)
    end
    applyNaturalRecovery(bodyDamage, Model.naturalRecoveryMultiplier(malnutrition))
end

local function getCompat()
    local compat = NutritionMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" or tostring(compat.protocol) ~= "mscompat-v1" then
        return nil
    end
    return compat
end

function Runtime.isCompatEnduranceActive()
    local compat = getCompat()
    return compat ~= nil
        and type(compat.hasCapability) == "function"
        and compat:hasCapability("ArmorMakesSense", "endurance_coordinator") == true
end

local function controlEndurance(mem, reads, malnutrition, met, dtHours)
    local endurance = reads.endurance
    if endurance == nil then
        return
    end
    local previous = mem.lastEndurance
    mem.lastEndurance = endurance
    if previous == nil or Runtime.isCompatEnduranceActive() then
        mem.last.enduranceRegenScale = 1
        mem.last.enduranceDrain = 0
        return
    end
    local controlled = endurance
    local delta = endurance - previous
    local regenScale = 1
    local drain = 0
    if delta > 0 then
        regenScale = Model.enduranceRegenScale(malnutrition)
        controlled = previous + delta * regenScale
    elseif malnutrition > Model.MALNUTRITION_ENDURANCE_ONSET then
        drain = Model.enduranceActivityDrainPerHour(malnutrition, met) * dtHours
        controlled = controlled - drain
    end
    controlled = clamp(controlled, 0, 1)
    if math.abs(controlled - endurance) > WRITE_EPSILON then
        setStat(reads.stats, "ENDURANCE", controlled)
    end
    mem.lastEndurance = controlled
    mem.last.enduranceRegenScale = regenScale
    mem.last.enduranceDrain = drain
end

local function writeBack(reads, prev, out)
    if math.abs(out.hunger - reads.hunger) > WRITE_EPSILON then
        setStat(reads.stats, "HUNGER", out.hunger)
    end
    if math.abs(out.calories - reads.calories) > WRITE_EPSILON then
        safeCall(reads.nutrition, "setCalories", out.calories)
    end
    if math.abs(out.weight - reads.weight) > WRITE_EPSILON then
        safeCall(reads.nutrition, "setWeight", out.weight)
    end
    if math.abs(out.timer - reads.timer) > WRITE_EPSILON then
        safeCall(reads.bodyDamage, "setHealthFromFoodTimer", out.timer)
    end
    prev.calories = out.calories
    prev.hunger = out.hunger
    prev.weight = out.weight
    prev.timer = out.timer
end

local function advance(playerObj, mem, persisted, reads, worldHours, force)
    local elapsed = worldHours - (mem.lastWorldHours or worldHours)
    if elapsed < 0 or elapsed >= Runtime.GAP_HOURS then
        -- Save load, MP reconnect, or clock jump: resume from current vanilla values without catch-up.
        seedMemory(mem, reads, worldHours)
        return false
    end
    if elapsed <= 0 and not force then
        return false
    end
    mem.lastWorldHours = worldHours

    local workload = Workload.sampleForAuthority(playerObj)
    local traits = readTraits(playerObj)
    local ctx = {
        met = workload.met,
        asleep = workload.asleep,
        traits = traits,
        burnMultiplier = Settings.getEnergyBurnMultiplier(),
        appetiteMultiplier = Settings.getAppetiteRateMultiplier() * Settings.getVanillaStatsDecreaseMultiplier(),
    }

    local prev = mem.prev
    local obs = {
        calories = reads.calories,
        hunger = reads.hunger,
        timer = reads.timer,
        weight = reads.weight,
        fatsIn = math.max(0, reads.fats - (mem.prevFats or reads.fats)),
        proteinsIn = math.max(0, reads.proteins - (mem.prevProteins or reads.proteins)),
    }
    local obsFats, obsProteins = obs.fatsIn, obs.proteinsIn

    -- Long ticks (sleep, fast-forward) are split; only the first sub-step carries vanilla's changes.
    local remaining = elapsed
    local intake, weightDelta, fill, out = 0, 0, 0, nil
    local dropRaw, dropApplied = 0, 0
    local first = true
    repeat
        local dt = math.min(remaining, Runtime.STEP_HOURS)
        remaining = remaining - dt
        ctx.dtHours = dt
        ctx.vanillaBurnPerHour = mem.vanillaBurnPerHour
        out = Model.step(prev, obs, ctx)
        if first then
            mem.vanillaBurnPerHour = out.vanillaBurnPerHour
            dropRaw, dropApplied = out.hungerDropRaw, out.hungerDrop
            first = false
        end
        intake = intake + out.intakeKcal
        weightDelta = weightDelta + out.weightDelta
        fill = fill + out.fill
        prev = { calories = out.calories, hunger = out.hunger, timer = out.timer, weight = out.weight }
        obs = { calories = out.calories, hunger = out.hunger, timer = out.timer, weight = out.weight, fatsIn = 0, proteinsIn = 0 }
    until remaining <= 0

    writeBack(reads, mem.prev, out)
    mem.prevFats = reads.fats
    mem.prevProteins = reads.proteins

    if math.abs(out.weight - (mem.traitWeight or out.weight)) >= Runtime.TRAIT_WEIGHT_STEP_KG or out.externalWeight then
        safeCall(reads.nutrition, "applyTraitFromWeight")
        mem.traitWeight = out.weight
    end

    local target, calorieTarget, proteinTarget = Model.malnutritionTargets(out.calories, reads.proteins)
    local malnutrition = Model.advanceMalnutrition(persisted.malnutrition, target, elapsed)
    persisted.malnutrition = malnutrition
    if elapsed > 0 then
        local weeklyRate = (weightDelta / elapsed) * 168
        local trend = tonumber(persisted.trendKgPerWeek) or 0
        persisted.trendKgPerWeek = trend + (weeklyRate - trend) * math.min(1, elapsed / Runtime.TREND_HOURS)
    end

    controlEndurance(mem, reads, malnutrition, workload.met, elapsed)
    Runtime.applyBodyTuning(reads.bodyDamage, malnutrition)

    local last = mem.last
    last.malnutritionTarget = target
    last.calorieTarget = calorieTarget
    last.proteinTarget = proteinTarget
    last.burnPerHour = out.burnPerHour
    last.hungerRatePerHour = out.hungerRatePerHour
    last.met = workload.met
    last.asleep = workload.asleep
    last.workloadSource = workload.source
    if intake > 0 then
        -- Cumulative totals let observers diff meals without missing ticks between polls.
        last.intakeKcalTotal = (last.intakeKcalTotal or 0) + intake
        last.intakeFillTotal = (last.intakeFillTotal or 0) + fill
        last.intakeFatsTotal = (last.intakeFatsTotal or 0) + obsFats
        last.intakeProteinsTotal = (last.intakeProteinsTotal or 0) + obsProteins
        last.hungerDropRawTotal = (last.hungerDropRawTotal or 0) + dropRaw
        last.hungerDropAppliedTotal = (last.hungerDropAppliedTotal or 0) + dropApplied
        last.lastIntakeWorldHours = worldHours
    end
    return true
end

function Runtime.tick(playerObj, force)
    if not Runtime.isAuthority() or not CoreUtils.isActivePlayer(playerObj) then
        return false
    end
    local mem = ensureMemory(playerObj)
    if not mem then
        return false
    end
    local now = Workload.wallSeconds()
    if not force and (now - mem.lastTickWall) < Runtime.TICK_SECONDS then
        return false
    end
    mem.lastTickWall = now
    local reads = readVanilla(playerObj)
    local persisted = getPersisted(playerObj)
    local worldHours = CoreUtils.getWorldHours()
    if not reads or not persisted or not worldHours then
        return false
    end
    return advance(playerObj, mem, persisted, reads, worldHours, force)
end

-- Correct the eat-time hunger drop immediately instead of on the next throttled tick.
function Runtime.afterEat(playerObj)
    if not Runtime.tick(playerObj, true) then
        return
    end
    if type(isServer) == "function" and isServer() and type(syncPlayerStats) == "function" then
        syncPlayerStats(playerObj, -1)
        if SyncPlayerStatsPacket and CharacterStat and CharacterStat.HUNGER then
            local okMask, mask = pcall(SyncPlayerStatsPacket.getBitMaskForStat, CharacterStat.HUNGER)
            if okMask and tonumber(mask) and mask ~= 0 then
                syncPlayerStats(playerObj, mask)
            end
        end
    end
end

-- Display data for UI. Authority reads its own memory; MP clients use the server snapshot.
function Runtime.buildDisplaySnapshot(playerObj)
    local persisted = getPersisted(playerObj)
    local mem = memoryByPlayer[playerObj]
    if not persisted then
        return nil
    end
    local last = mem and mem.last or {}
    local target = tonumber(last.malnutritionTarget) or 0
    return {
        malnutrition = tonumber(persisted.malnutrition) or 0,
        malnutritionTarget = target,
        calorieTarget = tonumber(last.calorieTarget) or 0,
        proteinTarget = tonumber(last.proteinTarget) or 0,
        trendKgPerWeek = tonumber(persisted.trendKgPerWeek) or 0,
        burnPerHour = tonumber(last.burnPerHour) or 0,
        hungerRatePerHour = tonumber(last.hungerRatePerHour) or 0,
        met = tonumber(last.met) or Model.MET_REST,
        asleep = last.asleep == true,
        enduranceRegenScale = tonumber(last.enduranceRegenScale) or 1,
    }
end

-- Read-only view of authority internals for diagnostics.
function Runtime.inspect(playerObj)
    local persisted, modData = getPersisted(playerObj)
    return memoryByPlayer[playerObj], persisted, modData
end

function Runtime.importDisplaySnapshot(playerObj, snapshot)
    if not playerObj or type(snapshot) ~= "table" then
        return
    end
    displayByPlayer[playerObj] = snapshot
    Runtime.applyBodyTuning(CoreUtils.getPlayerBodyDamage(playerObj), tonumber(snapshot.malnutrition) or 0)
end

function Runtime.getMalnutrition(playerObj)
    local snapshot
    if Runtime.isMPClient() then
        snapshot = displayByPlayer[playerObj]
    else
        snapshot = Runtime.buildDisplaySnapshot(playerObj)
    end
    return snapshot and tonumber(snapshot.malnutrition) or 0
end

function Runtime.getDisplay(playerObj)
    if not playerObj then
        return nil
    end
    local snapshot
    if Runtime.isMPClient() then
        snapshot = displayByPlayer[playerObj]
    else
        snapshot = Runtime.buildDisplaySnapshot(playerObj)
    end
    local reads = readVanilla(playerObj)
    if not snapshot or not reads then
        return nil
    end
    local view = {}
    for key, value in pairs(snapshot) do
        view[key] = value
    end
    view.calories = reads.calories
    view.proteins = reads.proteins
    view.fats = reads.fats
    view.carbs = reads.carbs
    view.hunger = reads.hunger
    view.stomachTimer = reads.timer
    view.weightKg = reads.weight
    view.stomachLevel = Model.stomachLevel(reads.timer)
    view.stomachHoursLeft = math.max(0, reads.timer) / Model.STOMACH_UNITS_PER_HOUR
    view.cause = Model.malnutritionCause(view.calorieTarget, view.proteinTarget)
    view.reserveZone = Model.reserveZone(reads.calories)
    view.recoveryMultiplier = Model.naturalRecoveryMultiplier(view.malnutrition)
    return view
end

local function onPlayerUpdate(playerObj)
    Runtime.tick(playerObj, false)
end

local function onPlayerDeath(playerObj)
    Runtime.forget(playerObj)
end

local function wrapEatAction()
    if type(ISEatFoodAction) ~= "table" or ISEatFoodAction.__nmsWrapped then
        return
    end
    local original = ISEatFoodAction.complete
    if type(original) ~= "function" then
        return
    end
    ISEatFoodAction.__nmsWrapped = true
    ISEatFoodAction.complete = function(self, ...)
        local result = original(self, ...)
        if Runtime.isAuthority() and self and self.character then
            Runtime.afterEat(self.character)
        end
        return result
    end
end

function Runtime.install()
    if Runtime._installed then
        return
    end
    Runtime._installed = true
    -- Dedicated servers never fire OnPlayerUpdate for connected (remote) players; MPServer ticks them instead.
    if Events and Events.OnPlayerUpdate and not (type(isServer) == "function" and isServer()) then
        Events.OnPlayerUpdate.Add(onPlayerUpdate)
    end
    if Events and Events.OnPlayerDeath then
        Events.OnPlayerDeath.Add(onPlayerDeath)
    end
    if Events and Events.OnGameStart then
        Events.OnGameStart.Add(wrapEatAction)
    end
    if Events and Events.OnServerStarted then
        Events.OnServerStarted.Add(wrapEatAction)
    end
end

return Runtime
