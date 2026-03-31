NutritionMakesSense = NutritionMakesSense or {}

require "NutritionMakesSense_CoreUtils"

local ItemAuthority = NutritionMakesSense.ItemAuthority or {}
NutritionMakesSense.ItemAuthority = ItemAuthority
local CoreUtils = NutritionMakesSense.CoreUtils or {}

local safeCall = ItemAuthority.safeCall or CoreUtils.safeCall
local log = ItemAuthority.log
local getFoodEntry = ItemAuthority.getFoodEntry
local resolveEntrySource = ItemAuthority.resolveEntrySource
local resolveSnapshotMode = ItemAuthority.resolveSnapshotMode
local resolveAppliedSnapshot = ItemAuthority.resolveAppliedSnapshot
local snapshotsMatch = ItemAuthority.snapshotsMatch
local applySnapshot = ItemAuthority.applySnapshot
local warnAuthorityOnce = ItemAuthority.warnAuthorityOnce
local getStaticFoodValueSource = ItemAuthority.getStaticFoodValueSource
local visitList = CoreUtils.visitList
local eachKnownPlayer = CoreUtils.eachKnownPlayer

local function refreshBindings()
    ItemAuthority = NutritionMakesSense.ItemAuthority or ItemAuthority
    NutritionMakesSense.ItemAuthority = ItemAuthority
    CoreUtils = NutritionMakesSense.CoreUtils or CoreUtils
    safeCall = ItemAuthority.safeCall or CoreUtils.safeCall
    log = ItemAuthority.log
    getFoodEntry = ItemAuthority.getFoodEntry
    resolveEntrySource = ItemAuthority.resolveEntrySource
    resolveSnapshotMode = ItemAuthority.resolveSnapshotMode
    resolveAppliedSnapshot = ItemAuthority.resolveAppliedSnapshot
    snapshotsMatch = ItemAuthority.snapshotsMatch
    applySnapshot = ItemAuthority.applySnapshot
    warnAuthorityOnce = ItemAuthority.warnAuthorityOnce
    getStaticFoodValueSource = ItemAuthority.getStaticFoodValueSource
    visitList = CoreUtils.visitList
    eachKnownPlayer = CoreUtils.eachKnownPlayer or eachKnownPlayer
end

local function summarizeResult(summary, action)
    summary[action] = (summary[action] or 0) + 1
end

local syncItem
local visitContainer

local function newTraversalState(summary)
    return {
        summary = summary,
        seenItems = {},
        seenContainers = {},
        seenSquares = {},
        seenObjects = {},
        seenWorldObjects = {},
        seenVehicles = {},
        seenChunkMaps = {},
        surfaceCounts = {
            player = 0,
            world = 0,
            object = 0,
            vehicle = 0,
        },
        chunkMapsVisited = 0,
        squaresVisited = 0,
        objectsVisited = 0,
        worldObjectsVisited = 0,
        vehiclesVisited = 0,
        containersVisited = 0,
    }
end

local function recordSurfaceVisit(state, surface)
    if state and surface and state.surfaceCounts[surface] ~= nil then
        state.surfaceCounts[surface] = state.surfaceCounts[surface] + 1
    end
end

local function visitTrackedItem(item, state, mode, reason, surface)
    if not item or not state or state.seenItems[item] then
        return
    end

    state.seenItems[item] = true
    recordSurfaceVisit(state, surface)
    summarizeResult(state.summary, syncItem(item, mode, reason))

    if type(item.getItemContainer) == "function" then
        visitContainer(item:getItemContainer(), state, mode, reason, surface)
    end
end

visitContainer = function(container, state, mode, reason, surface)
    if not container or not state or state.seenContainers[container] or type(container.getItems) ~= "function" then
        return
    end

    state.seenContainers[container] = true
    state.containersVisited = state.containersVisited + 1

    visitList(container:getItems(), function(item)
        visitTrackedItem(item, state, mode, reason, surface)
    end)
end

local function visitObjectContainers(object, state, mode, reason)
    if not object or not state or state.seenObjects[object] then
        return
    end

    state.seenObjects[object] = true
    state.objectsVisited = state.objectsVisited + 1

    local primaryContainer = safeCall(object, "getItemContainer")
    if primaryContainer then
        visitContainer(primaryContainer, state, mode, reason, "object")
    end

    local containerCount = tonumber(safeCall(object, "getContainerCount")) or 0
    for containerIndex = 0, containerCount - 1 do
        local objectContainer = safeCall(object, "getContainerByIndex", containerIndex)
        if objectContainer then
            visitContainer(objectContainer, state, mode, reason, "object")
        end
    end
