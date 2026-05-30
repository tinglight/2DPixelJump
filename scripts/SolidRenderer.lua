-- ====================================================================
-- SolidRenderer.lua - 像素风格碰撞方块渲染 + 法线贴图光照效果
-- ====================================================================
--
-- 功能：
-- 1. 砖块（SOLID）和柱子（SOLID_PILLAR）的像素风格绘制
-- 2. 像素阴影效果（每个像素格有独立的明暗层次）
-- 3. 法线贴图模拟：当光源照射时显示像素化纹理凹凸效果
-- 4. 5种随机碎裂痕迹（可在相邻砖块间相连）
-- 5. 边缘青苔效果（无相邻砖块的边缘生成苔藓，带法线光照）
--
-- ====================================================================

local SolidRenderer = {}

-- ====================================================================
-- 像素网格配置
-- ====================================================================
local PIXEL_CELLS = 4  -- 每个碰撞格子细分为 4x4 像素网格

-- ====================================================================
-- 砖块法线图（4x4像素格，每像素 {nx, ny} 模拟凹凸）
-- ====================================================================
local BRICK_NORMAL_MAP = {
    { {0, -0.8}, {0, -0.7}, {0, -0.7}, {0, -0.8} },
    { {-0.3, 0.5}, {0, 0.6}, {0, 0.6}, {0.3, 0.5} },
    { {-0.3, -0.2}, {0, 0.1}, {0, 0.1}, {0.3, -0.2} },
    { {0, 0.8}, {0, 0.7}, {0, 0.7}, {0, 0.8} },
}

-- ====================================================================
-- 柱子法线图（4x4像素格）
-- ====================================================================
local PILLAR_NORMAL_MAP = {
    { {-0.9, 0.2}, {-0.2, 0.3}, {0.2, 0.3}, {0.9, 0.2} },
    { {-0.8, 0.0}, {-0.1, 0.2}, {0.1, 0.2}, {0.8, 0.0} },
    { {-0.8, 0.0}, {-0.1, -0.2}, {0.1, -0.2}, {0.8, 0.0} },
    { {-0.9, -0.2}, {-0.2, -0.3}, {0.2, -0.3}, {0.9, -0.2} },
}

-- ====================================================================
-- 砖块基础颜色 - 更灰的色调
-- ====================================================================
local BRICK_BASE_COLORS = {
    { {42,44,50}, {45,46,52}, {45,46,52}, {42,44,50} },
    { {62,60,58}, {68,65,62}, {66,64,60}, {62,60,58} },
    { {55,53,51}, {60,57,54}, {58,56,53}, {55,53,51} },
    { {42,44,50}, {45,46,52}, {45,46,52}, {42,44,50} },
}

-- ====================================================================
-- 柱子基础颜色（更灰色调）
-- ====================================================================
local PILLAR_BASE_COLORS = {
    { {44,46,55}, {58,60,70}, {60,62,72}, {46,48,58} },
    { {42,44,52}, {62,64,74}, {64,66,76}, {44,46,55} },
    { {42,44,52}, {60,62,72}, {62,64,74}, {44,46,55} },
    { {44,46,55}, {55,57,67}, {57,59,69}, {46,48,58} },
}

-- ====================================================================
-- 像素阴影参数
-- ====================================================================
local SHADOW_DARKEN = 20
local HIGHLIGHT_BOOST = 15

-- ====================================================================
-- 5种裂纹图案定义
-- 每种裂纹是一组线段，定义在4x4网格内（坐标0~4表示边界）
-- 带有边缘出口点的裂纹可以与相邻砖块的裂纹视觉相连
--
-- 出口标记: top/bottom/left/right 表示该裂纹延伸到哪个边缘
-- ====================================================================
local CRACK_PATTERNS = {
    -- 裂纹1: 从顶部中间向下延伸，在右下出口
    {
        lines = {
            {2.0, 0.0,  2.2, 1.2},
            {2.2, 1.2,  1.8, 2.0},
            {1.8, 2.0,  2.5, 3.0},
            {2.5, 3.0,  4.0, 3.5},
        },
        exits = { top = true, right = true },
    },
    -- 裂纹2: 从左边向右下延伸
    {
        lines = {
            {0.0, 1.5,  1.0, 1.8},
            {1.0, 1.8,  1.5, 2.5},
            {1.5, 2.5,  2.8, 2.8},
            {2.8, 2.8,  3.2, 4.0},
        },
        exits = { left = true, bottom = true },
    },
    -- 裂纹3: 从右边向左下延伸（Y形分叉）
    {
        lines = {
            {4.0, 1.0,  3.0, 1.5},
            {3.0, 1.5,  2.5, 2.5},
            {2.5, 2.5,  2.0, 4.0},
            {2.5, 2.5,  1.5, 3.0},  -- 分叉
        },
        exits = { right = true, bottom = true },
    },
    -- 裂纹4: 从底部向上延伸到中心碎裂
    {
        lines = {
            {1.5, 4.0,  1.8, 3.0},
            {1.8, 3.0,  2.2, 2.0},
            {2.2, 2.0,  2.0, 0.0},
            {2.2, 2.0,  3.0, 1.8},  -- 横向分叉
        },
        exits = { bottom = true, top = true },
    },
    -- 裂纹5: 对角线从左上到右下
    {
        lines = {
            {0.0, 0.5,  1.2, 1.0},
            {1.2, 1.0,  2.0, 2.2},
            {2.0, 2.2,  3.2, 3.0},
            {3.2, 3.0,  4.0, 3.5},
        },
        exits = { left = true, right = true },
    },
}

