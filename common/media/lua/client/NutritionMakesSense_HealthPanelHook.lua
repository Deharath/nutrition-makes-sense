NutritionMakesSense = NutritionMakesSense or {}

require "ui/NutritionMakesSense_UIHelpers"
require "NutritionMakesSense_HealthPanelCompat"
require "NutritionMakesSense_PlayerStatusPanel"

local Metabolism = NutritionMakesSense.Metabolism or {}
local UIHelpers = NutritionMakesSense.UIHelpers or {}
local CompatHelpers = NutritionMakesSense.HealthPanelCompat or {}
local HealthPanelHook = NutritionMakesSense.HealthPanelHook or {}
NutritionMakesSense.HealthPanelHook = HealthPanelHook

local UI_BORDER_SPACING = 10
local FONT = UIFont.Small
local FONT_HGT = nil

local C_WHITE = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
local C_VALUE = { r = 0.75, g = 0.77, b = 0.80, a = 1.0 }
local C_MILD = { r = 0.72, g = 0.78, b = 0.82, a = 1.0 }
local C_GOOD = { r = 0.55, g = 0.80, b = 0.55, a = 1.0 }
local C_WARN = { r = 0.90, g = 0.75, b = 0.30, a = 1.0 }
local C_BAD = { r = 0.90, g = 0.35, b = 0.30, a = 1.0 }

local function getState(player)
    return UIHelpers.getStateCopy(player)
end

local function getDeprivationSeverity(progress)
    local p = UIHelpers.clamp(tonumber(progress) or 0, 0, 1)
    if p >= (2 / 3) then
        return UIHelpers.tr("UI_NMS_Deprivation_Severity_Severe", "Severe"), C_BAD
    end
    if p >= (1 / 3) then
        return UIHelpers.tr("UI_NMS_Deprivation_Severity_Moderate", "Moderate"), C_WARN
    end
    return UIHelpers.tr("UI_NMS_Deprivation_Severity_Mild", "Mild"), C_MILD
end

local function getDeprivationDirection(state, deprivation)
    local target = tonumber(state and state.lastDeprivationTarget)
    if target == nil and Metabolism.getDeprivationTarget then
        target = Metabolism.getDeprivationTarget(state)
    end
    target = tonumber(target) or deprivation
    if target > deprivation + 0.01 then
        return UIHelpers.tr("UI_NMS_Deprivation_Direction_Worsening", "Worsening")
    end
    if target < deprivation - 0.01 then
        return UIHelpers.tr("UI_NMS_Deprivation_Direction_Recovering", "Recovering")
    end
    return UIHelpers.tr("UI_NMS_Deprivation_Direction_Stable", "Stable")
end

