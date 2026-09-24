NutritionMakesSense = NutritionMakesSense or {}

require "ui/NutritionMakesSense_UIHelpers"
require "NutritionMakesSense_Model"
require "NutritionMakesSense_HealthPanelCompat"
require "ui/NutritionMakesSense_Draw"
require "NutritionMakesSense_NutritionWindow"

local UIHelpers = NutritionMakesSense.UIHelpers or {}
local CompatHelpers = NutritionMakesSense.HealthPanelCompat or {}
local HealthPanelHook = NutritionMakesSense.HealthPanelHook or {}
NutritionMakesSense.HealthPanelHook = HealthPanelHook

local UI_BORDER_SPACING = 10
local FONT = UIFont.Small
local FONT_HGT = nil

local Model = NutritionMakesSense.Model
local Draw = NutritionMakesSense.Draw
local T = UIHelpers.trf
local CHEVRON_W = 14

local C_WHITE = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
local C_DIM = { r = Draw.C.dim.r, g = Draw.C.dim.g, b = Draw.C.dim.b, a = 1.0 }

local function rgba(c)
    return { r = c.r, g = c.g, b = c.b, a = 1.0 }
end

local function getState(player)
    return UIHelpers.getDisplay(player)
end

local CAUSE_KEYS = { calories = "UI_NMS_Malnutrition_Cause_Calories", protein = "UI_NMS_Malnutrition_Cause_Protein",
    both = "UI_NMS_Malnutrition_Cause_Both" }

local function getCauseText(cause)
    return CAUSE_KEYS[cause] and T(CAUSE_KEYS[cause]) or nil
end
HealthPanelHook.getCauseText = getCauseText

