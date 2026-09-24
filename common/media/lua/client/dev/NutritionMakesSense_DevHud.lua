NutritionMakesSense = NutritionMakesSense or {}

require "ISUI/ISPanel"
require "ui/NutritionMakesSense_Draw"
require "NutritionMakesSense_Model"
require "NutritionMakesSense_Runtime"
require "NutritionMakesSense_Workload"
require "dev/NutritionMakesSense_DevTools"

-- Dev-build only (stripped from release). Load check, meal log, history, and the top-centre chip.
local DevHud = NutritionMakesSense.DevHud or {}
NutritionMakesSense.DevHud = DevHud

local Draw = NutritionMakesSense.Draw
local Model = NutritionMakesSense.Model
local Runtime = NutritionMakesSense.Runtime
local Workload = NutritionMakesSense.Workload
local DevTools = NutritionMakesSense.DevTools
local C = Draw.C

local POLL_SECONDS = 0.5
local LOAD_CHECK_SECONDS = 8
local LOAD_CHECK_GIVE_UP_SECONDS = 30
local MEAL_MERGE_HOURS = 0.25
local HISTORY_STEP_HOURS = 0.1
local HISTORY_MAX = 240
local MEALS_MAX = 12
local EXPECTED_DROP_RATIO = Model.HUNGER_DROP_SCALE

DevHud.state = nil
DevHud.display = nil
DevHud.checks = {}
DevHud.meals = {}
DevHud.history = {}

local startedAt = nil
local lastPoll = nil
local loadChecked = false
local prevTotals = nil
local chip = nil

local function log(msg)
    print("[NutritionMakesSense] [DEV] " .. tostring(msg))
end

local function isMP()
    return Runtime.isMPClient()
end

function DevHud.sendTool(op, value)
    local playerObj = getPlayer()
    if not playerObj then
        return
    end
    if isMP() then
        sendClientCommand(playerObj, DevTools.NET_MODULE, DevTools.TOOL_COMMAND, { op = op, value = value })
    else
        DevTools.apply(playerObj, op, value)
        prevTotals = nil
    end
end

