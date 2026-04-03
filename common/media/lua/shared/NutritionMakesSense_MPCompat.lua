NutritionMakesSense = NutritionMakesSense or {}

NutritionMakesSense.MP = NutritionMakesSense.MP or {}
local MP = NutritionMakesSense.MP

MP.NET_MODULE = "NutritionMakesSenseRuntime"
MP.MOD_STATE_KEY = "NutritionMakesSenseState"
MP.REQUEST_SNAPSHOT_COMMAND = "requestSnapshot"
MP.REPORT_WORKLOAD_COMMAND = "reportWorkload"
MP.CONSUME_ITEM_COMMAND = "consumeItem"
MP.STATE_SNAPSHOT_COMMAND = "stateSnapshot"
MP.COMPAT_TRACE_START_COMMAND = "compatTraceStart"
MP.COMPAT_TRACE_STOP_COMMAND = "compatTraceStop"
MP.COMPAT_TRACE_STATUS_COMMAND = "compatTraceStatus"
MP.SCRIPT_VERSION = "1.0.1"

return MP