-- Compact summary under the body diagram; the Nutrition window holds the detail.
local function collectLines(playerObj, state)
    local baseLines = {}
    local compatLines = type(CompatHelpers.collectExternalLines) == "function"
        and CompatHelpers.collectExternalLines(nil, playerObj)
        or {}

    if not state then
        return compatLines
    end

    local m = tonumber(state.malnutrition) or 0
    local target = tonumber(state.malnutritionTarget) or 0

    if m >= 0.02 or target >= 0.05 then
        local detailed = UIHelpers.isDetailed(playerObj)
        local levels = Model.MALNOURISHED_LEVELS
        local level = (m >= levels[3] and "Severe") or (m >= levels[2] and "Moderate") or (m >= levels[1] and "Mild") or "Slight"
        local color = rgba(Draw.severity(m / 0.6))
        local chevron = nil
        if target > m + 0.01 then
            chevron = { up = true, color = Draw.bad() }
        elseif target < m - 0.01 then
            chevron = { up = false, color = Draw.good() }
        end
        baseLines[#baseLines + 1] = {
            text = T("UI_NMS_Deprivation_Header") .. ": ",
            color = C_WHITE,
            valueText = detailed and UIHelpers.formatPercent(m * 100) or T("UI_NMS_Deprivation_Severity_" .. level),
            valueColor = color,
            chevron = chevron,
            suffixText = getCauseText(state.cause),
            suffixColor = C_DIM,
        }
        local effects = UIHelpers.effectsText(m, detailed)
        if effects then
            baseLines[#baseLines + 1] = { text = effects, color = C_DIM, indent = 12 }
        end
    end

    local deficient = (tonumber(state.proteinTarget) or 0) > 0
    if deficient or (tonumber(state.proteins) or 0) < Model.PROTEIN_LOW_WARNING then
        baseLines[#baseLines + 1] = {
            text = T("UI_NMS_Row_Protein") .. ": ",
            color = C_WHITE,
            valueText = deficient and T("UI_NMS_Protein_Deficient") or T("UI_NMS_Protein_Low"),
            valueColor = rgba(deficient and Draw.bad() or Draw.C.warn),
        }
    end

    local bodyDamage = playerObj and playerObj.getBodyDamage and playerObj:getBodyDamage() or nil
    local health = bodyDamage and tonumber(bodyDamage:getOverallBodyHealth()) or 100
    if (tonumber(state.stomachTimer) or 0) > 0 and health < 99.9 then
        baseLines[#baseLines + 1] = {
            text = T("UI_NMS_Stomach_WellFed") .. ": ",
            color = C_WHITE,
            valueText = T("UI_NMS_WellFed_Healing"),
            valueColor = rgba(Draw.good()),
        }
    end

    if type(CompatHelpers.mergeLines) == "function" then
        return CompatHelpers.mergeLines(compatLines, baseLines)
    end
    return baseLines
end

HealthPanelHook.collectLines = collectLines

local originalRender = nil
local originalUpdate = nil
local originalCreateChildren = nil

local NMS_BUTTON_GAP = 6
local hookInstallLogged = false
local hookDeferredLogged = false

local function logHook(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log("[HEALTH_PANEL_HOOK] " .. tostring(msg))
    else
        print("[NutritionMakesSense] [HEALTH_PANEL_HOOK] " .. tostring(msg))
    end
end

local function requireVanillaHealthPanel()
    pcall(require, "ISUI/ISButton")
    pcall(require, "XpSystem/ISUI/ISHealthPanel")
    return ISHealthPanel
        and type(ISHealthPanel.render) == "function"
        and type(ISHealthPanel.update) == "function"
        and type(ISHealthPanel.createChildren) == "function"
end

local function isActiveHealthPanel(self)
    return self and type(self.isReallyVisible) == "function" and self:isReallyVisible()
end

local function isTutorialMode()
    local core = type(getCore) == "function" and getCore() or nil
    return core and type(core.getGameMode) == "function" and core:getGameMode() == "Tutorial"
end

local function isElementVisible(element)
    if not element then
        return false
    end
    if type(element.isReallyVisible) == "function" then
        return element:isReallyVisible()
    end
    if type(element.isVisible) == "function" then
        return element:isVisible()
    end
    if type(element.getIsVisible) == "function" then
        return element:getIsVisible()
    end
    return element.visible ~= false
end

local function shouldShowNmsStatusButton(self)
    return isActiveHealthPanel(self) and not self.otherPlayer and not isTutorialMode()
end

local function getFitnessAnchor(self)
    local fallback = self and self.fitness or nil
    if not self then
        return fallback
    end

    local fitnessLabel = type(getText) == "function" and getText("ContextMenu_Fitness") or nil
    local children = type(self.getChildren) == "function" and self:getChildren() or self.children
    for _, child in pairs(children or {}) do
        if child ~= fallback
            and child ~= self.nmsStatusButton
            and type(child.getRight) == "function"
            and isElementVisible(child)
            and fitnessLabel
            and child.tabName == fitnessLabel then
            return child
        end
    end

    return fallback
end

local function hideNmsStatusButton(self)
    if self and self.nmsStatusButton then
        self.nmsStatusButton:setVisible(false)
    end
end

local function positionNmsStatusButton(self)
    if not self.nmsStatusButton or not self.fitness then
        return
    end
    if not shouldShowNmsStatusButton(self) then
        hideNmsStatusButton(self)
        return
    end

    local anchor = getFitnessAnchor(self)
    self.nmsStatusButton:setX(anchor:getRight() + NMS_BUTTON_GAP)
    self.nmsStatusButton:setY(anchor:getY())
    self.nmsStatusButton:setVisible(true)
    local width = math.max(self:getWidth(), self.nmsStatusButton:getRight() + UI_BORDER_SPACING + 1)
    self:setWidthAndParentWidth(width)
end

local function getTextManagerSafe()
    if type(getTextManager) == "function" then
        local manager = getTextManager()
        if manager then
            return manager
        end
    end
    return _G.TextManager and TextManager.instance or nil
end

local function getFontHeight()
    if FONT_HGT then
        return FONT_HGT
    end
    local manager = getTextManagerSafe()
    local height = tonumber(manager and manager.getFontHeight and manager:getFontHeight(FONT) or nil)
    FONT_HGT = (height and height > 0) and height or 12
    return FONT_HGT
end

local function hookedUpdate(self)
    local fontHeight = getFontHeight()

    local patient = self.getPatient and self:getPatient() or nil
    if not patient or (self.otherPlayer and self.otherPlayer ~= patient) then
        originalUpdate(self)
        hideNmsStatusButton(self)
        return
    end

    local lines = collectLines(patient, getState(patient))
    if #lines == 0 then
        originalUpdate(self)
        positionNmsStatusButton(self)
        return
    end

    local blockHeight = #lines * fontHeight
    local previousAllTextHeight = self.allTextHeight
    if previousAllTextHeight ~= nil then
        self.allTextHeight = previousAllTextHeight + blockHeight
    end

    originalUpdate(self)

    self.allTextHeight = previousAllTextHeight
    positionNmsStatusButton(self)
end

local function hookedRender(self)
    local fontHeight = getFontHeight()
    originalRender(self)
    positionNmsStatusButton(self)

    local patient = self:getPatient()
    if not patient or (self.otherPlayer and self.otherPlayer ~= patient) then
        hideNmsStatusButton(self)
        return
    end

    local lines = collectLines(patient, getState(patient))
    if #lines == 0 then
        return
    end

    local x = self.healthPanel:getRight() + UI_BORDER_SPACING
    local listY = self.listbox:getY()
    local blockHeight = #lines * fontHeight

    self.listbox:setY(listY + blockHeight)
    self.listbox.vscroll:setHeight(self.listbox:getHeight())

    local y = listY
    for _, line in ipairs(lines) do
        local lx = x + (line.indent or 0)
        local color = line.color or C_WHITE
        self:drawText(line.text, lx, y, color.r, color.g, color.b, color.a, FONT)
        local cx = lx + Draw.textWidth(FONT, line.text)
        if line.valueText then
            local vc = line.valueColor or C_WHITE
            self:drawText(line.valueText, cx, y, vc.r, vc.g, vc.b, vc.a, FONT)
            cx = cx + Draw.textWidth(FONT, line.valueText)
        end
        if line.chevron then
            Draw.chevron(self, cx + 3, y + math.floor(fontHeight / 2) - 2, line.chevron.up, line.chevron.color)
            cx = cx + CHEVRON_W
        end
        if line.suffixText then
            local sc = line.suffixColor or C_DIM
            self:drawText("  " .. line.suffixText, cx, y, sc.r, sc.g, sc.b, sc.a, FONT)
        end
        y = y + fontHeight
    end
end

local function onNmsStatusButton()
    NutritionMakesSense.NutritionWindow.toggle()
end

local function ensureNmsStatusButton(self)
    if self.nmsStatusButton or not self.fitness then
        return
    end

    local label = T("UI_NMS_Window_Button")
    self.nmsStatusButton = ISButton:new(
        self.fitness:getRight() + NMS_BUTTON_GAP,
        self.fitness:getY(),
        math.max(self.fitness:getWidth(), Draw.textWidth(FONT, label) + 16),
        self.fitness:getHeight(),
        label,
        self,
        onNmsStatusButton
    )
    self.nmsStatusButton.anchorTop = false
    self.nmsStatusButton.anchorBottom = true
    self.nmsStatusButton:initialise()
    self.nmsStatusButton:instantiate()
    self:addChild(self.nmsStatusButton)
    if isTutorialMode() then
        self.nmsStatusButton:setVisible(false)
    end
end

local function ensureExistingHealthPanels()
    if ISHealthPanel and ISHealthPanel.instance then
        ensureNmsStatusButton(ISHealthPanel.instance)
        positionNmsStatusButton(ISHealthPanel.instance)
    end

    if type(getPlayerData) ~= "function" then
        return
    end
    for playerNum = 0, 3 do
        local pdata = getPlayerData(playerNum)
        local healthView = pdata and pdata.characterInfo and pdata.characterInfo.healthView or nil
        if healthView then
            ensureNmsStatusButton(healthView)
            positionNmsStatusButton(healthView)
        end
    end
end

local function hookedCreateChildren(self)
    originalCreateChildren(self)
    ensureNmsStatusButton(self)
end

local function install()
    if not requireVanillaHealthPanel() then
        if not hookDeferredLogged then
            hookDeferredLogged = true
            logHook("deferred: ISHealthPanel unavailable")
        end
        return
    end
    if originalRender or originalUpdate or originalCreateChildren then
        ensureExistingHealthPanels()
        return
    end

    originalCreateChildren = ISHealthPanel.createChildren
    originalUpdate = ISHealthPanel.update
    originalRender = ISHealthPanel.render
    ISHealthPanel.createChildren = hookedCreateChildren
    ISHealthPanel.update = hookedUpdate
    ISHealthPanel.render = hookedRender
    if not hookInstallLogged then
        hookInstallLogged = true
        logHook("installed")
    end
    ensureExistingHealthPanels()
end

local function retryInstall()
    install()
    if originalRender and Events and Events.OnPreUIDraw and type(Events.OnPreUIDraw.Remove) == "function" then
        Events.OnPreUIDraw.Remove(retryInstall)
    end
end

function HealthPanelHook.install()
    if HealthPanelHook._installed then
        return HealthPanelHook
    end
    HealthPanelHook._installed = true
    if type(CompatHelpers.registerCoordinator) == "function" then
        CompatHelpers.registerCoordinator()
    end

    if Events and Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(install)
    end
    if Events and Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
        Events.OnCreatePlayer.Add(install)
    end
    if Events and Events.OnPreUIDraw and type(Events.OnPreUIDraw.Add) == "function" then
        Events.OnPreUIDraw.Add(retryInstall)
    end
    install()

    return HealthPanelHook
end

return HealthPanelHook