-- ====================================================================
-- 青苔法线图（边缘苔藓的凹凸感）
-- 每个方向（上下左右）有独立的法线偏移
-- ====================================================================
local MOSS_NORMALS = {
    top    = { {0, -0.9}, {-0.3, -0.7}, {0.2, -0.8}, {0.1, -0.6} },
    bottom = { {0, 0.9}, {0.3, 0.7}, {-0.2, 0.8}, {-0.1, 0.6} },
    left   = { {-0.9, 0}, {-0.7, -0.3}, {-0.8, 0.2}, {-0.6, 0.1} },
    right  = { {0.9, 0}, {0.7, 0.3}, {0.8, -0.2}, {0.6, -0.1} },
}

-- 青苔颜色变体（几种不同深浅的绿）
local MOSS_COLORS = {
    {38, 62, 28},
    {45, 70, 32},
    {32, 55, 25},
    {50, 75, 38},
}

-- ====================================================================
-- 简易哈希函数 - 基于坐标生成稳定的伪随机值
-- ====================================================================
local function HashPos(col, row, seed)
    local h = col * 374761393 + row * 668265263 + (seed or 0) * 1013904223
    h = (h ~ (h >> 13)) * 1274126177
    h = h ~ (h >> 16)
    return h
end

-- 基于哈希获取 0~1 之间的浮点数
local function HashFloat(col, row, seed)
    local h = HashPos(col, row, seed)
    return (h % 10000) / 10000.0
end

-- ====================================================================
-- 计算光照法线贡献
-- ====================================================================
local function CalcNormalLighting(lightDirX, lightDirY, nx, ny)
    local dot = nx * lightDirX + ny * lightDirY
    return math.max(0, math.min(1.0, dot * 0.5 + 0.5))
end

-- ====================================================================
-- DrawPixelBlock - 绘制单个带阴影的像素格子
-- ====================================================================
local function DrawPixelBlock(vg, x, y, size, r, g, b, normalIntensity, lighting)
    local lit = lighting * 0.7 + 0.3
    local normalMod = (normalIntensity - 0.5) * 2.0
    local brightBoost = normalMod * HIGHLIGHT_BOOST * lighting

    local fr = math.floor(math.max(0, math.min(255, r * lit + brightBoost)))
    local fg = math.floor(math.max(0, math.min(255, g * lit + brightBoost)))
    local fb = math.floor(math.max(0, math.min(255, b * lit + brightBoost)))

    nvgBeginPath(vg)
    nvgRect(vg, x, y, size, size)
    nvgFillColor(vg, nvgRGBA(fr, fg, fb, 255))
    nvgFill(vg)

    -- 像素内高光（左上角）
    if lighting > 0.3 and normalIntensity > 0.55 then
        local hlA = math.floor(30 * lighting * (normalIntensity - 0.5) * 2)
        if hlA > 0 then
            nvgBeginPath(vg)
            nvgRect(vg, x, y, math.max(1, size * 0.25), math.max(1, size * 0.25))
            nvgFillColor(vg, nvgRGBA(255, 255, 255, hlA))
            nvgFill(vg)
        end
    end

    -- 像素内阴影（右边缘+下边缘）
    local shadowSize = math.max(1, math.floor(size * 0.2))
    local shadowA = math.floor((SHADOW_DARKEN + 10) * (1.0 - normalIntensity * 0.5))
    if shadowA > 2 then
        nvgBeginPath(vg)
        nvgRect(vg, x + size - shadowSize, y, shadowSize, size)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, shadowA))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, x, y + size - shadowSize, size - shadowSize, shadowSize)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, shadowA))
        nvgFill(vg)
    end
