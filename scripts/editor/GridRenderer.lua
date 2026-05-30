-- ====================================================================
-- editor/GridRenderer.lua - 地图网格与地块渲染、选中/拖拽/框选/悬停绘制
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"
local TileUtils = require "editor.TileUtils"
local SolidRenderer = require "SolidRenderer"

local TILE = C.TILE

local M = {}

-- 注入外部依赖
local FogOfWar = nil

function M.Inject(deps)
    FogOfWar = deps.FogOfWar
end

-- 检查某格是否为实体方块（用于邻居检测）
local function IsSolidAt(row, col)
    if row < 1 or row > S.MAP_ROWS or col < 1 or col > S.MAP_COLS then
        return false
    end
    if not S.levelData[row] then return false end
    local val = S.levelData[row][col]
    if not val or val == TILE.EMPTY then return false end
    local base = TileUtils.GetTileType(val)
    return base == TILE.SOLID or base == TILE.SOLID_PILLAR
end

-- ====================================================================
-- 内部：计算地图区域
-- ====================================================================
local function GetMapArea()
    local mapX = 0
    local mapY = C.TOPBAR_H
    local mapW = S.screenDesignW - (S.sidebarOpen and C.SIDEBAR_W or 0)
    local mapH = S.screenDesignH - C.TOPBAR_H - C.BOTTOMBAR_H
    return mapX, mapY, mapW, mapH
end

-- ====================================================================
-- 内部：计算可见行列范围
-- ====================================================================
local function GetVisibleRange(mapW, mapH, zGrid)
    local startCol = math.max(1, math.floor(S.cameraX / zGrid) + 1)
    local endCol = math.min(S.MAP_COLS, startCol + math.ceil(mapW / zGrid) + 2)
    local startRow = math.max(1, math.floor(S.cameraY / zGrid) + 1)
    local endRow = math.min(S.MAP_ROWS, startRow + math.ceil(mapH / zGrid) + 2)
    return startCol, endCol, startRow, endRow
end

-- ====================================================================
-- 内部：绘制网格线
-- ====================================================================
local function DrawGridLines(vg, mapX, mapY, mapH, startCol, endCol, startRow, endRow, zGrid)
    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        local x = mapX + (col - 1) * zGrid - S.cameraX
        local y1 = mapY + (startRow - 1) * zGrid - S.cameraY
        local y2 = mapY + endRow * zGrid - S.cameraY
        nvgMoveTo(vg, x, math.max(mapY, y1))
        nvgLineTo(vg, x, math.min(mapY + mapH, y2))
    end
    for row = startRow, endRow + 1 do
        local y = mapY + (row - 1) * zGrid - S.cameraY
        local x1 = mapX + (startCol - 1) * zGrid - S.cameraX
        local x2 = mapX + endCol * zGrid - S.cameraX
        nvgMoveTo(vg, math.max(mapX, x1), y)
        nvgLineTo(vg, math.min(mapX + mapX + (S.screenDesignW - (S.sidebarOpen and C.SIDEBAR_W or 0)), x2), y)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 20))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)
end

