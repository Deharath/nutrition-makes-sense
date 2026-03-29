NutritionMakesSense = NutritionMakesSense or {}

require "ui/NutritionMakesSense_UIHelpers"
require "NutritionMakesSense_ClientOptions"

local AwarenessCues = NutritionMakesSense.AwarenessCues or {}
NutritionMakesSense.AwarenessCues = AwarenessCues

local UIHelpers = NutritionMakesSense.UIHelpers or {}
local ClientOptions = NutritionMakesSense.ClientOptions or {}
local Metabolism = NutritionMakesSense.Metabolism or {}

local FUEL_THRESHOLD = tonumber(Metabolism.FUEL_ACUTE_ENDURANCE_THRESHOLD) or 450
local HALO_COLOR = { r = 214, g = 170, b = 88 }
local HALO_DURATION = 250
local cueStateByPlayer = {}
local HALO_HEADER_KEY = "UI_NMS_LowEnergyCue_Header"
local HALO_THOUGHT_KEYS = {
    "UI_NMS_LowEnergyCue_Thought_1",
    "UI_NMS_LowEnergyCue_Thought_2",
    "UI_NMS_LowEnergyCue_Thought_3",
}

local function safeCall(target, methodName, ...)
    return UIHelpers.safeCall(target, methodName, ...)
end

local function isLocalPlayer(playerObj)
    if not playerObj then
        return false
    end

    if safeCall(playerObj, "isLocalPlayer") == true then
        return true
    end

    return type(getPlayer) == "function" and playerObj == getPlayer()
end

local function getPlayerKey(playerObj)
    local playerNum = tonumber(safeCall(playerObj, "getPlayerNum"))
    if playerNum ~= nil then
        return "player-num:" .. tostring(playerNum)
    end

    local onlineId = tonumber(safeCall(playerObj, "getOnlineID"))
    if onlineId ~= nil then
        return "online-id:" .. tostring(onlineId)
    end

    return tostring(playerObj)
end

local function getCueState(playerObj)
    local key = getPlayerKey(playerObj)
    local entry = cueStateByPlayer[key]
    if entry then
        return entry
    end

    entry = {
        initialized = false,
        wasBelow = false,
        armed = true,
    }
    cueStateByPlayer[key] = entry
    return entry
end

local function clearCueState(playerObj)
    if not playerObj then
        return
    end
    cueStateByPlayer[getPlayerKey(playerObj)] = nil
end

local function pickHaloText()
    local index = 1
    if type(ZombRand) == "function" then
        index = ZombRand(#HALO_THOUGHT_KEYS) + 1
    end

    local header = UIHelpers.tr(HALO_HEADER_KEY, "(Low glycogen reserves)")
    local thought = UIHelpers.tr(HALO_THOUGHT_KEYS[index], "\"Feeling a bit flat...\"")
    return string.format("%s\n%s", header, thought)
end

local function playLowEnergySound(playerObj)
    if not playerObj then
        return false
    end

    local female = safeCall(playerObj, "isFemale") == true
    local soundKey = SoundKey and (female and SoundKey.VOICE_FEMALE_SIGH_BORED or SoundKey.VOICE_MALE_SIGH_BORED) or nil
    local soundName = soundKey and safeCall(soundKey, "getSoundName") or nil
    if type(soundName) == "string" and soundName ~= "" then
        local played = safeCall(playerObj, "playSoundLocal", soundName)
        if played ~= nil then
            return true
        end
    end

    local voicePlayed = safeCall(playerObj, "playerVoiceSound", "SighBored")
    return voicePlayed ~= nil
end

local function showLowEnergyHalo(playerObj)
    if not playerObj then
        return false
    end

    local text = pickHaloText()
    return safeCall(
        playerObj,
        "setHaloNote",
        text,
        HALO_COLOR.r,
        HALO_COLOR.g,
        HALO_COLOR.b,
        HALO_DURATION
    ) ~= nil
end

local function fireCue(playerObj)
    if ClientOptions.getLowEnergySoundCueEnabled and ClientOptions.getLowEnergySoundCueEnabled() then
        playLowEnergySound(playerObj)
    end
    if ClientOptions.getLowEnergyHaloCueEnabled and ClientOptions.getLowEnergyHaloCueEnabled() then
        showLowEnergyHalo(playerObj)
    end
end

local function shouldTriggerCue(playerObj)
    local state = UIHelpers.getStateCopy(playerObj)
    local fuel = tonumber(state and state.fuel)
    if fuel == nil then
        return nil
    end
    return fuel <= FUEL_THRESHOLD
end

local function evaluatePlayerCue(playerObj)
    if not isLocalPlayer(playerObj) then
        return
    end

    local isBelowThreshold = shouldTriggerCue(playerObj)
    if isBelowThreshold == nil then
        return
    end

    local cueState = getCueState(playerObj)
    if not cueState.initialized then
        cueState.initialized = true
        cueState.wasBelow = isBelowThreshold
        cueState.armed = not isBelowThreshold
        return
    end

    if not isBelowThreshold then
        cueState.wasBelow = false
        cueState.armed = true
        return
    end

    if cueState.wasBelow then
        return
    end

    cueState.wasBelow = true
    if not cueState.armed then
        return
    end

    cueState.armed = false
    fireCue(playerObj)
end

local function onCreatePlayer(_, playerObj)
    clearCueState(playerObj)
end

local function onPlayerUpdate(playerObj)
    evaluatePlayerCue(playerObj)
end

function AwarenessCues.install()
    if AwarenessCues._installed then
        return AwarenessCues
    end
    AwarenessCues._installed = true

    if Events then
        if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
            Events.OnCreatePlayer.Add(onCreatePlayer)
        end
        if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
            Events.OnPlayerUpdate.Add(onPlayerUpdate)
        end
    end

    return AwarenessCues
end

return AwarenessCues
