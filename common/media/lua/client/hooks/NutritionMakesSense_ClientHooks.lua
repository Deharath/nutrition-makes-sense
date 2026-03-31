NutritionMakesSense = NutritionMakesSense or {}

require "ui/NutritionMakesSense_UIHelpers"

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}
local UIHelpers = NutritionMakesSense.UIHelpers or {}

local ClientHooks = NutritionMakesSense.ClientHooks or {}
NutritionMakesSense.ClientHooks = ClientHooks

local nmsMeleePenalty = {}

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
    return 0
end

local function getWeaponId(weapon)
    return UIHelpers.safeCall(weapon, "getID") or tostring(weapon)
end

local function restoreMeleePenalty(weaponId, penalty)
    if not penalty then
        return
    end

    local weapon = penalty.weapon
    if weapon then
        UIHelpers.safeCall(weapon, "setMinDamage", penalty.minDmg)
        UIHelpers.safeCall(weapon, "setMaxDamage", penalty.maxDmg)
    end
    nmsMeleePenalty[weaponId] = nil
end

local function cleanupMeleePenalties(playerObj)
    if not playerObj then
        return
    end

    local activeWeapon = UIHelpers.safeCall(playerObj, "getPrimaryHandItem") or UIHelpers.safeCall(playerObj, "getWeapon")
    local activeWeaponId = activeWeapon and getWeaponId(activeWeapon) or nil
    local nowSecond = getWallClockSeconds()

    for weaponId, penalty in pairs(nmsMeleePenalty) do
        if penalty.player == playerObj then
            local expired = nowSecond > 0 and tonumber(penalty.appliedAt) ~= nil and (nowSecond - penalty.appliedAt) >= 2
            if activeWeaponId ~= weaponId or expired then
                restoreMeleePenalty(weaponId, penalty)
            end
        end
    end
end

local function onPlayerUpdate(playerObj)
    if not playerObj then
        return
    end
    if type(getPlayer) == "function" and playerObj ~= getPlayer() then
        return
    end

    if Runtime and type(Runtime.syncVisibleIndicators) == "function" then
        Runtime.syncVisibleIndicators(playerObj, "client-player-update")
    end
    cleanupMeleePenalties(playerObj)
end

local function onMeleeAttackStart(character, chargeDelta, weapon)
    if not character or not weapon then
        return
    end
    if not instanceof(character, "IsoPlayer") then
        return
    end
    if UIHelpers.safeCall(weapon, "isRanged") then
        return
    end

    if not Runtime or not Metabolism then
        return
    end

    local state = Runtime.ensureStateForPlayer and Runtime.ensureStateForPlayer(character)
    if not state then
        return
    end

    local mult = Metabolism.getMeleeDamageMultiplier(state.deprivation)
    if mult >= 1.0 then
        return
    end

    local weaponId = getWeaponId(weapon)
    local origMin = UIHelpers.safeCall(weapon, "getMinDamage") or 0
    local origMax = UIHelpers.safeCall(weapon, "getMaxDamage") or 0
    nmsMeleePenalty[weaponId] = {
        weapon = weapon,
        player = character,
        minDmg = origMin,
        maxDmg = origMax,
        appliedAt = getWallClockSeconds(),
    }
    UIHelpers.safeCall(weapon, "setMinDamage", origMin * mult)
    UIHelpers.safeCall(weapon, "setMaxDamage", origMax * mult)
end

local function onMeleeAttackFinished(playerObj, weapon)
    if not playerObj or not weapon then
        return
    end

    local weaponId = getWeaponId(weapon)
    restoreMeleePenalty(weaponId, nmsMeleePenalty[weaponId])
end

local function install()
    if ClientHooks._installed then
        return ClientHooks
    end
    ClientHooks._installed = true

    if Events then
        if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
            Events.OnPlayerUpdate.Add(onPlayerUpdate)
        end
        if Events.OnPlayerAttackFinished and type(Events.OnPlayerAttackFinished.Add) == "function" then
            Events.OnPlayerAttackFinished.Add(onMeleeAttackFinished)
        end
    end

    if Hook and Hook.Attack and type(Hook.Attack.Add) == "function" then
        Hook.Attack.Add(onMeleeAttackStart)
    end

    return ClientHooks
end

ClientHooks.install = install

return ClientHooks