-- ====================================================================
-- 内部：绘制单个地块
-- ====================================================================
local function DrawTile(vg, base, group, px, py, zGrid, row, col)
    if base == TILE.SOLID or base == TILE.SOLID_PILLAR then
        -- 像素风格碰撞方块渲染（编辑器中以中等亮度展示，带轻微光照方向）
        local lighting = 0.7
        local ldx, ldy = 0.3, -0.5  -- 编辑器预览：固定的左上角光源方向
        local neighbors = {
            top    = IsSolidAt(row - 1, col),
            bottom = IsSolidAt(row + 1, col),
            left   = IsSolidAt(row, col - 1),
            right  = IsSolidAt(row, col + 1),
        }
        SolidRenderer.DrawSolid(vg, base, px, py, zGrid, lighting, ldx, ldy, col, row, neighbors)

    elseif base == TILE.SPAWN then
        nvgBeginPath(vg)
        nvgRect(vg, px, py, zGrid, zGrid)
        nvgFillColor(vg, nvgRGBA(60, 40, 10, 150))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + zGrid * 0.5, py + 2)
        nvgLineTo(vg, px + zGrid - 3, py + zGrid - 2)
        nvgLineTo(vg, px + 3, py + zGrid - 2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 180, 40, 255))
        nvgFill(vg)

    elseif base == TILE.FUEL then
        nvgBeginPath(vg)
        nvgCircle(vg, px + zGrid * 0.5, py + zGrid * 0.5, 6 * S.zoomLevel)
        nvgFillColor(vg, nvgRGBA(255, 80, 10, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, px + zGrid * 0.5, py + zGrid * 0.5, 3 * S.zoomLevel)
        nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
        nvgFill(vg)

    elseif base == TILE.GOAL then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + 2, py + 1, zGrid - 4, zGrid - 2, 2)
        nvgFillColor(vg, nvgRGBA(40, 180, 40, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + 2, py + 1, zGrid - 4, zGrid - 2, 2)
        nvgStrokeColor(vg, nvgRGBA(100, 255, 100, 255))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

    elseif base == TILE.SPIKE then
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + 2, py + zGrid - 2)
        nvgLineTo(vg, px + zGrid * 0.5, py + 2)
        nvgLineTo(vg, px + zGrid - 2, py + zGrid - 2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(200, 30, 30, 255))
        nvgFill(vg)

    elseif base == TILE.SWITCH then
        local gc = C.GROUP_COLORS[group] or C.GROUP_COLORS[1]
        nvgBeginPath(vg)
        nvgCircle(vg, px + zGrid * 0.5, py + zGrid * 0.5, 5 * S.zoomLevel)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, px + zGrid * 0.5 - 1, py + 3, 2, 5 * S.zoomLevel)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgFill(vg)

    elseif base == TILE.GATE then
        local gc = C.GROUP_COLORS[group] or C.GROUP_COLORS[1]
        nvgBeginPath(vg)
        nvgRect(vg, px + 1, py, zGrid - 2, zGrid)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 180))
        nvgFill(vg)
        for dx = 0, 2 do
            nvgBeginPath(vg)
            nvgRect(vg, px + 3 + dx * 5 * S.zoomLevel, py + 2, 2, zGrid - 4)
            nvgFillColor(vg, nvgRGBA(
                math.floor(gc[1] * 0.4),
                math.floor(gc[2] * 0.4),
                math.floor(gc[3] * 0.4), 255))
            nvgFill(vg)
        end

    elseif base == TILE.HIDDEN_WALL then
        local darken = math.max(0.3, 1.0 - (group - 1) * 0.12)
        local hr = math.floor(S.hiddenWall.baseColor[1] * darken)
        local hg = math.floor(S.hiddenWall.baseColor[2] * darken)
        local hb = math.floor(S.hiddenWall.baseColor[3] * darken)

        nvgBeginPath(vg)
        nvgRect(vg, px + 1, py + 1, zGrid - 2, zGrid - 2)
        nvgFillColor(vg, nvgRGBA(hr, hg, hb, 160))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRect(vg, px + 1, py + 1, zGrid - 2, zGrid - 2)
        nvgStrokeColor(vg, nvgRGBA(hr, hg, hb, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(7, 9 * S.zoomLevel))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgText(vg, px + zGrid * 0.5, py + zGrid * 0.5, tostring(group))

    elseif base == TILE.WATER then
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, zGrid - 1, zGrid - 1)
        nvgFillColor(vg, nvgRGBA(30, 90, 200, 180))
        nvgFill(vg)
        -- 波浪线指示
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + 2, py + zGrid * 0.4)
        nvgLineTo(vg, px + zGrid * 0.33, py + zGrid * 0.3)
        nvgLineTo(vg, px + zGrid * 0.66, py + zGrid * 0.4)
        nvgLineTo(vg, px + zGrid - 2, py + zGrid * 0.3)
        nvgStrokeColor(vg, nvgRGBA(150, 210, 255, 220))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

    elseif base == TILE.POISON_WATER then
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, zGrid - 1, zGrid - 1)
        nvgFillColor(vg, nvgRGBA(20, 150, 40, 180))
        nvgFill(vg)
        -- 骷髅标记
        nvgBeginPath(vg)
        nvgCircle(vg, px + zGrid * 0.5, py + zGrid * 0.4, 3 * S.zoomLevel)
        nvgFillColor(vg, nvgRGBA(200, 255, 200, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, px + zGrid * 0.35, py + zGrid * 0.65, zGrid * 0.3, 2)
        nvgFillColor(vg, nvgRGBA(200, 255, 200, 200))
        nvgFill(vg)

    elseif base == TILE.BLACK_WATER then
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, zGrid - 1, zGrid - 1)
        nvgFillColor(vg, nvgRGBA(50, 50, 60, 220))
        nvgFill(vg)
        -- 减速标记（水平线条）
        for i = 0, 2 do
            nvgBeginPath(vg)
            nvgRect(vg, px + 3, py + 4 + i * 4 * S.zoomLevel, zGrid - 6, 1)
            nvgFillColor(vg, nvgRGBA(100, 100, 120, 150))
            nvgFill(vg)
        end

    elseif base == TILE.CHECKPOINT then
        -- 篝火（编辑器视图：简化的火焰+底座图标）
        -- 底座石块
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + 2, py + zGrid - 5, zGrid - 4, 4, 1)
        nvgFillColor(vg, nvgRGBA(100, 80, 60, 255))
        nvgFill(vg)
        -- 火焰（橙色三角形）
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + zGrid * 0.5, py + 2)
        nvgLineTo(vg, px + zGrid - 4, py + zGrid - 5)
        nvgLineTo(vg, px + 4, py + zGrid - 5)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 140, 30, 240))
        nvgFill(vg)
        -- 火焰内芯（黄色）
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + zGrid * 0.5, py + 5)
        nvgLineTo(vg, px + zGrid * 0.65, py + zGrid - 6)
        nvgLineTo(vg, px + zGrid * 0.35, py + zGrid - 6)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 240, 100, 220))
        nvgFill(vg)

    elseif base == TILE.LADDER then
        -- 2格宽梯子：只由左半格绘制整体
        -- 如果左邻格也是梯子，则当前格是右半部分，跳过
        if col > 1 then
            local leftVal = S.levelData[row][col - 1]
            local leftBase = TileUtils.GetTileType(leftVal)
            if leftBase == TILE.LADDER then goto skipLadder end
        end
        do
            local W = zGrid * 2  -- 2格宽
            local railW = 2 * S.zoomLevel
            local railL = px + 1 * S.zoomLevel
            local railR = px + W - 3 * S.zoomLevel
            -- 侧柱（深棕色）
            nvgBeginPath(vg)
            nvgRect(vg, railL, py, railW, zGrid)
            nvgFillColor(vg, nvgRGBA(120, 75, 30, 255))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRect(vg, railR, py, railW, zGrid)
            nvgFillColor(vg, nvgRGBA(120, 75, 30, 255))
            nvgFill(vg)
            -- 横档（浅棕色，2根，跨越2格宽）
            local rungH = 1.5 * S.zoomLevel
            local rungY1 = py + zGrid * 0.3
            local rungY2 = py + zGrid * 0.7
            nvgBeginPath(vg)
            nvgRect(vg, railL, rungY1, railR + railW - railL, rungH)
            nvgFillColor(vg, nvgRGBA(180, 130, 60, 255))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRect(vg, railL, rungY2, railR + railW - railL, rungH)
            nvgFillColor(vg, nvgRGBA(180, 130, 60, 255))
            nvgFill(vg)
        end
        ::skipLadder::

    elseif base == TILE.PIPE then
        -- 5x5 管道：只由左上角锚点绘制整体
        local isAnchor = true
        if col > 1 then
            local leftVal = S.levelData[row][col - 1]
            if TileUtils.GetTileType(leftVal) == TILE.PIPE then isAnchor = false end
        end
        if isAnchor and row > 1 then
            local topVal = S.levelData[row - 1][col]
            if TileUtils.GetTileType(topVal) == TILE.PIPE then isAnchor = false end
        end
        if not isAnchor then goto skipPipe end
        do
            local switchGroup, waterTypeIndex = TileUtils.ParsePipeValue(S.levelData[row][col])
            local wColor = C.PIPE_WATER_COLORS[C.PIPE_WATER_TYPES[waterTypeIndex]]
                or C.PIPE_WATER_COLORS[TILE.WATER]
            local PW = zGrid * C.PIPE_WIDTH
            local PH = zGrid * C.PIPE_HEIGHT

            local cx = px + PW * 0.5
            local cy = py + PH * 0.5
            local outerR = math.min(PW, PH) * 0.45

            -- 管壁外圈（大圆形金属管，无底板背景）
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, outerR)
            nvgFillColor(vg, nvgRGBA(65, 70, 80, 255))
            nvgFill(vg)

            -- 管壁中圈（立体层次）
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, outerR * 0.88)
            nvgFillColor(vg, nvgRGBA(80, 85, 98, 255))
            nvgFill(vg)

            -- 顶部高光弧线（金属光泽）
            nvgBeginPath(vg)
            nvgArc(vg, cx, cy, outerR * 0.82, -2.5, -0.6, 1)
            nvgStrokeColor(vg, nvgRGBA(140, 145, 160, 180))
            nvgStrokeWidth(vg, 2.0 * S.zoomLevel)
            nvgStroke(vg)

            -- 管口黑洞（圆形深洞）
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, outerR * 0.62)
            nvgFillColor(vg, nvgRGBA(10, 12, 18, 255))
            nvgFill(vg)

            -- 管口内静态水面（底部积水弧）
            local waterR = outerR * 0.55
            nvgBeginPath(vg)
            nvgArc(vg, cx, cy, waterR, 0.5, 2.64, 1)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], 160))
            nvgFill(vg)

            -- 外圈轮廓
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, outerR)
            nvgStrokeColor(vg, nvgRGBA(35, 38, 45, 255))
            nvgStrokeWidth(vg, 1.5 * S.zoomLevel)
            nvgStroke(vg)

            -- 开关组指示器
            if switchGroup > 0 then
                local gc = C.GROUP_COLORS[switchGroup] or C.GROUP_COLORS[1]
                nvgBeginPath(vg)
                nvgCircle(vg, px + PW - 5 * S.zoomLevel, py + 5 * S.zoomLevel, 3 * S.zoomLevel)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 220))
                nvgFill(vg)
            end
        end
        ::skipPipe::

    elseif base == TILE.FRAGILE then
        -- 编辑器预览：沙土色方块 + 裂纹标记
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, zGrid - 1, zGrid - 1)
        nvgFillColor(vg, nvgRGBA(175, 145, 95, 255))
        nvgFill(vg)
        -- 顶部高光
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, zGrid - 1, 2)
        nvgFillColor(vg, nvgRGBA(215, 190, 135, 255))
        nvgFill(vg)
        -- X 标记表示脆弱
        nvgStrokeColor(vg, nvgRGBA(100, 65, 20, 180))
        nvgStrokeWidth(vg, 1.0)
        local m = 3
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + m, py + m)
        nvgLineTo(vg, px + zGrid - m, py + zGrid - m)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + zGrid - m, py + m)
        nvgLineTo(vg, px + m, py + zGrid - m)
        nvgStroke(vg)
    end