local function check(list, label, ok, warnOnly, detail)
    list[#list + 1] = { label = label, ok = ok == true, warn = warnOnly == true and not ok, detail = detail }
end

function DevHud.evaluate()
    local s, d = DevHud.state, DevHud.display
    local list = {}
    if not s then
        check(list, "dev state", false, false, isMP() and "no devState from server" or "inspect failed")
        DevHud.checks = list
        return list
    end
    if isMP() then
        local age = Workload.wallSeconds() - (DevHud.stateAt or 0)
        check(list, "server data", age < 5, false, string.format("%.0fs old", age))
    end
    check(list, "runtime", s.installed)
    check(list, "ticking", s.hasMemory and (s.tickAge or 99) < 3, false,
        s.tickAge and string.format("%.1fs", s.tickAge) or "no memory")
    check(list, "eat hook", s.eatHook)
    check(list, "display", d ~= nil)
    local p = s.persisted
    check(list, "save v2", p ~= nil and p.version == Runtime.STATE_VERSION, false,
        p and p.migratedFromLegacy and "1.x migrated" or nil)
    check(list, "legacy gone", not s.legacyKeyPresent)
    check(list, "healing", s.healthFromFood and math.abs(s.healthFromFood - s.expectedHealthFromFood) < 1e-6, false,
        s.healthFromFood and string.format("%.5f", s.healthFromFood) or nil)
    check(list, "stomach cap", s.reads and s.reads.timer <= Model.STOMACH_CAP + 1, false,
        s.reads and string.format("%.0f", s.reads.timer) or nil)
    check(list, "sandbox nutrition", s.sandboxNutrition, true, not s.sandboxNutrition and "off: protein never decays" or nil)
    DevHud.checks = list
    return list
end

function DevHud.allOk()
    for _, c in ipairs(DevHud.checks) do
        if not c.ok and not c.warn then
            return false
        end
    end
    return #DevHud.checks > 0
end

local function runLoadCheck(playerObj)
    loadChecked = true
    local list = DevHud.evaluate()
    local failed, warned = {}, {}
    for _, c in ipairs(list) do
        local line = c.label .. (c.detail and (" (" .. c.detail .. ")") or "")
        log(string.format("load check %s: %s", c.label, c.ok and "OK" or (c.warn and "WARN" or "FAIL"))
            .. (c.detail and ("  " .. c.detail) or ""))
        if not c.ok then
            if c.warn then warned[#warned + 1] = line else failed[#failed + 1] = line end
        end
    end
    if #failed == 0 then
        local text = string.format("NMS dev: %d checks OK", #list - #warned)
        HaloTextHelper.addGoodText(playerObj, text)
    else
        HaloTextHelper.addBadText(playerObj, "NMS dev FAIL: " .. table.concat(failed, ", "))
    end
    for _, line in ipairs(warned) do
        HaloTextHelper.addBadText(playerObj, "NMS dev warn: " .. line)
    end
end

local function trackMeals(playerObj, s)
    local last = s.last or {}
    local totals = {
        kcal = tonumber(last.intakeKcalTotal) or 0,
        fill = tonumber(last.intakeFillTotal) or 0,
        fats = tonumber(last.intakeFatsTotal) or 0,
        proteins = tonumber(last.intakeProteinsTotal) or 0,
        raw = tonumber(last.hungerDropRawTotal) or 0,
        applied = tonumber(last.hungerDropAppliedTotal) or 0,
    }
    local prev = prevTotals
    prevTotals = totals
    if not prev or totals.kcal < prev.kcal then
        return
    end
    local dk = totals.kcal - prev.kcal
    if dk < 1 then
        return
    end
    local delta = {
        kcal = dk, fill = totals.fill - prev.fill, fats = totals.fats - prev.fats,
        proteins = totals.proteins - prev.proteins, raw = totals.raw - prev.raw, applied = totals.applied - prev.applied,
    }
    local flags = {}
    if delta.raw > 0.005 then
        local ratio = delta.applied / delta.raw
        if math.abs(ratio - EXPECTED_DROP_RATIO) > 0.05 then
            flags[#flags + 1] = string.format("drop ratio %.2f", ratio)
        end
    end
    if s.reads and s.reads.timer > Model.STOMACH_CAP + 1 then
        flags[#flags + 1] = "stomach over cap"
    end

    local now = s.worldHours or 0
    local meal = DevHud.meals[1]
    if not meal or (now - meal.at) > MEAL_MERGE_HOURS then
        meal = { startedAt = now, kcal = 0, fill = 0, fats = 0, proteins = 0, raw = 0, applied = 0, flags = {} }
        table.insert(DevHud.meals, 1, meal)
        if #DevHud.meals > MEALS_MAX then
            table.remove(DevHud.meals)
        end
    end
    meal.at = now
    for k, v in pairs(delta) do
        meal[k] = meal[k] + v
    end
    for _, f in ipairs(flags) do
        meal.flags[#meal.flags + 1] = f
    end

    local text = string.format("Ate %.0f kcal: stomach +%.1f h, hunger -%.0f%% (vanilla -%.0f%%)",
        delta.kcal, delta.fill / Model.STOMACH_UNITS_PER_HOUR, delta.applied * 100, delta.raw * 100)
    log("meal " .. text .. (#flags > 0 and ("  FLAGS: " .. table.concat(flags, ", ")) or ""))
    if #flags > 0 then
        HaloTextHelper.addBadText(playerObj, text .. " | " .. table.concat(flags, ", "))
    else
        HaloTextHelper.addGoodText(playerObj, text)
    end
end

local function sampleHistory(d, worldHours)
    local h = DevHud.history
    local lastSample = h[#h]
    if lastSample and worldHours < lastSample.t then
        DevHud.history = {}
        h = DevHud.history
        lastSample = nil
    end
    if lastSample and (worldHours - lastSample.t) < HISTORY_STEP_HOURS then
        return
    end
    h[#h + 1] = {
        t = worldHours, hunger = d.hunger, timer = d.stomachTimer, calories = d.calories,
        m = d.malnutrition, weight = d.weightKg,
    }
    while #h > HISTORY_MAX do
        table.remove(h, 1)
    end
end

local function onPlayerUpdate(playerObj)
    if playerObj ~= getPlayer() then
        return
    end
    local now = Workload.wallSeconds()
    startedAt = startedAt or now
    if lastPoll and (now - lastPoll) < POLL_SECONDS then
        return
    end
    lastPoll = now
    if not isMP() then
        DevHud.state = DevTools.inspect(playerObj)
        DevHud.stateAt = now
    end
    DevHud.display = Runtime.getDisplay(playerObj)
    local s = DevHud.state
    if s then
        trackMeals(playerObj, s)
    end
    local worldHours = s and s.worldHours or (getGameTime() and getGameTime():getWorldAgeHours())
    if DevHud.display and worldHours then
        sampleHistory(DevHud.display, worldHours)
    end
    if not loadChecked then
        local elapsed = now - startedAt
        if (elapsed >= LOAD_CHECK_SECONDS and s) or elapsed >= LOAD_CHECK_GIVE_UP_SECONDS then
            runLoadCheck(playerObj)
        end
    else
        DevHud.evaluate()
    end
end

local function onServerCommand(module, command, args)
    if module ~= DevTools.NET_MODULE or command ~= DevTools.STATE_COMMAND or type(args) ~= "table" then
        return
    end
    DevHud.state = args
    DevHud.stateAt = Workload.wallSeconds()
end

-- Chip -----------------------------------------------------------------------

local NMS_DevChip = ISPanel:derive("NMS_DevChip")

function NMS_DevChip:new(x, y)
    local fh = Draw.fontHeight(UIFont.Small)
    local o = ISPanel.new(self, x, y, 260, fh + 6)
    o.moveWithMouse = true
    o.background = false
    o.fh = fh
    return o
end

function NMS_DevChip:onMouseDown(x, y)
    self.pressX, self.pressY = self:getX(), self:getY()
    return ISPanel.onMouseDown(self, x, y)
end

function NMS_DevChip:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    if self.pressX and math.abs(self:getX() - self.pressX) < 3 and math.abs(self:getY() - self.pressY) < 3 then
        if NutritionMakesSense.DevPanel then
            NutritionMakesSense.DevPanel.toggle()
        end
    end
    self.pressX = nil
end

function NMS_DevChip:prerender()
    local d = DevHud.display
    local ok = DevHud.allOk()
    local status = loadChecked and (ok and "NMS dev OK" or "NMS dev FAIL") or "NMS dev ..."
    local text = status
    if d then
        text = string.format("%s | H %d%%  %.1f h  %d kcal  P %d  M %d%%", status,
            math.floor(d.hunger * 100 + 0.5), d.stomachHoursLeft, math.floor(d.calories + 0.5),
            math.floor(d.proteins + 0.5), math.floor(d.malnutrition * 100 + 0.5))
    end
    local w = Draw.textWidth(UIFont.Small, text) + 16
    if math.abs(w - self.width) > 1 then
        self:setWidth(w)
    end
    local edge = (not loadChecked) and C.dim or (ok and Draw.good() or Draw.bad())
    self:drawRect(0, 0, self.width, self.height, 0.72, 0.05, 0.05, 0.06)
    self:drawRect(0, 0, 3, self.height, 1, edge.r, edge.g, edge.b)
    self:drawRectBorder(0, 0, self.width, self.height, 0.35, edge.r, edge.g, edge.b)
    self:drawText(text, 9, 3, C.text.r, C.text.g, C.text.b, 1, UIFont.Small)
end

local function ensureChip()
    if chip then
        chip:removeFromUIManager()
    end
    local core = getCore()
    chip = NMS_DevChip:new(math.floor(core:getScreenWidth() / 2) - 130, 6)
    chip:initialise()
    chip:addToUIManager()
end

local function onCreatePlayer(playerNum)
    if playerNum ~= 0 then
        return
    end
    startedAt, lastPoll, loadChecked, prevTotals = nil, nil, false, nil
    DevHud.state, DevHud.display, DevHud.meals, DevHud.history = nil, nil, {}, {}
    ensureChip()
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnServerCommand.Add(onServerCommand)

return DevHud
