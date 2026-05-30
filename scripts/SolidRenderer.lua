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
-- 动画时间（由外部每帧调用 SetTime 传入）
-- ====================================================================
local _animTime = 0

function SolidRenderer.SetTime(t)
    _animTime = t or 0
end

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
-- 旧王城地下水渠 - 瓦片渲染系统
-- ====================================================================
-- 主题: 低饱和暗色、类魂氛围、石砌水渠、潮湿石砖、残破圣堂、
--       黑水侵蚀、苔藓和腐败根须
--
-- 10种瓦片类型（根据 neighbors 自动判定）:
-- 1. 地面中心块 (CENTER)       - 四面有邻居
-- 2. 地面上边缘块 (TOP_EDGE)   - 上方无邻居
-- 3. 左右侧边块 (SIDE_EDGE)    - 左或右无邻居
-- 4. 底部边缘块 (BOTTOM_EDGE)  - 下方无邻居
-- 5. 内角块 (INNER_CORNER)     - 对角无邻居但两侧有
-- 6. 外角块 (OUTER_CORNER)     - 两面相邻无邻居
-- 7. 断裂平台边缘 (FRACTURED)  - 上方和一侧无邻居
-- 8. 墙体块 (WALL)             - 左右都有邻居，上下至少一面无
-- 9. 墙体与地面衔接块 (WALL_FLOOR) - 上方为墙、下方为空
-- 10. 水边衔接块 (WATER_EDGE)  - 邻接水体
-- ====================================================================

-- 旧王城石砖基色（冷灰偏青，低饱和）
local SEWER_BASE_COLORS = {
    { {32,34,38}, {38,40,44}, {36,39,43}, {33,35,39} },
    { {42,44,48}, {50,52,56}, {48,50,54}, {43,45,49} },
    { {38,40,45}, {46,48,52}, {44,46,51}, {39,41,46} },
    { {33,35,39}, {39,41,45}, {37,39,43}, {34,36,40} },
}

-- 墙体石砖基色（更深更冷，垂直砌石感）
local SEWER_WALL_COLORS = {
    { {28,30,35}, {34,36,40}, {32,34,39}, {29,31,36} },
    { {36,38,43}, {44,46,50}, {42,44,49}, {37,39,44} },
    { {32,34,39}, {40,42,46}, {38,40,45}, {33,35,40} },
    { {29,31,36}, {35,37,41}, {33,35,40}, {30,32,37} },
}

-- 地面上边缘基色（稍亮，表面风化）
local SEWER_TOP_COLORS = {
    { {40,42,48}, {48,50,55}, {46,48,53}, {41,43,49} },
    { {44,46,51}, {52,54,58}, {50,52,57}, {45,47,52} },
    { {38,40,45}, {46,48,52}, {44,46,51}, {39,41,46} },
    { {33,35,39}, {39,41,45}, {37,39,43}, {34,36,40} },
}

-- 底部边缘基色（被水侵蚀，偏暗偏绿）
local SEWER_BOTTOM_COLORS = {
    { {32,34,38}, {38,40,44}, {36,39,43}, {33,35,39} },
    { {36,40,42}, {42,46,48}, {40,44,46}, {37,41,43} },
    { {30,36,35}, {36,42,40}, {34,40,38}, {31,37,36} },
    { {25,32,30}, {30,38,35}, {28,35,33}, {26,33,31} },
}

-- 法线图（石砖凹凸）
local SEWER_NORMAL_MAP = {
    { {0, -0.85}, {0, -0.7}, {0, -0.7}, {0, -0.85} },
    { {-0.4, 0.5}, {0, 0.6}, {0, 0.6}, {0.4, 0.5} },
    { {-0.4, -0.3}, {0, 0.15}, {0, 0.15}, {0.4, -0.3} },
    { {0, 0.85}, {0, 0.7}, {0, 0.7}, {0, 0.85} },
}

-- 墙体法线（垂直砌缝更深）
local SEWER_WALL_NORMAL = {
    { {-0.5, -0.9}, {0, -0.85}, {0, -0.85}, {0.5, -0.9} },
    { {-0.6, 0.3}, {-0.1, 0.4}, {0.1, 0.4}, {0.6, 0.3} },
    { {-0.6, -0.3}, {-0.1, -0.2}, {0.1, -0.2}, {0.6, -0.3} },
    { {-0.5, 0.9}, {0, 0.85}, {0, 0.85}, {0.5, 0.9} },
}