end

-- ====================================================================
-- 内部：绘制所有可见地块
-- ====================================================================
local function DrawTiles(vg, mapX, mapY, startCol, endCol, startRow, endRow, zGrid)
    for row = startRow, endRow do
        if not S.levelData[row] then goto continueRow end
        for col = startCol, endCol do
            local val = S.levelData[row][col]
            if not val or val == TILE.EMPTY then goto continueCol end
            local px = mapX + (col - 1) * zGrid - S.cameraX
            local py = mapY + (row - 1) * zGrid - S.cameraY
            local base, group = TileUtils.GetTileType(val)
            DrawTile(vg, base, group, px, py, zGrid, row, col)
            ::continueCol::
        end
        ::continueRow::
    end
end

-- ====================================================================
-- 内部：绘制摄像机边界
-- ====================================================================
local function DrawCameraBounds(vg, mapX, mapY, mapW, mapH)
    local bx1, by1 = TileUtils.GridToScreen(S.camBound.left, S.camBound.top, S.cameraX, S.cameraY, S.zoomLevel)
    local bx2, by2 = TileUtils.GridToScreen(S.camBound.right + 1, S.camBound.bottom + 1, S.cameraX, S.cameraY, S.zoomLevel)

    -- 边界外遮罩
    nvgBeginPath(vg)
    nvgRect(vg, mapX, mapY, mapW, mapH)
    nvgPathWinding(vg, NVG_HOLE)
    local cbx1 = math.max(mapX, bx1)
    local cby1 = math.max(mapY, by1)
    local cbx2 = math.min(mapX + mapW, bx2)
    local cby2 = math.min(mapY + mapH, by2)
    if cbx2 > cbx1 and cby2 > cby1 then
        nvgRect(vg, cbx1, cby1, cbx2 - cbx1, cby2 - cby1)
    end
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
    nvgFill(vg)

    -- 边界虚线框
    nvgBeginPath(vg)
    nvgRect(vg, bx1, by1, bx2 - bx1, by2 - by1)
    nvgStrokeColor(vg, nvgRGBA(0, 200, 255, 200))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)

    -- 角拖拽手柄
    local handleSize = 5
    local corners = { {bx1, by1}, {bx2, by1}, {bx1, by2}, {bx2, by2} }
    for _, c in ipairs(corners) do
        nvgBeginPath(vg)
        nvgRect(vg, c[1] - handleSize, c[2] - handleSize, handleSize * 2, handleSize * 2)
        nvgFillColor(vg, nvgRGBA(0, 200, 255, 255))
        nvgFill(vg)
    end

    -- 尺寸标注
    local boundW = S.camBound.right - S.camBound.left + 1
    local boundH = S.camBound.bottom - S.camBound.top + 1
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(0, 200, 255, 220))
    nvgText(vg, (bx1 + bx2) * 0.5, by1 - 3, boundW .. "x" .. boundH)
