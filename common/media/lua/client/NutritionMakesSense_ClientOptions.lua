NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_DevSupport"

local ClientOptions = NutritionMakesSense.ClientOptions or {}
NutritionMakesSense.ClientOptions = ClientOptions

local MOD_OPTIONS_ID = "NutritionMakesSense"
local registered = false
local DevSupport = NutritionMakesSense.DevSupport or {}

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
    if not (DevSupport.isDebugLaunch and DevSupport.isDebugLaunch()) then
        return false
    end
    if not ensureModOptionsLoaded() then
        return false
    end

    local existing = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if existing then
        registered = true
        return true
    end

    local options = PZAPI.ModOptions:create(MOD_OPTIONS_ID, getText("UI_NMS_ModOptions_Title"))
    options:addTitle(getText("UI_NMS_ModOptions_Debug_Title"))
    options:addTickBox(
        "showDebugFoodTooltips",
        getText("UI_NMS_ModOptions_DebugTooltips"),
        true,
        getText("UI_NMS_ModOptions_DebugTooltips_Tooltip")
    )

    registered = true
    return true
end

function ClientOptions.isDebugLaunch()
    return DevSupport.isDebugLaunch and DevSupport.isDebugLaunch() or false
end

function ClientOptions.getShowDebugFoodTooltips()
    if not ClientOptions.isDebugLaunch() then
        return nil
    end

    ClientOptions.ensureRegistered()
    if not (PZAPI and PZAPI.ModOptions and type(PZAPI.ModOptions.getOptions) == "function") then
        return true
    end

    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    local option = options and options:getOption("showDebugFoodTooltips") or nil
    if option and type(option.getValue) == "function" then
        return option:getValue() == true
    end

    return true
end

local function install()
    if ClientOptions._installed then
        return ClientOptions
    end
    ClientOptions._installed = true

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
