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
-- 柱子法线图（4x4像素格）- 单列柱子
-- ====================================================================
local PILLAR_NORMAL_MAP = {
    { {-0.9, 0.2}, {-0.2, 0.3}, {0.2, 0.3}, {0.9, 0.2} },
    { {-0.8, 0.0}, {-0.1, 0.2}, {0.1, 0.2}, {0.8, 0.0} },
    { {-0.8, 0.0}, {-0.1, -0.2}, {0.1, -0.2}, {0.8, 0.0} },
    { {-0.9, -0.2}, {-0.2, -0.3}, {0.2, -0.3}, {0.9, -0.2} },
}

-- ====================================================================
-- 粗柱子法线图 - 左半边（两列合并时左列使用）
-- ====================================================================
local PILLAR_WIDE_LEFT_NORMAL = {
    { {-0.9, 0.2}, {-0.5, 0.3}, {-0.2, 0.2}, {-0.05, 0.1} },
    { {-0.8, 0.0}, {-0.4, 0.1}, {-0.15, 0.05}, {0.0, 0.0} },
    { {-0.8, 0.0}, {-0.4, -0.1}, {-0.15, -0.05}, {0.0, 0.0} },
    { {-0.9, -0.2}, {-0.5, -0.3}, {-0.2, -0.2}, {-0.05, -0.1} },
}

-- ====================================================================
-- 粗柱子法线图 - 右半边（两列合并时右列使用）
-- ====================================================================
local PILLAR_WIDE_RIGHT_NORMAL = {
    { {0.05, 0.1}, {0.2, 0.2}, {0.5, 0.3}, {0.9, 0.2} },
    { {0.0, 0.0}, {0.15, 0.05}, {0.4, 0.1}, {0.8, 0.0} },
    { {0.0, 0.0}, {0.15, -0.05}, {0.4, -0.1}, {0.8, 0.0} },
    { {0.05, -0.1}, {0.2, -0.2}, {0.5, -0.3}, {0.9, -0.2} },
}

-- ====================================================================
-- 柱帽法线图（顶端装饰，向上凸出感）
-- ====================================================================
local PILLAR_CAP_NORMAL = {
    { {-0.6, -0.8}, {-0.2, -0.9}, {0.2, -0.9}, {0.6, -0.8} },
    { {-0.7, -0.3}, {-0.1, -0.4}, {0.1, -0.4}, {0.7, -0.3} },
    { {-0.8, 0.1}, {-0.2, 0.0}, {0.2, 0.0}, {0.8, 0.1} },
    { {-0.9, 0.2}, {-0.2, 0.3}, {0.2, 0.3}, {0.9, 0.2} },
}

-- 粗柱帽法线 - 左半
local PILLAR_CAP_WIDE_LEFT_NORMAL = {
    { {-0.7, -0.8}, {-0.4, -0.9}, {-0.15, -0.9}, {-0.05, -0.8} },
    { {-0.8, -0.3}, {-0.4, -0.4}, {-0.15, -0.3}, {0.0, -0.2} },
    { {-0.85, 0.1}, {-0.5, 0.0}, {-0.2, 0.0}, {0.0, 0.0} },
    { {-0.9, 0.2}, {-0.5, 0.3}, {-0.2, 0.2}, {-0.05, 0.1} },
}

-- 粗柱帽法线 - 右半
local PILLAR_CAP_WIDE_RIGHT_NORMAL = {
    { {0.05, -0.8}, {0.15, -0.9}, {0.4, -0.9}, {0.7, -0.8} },
    { {0.0, -0.2}, {0.15, -0.3}, {0.4, -0.4}, {0.8, -0.3} },
    { {0.0, 0.0}, {0.2, 0.0}, {0.5, 0.0}, {0.85, 0.1} },
    { {0.05, 0.1}, {0.2, 0.2}, {0.5, 0.3}, {0.9, 0.2} },
}

