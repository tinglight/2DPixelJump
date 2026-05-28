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

    if oldBase == TILE.SOLID then return end

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
    if tileType == TILE.SOLID then
        local oldBase = TileUtils.GetTileType(oldVal)
        if oldBase == TILE.HIDDEN_WALL then return end
    end
    S.levelData[row][col] = tileType
    Undo.RecordTileChange(col, row, oldVal, tileType)
end

--- 擦除地块
---@param col number
---@param row number
function M.EraseTile(col, row)
    if col < 1 or col > S.MAP_COLS then return end
    if row < 1 or row > S.MAP_ROWS then return end
    if S.levelData[row][col] == TILE.SPAWN then return end
    local oldVal = S.levelData[row][col]
    S.levelData[row][col] = TILE.EMPTY
    Undo.RecordTileChange(col, row, oldVal, TILE.EMPTY)
end

return M