-- 苔藓/根须颜色（暗绿偏灰，类魂风格不会太鲜）
local SEWER_MOSS_COLORS = {
    {28, 42, 22},   -- 暗苔藓
    {22, 36, 18},   -- 深腐苔
    {35, 48, 28},   -- 稍亮湿苔
    {18, 30, 15},   -- 极暗腐苔
}

-- 腐败根须颜色
local SEWER_ROOT_COLORS = {
    {42, 32, 22},   -- 暗棕腐根
    {35, 26, 18},   -- 深褐根须
    {50, 38, 26},   -- 干枯根
    {28, 22, 16},   -- 黑色死根
}

-- 黑水侵蚀颜色
local SEWER_WATER_STAIN_COLORS = {
    {20, 28, 32},   -- 黑水渍
    {15, 22, 28},   -- 深黑水迹
    {25, 34, 38},   -- 暗青水线
    {18, 25, 30},   -- 阴暗积水
}

-- 湿润高光颜色（冷色调反光）
local SEWER_WET_HIGHLIGHT = {80, 95, 110}

-- ====================================================================
-- 瓦片类型判定函数
-- ====================================================================
local SEWER_TYPE_CENTER      = 1
local SEWER_TYPE_TOP_EDGE    = 2
local SEWER_TYPE_SIDE_EDGE   = 3
local SEWER_TYPE_BOTTOM_EDGE = 4
local SEWER_TYPE_INNER_CORNER = 5
local SEWER_TYPE_OUTER_CORNER = 6
local SEWER_TYPE_FRACTURED   = 7
local SEWER_TYPE_WALL        = 8
local SEWER_TYPE_WALL_FLOOR  = 9
local SEWER_TYPE_WATER_EDGE  = 10

local function ClassifySewerTile(neighbors)
    if not neighbors then return SEWER_TYPE_CENTER end

    local t = neighbors.top
    local b = neighbors.bottom
    local l = neighbors.left
    local r = neighbors.right
    local water = neighbors.water  -- 是否邻接水体

    -- 10. 水边衔接块 - 邻接水体（底部或侧面有水）
    if water then return SEWER_TYPE_WATER_EDGE end

    -- 6. 外角块 - 两面相邻无邻居（角落位置）
    if not t and not l then return SEWER_TYPE_OUTER_CORNER end
    if not t and not r then return SEWER_TYPE_OUTER_CORNER end
    if not b and not l then return SEWER_TYPE_OUTER_CORNER end
    if not b and not r then return SEWER_TYPE_OUTER_CORNER end

    -- 7. 断裂平台边缘 - 上方无邻居 + 一侧也无（但已被外角覆盖，这里处理特殊断裂）
    -- （外角已处理，此处对应：三面暴露的凸出断块）
    if not t and not b then return SEWER_TYPE_FRACTURED end

    -- 9. 墙体与地面衔接块 - 上方有、下方无、左右有
    if t and not b and l and r then return SEWER_TYPE_WALL_FLOOR end

    -- 8. 墙体块 - 左右有邻居、上方无
    if not t and l and r and b then return SEWER_TYPE_WALL end

    -- 2. 地面上边缘块 - 上方无邻居
    if not t then return SEWER_TYPE_TOP_EDGE end

    -- 4. 底部边缘块 - 下方无邻居
    if not b then return SEWER_TYPE_BOTTOM_EDGE end

    -- 3. 左右侧边块 - 左或右无邻居
    if not l or not r then return SEWER_TYPE_SIDE_EDGE end

    -- 5. 内角块 - 四面有邻居但对角无（检查对角邻居）
    if neighbors.topLeft == false or neighbors.topRight == false
       or neighbors.bottomLeft == false or neighbors.bottomRight == false then
        return SEWER_TYPE_INNER_CORNER
    end

    -- 1. 地面中心块 - 四面都有邻居
    return SEWER_TYPE_CENTER
end

