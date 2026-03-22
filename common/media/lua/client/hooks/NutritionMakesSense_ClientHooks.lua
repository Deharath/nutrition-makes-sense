NutritionMakesSense = NutritionMakesSense or {}

require "ui/NutritionMakesSense_UIHelpers"

local Runtime = NutritionMakesSense.MetabolismRuntime or {}
local Metabolism = NutritionMakesSense.Metabolism or {}
local UIHelpers = NutritionMakesSense.UIHelpers or {}

local ClientHooks = NutritionMakesSense.ClientHooks or {}
NutritionMakesSense.ClientHooks = ClientHooks

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
end

local nmsMeleePenalty = {}

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

    local weaponId = UIHelpers.safeCall(weapon, "getID") or tostring(weapon)
    local origMin = UIHelpers.safeCall(weapon, "getMinDamage") or 0
    local origMax = UIHelpers.safeCall(weapon, "getMaxDamage") or 0
    nmsMeleePenalty[weaponId] = { minDmg = origMin, maxDmg = origMax }
    UIHelpers.safeCall(weapon, "setMinDamage", origMin * mult)
    UIHelpers.safeCall(weapon, "setMaxDamage", origMax * mult)
end

local function onMeleeAttackFinished(playerObj, weapon)
    if not playerObj or not weapon then
        return
    end

    local weaponId = UIHelpers.safeCall(weapon, "getID") or tostring(weapon)
    local saved = nmsMeleePenalty[weaponId]
    if saved then
        UIHelpers.safeCall(weapon, "setMinDamage", saved.minDmg)
        UIHelpers.safeCall(weapon, "setMaxDamage", saved.maxDmg)
        nmsMeleePenalty[weaponId] = nil
    end
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
