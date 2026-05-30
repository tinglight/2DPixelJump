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
    return base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER
end

-- 检查某格是否为柱子（专门用于柱子拼接检测）
local function IsPillarAt(row, col)
    if row < 1 or row > S.MAP_ROWS or col < 1 or col > S.MAP_COLS then
        return false
    end
    if not S.levelData[row] then return false end
    local val = S.levelData[row][col]
    if not val or val == TILE.EMPTY then return false end
    local base = TileUtils.GetTileType(val)
    return base == TILE.SOLID_PILLAR
end

-- 检查某格是否为水体（用于下水道水边衔接检测）
local function IsWaterAt(row, col)
    if row < 1 or row > S.MAP_ROWS or col < 1 or col > S.MAP_COLS then
        return false
    end
    if not S.levelData[row] then return false end
    local val = S.levelData[row][col]
    if not val or val == TILE.EMPTY then return false end
    local base = TileUtils.GetTileType(val)
    return base == TILE.WATER or base == TILE.POISON_WATER or base == TILE.BLACK_WATER
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
    if base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER then
        -- 像素风格碰撞方块渲染（编辑器中以中等亮度展示，带轻微光照方向）
        local lighting = 0.7
        local ldx, ldy = 0.3, -0.5  -- 编辑器预览：固定的左上角光源方向
        local neighbors = {
            top    = IsSolidAt(row - 1, col),
            bottom = IsSolidAt(row + 1, col),
            left   = IsSolidAt(row, col - 1),
            right  = IsSolidAt(row, col + 1),
            -- 柱子拼接专用邻居检测
            pillarTop    = IsPillarAt(row - 1, col),
            pillarBottom = IsPillarAt(row + 1, col),
            pillarLeft   = IsPillarAt(row, col - 1),
            pillarRight  = IsPillarAt(row, col + 1),
        }
        -- 下水道瓦片额外检测：对角邻居 + 水体邻接
        if base == TILE.SOLID_SEWER then
            neighbors.topLeft     = IsSolidAt(row - 1, col - 1)
            neighbors.topRight    = IsSolidAt(row - 1, col + 1)
            neighbors.bottomLeft  = IsSolidAt(row + 1, col - 1)
            neighbors.bottomRight = IsSolidAt(row + 1, col + 1)
            neighbors.water = IsWaterAt(row + 1, col) or IsWaterAt(row, col - 1) or IsWaterAt(row, col + 1)
        end
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
        -- 2格宽梯子：只由左半格绘制整体（像素风+魂类腐朽风格）
        -- 如果左邻格也是梯子，则当前格是右半部分，跳过
        if col > 1 then
            local leftVal = S.levelData[row][col - 1]
            local leftBase = TileUtils.GetTileType(leftVal)
            if leftBase == TILE.LADDER then goto skipLadder end
        end
        do
            local Z = S.zoomLevel
            local P = 2 * Z      -- 像素块单元（2px基础×缩放），让格子感明显

            -- 颜色定义（暗色系、腐朽木质）
            local darkWood   = nvgRGBA(58, 40, 22, 255)
            local midWood    = nvgRGBA(82, 55, 30, 255)
            local hiWood     = nvgRGBA(105, 72, 38, 255)
            local rungMain   = nvgRGBA(95, 65, 35, 255)
            local rungHi     = nvgRGBA(120, 85, 48, 255)
            local shadowWood = nvgRGBA(35, 24, 12, 255)
            local moss1      = nvgRGBA(40, 85, 30, 255)
            local moss2      = nvgRGBA(58, 110, 42, 220)
            local vine       = nvgRGBA(32, 70, 28, 240)
            local decay      = nvgRGBA(50, 45, 25, 200)

            local lx = px
            local ly = py

            -- 辅助：画一个像素块
            local function pix(cx, cy, color)
                nvgBeginPath(vg) nvgRect(vg, lx + cx * P, ly + cy * P, P, P)
                nvgFillColor(vg, color) nvgFill(vg)
            end

            -- == 左侧柱（col 1-2, row 0-7）==
            for r = 0, 7 do
                pix(1, r, midWood)
                pix(2, r, darkWood)
            end
            pix(1, 0, hiWood)
            pix(1, 2, hiWood)
            pix(1, 5, hiWood)
            pix(2, 3, shadowWood)
            pix(1, 6, shadowWood)

            -- == 右侧柱（col 13-14, row 0-7）==
            for r = 0, 7 do
                pix(13, r, darkWood)
                pix(14, r, midWood)
            end
            pix(14, 1, hiWood)
            pix(14, 4, hiWood)
            pix(14, 6, hiWood)
            pix(13, 2, shadowWood)
            pix(14, 5, shadowWood)

            -- == 上横档（row 2, col 3-12）==
            for c = 3, 12 do
                pix(c, 2, rungMain)
            end
            pix(4, 2, rungHi)
            pix(6, 2, rungHi)
            pix(9, 2, rungHi)
            pix(11, 2, rungHi)
            for c = 3, 12 do
                pix(c, 3, shadowWood)
            end

            -- == 下横档（row 5, col 3-12）==
            for c = 3, 12 do
                pix(c, 5, rungMain)
            end
            pix(3, 5, rungHi)
            pix(5, 5, rungHi)
            pix(8, 5, rungHi)
            pix(10, 5, rungHi)
            for c = 3, 12 do
                pix(c, 6, shadowWood)
            end

            -- === 魂类细节 ===
            pix(0, 0, moss1)
            pix(1, 0, moss2)
            pix(0, 1, moss2)

            pix(15, 6, vine)
            pix(15, 7, vine)
            pix(14, 7, moss2)

            pix(5, 2, moss1)
            pix(7, 5, moss1)

            pix(9, 5, decay)
            pix(2, 4, decay)
            pix(13, 6, decay)

            pix(0, 4, vine)
            pix(0, 5, moss2)
        end
        ::skipLadder::

    elseif base == TILE.PIPE then
        -- 7x7 管道：只由左上角锚点绘制整体
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
            local innerR = outerR * 0.62

            -- 像素块尺寸随缩放适配
            local PS = math.max(1, math.floor(zGrid * 0.25))

            -- 像素圆环：外圆减内圆
            local startX = math.floor((cx - outerR) / PS) * PS
            local startY = math.floor((cy - outerR) / PS) * PS
            local endX = math.floor((cx + outerR) / PS) * PS
            local endY = math.floor((cy + outerR) / PS) * PS

            for by = startY, endY, PS do
                for bx = startX, endX, PS do
                    local dx = (bx + PS * 0.5) - cx
                    local dy = (by + PS * 0.5) - cy
                    local d2 = dx * dx + dy * dy
                    if d2 <= outerR * outerR then
                        local r, g, b, a = 0, 0, 0, 255
                        if d2 <= innerR * innerR then
                            -- 管口黑洞
                            r, g, b = 8, 10, 12
                            -- 底部积水（下半部分）
                            if dy > 0 and d2 <= (innerR * 0.9) * (innerR * 0.9) then
                                r, g, b, a = wColor[1], wColor[2], wColor[3], 160
                            end
                        elseif d2 <= (outerR * 0.85) * (outerR * 0.85) then
                            -- 中圈管壁（深灰）
                            r, g, b = 48, 52, 50
                            -- 顶部墨绿高光（上方像素）
                            if dy < -innerR * 0.3 and dx > -outerR * 0.5 and dx < outerR * 0.3 then
                                r, g, b, a = 45, 85, 62, 200
                            end
                        else
                            -- 外圈管壁（黑灰）
                            r, g, b = 32, 34, 36
                        end
                        nvgBeginPath(vg)
                        nvgRect(vg, bx, by, PS, PS)
                        nvgFillColor(vg, nvgRGBA(r, g, b, a))
                        nvgFill(vg)
                    end
                end
            end

            -- 墨绿苔痕像素点（伪随机）
            local seed = row * 137 + col * 53
            for i = 0, 2 do
                local angle = (seed * (i + 1) * 2.17) % (math.pi * 2)
                local dist = outerR * (0.72 + ((seed * (i + 3)) % 15) * 0.012)
                local mx = math.floor((cx + math.cos(angle) * dist) / PS) * PS
                local my = math.floor((cy + math.sin(angle) * dist) / PS) * PS
                nvgBeginPath(vg)
                nvgRect(vg, mx, my, PS, PS)
                nvgFillColor(vg, nvgRGBA(30, 70, 48, 180))
                nvgFill(vg)
            end

            -- 开关组指示器（像素方块）
            if switchGroup > 0 then
                local gc = C.GROUP_COLORS[switchGroup] or C.GROUP_COLORS[1]
                local ix = math.floor((px + PW - 5 * S.zoomLevel) / PS) * PS
                local iy = math.floor((py + 3 * S.zoomLevel) / PS) * PS
                nvgBeginPath(vg)
                nvgRect(vg, ix, iy, PS * 2, PS * 2)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 220))
                nvgFill(vg)
            end
        end
        ::skipPipe::

    elseif base == TILE.FRAGILE then
        -- 编辑器预览：暗灰破损方块
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, zGrid - 1, zGrid - 1)
        nvgFillColor(vg, nvgRGBA(75, 60, 45, 255))
        nvgFill(vg)
        -- 顶部微弱高光（暗淡）
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, zGrid - 1, 1)
        nvgFillColor(vg, nvgRGBA(110, 90, 65, 200))
        nvgFill(vg)
        -- 底部阴影边
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + zGrid - 2, zGrid - 1, 1.5)
        nvgFillColor(vg, nvgRGBA(40, 30, 20, 180))
        nvgFill(vg)
        -- 裂纹网络（多条不规则裂痕）
        nvgStrokeColor(vg, nvgRGBA(30, 20, 10, 200))
        nvgStrokeWidth(vg, 0.8)
        local cx = px + zGrid * 0.5
        local cy = py + zGrid * 0.5
        -- 主裂纹：从左上到右下的锯齿线
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + 2, py + 3)
        nvgLineTo(vg, cx - 1, cy - 2)
        nvgLineTo(vg, cx + 2, cy + 1)
        nvgLineTo(vg, px + zGrid - 3, py + zGrid - 2)
        nvgStroke(vg)
        -- 分叉裂纹
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 1, cy - 2)
        nvgLineTo(vg, cx + 3, cy - 4)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + 2, cy + 1)
        nvgLineTo(vg, cx - 2, cy + 4)
        nvgStroke(vg)
        -- 缺角效果（右上角小三角）
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + zGrid - 4, py + 0.5)
        nvgLineTo(vg, px + zGrid - 1, py + 0.5)
        nvgLineTo(vg, px + zGrid - 1, py + 3)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(30, 22, 15, 200))
        nvgFill(vg)
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
-- 内部：装饰物贴图缓存
-- ====================================================================
local decoImageCache = {}  -- { [spritePath] = nvgImageHandle }

