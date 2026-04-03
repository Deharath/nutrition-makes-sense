NutritionMakesSense = NutritionMakesSense or {}

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = Runtime.Metabolism or {}
local CoreUtils = NutritionMakesSense.CoreUtils or {}

local safeCall = CoreUtils.safeCall
local safeInvoke = CoreUtils.safeInvoke
local getPlayerLabel = CoreUtils.getPlayerLabel

local Perks = _G.PerkFactory and _G.PerkFactory.Perks or _G.Perks
local isServerRuntime = type(isServer) == "function" and isServer() == true
local isClientRuntime = type(isClient) == "function" and isClient() == true
local addXpReentryByPlayerKey = {}
local pendingInjectedXpByPlayerKey = {}
local INJECTED_XP_TTL_SECONDS = 6

local function log(msg)
    if NutritionMakesSense.log then
        NutritionMakesSense.log(msg)
    else
        print("[NutritionMakesSense] " .. tostring(msg))
    end
end

local function isIsoPlayer(playerObj)
    if not playerObj then
        return false
    end
    if type(instanceof) == "function" then
        return instanceof(playerObj, "IsoPlayer")
    end
    return true
end

local function isStrengthPerk(perkType)
    if perkType == nil then
        return false
    end
    if Perks and perkType == Perks.Strength then
        return true
    end
    return tostring(perkType) == "Strength" or tostring(perkType) == "Perks.Strength"
end

local function getPlayerKey(playerObj)
    if not playerObj then
        return nil
    end
    local onlineId = tonumber(safeCall(playerObj, "getOnlineID"))
    if onlineId ~= nil then
        return "online:" .. tostring(onlineId)
    end
    local playerNum = tonumber(safeCall(playerObj, "getPlayerNum"))
    if playerNum ~= nil then
        return "player:" .. tostring(playerNum)
    end
    return tostring(playerObj)
end

local function getState(playerObj)
    if Runtime.getStateCopy then
        local copy = Runtime.getStateCopy(playerObj)
        if type(copy) == "table" then
            return copy
        end
    end
    if Runtime.ensureStateForPlayer then
        local state = Runtime.ensureStateForPlayer(playerObj)
        if type(state) == "table" then
            return state
        end
    end
    return nil
end