end

-- ====================================================================
-- 内部：绘制主角相机框（试玩时的可视区域指示）
-- ====================================================================
local function DrawPlayerCameraFrame(vg, mapX, mapY, mapW, mapH)
    -- 相机缩放
    local zoom = S.playerParams.cameraZoom or 1.0

    -- 试玩视口在世界中的像素尺寸
    local viewW = S.playViewW * zoom
    local viewH = S.playViewH * zoom

    -- 边界像素
    local boundLeftPx = (S.camBound.left - 1) * C.GRID
    local boundRightPx = S.camBound.right * C.GRID
    local boundTopPx = (S.camBound.top - 1) * C.GRID
    local boundBottomPx = S.camBound.bottom * C.GRID

    -- 水平：35% anchor（与 PlayMode.UpdateCamera 一致）
    local camMinX = boundLeftPx
    local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)
    local spawnPx = (S.spawnCol - 1) * C.GRID
    local targetCamX = spawnPx - viewW * 0.35
    local camX = math.max(camMinX, math.min(targetCamX, camMaxX))

    -- 垂直：50% anchor（与 PlayMode.UpdateCamera 一致）
    local camMinY = boundTopPx
    local camMaxY = math.max(boundTopPx, boundBottomPx - viewH)
    local spawnTopPx = (S.spawnRow - C.PLAYER_GRID_H) * C.GRID
    local targetCamY = spawnTopPx - viewH * 0.5
    local camY = math.max(camMinY, math.min(targetCamY, camMaxY))

    -- 转换为编辑器屏幕坐标（camX/camY 是世界像素，需乘 editor zoom 再减 editor camera）
    local frameX = camX * S.zoomLevel - S.cameraX
    local frameY = camY * S.zoomLevel - S.cameraY + C.TOPBAR_H
    local frameW = viewW * S.zoomLevel
    local frameH = viewH * S.zoomLevel

    -- 绘制半透明填充
    nvgBeginPath(vg)
    nvgRect(vg, frameX, frameY, frameW, frameH)
    nvgFillColor(vg, nvgRGBA(255, 180, 50, 15))
    nvgFill(vg)

    -- 绘制边框（橙色虚线风格）
    nvgBeginPath(vg)
    nvgRect(vg, frameX, frameY, frameW, frameH)
    nvgStrokeColor(vg, nvgRGBA(255, 180, 50, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 角标标注 "CAM"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 180, 50, 200))
    nvgText(vg, frameX + 2, frameY + 1, "CAM " .. S.playViewW .. "x" .. S.playViewH)
