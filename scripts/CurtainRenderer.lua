-- ====================================================================
-- CurtainRenderer.lua - 像素风格柳条门帘渲染 + 法线光照 + 晃动动画
-- ====================================================================
--
-- 功能：
-- 1. 像素风格的垂直柳条门帘（每格 8x8 细分渲染）
-- 2. 法线贴图：每根柳条的左右边缘有法线方向，光照时显示立体感
-- 3. 晃动动画：玩家触碰时触发阻尼振荡
-- 4. 连续柳条 tilemap 无缝衔接（上下拼接时条纹对齐）
-- 5. 部分遮光：光线穿过柳条时衰减（非完全阻挡）
--
-- ====================================================================

local CurtainRenderer = {}

-- ====================================================================
-- 配置
-- ====================================================================
local PIXEL_CELLS = 8       -- 每格细分 8x8（每像素 2px，更细腻的柳条表现）
local STRAND_COUNT = 5      -- 每格5根柳条（间距约 1.6 像素格）

-- 柳条基础颜色（暖棕绿色调，接近枯叶/藤条）
local STRAND_COLORS = {
    { 88, 105, 65 },   -- 暗绿棕
    { 95, 112, 70 },   -- 稍亮
    { 82, 98, 60 },    -- 深色
    { 100, 115, 72 },  -- 亮绿棕
    { 78, 92, 55 },    -- 最暗
}

-- 光照遮挡衰减系数（0~1，1=完全遮挡，0=完全透过）
CurtainRenderer.LIGHT_ATTENUATION = 0.3

-- ====================================================================
-- 晃动状态管理
-- ====================================================================
-- 存储每个柳条格子的晃动状态 key = "row_col"
local swayState = {}

--- 触发某格柳条的晃动
---@param col number
---@param row number
---@param strength number 初始强度（0~1）
function CurtainRenderer.TriggerSway(col, row, strength)
    local key = row .. "_" .. col
    local existing = swayState[key]
    -- 如果已在晃动且振幅还较大，不重复触发（防止每帧叠加导致颤抖）
    if existing then
        if existing.amplitude > 0.15 then
            -- 正在大幅晃动中，跳过（自然衰减后才能再触发）
            return
        end
        -- 振幅已衰减较小，可以重新激发
        existing.amplitude = math.min(1.0, strength * 0.8)
        existing.velocity = strength * 8.0
    else
        swayState[key] = {
            amplitude = strength,
            phase = 0,
            velocity = strength * 10.0,   -- 初始角速度
            damping = 3.5,                 -- 阻尼系数
            frequency = 6.0 + math.random() * 2.0,  -- 振荡频率
        }
    end
end

--- 传播晃动到相邻柳条格子
---@param col number 触发格列
---@param row number 触发格行
---@param strength number 原始强度
---@param levelData table 关卡数据
---@param TILE table TILE枚举
---@param getTileType function GetTileType函数
local function PropagateSwayToNeighbors(col, row, strength, levelData, TILE, getTileType)
    local propagated = strength * 0.4
    if propagated < 0.05 then return end
    local MAP_ROWS = #levelData
    local MAP_COLS = levelData[1] and #levelData[1] or 0
    local neighbors = { {row - 1, col}, {row + 1, col}, {row, col - 1}, {row, col + 1} }
    for _, nb in ipairs(neighbors) do
        local nr, nc = nb[1], nb[2]
        if nr >= 1 and nr <= MAP_ROWS and nc >= 1 and nc <= MAP_COLS then
            local val = levelData[nr][nc]
            if val and val ~= 0 then
                local base = getTileType(val)
                if base == TILE.CURTAIN then
                    local nkey = nr .. "_" .. nc
                    if not swayState[nkey] or swayState[nkey].amplitude < propagated then
                        CurtainRenderer.TriggerSway(nc, nr, propagated)
                    end
                end
            end
        end
    end
end

CurtainRenderer.PropagateSwayToNeighbors = PropagateSwayToNeighbors