-- ====================================================================
-- 砖块基础颜色 - 暖色调（偏棕/赭石）
-- ====================================================================
local BRICK_BASE_COLORS = {
    { {82,62,48}, {88,65,52}, {88,65,52}, {82,62,48} },
    { {108,82,60}, {118,90,66}, {114,87,63}, {108,82,60} },
    { {98,74,54}, {106,80,60}, {103,78,57}, {98,74,54} },
    { {82,62,48}, {88,65,52}, {88,65,52}, {82,62,48} },
}

-- ====================================================================
-- 柱子基础颜色（暖灰/深棕色调）
-- ====================================================================
local PILLAR_BASE_COLORS = {
    { {78,64,54}, {96,80,68}, {99,82,70}, {80,66,56} },
    { {74,60,50}, {102,84,70}, {105,87,73}, {78,64,54} },
    { {74,60,50}, {99,80,68}, {102,84,70}, {78,64,54} },
    { {78,64,54}, {92,76,64}, {94,78,66}, {80,66,56} },
}

-- ====================================================================
-- 粗柱子颜色 - 左半边（稍暗的边缘渐变到中心）
-- ====================================================================
local PILLAR_WIDE_LEFT_COLORS = {
    { {72,58,48}, {84,72,60}, {94,80,66}, {100,86,72} },
    { {68,56,46}, {86,74,62}, {96,82,68}, {102,88,74} },
    { {68,56,46}, {84,72,60}, {94,80,66}, {100,86,72} },
    { {72,58,48}, {82,70,58}, {92,78,64}, {98,84,70} },
}

-- ====================================================================
-- 粗柱子颜色 - 右半边（中心渐变到暗边缘）
-- ====================================================================
local PILLAR_WIDE_RIGHT_COLORS = {
    { {100,86,72}, {94,80,66}, {84,72,60}, {72,58,48} },
    { {102,88,74}, {96,82,68}, {86,74,62}, {68,56,46} },
    { {100,86,72}, {94,80,66}, {84,72,60}, {68,56,46} },
    { {98,84,70}, {92,78,64}, {82,70,58}, {72,58,48} },
}

-- ====================================================================
-- 柱帽颜色（比主体稍亮，带石质感）
-- ====================================================================
local PILLAR_CAP_COLORS = {
    { {90,78,68}, {108,94,82}, {111,97,84}, {92,80,70} },
    { {84,72,62}, {106,92,78}, {108,94,80}, {86,74,64} },
    { {78,66,58}, {99,84,72}, {102,87,74}, {82,68,60} },
    { {74,62,52}, {94,80,68}, {96,82,70}, {78,64,54} },
}

-- 粗柱帽颜色 - 左半
local PILLAR_CAP_WIDE_LEFT_COLORS = {
    { {84,72,62}, {96,84,74}, {104,92,78}, {108,96,82} },
    { {78,66,56}, {94,82,70}, {102,88,74}, {106,92,78} },
    { {74,62,52}, {88,76,64}, {96,84,70}, {102,88,74} },
    { {72,58,48}, {84,72,60}, {94,80,66}, {100,86,72} },
}

-- 粗柱帽颜色 - 右半
local PILLAR_CAP_WIDE_RIGHT_COLORS = {
    { {108,96,82}, {104,92,78}, {96,84,74}, {84,72,62} },
    { {106,92,78}, {102,88,74}, {94,82,70}, {78,66,56} },
    { {102,88,74}, {96,84,70}, {88,76,64}, {74,62,52} },
    { {100,86,72}, {94,80,66}, {84,72,60}, {72,58,48} },
}