-- ====================================================================
-- 内部：绘制装饰物标记
-- ====================================================================
local function DrawDecorations(vg, mapX, mapY, zGrid, startCol, endCol, startRow, endRow)
    if #S.decorations == 0 then return end

    for i, deco in ipairs(S.decorations) do
        -- 只绘制可见范围内的装饰物
        if deco.col >= startCol and deco.col <= endCol and deco.row >= startRow and deco.row <= endRow then
            local dx = mapX + (deco.col - 1) * C.GRID * S.zoomLevel - S.cameraX
            local dy = mapY + (deco.row - 1) * C.GRID * S.zoomLevel - S.cameraY

            local decoType = C.DECORATION_TYPES[deco.typeId]
            local color = decoType and decoType.color or {180, 140, 220}
            local name = decoType and decoType.name or "?"

            -- 读取装饰物属性（明暗度和缩放）
            local brightness = (deco.brightness or 100) / 100  -- 0~1
            local scalePct = (deco.scale or 100) / 100          -- 0~1

            -- 如果装饰物有贴图且有 size，渲染贴图
            if decoType and decoType.sprite and decoType.size then
                local sizeW = decoType.size.w or 1
                local sizeH = decoType.size.h or 1
                local drawW = sizeW * zGrid * scalePct
                local drawH = sizeH * zGrid * scalePct
                -- 锚点在中心：放置格的中心 = 装饰物图片的中心
                local imgX = dx + zGrid * 0.5 - drawW * 0.5
                local imgY = dy + zGrid * 0.5 - drawH * 0.5

                -- 加载/缓存贴图
                if not decoImageCache[decoType.sprite] then
                    local handle = nvgCreateImage(vg, decoType.sprite, 0)
                    decoImageCache[decoType.sprite] = handle or -1
                end

                local imgHandle = decoImageCache[decoType.sprite]
                if imgHandle and imgHandle > 0 then
                    local paint = nvgImagePattern(vg, imgX, imgY, drawW, drawH, 0, imgHandle, brightness)
                    nvgBeginPath(vg)
                    nvgRect(vg, imgX, imgY, drawW, drawH)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                else
                    -- 贴图不可用，fallback 到颜色块
                    nvgBeginPath(vg)
                    nvgRect(vg, dx + 1, dy + 1, zGrid - 2, zGrid - 2)
                    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(100 * brightness)))
                    nvgFill(vg)
                end


            else
                -- 无贴图：使用颜色格子渲染（支持缩放和明暗度）
                local drawSize = (zGrid - 2) * scalePct
                local offset = (zGrid - drawSize) * 0.5
                -- 背景填充
                nvgBeginPath(vg)
                nvgRect(vg, dx + offset, dy + offset, drawSize, drawSize)
                nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(100 * brightness)))
                nvgFill(vg)

                -- 边框
                nvgBeginPath(vg)
                nvgRect(vg, dx + offset, dy + offset, drawSize, drawSize)
                nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(200 * brightness)))
                nvgStrokeWidth(vg, 1.0)
                nvgStroke(vg)

                -- 装饰物名称标签
                if zGrid >= 10 then
                    local fontSize = math.max(7, math.min(10, zGrid * 0.5))
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, fontSize)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
                    local label = string.sub(name, 1, 3)
                    nvgText(vg, dx + zGrid * 0.5, dy + zGrid * 0.5, label)
                end
            end
        end
    end