end

-- ====================================================================
-- 内部：绘制选中高亮（多选/单选）
-- ====================================================================
local function DrawSelectionHighlight(vg, zGrid)
    local pulse = math.abs(math.sin(os.clock() * 3.0))
    local alpha = math.floor(140 + pulse * 115)

    if #S.selectedTiles > 0 and not S.moveDragging then
        for _, sel in ipairs(S.selectedTiles) do
            local sx, sy = TileUtils.GridToScreen(sel.col, sel.row, S.cameraX, S.cameraY, S.zoomLevel)
            local strokeColor = sel.isLight and nvgRGBA(255, 220, 50, alpha) or nvgRGBA(50, 200, 255, alpha)
            local fillColor = sel.isLight and nvgRGBA(255, 220, 50, 30) or nvgRGBA(50, 200, 255, 30)

            nvgBeginPath(vg)
            nvgRect(vg, sx - 1, sy - 1, zGrid + 2, zGrid + 2)
            nvgStrokeColor(vg, strokeColor)
            nvgStrokeWidth(vg, 2.0)
            nvgStroke(vg)

            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, zGrid, zGrid)
            nvgFillColor(vg, fillColor)
            nvgFill(vg)
        end
    elseif S.selectedTileCol > 0 and S.selectedTileRow > 0 and not S.moveDragging then
        local sx, sy = TileUtils.GridToScreen(S.selectedTileCol, S.selectedTileRow, S.cameraX, S.cameraY, S.zoomLevel)
        local strokeColor = S.selectedIsLight and nvgRGBA(255, 220, 50, alpha) or nvgRGBA(50, 200, 255, alpha)
        local fillColor = S.selectedIsLight and nvgRGBA(255, 220, 50, 30) or nvgRGBA(50, 200, 255, 30)

        nvgBeginPath(vg)
        nvgRect(vg, sx - 1, sy - 1, zGrid + 2, zGrid + 2)
        nvgStrokeColor(vg, strokeColor)
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)

        nvgBeginPath(vg)
        nvgRect(vg, sx, sy, zGrid, zGrid)
        nvgFillColor(vg, fillColor)
        nvgFill(vg)
    end
