NutritionMakesSense = NutritionMakesSense or {}

NutritionMakesSense.MP = NutritionMakesSense.MP or {}
local MP = NutritionMakesSense.MP

MP.NET_MODULE = "NutritionMakesSenseRuntime"
MP.MOD_STATE_KEY = "NutritionMakesSenseState"
MP.REQUEST_SNAPSHOT_COMMAND = "requestSnapshot"
MP.REPORT_WORKLOAD_COMMAND = "reportWorkload"
MP.CONSUME_ITEM_COMMAND = "consumeItem"
MP.STATE_SNAPSHOT_COMMAND = "stateSnapshot"
MP.SCRIPT_VERSION = "0.1.0"

return MP
