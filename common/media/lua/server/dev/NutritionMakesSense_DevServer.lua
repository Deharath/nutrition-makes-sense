NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_Workload"
require "dev/NutritionMakesSense_DevTools"

-- Dev-build only. Dedicated server: runs dev tools and pushes dev state to each player.
local DevTools = NutritionMakesSense.DevTools
local Workload = NutritionMakesSense.Workload

local PUSH_SECONDS = 1
local lastPush = setmetatable({}, { __mode = "k" })

local function push(playerObj)
    local state = DevTools.inspect(playerObj)
    if state then
        sendServerCommand(playerObj, DevTools.NET_MODULE, DevTools.STATE_COMMAND, state)
    end
end

local function onClientCommand(module, command, playerObj, args)
    if module ~= DevTools.NET_MODULE or command ~= DevTools.TOOL_COMMAND or type(args) ~= "table" then
        return
    end
    DevTools.apply(playerObj, args.op, args.value)
    push(playerObj)
end

local function onPlayerUpdate(playerObj)
    local now = Workload.wallSeconds()
    if lastPush[playerObj] and (now - lastPush[playerObj]) < PUSH_SECONDS then
        return
    end
    lastPush[playerObj] = now
    push(playerObj)
end

if type(isServer) == "function" and isServer() then
    Events.OnClientCommand.Add(onClientCommand)
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
    print("[NutritionMakesSense] [DEV] server dev module active")
end