--- 更新所有柳条的晃动状态
---@param dt number 帧时间
function CurtainRenderer.UpdateSway(dt)
    for key, state in pairs(swayState) do
        -- 阻尼振荡：phase += velocity * dt, velocity 衰减
        state.phase = state.phase + state.velocity * dt
        state.velocity = state.velocity - state.velocity * state.damping * dt
        state.amplitude = state.amplitude * (1.0 - state.damping * 0.5 * dt)

        -- 振幅太小就移除
        if math.abs(state.amplitude) < 0.01 and math.abs(state.velocity) < 0.1 then
            swayState[key] = nil
        end
    end
end

--- 清空晃动状态（关卡切换时）
function CurtainRenderer.ClearSway()
    swayState = {}
end

-- ====================================================================
-- 柳条形状生成（基于列位置伪随机）
-- ====================================================================

-- 简单伪随机哈希
local function HashStrand(col, row, strandIdx, seed)
    local h = col * 374761 + row * 668265 + strandIdx * 982451 + (seed or 0)
    h = ((h ~ (h >> 16)) * 0x45d9f3b) & 0x7FFFFFFF
    h = ((h ~ (h >> 16)) * 0x45d9f3b) & 0x7FFFFFFF
    return (h % 10000) / 10000.0
end

--- 获取单格内每根柳条的 X 位置（像素格单位，0~7）
--- 保证同列上下连续格的柳条 X 一致（tilemap无缝）
---@param col number 地图列
---@return table 柳条X位置列表 (1~STRAND_COUNT)
local function GetStrandPositions(col)
    local positions = {}
    -- 基于列号生成固定位置，上下格共享同一列的X偏移
    for i = 1, STRAND_COUNT do
        local baseX = (i - 1) * (PIXEL_CELLS / STRAND_COUNT) + 0.5
        local jitter = (HashStrand(col, 0, i, 12345) - 0.5) * 0.8
        positions[i] = math.max(0, math.min(PIXEL_CELLS - 1, math.floor(baseX + jitter + 0.5)))
    end
    return positions
end

-- ====================================================================
-- 法线图生成
-- ====================================================================

--- 计算某像素的法线方向（基于柳条形状）
--- 柳条上的像素：法线朝向柳条表面外侧
---@param localX number 局部像素X (0~7)
---@param localY number 局部像素Y (0~7)
---@param strandPositions table 柳条X位置列表
---@return number nx, number ny 法线方向
local function CalcStrandNormal(localX, localY, strandPositions)
    -- 找最近的柳条
    local minDist = 999
    local nearestX = 0
    for _, sx in ipairs(strandPositions) do
        local d = math.abs(localX - sx)
        if d < minDist then
            minDist = d
            nearestX = sx
        end
    end

    if minDist > 1 then
        -- 不在柳条上，无法线
        return 0, 0
    end

    -- 法线方向：柳条左侧朝左，右侧朝右，中心略朝前
    local nx = 0
    if localX < nearestX then
        nx = -0.7
    elseif localX > nearestX then
        nx = 0.7
    else
        nx = 0
    end

    -- Y方向的法线：柳条表面微微朝上（顶部）或朝下（底部）
    local nyBias = (localY / PIXEL_CELLS - 0.5) * 0.4
    local ny = nyBias

    return nx, ny
end

-- ====================================================================
-- 光照法线计算（与 SolidRenderer 统一）
-- ====================================================================
local function CalcNormalLighting(lightDirX, lightDirY, nx, ny)
    local dot = nx * lightDirX + ny * lightDirY
    return math.max(0, math.min(1.0, dot * 0.5 + 0.5))
end

-- ====================================================================
-- 绘制单格柳条门帘
-- ====================================================================

