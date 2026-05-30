-- ====================================================================
-- editor/Placement.lua - 地块放置/擦除（副作用模块）
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"
local Undo = require "editor.UndoSystem"
local TileUtils = require "editor.TileUtils"

local TILE = C.TILE
local M = {}

--- 放置地块到指定位置
---@param col number
---@param row number
function M.PlaceTile(col, row)
    if col < 1 or col > S.MAP_COLS then return end
    if row < 1 or row > S.MAP_ROWS then return end

    local tool = C.TOOLS[S.currentTool]
    local tileType = tool.tile

    if tileType == TILE.SPAWN then
        M.PlaceSpawn(col, row)
    elseif tileType == TILE.SWITCH or tileType == TILE.GATE then
        M.PlaceGrouped(col, row, tileType)
    elseif tileType == TILE.HIDDEN_WALL then
        M.PlaceHiddenWall(col, row)
    elseif tileType == TILE.LADDER then
        M.PlaceLadder(col, row)
    elseif tileType == TILE.PIPE then
        M.PlacePipe(col, row)
    else
        M.PlaceSimple(col, row, tileType)
    end
end

--- 放置出生点（清除旧位置）
---@param col number
---@param row number
function M.PlaceSpawn(col, row)
    local oldCol, oldRow = S.spawnCol, S.spawnRow
    for r = 1, S.MAP_ROWS do
        for c = 1, S.MAP_COLS do
            if S.levelData[r][c] == TILE.SPAWN then
                S.levelData[r][c] = TILE.EMPTY
            end
        end
    end
    S.spawnCol = col
    S.spawnRow = row
    S.levelData[row][col] = TILE.SPAWN
    Undo.RecordSpawnChange(oldCol, oldRow, col, row)
end

--- 放置带颜色组的地块（开关/门）
---@param col number
---@param row number
---@param tileType number
function M.PlaceGrouped(col, row, tileType)
    local oldVal = S.levelData[row][col]
    local newVal = TileUtils.MakeTileValue(tileType, S.currentGroup)
    S.levelData[row][col] = newVal
    Undo.RecordTileChange(col, row, oldVal, newVal)
end

--- 放置隐藏墙（含分组超时逻辑）
---@param col number
---@param row number
function M.PlaceHiddenWall(col, row)
    local oldVal = S.levelData[row][col]
    local oldBase, oldGroup = TileUtils.GetTileType(oldVal)

    if oldBase == TILE.SOLID or oldBase == TILE.SOLID_PILLAR or oldBase == TILE.SOLID_SEWER
        or oldBase == TILE.SLOPE_TR or oldBase == TILE.SLOPE_TL or oldBase == TILE.SLOPE_BR or oldBase == TILE.SLOPE_BL then return end

    if oldBase == TILE.HIDDEN_WALL then
        S.hiddenWall.group = oldGroup
        S.hiddenWall.lastEditTime = S.editorClock
        return
    end

    if S.hiddenWall.lastEditTime > 0 then
        local elapsed = S.editorClock - S.hiddenWall.lastEditTime
        if elapsed > S.hiddenWall.timeout then
            S.hiddenWall.group = S.hiddenWall.group + 1
        end
    end
    S.hiddenWall.lastEditTime = S.editorClock

    local newVal = TileUtils.MakeTileValue(TILE.HIDDEN_WALL, S.hiddenWall.group)
    S.levelData[row][col] = newVal
    Undo.RecordTileChange(col, row, oldVal, newVal)
end

--- 放置普通地块
---@param col number
---@param row number
---@param tileType number
function M.PlaceSimple(col, row, tileType)
    local oldVal = S.levelData[row][col]
    if tileType == TILE.SOLID or tileType == TILE.SOLID_PILLAR or tileType == TILE.SOLID_SEWER
        or tileType == TILE.SLOPE_TR or tileType == TILE.SLOPE_TL or tileType == TILE.SLOPE_BR or tileType == TILE.SLOPE_BL then
        local oldBase = TileUtils.GetTileType(oldVal)
        if oldBase == TILE.HIDDEN_WALL then return end
    end
    S.levelData[row][col] = tileType
    Undo.RecordTileChange(col, row, oldVal, tileType)
end

--- 放置梯子（2格宽，匹配2x2玩家）
---@param col number
---@param row number
function M.PlaceLadder(col, row)
    for dx = 0, 1 do
        local c = col + dx
        if c >= 1 and c <= S.MAP_COLS then
            local oldVal = S.levelData[row][c]
            if oldVal ~= TILE.LADDER then
                S.levelData[row][c] = TILE.LADDER
                Undo.RecordTileChange(c, row, oldVal, TILE.LADDER)
            end
        end
    end
end

--- 放置管道（7x7区域）
---@param col number
---@param row number
function M.PlacePipe(col, row)
    local pw = C.PIPE_WIDTH
    local ph = C.PIPE_HEIGHT
    -- 确保不超出边界
    if col + pw - 1 > S.MAP_COLS or row + ph - 1 > S.MAP_ROWS then return end
    -- 构建管道值（带开关组和水类型）
    local newVal = TileUtils.MakePipeValue(S.currentGroup, 1)
    for dy = 0, ph - 1 do
        for dx = 0, pw - 1 do
            local c = col + dx
            local r = row + dy
            local oldVal = S.levelData[r][c]
            if oldVal ~= newVal then
                S.levelData[r][c] = newVal
                Undo.RecordTileChange(c, r, oldVal, newVal)
            end
        end
    end
end

--- 擦除地块（同时检查并删除装饰物）
---@param col number
---@param row number
function M.EraseTile(col, row)
    if col < 1 or col > S.MAP_COLS then return end
    if row < 1 or row > S.MAP_ROWS then return end

    -- 尝试删除该位置的装饰物
    local decoIdx = M.FindDecoration(col, row)
    if decoIdx then
        table.remove(S.decorations, decoIdx)
        Undo.dirty = true
        Undo.saveTimer = Undo.saveDelay
    end

    if S.levelData[row][col] == TILE.SPAWN then return end
    local oldVal = S.levelData[row][col]
    if oldVal == TILE.EMPTY then return end
    S.levelData[row][col] = TILE.EMPTY
    Undo.RecordTileChange(col, row, oldVal, TILE.EMPTY)
end

--- 查找指定格子上的装饰物（支持区域命中，锚点在中心）
---@param col number
---@param row number
---@return number|nil 索引或 nil
function M.FindDecoration(col, row)
    for i, deco in ipairs(S.decorations) do
        local decoType = C.DECORATION_TYPES[deco.typeId]
        if decoType then
            local halfW = math.ceil(decoType.size.w / 2)
            local halfH = math.ceil(decoType.size.h / 2)
            if col >= deco.col - halfW and col <= deco.col + halfW
               and row >= deco.row - halfH and row <= deco.row + halfH then
                return i
            end
        else
            if deco.col == col and deco.row == row then
                return i
            end
        end
    end
    return nil
end

return M
