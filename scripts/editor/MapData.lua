-- ====================================================================
-- editor/MapData.lua - 地图数据初始化与画布调整
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"
local FogOfWar = require "FogOfWar"

local TILE = C.TILE
local M = {}

--- 初始化空白地图
function M.InitEmptyMap()
    for row = 1, S.MAP_ROWS do
        S.levelData[row] = {}
        for col = 1, S.MAP_COLS do
            S.levelData[row][col] = TILE.EMPTY
        end
    end
    for col = 1, S.MAP_COLS do
        S.levelData[S.MAP_ROWS][col] = TILE.SOLID
        S.levelData[S.MAP_ROWS - 1][col] = TILE.SOLID
    end
    S.spawnCol = 3
    S.spawnRow = S.MAP_ROWS - 3
    FogOfWar.ClearAll()
    S.lightSources = FogOfWar.GetLightSources()
    S.selectedLightIndex = 0
end

--- 调整画布大小（保留已有数据）
---@param newCols number
---@param newRows number
function M.ResizeCanvas(newCols, newRows)
    newCols = math.max(10, math.min(200, newCols))
    newRows = math.max(5, math.min(100, newRows))

    local oldCols = S.MAP_COLS
    local oldRows = S.MAP_ROWS

    local newData = {}
    for row = 1, newRows do
        newData[row] = {}
        for col = 1, newCols do
            if row <= oldRows and col <= oldCols then
                newData[row][col] = S.levelData[row][col]
            else
                newData[row][col] = TILE.EMPTY
            end
        end
    end

    S.MAP_COLS = newCols
    S.MAP_ROWS = newRows
    S.levelData = newData

    M.ClampSpawnToBounds()
    M.ClampCamBoundToBounds()

    S.SetMessage("画布大小: " .. S.MAP_COLS .. "x" .. S.MAP_ROWS, 2.0)
end

--- 确保出生点在地图范围内
function M.ClampSpawnToBounds()
    if S.spawnCol > S.MAP_COLS then S.spawnCol = S.MAP_COLS end
    if S.spawnRow > S.MAP_ROWS then S.spawnRow = S.MAP_ROWS end
end

--- 确保摄像机边界在地图范围内
function M.ClampCamBoundToBounds()
    if S.camBound.right > S.MAP_COLS then
        S.camBound.right = S.MAP_COLS
    end
    if S.camBound.bottom > S.MAP_ROWS then
        S.camBound.bottom = S.MAP_ROWS
    end
    if S.camBound.left > S.camBound.right then
        S.camBound.left = 1
    end
    if S.camBound.top > S.camBound.bottom then
        S.camBound.top = 1
    end
end

return M