-- ====================================================================
-- 像素阴影参数
-- ====================================================================
local SHADOW_DARKEN = 18
local HIGHLIGHT_BOOST = 22

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
    local lit = lighting * 0.55 + 0.45
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

            local litMul = lighting * 0.55 + 0.45
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
-- DrawPillarRoundedCorner - 绘制像素风格圆角（裁掉暴露的外角像素）
-- ====================================================================
local function DrawPillarRoundedCorner(vg, px, py, cellSize, corner, lighting)
    -- corner: "tl", "tr", "bl", "br" (top-left, top-right, bottom-left, bottom-right)
    -- 在该角落绘制一个暗色像素来模拟圆角裁切
    local cx, cy
    if corner == "tl" then
        cx, cy = px, py
    elseif corner == "tr" then
        cx, cy = px + cellSize * 3, py
    elseif corner == "bl" then
        cx, cy = px, py + cellSize * 3
    elseif corner == "br" then
        cx, cy = px + cellSize * 3, py + cellSize * 3
    end
    if cx and cy then
        local a = math.floor(180 * (1.0 - lighting * 0.3))
        nvgBeginPath(vg)
        nvgRect(vg, cx, cy, cellSize, cellSize)
        nvgFillColor(vg, nvgRGBA(10, 8, 6, a))
        nvgFill(vg)
    end
end

-- ====================================================================
-- DrawPillarCapOverhang - 绘制柱帽的悬挑装饰（超出柱体的额外像素）
-- ====================================================================
local function DrawPillarCapOverhang(vg, px, py, gridSize, cellSize, lighting, lightDirX, lightDirY, col, row, isWide, wideSide)
    -- 柱帽向左右各伸出 1 像素格的悬挑
    local overhangSize = cellSize
    local overhangY = py  -- 在柱帽顶部一行
    local capR, capG, capB = 75, 65, 55
    local colorShift = (HashPos(col, row, 99) % 6) - 3
    capR = capR + colorShift
    capG = capG + colorShift
    capB = capB + colorShift

    local lit = lighting * 0.7 + 0.3
    local fr = math.floor(math.max(0, math.min(255, capR * lit)))
    local fg = math.floor(math.max(0, math.min(255, capG * lit)))
    local fb = math.floor(math.max(0, math.min(255, capB * lit)))

    -- 左侧悬挑（只在柱体左边缘暴露时绘制）
    local drawLeft = false
    local drawRight = false
    if isWide then
        if wideSide == "left" then
            drawLeft = true   -- 粗柱左半的左侧悬挑
        elseif wideSide == "right" then
            drawRight = true  -- 粗柱右半的右侧悬挑
        end
    else
        drawLeft = true
        drawRight = true
    end

    if drawLeft then
        -- 左侧悬挑块（2行高，1格宽）
        for dr = 0, 1 do
            local alpha = 255 - dr * 40
            nvgBeginPath(vg)
            nvgRect(vg, px - overhangSize, overhangY + dr * cellSize, overhangSize, cellSize)
            nvgFillColor(vg, nvgRGBA(fr, fg, fb, alpha))
            nvgFill(vg)
        end
        -- 悬挑底部阴影
        nvgBeginPath(vg)
        nvgRect(vg, px - overhangSize, overhangY + 2 * cellSize, overhangSize, math.max(1, cellSize * 0.4))
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(60 * lighting)))
        nvgFill(vg)
    end

    if drawRight then
        -- 右侧悬挑块（2行高，1格宽）
        for dr = 0, 1 do
            local alpha = 255 - dr * 40
            nvgBeginPath(vg)
            nvgRect(vg, px + gridSize, overhangY + dr * cellSize, overhangSize, cellSize)
            nvgFillColor(vg, nvgRGBA(fr, fg, fb, alpha))
            nvgFill(vg)
        end
        -- 悬挑底部阴影
        nvgBeginPath(vg)
        nvgRect(vg, px + gridSize, overhangY + 2 * cellSize, overhangSize, math.max(1, cellSize * 0.4))
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(60 * lighting)))
        nvgFill(vg)
    end
end