-- ====================================================================
-- DrawSewerBase - 绘制石砖基底（通用）
-- ====================================================================
local function DrawSewerBase(vg, px, py, gridSize, colorMap, normalMap, lighting, lightDirX, lightDirY, col, row)
    local cellSize = gridSize / PIXEL_CELLS
    local colorShift = (HashPos(col, row, 77) % 6) - 3
    local lit = lighting * 0.55 + 0.45
    local hasLight = lighting > 0.05 and (lightDirX ~= 0 or lightDirY ~= 0)

    -- 优化：先画一个平均色底色大矩形，减少后续开销
    local avgColor = colorMap[2][2]
    local avgR = math.floor(math.max(0, math.min(255, (avgColor[1] + colorShift) * lit)))
    local avgG = math.floor(math.max(0, math.min(255, (avgColor[2] + colorShift) * lit)))
    local avgB = math.floor(math.max(0, math.min(255, (avgColor[3] + colorShift) * lit)))
    nvgBeginPath(vg)
    nvgRect(vg, px, py, gridSize, gridSize)
    nvgFillColor(vg, nvgRGBA(avgR, avgG, avgB, 255))
    nvgFill(vg)

    -- 只对颜色/法线有显著差异的像素做覆盖绘制
    for r = 1, PIXEL_CELLS do
        for c = 1, PIXEL_CELLS do
            local baseColor = colorMap[r][c]
            local normal = normalMap[r][c]

            local br = baseColor[1] + colorShift
            local bg = baseColor[2] + colorShift
            local bb = baseColor[3] + colorShift

            local normalIntensity = 0.5
            if hasLight then
                normalIntensity = CalcNormalLighting(lightDirX, lightDirY, normal[1], normal[2])
            end

            local normalMod = (normalIntensity - 0.5) * 2.0
            local brightBoost = normalMod * HIGHLIGHT_BOOST * lighting

            local fr = math.floor(math.max(0, math.min(255, br * lit + brightBoost)))
            local fg = math.floor(math.max(0, math.min(255, bg * lit + brightBoost)))
            local fb = math.floor(math.max(0, math.min(255, bb * lit + brightBoost)))

            -- 跳过与底色差异小于 8 的像素（视觉不可辨）
            if math.abs(fr - avgR) > 8 or math.abs(fg - avgG) > 8 or math.abs(fb - avgB) > 8 then
                local cx = px + (c - 1) * cellSize
                local cy = py + (r - 1) * cellSize
                nvgBeginPath(vg)
                nvgRect(vg, cx, cy, cellSize, cellSize)
                nvgFillColor(vg, nvgRGBA(fr, fg, fb, 255))
                nvgFill(vg)
            end
        end
    end

    -- 简化的整体边缘阴影（替代逐像素阴影）
    local shadowSize = math.max(1, math.floor(cellSize * 0.2))
    local shadowA = math.floor(SHADOW_DARKEN * 0.7)
    if shadowA > 3 then
        -- 右边缘
        nvgBeginPath(vg)
        nvgRect(vg, px + gridSize - shadowSize, py, shadowSize, gridSize)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, shadowA))
        nvgFill(vg)
        -- 下边缘
        nvgBeginPath(vg)
        nvgRect(vg, px, py + gridSize - shadowSize, gridSize - shadowSize, shadowSize)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, shadowA))
        nvgFill(vg)
    end
end

-- ====================================================================
-- DrawSewerMortar - 绘制砖缝/灰浆线（石砌感）
-- ====================================================================
local function DrawSewerMortar(vg, px, py, gridSize, col, row, lighting, vertical)
    local cellSize = gridSize / PIXEL_CELLS
    local mortarA = math.floor(math.max(20, 55 * (lighting * 0.4 + 0.6)))

    -- 水平灰浆线（砖缝）
    local hLine = HashFloat(col, row, 301)
    if hLine < 0.7 then
        local yOff = (HashPos(col, row, 302) % 2 == 0) and 2 or 1
        nvgBeginPath(vg)
        nvgRect(vg, px, py + yOff * cellSize - math.max(1, cellSize * 0.15),
                gridSize, math.max(1, cellSize * 0.3))
        nvgFillColor(vg, nvgRGBA(18, 20, 24, mortarA))
        nvgFill(vg)
    end

    -- 垂直灰浆线（交错砌法）
    if vertical ~= false then
        local vLine = HashFloat(col, row, 303)
        if vLine < 0.6 then
            local xOff = (HashPos(col, row, 304) % 2 == 0) and 1 or 3
            local yStart = (HashPos(col, row, 305) % 2 == 0) and 0 or 2
            nvgBeginPath(vg)
            nvgRect(vg, px + xOff * cellSize - math.max(1, cellSize * 0.15),
                    py + yStart * cellSize,
                    math.max(1, cellSize * 0.3), 2 * cellSize)
            nvgFillColor(vg, nvgRGBA(18, 20, 24, mortarA))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- DrawSewerCrack - 深层裂纹（比普通砖块更暗、更宽）