end

-- ====================================================================
-- 内部：绘制框选矩形
-- ====================================================================
local function DrawBoxSelect(vg)
    if not S.boxSelectActive then return end
    local bsDx = math.abs(S.boxSelectCurrentX - S.boxSelectStartX)
    local bsDy = math.abs(S.boxSelectCurrentY - S.boxSelectStartY)
    if bsDx <= C.BOX_SELECT_THRESHOLD and bsDy <= C.BOX_SELECT_THRESHOLD then return end

    local bsX = math.min(S.boxSelectStartX, S.boxSelectCurrentX)
    local bsY = math.min(S.boxSelectStartY, S.boxSelectCurrentY)
    local bsW = math.abs(S.boxSelectCurrentX - S.boxSelectStartX)
    local bsH = math.abs(S.boxSelectCurrentY - S.boxSelectStartY)

    nvgBeginPath(vg)
    nvgRect(vg, bsX, bsY, bsW, bsH)
    nvgFillColor(vg, nvgRGBA(80, 160, 255, 30))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRect(vg, bsX, bsY, bsW, bsH)
    nvgStrokeColor(vg, nvgRGBA(80, 180, 255, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

-- ====================================================================
-- 内部：绘制移动拖拽预览（多选）
-- ====================================================================
local function DrawMultiMoveDragPreview(vg, zGrid)
    local offsetCol = S.moveDragCurrentCol - S.moveDragStartCol
    local offsetRow = S.moveDragCurrentRow - S.moveDragStartRow

    -- 检查全部可放置
    local selectedSet = {}
    for _, st in ipairs(S.selectedTiles) do
        selectedSet[st.row * 10000 + st.col] = true
    end

    local canPlaceAll = true
    if offsetCol ~= 0 or offsetRow ~= 0 then
        for _, st in ipairs(S.selectedTiles) do
            local nc = st.col + offsetCol
            local nr = st.row + offsetRow
            if nc < 1 or nc > S.MAP_COLS or nr < 1 or nr > S.MAP_ROWS then
                canPlaceAll = false; break
            end
            if not st.isLight then
                local destVal = S.levelData[nr] and S.levelData[nr][nc]
                if destVal and destVal ~= TILE.EMPTY and not selectedSet[nr * 10000 + nc] then
                    canPlaceAll = false; break
                end
            end
        end
    end

    for _, st in ipairs(S.selectedTiles) do
        -- 原位置虚线框
        local ox, oy = TileUtils.GridToScreen(st.col, st.row, S.cameraX, S.cameraY, S.zoomLevel)
        nvgBeginPath(vg)
        nvgRect(vg, ox, oy, zGrid, zGrid)
        nvgStrokeColor(vg, nvgRGBA(255, 100, 100, 120))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- 目标位置
        local nc = st.col + offsetCol
        local nr = st.row + offsetRow
        if nc >= 1 and nc <= S.MAP_COLS and nr >= 1 and nr <= S.MAP_ROWS then
            local tx, ty = TileUtils.GridToScreen(nc, nr, S.cameraX, S.cameraY, S.zoomLevel)
            local fillC = canPlaceAll and nvgRGBA(50, 255, 120, 60) or nvgRGBA(255, 60, 60, 60)
            local strokeC = canPlaceAll and nvgRGBA(50, 255, 120, 200) or nvgRGBA(255, 60, 60, 200)

            nvgBeginPath(vg)
            nvgRect(vg, tx, ty, zGrid, zGrid)
            nvgFillColor(vg, fillC)
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRect(vg, tx, ty, zGrid, zGrid)
            nvgStrokeColor(vg, strokeC)
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end
end

-- ====================================================================
-- 内部：绘制移动拖拽预览（单选）
-- ====================================================================
local function DrawSingleMoveDragPreview(vg, zGrid)
    -- 原位置
    local ox, oy = TileUtils.GridToScreen(S.moveDragStartCol, S.moveDragStartRow, S.cameraX, S.cameraY, S.zoomLevel)
    nvgBeginPath(vg)
    nvgRect(vg, ox, oy, zGrid, zGrid)
    nvgStrokeColor(vg, nvgRGBA(255, 100, 100, 120))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 目标位置
    local tx, ty = TileUtils.GridToScreen(S.moveDragCurrentCol, S.moveDragCurrentRow, S.cameraX, S.cameraY, S.zoomLevel)
    local canPlace = true
    if S.moveDragCurrentCol == S.moveDragStartCol and S.moveDragCurrentRow == S.moveDragStartRow then
        canPlace = true
    elseif S.moveDragLightIdx > 0 then
        canPlace = true
    else
        local destVal = S.levelData[S.moveDragCurrentRow] and S.levelData[S.moveDragCurrentRow][S.moveDragCurrentCol]
        if destVal and destVal ~= TILE.EMPTY then canPlace = false end
    end

    nvgBeginPath(vg)
    nvgRect(vg, tx, ty, zGrid, zGrid)
    nvgFillColor(vg, canPlace and nvgRGBA(50, 255, 120, 60) or nvgRGBA(255, 60, 60, 60))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRect(vg, tx, ty, zGrid, zGrid)
    nvgStrokeColor(vg, canPlace and nvgRGBA(50, 255, 120, 200) or nvgRGBA(255, 60, 60, 200))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)
end

-- ====================================================================
-- 内部：绘制悬停指示器
-- ====================================================================
local function DrawHoverIndicator(vg, mapW, zGrid)
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local my = input:GetMousePosition().y / S.dpr / S.scaleF
    local hoverCol, hoverRow = TileUtils.ScreenToGrid(mx, my, S.cameraX, S.cameraY, S.zoomLevel)

    if hoverCol >= 1 and hoverCol <= S.MAP_COLS and hoverRow >= 1 and hoverRow <= S.MAP_ROWS then
        local hx, hy = TileUtils.GridToScreen(hoverCol, hoverRow, S.cameraX, S.cameraY, S.zoomLevel)
        nvgBeginPath(vg)
        nvgRect(vg, hx, hy, zGrid, zGrid)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 120))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 180))
        nvgText(vg, hx + 1, hy - 1, hoverCol .. "," .. hoverRow)
    end
