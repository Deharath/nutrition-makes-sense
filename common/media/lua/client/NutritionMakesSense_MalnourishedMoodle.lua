NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}

local MoodleUI = {}
NutritionMakesSense.MalnourishedMoodle = MoodleUI

local ACTIVE_THRESHOLD = tonumber(Metabolism.DEPRIVATION_PENALTY_ONSET) or 0.10
local LEVEL_TWO_THRESHOLD = 0.30
local LEVEL_THREE_THRESHOLD = 0.60
local LEVEL_FOUR_THRESHOLD = 0.85
local TOP_Y_OFFSET = 120
local RIGHT_X_OFFSET = 10
local SPACING = 10
local TOOLTIP_MARGIN = 8
local TOOLTIP_PADDING = 6
local OSCILLATOR_DECEL = 0.84
local OSCILLATOR_RATE = 0.8
local OSCILLATOR_SCALAR = 15.6
local ICON_PATH = "media/ui/NMS_Malnourished.png"

local C_TEXT = { a = 1.0, r = 1.0, g = 1.0, b = 1.0 }
local C_TEXT_DIM = { a = 1.0, r = 0.8, g = 0.8, b = 0.8 }

local instances = {}
local VANILLA_MOODLE_TYPES = {
    "ENDURANCE",
    "TIRED",
    "HUNGRY",
    "PANIC",
    "SICK",
    "BORED",
    "UNHAPPY",
    "BLEEDING",
    "WET",
    "HAS_A_COLD",
    "ANGRY",
    "STRESS",
    "THIRST",
    "INJURED",
    "PAIN",
    "HEAVY_LOAD",
    "DRUNK",
    "DEAD",
    "ZOMBIE",
    "HYPERTHERMIA",
    "HYPOTHERMIA",
    "WINDCHILL",
    "CANT_SPRINT",
    "UNCOMFORTABLE",
    "NOXIOUS_SMELL",
    "FOOD_EATEN",
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getPlayerState(player)
    if not player or not Runtime.getStateCopy then
        return nil
    end
    return Runtime.getStateCopy(player)
end

local function getValueAndLevel(player)
    local state = getPlayerState(player)
    local deprivation = tonumber(state and state.deprivation) or 0
    local target = Metabolism.getDeprivationTarget and Metabolism.getDeprivationTarget(tonumber(state and state.fuel) or 0) or deprivation
    local direction = "stable"
    if target > deprivation + 0.01 then
        direction = "worsening"
    elseif target < deprivation - 0.01 then
        direction = "recovering"
    end

    local level = 0
    if deprivation >= LEVEL_FOUR_THRESHOLD then
        level = 4
    elseif deprivation >= LEVEL_THREE_THRESHOLD then
        level = 3
    elseif deprivation >= LEVEL_TWO_THRESHOLD then
        level = 2
    elseif deprivation >= ACTIVE_THRESHOLD then
        level = 1
    end

    return deprivation, level, direction
end

local function getMoodleSize()
    local core = getCore and getCore() or nil
    local option = core and core.getOptionMoodleSize and core:getOptionMoodleSize() or 1
    if option < 5.5 then
        return math.floor(32 * (0.5 + 0.5 * option))
    end
    if option < 6.5 then
        return 128
    end
    local fontSize = core and core.getOptionFontSizeReal and core:getOptionFontSizeReal() or 1
    return math.floor(32 * (0.5 + 0.5 * fontSize))
end

local function getVanillaActiveMoodleCount(player)
    if not player or not player.getMoodles then
        return 0
    end
    local moodles = player:getMoodles()
    if not moodles then
        return 0
    end

    local count = 0
    for _, fieldName in ipairs(VANILLA_MOODLE_TYPES) do
        local moodleType = MoodleType and MoodleType[fieldName] or nil
        if moodleType then
            local level = tonumber(moodles:getMoodleLevel(moodleType)) or 0
            if (moodleType ~= MoodleType.FOOD_EATEN and level ~= 0) or level >= 3 then
                count = count + 1
            end
        end
    end
    return count
end

local function getAiteronMoodleCount(player)
    local manager = player and player.getModData and player:getModData().MoodleManager or nil
    if not manager or not manager.moodles then
        return 0
    end

    local count = 0
    for _, moodleObj in pairs(manager.moodles) do
        if moodleObj and moodleObj.getLevel and moodleObj:getLevel() > 0 then
            count = count + 1
        end
    end
    return count
end

local function getFrameworkMoodleCount(player)
    local moodles = player and player.getModData and player:getModData().Moodles or nil
    if type(moodles) ~= "table" then
        return 0
    end

    local count = 0
    for _, entry in pairs(moodles) do
        if type(entry) == "table" and (tonumber(entry.Level) or 0) > 0 then
            count = count + 1
        end
    end
    return count
end

local function clearVanillaMoodleTooltip(player)
    local playerNum = player and player.getPlayerNum and player:getPlayerNum() or nil
    if playerNum == nil or not UIManager or not UIManager.getMoodleUI then
        return
    end

    local moodleUi = UIManager.getMoodleUI(playerNum)
    if not moodleUi or type(moodleUi.onMouseMoveOutside) ~= "function" then
        return
    end

    pcall(moodleUi.onMouseMoveOutside, moodleUi, 0, 0)
end

local function getVanillaBadMoodleARGB(level)
    local core = getCore and getCore() or nil
    local bad = core and core.getBadHighlitedColor and core:getBadHighlitedColor() or nil
    local gray = Color and Color.gray or nil
    if not bad or not gray then
        return 1, 1, 1, 1
    end

    local severity = clamp((tonumber(level) or 1) / 4, 0, 1)
    local grayWeight = 1 - severity
    local badWeight = severity
    return
        (gray:getAlphaFloat() * grayWeight) + (bad:getA() * badWeight),
        (gray:getRedFloat() * grayWeight) + (bad:getR() * badWeight),
        (gray:getGreenFloat() * grayWeight) + (bad:getG() * badWeight),
        (gray:getBlueFloat() * grayWeight) + (bad:getB() * badWeight)
end

local function getFallbackIconPath(size)
    return string.format("media/ui/Moodles/%d/Status_Hunger.png", size)
end

local NMSMalnourishedMoodle = ISUIElement:derive("NMSMalnourishedMoodle")

function NMSMalnourishedMoodle:updateTextures(size)
    if self.size == size and self.backgroundTexture and self.borderTexture then
        return
    end

    self.size = size
    self:setWidth(size)
    self:setHeight(size)
    self.backgroundTexture = getTexture(string.format("media/ui/Moodles/%d/_Moodles_BGsolid.png", size))
    self.borderTexture = getTexture(string.format("media/ui/Moodles/%d/_Moodles_BGoutline.png", size))
    self.iconTexture = getTexture(ICON_PATH) or getTexture(getFallbackIconPath(size))
end

function NMSMalnourishedMoodle:updateOscillator()
    if self.oscillationLevel <= 0 then
        self.oscillationOffset = 0
        self.oscillationStep = 0
        return
    end

    local fpsFrac = PerformanceSettings and PerformanceSettings.getLockFPS and (PerformanceSettings.getLockFPS() / 30.0) or 1
    if not fpsFrac or fpsFrac <= 0 then
        fpsFrac = 1
    end

    self.oscillationLevel = self.oscillationLevel - self.oscillationLevel * (1.0 - OSCILLATOR_DECEL) / fpsFrac
    if self.oscillationLevel < 0.015 then
        self.oscillationLevel = 0
        self.oscillationOffset = 0
        self.oscillationStep = 0
        return
    end

    self.oscillationStep = self.oscillationStep + OSCILLATOR_RATE / fpsFrac
    self.oscillationOffset = math.sin(self.oscillationStep) * OSCILLATOR_SCALAR * self.oscillationLevel * (self.size / 32)
end

function NMSMalnourishedMoodle:getPosition()
    local playerNum = self.player and self.player.getPlayerNum and self.player:getPlayerNum() or 0
    local size = getMoodleSize()
    self:updateTextures(size)

    local x = getPlayerScreenLeft(playerNum) + getPlayerScreenWidth(playerNum) - RIGHT_X_OFFSET - size
    local y = getPlayerScreenTop(playerNum) + TOP_Y_OFFSET
    local occupiedSlots = getVanillaActiveMoodleCount(self.player)
        + getAiteronMoodleCount(self.player)
        + getFrameworkMoodleCount(self.player)
    y = y + ((size + SPACING) * occupiedSlots)
    return x, y
end

function NMSMalnourishedMoodle:getTitle()
    return getText(string.format("Moodles_Malnourished_lvl%d", self.level))
end

function NMSMalnourishedMoodle:getDescription()
    return getText(string.format("Moodles_Malnourished_desc_lvl%d", self.level))
end

function NMSMalnourishedMoodle:syncVisibility()
    local shouldShow = self.level > 0
    if shouldShow and not self.addedToUIManager then
        self:addToUIManager()
        self.addedToUIManager = true
    elseif (not shouldShow) and self.addedToUIManager then
        self:removeFromUIManager()
        self.addedToUIManager = false
    end
end

function NMSMalnourishedMoodle:updateFromState()
    if not self.player then
        self.level = 0
        self.value = 0
        self.direction = "stable"
        self:syncVisibility()
        return
    end

    local deprivation, level, direction = getValueAndLevel(self.player)
    if level ~= self.level then
        self.oscillationLevel = 1
    end
    self.value = deprivation
    self.level = level
    self.direction = direction
    self:syncVisibility()
end

function NMSMalnourishedMoodle:renderTooltip()
    if self.level <= 0 or not self:isMouseOver() then
        return
    end

    clearVanillaMoodleTooltip(self.player)

    local title = self:getTitle()
    local description = self:getDescription()
    local titleWidth = getTextManager():MeasureStringX(UIFont.Small, title)
    local descWidth = getTextManager():MeasureStringX(UIFont.Small, description)
    local textWidth = math.max(titleWidth, descWidth)
    local titleHeight = getTextManager():MeasureStringY(UIFont.Small, title)
    local descHeight = getTextManager():MeasureStringY(UIFont.Small, description)
    local tooltipWidth = textWidth + (TOOLTIP_PADDING * 2)
    local tooltipHeight = titleHeight + descHeight + (TOOLTIP_PADDING * 3)
    local tooltipX = -tooltipWidth - TOOLTIP_MARGIN
    local tooltipY = math.max(0, math.floor((self.size - tooltipHeight) / 2))

    self:drawRect(tooltipX, tooltipY, tooltipWidth, tooltipHeight, 0.78, 0.06, 0.05, 0.05)
    self:drawTextRight(title, -TOOLTIP_PADDING - TOOLTIP_MARGIN, tooltipY + TOOLTIP_PADDING, C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Small)
    self:drawTextRight(description, -TOOLTIP_PADDING - TOOLTIP_MARGIN, tooltipY + TOOLTIP_PADDING + titleHeight + TOOLTIP_PADDING, C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, C_TEXT_DIM.a, UIFont.Small)
end

function NMSMalnourishedMoodle:render()
    self:updateFromState()
    if self.level <= 0 then
        return
    end

    local x, y = self:getPosition()
    if x ~= self:getX() then self:setX(x) end
    if y ~= self:getY() then self:setY(y) end

    self:updateOscillator()
    local offset = self.oscillationOffset or 0
    local bgA, bgR, bgG, bgB = getVanillaBadMoodleARGB(self.level)

    if self.backgroundTexture then
        self:drawTextureScaled(self.backgroundTexture, offset, 0, self.size, self.size, bgA, bgR, bgG, bgB)
    else
        self:drawRect(offset, 0, self.size, self.size, bgA, bgR, bgG, bgB)
    end

    if self.iconTexture then
        self:drawTextureScaled(self.iconTexture, offset, 0, self.size, self.size, 1, 1, 1, 1)
    else
        self:drawRectBorder(offset, 0, self.size, self.size, 1, 1, 1, 1)
        self:drawTextCentre("N", offset + (self.size / 2), math.max(0, (self.size - getTextManager():getFontHeight(UIFont.Medium)) / 2), C_TEXT.r, C_TEXT.g, C_TEXT.b, C_TEXT.a, UIFont.Medium)
    end

    if self.borderTexture then
        self:drawTextureScaled(self.borderTexture, offset, 0, self.size, self.size, 1, 1, 1, 1)
    else
        self:drawRectBorder(offset, 0, self.size, self.size, 1, 1, 1, 1)
    end

    self:renderTooltip()
end

function NMSMalnourishedMoodle:new(player)
    local size = getMoodleSize()
    local o = ISUIElement:new(0, 0, size, size)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.level = 0
    o.value = 0
    o.direction = "stable"
    o.size = size
    o.oscillationLevel = 0
    o.oscillationOffset = 0
    o.oscillationStep = 0
    o.backgroundTexture = nil
    o.borderTexture = nil
    o.iconTexture = nil
    o.addedToUIManager = false
    o:setAnchorRight(true)
    o:setAnchorTop(true)
    o:setWantKeyEvents(false)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o:initialise()
    return o
end

local function getOrCreateInstance(playerNum)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    if not player then
        return nil
    end
    local existing = instances[playerNum]
    if existing then
        existing.player = player
        return existing
    end

    local instance = NMSMalnourishedMoodle:new(player)
    instances[playerNum] = instance
    return instance
end

local function updatePlayer(player)
    if not player or not player.getPlayerNum then
        return
    end
    local playerNum = player:getPlayerNum()
    local instance = getOrCreateInstance(playerNum)
    if instance then
        instance.player = player
        instance:updateFromState()
    end
end

local function onCreatePlayer(playerNum)
    getOrCreateInstance(playerNum)
end

local function onPlayerUpdate(player)
    updatePlayer(player)
end

local function cleanup()
    for _, instance in pairs(instances) do
        if instance and instance.addedToUIManager then
            instance:removeFromUIManager()
            instance.addedToUIManager = false
        end
    end
    instances = {}
end

local function install()
    for playerNum = 0, 3 do
        getOrCreateInstance(playerNum)
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(install)
end
if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(onCreatePlayer)
end
if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end
if Events and Events.OnGameExit then
    Events.OnGameExit.Add(cleanup)
end