-- ====================================================================
local function DrawSewerCrack(vg, px, py, gridSize, col, row, lighting)
    local crackChance = HashFloat(col, row, 200)
    if crackChance > 0.60 then return end

    local crackIdx = (HashPos(col, row, 789) % 5) + 1
    local pattern = CRACK_PATTERNS[crackIdx]
    if not pattern then return end

    local cellSize = gridSize / 4.0
    local alpha = math.floor(math.max(40, 80 * (lighting * 0.4 + 0.6)))

    -- 裂纹主线（暗色）
    nvgBeginPath(vg)
    for _, seg in ipairs(pattern.lines) do
        local x1 = px + seg[1] * cellSize
        local y1 = py + seg[2] * cellSize
        local x2 = px + seg[3] * cellSize
        local y2 = py + seg[4] * cellSize
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
    end
    nvgStrokeColor(vg, nvgRGBA(10, 12, 16, alpha))
    nvgStrokeWidth(vg, math.max(0.8, gridSize / 16))
    nvgStroke(vg)

    -- 裂纹内发暗（深度感）
    nvgBeginPath(vg)
    for _, seg in ipairs(pattern.lines) do
        nvgMoveTo(vg, px + seg[1] * cellSize + 0.5, py + seg[2] * cellSize + 0.5)
        nvgLineTo(vg, px + seg[3] * cellSize + 0.5, py + seg[4] * cellSize + 0.5)
    end
    nvgStrokeColor(vg, nvgRGBA(5, 5, 8, math.floor(alpha * 0.5)))
    nvgStrokeWidth(vg, math.max(0.3, gridSize / 28))
    nvgStroke(vg)
end

-- ====================================================================
-- DrawSewerMoss - 苔藓和腐败根须（跨块连接）
-- ====================================================================
local function DrawSewerMoss(vg, px, py, gridSize, edge, col, row, lighting, lightDirX, lightDirY)
    local cellSize = gridSize / 4.0
    local normals = MOSS_NORMALS[edge]
    local litMul = lighting * 0.45 + 0.55
    local hasLight = lighting > 0.05 and (lightDirX ~= 0 or lightDirY ~= 0)

    for i = 1, 4 do
        local h = HashFloat(col * 13 + i, row * 19, edge:byte(1) + 70)
        if h < 0.70 then
            local depth = 1 + math.floor(HashFloat(col + i * 3, row * 7, 88) * 2.2)
            local isRoot = HashFloat(col * 5 + i, row * 3, 555) < 0.25
            local colorIdx = (HashPos(col, row, i + 20) % 4) + 1
            local mossColor = isRoot and SEWER_ROOT_COLORS[colorIdx] or SEWER_MOSS_COLORS[colorIdx]

            local mossLit = 0.5
            if hasLight then
                local nx, ny = normals[i][1], normals[i][2]
                mossLit = CalcNormalLighting(lightDirX, lightDirY, nx, ny)
            end
            local normalBoost = (mossLit - 0.5) * 2.0 * HIGHLIGHT_BOOST * lighting * 0.7
            local mr = math.floor(math.max(0, math.min(255, mossColor[1] * litMul + normalBoost * 0.5)))
            local mg = math.floor(math.max(0, math.min(255, mossColor[2] * litMul + normalBoost)))
            local mb = math.floor(math.max(0, math.min(255, mossColor[3] * litMul + normalBoost * 0.3)))

            -- 优化：将多层深度合并为一个矩形（用最外层alpha）
            -- 视觉上逐层渐淡差异不大，改为单个矩形 + 深度决定覆盖面积
            local totalDepth = depth * cellSize
            local w, hh, mx, my
            if edge == "top" then
                mx = px + (i - 1) * cellSize
                my = py
                w = isRoot and math.max(1, cellSize * 0.5) or cellSize
                hh = totalDepth
            elseif edge == "bottom" then
                mx = px + (i - 1) * cellSize
                my = py + gridSize - totalDepth
                w = isRoot and math.max(1, cellSize * 0.5) or cellSize
                hh = totalDepth
            elseif edge == "left" then
                mx = px
                my = py + (i - 1) * cellSize
                w = totalDepth
                hh = isRoot and math.max(1, cellSize * 0.5) or cellSize
            else -- right
                mx = px + gridSize - totalDepth
                my = py + (i - 1) * cellSize
                w = totalDepth
                hh = isRoot and math.max(1, cellSize * 0.5) or cellSize
            end

            -- 整体渐变用中间alpha值模拟
            local avgAlpha = math.floor(220 - (depth - 1) * 27)
            nvgBeginPath(vg)
            nvgRect(vg, mx, my, w, hh)
            nvgFillColor(vg, nvgRGBA(mr, mg, mb, avgAlpha))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- DrawSewerWaterStain - 黑水侵蚀效果（从边缘向内蔓延）