end

-- ====================================================================
-- 内部：绘制缩放比例
-- ====================================================================
local function DrawZoomIndicator(vg, mapW, mapY, mapH)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 180))
    nvgText(vg, mapW - 4, mapY + mapH - 3, math.floor(S.zoomLevel * 100) .. "%")
end

-- ====================================================================
-- Draw - 绘制完整地图网格
-- ====================================================================
function M.Draw()
    local vg = S.vg
    local mapX, mapY, mapW, mapH = GetMapArea()
    local zGrid = C.GRID * S.zoomLevel

    nvgSave(vg)
    nvgScissor(vg, mapX, mapY, mapW, mapH)

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, mapX, mapY, mapW, mapH)
    nvgFillColor(vg, nvgRGBA(15, 12, 25, 255))
    nvgFill(vg)

    -- 背景图（铺满 camBound 区域）
    if S.backgroundImage ~= "" then
        -- 懒加载 NanoVG 图片句柄
        if not S.bgImageHandle then
            S.bgImageHandle = nvgCreateImage(vg, S.backgroundImage, 0)
        end
        if S.bgImageHandle and S.bgImageHandle > 0 then
            -- 计算 camBound 在屏幕上的位置
            local bx1 = mapX + (S.camBound.left - 1) * zGrid - S.cameraX
            local by1 = mapY + (S.camBound.top - 1) * zGrid - S.cameraY
            local bw = (S.camBound.right - S.camBound.left + 1) * zGrid
            local bh = (S.camBound.bottom - S.camBound.top + 1) * zGrid
            local imgPaint = nvgImagePattern(vg, bx1, by1, bw, bh, 0, S.bgImageHandle, S.bgImageAlpha or 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, bx1, by1, bw, bh)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        end
    end

    local startCol, endCol, startRow, endRow = GetVisibleRange(mapW, mapH, zGrid)

    DrawGridLines(vg, mapX, mapY, mapH, startCol, endCol, startRow, endRow, zGrid)
    DrawTiles(vg, mapX, mapY, startCol, endCol, startRow, endRow, zGrid)
    DrawCameraBounds(vg, mapX, mapY, mapW, mapH)
    DrawPlayerCameraFrame(vg, mapX, mapY, mapW, mapH)

    -- 光源标记
    if FogOfWar then
        FogOfWar.SetLightSources(FogOfWar.GetLightSources())
        FogOfWar.DrawLightMarkers(vg, {
            gridSize = C.GRID,
            offsetX = S.cameraX,
            offsetY = S.cameraY,
            zoomLevel = S.zoomLevel,
            mapX = mapX,
            mapY = mapY,
            selectedIndex = S.selectedLightIndex,
        })

        -- 战争迷雾
        if S.fogShowInEditor then
            FogOfWar.Draw(vg, {
                gridSize = C.GRID,
                startCol = startCol,
                endCol = endCol,
                startRow = startRow,
                endRow = endRow,
                offsetX = S.cameraX,
                offsetY = S.cameraY,
                zoomLevel = S.zoomLevel,
                mapX = mapX,
                mapY = mapY,
            })
        end
    end

    -- 选中 & 拖拽 & 框选
    DrawSelectionHighlight(vg, zGrid)
    DrawBoxSelect(vg)

    if S.moveDragging and S.moveDragCurrentCol > 0 and S.moveDragCurrentRow > 0 then
        if S.multiMoving and #S.selectedTiles > 0 then
            DrawMultiMoveDragPreview(vg, zGrid)
        else
            DrawSingleMoveDragPreview(vg, zGrid)
        end
    end

    DrawHoverIndicator(vg, mapW, zGrid)
    DrawZoomIndicator(vg, mapW, mapY, mapH)

    nvgRestore(vg)
end

return M