-- ====================================================================
-- DrawPillar - 绘制像素风格柱子（支持粗柱/柱帽/圆角自动拼接）
-- ====================================================================
-- neighbors.pillarLeft / pillarRight / pillarTop / pillarBottom:
--   专门检测是否有柱子（不是普通砖块）
function SolidRenderer.DrawPillar(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
    local cellSize = gridSize / PIXEL_CELLS
    lighting = lighting or 0.5
    lightDirX = lightDirX or 0
    lightDirY = lightDirY or 0
    col = col or 0
    row = row or 0

    -- 判定柱子模式
    local pLeft = neighbors and neighbors.pillarLeft or false
    local pRight = neighbors and neighbors.pillarRight or false
    local pTop = neighbors and neighbors.pillarTop or false
    local pBottom = neighbors and neighbors.pillarBottom or false

    -- 确定此格是否为粗柱的一部分
    -- 规则：两列相邻柱子 → 合并为粗柱（左列画左半，右列画右半）
    local isWide = false
    local wideSide = nil  -- "left" 或 "right"

    if pLeft and pRight then
        -- 三列以上柱子的中间：按左半处理（确保成对匹配）
        isWide = true
        wideSide = "right"  -- 和左边的配对，自己做右半
    elseif pRight and not pLeft then
        -- 右侧有柱子，自己是左半
        isWide = true
        wideSide = "left"
    elseif pLeft and not pRight then
        -- 左侧有柱子，自己是右半
        isWide = true
        wideSide = "right"
    end

    -- 判定是否为柱帽（顶端）
    local isCap = not pTop

    -- 选择法线图和颜色
    local normalMap, colorMap
    if isCap then
        if isWide then
            if wideSide == "left" then
                normalMap = PILLAR_CAP_WIDE_LEFT_NORMAL
                colorMap = PILLAR_CAP_WIDE_LEFT_COLORS
            else
                normalMap = PILLAR_CAP_WIDE_RIGHT_NORMAL
                colorMap = PILLAR_CAP_WIDE_RIGHT_COLORS
            end
        else
            normalMap = PILLAR_CAP_NORMAL
            colorMap = PILLAR_CAP_COLORS
        end
    else
        if isWide then
            if wideSide == "left" then
                normalMap = PILLAR_WIDE_LEFT_NORMAL
                colorMap = PILLAR_WIDE_LEFT_COLORS
            else
                normalMap = PILLAR_WIDE_RIGHT_NORMAL
                colorMap = PILLAR_WIDE_RIGHT_COLORS
            end
        else
            normalMap = PILLAR_NORMAL_MAP
            colorMap = PILLAR_BASE_COLORS
        end
    end

    local colorShift = (HashPos(col, row, 77) % 8) - 4

    -- 绘制主体 4x4 像素格
    for r = 1, PIXEL_CELLS do
        for c = 1, PIXEL_CELLS do
            local cx = px + (c - 1) * cellSize
            local cy = py + (r - 1) * cellSize

            local baseColor = colorMap[r][c]
            local normal = normalMap[r][c]

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

    -- 粗柱子内侧接缝（左右两半之间画一道很淡的垂直线增加连接感）
    if isWide then
        if wideSide == "left" then
            -- 右边缘画淡色接缝线
            nvgBeginPath(vg)
            nvgRect(vg, px + gridSize - math.max(1, cellSize * 0.2), py, math.max(1, cellSize * 0.2), gridSize)
            nvgFillColor(vg, nvgRGBA(90, 75, 60, math.floor(40 * lighting)))
            nvgFill(vg)
        elseif wideSide == "right" then
            -- 左边缘画淡色接缝线
            nvgBeginPath(vg)
            nvgRect(vg, px, py, math.max(1, cellSize * 0.2), gridSize)
            nvgFillColor(vg, nvgRGBA(90, 75, 60, math.floor(40 * lighting)))
            nvgFill(vg)
        end
    end

    -- 柱帽悬挑装饰（只对顶端格子绘制）
    if isCap then
        DrawPillarCapOverhang(vg, px, py, gridSize, cellSize, lighting, lightDirX, lightDirY, col, row, isWide, wideSide)
        -- 柱帽底部边线（分隔帽和柱体）
        if pBottom then
            nvgBeginPath(vg)
            nvgMoveTo(vg, px, py + gridSize)
            nvgLineTo(vg, px + gridSize, py + gridSize)
            nvgStrokeColor(vg, nvgRGBA(30, 25, 20, math.floor(100 * lighting)))
            nvgStrokeWidth(vg, math.max(0.5, cellSize * 0.2))
            nvgStroke(vg)
        end
    end

    -- 圆润边角处理（暴露的外角裁切像素）
    if neighbors and col > 0 and row > 0 then
        -- 左上角圆角：顶部和左侧都暴露
        if not neighbors.top and not neighbors.left then
            DrawPillarRoundedCorner(vg, px, py, cellSize, "tl", lighting)
        end
        -- 右上角圆角
        if not neighbors.top and not neighbors.right then
            DrawPillarRoundedCorner(vg, px, py, cellSize, "tr", lighting)
        end
        -- 左下角圆角
        if not neighbors.bottom and not neighbors.left then
            DrawPillarRoundedCorner(vg, px, py, cellSize, "bl", lighting)
        end
        -- 右下角圆角
        if not neighbors.bottom and not neighbors.right then
            DrawPillarRoundedCorner(vg, px, py, cellSize, "br", lighting)
        end
    end

    -- 柱子裂纹（概率较低，柱帽不出现裂纹）
    if not isCap and col > 0 and row > 0 then
        local crackChance = HashFloat(col, row, 789)
        if crackChance < 0.20 then
            local crackIdx = (HashPos(col, row, 321) % 5) + 1
            DrawCrack(vg, px, py, gridSize, crackIdx, lighting)
        end
    end

    -- 柱子边缘青苔（只在暴露面）
    if neighbors and col > 0 and row > 0 then
        if not neighbors.top then
            DrawMossEdge(vg, px, py, gridSize, "top", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.bottom then
            DrawMossEdge(vg, px, py, gridSize, "bottom", col, row, lighting, lightDirX, lightDirY)
        end
        -- 粗柱内侧不画青苔
        if not neighbors.left and not (isWide and wideSide == "right") then
            DrawMossEdge(vg, px, py, gridSize, "left", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.right and not (isWide and wideSide == "left") then
            DrawMossEdge(vg, px, py, gridSize, "right", col, row, lighting, lightDirX, lightDirY)
        end
    end
end

-- ====================================================================
-- 下水道砖块配色（深绿/暗黄湿润色调）
-- ====================================================================
local SEWER_BASE_COLORS = {
    { {38,48,35}, {44,52,38}, {44,52,38}, {38,48,35} },
    { {52,62,42}, {58,68,46}, {56,66,44}, {52,62,42} },
    { {46,56,38}, {52,62,42}, {50,60,40}, {46,56,38} },
    { {38,48,35}, {44,52,38}, {44,52,38}, {38,48,35} },
}

-- 下水道法线图（更深的凹槽感）
local SEWER_NORMAL_MAP = {
    { {0, -0.9}, {0, -0.8}, {0, -0.8}, {0, -0.9} },
    { {-0.4, 0.6}, {0, 0.7}, {0, 0.7}, {0.4, 0.6} },
    { {-0.4, -0.3}, {0, 0.2}, {0, 0.2}, {0.4, -0.3} },
    { {0, 0.9}, {0, 0.8}, {0, 0.8}, {0, 0.9} },
}

-- 水渍/锈迹颜色
local SEWER_STAIN_COLORS = {
    {60, 80, 50},   -- 暗绿水渍
    {80, 65, 35},   -- 铁锈色
    {50, 70, 55},   -- 青绿水垢
    {70, 60, 40},   -- 深黄泥垢
}

-- ====================================================================
-- DrawSewerStainEdge - 下水道边缘水渍效果（替代青苔）
-- ====================================================================
local function DrawSewerStainEdge(vg, px, py, gridSize, edge, col, row, lighting, lightDirX, lightDirY)
    local cellSize = gridSize / 4.0
    local normals = MOSS_NORMALS[edge]

    for i = 1, 4 do
        local h = HashFloat(col * 11 + i, row * 17, edge:byte(1) + 50)
        if h < 0.55 then
            local depth = 1 + math.floor(HashFloat(col + i * 5, row * 7, 99) * 1.5)
            local colorIdx = (HashPos(col, row, i + 10) % 4) + 1
            local stainColor = SEWER_STAIN_COLORS[colorIdx]
            local nx, ny = normals[i][1], normals[i][2]

            local stainLit = 0.5
            if lighting > 0.05 and (lightDirX ~= 0 or lightDirY ~= 0) then
                stainLit = CalcNormalLighting(lightDirX, lightDirY, nx, ny)
            end

            local litMul = lighting * 0.5 + 0.5
            local normalBoost = (stainLit - 0.5) * 2.0 * HIGHLIGHT_BOOST * lighting

            local sr = math.floor(math.max(0, math.min(255, stainColor[1] * litMul + normalBoost)))
            local sg = math.floor(math.max(0, math.min(255, stainColor[2] * litMul + normalBoost * 0.8)))
            local sb = math.floor(math.max(0, math.min(255, stainColor[3] * litMul + normalBoost * 0.5)))

            for d = 1, depth do
                local mx, my
                if edge == "top" then
                    mx = px + (i - 1) * cellSize
                    my = py + (d - 1) * cellSize
                elseif edge == "bottom" then
                    mx = px + (i - 1) * cellSize
                    my = py + gridSize - d * cellSize
                elseif edge == "left" then
                    mx = px + (d - 1) * cellSize
                    my = py + (i - 1) * cellSize
                elseif edge == "right" then
                    mx = px + gridSize - d * cellSize
                    my = py + (i - 1) * cellSize
                end

                local depthAlpha = math.floor(200 - (d - 1) * 70)
                nvgBeginPath(vg)
                nvgRect(vg, mx, my, cellSize, cellSize)
                nvgFillColor(vg, nvgRGBA(sr, sg, sb, depthAlpha))
                nvgFill(vg)
            end

            -- 湿润高光（模拟水渍反光）
            if stainLit > 0.6 and lighting > 0.3 then
                local specA = math.floor((stainLit - 0.5) * 60 * lighting)
                local sx, sy
                if edge == "top" then
                    sx = px + (i - 1) * cellSize + cellSize * 0.25
                    sy = py + cellSize * 0.25
                elseif edge == "bottom" then
                    sx = px + (i - 1) * cellSize + cellSize * 0.25
                    sy = py + gridSize - cellSize * 0.75
                elseif edge == "left" then
                    sx = px + cellSize * 0.25
                    sy = py + (i - 1) * cellSize + cellSize * 0.25
                elseif edge == "right" then
                    sx = px + gridSize - cellSize * 0.75
                    sy = py + (i - 1) * cellSize + cellSize * 0.25
                end
                if specA > 5 then
                    nvgBeginPath(vg)
                    nvgRect(vg, sx, sy, math.max(1, cellSize * 0.5), math.max(1, cellSize * 0.5))
                    nvgFillColor(vg, nvgRGBA(120, 160, 100, specA))
                    nvgFill(vg)
                end
            end
        end
    end
end

-- ====================================================================
-- DrawSewer - 绘制下水道风格砖块（深绿暗色 + 水渍边缘 + 裂纹）
-- ====================================================================
function SolidRenderer.DrawSewer(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
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

            local baseColor = SEWER_BASE_COLORS[r][c]
            local normal = SEWER_NORMAL_MAP[r][c]

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

    -- 裂纹（比普通砖块稍多）
    if col > 0 and row > 0 then
        local crackChance = HashFloat(col, row, 200)
        if crackChance < 0.55 then
            local crackIdx = (HashPos(col, row, 789) % 5) + 1
            DrawCrack(vg, px, py, gridSize, crackIdx, lighting)
        end
    end

    -- 边缘水渍（替代青苔）
    if neighbors and col > 0 and row > 0 then
        if not neighbors.top then
            DrawSewerStainEdge(vg, px, py, gridSize, "top", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.bottom then
            DrawSewerStainEdge(vg, px, py, gridSize, "bottom", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.left then
            DrawSewerStainEdge(vg, px, py, gridSize, "left", col, row, lighting, lightDirX, lightDirY)
        end
        if not neighbors.right then
            DrawSewerStainEdge(vg, px, py, gridSize, "right", col, row, lighting, lightDirX, lightDirY)
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
    elseif tileType == 17 then
        SolidRenderer.DrawSewer(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
    else
        SolidRenderer.DrawBrick(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
    end
end

-- ====================================================================
-- 碰撞检测回调（用于阴影遮挡）
-- ====================================================================
local solidCollisionChecker = nil

--- 设置碰撞检测函数（用于光照阴影计算）
--- 签名: function(col, row) -> boolean
---@param checker function|nil
function SolidRenderer.SetCollisionChecker(checker)
    solidCollisionChecker = checker
end

-- ====================================================================
-- Bresenham 网格射线遮挡检测（与 FogOfWar 相同逻辑）
-- ====================================================================
local function IsLightOccluded(srcCol, srcRow, dstCol, dstRow)
    if not solidCollisionChecker then return false end
    if srcCol == dstCol and srcRow == dstRow then return false end

    local dx = dstCol - srcCol
    local dy = dstRow - srcRow
    local absDx = (dx >= 0) and dx or -dx
    local absDy = (dy >= 0) and dy or -dy
    local sx = (dx > 0) and 1 or (dx < 0 and -1 or 0)
    local sy = (dy > 0) and 1 or (dy < 0 and -1 or 0)

    local x = srcCol
    local y = srcRow

    if absDx >= absDy then
        local err = absDx // 2
        for _ = 1, absDx do
            x = x + sx
            err = err - absDy
            if err < 0 then
                y = y + sy
                err = err + absDx
            end
            if x == dstCol and y == dstRow then
                return false
            end
            if solidCollisionChecker(x, y) then
                -- 允许光沿表面扩散：同一水平面/垂直面不互相遮挡
                if y == dstRow and srcRow ~= dstRow then
                    -- 同行表面，光源来自不同行 → 不遮挡
                elseif x == dstCol and srcCol ~= dstCol then
                    -- 同列表面，光源来自不同列 → 不遮挡
                else
                    return true
                end
            end
        end
    else
        local err = absDy // 2
        for _ = 1, absDy do
            y = y + sy
            err = err - absDx
            if err < 0 then
                x = x + sx
                err = err + absDy
            end
            if x == dstCol and y == dstRow then
                return false
            end
            if solidCollisionChecker(x, y) then
                -- 允许光沿表面扩散：同一水平面/垂直面不互相遮挡
                if y == dstRow and srcRow ~= dstRow then
                    -- 同行表面，光源来自不同行 → 不遮挡
                elseif x == dstCol and srcCol ~= dstCol then
                    -- 同列表面，光源来自不同列 → 不遮挡
                else
                    return true
                end
            end
        end
    end

    return false
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
            -- 阴影遮挡检测
            if IsLightOccluded(light.col, light.row, col, row) then
                goto continueLight
            end

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

        ::continueLight::
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

    -- 阴影遮挡检测（玩家光源到目标格子，坐标取整确保 Bresenham 正确）
    local srcC = math.floor(playerCol + 0.5)
    local srcR = math.floor(playerRow + 0.5)
    if IsLightOccluded(srcC, srcR, col, row) then
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