end

local function visitWorldInventoryObject(worldObject, state, mode, reason)
    if not worldObject or not state or state.seenWorldObjects[worldObject] then
        return
    end

    state.seenWorldObjects[worldObject] = true
    state.worldObjectsVisited = state.worldObjectsVisited + 1
    visitTrackedItem(safeCall(worldObject, "getItem"), state, mode, reason, "world")
end

local function visitSquare(square, state, mode, reason)
    if not square or not state or state.seenSquares[square] then
        return
    end

    state.seenSquares[square] = true
    state.squaresVisited = state.squaresVisited + 1

    visitList(safeCall(square, "getWorldObjects"), function(worldObject)
        visitWorldInventoryObject(worldObject, state, mode, reason)
    end)

    visitList(safeCall(square, "getObjects"), function(object)
        visitObjectContainers(object, state, mode, reason)
    end)
end

local function visitVehicle(vehicle, state, mode, reason)
    if not vehicle or not state or state.seenVehicles[vehicle] then
        return
    end

    state.seenVehicles[vehicle] = true
    state.vehiclesVisited = state.vehiclesVisited + 1

    local partCount = tonumber(safeCall(vehicle, "getPartCount")) or 0
    for partIndex = 0, partCount - 1 do
        local part = safeCall(vehicle, "getPartByIndex", partIndex)
        local vehicleContainer = part and safeCall(part, "getItemContainer") or nil
        if vehicleContainer then
            visitContainer(vehicleContainer, state, mode, reason, "vehicle")
        end
    end
end

local function getWorldCell()
    if type(getCell) == "function" then
        local cell = getCell()
        if cell then
            return cell
        end
    end

    if type(getWorld) == "function" then
        local world = getWorld()
        local cell = safeCall(world, "getCell")
        if cell then
            return cell
        end
    end

    return nil
end

local function visitChunkMap(chunkMap, cell, state, mode, reason)
    if not chunkMap or not state or state.seenChunkMaps[chunkMap] then
        return
    end

    local minX = tonumber(safeCall(chunkMap, "getWorldXMinTiles"))
    local maxX = tonumber(safeCall(chunkMap, "getWorldXMaxTiles"))
    local minY = tonumber(safeCall(chunkMap, "getWorldYMinTiles"))
    local maxY = tonumber(safeCall(chunkMap, "getWorldYMaxTiles"))
    if not minX or not maxX or not minY or not maxY then
        return
    end

    state.seenChunkMaps[chunkMap] = true
    state.chunkMapsVisited = state.chunkMapsVisited + 1

    local minZ = tonumber(cell and safeCall(cell, "getMinZ")) or 0
    local maxZ = tonumber(cell and safeCall(cell, "getMaxZ")) or 0

    for z = minZ, maxZ do
        for y = minY, maxY do
            for x = minX, maxX do
                visitSquare(safeCall(chunkMap, "getGridSquare", x, y, z), state, mode, reason)
            end
        end
    end
end

local function eachActiveChunkMap(callback)
    if type(callback) ~= "function" then
        return
    end

    local cell = getWorldCell()
    if not cell or type(cell.getChunkMap) ~= "function" then
        return cell
    end

    local seen = {}
    local yieldedAny = false

    local function yieldChunkMap(index)
        local chunkMap = safeCall(cell, "getChunkMap", index)
        if chunkMap and not seen[chunkMap] then
            seen[chunkMap] = true
            yieldedAny = true
            callback(chunkMap, cell, index)
        end
    end

    if type(getNumActivePlayers) == "function" then
        local playerCount = tonumber(getNumActivePlayers()) or 0
        for playerIndex = 0, playerCount - 1 do
            yieldChunkMap(playerIndex)
        end
    end

    if type(isServer) == "function" and isServer() and type(getOnlinePlayers) == "function" then
        local players = getOnlinePlayers()
        local playerCount = tonumber(players and safeCall(players, "size")) or 0
        for playerIndex = 0, playerCount - 1 do
            yieldChunkMap(playerIndex)
        end
    end

    if not yieldedAny then
        yieldChunkMap(0)
    end

    return cell
end

