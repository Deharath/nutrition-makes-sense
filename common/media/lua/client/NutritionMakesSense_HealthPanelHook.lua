NutritionMakesSense = NutritionMakesSense or {}

require "ui/NutritionMakesSense_UIHelpers"

local Metabolism = NutritionMakesSense.Metabolism or {}
local UIHelpers = NutritionMakesSense.UIHelpers or {}
local HealthPanelHook = NutritionMakesSense.HealthPanelHook or {}
NutritionMakesSense.HealthPanelHook = HealthPanelHook

local UI_BORDER_SPACING = 10
local FONT = UIFont.Small
local FONT_HGT = nil

local C_HEADER = { r = 0.72, g = 0.78, b = 0.82, a = 1.0 }
local C_GOOD = { r = 0.55, g = 0.80, b = 0.55, a = 1.0 }
local C_WARN = { r = 0.90, g = 0.75, b = 0.30, a = 1.0 }
local C_BAD = { r = 0.90, g = 0.35, b = 0.30, a = 1.0 }
local C_DIM = { r = 0.55, g = 0.58, b = 0.62, a = 0.85 }

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
    return UIHelpers.tr("UI_NMS_Deprivation_Severity_Mild", "Mild"), C_DIM
end

local function getDeprivationDirection(fuel, deprivation)
    local target = Metabolism.getDeprivationTarget and Metabolism.getDeprivationTarget(fuel) or deprivation
    if target > deprivation + 0.01 then
        return UIHelpers.tr("UI_NMS_Deprivation_Direction_Worsening", "Worsening")
    end
    if target < deprivation - 0.01 then
        return UIHelpers.tr("UI_NMS_Deprivation_Direction_Recovering", "Recovering")
    end
    return UIHelpers.tr("UI_NMS_Deprivation_Direction_Stable", "Stable")
end

