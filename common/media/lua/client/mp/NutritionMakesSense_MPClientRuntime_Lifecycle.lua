NutritionMakesSense = NutritionMakesSense or {}

local MPClient = NutritionMakesSense.MPClientRuntime or {}
local state = MPClient._state or {}

local MP = MPClient.MP or {}
local Runtime = MPClient.Runtime or {}
local log = MPClient.log
local isClientRuntime = MPClient.isClientRuntime
local getLocalPlayer = MPClient.getLocalPlayer
local getPlayerLabel = MPClient.getPlayerLabel
local registerHooks = MPClient.registerHooks or function() end

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) ~= tostring(MP.STATE_SNAPSHOT_COMMAND) then
        return
    end
    if not isClientRuntime() or type(args) ~= "table" then
        return
    end

    state.latestSnapshot = args
    local playerObj = getLocalPlayer(0, nil)
    if playerObj and Runtime.importStateSnapshot then
        Runtime.importStateSnapshot(playerObj, args, args.reason or "mp-server")
    end

    log(string.format(
        "[CLIENT_SNAPSHOT] reason=%s bootstrap=%s event=%s fuel=%.1f zone=%s",
        tostring(args.reason or "server"),
        tostring(args.bootstrap == true),
        tostring(args.eventId or "none"),
        tonumber(args.state and args.state.fuel or 0),
        tostring(args.state and args.state.lastZone or "unknown")
    ))
end

local function onCreatePlayer(playerIndex, playerObj)
    registerHooks()

    if not isClientRuntime() then
        return
    end

    MPClient.requestSnapshot("create-player", true)

    if state.bootLogged then
        return
    end
    state.bootLogged = true

    log(string.format(
        "[CLIENT_READY] player=%s version=%s module=%s",
        tostring(getPlayerLabel(playerObj, playerIndex)),
        tostring(MP.SCRIPT_VERSION or "0.1.0"),
        tostring(MP.NET_MODULE or "NutritionMakesSenseRuntime")
    ))
end

function MPClient.install()
    if MPClient._installed then
        return MPClient
    end
    MPClient._installed = true

    if Events then
        if Events.OnServerCommand and type(Events.OnServerCommand.Add) == "function" then
            Events.OnServerCommand.Add(onServerCommand)
        end
        if Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
            Events.OnCreatePlayer.Add(onCreatePlayer)
        end
    end

    return MPClient
end

return MPClient
