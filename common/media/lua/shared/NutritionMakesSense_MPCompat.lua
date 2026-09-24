NutritionMakesSense = NutritionMakesSense or {}

NutritionMakesSense.MP = NutritionMakesSense.MP or {}
local MP = NutritionMakesSense.MP

MP.NET_MODULE = "NutritionMakesSenseRuntime"
MP.MOD_STATE_KEY = "NutritionMakesSenseState"
MP.REQUEST_SNAPSHOT_COMMAND = "requestSnapshot"
MP.REPORT_WORKLOAD_COMMAND = "reportWorkload"
MP.DISPLAY_SNAPSHOT_COMMAND = "displaySnapshot"
MP.SCRIPT_VERSION = "2.0.0"

return MP
