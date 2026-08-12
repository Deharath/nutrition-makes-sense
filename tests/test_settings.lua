local Support = require "support"

NutritionMakesSense = nil
SandboxVars = nil
package.loaded["NutritionMakesSense_Settings"] = nil
local Settings = require "NutritionMakesSense_Settings"

Support.assertEqual(Settings.useCuratedFoodValues(), true,
    "curated values remain enabled by default")
Support.assertClose(Settings.getEnergyBurnMultiplier(), 1.0, 0.000001,
    "missing energy tuning preserves existing balance")
Support.assertClose(Settings.getAppetiteRateMultiplier(), 1.0, 0.000001,
    "missing appetite tuning preserves existing balance")

SandboxVars = {
    NutritionMakesSense = {
        UseCuratedFoodValues = false,
        EnergyBurnMultiplier = 0.65,
        AppetiteRateMultiplier = 1.4,
    },
}
Support.assertEqual(Settings.useCuratedFoodValues(), false,
    "nested sandbox booleans remain supported")
Support.assertClose(Settings.getEnergyBurnMultiplier(), 0.65, 0.000001,
    "nested energy tuning is read")
Support.assertClose(Settings.getAppetiteRateMultiplier(), 1.4, 0.000001,
    "nested appetite tuning is read")

SandboxVars = {
    ["NutritionMakesSense.EnergyBurnMultiplier"] = 0.01,
    ["NutritionMakesSense.AppetiteRateMultiplier"] = 9,
}
Support.assertClose(Settings.getEnergyBurnMultiplier(), Settings.MULTIPLIER_MIN, 0.000001,
    "energy tuning is clamped to the supported minimum")
Support.assertClose(Settings.getAppetiteRateMultiplier(), Settings.MULTIPLIER_MAX, 0.000001,
    "appetite tuning is clamped to the supported maximum")

print("nms sandbox settings characterization passed")