local function toNumber(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return nil
    end
    if numeric ~= numeric then
        return nil
    end
    return numeric
end

local function getWallClockSeconds()
    if type(getTimestampMs) == "function" then
        local nowMs = tonumber(getTimestampMs())
        if nowMs ~= nil then
            return math.floor(nowMs / 1000)
        end
    end
    if type(getTimestamp) == "function" then
        local nowSecond = tonumber(getTimestamp())
        if nowSecond ~= nil then
            return math.floor(nowSecond)
        end
    end
    local worldHours = Runtime.getWorldHours and Runtime.getWorldHours() or nil
    return math.floor((tonumber(worldHours) or 0) * 3600)
end

local function prunePendingInjectedXp(playerKey, nowSecond)
    local queue = playerKey and pendingInjectedXpByPlayerKey[playerKey] or nil
    if type(queue) ~= "table" then
        return nil
    end
    local now = tonumber(nowSecond) or getWallClockSeconds()
    local kept = {}
    for _, entry in ipairs(queue) do
        if type(entry) == "table" and tonumber(entry.expiresAt) and entry.expiresAt >= now then
            kept[#kept + 1] = entry
        end
    end
    if #kept > 0 then
        pendingInjectedXpByPlayerKey[playerKey] = kept
        return kept
    end
    pendingInjectedXpByPlayerKey[playerKey] = nil
    return nil
end

local function enqueuePendingInjectedXp(playerKey, amount)
    if not playerKey then
        return nil
    end
    local numericAmount = tonumber(amount)
    if numericAmount == nil or math.abs(numericAmount) < 0.0001 then
        return nil
    end
    local queue = prunePendingInjectedXp(playerKey)
    if type(queue) ~= "table" then
        queue = {}
        pendingInjectedXpByPlayerKey[playerKey] = queue
    end
    local entry = {
        amount = math.abs(numericAmount),
        sign = numericAmount >= 0 and 1 or -1,
        expiresAt = getWallClockSeconds() + INJECTED_XP_TTL_SECONDS,
    }
    queue[#queue + 1] = entry
    return entry
end

local function removePendingInjectedXpEntry(playerKey, token)
    if not playerKey or type(token) ~= "table" then
        return
    end
    local queue = pendingInjectedXpByPlayerKey[playerKey]
    if type(queue) ~= "table" then
        return
    end
    for index, entry in ipairs(queue) do
        if entry == token then
            table.remove(queue, index)
            break
        end
    end
    if #queue <= 0 then
        pendingInjectedXpByPlayerKey[playerKey] = nil
    end
end

local function shouldSuppressInjectedXpEvent(playerKey, observedAmount)
    if not playerKey then
        return false
    end
    local numericObserved = tonumber(observedAmount)
    if numericObserved == nil then
        return false
    end
    local queue = prunePendingInjectedXp(playerKey)
    if type(queue) ~= "table" then
        return false
    end
    local observedSign = numericObserved >= 0 and 1 or -1
    local observedAbs = math.abs(numericObserved)
    for index, entry in ipairs(queue) do
        local expectedSign = tonumber(entry.sign) or 1
        local expectedAbs = tonumber(entry.amount) or 0
        local tolerance = math.max(0.05, expectedAbs * 0.25)
        if observedSign == expectedSign and math.abs(observedAbs - expectedAbs) <= tolerance then
            table.remove(queue, index)
            if #queue <= 0 then
                pendingInjectedXpByPlayerKey[playerKey] = nil
            end
            return true
        end
    end
    return false
end

local function addXp(owner, perkType, amount)
    if not owner or not perkType then
        return false
    end
    local xp = safeCall(owner, "getXp")
    if not xp then
        return false
    end
    if GameServer and type(GameServer.addXp) == "function" and isServerRuntime and owner and isIsoPlayer(owner) then
        local ok = pcall(GameServer.addXp, owner, perkType, amount, true)
        if ok then
            return true
        end
        return pcall(GameServer.addXp, owner, perkType, amount)
    end
    if type(GameClient) == "table" and GameClient.client == true and isClientRuntime then
        return false
    end
    local ok = safeInvoke(xp, "AddXP", perkType, amount, true)
    if ok then
        return true
    end
    ok = safeInvoke(xp, "AddXP", perkType, amount, false)
    if ok then
        return true
    end
    ok = safeInvoke(xp, "AddXP", perkType, amount)
    return ok
end

local function onAddXp(owner, perkType, amount)
    if not isStrengthPerk(perkType) then
        return
    end

    if not isIsoPlayer(owner) then
        return
    end

    local baseAmount = toNumber(amount)
    if baseAmount == nil or baseAmount <= 0 then
        return
    end

    local playerKey = getPlayerKey(owner)
    if playerKey and addXpReentryByPlayerKey[playerKey] then
        return
    end
    if shouldSuppressInjectedXpEvent(playerKey, baseAmount) then
        return
    end

    local state = getState(owner)
    if type(state) ~= "table" then
        return
    end

    local proteins = tonumber(state.proteins)
    local weightKg = tonumber(state.weightKg) or Metabolism.DEFAULT_WEIGHT_KG
    if proteins == nil or not Metabolism.getStrengthXpProteinMultiplier then
        return
    end

    local multiplier = tonumber(Metabolism.getStrengthXpProteinMultiplier(proteins, weightKg)) or 1.0
    if multiplier <= 0 then
        return
    end

    local bonusAmount = baseAmount * (multiplier - 1.0)
    if math.abs(bonusAmount) < 0.0001 then
        return
    end

    local pendingToken = enqueuePendingInjectedXp(playerKey, bonusAmount)
    if playerKey then
        addXpReentryByPlayerKey[playerKey] = true
    end
    local ok, appliedOrErr = pcall(addXp, owner, perkType, bonusAmount)
    if playerKey then
        addXpReentryByPlayerKey[playerKey] = nil
    end
    if not ok or appliedOrErr ~= true then
        removePendingInjectedXpEntry(playerKey, pendingToken)
        log(string.format(
            "[NMS_XP][ERROR] player=%s err=%s",
            tostring(getPlayerLabel(owner)),
            tostring(appliedOrErr)
        ))
    end
end

function Runtime.installProteinXpHooks()
    if Runtime._proteinXpHooksInstalled then
        return Runtime
    end
    Runtime._proteinXpHooksInstalled = true

    if Events and Events.AddXP and type(Events.AddXP.Add) == "function" then
        Events.AddXP.Add(onAddXp)
    end
    return Runtime
end

return Runtime
