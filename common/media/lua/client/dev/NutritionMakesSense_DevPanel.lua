NutritionMakesSense = NutritionMakesSense or {}

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ui/NutritionMakesSense_Draw"
require "NutritionMakesSense_Model"
require "dev/NutritionMakesSense_DevHud"

-- Dev-build only (stripped from release). Live internals, 24 h history, meal log, state tools.
local DevPanel = NutritionMakesSense.DevPanel or {}
NutritionMakesSense.DevPanel = DevPanel

local Draw = NutritionMakesSense.Draw
local Model = NutritionMakesSense.Model
local DevHud = NutritionMakesSense.DevHud
local C = Draw.C

local FONT = UIFont.Small
local HISTORY_HOURS = 24
local LAYOUT_NAME = "nms_dev"

local instance = nil

local function reads()
    local s = DevHud.state
    return s and s.reads or nil
end

-- Each tool computes an absolute value from current reads at click time.
local TOOLS = {
    { "kcal -500", "calories", function(r) return r.calories - 500 end },
    { "kcal +500", "calories", function(r) return r.calories + 500 end },
    { "kcal 800", "calories", function() return Model.RESERVE_SET_POINT end },
    { "P -150", "proteins", function(r) return r.proteins - 150 end },
    { "P +150", "proteins", function(r) return r.proteins + 150 end },
    { "Spawn food", "spawn", function() return 0 end },
    { "M 0", "malnutrition", function() return 0 end },
    { "M +0.3", "malnutrition", function() return (DevHud.display and DevHud.display.malnutrition or 0) + 0.3 end },
    { "Stomach 0", "stomach", function() return 0 end },
    { "Stomach +2h", "stomach", function(r) return r.timer / Model.STOMACH_UNITS_PER_HOUR + 2 end },
    { "Hunger 0", "hunger", function() return 0 end },
    { "Hunger +0.3", "hunger", function(r) return r.hunger + 0.3 end },
    { "Weight -5", "weightDelta", function() return -5 end },
    { "Weight +5", "weightDelta", function() return 5 end },
    { "Reset save", "reset", function() return 0 end },
}
local TOOL_COLUMNS = 6

local NMS_DevPanel = ISCollapsableWindow:derive("NMS_DevPanel")

function NMS_DevPanel:new(x, y)
    local fh = Draw.fontHeight(FONT)
    local o = ISCollapsableWindow.new(self, x, y, math.max(560, fh * 40), 400)
    o.fh = fh
    o.pad = 8
    o:setTitle("NMS Dev")
    o:setResizable(false)
    return o
end