-- ====================================================================
local function DrawSewerWaterStain(vg, px, py, gridSize, edge, col, row, lighting)
    local cellSize = gridSize / 4.0
    local litMul = lighting * 0.35 + 0.65
    local showSpec = lighting > 0.25
    local specA = showSpec and math.floor(25 * lighting) or 0

    for i = 1, 4 do
        local h = HashFloat(col * 9 + i, row * 23, edge:byte(1) + 100)
        if h < 0.55 then
            local depth = 1 + math.floor(HashFloat(col + i * 7, row * 11, 111) * 2.5)
            local colorIdx = (HashPos(col, row, i + 30) % 4) + 1
            local stainColor = SEWER_WATER_STAIN_COLORS[colorIdx]

            local sr = math.floor(math.max(0, math.min(255, stainColor[1] * litMul)))
            local sg = math.floor(math.max(0, math.min(255, stainColor[2] * litMul)))
            local sb = math.floor(math.max(0, math.min(255, stainColor[3] * litMul)))

            -- 优化：合并深度层为单个矩形
            local totalDepth = depth * cellSize
            local mx, my, w, hh
            if edge == "top" then
                mx = px + (i - 1) * cellSize; my = py
                w = cellSize; hh = totalDepth
            elseif edge == "bottom" then
                mx = px + (i - 1) * cellSize; my = py + gridSize - totalDepth
                w = cellSize; hh = totalDepth
            elseif edge == "left" then
                mx = px; my = py + (i - 1) * cellSize
                w = totalDepth; hh = cellSize
            else -- right
                mx = px + gridSize - totalDepth; my = py + (i - 1) * cellSize
                w = totalDepth; hh = cellSize
            end

            local avgAlpha = math.floor(160 - (depth - 1) * 22)
            nvgBeginPath(vg)
            nvgRect(vg, mx, my, w, hh)
            nvgFillColor(vg, nvgRGBA(sr, sg, sb, avgAlpha))
            nvgFill(vg)

            -- 湿润反光（冷色高光）— 仅首层位置
            if specA > 3 then
                local sx, sy
                if edge == "top" then
                    sx = mx + cellSize * 0.2; sy = py + cellSize * 0.2
                elseif edge == "bottom" then
                    sx = mx + cellSize * 0.2; sy = py + gridSize - cellSize * 0.8
                elseif edge == "left" then
                    sx = px + cellSize * 0.2; sy = my + cellSize * 0.2
                else
                    sx = px + gridSize - cellSize * 0.8; sy = my + cellSize * 0.2
                end
                nvgBeginPath(vg)
                nvgRect(vg, sx, sy, math.max(1, cellSize * 0.4), math.max(1, cellSize * 0.4))
                nvgFillColor(vg, nvgRGBA(SEWER_WET_HIGHLIGHT[1], SEWER_WET_HIGHLIGHT[2], SEWER_WET_HIGHLIGHT[3], specA))
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- DrawSewerEdgeShadow - 边缘连续阴影（跨块自然衔接）
-- ====================================================================
local function DrawSewerEdgeShadow(vg, px, py, gridSize, edge, lighting)
    local cellSize = gridSize / PIXEL_CELLS
    local shadowDepth = math.max(1, cellSize * 0.6)
    local shadowA = math.floor(math.max(30, 70 * (1.0 - lighting * 0.4)))

    if edge == "top" then
        -- 上边缘向下投射阴影（从暴露面向内）
        nvgBeginPath(vg)
        nvgRect(vg, px, py, gridSize, shadowDepth)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
    elseif edge == "bottom" then
        nvgBeginPath(vg)
        nvgRect(vg, px, py + gridSize - shadowDepth, gridSize, shadowDepth)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
    elseif edge == "left" then
        nvgBeginPath(vg)
        nvgRect(vg, px, py, shadowDepth, gridSize)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
    elseif edge == "right" then
        nvgBeginPath(vg)
        nvgRect(vg, px + gridSize - shadowDepth, py, shadowDepth, gridSize)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
    end
end