end

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

    -- 传入动画时间驱动萤火虫闪烁
    SolidRenderer.SetTime(S.editorClock)

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
            local bx1, by1, bw, bh
            if S.bgStretchToCanvas then
                -- 拉伸为整个画布（地图）大小
                bx1 = mapX - S.cameraX
                by1 = mapY - S.cameraY
                bw = S.MAP_COLS * zGrid
                bh = S.MAP_ROWS * zGrid
            else
                -- 铺满 camBound 区域
                bx1 = mapX + (S.camBound.left - 1) * zGrid - S.cameraX
                by1 = mapY + (S.camBound.top - 1) * zGrid - S.cameraY
                bw = (S.camBound.right - S.camBound.left + 1) * zGrid
                bh = (S.camBound.bottom - S.camBound.top + 1) * zGrid
            end
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

    if S.showGizmos then
        DrawCameraBounds(vg, mapX, mapY, mapW, mapH)
        DrawPlayerCameraFrame(vg, mapX, mapY, mapW, mapH)
    end

    -- 光源区域矩形
    if FogOfWar and S.showGizmos then
        FogOfWar.DrawLightZones(vg, {
            gridSize = C.GRID,
            offsetX = S.cameraX,
            offsetY = S.cameraY,
            zoomLevel = S.zoomLevel,
            mapX = mapX,
            mapY = mapY,
            selectedIndex = S.selectedLightZoneIndex,
        })

        -- 正在绘制的区域预览
        if S.lightZoneDrawing then
            local zc1 = math.min(S.lightZoneStartCol, S.lightZoneEndCol)
            local zr1 = math.min(S.lightZoneStartRow, S.lightZoneEndRow)
            local zc2 = math.max(S.lightZoneStartCol, S.lightZoneEndCol)
            local zr2 = math.max(S.lightZoneStartRow, S.lightZoneEndRow)
            local zx = mapX + (zc1 - 1) * C.GRID * S.zoomLevel - S.cameraX
            local zy = mapY + (zr1 - 1) * C.GRID * S.zoomLevel - S.cameraY
            local zw = (zc2 - zc1 + 1) * C.GRID * S.zoomLevel
            local zh = (zr2 - zr1 + 1) * C.GRID * S.zoomLevel
            nvgBeginPath(vg); nvgRect(vg, zx, zy, zw, zh)
            nvgFillColor(vg, nvgRGBA(255, 160, 40, 40)); nvgFill(vg)
            nvgBeginPath(vg); nvgRect(vg, zx, zy, zw, zh)
            nvgStrokeColor(vg, nvgRGBA(255, 160, 40, 200))
            nvgStrokeWidth(vg, 1.5); nvgStroke(vg)
            -- 预览标识
            local nextIdx = #(FogOfWar.GetLightZones()) + 1
            local previewLabel = "#" .. nextIdx
            nvgFontSize(vg, math.max(12, 14 * S.zoomLevel))
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 160, 40, 220))
            nvgText(vg, zx + zw * 0.5, zy + zh * 0.5, previewLabel)
        end
    end

    -- 光源标记
    if FogOfWar and S.showGizmos then
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
    end

    -- 装饰物标记
    DrawDecorations(vg, mapX, mapY, zGrid, startCol, endCol, startRow, endRow)

    -- 战争迷雾（独立于 gizmos 开关）
    if FogOfWar and S.fogShowInEditor then
        FogOfWar.SetLightSources(FogOfWar.GetLightSources())
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
