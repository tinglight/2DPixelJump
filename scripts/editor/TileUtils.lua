-- ====================================================================
-- editor/TileUtils.lua - 地块工具纯函数（无副作用）
-- ====================================================================

local C = require "editor.Constants"
local TILE = C.TILE

local M = {}

--- 解析组合地块值，返回基础类型和颜色组号
---@param value number|nil
---@return number baseType
---@return number group
function M.GetTileType(value)
    if not value then return TILE.EMPTY, 0 end
    if value >= 100 then
        return value % 100, math.floor(value / 100)
    end
    return value, 0
end

--- 将基础类型和组号合成存储值
---@param baseType number
---@param group number
---@return number
function M.MakeTileValue(baseType, group)
    local needsGroup = (baseType == TILE.SWITCH
        or baseType == TILE.GATE
        or baseType == TILE.HIDDEN_WALL)
    if needsGroup and group > 0 then
        return group * 100 + baseType
    end
    return baseType
end

--- 判断地块是否可被选取（非空、非碰撞）
---@param levelData table
---@param col number
---@param row number
---@param mapCols number
---@param mapRows number
---@return boolean
function M.IsTileSelectable(levelData, col, row, mapCols, mapRows)
    if col < 1 or col > mapCols then return false end
    if row < 1 or row > mapRows then return false end
    local val = levelData[row][col]
    if val == TILE.EMPTY or val == TILE.SOLID or val == TILE.SOLID_PILLAR or val == TILE.SOLID_SEWER
        or val == TILE.SLOPE_TR or val == TILE.SLOPE_TL or val == TILE.SLOPE_BR or val == TILE.SLOPE_BL then
        return false
    end
    return true
end

--- 屏幕坐标转网格坐标
---@param sx number
---@param sy number
---@param cameraX number
---@param cameraY number
---@param zoomLevel number
---@return number col
---@return number row
function M.ScreenToGrid(sx, sy, cameraX, cameraY, zoomLevel)
    local localX = (sx + cameraX) / zoomLevel
    local localY = (sy - C.TOPBAR_H + cameraY) / zoomLevel
    return math.floor(localX / C.GRID) + 1, math.floor(localY / C.GRID) + 1
end

--- 网格坐标转屏幕坐标
---@param col number
---@param row number
---@param cameraX number
---@param cameraY number
---@param zoomLevel number
---@return number sx
---@return number sy
function M.GridToScreen(col, row, cameraX, cameraY, zoomLevel)
    local sx = (col - 1) * C.GRID * zoomLevel - cameraX
    local sy = (row - 1) * C.GRID * zoomLevel - cameraY + C.TOPBAR_H
    return sx, sy
end

--- 检测鼠标是否在摄像机边界的某条边附近
---@param mx number
---@param my number
---@param camBound table
---@param cameraX number
---@param cameraY number
---@param zoomLevel number
---@param screenDesignW number
---@param screenDesignH number
---@param sidebarOpen boolean
---@return number edgeId
function M.DetectBoundEdge(mx, my, camBound, cameraX, cameraY, zoomLevel, screenDesignW, screenDesignH, sidebarOpen)
    local mapY = C.TOPBAR_H
    local mapW = screenDesignW - (sidebarOpen and C.SIDEBAR_W or 0)
    local mapH = screenDesignH - C.TOPBAR_H - C.BOTTOMBAR_H
    if mx < 0 or mx > mapW or my < mapY or my > mapY + mapH then
        return C.BOUND_EDGE_NONE
    end

    local leftX = M.GridToScreen(camBound.left, camBound.top, cameraX, cameraY, zoomLevel)
    local rightX = M.GridToScreen(camBound.right + 1, camBound.bottom + 1, cameraX, cameraY, zoomLevel)
    local _, leftY = M.GridToScreen(camBound.left, camBound.top, cameraX, cameraY, zoomLevel)
    local _, rightY = M.GridToScreen(camBound.right + 1, camBound.bottom + 1, cameraX, cameraY, zoomLevel)

    local threshold = C.BOUND_DRAG_THRESHOLD

    if math.abs(mx - rightX) < threshold and my >= leftY and my <= rightY then
        return C.BOUND_EDGE_RIGHT
    end
    if math.abs(mx - leftX) < threshold and my >= leftY and my <= rightY then
        return C.BOUND_EDGE_LEFT
    end
    if math.abs(my - rightY) < threshold and mx >= leftX and mx <= rightX then
        return C.BOUND_EDGE_BOTTOM
    end
    if math.abs(my - leftY) < threshold and mx >= leftX and mx <= rightX then
        return C.BOUND_EDGE_TOP
    end

    return C.BOUND_EDGE_NONE
end

--- 解析管道地块值，返回开关组和水类型索引
--- 存储格式: (switchGroup * 10 + waterTypeIndex) * 100 + PIPE
---@param value number
---@return number switchGroup
---@return number waterTypeIndex
function M.ParsePipeValue(value)
    if not value then return 0, 1 end
    local encoded = math.floor(value / 100)
    local switchGroup = math.floor(encoded / 10)
    local waterTypeIndex = encoded % 10
    if waterTypeIndex < 1 then waterTypeIndex = 1 end
    return switchGroup, waterTypeIndex
end

--- 构建管道地块值
---@param switchGroup number
---@param waterTypeIndex number
---@return number
function M.MakePipeValue(switchGroup, waterTypeIndex)
    return (switchGroup * 10 + waterTypeIndex) * 100 + TILE.PIPE
end

return M