-- ====================================================================
-- DrawSewerFracturedEdge - 断裂边缘效果
-- ====================================================================
local function DrawSewerFracturedEdge(vg, px, py, gridSize, col, row, lighting)
    local cellSize = gridSize / 4.0
    -- 不规则缺口
    for i = 1, 4 do
        local broken = HashFloat(col * 17 + i, row * 29, 777)
        if broken < 0.4 then
            -- 缺失一个像素格（露出黑暗深渊）
            local bx = px + (i - 1) * cellSize
            local by = py  -- 顶部
            nvgBeginPath(vg)
            nvgRect(vg, bx, by, cellSize, cellSize)
            nvgFillColor(vg, nvgRGBA(8, 8, 12, math.floor(200 * (lighting * 0.3 + 0.7))))
            nvgFill(vg)
        end
    end
    -- 底边断裂
    for i = 1, 4 do
        local broken = HashFloat(col * 13 + i, row * 31, 888)
        if broken < 0.35 then
            local bx = px + (i - 1) * cellSize
            local by = py + gridSize - cellSize
            nvgBeginPath(vg)
            nvgRect(vg, bx, by, cellSize, cellSize)
            nvgFillColor(vg, nvgRGBA(8, 8, 12, math.floor(180 * (lighting * 0.3 + 0.7))))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- DrawSewerInnerCorner - 内角暗影（L形阴影）
-- ====================================================================
local function DrawSewerInnerCorner(vg, px, py, gridSize, col, row, lighting, neighbors)
    local cellSize = gridSize / PIXEL_CELLS
    local shadowA = math.floor(math.max(40, 90 * (1.0 - lighting * 0.3)))

    -- 检查哪个对角缺失，在对应角落绘制L形阴影
    if neighbors.topLeft == false then
        nvgBeginPath(vg)
        nvgRect(vg, px, py, cellSize, cellSize * 2)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, px, py, cellSize * 2, cellSize)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
    end
    if neighbors.topRight == false then
        nvgBeginPath(vg)
        nvgRect(vg, px + gridSize - cellSize, py, cellSize, cellSize * 2)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, px + gridSize - cellSize * 2, py, cellSize * 2, cellSize)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
    end
    if neighbors.bottomLeft == false then
        nvgBeginPath(vg)
        nvgRect(vg, px, py + gridSize - cellSize * 2, cellSize, cellSize * 2)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, px, py + gridSize - cellSize, cellSize * 2, cellSize)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
    end
    if neighbors.bottomRight == false then
        nvgBeginPath(vg)
        nvgRect(vg, px + gridSize - cellSize, py + gridSize - cellSize * 2, cellSize, cellSize * 2)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, px + gridSize - cellSize * 2, py + gridSize - cellSize, cellSize * 2, cellSize)
        nvgFillColor(vg, nvgRGBA(5, 8, 12, shadowA))
        nvgFill(vg)
    end
end