--- 绘制柳条门帘
---@param vg userdata NanoVG上下文
---@param px number 格子左上角屏幕X
---@param py number 格子左上角屏幕Y
---@param gridSize number 格子像素尺寸（16）
---@param lighting number 光照强度(0~1)
---@param lightDirX number 光照方向X
---@param lightDirY number 光照方向Y
---@param col number 地图列
---@param row number 地图行
---@param gameTime number 当前游戏时间
---@param hasAbove boolean 上方是否有柳条
---@param hasBelow boolean 下方是否有柳条
function CurtainRenderer.DrawCurtain(vg, px, py, gridSize, lighting, lightDirX, lightDirY, col, row, gameTime, hasAbove, hasBelow)
    local cellSize = gridSize / PIXEL_CELLS  -- 每像素格 2px

    -- 超级 LOD: gridSize 极小时画简化柳条（几条竖线代替 8×8 像素细节）
    if gridSize < 10 then
        local lit = lighting * 0.7 + 0.1
        local gr = math.floor(math.max(0, math.min(255, 50 * lit)))
        local gg = math.floor(math.max(0, math.min(255, 90 * lit)))
        local gb = math.floor(math.max(0, math.min(255, 35 * lit)))
        -- 画 3 条简化竖线代表柳条
        local sw = math.max(1, gridSize / 6)
        nvgBeginPath(vg)
        for i = 1, 3 do
            local lx = px + gridSize * i / 4 - sw * 0.5
            nvgRect(vg, lx, py, sw, gridSize)
        end
        nvgFillColor(vg, nvgRGBA(gr, gg, gb, 255))
        nvgFill(vg)
        return
    end

    -- 获取柳条位置（同列共享，保证上下衔接）
    local strandPositions = GetStrandPositions(col)

    -- 获取当前格的晃动状态
    local key = row .. "_" .. col
    local sway = swayState[key]
    local swayOffset = 0
    if sway then
        swayOffset = math.sin(sway.phase) * sway.amplitude * 2.0
    end

    -- 自然微风（始终存在的轻微摆动）
    local windSway = math.sin(gameTime * 1.5 + col * 0.7 + row * 0.3) * 0.3
    local totalSway = swayOffset + windSway

    -- 绘制每根柳条的像素
    for si = 1, STRAND_COUNT do
        local strandX = strandPositions[si]
        local strandColor = STRAND_COLORS[((si - 1 + col) % #STRAND_COLORS) + 1]

        -- 每根柳条的晃动有微小相位差
        local strandPhaseOff = si * 0.4 + HashStrand(col, row, si, 777) * 1.5
        local strandSwayOff = math.sin(gameTime * 1.8 + strandPhaseOff) * 0.15

        for cy = 0, PIXEL_CELLS - 1 do
            -- 柳条有断裂/间隙（模拟自然感）
            -- 顶部格有上方连接时，前几行可以稍空；底部无连接时末尾几行也可以空
            local isGap = false
            if not hasAbove and cy == 0 then
                -- 顶部起始行：横梁/绑绳位置，全部填充
                isGap = false
            end
            -- 随机间隙（让柳条不是实心长条）
            local gapHash = HashStrand(col, row * 8 + cy, si, 5555)
            if gapHash > 0.88 and cy > 0 and cy < PIXEL_CELLS - 1 then
                isGap = true
            end

            if not isGap then
                -- 计算该像素的X偏移（晃动效果，越靠下越明显）
                local yRatio = (row * PIXEL_CELLS + cy) / (PIXEL_CELLS * 4)  -- 整体位置比
                local localYRatio = cy / PIXEL_CELLS  -- 格内位置
                local pixSwayX = totalSway * (0.3 + localYRatio * 0.7) + strandSwayOff * localYRatio

                -- 像素对齐
                local swayPixels = math.floor(pixSwayX + 0.5)
                local drawX = strandX + swayPixels
                if drawX < 0 then drawX = 0 end
                if drawX >= PIXEL_CELLS then drawX = PIXEL_CELLS - 1 end

                -- 计算法线光照
                local nx, ny = CalcStrandNormal(drawX, cy, strandPositions)
                local normalInt = 0.5
                if lighting > 0.01 and (nx ~= 0 or ny ~= 0) then
                    normalInt = CalcNormalLighting(lightDirX, lightDirY, nx, ny)
                end

                -- 颜色+光照
                local lit = lighting * 0.5 + 0.5  -- 基础50%可见度 + 光照加成
                local normalMod = (normalInt - 0.5) * 2.0
                local brightBoost = normalMod * 18 * lighting

                local cr = math.floor(math.max(0, math.min(255, strandColor[1] * lit + brightBoost)))
                local cg = math.floor(math.max(0, math.min(255, strandColor[2] * lit + brightBoost)))
                local cb = math.floor(math.max(0, math.min(255, strandColor[3] * lit + brightBoost)))

                -- 透明度：柳条不完全不透明，模拟半透感
                local alpha = 220
                if isGap then alpha = 0 end

                -- 绘制像素
                local finalX = px + drawX * cellSize
                local finalY = py + cy * cellSize

                nvgBeginPath(vg)
                nvgRect(vg, finalX, finalY, cellSize, cellSize)
                nvgFillColor(vg, nvgRGBA(cr, cg, cb, alpha))
                nvgFill(vg)

                -- 像素内阴影（右边/下边薄边缘）
                if lighting > 0.2 and normalInt < 0.45 then
                    local shadowA = math.floor(20 * (1.0 - normalInt))
                    nvgBeginPath(vg)
                    nvgRect(vg, finalX + cellSize - 1, finalY, 1, cellSize)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, shadowA))
                    nvgFill(vg)
                end

                -- 高光（左上角小点）
                if lighting > 0.4 and normalInt > 0.65 then
                    local hlA = math.floor(25 * lighting * (normalInt - 0.5))
                    nvgBeginPath(vg)
                    nvgRect(vg, finalX, finalY, 1, 1)
                    nvgFillColor(vg, nvgRGBA(255, 255, 220, hlA))
                    nvgFill(vg)
                end
            end
        end
    end

    -- 顶部横梁（如果没有上方连接，画一条绑绳/横杆）
    if not hasAbove then
        local barColor = { 70, 55, 40 }
        local barLit = lighting * 0.5 + 0.5
        local br = math.floor(barColor[1] * barLit)
        local bg = math.floor(barColor[2] * barLit)
        local bb = math.floor(barColor[3] * barLit)
        nvgBeginPath(vg)
        nvgRect(vg, px, py, gridSize, cellSize)
        nvgFillColor(vg, nvgRGBA(br, bg, bb, 240))
        nvgFill(vg)
        -- 横梁高光线
        nvgBeginPath(vg)
        nvgRect(vg, px, py, gridSize, 1)
        nvgFillColor(vg, nvgRGBA(120, 100, 75, math.floor(60 * lighting)))
        nvgFill(vg)
    end

    -- 底部收尾（如果没有下方连接，柳条末端变尖/渐隐）
    if not hasBelow then
        -- 在最底部几个像素降低透明度制造渐隐效果
        for si = 1, STRAND_COUNT do
            local strandX = strandPositions[si]
            local strandPhaseOff = si * 0.4
            local strandSwayOff = math.sin(gameTime * 1.8 + strandPhaseOff) * 0.15
            local pixSwayX = totalSway * 0.9 + strandSwayOff
            local swayPixels = math.floor(pixSwayX + 0.5)
            local drawX = math.max(0, math.min(PIXEL_CELLS - 1, strandX + swayPixels))
            -- 尖端像素（半透明）
            local tipX = px + drawX * cellSize
            local tipY = py + (PIXEL_CELLS - 1) * cellSize + cellSize
            nvgBeginPath(vg)
            nvgRect(vg, tipX, tipY, cellSize, math.max(1, cellSize * 0.5))
            local tipColor = STRAND_COLORS[((si - 1 + col) % #STRAND_COLORS) + 1]
            local tLit = lighting * 0.4 + 0.4
            nvgFillColor(vg, nvgRGBA(
                math.floor(tipColor[1] * tLit),
                math.floor(tipColor[2] * tLit),
                math.floor(tipColor[3] * tLit), 100))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 光线衰减查询（供 FogOfWar 使用）
-- ====================================================================

--- 判断某格是否是柳条门帘（供外部光照系统查询）
---@param col number
---@param row number
---@param levelData table
---@param TILE table
---@param getTileType function
---@return boolean
function CurtainRenderer.IsCurtainAt(col, row, levelData, TILE, getTileType)
    local MAP_ROWS = #levelData
    local MAP_COLS = levelData[1] and #levelData[1] or 0
    if col < 1 or col > MAP_COLS or row < 1 or row > MAP_ROWS then return false end
    local val = levelData[row][col]
    if not val or val == 0 then return false end
    local base = getTileType(val)
    return base == TILE.CURTAIN
end

return CurtainRenderer