end

-- ====================================================================
-- DrawCrack - 绘制裂纹图案
-- ====================================================================
---@param vg userdata
---@param px number 格子左上角X
---@param py number 格子左上角Y
---@param gridSize number 格子像素尺寸
---@param crackIndex number 裂纹图案索引 1~5
---@param lighting number 光照强度
local function DrawCrack(vg, px, py, gridSize, crackIndex, lighting)
    local pattern = CRACK_PATTERNS[crackIndex]
    if not pattern then return end

    local cellSize = gridSize / 4.0  -- 归一化到4x4网格
    -- 裂纹颜色：比砖块暗一些，微灰
    local alpha = math.floor(math.max(30, 60 * (lighting * 0.5 + 0.5)))

    nvgBeginPath(vg)
    for _, seg in ipairs(pattern.lines) do
        local x1 = px + seg[1] * cellSize
        local y1 = py + seg[2] * cellSize
        local x2 = px + seg[3] * cellSize
        local y2 = py + seg[4] * cellSize
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
    end
    nvgStrokeColor(vg, nvgRGBA(20, 20, 25, alpha))
    nvgStrokeWidth(vg, math.max(0.5, gridSize / 20))
    nvgStroke(vg)
end

-- ====================================================================
-- DrawMossEdge - 绘制边缘青苔效果（带法线光照）
-- ====================================================================
---@param vg userdata
---@param px number 格子左上角X
---@param py number 格子左上角Y
---@param gridSize number 格子像素尺寸
---@param edge string "top"|"bottom"|"left"|"right"
---@param col number 当前列
---@param row number 当前行
---@param lighting number 光照强度
---@param lightDirX number 光源方向X
---@param lightDirY number 光源方向Y
local function DrawMossEdge(vg, px, py, gridSize, edge, col, row, lighting, lightDirX, lightDirY)
    local cellSize = gridSize / 4.0
    local normals = MOSS_NORMALS[edge]

    -- 用哈希决定每个moss像素的不规则深度（0~3像素深入砖块）
    for i = 1, 4 do
        local h = HashFloat(col * 7 + i, row * 13, edge:byte(1))
        -- 30% 概率在该位置生长苔藓
        if h < 0.65 then
            -- 苔藓深度（1~2像素格深入砖块内部）
            local depth = 1 + math.floor(HashFloat(col + i * 3, row * 5, 77) * 1.5)
            local colorIdx = (HashPos(col, row, i) % 4) + 1
            local mossColor = MOSS_COLORS[colorIdx]
            local nx, ny = normals[i][1], normals[i][2]

            -- 计算法线光照对青苔的影响
            local mossLitIntensity = 0.5
            if lighting > 0.05 and (lightDirX ~= 0 or lightDirY ~= 0) then
                mossLitIntensity = CalcNormalLighting(lightDirX, lightDirY, nx, ny)
            end

            local litMul = lighting * 0.7 + 0.3
            local normalBoost = (mossLitIntensity - 0.5) * 2.0 * HIGHLIGHT_BOOST * lighting

            local mr = math.floor(math.max(0, math.min(255, mossColor[1] * litMul + normalBoost)))
            local mg = math.floor(math.max(0, math.min(255, mossColor[2] * litMul + normalBoost * 1.5)))
            local mb = math.floor(math.max(0, math.min(255, mossColor[3] * litMul + normalBoost * 0.5)))

            -- 绘制苔藓像素块
            for d = 1, depth do
                local mx, my, mw, mh
                if edge == "top" then
                    mx = px + (i - 1) * cellSize
                    my = py + (d - 1) * cellSize
                    mw = cellSize
                    mh = cellSize
                elseif edge == "bottom" then
                    mx = px + (i - 1) * cellSize
                    my = py + gridSize - d * cellSize
                    mw = cellSize
                    mh = cellSize
                elseif edge == "left" then
                    mx = px + (d - 1) * cellSize
                    my = py + (i - 1) * cellSize
                    mw = cellSize
                    mh = cellSize
                elseif edge == "right" then
                    mx = px + gridSize - d * cellSize
                    my = py + (i - 1) * cellSize
                    mw = cellSize
                    mh = cellSize
                end

                -- 深度越深透明度越低
                local depthAlpha = math.floor(220 - (d - 1) * 80)
                nvgBeginPath(vg)
                nvgRect(vg, mx, my, mw, mh)
                nvgFillColor(vg, nvgRGBA(mr, mg, mb, depthAlpha))
                nvgFill(vg)
            end

            -- 高光反射点（模拟苔藓表面凸起的光泽）
            if mossLitIntensity > 0.65 and lighting > 0.3 then
                local specA = math.floor((mossLitIntensity - 0.5) * 80 * lighting)
                local sx, sy
                if edge == "top" then
                    sx = px + (i - 1) * cellSize + cellSize * 0.3
                    sy = py + cellSize * 0.3
                elseif edge == "bottom" then
                    sx = px + (i - 1) * cellSize + cellSize * 0.3
                    sy = py + gridSize - cellSize * 0.7
                elseif edge == "left" then
                    sx = px + cellSize * 0.3
                    sy = py + (i - 1) * cellSize + cellSize * 0.3
                elseif edge == "right" then
                    sx = px + gridSize - cellSize * 0.7
                    sy = py + (i - 1) * cellSize + cellSize * 0.3
                end
                if specA > 5 then
                    nvgBeginPath(vg)
                    nvgRect(vg, sx, sy, math.max(1, cellSize * 0.4), math.max(1, cellSize * 0.4))
                    nvgFillColor(vg, nvgRGBA(180, 255, 180, specA))
                    nvgFill(vg)
                end
            end
        end
    end