function NMS_DevPanel:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = self.pad
    local bh = self.fh + 4
    local bw = math.floor((self.width - pad * 2 - (TOOL_COLUMNS - 1) * 4) / TOOL_COLUMNS)
    local top = self:titleBarHeight() + pad
    for i, tool in ipairs(TOOLS) do
        local col = (i - 1) % TOOL_COLUMNS
        local row = math.floor((i - 1) / TOOL_COLUMNS)
        local button = ISButton:new(pad + col * (bw + 4), top + row * (bh + 4), bw, bh, tool[1], self, NMS_DevPanel.onTool)
        button.internal = tool
        button:initialise()
        button:instantiate()
        self:addChild(button)
    end
    self.contentTop = top + math.ceil(#TOOLS / TOOL_COLUMNS) * (bh + 4) + pad
end

function NMS_DevPanel:onTool(button)
    local tool = button.internal
    local r = reads()
    if not r then
        return
    end
    DevHud.sendTool(tool[2], tool[3](r))
end

function NMS_DevPanel:close()
    DevPanel.hide()
end

function NMS_DevPanel:line(x, y, label, value, color)
    self:drawText(label, x, y, C.label.r, C.label.g, C.label.b, 1, FONT)
    local c = color or C.text
    self:drawText(tostring(value), x + 110, y, c.r, c.g, c.b, 1, FONT)
    return y + self.fh
end

function NMS_DevPanel:pills(y)
    local x = self.pad
    local h = self.fh + 2
    for _, c in ipairs(DevHud.checks) do
        local text = c.label .. (c.detail and (" " .. c.detail) or "")
        local w = Draw.textWidth(FONT, text) + 10
        if x + w > self.width - self.pad then
            x = self.pad
            y = y + h + 3
        end
        local col = c.ok and Draw.good() or (c.warn and C.warn or Draw.bad())
        self:drawRect(x, y, w, h, 0.22, col.r, col.g, col.b)
        self:drawRectBorder(x, y, w, h, 0.6, col.r, col.g, col.b)
        self:drawText(text, x + 5, y + 1, C.text.r, C.text.g, C.text.b, 1, FONT)
        x = x + w + 4
    end
    return y + h + self.pad
end

local function fmt(v, pattern)
    if v == nil then
        return "-"
    end
    return string.format(pattern or "%.2f", v)
end

local function traitText(t)
    local out = {}
    if t.fastMetabolism then out[#out + 1] = "FastMet" end
    if t.slowMetabolism then out[#out + 1] = "SlowMet" end
    if t.heartyAppetite then out[#out + 1] = "Hearty" end
    if t.lightEater then out[#out + 1] = "Light" end
    return #out > 0 and table.concat(out, " ") or "none"
end

function NMS_DevPanel:columns(y, s, d)
    local last, r, p = s.last or {}, s.reads or {}, s.persisted or {}
    local x1, x2 = self.pad, math.floor(self.width / 2) + 4
    local y1, y2 = y, y
    y1 = self:line(x1, y1, "mode", s.mode .. (s.compatEndurance and " +AMS endurance" or ""))
    y1 = self:line(x1, y1, "MET", fmt(last.met) .. (last.asleep and " asleep" or "") .. " " .. tostring(last.workloadSource or ""))
    y1 = self:line(x1, y1, "traits", traitText(s.traits or {}))
    y1 = self:line(x1, y1, "burn/app/stats", fmt(s.burnMultiplier) .. " / " .. fmt(s.appetiteMultiplier) .. " / " .. fmt(s.statsMultiplier))
    y1 = self:line(x1, y1, "vanilla burn", fmt(s.vanillaBurnPerHour, "%.1f kcal/h"))
    y1 = self:line(x1, y1, "tick age", fmt(s.tickAge, "%.2f s"))
    y1 = self:line(x1, y1, "healing", fmt(s.healthFromFood, "%.5f") .. " / " .. fmt(s.expectedHealthFromFood, "%.5f"))
    y1 = self:line(x1, y1, "endurance", fmt(r.endurance) .. " regen x" .. fmt(last.enduranceRegenScale))

    y2 = self:line(x2, y2, "calories", fmt(r.calories, "%.0f") .. "  " .. tostring(d and d.reserveZone or ""))
    y2 = self:line(x2, y2, "hunger", fmt(r.hunger, "%.3f") .. "  +" .. fmt(last.hungerRatePerHour, "%.3f") .. "/h")
    y2 = self:line(x2, y2, "stomach", fmt(r.timer, "%.0f") .. "  (" .. fmt((r.timer or 0) / Model.STOMACH_UNITS_PER_HOUR, "%.2f h") .. ")")
    y2 = self:line(x2, y2, "prot/fat/carb", fmt(r.proteins, "%.0f") .. " / " .. fmt(r.fats, "%.0f") .. " / " .. fmt(r.carbs, "%.0f"))
    y2 = self:line(x2, y2, "weight", fmt(r.weight, "%.2f kg") .. "  " .. fmt(p.trendKgPerWeek, "%+.2f kg/wk"))
    y2 = self:line(x2, y2, "burn", fmt(last.burnPerHour, "%.0f kcal/h"))
    y2 = self:line(x2, y2, "M -> target", fmt(p.malnutrition, "%.3f") .. " -> " .. fmt(last.malnutritionTarget, "%.3f"))
    y2 = self:line(x2, y2, "cal/prot tgt", fmt(last.calorieTarget, "%.3f") .. " / " .. fmt(last.proteinTarget, "%.3f"))
    return math.max(y1, y2) + self.pad
end

-- One 24 h sparkline; samples are columns from the baseline, meals are ticks on top.
function NMS_DevPanel:spark(y, label, key, lo, hi, color, band)
    local h = math.max(22, self.fh * 2)
    local lx = self.pad
    local gx = self.pad + 90
    local gw = self.width - gx - self.pad
    self:drawText(label, lx, y + math.floor((h - self.fh) / 2), C.label.r, C.label.g, C.label.b, 1, FONT)
    self:drawRect(gx, y, gw, h, Draw.TRACK_ALPHA, C.track.r, C.track.g, C.track.b)
    local function toY(v)
        local t = math.max(0, math.min(1, (v - lo) / (hi - lo)))
        return y + h - math.floor(t * h + 0.5)
    end
    if band then
        local y0, y1 = toY(band[2]), toY(band[1])
        self:drawRect(gx, y0, gw, math.max(1, y1 - y0), 0.10, Draw.good().r, Draw.good().g, Draw.good().b)
    end
    local base = toY(math.max(lo, math.min(hi, 0)))
    local hist = DevHud.history
    local now = hist[#hist] and hist[#hist].t or 0
    local colW = math.max(1, math.floor(gw / (HISTORY_HOURS * 10)))
    local latest = nil
    for _, sample in ipairs(hist) do
        local age = now - sample.t
        if age <= HISTORY_HOURS and sample[key] then
            local x = gx + gw - colW - math.floor(age / HISTORY_HOURS * gw)
            local vy = toY(sample[key])
            self:drawRect(x, math.min(vy, base), colW, math.max(1, math.abs(base - vy)), 0.85, color.r, color.g, color.b)
            latest = sample[key]
        end
    end
    for _, meal in ipairs(DevHud.meals) do
        local age = now - (meal.startedAt or now)
        if age >= 0 and age <= HISTORY_HOURS then
            local x = gx + gw - 1 - math.floor(age / HISTORY_HOURS * gw)
            self:drawRect(x, y, 1, h, 0.7, C.text.r, C.text.g, C.text.b)
        end
    end
    if latest then
        self:drawTextRight(string.format(hi > 10 and "%.0f" or "%.2f", latest), self.width - self.pad - 3, y + 1,
            C.dim.r, C.dim.g, C.dim.b, 1, FONT)
    end
    return y + h + 4
end

function NMS_DevPanel:meals(y)
    self:drawText("Meals", self.pad, y, C.label.r, C.label.g, C.label.b, 1, FONT)
    y = y + self.fh
    if #DevHud.meals == 0 then
        self:drawText("none yet", self.pad, y, C.dim.r, C.dim.g, C.dim.b, 1, FONT)
        return y + self.fh
    end
    local now = DevHud.state and DevHud.state.worldHours or 0
    for i = 1, math.min(6, #DevHud.meals) do
        local m = DevHud.meals[i]
        local flagged = #m.flags > 0
        local text = string.format("%.1f h ago  %.0f kcal  stomach +%.1f h  hunger -%.0f%% (v -%.0f%%)  P %.0f  F %.0f%s",
            now - m.startedAt, m.kcal, m.fill / Model.STOMACH_UNITS_PER_HOUR, m.applied * 100, m.raw * 100,
            m.proteins, m.fats, flagged and ("  " .. table.concat(m.flags, ", ")) or "")
        local c = flagged and Draw.bad() or C.text
        self:drawText(text, self.pad, y, c.r, c.g, c.b, 1, FONT)
        y = y + self.fh
    end
    return y
end

function NMS_DevPanel:prerender()
    ISCollapsableWindow.prerender(self)
    if self.isCollapsed then
        return
    end
    local y = self.contentTop or (self:titleBarHeight() + self.pad)
    y = self:pills(y)
    local s, d = DevHud.state, DevHud.display
    if not s then
        self:drawText("no dev state yet", self.pad, y, C.dim.r, C.dim.g, C.dim.b, 1, FONT)
        y = y + self.fh
    else
        y = self:columns(y, s, d)
        y = self:spark(y, "hunger", "hunger", 0, 1, C.hunger)
        y = self:spark(y, "stomach", "timer", 0, Model.STOMACH_CAP, C.stomach)
        y = self:spark(y, "energy", "calories", -1500, 2200, C.energy, { Model.RESERVE_LOWER, Model.RESERVE_UPPER })
        y = self:spark(y, "malnourish", "m", 0, 1, Draw.bad())
        y = self:meals(y + self.pad)
    end
    local h = y + self.pad
    if math.abs(self.height - h) > 1 then
        self:setHeight(h)
    end
end

function DevPanel.show()
    if instance then
        instance:setVisible(true)
        instance:addToUIManager()
        instance:bringToTop()
        return
    end
    instance = NMS_DevPanel:new(80, 120)
    instance:initialise()
    instance:instantiate()
    instance:addToUIManager()
    if ISLayoutManager then
        ISLayoutManager.RegisterWindow(LAYOUT_NAME, ISCollapsableWindow, instance)
    end
end

function DevPanel.hide()
    if instance then
        instance:setVisible(false)
        instance:removeFromUIManager()
    end
end

function DevPanel.toggle()
    if instance and instance:isReallyVisible() then
        DevPanel.hide()
    else
        DevPanel.show()
    end
end

Events.OnCreatePlayer.Add(function(playerNum)
    if playerNum == 0 and instance then
        instance:removeFromUIManager()
        instance = nil
    end
end)

return DevPanel