local function logTraversalSummary(tag, summary, state, mode, reason)
    if not summary or not state then
        return
    end

    if (summary.restored + summary.captured + summary.updated) <= 0 then
        return
    end

    log(string.format(
        "[%s] mode=%s reason=%s restored=%d captured=%d updated=%d unchanged=%d player=%d world=%d object=%d vehicle=%d chunk_maps=%d squares=%d containers=%d vehicles=%d",
        tostring(tag),
        tostring(mode or "capture"),
        tostring(reason),
        tonumber(summary.restored or 0),
        tonumber(summary.captured or 0),
        tonumber(summary.updated or 0),
        tonumber(summary.unchanged or 0),
        tonumber(state.surfaceCounts.player or 0),
        tonumber(state.surfaceCounts.world or 0),
        tonumber(state.surfaceCounts.object or 0),
        tonumber(state.surfaceCounts.vehicle or 0),
        tonumber(state.chunkMapsVisited or 0),
        tonumber(state.squaresVisited or 0),
        tonumber(state.containersVisited or 0),
        tonumber(state.vehiclesVisited or 0)
    ))
end

local function syncTraversedSurfaces(reason, mode, includeLoadedWorld)
    refreshBindings()
    pcall(function()
        if NutritionMakesSense.StablePatcher and NutritionMakesSense.StablePatcher.ensurePatched then
            NutritionMakesSense.StablePatcher.ensurePatched(tostring(reason or "item-authority"))
        end
    end)

    local summary = {
        restored = 0,
        captured = 0,
        updated = 0,
        unchanged = 0,
        ignored = 0,
    }
    local state = newTraversalState(summary)

    eachKnownPlayer(function(playerObj)
        if playerObj and type(playerObj.getInventory) == "function" then
            visitContainer(playerObj:getInventory(), state, mode or "capture", reason, "player")
        end
    end)

    if includeLoadedWorld then
        local cell = eachActiveChunkMap(function(chunkMap, activeCell)
            visitChunkMap(chunkMap, activeCell, state, mode or "capture", reason)
        end)

        if cell and state.chunkMapsVisited <= 0 then
            visitList(safeCall(cell, "getProcessWorldItems"), function(worldObject)
                visitWorldInventoryObject(worldObject, state, mode or "capture", reason)
            end)

            visitList(safeCall(cell, "getProcessIsoObjects"), function(object)
                visitObjectContainers(object, state, mode or "capture", reason)
            end)
        end

        if cell and type(cell.getVehicles) == "function" then
            visitList(cell:getVehicles(), function(vehicle)
                visitVehicle(vehicle, state, mode or "capture", reason)
            end)
        end
    end

    logTraversalSummary(includeLoadedWorld and "ITEM_AUTHORITY_PERSISTENCE_SYNC" or "ITEM_AUTHORITY_SYNC", summary, state, mode, reason)
    return summary
end

syncItem = function(item, mode, reason)
    refreshBindings()
    if not item then
        return "ignored"
    end
    if type(isClient) == "function" and isClient() == true
        and not (type(isServer) == "function" and isServer() == true)
    then
        return "ignored"
    end

    local isFood = safeCall(item, "isFood")
    if isFood == nil then
        isFood = safeCall(item, "IsFood")
    end
    if isFood == false then
        return "ignored"
    end

    local entry, fullType = getFoodEntry(item)
    if not entry or not fullType then
        return "ignored"
    end

    if type(resolveEntrySource) == "function" and type(resolveSnapshotMode) == "function" then
        local staticSource = type(getStaticFoodValueSource) == "function"
            and getStaticFoodValueSource(fullType, entry) or "authored"
        if resolveEntrySource(entry) == "authored"
            and resolveSnapshotMode(item, fullType, entry) == "static"
            and staticSource == "authored"
        then
            return "ignored"
        end
    end

    local applied, current, stored, defaults, resolvedSource = resolveAppliedSnapshot(item, fullType, entry)
    if not applied then
        warnAuthorityOnce(fullType, "missing-normalization-source")
        return "ignored"
    end

    if not current or not snapshotsMatch(current, applied) then
        applySnapshot(item, applied)
        log(string.format(
            "[ITEM_AUTHORITY] mode=%s reason=%s item=%s resolved=%s action=normalize",
            tostring(mode or "capture"),
            tostring(reason),
            tostring(fullType),
            tostring(applied and applied.nutritionSource or resolvedSource or "authored")
        ))
        return stored and "restored" or "captured"
    end

    if stored and not defaults then
        return "captured"
    end

    return "unchanged"
end

function ItemAuthority.restoreItem(item, reason)
    return syncItem(item, "restore", reason or "restore")
end

function ItemAuthority.syncPersistenceSurfaces(reason, mode)
    return syncTraversedSurfaces(reason, mode, true)
end

function ItemAuthority.syncPlayerInventories(reason, mode)
    return syncTraversedSurfaces(reason, mode, false)
end

return ItemAuthority