end

-- ====================================================================
-- DrawBrick - 绘制像素风格砖块（带光照法线、裂纹、青苔）
-- ====================================================================
---@param vg userdata NanoVG context
---@param px number 格子左上角屏幕X
---@param py number 格子左上角屏幕Y
---@param gridSize number 格子像素尺寸
---@param lighting number 光照强度 0~1
---@param lightDirX number|nil 光源方向X
---@param lightDirY number|nil 光源方向Y
---@param col number|nil 格子列（用于裂纹/青苔计算）
---@param row number|nil 格子行
---@param neighbors table|nil 相邻信息 {top, bottom, left, right} bool
function SolidRenderer.DrawBrick(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
    local cellSize = gridSize / PIXEL_CELLS
    lighting = lighting or 0.5
    lightDirX = lightDirX or 0
    lightDirY = lightDirY or 0
    col = col or 0
    row = row or 0

    -- 基于坐标的颜色微变（每个砖块略有色差增加自然感）
    local colorShift = (HashPos(col, row, 42) % 10) - 5  -- -5 ~ +4

    for r = 1, PIXEL_CELLS do
        for c = 1, PIXEL_CELLS do
            local cx = px + (c - 1) * cellSize
            local cy = py + (r - 1) * cellSize

            local baseColor = BRICK_BASE_COLORS[r][c]
            local normal = BRICK_NORMAL_MAP[r][c]

            -- 应用颜色微变
            local br = baseColor[1] + colorShift
            local bg = baseColor[2] + colorShift
            local bb = baseColor[3] + colorShift

            local normalIntensity = 0.5
            if lighting > 0.05 and (lightDirX ~= 0 or lightDirY ~= 0) then
                normalIntensity = CalcNormalLighting(lightDirX, lightDirY, normal[1], normal[2])
            end

            DrawPixelBlock(vg, cx, cy, cellSize, br, bg, bb, normalIntensity, lighting)
        end
    end

    -- 绘制裂纹（基于坐标哈希决定是否有裂纹及类型）
    if col > 0 and row > 0 then
        local crackChance = HashFloat(col, row, 123)
        if crackChance < 0.45 then  -- 45% 的砖块有裂纹
            local crackIdx = (HashPos(col, row, 456) % 5) + 1
            DrawCrack(vg, px, py, gridSize, crackIdx, lighting)
        end
    end

    -- 绘制边缘青苔
    if neighbors and col > 0 and row > 0 then
        if not neighbors.top then
            DrawMossEdge(vg, px, py, gridSize, "top", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.bottom then
            DrawMossEdge(vg, px, py, gridSize, "bottom", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.left then
            DrawMossEdge(vg, px, py, gridSize, "left", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.right then
            DrawMossEdge(vg, px, py, gridSize, "right", col, row, lighting, lightDirX, lightDirY)
        end
    end
end

-- ====================================================================
-- DrawPillar - 绘制像素风格柱子（带光照法线效果）
-- ====================================================================
function SolidRenderer.DrawPillar(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
    local cellSize = gridSize / PIXEL_CELLS
    lighting = lighting or 0.5
    lightDirX = lightDirX or 0
    lightDirY = lightDirY or 0
    col = col or 0
    row = row or 0

    local colorShift = (HashPos(col, row, 77) % 8) - 4

    for r = 1, PIXEL_CELLS do
        for c = 1, PIXEL_CELLS do
            local cx = px + (c - 1) * cellSize
            local cy = py + (r - 1) * cellSize

            local baseColor = PILLAR_BASE_COLORS[r][c]
            local normal = PILLAR_NORMAL_MAP[r][c]

            local br = baseColor[1] + colorShift
            local bg = baseColor[2] + colorShift
            local bb = baseColor[3] + colorShift

            local normalIntensity = 0.5
            if lighting > 0.05 and (lightDirX ~= 0 or lightDirY ~= 0) then
                normalIntensity = CalcNormalLighting(lightDirX, lightDirY, normal[1], normal[2])
            end

            DrawPixelBlock(vg, cx, cy, cellSize, br, bg, bb, normalIntensity, lighting)
        end
    end

    -- 柱子也可能有裂纹（概率较低）
    if col > 0 and row > 0 then
        local crackChance = HashFloat(col, row, 789)
        if crackChance < 0.25 then
            local crackIdx = (HashPos(col, row, 321) % 5) + 1
            DrawCrack(vg, px, py, gridSize, crackIdx, lighting)
        end
    end

    -- 柱子边缘青苔
    if neighbors and col > 0 and row > 0 then
        if not neighbors.top then
            DrawMossEdge(vg, px, py, gridSize, "top", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.bottom then
            DrawMossEdge(vg, px, py, gridSize, "bottom", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.left then
            DrawMossEdge(vg, px, py, gridSize, "left", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.right then
            DrawMossEdge(vg, px, py, gridSize, "right", col, row, lighting, lightDirX, lightDirY)
        end
    end
end

-- ====================================================================
-- DrawSolid - 通用入口（向后兼容旧调用，同时支持新参数）
-- ====================================================================
---@param vg userdata
---@param tileType number
---@param px number
---@param py number
---@param gridSize number
---@param lighting number
---@param lightDirX number|nil
---@param lightDirY number|nil
---@param col number|nil
---@param row number|nil
---@param neighbors table|nil
function SolidRenderer.DrawSolid(vg, tileType, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
    if tileType == 13 then
        SolidRenderer.DrawPillar(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
    else
        SolidRenderer.DrawBrick(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
    end
end

-- ====================================================================
-- CalcLightDirection - 计算某格子受所有光源的综合光照方向
-- ====================================================================
---@param col number
---@param row number
---@param lightSources table
---@return number lighting, number lightDirX, number lightDirY
function SolidRenderer.CalcLightDirection(col, row, lightSources)
    if not lightSources or #lightSources == 0 then
        return 0, 0, 0
    end

    local totalLx, totalLy = 0, 0
    local maxLighting = 0

    for _, light in ipairs(lightSources) do
        local dx = col - light.col
        local dy = row - light.row
        local dist = math.sqrt(dx * dx + dy * dy)
        local radius = light.diameter * 0.5

        if dist < radius + 1 then
            local intensity = 1.0 - math.min(1.0, dist / radius)
            if intensity > maxLighting then
                maxLighting = intensity
            end

            if dist > 0.01 then
                local invDist = 1.0 / dist
                totalLx = totalLx + (-dx * invDist) * intensity
                totalLy = totalLy + (-dy * invDist) * intensity
            end
        end
    end

    local len = math.sqrt(totalLx * totalLx + totalLy * totalLy)
    if len > 0.01 then
        totalLx = totalLx / len
        totalLy = totalLy / len
    else
        totalLx, totalLy = 0, 0
    end

    return maxLighting, totalLx, totalLy
end

-- ====================================================================
-- CalcPlayerLightDirection - 计算玩家光源对某格子的光照方向
-- ====================================================================
---@param col number
---@param row number
---@param playerCol number
---@param playerRow number
---@param playerRadius number
---@return number lighting, number lightDirX, number lightDirY
function SolidRenderer.CalcPlayerLightDirection(col, row, playerCol, playerRow, playerRadius)
    local dx = col - playerCol
    local dy = row - playerRow
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist >= playerRadius + 1 then
        return 0, 0, 0
    end

    local intensity = 1.0 - math.min(1.0, dist / playerRadius)
    local lx, ly = 0, 0
    if dist > 0.01 then
        lx = -dx / dist
        ly = -dy / dist
    end

    return intensity, lx, ly
end

return SolidRenderer
