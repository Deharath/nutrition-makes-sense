NutritionMakesSense = NutritionMakesSense or {}

-- Shared drawing vocabulary: one palette, pips, gauges and trend chevrons for every NMS surface.
local Draw = NutritionMakesSense.Draw or {}
NutritionMakesSense.Draw = Draw

local function rgb(r, g, b)
    return { r = r, g = g, b = b }
end

Draw.C = {
    text = rgb(0.92, 0.92, 0.88),
    label = rgb(0.70, 0.71, 0.66),
    dim = rgb(0.52, 0.53, 0.50),
    track = rgb(1, 1, 1),
    stomach = rgb(0.93, 0.78, 0.47),
    energy = rgb(0.96, 0.60, 0.27),
    protein = rgb(0.60, 0.80, 0.50),
    hunger = rgb(0.86, 0.62, 0.40),
    weight = rgb(0.62, 0.72, 0.84),
    warn = rgb(0.92, 0.74, 0.30),
    good = rgb(0.45, 0.80, 0.45),
    bad = rgb(0.88, 0.34, 0.30),
}

Draw.TRACK_ALPHA = 0.13

local function colorFromCore(getterName, fallback)
    local core = type(getCore) == "function" and getCore() or nil
    local info = core and core[getterName] and core[getterName](core) or nil
    if info and info.getR then
        return rgb(info:getR(), info:getG(), info:getB())
    end
    return fallback
end

-- Vanilla good/bad colours follow the colour-blind accessibility option.
function Draw.good()
    return colorFromCore("getGoodHighlitedColor", Draw.C.good)
end

function Draw.bad()
    return colorFromCore("getBadHighlitedColor", Draw.C.bad)
end