local function collectLines(playerObj, state)
    local baseLines = {}
    local compatLines = type(CompatHelpers.collectExternalLines) == "function"
        and CompatHelpers.collectExternalLines(nil, playerObj)
        or {}

    if not state then
        return compatLines
    end

    local deprivation = tonumber(state.deprivation) or 0
    local weightKg = tonumber(state.weightKg) or Metabolism.DEFAULT_WEIGHT_KG
    local proteins = tonumber(state.proteins) or 0
    local proteinDef = tonumber(state.lastProteinDeficiency)
    if proteinDef == nil and Metabolism.getProteinDeficiencyProgress then
        proteinDef = Metabolism.getProteinDeficiencyProgress(proteins, weightKg)
    end
    proteinDef = tonumber(proteinDef) or 0

    if deprivation >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) then
        local progress = Metabolism.getDeprivationPenaltyProgress and Metabolism.getDeprivationPenaltyProgress(deprivation) or 0
        local severityText, severityColor = getDeprivationSeverity(progress)
        local directionText = getDeprivationDirection(state, deprivation)
        baseLines[#baseLines + 1] = {
            text = UIHelpers.tr("UI_NMS_Deprivation_Header", "Malnourishment"),
            color = C_WHITE,
        }
        baseLines[#baseLines + 1] = {
            text = severityText .. " | " .. directionText,
            color = severityColor,
            indent = 12,
        }

        if deprivation >= (Metabolism.DEPRIVATION_ENDURANCE_ONSET or 0.15) then
            local regenScale = Metabolism.getDeprivationRegenScale and Metabolism.getDeprivationRegenScale(deprivation) or 1.0
            local regenPenalty = math.max(0, (1.0 - regenScale) * 100)
            if regenPenalty >= 1 then
                baseLines[#baseLines + 1] = {
                    text = UIHelpers.tr("UI_NMS_Deprivation_EndurancePenalty", "Stamina Recovery") .. ": ",
                    color = C_WHITE,
                    valueText = "-" .. UIHelpers.formatPercent(regenPenalty),
                    valueColor = C_VALUE,
                    indent = 12,
                }
            end
        end

        local fatigueFactor = Metabolism.getFatigueAccelFactor and Metabolism.getFatigueAccelFactor(deprivation) or 1.0
        local fatiguePenalty = math.max(0, (fatigueFactor - 1.0) * 100)
        if fatiguePenalty >= 1 then
            baseLines[#baseLines + 1] = {
                text = UIHelpers.tr("UI_NMS_Deprivation_FatiguePenalty", "Fatigue Rate") .. ": ",
                color = C_WHITE,
                valueText = "+" .. UIHelpers.formatPercent(fatiguePenalty),
                valueColor = C_VALUE,
                indent = 12,
            }
        end

    end

    if proteinDef > 0.3 then
        local proteinColor = proteinDef >= 0.7 and C_BAD or C_WARN
        baseLines[#baseLines + 1] = {
            text = UIHelpers.tr("UI_NMS_Section_Protein", "Protein") .. ": ",
            color = C_WHITE,
            valueText = UIHelpers.tr("UI_NMS_Protein_Low", "Low"),
            valueColor = proteinColor,
        }

        local healingMultiplier = tonumber(state.lastProteinHealingMultiplier)
        if healingMultiplier == nil and Metabolism.getProteinHealingMultiplier then
            healingMultiplier = Metabolism.getProteinHealingMultiplier(proteins, weightKg)
        end
        healingMultiplier = tonumber(healingMultiplier) or 1.0
        local healingPenalty = math.max(0, (1.0 - healingMultiplier) * 100)
        if healingPenalty >= 1 then
            baseLines[#baseLines + 1] = {
                text = UIHelpers.tr("UI_NMS_Protein_HealingPenalty", "Wound Healing") .. ": ",
                color = C_WHITE,
                valueText = "-" .. UIHelpers.formatPercent(healingPenalty),
                valueColor = C_VALUE,
                indent = 12,
            }
        end
    end

    if type(CompatHelpers.mergeLines) == "function" then
        return CompatHelpers.mergeLines(compatLines, baseLines)
    end
    return baseLines
end

local originalRender = nil
local originalUpdate = nil
local originalCreateChildren = nil

local NMS_BUTTON_W = 42
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
    local textManager = getTextManagerSafe()

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
        if line.valueText then
            local measuredWidth = tonumber(textManager and textManager.MeasureStringX and textManager:MeasureStringX(FONT, line.text) or nil) or 0
            local vx = lx + measuredWidth
            local vc = line.valueColor or C_VALUE
            self:drawText(line.valueText, vx, y, vc.r, vc.g, vc.b, vc.a, FONT)
        end
        y = y + fontHeight
    end
end

local function onNmsStatusButton()
    local panel = NutritionMakesSense.PlayerStatusPanel
    if panel and type(panel.toggle) == "function" then
        panel.toggle()
    end
end

local function ensureNmsStatusButton(self)
    if self.nmsStatusButton or not self.fitness then
        return
    end

    local label = UIHelpers.tr("UI_NMS_StatusPanel_Button", "NMS")
    self.nmsStatusButton = ISButton:new(
        self.fitness:getRight() + NMS_BUTTON_GAP,
        self.fitness:getY(),
        NMS_BUTTON_W,
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