-- ====================================================================
-- DrawSewerWetSurface - 潮湿表面反光（全局湿润感）
-- ====================================================================
local function DrawSewerWetSurface(vg, px, py, gridSize, col, row, lighting)
    if lighting < 0.2 then return end
    local cellSize = gridSize / PIXEL_CELLS
    local specSize = math.max(1, cellSize * 0.35)
    local hr, hg, hb = SEWER_WET_HIGHLIGHT[1], SEWER_WET_HIGHLIGHT[2], SEWER_WET_HIGHLIGHT[3]

    -- 随机散布几个湿润反光点（最多1-2个可见）
    for i = 1, 3 do
        local h = HashFloat(col * 7 + i, row * 11, 444)
        if h < 0.30 then
            local specA = math.floor(18 * lighting * (0.5 + h))
            if specA > 2 then
                local wx = px + (HashPos(col, row, i * 100) % 3) * cellSize + cellSize * 0.3
                local wy = py + (HashPos(col, row, i * 200) % 3) * cellSize + cellSize * 0.3
                nvgBeginPath(vg)
                nvgRect(vg, wx, wy, specSize, specSize)
                nvgFillColor(vg, nvgRGBA(hr, hg, hb, specA))
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- DrawSewer - 绘制旧王城地下水渠风格砖块（主入口）
-- ====================================================================
function SolidRenderer.DrawSewer(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, neighbors)
    lighting = lighting or 0.5
    lightDirX = lightDirX or 0
    lightDirY = lightDirY or 0
    col = col or 0
    row = row or 0

    -- 判定瓦片类型
    local tileClass = ClassifySewerTile(neighbors)

    -- 根据类型选择基色和法线
    local colorMap, normalMap

    if tileClass == SEWER_TYPE_WALL or tileClass == SEWER_TYPE_WALL_FLOOR then
        colorMap = SEWER_WALL_COLORS
        normalMap = SEWER_WALL_NORMAL
    elseif tileClass == SEWER_TYPE_TOP_EDGE or tileClass == SEWER_TYPE_OUTER_CORNER then
        colorMap = SEWER_TOP_COLORS
        normalMap = SEWER_NORMAL_MAP
    elseif tileClass == SEWER_TYPE_BOTTOM_EDGE or tileClass == SEWER_TYPE_WATER_EDGE then
        colorMap = SEWER_BOTTOM_COLORS
        normalMap = SEWER_NORMAL_MAP
    else
        colorMap = SEWER_BASE_COLORS
        normalMap = SEWER_NORMAL_MAP
    end

    -- 1. 绘制石砖基底
    DrawSewerBase(vg, px, py, gridSize, colorMap, normalMap, lighting, lightDirX, lightDirY, col, row)

    -- 2. 绘制砖缝灰浆线
    DrawSewerMortar(vg, px, py, gridSize, col, row, lighting,
        tileClass ~= SEWER_TYPE_WALL)  -- 墙体只画水平线

    -- 3. 绘制裂纹
    DrawSewerCrack(vg, px, py, gridSize, col, row, lighting)

    -- 4. 根据瓦片类型绘制特殊效果
    if tileClass == SEWER_TYPE_CENTER then
        -- 中心块：潮湿表面 + 偶尔苔藓斑
        DrawSewerWetSurface(vg, px, py, gridSize, col, row, lighting)

    elseif tileClass == SEWER_TYPE_TOP_EDGE then
        -- 上边缘：苔藓从顶部垂下 + 边缘阴影
        DrawSewerMoss(vg, px, py, gridSize, "top", col, row, lighting, lightDirX, lightDirY)
        DrawSewerEdgeShadow(vg, px, py, gridSize, "top", lighting)
        DrawSewerWetSurface(vg, px, py, gridSize, col, row, lighting)

    elseif tileClass == SEWER_TYPE_SIDE_EDGE then
        -- 侧边：水渍从侧面流下 + 苔藓
        if neighbors and not neighbors.left then
            DrawSewerMoss(vg, px, py, gridSize, "left", col, row, lighting, lightDirX, lightDirY)
            DrawSewerEdgeShadow(vg, px, py, gridSize, "left", lighting)
        end
        if neighbors and not neighbors.right then
            DrawSewerMoss(vg, px, py, gridSize, "right", col, row, lighting, lightDirX, lightDirY)
            DrawSewerEdgeShadow(vg, px, py, gridSize, "right", lighting)
        end
        DrawSewerWetSurface(vg, px, py, gridSize, col, row, lighting)

    elseif tileClass == SEWER_TYPE_BOTTOM_EDGE then
        -- 底部边缘：黑水侵蚀 + 暗影
        DrawSewerWaterStain(vg, px, py, gridSize, "bottom", col, row, lighting)
        DrawSewerEdgeShadow(vg, px, py, gridSize, "bottom", lighting)

    elseif tileClass == SEWER_TYPE_INNER_CORNER then
        -- 内角：L形暗影 + 湿润
        DrawSewerInnerCorner(vg, px, py, gridSize, col, row, lighting, neighbors)
        DrawSewerWetSurface(vg, px, py, gridSize, col, row, lighting)

    elseif tileClass == SEWER_TYPE_OUTER_CORNER then
        -- 外角：两面苔藓 + 边缘阴影 + 圆角裁切
        if neighbors then
            if not neighbors.top then
                DrawSewerMoss(vg, px, py, gridSize, "top", col, row, lighting, lightDirX, lightDirY)
                DrawSewerEdgeShadow(vg, px, py, gridSize, "top", lighting)
            end
            if not neighbors.bottom then
                DrawSewerWaterStain(vg, px, py, gridSize, "bottom", col, row, lighting)
                DrawSewerEdgeShadow(vg, px, py, gridSize, "bottom", lighting)
            end
            if not neighbors.left then
                DrawSewerMoss(vg, px, py, gridSize, "left", col, row, lighting, lightDirX, lightDirY)
                DrawSewerEdgeShadow(vg, px, py, gridSize, "left", lighting)
            end
            if not neighbors.right then
                DrawSewerMoss(vg, px, py, gridSize, "right", col, row, lighting, lightDirX, lightDirY)
                DrawSewerEdgeShadow(vg, px, py, gridSize, "right", lighting)
            end
        end
        -- 外角圆角裁切
        local cellSize = gridSize / PIXEL_CELLS
        if neighbors and not neighbors.top and not neighbors.left then
            DrawPillarRoundedCorner(vg, px, py, cellSize, "tl", lighting)
        end
        if neighbors and not neighbors.top and not neighbors.right then
            DrawPillarRoundedCorner(vg, px, py, cellSize, "tr", lighting)
        end
        if neighbors and not neighbors.bottom and not neighbors.left then
            DrawPillarRoundedCorner(vg, px, py, cellSize, "bl", lighting)
        end
        if neighbors and not neighbors.bottom and not neighbors.right then
            DrawPillarRoundedCorner(vg, px, py, cellSize, "br", lighting)
        end

    elseif tileClass == SEWER_TYPE_FRACTURED then
        -- 断裂平台：不规则缺口 + 暴露暗面
        DrawSewerFracturedEdge(vg, px, py, gridSize, col, row, lighting)
        if neighbors and not neighbors.top then
            DrawSewerMoss(vg, px, py, gridSize, "top", col, row, lighting, lightDirX, lightDirY)
        end
        if neighbors and not neighbors.bottom then
            DrawSewerWaterStain(vg, px, py, gridSize, "bottom", col, row, lighting)
        end
        if neighbors and not neighbors.left then
            DrawSewerEdgeShadow(vg, px, py, gridSize, "left", lighting)
        end
        if neighbors and not neighbors.right then
            DrawSewerEdgeShadow(vg, px, py, gridSize, "right", lighting)
        end

    elseif tileClass == SEWER_TYPE_WALL then
        -- 墙体：垂直纹理强调 + 水渍向下流淌
        DrawSewerWaterStain(vg, px, py, gridSize, "top", col, row, lighting)
        DrawSewerEdgeShadow(vg, px, py, gridSize, "top", lighting)
        DrawSewerWetSurface(vg, px, py, gridSize, col, row, lighting)

    elseif tileClass == SEWER_TYPE_WALL_FLOOR then
        -- 墙地衔接：上方水渍流到地面 + 底部边缘高光
        DrawSewerWaterStain(vg, px, py, gridSize, "bottom", col, row, lighting)
        DrawSewerEdgeShadow(vg, px, py, gridSize, "bottom", lighting)
        -- 衔接线（墙体到地面过渡）
        local cellSize = gridSize / PIXEL_CELLS
        local lineA = math.floor(math.max(30, 65 * (lighting * 0.5 + 0.5)))
        nvgBeginPath(vg)
        nvgRect(vg, px, py + gridSize - math.max(1, cellSize * 0.4),
                gridSize, math.max(1, cellSize * 0.4))
        nvgFillColor(vg, nvgRGBA(12, 14, 18, lineA))
        nvgFill(vg)

    elseif tileClass == SEWER_TYPE_WATER_EDGE then
        -- 水边衔接：仅底部薄阴影过渡，不覆盖水方块表现
        local cellSize = gridSize / PIXEL_CELLS
        local edgeA = math.floor(50 * (lighting * 0.3 + 0.7))
        nvgBeginPath(vg)
        nvgRect(vg, px, py + gridSize - math.max(1, cellSize * 0.3),
                gridSize, math.max(1, cellSize * 0.3))
        nvgFillColor(vg, nvgRGBA(10, 14, 18, edgeA))
        nvgFill(vg)
    end

    -- 5. 绿色荧光苔藓点（像素块风格，少量随机亮起）
    local cellSize = gridSize / PIXEL_CELLS
    -- 只有约30%的瓦片有荧光苔藓
    local glowSeed = HashFloat(col * 13 + 7, row * 17 + 3, 999)
    if glowSeed < 0.30 then
        local phase = glowSeed * 6.2832 * 5.0 + col * 2.31 + row * 3.17
        -- 慢周期明暗变化（约 8~16 秒一轮）
        local onOffFreq = 0.06 + HashFloat(col * 3, row * 7, 123) * 0.065
        local onOffWave = math.sin(_animTime * onOffFreq * 6.2832 + phase)
        if onOffWave > 0.3 then
            local brightness = (onOffWave - 0.3) * 1.43  -- 0~1

            -- 固定像素位置（苔藓风格，贴在砖块上）
            local cx = (HashPos(col, row, 777) % 4)
            local cy = (HashPos(col, row, 888) % 4)
            local gx = px + cx * cellSize
            local gy = py + cy * cellSize
            local alpha = math.floor(140 * brightness + 40)

            nvgBeginPath(vg)
            nvgRect(vg, gx, gy, cellSize, cellSize)
            nvgFillColor(vg, nvgRGBA(60, 180, 80, alpha))
            nvgFill(vg)
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
