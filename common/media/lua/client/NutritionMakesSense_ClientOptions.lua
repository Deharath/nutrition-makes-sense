NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_DebugSupport"

local ClientOptions = NutritionMakesSense.ClientOptions or {}
NutritionMakesSense.ClientOptions = ClientOptions

local MOD_OPTIONS_ID = "NutritionMakesSense"
local registered = false
local DebugSupport = NutritionMakesSense.DebugSupport or {}

local function getOptionsObject()
    if not (PZAPI and PZAPI.ModOptions and type(PZAPI.ModOptions.getOptions) == "function") then
        return nil
    end
    return PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
end

local function ensureTickBox(options, optionId, label, defaultValue, tooltip)
    if not options or type(options.addTickBox) ~= "function" then
        return nil
    end

    local existing = type(options.getOption) == "function" and options:getOption(optionId) or nil
    if existing then
        return existing
    end

    return options:addTickBox(optionId, label, defaultValue, tooltip)
end

local function ensureModOptionsLoaded()
    if PZAPI and PZAPI.ModOptions and type(PZAPI.ModOptions.create) == "function" then
        return true
    end

    local ok = pcall(require, "PZAPI/ModOptions")
    return ok and PZAPI and PZAPI.ModOptions and type(PZAPI.ModOptions.create) == "function"
end

function ClientOptions.ensureRegistered()
    if registered then
        return true
    end
    if not ensureModOptionsLoaded() then
        return false
    end

    local options = getOptionsObject()
    if not options and PZAPI and PZAPI.ModOptions and type(PZAPI.ModOptions.create) == "function" then
        options = PZAPI.ModOptions:create(MOD_OPTIONS_ID, getText("UI_NMS_ModOptions_Title"))
    end
    if not options then
        return false
    end

    if type(options.getOption) == "function" and not options:getOption("displayMode") then
        local combo = options:addComboBox("displayMode", getText("UI_NMS_ModOptions_Display"),
            getText("UI_NMS_ModOptions_Display_Tooltip"))
        combo:addItem("UI_NMS_ModOptions_Display_Immersive", true)
        combo:addItem("UI_NMS_ModOptions_Display_Detailed", false)
    end

    if DebugSupport.isDebugLaunch and DebugSupport.isDebugLaunch() then
        options:addTitle(getText("UI_NMS_ModOptions_Debug_Title"))
        ensureTickBox(
            options,
        "showDebugFoodTooltips",
        getText("UI_NMS_ModOptions_DebugTooltips"),
        true,
        getText("UI_NMS_ModOptions_DebugTooltips_Tooltip")
        )
    end

    registered = true
    return true
end

function ClientOptions.isDebugLaunch()
    return DebugSupport.isDebugLaunch and DebugSupport.isDebugLaunch() or false
end

function ClientOptions.getShowDebugFoodTooltips()
    if not ClientOptions.isDebugLaunch() then
        return nil
    end

    ClientOptions.ensureRegistered()
    local options = getOptionsObject()
    if not options then
        return true
    end

    local option = options and options:getOption("showDebugFoodTooltips") or nil
    if option and type(option.getValue) == "function" then
        return option:getValue() == true
    end

    return true
end

-- Immersive (default) shows what the character feels; Detailed shows exact amounts and times.
function ClientOptions.isDetailedDisplay()
    ClientOptions.ensureRegistered()
    local options = getOptionsObject()
    local option = options and options:getOption("displayMode") or nil
    return option ~= nil and type(option.getValue) == "function" and option:getValue() == 2
end

local function install()
    if ClientOptions._installed then
        return ClientOptions
    end
    ClientOptions._installed = true
    ClientOptions.ensureRegistered()

    if Events and Events.OnMainMenuEnter and type(Events.OnMainMenuEnter.Add) == "function" then
        Events.OnMainMenuEnter.Add(function()
            ClientOptions.ensureRegistered()
        end)
    end

    if Events and Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(function()
            ClientOptions.ensureRegistered()
        end)
    else
        ClientOptions.ensureRegistered()
    end

    return ClientOptions
end

ClientOptions.install = install

return ClientOptions