function Draw.mix(a, b, t)
    t = math.max(0, math.min(1, t))
    return rgb(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
end

-- Severity 0..1 -> good .. warn .. bad.
function Draw.severity(t)
    t = math.max(0, math.min(1, tonumber(t) or 0))
    if t < 0.5 then
        return Draw.mix(Draw.good(), Draw.C.warn, t * 2)
    end
    return Draw.mix(Draw.C.warn, Draw.bad(), (t - 0.5) * 2)
end

function Draw.fontHeight(font)
    local tm = type(getTextManager) == "function" and getTextManager() or nil
    return tm and tm:getFontHeight(font) or 14
end

function Draw.textWidth(font, text)
    local tm = type(getTextManager) == "function" and getTextManager() or nil
    return tm and tm:MeasureStringX(font, tostring(text or "")) or 0
end

-- Rect sinks: fn(x, y, w, h, color, alpha).
function Draw.elementSink(el)
    return function(x, y, w, h, c, a)
        el:drawRect(x, y, w, h, a, c.r, c.g, c.b)
    end
end

function Draw.tooltipSink(tooltip)
    return function(x, y, w, h, c, a)
        tooltip:DrawTextureScaledColor(nil, x, y, w, h, c.r, c.g, c.b, a)
    end
end

function Draw.pipGeometry(lineHeight)
    local size = math.max(5, math.floor(lineHeight * 0.5))
    local gap = math.max(2, math.floor(size * 0.45))
    return size, gap
end

function Draw.pipStripWidth(count, size, gap)
    return count * size + (count - 1) * gap
end

-- Pips filled to `value` (in pip units, quarter resolution); returns the strip width.
function Draw.pips(sink, x, y, count, value, size, gap, color, alpha)
    local v = math.max(0, tonumber(value) or 0)
    local q = math.floor(v * 4 + 0.5) / 4
    if v > 0 and q == 0 then
        q = 0.25
    end
    for i = 1, count do
        local px = x + (i - 1) * (size + gap)
        sink(px, y, size, size, Draw.C.track, Draw.TRACK_ALPHA)
        local fill = math.max(0, math.min(1, q - (i - 1)))
        if fill > 0 then
            sink(px, y, math.max(1, math.floor(size * fill + 0.5)), size, color, alpha or 1)
        end
    end
    return Draw.pipStripWidth(count, size, gap)
end

local function toX(spec, x, w, value)
    local t = (value - spec.min) / (spec.max - spec.min)
    return x + math.floor(w * math.max(0, math.min(1, t)) + 0.5)
end

--[[
Horizontal gauge.
spec = { min, max, value, color, from (fill origin, default min), ghost (value), ghostColor,
         bands = { {from, to, color, alpha} }, notches = { value, ... } }
]]
function Draw.gauge(el, x, y, w, h, spec)
    local sink = Draw.elementSink(el)
    sink(x, y, w, h, Draw.C.track, Draw.TRACK_ALPHA)
    for _, band in ipairs(spec.bands or {}) do
        local x0, x1 = toX(spec, x, w, band[1]), toX(spec, x, w, band[2])
        if x1 > x0 then
            sink(x0, y, x1 - x0, h, band[3], band[4] or 0.12)
        end
    end
    local origin = spec.from or spec.min
    if spec.ghost then
        local g0, g1 = toX(spec, x, w, origin), toX(spec, x, w, spec.ghost)
        if g1 ~= g0 then
            sink(math.min(g0, g1), y, math.abs(g1 - g0), h, spec.ghostColor or spec.color, 0.28)
        end
    end
    local v0, v1 = toX(spec, x, w, origin), toX(spec, x, w, spec.value)
    if v1 ~= v0 then
        sink(math.min(v0, v1), y, math.abs(v1 - v0), h, spec.color, 0.95)
    end
    for _, notch in ipairs(spec.notches or {}) do
        local nx = toX(spec, x, w, notch)
        if nx > x and nx < x + w then
            sink(nx, y - 1, 1, h + 2, Draw.C.text, 0.45)
        end
    end
    if spec.marker then
        local mx = toX(spec, x, w, spec.value)
        sink(math.max(x, mx - 1), y - 2, 2, h + 4, Draw.C.text, 0.95)
    end
end

local chevronUp, chevronDown
function Draw.chevron(el, x, y, up, color)
    if not chevronUp then
        chevronUp = getTexture("media/ui/Moodle_chevron_up.png")
        chevronDown = getTexture("media/ui/Moodle_chevron_down.png")
    end
    local tex = up and chevronUp or chevronDown
    if tex then
        el:drawTextureScaled(tex, x, y, 10, 5, 1, color.r, color.g, color.b)
    end
    return 10
end

-- "2 h 15 m", "40 m", "3 d".
function Draw.duration(hours)
    local h = tonumber(hours)
    if not h then
        return nil
    end
    if h >= 14 * 24 then
        return string.format("%d wk", math.floor(h / 168 + 0.5))
    end
    if h >= 48 then
        return string.format("%d d", math.floor(h / 24 + 0.5))
    end
    if h >= 12 then
        return string.format("%d h", math.floor(h + 0.5))
    end
    if h >= 1 then
        local whole = math.floor(h)
        local minutes = math.floor((h - whole) * 60 / 5 + 0.5) * 5
        if minutes >= 60 then
            whole, minutes = whole + 1, 0
        end
        return minutes > 0 and string.format("%d h %d m", whole, minutes) or string.format("%d h", whole)
    end
    return string.format("%d m", math.max(5, math.floor(h * 60 / 5 + 0.5) * 5))
end

-- In-game clock time `hours` from now, honouring the 12/24 h option.
function Draw.clockIn(hours)
    local gt = type(getGameTime) == "function" and getGameTime() or nil
    if not gt or not hours then
        return nil
    end
    local tod = (gt:getTimeOfDay() + hours) % 24
    local hh = math.floor(tod)
    local mm = math.floor((tod - hh) * 60 / 5) * 5
    local core = getCore and getCore() or nil
    if core and core.getOptionClock24Hour and not core:getOptionClock24Hour() then
        local suffix = hh >= 12 and "pm" or "am"
        local h12 = hh % 12
        return string.format("%d:%02d %s", h12 == 0 and 12 or h12, mm, suffix)
    end
    return string.format("%02d:%02d", hh, mm)
end

return Draw