local function collectLines(state)
    if not state then
        return {}
    end

    local lines = {}
    local fuel = tonumber(state.fuel) or 0
    local deprivation = tonumber(state.deprivation) or 0
    local proteins = tonumber(state.proteins) or 0
    local proteinDef = tonumber(state.lastProteinDeficiency)
    if proteinDef == nil and Metabolism.getProteinDeficiencyProgress then
        proteinDef = Metabolism.getProteinDeficiencyProgress(proteins)
    end
    proteinDef = tonumber(proteinDef) or 0

    local zone = tostring(state.lastZone or (Metabolism.getFuelZone and Metabolism.getFuelZone(fuel)) or "")

    local acuteRecoveryScale = tonumber(state.lastAcuteFuelRecoveryScale)
    if acuteRecoveryScale == nil and Metabolism.getFuelRecoveryScale then
        acuteRecoveryScale = Metabolism.getFuelRecoveryScale(fuel)
    end
    acuteRecoveryScale = tonumber(acuteRecoveryScale) or 1.0
    local acuteRecoveryPenalty = math.max(0, (1.0 - acuteRecoveryScale) * 100)
    local hasFuelSection = false
    if zone == "Penalty" or zone == "Low" or acuteRecoveryPenalty >= 1 then
        hasFuelSection = true
        lines[#lines + 1] = { text = UIHelpers.tr("UI_NMS_Section_Fuel", "Energy Reserves"), color = C_HEADER }
        if zone == "Penalty" then
            lines[#lines + 1] = { text = UIHelpers.tr("UI_NMS_Fuel_State_Depleted", "Depleted"), color = C_BAD }
        elseif zone == "Low" then
            lines[#lines + 1] = { text = UIHelpers.tr("UI_NMS_Fuel_State_Low", "Low"), color = C_WARN }
        end
    end
    if acuteRecoveryPenalty >= 1 then
        lines[#lines + 1] = {
            text = UIHelpers.tr("UI_NMS_Fuel_RecoveryPenalty", "Stamina Recovery") .. " -" .. UIHelpers.formatPercent(acuteRecoveryPenalty),
            color = C_DIM,
        }
    end

    if deprivation >= (Metabolism.DEPRIVATION_PENALTY_ONSET or 0.10) then
        if hasFuelSection then
            lines[#lines + 1] = { text = "", color = C_DIM }
        end
        local progress = Metabolism.getDeprivationPenaltyProgress and Metabolism.getDeprivationPenaltyProgress(deprivation) or 0
        local severityText, severityColor = getDeprivationSeverity(progress)
        local directionText = getDeprivationDirection(fuel, deprivation)
        lines[#lines + 1] = { text = UIHelpers.tr("UI_NMS_Deprivation_Header", "Malnourishment"), color = C_HEADER }
        lines[#lines + 1] = {
            text = severityText .. " | " .. directionText,
            color = severityColor,
        }

        if deprivation >= (Metabolism.DEPRIVATION_ENDURANCE_ONSET or 0.15) then
            local regenScale = Metabolism.getDeprivationRegenScale and Metabolism.getDeprivationRegenScale(deprivation) or 1.0
            local regenPenalty = math.max(0, (1.0 - regenScale) * 100)
            if regenPenalty >= 1 then
                lines[#lines + 1] = {
                    text = UIHelpers.tr("UI_NMS_Deprivation_EndurancePenalty", "Stamina Recovery") .. " -" .. UIHelpers.formatPercent(regenPenalty),
                    color = C_DIM,
                }
            end
        end

        local fatigueFactor = Metabolism.getFatigueAccelFactor and Metabolism.getFatigueAccelFactor(deprivation) or 1.0
        local fatiguePenalty = math.max(0, (fatigueFactor - 1.0) * 100)
        if fatiguePenalty >= 1 then
            lines[#lines + 1] = {
                text = UIHelpers.tr("UI_NMS_Deprivation_FatiguePenalty", "Fatigue Rate") .. " +" .. UIHelpers.formatPercent(fatiguePenalty),
                color = C_DIM,
            }
        end

        local meleeMultiplier = Metabolism.getMeleeDamageMultiplier and Metabolism.getMeleeDamageMultiplier(deprivation) or 1.0
        local meleePenalty = math.max(0, (1.0 - meleeMultiplier) * 100)
        if meleePenalty >= 1 then
            lines[#lines + 1] = {
                text = UIHelpers.tr("UI_NMS_Deprivation_MeleePenalty", "Melee Damage") .. " -" .. UIHelpers.formatPercent(meleePenalty),
                color = C_DIM,
            }
        end
    end

    if proteinDef > 0.3 then
        local proteinColor = proteinDef >= 0.7 and C_BAD or C_WARN
        lines[#lines + 1] = { text = UIHelpers.tr("UI_NMS_Section_Protein", "Protein"), color = C_HEADER }
        lines[#lines + 1] = { text = UIHelpers.tr("UI_NMS_Protein_Low", "Low"), color = proteinColor }

        local healingMultiplier = tonumber(state.lastProteinHealingMultiplier)
        if healingMultiplier == nil and Metabolism.getProteinHealingMultiplier then
            healingMultiplier = Metabolism.getProteinHealingMultiplier(proteins)
        end
        healingMultiplier = tonumber(healingMultiplier) or 1.0
        local healingPenalty = math.max(0, (1.0 - healingMultiplier) * 100)
        if healingPenalty >= 1 then
            lines[#lines + 1] = {
                text = UIHelpers.tr("UI_NMS_Protein_HealingPenalty", "Wound Healing") .. " -" .. UIHelpers.formatPercent(healingPenalty),
                color = C_DIM,
            }
        end
    end

    return lines
end

local originalRender = nil
local originalUpdate = nil

local function hookedUpdate(self)
    if not FONT_HGT then
        FONT_HGT = getTextManager():getFontHeight(FONT)
    end

    local patient = self.getPatient and self:getPatient() or nil
    if not patient or (self.otherPlayer and self.otherPlayer ~= patient) then
        originalUpdate(self)
        return
    end

    local lines = collectLines(getState(patient))
    if #lines == 0 then
        originalUpdate(self)
        return
    end

    local blockHeight = (#lines + 1) * FONT_HGT + 4
    local previousAllTextHeight = self.allTextHeight
    if previousAllTextHeight ~= nil then
        self.allTextHeight = previousAllTextHeight + blockHeight
    end

    originalUpdate(self)

    self.allTextHeight = previousAllTextHeight
end

local function hookedRender(self)
    if not FONT_HGT then
        FONT_HGT = getTextManager():getFontHeight(FONT)
    end

    originalRender(self)

    local patient = self:getPatient()
    if not patient or (self.otherPlayer and self.otherPlayer ~= patient) then
        return
    end

    local lines = collectLines(getState(patient))
    if #lines == 0 then
        return
    end

    local x = self.healthPanel:getRight() + UI_BORDER_SPACING
    local listY = self.listbox:getY()
    local blockHeight = (#lines + 1) * FONT_HGT + 4

    self.listbox:setY(listY + blockHeight)
    self.listbox.vscroll:setHeight(self.listbox:getHeight())

    local y = listY
    self:drawRect(x, y, self.width - x - UI_BORDER_SPACING, 1, 0.25, 0.5, 0.6, 0.7)
    y = y + 4

    for _, line in ipairs(lines) do
        local color = line.color or C_DIM
        self:drawText(line.text, x, y, color.r, color.g, color.b, color.a, FONT)
        y = y + FONT_HGT
    end
end

local function install()
    if not ISHealthPanel or type(ISHealthPanel.render) ~= "function" or type(ISHealthPanel.update) ~= "function" then
        return
    end
    if originalRender or originalUpdate then
        return
    end

    originalUpdate = ISHealthPanel.update
    originalRender = ISHealthPanel.render
    ISHealthPanel.update = hookedUpdate
    ISHealthPanel.render = hookedRender
end

function HealthPanelHook.install()
    if HealthPanelHook._installed then
        return HealthPanelHook
    end
    HealthPanelHook._installed = true

    if Events and Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(install)
    end
    install()

    return HealthPanelHook
end

return HealthPanelHook
