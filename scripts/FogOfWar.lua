-- ====================================================================
-- FogOfWar.lua - 战争迷雾 & 光源系统
-- ====================================================================
--
-- 像素风格的视野系统：
-- - 无光源时整个地图被黑色遮罩覆盖
-- - 光源照亮周围区域，边缘采用像素化阶梯式羽化
-- - 支持配置光源直径和羽化程度
--
-- 用法：
--   local FogOfWar = require "FogOfWar"
--   FogOfWar.Init(vg)
--   FogOfWar.SetLightSources(lightSources)
--   FogOfWar.Draw(vg, params)
--
-- ====================================================================

local FogOfWar = {}

-- ====================================================================
-- 光源数据
-- ====================================================================
local lightSources = {}  -- { {col, row, diameter, feather}, ... }

-- ====================================================================
-- 光照缓存系统（性能优化核心）
-- ====================================================================
-- 缓存每个格子的光照值，只在光源变化时重算
local lightCache = {}          -- [row][col] = lighting (0~1)
local lightCacheDirty = true   -- 标记缓存是否需要重算
local lastLightFingerprint = "" -- 用于检测光源是否变化
local lastCacheRange = -1      -- 用于检测可见范围是否变化

--- 计算光源指纹（用于快速检测变化）
local function CalcLightFingerprint()
    -- 简化：用光源数量 + 所有光源位置/直径的校验和
    local sum = #lightSources
    for _, light in ipairs(lightSources) do
        sum = sum + light.col * 1000 + light.row * 100 + math.floor(light.diameter * 10)
    end
    return sum
end

--- 标记光照缓存为脏（需要重算）
function FogOfWar.InvalidateCache()
    lightCacheDirty = true
end

-- ====================================================================
-- 碰撞检测回调（用于阴影遮挡）
-- ====================================================================
-- 签名: function(col, row) -> boolean
-- 返回 true 表示该格子是实体碰撞（阻挡光线）
local collisionChecker = nil

-- 柳条检测回调（部分遮光）
-- 签名: function(col, row) -> boolean
-- 返回 true 表示该格子是柳条（衰减光线但不完全阻挡）
local curtainChecker = nil
local CURTAIN_ATTENUATION = 0.3  -- 每层柳条衰减30%光照
local THIN_WALL_ATTENUATION = 0.6  -- 每层薄墙衰减60%光照（比柳条更强）

--- 设置碰撞检测函数（用于阴影计算）
--- 签名: function(col, row) -> boolean
---@param checker function|nil
function FogOfWar.SetCollisionChecker(checker)
    collisionChecker = checker
end

--- 设置柳条检测函数（用于部分遮光）
--- 签名: function(col, row) -> boolean
---@param checker function|nil
function FogOfWar.SetCurtainChecker(checker)
    curtainChecker = checker
end

-- ====================================================================
-- 薄墙判定（一层厚度的墙壁/柱子）
-- ====================================================================
-- 判断 (col, row) 处的碰撞格子是否为"薄墙"：
-- 在某个方向上只有一层厚度（两侧邻居均不是碰撞）
-- 用于光照穿透效果：薄墙减弱光线但不完全阻挡
-- 判定标准：
--   水平薄墙：左右邻居均非碰撞（竖直方向一层厚度的墙/柱子）
--   垂直薄墙：上下邻居均非碰撞（水平方向一层厚度的平台/顶板）
-- 只要满足其中一个方向为"薄"即视为可穿透
local function IsThinWall(col, row, sx, sy)
    if not collisionChecker then return false end
    -- 柳条不算薄墙（柳条有自己的衰减逻辑）
    if curtainChecker and curtainChecker(col, row) then return false end

    -- 检查水平方向（左右）是否为薄墙
    local leftSolid = collisionChecker(col - 1, row)
    local rightSolid = collisionChecker(col + 1, row)
    local horizontalThin = (not leftSolid) and (not rightSolid)

    -- 检查垂直方向（上下）是否为薄墙
    local topSolid = collisionChecker(col, row - 1)
    local bottomSolid = collisionChecker(col, row + 1)
    local verticalThin = (not topSolid) and (not bottomSolid)

    -- 根据射线方向决定判定条件：
    -- 如果射线主要在水平方向（sx != 0），检查水平方向是否薄（左右无碰撞）
    -- 如果射线主要在垂直方向（sy != 0），检查垂直方向是否薄（上下无碰撞）
    if sx ~= 0 and sy == 0 then
        -- 纯水平射线：墙在水平方向薄则可穿透
        return horizontalThin
    elseif sy ~= 0 and sx == 0 then
        -- 纯垂直射线：墙在垂直方向薄则可穿透
        return verticalThin
    else
        -- 对角线射线：任一方向薄即可穿透
        return horizontalThin or verticalThin
    end
end

-- ====================================================================
-- Bresenham 网格射线遮挡检测
-- ====================================================================
-- 从光源 (srcCol, srcRow) 到目标 (dstCol, dstRow) 射线
-- 返回 true 表示路径被阻挡（有实体碰撞块挡在中间）
-- 规则：光线照亮碰撞本身，但不照亮碰撞背后的格子
-- 即：如果射线路径上(不含起点和终点)遇到碰撞格子 → 目标被遮挡
--     如果目标本身是碰撞 → 不被遮挡（光照亮碰撞方块）
-- 新增：薄墙（一层厚度）不完全阻挡光线，允许减弱穿透
local function IsOccluded(srcCol, srcRow, dstCol, dstRow)
    if not collisionChecker then return false end
    -- 相同位置不遮挡
    if srcCol == dstCol and srcRow == dstRow then return false end

    -- Bresenham 直线算法（格子级别）
    local dx = dstCol - srcCol
    local dy = dstRow - srcRow
    local absDx = (dx >= 0) and dx or -dx
    local absDy = (dy >= 0) and dy or -dy
    local sx = (dx > 0) and 1 or (dx < 0 and -1 or 0)
    local sy = (dy > 0) and 1 or (dy < 0 and -1 or 0)

    local x = srcCol
    local y = srcRow

    if absDx >= absDy then
        -- X 主轴
        local err = absDx // 2
        for _ = 1, absDx do
            x = x + sx
            err = err - absDy
            if err < 0 then
                y = y + sy
                err = err + absDx
            end
            -- 到达终点前检查中间格子
            if x == dstCol and y == dstRow then
                return false  -- 终点本身不算遮挡
            end
            -- 中间格子是碰撞 → 检查是否为同一表面
            if collisionChecker(x, y) then
                -- 允许光沿表面扩散：同一水平面(地面/天花板)不互相遮挡
                if y == dstRow and srcRow ~= dstRow then
                    -- 同行表面，光源来自不同行 → 不遮挡
                elseif x == dstCol and srcCol ~= dstCol then
                    -- 同列表面，光源来自不同列 → 不遮挡
                else
                    -- 薄墙：允许光线穿透（衰减由 CalcThinWallAttenuation 计算）
                    if IsThinWall(x, y, sx, sy) then
                        -- 不阻挡，继续射线
                    else
                        return true
                    end
                end
            end
        end
    else
        -- Y 主轴
        local err = absDy // 2
        for _ = 1, absDy do
            y = y + sy
            err = err - absDx
            if err < 0 then
                x = x + sx
                err = err + absDy
            end
            -- 到达终点前检查中间格子
            if x == dstCol and y == dstRow then
                return false  -- 终点本身不算遮挡
            end
            -- 中间格子是碰撞 → 检查是否为同一表面
            if collisionChecker(x, y) then
                -- 允许光沿表面扩散：同一水平面(地面/天花板)不互相遮挡
                if y == dstRow and srcRow ~= dstRow then
                    -- 同行表面，光源来自不同行 → 不遮挡
                elseif x == dstCol and srcCol ~= dstCol then
                    -- 同列表面，光源来自不同列 → 不遮挡
                else
                    -- 薄墙：允许光线穿透（衰减由 CalcThinWallAttenuation 计算）
                    if IsThinWall(x, y, sx, sy) then
                        -- 不阻挡，继续射线
                    else
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- ====================================================================
-- 薄墙射线衰减计算（Bresenham 路径上统计薄墙数量）
-- ====================================================================
-- 从光源到目标射线经过多少层薄墙，返回衰减因子 (0~1, 1=无衰减)
local function CalcThinWallAttenuation(srcCol, srcRow, dstCol, dstRow)
    if not collisionChecker then return 1.0 end
    if srcCol == dstCol and srcRow == dstRow then return 1.0 end

    local thinWallCount = 0
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
            if x == dstCol and y == dstRow then break end
            if collisionChecker(x, y) and IsThinWall(x, y, sx, sy) then
                thinWallCount = thinWallCount + 1
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
            if x == dstCol and y == dstRow then break end
            if collisionChecker(x, y) and IsThinWall(x, y, sx, sy) then
                thinWallCount = thinWallCount + 1
            end
        end
    end

    if thinWallCount == 0 then return 1.0 end
    return math.max(0.02, (1.0 - THIN_WALL_ATTENUATION) ^ thinWallCount)
end

-- ====================================================================
-- 柳条射线衰减计算（Bresenham 路径上统计柳条数量）
-- ====================================================================
-- 从光源到目标射线经过多少层柳条，返回衰减因子 (0~1, 1=无衰减)
local function CalcCurtainAttenuation(srcCol, srcRow, dstCol, dstRow)
    if not curtainChecker then return 1.0 end
    if srcCol == dstCol and srcRow == dstRow then return 1.0 end

    local curtainCount = 0
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
            if x == dstCol and y == dstRow then break end
            if curtainChecker(x, y) then
                curtainCount = curtainCount + 1
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
            if x == dstCol and y == dstRow then break end
            if curtainChecker(x, y) then
                curtainCount = curtainCount + 1
            end
        end
    end

    if curtainCount == 0 then return 1.0 end
    return math.max(0.05, (1.0 - CURTAIN_ATTENUATION) ^ curtainCount)
end

-- ====================================================================
-- Tween 动画系统
-- ====================================================================
local TWEEN_DURATION = 0.4  -- 开启/关闭动画时长（秒）

-- 活跃的 tween 动画列表
-- { light=lightRef, startDiameter, targetDiameter, elapsed, duration, onComplete? }
local activeTweens = {}

--- 内部：为光源创建渐入 tween（diameter 从 0 到 target）
---@param light table 光源引用
---@param targetDiameter number 目标直径
local function TweenLightIn(light, targetDiameter)
    -- 移除该光源已有的 tween（避免重复）
    for i = #activeTweens, 1, -1 do
        if activeTweens[i].light == light then
            table.remove(activeTweens, i)
        end
    end
    light.diameter = 0.1  -- 从极小开始
    table.insert(activeTweens, {
        light = light,
        startDiameter = 0.1,
        targetDiameter = targetDiameter,
        elapsed = 0,
        duration = TWEEN_DURATION,
    })
end

--- 内部：为光源创建渐出 tween（diameter 从当前到 0，完成后移除）
---@param light table 光源引用
---@param onComplete function|nil 完成时的回调
local function TweenLightOut(light, onComplete)
    -- 移除该光源已有的 tween
    for i = #activeTweens, 1, -1 do
        if activeTweens[i].light == light then
            table.remove(activeTweens, i)
        end
    end
    table.insert(activeTweens, {
        light = light,
        startDiameter = light.diameter,
        targetDiameter = 0,
        elapsed = 0,
        duration = TWEEN_DURATION,
        onComplete = onComplete,
    })
end

--- easeOutQuad 缓动函数
local function EaseOutQuad(t)
    return 1 - (1 - t) * (1 - t)
end

--- easeInQuad 缓动函数
local function EaseInQuad(t)
    return t * t
end

--- 更新所有 tween 动画（每帧调用）
---@param dt number deltaTime（秒）
function FogOfWar.UpdateTweens(dt)
    if #activeTweens == 0 then return end
    lightCacheDirty = true  -- tween 改变光源尺寸，标记缓存脏
    for i = #activeTweens, 1, -1 do
        local tw = activeTweens[i]
        tw.elapsed = tw.elapsed + dt
        local progress = math.min(1.0, tw.elapsed / tw.duration)

        -- 渐入用 easeOut（快速展开），渐出用 easeIn（加速收缩）
        local eased
        if tw.targetDiameter > tw.startDiameter then
            eased = EaseOutQuad(progress)
        else
            eased = EaseInQuad(progress)
        end

        tw.light.diameter = tw.startDiameter + (tw.targetDiameter - tw.startDiameter) * eased

        if progress >= 1.0 then
            tw.light.diameter = tw.targetDiameter
            if tw.onComplete then
                tw.onComplete(tw.light)
            end
            table.remove(activeTweens, i)
        end
    end
end

--- 设置光源列表（引用传递）
---@param sources table[]
function FogOfWar.SetLightSources(sources)
    lightSources = sources or {}
end

--- 获取光源列表
function FogOfWar.GetLightSources()
    return lightSources
end

-- ====================================================================
-- Bresenham 像素圆算法 + 环形羽化
-- ====================================================================
-- 核心思路：
-- 1. 使用 Midpoint Circle 算法生成像素圆轮廓的扫描线填充
-- 2. 对每个半径生成一个像素圆，形成多层同心像素圆环
-- 3. 内圈完全点亮，外圈逐层递减（阶梯式羽化）
-- 4. 结果是正宗的像素风格圆形，边缘呈阶梯锯齿状

-- 透明度阶梯数（越少像素感越强）
local FOG_STEPS = 5

-- 缓存：对每个半径值缓存填充行数据 { [dy] = halfWidth }
-- 即圆心上下偏移 dy 行时，该行从圆心左右各填充 halfWidth 格
local circleCache = {}

--- 使用 Midpoint Circle 算法生成半径为 r 的填充圆的扫描行宽度
---@param r number 半径（格数，可以为浮点）
---@return table scanlines { [dy] = halfWidth } dy 范围 -R..+R
local function GetCircleScanlines(r)
    local ri = math.floor(r + 0.5)  -- 取整半径
    if ri < 1 then ri = 1 end

    if circleCache[ri] then return circleCache[ri] end

    -- 初始化扫描线表：dy -> 该行的半宽（从中心到边缘的格数）
    local scanlines = {}
    for dy = -ri, ri do
        scanlines[dy] = 0
    end

    -- Midpoint Circle 算法（填充版）
    local x = ri
    local y = 0
    local err = 1 - ri

    -- 填充每个八分圆对称点对应的扫描行
    local function fillScanline(px, py)
        -- px 是水平距离，py 是垂直距离
        if scanlines[py] < px then scanlines[py] = px end
        if scanlines[-py] < px then scanlines[-py] = px end
    end

    while x >= y do
        -- 八分圆对称填充
        fillScanline(x, y)
        fillScanline(y, x)

        y = y + 1
        if err < 0 then
            err = err + 2 * y + 1
        else
            x = x - 1
            err = err + 2 * (y - x) + 1
        end
    end

    circleCache[ri] = scanlines
    return scanlines
end

--- 判断 (dx, dy) 是否在半径为 r 的像素圆内
---@param dx number 相对圆心的列偏移
---@param dy number 相对圆心的行偏移
---@param r number 半径
---@return boolean
local function IsInsidePixelCircle(dx, dy, r)
    local scanlines = GetCircleScanlines(r)
    local dyi = (dy >= 0) and math.floor(dy + 0.5) or -math.floor(-dy + 0.5)
    local hw = scanlines[dyi]
    if not hw then return false end
    local dxi = (dx >= 0) and math.floor(dx + 0.5) or math.floor(-dx + 0.5)
    return dxi <= hw
end

-- ====================================================================
-- 计算某个格子的光照强度（像素圆 + 阶梯式环形羽化 + 小光源对角线柔化）
-- ====================================================================
local function CalcCellLightingWithNoise(cellCol, cellRow)
    if #lightSources == 0 then return 0 end

    local maxLight = 0
    for _, light in ipairs(lightSources) do
        if light.diameter <= 0 then goto continueLight end

        local dx = cellCol - light.col
        local dy = cellRow - light.row

        local radius = light.diameter * 0.5
        local featherAmount = light.feather  -- 0.0 ~ 1.0
        local innerRadius = radius * (1.0 - featherAmount)

        -- 快速排除：超出外接正方形（扩大1格以容纳对角线柔化）
        local absDx = (dx >= 0) and dx or -dx
        local absDy = (dy >= 0) and dy or -dy
        if absDx > radius + 2 or absDy > radius + 2 then
            goto continueLight
        end

        -- 阴影遮挡检测：如果射线被碰撞格挡住，跳过此光源
        if IsOccluded(light.col, light.row, cellCol, cellRow) then
            goto continueLight
        end

        -- 柳条衰减：光线穿过柳条时强度降低
        local curtainFactor = CalcCurtainAttenuation(light.col, light.row, cellCol, cellRow)
        -- 薄墙衰减：光线穿过一层厚度的墙壁/柱子时强度降低
        local thinWallFactor = CalcThinWallAttenuation(light.col, light.row, cellCol, cellRow)
        -- 合并衰减因子
        local combinedFactor = curtainFactor * thinWallFactor

        -- 判断是否在完整内圈像素圆内（全亮区域）
        if innerRadius >= 1 and IsInsidePixelCircle(dx, dy, innerRadius) then
            local attenuatedLight = 1.0 * combinedFactor
            if attenuatedLight > maxLight then
                maxLight = attenuatedLight
            end
            if combinedFactor >= 1.0 then return 1.0 end
            goto continueLight
        end

        -- 判断是否在外圈像素圆内（羽化区域）
        if IsInsidePixelCircle(dx, dy, radius) then
            -- 在内圈和外圈之间进行阶梯式衰减
            -- 使用同心像素环：生成 FOG_STEPS 个中间半径的像素圆
            -- 从外到内检查属于哪一环
            local intensity = 0
            if featherAmount < 0.01 then
                -- 无羽化：圆内全亮
                intensity = 1.0
            else
                -- 从内向外逐环检查：
                -- 将羽化区域等分为 FOG_STEPS 个环带
                -- 第 1 环最靠近内圈（最亮），第 FOG_STEPS 环最靠近外圈边缘（最暗）
                for step = 1, FOG_STEPS do
                    local t = step / FOG_STEPS  -- 0.2, 0.4, 0.6, 0.8, 1.0
                    local ringRadius = innerRadius + (radius - innerRadius) * t
                    if IsInsidePixelCircle(dx, dy, ringRadius) then
                        -- 该格子在第 step 环内：越靠外越暗
                        intensity = 1.0 - (step - 1) / FOG_STEPS  -- 1.0, 0.8, 0.6, 0.4, 0.2
                        break
                    end
                end
                -- 兜底：在外圈内但所有中间环都没匹配（离散化间隙）
                if intensity == 0 then
                    intensity = 1.0 / FOG_STEPS  -- 最低可见亮度
                end
            end

            -- 应用柳条+薄墙衰减
            intensity = intensity * combinedFactor

            if intensity > maxLight then
                maxLight = intensity
            end
        else
            -- ============================================================
            -- 小光源对角线柔化：当光源半径较小（radius <= 3）时，
            -- 像素圆只形成十字形，对角线完全没光照显得生硬。
            -- 对不在像素圆内的格子，计算基于欧几里得距离的微弱柔化光。
            -- ============================================================
            if radius <= 3 and radius > 0.5 then
                local dist = math.sqrt(dx * dx + dy * dy)
                -- 对角线格子（距离在 radius ~ radius+1.5 之间）给予微弱光照
                if dist <= radius + 1.5 then
                    -- 距离越远越暗，最大强度为 0.15（远低于正式光照）
                    local falloff = 1.0 - (dist - radius * 0.5) / (radius + 1.5)
                    falloff = math.max(0, math.min(1.0, falloff))
                    local softIntensity = falloff * 0.15 * combinedFactor
                    if softIntensity > maxLight then
                        maxLight = softIntensity
                    end
                end
            end
        end

        ::continueLight::
    end

    return maxLight
end

-- ====================================================================
-- 绘制迷雾遮罩
-- ====================================================================

--- 重建光照缓存（仅在脏标记时调用）
--- 只计算 startCol~endCol, startRow~endRow 范围内的光照
local function RebuildLightCache(startCol, endCol, startRow, endRow)
    for row = startRow, endRow do
        if not lightCache[row] then lightCache[row] = {} end
        for col = startCol, endCol do
            lightCache[row][col] = CalcCellLightingWithNoise(col, row)
        end
    end
end

--- 绘制战争迷雾
---@param vg userdata NanoVG context
---@param params table { gridSize, startCol, endCol, startRow, endRow, offsetX, offsetY, zoomLevel?, mapX?, mapY? }
function FogOfWar.Draw(vg, params)
    local gridSize = params.gridSize or 16
    local startCol = params.startCol or 1
    local endCol = params.endCol or 60
    local startRow = params.startRow or 1
    local endRow = params.endRow or 17
    local offsetX = params.offsetX or 0
    local offsetY = params.offsetY or 0
    local zoomLevel = params.zoomLevel or 1.0
    local mapX = params.mapX or 0
    local mapY = params.mapY or 0

    local zGrid = gridSize * zoomLevel

    -- 检测光源是否变化或可见范围变化，只在变化时重算
    local fp = CalcLightFingerprint()
    local rangeKey = startCol * 1000000 + endCol * 10000 + startRow * 100 + endRow
    if lightCacheDirty or fp ~= lastLightFingerprint or rangeKey ~= lastCacheRange then
        RebuildLightCache(startCol, endCol, startRow, endRow)
        lastLightFingerprint = fp
        lastCacheRange = rangeKey
        lightCacheDirty = false
    end

    -- 行合并渲染迷雾（RLE：相邻同 alpha 的格子合为一个大矩形）
    -- alpha 量化为 16 级（240/16=15 步），使相邻格子更容易合并
    local QUANT = 16
    for row = startRow, endRow do
        local cacheRow = lightCache[row]
        local py = mapY + (row - 1) * zGrid - offsetY
        local runStart = startCol
        local runAlpha = -1

        for col = startCol, endCol + 1 do
            local alpha = 0
            if col <= endCol then
                local lighting = (cacheRow and cacheRow[col]) or 0
                local fogAlpha = 1.0 - lighting
                if fogAlpha > 0 then
                    -- 量化到 QUANT 级
                    alpha = math.floor(fogAlpha * 240 / QUANT + 0.5) * QUANT
                    if alpha > 240 then alpha = 240 end
                end
            end

            if alpha ~= runAlpha then
                -- 输出上一段 run
                if runAlpha > 0 then
                    local px = mapX + (runStart - 1) * zGrid - offsetX
                    local w = (col - runStart) * zGrid + 0.5
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, w, zGrid + 0.5)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, runAlpha))
                    nvgFill(vg)
                end
                runStart = col
                runAlpha = alpha
            end
        end
    end
end

-- ====================================================================
-- 像素提灯形状定义（7列 x 9行）
-- 0=透明, 1=灯框(深色金属), 2=灯芯(亮黄), 3=玻璃(暖橙), 4=挂环(金属), 5=底座
-- ====================================================================
local LANTERN_SHAPE = {
    { 0, 0, 0, 4, 0, 0, 0 },  -- 顶部挂环
    { 0, 0, 4, 1, 4, 0, 0 },  -- 挂环+灯顶
    { 0, 0, 1, 1, 1, 0, 0 },  -- 灯顶盖
    { 0, 1, 3, 3, 3, 1, 0 },  -- 灯身上部
    { 0, 1, 3, 2, 3, 1, 0 },  -- 灯身中部（含灯芯）
    { 0, 1, 3, 2, 3, 1, 0 },  -- 灯身中部
    { 0, 1, 3, 3, 3, 1, 0 },  -- 灯身下部
    { 0, 0, 1, 1, 1, 0, 0 },  -- 灯底盖
    { 0, 0, 0, 5, 0, 0, 0 },  -- 底座
}
local LANTERN_COLS = 7
local LANTERN_ROWS = 9

--- 像素提灯调色板（带动态闪烁）
local function GetLanternColor(pixelType, flickerT)
    local flicker = 0.85 + 0.15 * math.sin(flickerT * 5.0)
    if pixelType == 1 then
        return 90, 70, 40, 255       -- 灯框：深铜色金属
    elseif pixelType == 2 then
        -- 灯芯：明亮黄白（闪烁）
        local r = math.min(255, math.floor(255 * flicker))
        local g = math.min(255, math.floor(240 * flicker))
        local b = math.min(255, math.floor(140 * flicker))
        return r, g, b, 255
    elseif pixelType == 3 then
        -- 玻璃灯罩：暖橙透光（半透明 + 闪烁）
        local r = math.min(255, math.floor(255 * flicker * 0.9))
        local g = math.min(255, math.floor(160 * flicker * 0.9))
        local b = math.min(255, math.floor(40 * flicker * 0.6))
        return r, g, b, 200
    elseif pixelType == 4 then
        return 110, 100, 80, 255     -- 挂环：暗灰金属
    elseif pixelType == 5 then
        return 70, 60, 50, 255       -- 底座：深灰
    end
    return 0, 0, 0, 0
end

local function GetUnlitLanternColor(pixelType)
    if pixelType == 1 then
        return 50, 40, 30, 255       -- 灯框：暗褐色
    elseif pixelType == 2 then
        return 30, 25, 20, 255       -- 灯芯位置：熄灭的黑色
    elseif pixelType == 3 then
        return 40, 35, 30, 180       -- 玻璃灯罩：暗灰不透光
    elseif pixelType == 4 then
        return 60, 55, 45, 255       -- 挂环：暗灰金属
    elseif pixelType == 5 then
        return 40, 35, 30, 255       -- 底座：深灰
    end
    return 0, 0, 0, 0
end

-- ====================================================================
-- 编辑模式：绘制光源标记（像素提灯风格）
-- ====================================================================
--- 在编辑模式下绘制光源的像素圆边界和中心标记
---@param vg userdata NanoVG context
---@param params table { gridSize, offsetX, offsetY, zoomLevel?, mapX?, mapY?, selectedIndex? }
function FogOfWar.DrawLightMarkers(vg, params)
    local gridSize = params.gridSize or 16
    local offsetX = params.offsetX or 0
    local offsetY = params.offsetY or 0
    local zoomLevel = params.zoomLevel or 1.0
    local mapX = params.mapX or 0
    local mapY = params.mapY or 0
    local selectedIndex = params.selectedIndex or 0

    local zGrid = gridSize * zoomLevel
    local flickerT = os.clock()

    -- 视口边界（用于裁剪屏幕外的光源）
    local vpLeft = offsetX / zGrid + 1
    local vpRight = vpLeft + (params.mapW or 1000) / zGrid
    local vpTop = offsetY / zGrid + 1
    local vpBottom = vpTop + (params.mapH or 600) / zGrid

    for i, light in ipairs(lightSources) do
        local isSelected = (i == selectedIndex)
        local isExtinguished = light.extinguished == true

        -- 熄灭灯用 targetDiameter 显示预期范围（虚线风格）
        local displayDiameter = isExtinguished and (light.targetDiameter or 6) or light.diameter
        local radius = displayDiameter * 0.5

        -- 视口裁剪：光源圆完全在屏幕外则跳过
        if light.col + radius < vpLeft or light.col - radius > vpRight
            or light.row + radius < vpTop or light.row - radius > vpBottom then
            goto continueLight
        end
        local innerRadius = radius * (1.0 - light.feather)
        local ri = math.floor(radius + 0.5)
        local iri = math.floor(innerRadius + 0.5)

        -- 绘制外圈像素圆边框（用方块描边）
        local outerScan = GetCircleScanlines(radius)
        local outerAlpha = isSelected and 180 or 80
        if isExtinguished then
            -- 熄灭灯用暗灰色边框
            nvgFillColor(vg, nvgRGBA(100, 80, 50, isSelected and 140 or 50))
        else
            nvgFillColor(vg, nvgRGBA(255, 200, 50, outerAlpha))
        end
        for dy = -ri, ri do
            local hw = outerScan[dy]
            if hw then
                -- 只画每行最外面两个格子（描边效果）
                -- 左边缘格
                local px = mapX + (light.col - 1 - hw) * zGrid - offsetX
                local py = mapY + (light.row - 1 + dy) * zGrid - offsetY
                nvgBeginPath(vg)
                nvgRect(vg, px, py, zGrid, zGrid)
                nvgFill(vg)
                -- 右边缘格
                px = mapX + (light.col - 1 + hw) * zGrid - offsetX
                nvgBeginPath(vg)
                nvgRect(vg, px, py, zGrid, zGrid)
                nvgFill(vg)
            end
        end
        -- 上下边缘行（完整填充，形成像素圆弧）
        for dy = -ri, ri do
            local hw = outerScan[dy]
            local nextHw = outerScan[dy - 1]  -- 上一行
            local prevHw = outerScan[dy + 1]  -- 下一行
            if hw then
                -- 如果当前行比相邻行宽，多出来的部分也要画（形成完整轮廓）
                if nextHw == nil or hw > nextHw then
                    local startHw = nextHw and (nextHw + 1) or 0
                    for ddx = startHw, hw do
                        local px = mapX + (light.col - 1 + ddx) * zGrid - offsetX
                        local py = mapY + (light.row - 1 + dy) * zGrid - offsetY
                        nvgBeginPath(vg)
                        nvgRect(vg, px, py, zGrid, zGrid)
                        nvgFill(vg)
                        if ddx > 0 then
                            px = mapX + (light.col - 1 - ddx) * zGrid - offsetX
                            nvgBeginPath(vg)
                            nvgRect(vg, px, py, zGrid, zGrid)
                            nvgFill(vg)
                        end
                    end
                end
                if prevHw == nil or hw > prevHw then
                    local startHw = prevHw and (prevHw + 1) or 0
                    for ddx = startHw, hw do
                        local px = mapX + (light.col - 1 + ddx) * zGrid - offsetX
                        local py = mapY + (light.row - 1 + dy) * zGrid - offsetY
                        nvgBeginPath(vg)
                        nvgRect(vg, px, py, zGrid, zGrid)
                        nvgFill(vg)
                        if ddx > 0 then
                            px = mapX + (light.col - 1 - ddx) * zGrid - offsetX
                            nvgBeginPath(vg)
                            nvgRect(vg, px, py, zGrid, zGrid)
                            nvgFill(vg)
                        end
                    end
                end
            end
        end

        -- 绘制内圈像素圆边框（如果有羽化）
        if light.feather > 0.01 and iri >= 1 then
            local innerScan = GetCircleScanlines(innerRadius)
            local innerAlpha = isSelected and 120 or 50
            if isExtinguished then
                nvgFillColor(vg, nvgRGBA(80, 60, 40, isSelected and 90 or 30))
            else
                nvgFillColor(vg, nvgRGBA(200, 200, 100, innerAlpha))
            end
            for dy = -iri, iri do
                local hw = innerScan[dy]
                if hw then
                    local px = mapX + (light.col - 1 - hw) * zGrid - offsetX
                    local py = mapY + (light.row - 1 + dy) * zGrid - offsetY
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, zGrid, zGrid)
                    nvgFill(vg)
                    px = mapX + (light.col - 1 + hw) * zGrid - offsetX
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, zGrid, zGrid)
                    nvgFill(vg)
                end
            end
        end

        -- ============================================================
        -- 像素提灯绘制（替代原中心标记）
        -- ============================================================
        local cx = mapX + (light.col - 1) * zGrid - offsetX
        local cy = mapY + (light.row - 1) * zGrid - offsetY

        -- 提灯像素大小：整体占 7 像素宽 = 1 格宽度
        local lanternPixel = zGrid / 7.0
        local lanternW = LANTERN_COLS * lanternPixel
        local lanternH = LANTERN_ROWS * lanternPixel
        -- 居中于光源格子
        local lx = cx + (zGrid - lanternW) * 0.5
        local ly = cy + (zGrid - lanternH) * 0.5

        -- 发光光晕（从灯内向外辐射的暖光）—— 熄灭灯不绘制光晕
        if not isExtinguished then
            local glowCx = lx + lanternW * 0.5
            local glowCy = ly + lanternH * 0.45  -- 偏上对齐灯芯
            local glowRadius = zGrid * 1.2
            local glowFlicker = 0.7 + 0.3 * math.sin(flickerT * 4.0 + i * 1.7)
            local glowAlpha = math.floor((isSelected and 100 or 70) * glowFlicker)

            -- 外层大光晕
            nvgBeginPath(vg)
            nvgCircle(vg, glowCx, glowCy, glowRadius)
            local outerGlow = nvgRadialGradient(vg, glowCx, glowCy, lanternPixel * 2, glowRadius,
                nvgRGBA(255, 180, 50, math.min(255, glowAlpha)),
                nvgRGBA(255, 100, 0, 0))
            nvgFillPaint(vg, outerGlow)
            nvgFill(vg)

            -- 内层强光（灯芯附近）
            local innerAlpha2 = math.min(255, math.floor(glowAlpha * 1.2))
            nvgBeginPath(vg)
            nvgCircle(vg, glowCx, glowCy, lanternPixel * 3)
            local innerGlow = nvgRadialGradient(vg, glowCx, glowCy, 0, lanternPixel * 3,
                nvgRGBA(255, 240, 150, innerAlpha2),
                nvgRGBA(255, 180, 50, 0))
            nvgFillPaint(vg, innerGlow)
            nvgFill(vg)
        end

        -- 逐像素绘制提灯主体（熄灭灯用暗色）
        for row = 1, LANTERN_ROWS do
            for col = 1, LANTERN_COLS do
                local pType = LANTERN_SHAPE[row][col]
                if pType > 0 then
                    local r, g, b, a
                    if isExtinguished then
                        r, g, b, a = GetUnlitLanternColor(pType)
                    else
                        r, g, b, a = GetLanternColor(pType, flickerT + i * 0.5)
                    end
                    local px = lx + (col - 1) * lanternPixel
                    local py = ly + (row - 1) * lanternPixel
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, lanternPixel + 0.5, lanternPixel + 0.5)
                    nvgFillColor(vg, nvgRGBA(r, g, b, a))
                    nvgFill(vg)
                end
            end
        end

        -- 选中时边框加亮
        if isSelected then
            nvgBeginPath(vg)
            nvgRect(vg, cx - 1, cy - 1, zGrid + 2, zGrid + 2)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 220))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
        ::continueLight::
    end
end

-- ====================================================================
-- 游戏模式：绘制像素提灯（仅灯笼+光晕，无圆形边界标记）
-- ====================================================================
--- 在游戏/试玩模式下绘制光源位置的像素提灯
---@param vg userdata NanoVG context
---@param params table { gridSize, offsetX, offsetY, zoomLevel?, mapX?, mapY? }
function FogOfWar.DrawLanterns(vg, params)
    local gridSize = params.gridSize or 16
    local offsetX = params.offsetX or 0
    local offsetY = params.offsetY or 0
    local zoomLevel = params.zoomLevel or 1.0
    local mapX = params.mapX or 0
    local mapY = params.mapY or 0

    local zGrid = gridSize * zoomLevel
    local flickerT = os.clock()

    for i, light in ipairs(lightSources) do
        if light.noLantern then goto continue_lantern end
        if light.extinguished then goto continue_lantern end  -- 熄灭灯由 DrawUnlitLanterns 绘制
        if light.diameter <= 0 then goto continue_lantern end
        local cx = mapX + (light.col - 1) * zGrid - offsetX
        local cy = mapY + (light.row - 1) * zGrid - offsetY

        -- 提灯像素大小
        local lanternPixel = zGrid / 7.0
        local lanternW = LANTERN_COLS * lanternPixel
        local lanternH = LANTERN_ROWS * lanternPixel
        local lx = cx + (zGrid - lanternW) * 0.5
        local ly = cy + (zGrid - lanternH) * 0.5

        -- 发光光晕
        local glowCx = lx + lanternW * 0.5
        local glowCy = ly + lanternH * 0.45
        local glowRadius = zGrid * 1.2
        local glowFlicker = 0.7 + 0.3 * math.sin(flickerT * 4.0 + i * 1.7)
        local glowAlpha = math.min(255, math.floor(70 * glowFlicker))

        -- 外层光晕
        nvgBeginPath(vg)
        nvgCircle(vg, glowCx, glowCy, glowRadius)
        local outerGlow = nvgRadialGradient(vg, glowCx, glowCy, lanternPixel * 2, glowRadius,
            nvgRGBA(255, 180, 50, glowAlpha),
            nvgRGBA(255, 100, 0, 0))
        nvgFillPaint(vg, outerGlow)
        nvgFill(vg)

        -- 内层强光
        local innerAlpha = math.min(255, math.floor(glowAlpha * 1.2))
        nvgBeginPath(vg)
        nvgCircle(vg, glowCx, glowCy, lanternPixel * 3)
        local innerGlow = nvgRadialGradient(vg, glowCx, glowCy, 0, lanternPixel * 3,
            nvgRGBA(255, 240, 150, innerAlpha),
            nvgRGBA(255, 180, 50, 0))
        nvgFillPaint(vg, innerGlow)
        nvgFill(vg)

        -- 逐像素绘制提灯主体
        for row = 1, LANTERN_ROWS do
            for col = 1, LANTERN_COLS do
                local pType = LANTERN_SHAPE[row][col]
                if pType > 0 then
                    local r, g, b, a = GetLanternColor(pType, flickerT + i * 0.5)
                    local px = lx + (col - 1) * lanternPixel
                    local py = ly + (row - 1) * lanternPixel
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, lanternPixel + 0.5, lanternPixel + 0.5)
                    nvgFillColor(vg, nvgRGBA(r, g, b, a))
                    nvgFill(vg)
                end
            end
        end
        ::continue_lantern::
    end
end

-- ====================================================================
-- 游戏模式：绘制熄灭的像素提灯（暗色调，无光晕）
-- ====================================================================
--- 在游戏/试玩模式下绘制熄灭状态的提灯（仅灯笼模型，无光晕）
---@param vg userdata NanoVG context
---@param params table { gridSize, offsetX, offsetY, zoomLevel?, mapX?, mapY? }
function FogOfWar.DrawUnlitLanterns(vg, params)
    local gridSize = params.gridSize or 16
    local offsetX = params.offsetX or 0
    local offsetY = params.offsetY or 0
    local zoomLevel = params.zoomLevel or 1.0
    local mapX = params.mapX or 0
    local mapY = params.mapY or 0

    local zGrid = gridSize * zoomLevel

    for _, light in ipairs(lightSources) do
        if not light.extinguished then goto continue_unlit end

        local cx = mapX + (light.col - 1) * zGrid - offsetX
        local cy = mapY + (light.row - 1) * zGrid - offsetY

        -- 提灯像素大小
        local lanternPixel = zGrid / 7.0
        local lanternW = LANTERN_COLS * lanternPixel
        local lanternH = LANTERN_ROWS * lanternPixel
        local lx = cx + (zGrid - lanternW) * 0.5
        local ly = cy + (zGrid - lanternH) * 0.5

        -- 逐像素绘制熄灭的提灯主体（暗色，无光晕）
        for row = 1, LANTERN_ROWS do
            for col = 1, LANTERN_COLS do
                local pType = LANTERN_SHAPE[row][col]
                if pType > 0 then
                    local r, g, b, a = GetUnlitLanternColor(pType)
                    local px = lx + (col - 1) * lanternPixel
                    local py = ly + (row - 1) * lanternPixel
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, lanternPixel + 0.5, lanternPixel + 0.5)
                    nvgFillColor(vg, nvgRGBA(r, g, b, a))
                    nvgFill(vg)
                end
            end
        end

        ::continue_unlit::
    end
end

-- ====================================================================
-- 光源管理 API
-- ====================================================================

--- 在指定格子放置光源
---@param col number
---@param row number
---@param diameter number 直径（格数），默认 6
---@param feather number 羽化程度 0.0~1.0，默认 0.5
---@param group number|nil 光源编组，0=默认/未编组，1~N=编组号
---@return number index 新光源的索引
function FogOfWar.AddLight(col, row, diameter, feather, group)
    local light = {
        col = col,
        row = row,
        diameter = diameter or 6,
        feather = feather or 0.5,
        group = group or 0,
    }
    table.insert(lightSources, light)
    lightCacheDirty = true
    return #lightSources
end

--- 在指定格子放置熄灭的光源（有灯模型但不发光，可被火球点亮）
---@param col number
---@param row number
---@param diameter number 点亮后的目标直径（格数），默认 6
---@param feather number 羽化程度 0.0~1.0，默认 0.5
---@param group number|nil 光源编组，0=默认/未编组
---@return number index 新光源的索引
function FogOfWar.AddUnlitLight(col, row, diameter, feather, group)
    local light = {
        col = col,
        row = row,
        diameter = 0,               -- 初始不发光
        feather = feather or 0.5,
        group = group or 0,
        extinguished = true,        -- 标记为熄灭状态
        targetDiameter = diameter or 6,  -- 点亮后的目标直径
    }
    table.insert(lightSources, light)
    return #lightSources
end

--- 点亮指定位置的熄灭光源（带渐入动画）
---@param col number
---@param row number
---@return boolean ignited 是否成功点亮
function FogOfWar.IgniteLight(col, row)
    for _, light in ipairs(lightSources) do
        if light.col == col and light.row == row and light.extinguished then
            light.extinguished = false
            local target = light.targetDiameter or 6
            TweenLightIn(light, target)
            return true
        end
    end
    return false
end

--- 查找指定位置是否有熄灭的光源
---@param col number
---@param row number
---@return boolean
function FogOfWar.HasUnlitLight(col, row)
    for _, light in ipairs(lightSources) do
        if light.col == col and light.row == row and light.extinguished then
            return true
        end
    end
    return false
end

--- 带渐入动画的光源添加（diameter 从 0 渐变到目标值，0.4 秒）
--- 这是所有游戏内动态生成光源的推荐接口
---@param col number
---@param row number
---@param diameter number 目标直径（格数），默认 6
---@param feather number 羽化程度 0.0~1.0，默认 0.5
---@param group number|nil 光源编组，0=默认/未编组，1~N=编组号
---@return number index 新光源的索引
function FogOfWar.AddLightAnimated(col, row, diameter, feather, group)
    local targetDiameter = diameter or 6
    local light = {
        col = col,
        row = row,
        diameter = 0.1,  -- 初始极小，动画会渐变
        feather = feather or 0.5,
        group = group or 0,
    }
    table.insert(lightSources, light)
    TweenLightIn(light, targetDiameter)
    return #lightSources
end

--- 带渐出动画的光源移除（diameter 从当前值渐变到 0，0.4 秒后真正移除）
--- 这是所有游戏内动态移除光源的推荐接口
---@param col number
---@param row number
---@return boolean started 是否成功启动渐出动画
function FogOfWar.RemoveLightAnimated(col, row)
    for i, light in ipairs(lightSources) do
        if light.col == col and light.row == row then
            TweenLightOut(light, function(l)
                -- 动画完成后从列表中真正移除
                for j = #lightSources, 1, -1 do
                    if lightSources[j] == l then
                        table.remove(lightSources, j)
                        break
                    end
                end
            end)
            return true
        end
    end
    return false
end

--- 移除指定位置的光源（返回是否成功）- 立即移除，无动画
---@param col number
---@param row number
---@return boolean removed
function FogOfWar.RemoveLight(col, row)
    for i = #lightSources, 1, -1 do
        if lightSources[i].col == col and lightSources[i].row == row then
            -- 同时清除该光源关联的 tween
            for j = #activeTweens, 1, -1 do
                if activeTweens[j].light == lightSources[i] then
                    table.remove(activeTweens, j)
                end
            end
            table.remove(lightSources, i)
            lightCacheDirty = true
            return true
        end
    end
    return false
end

--- 查找指定位置的光源索引
---@param col number
---@param row number
---@return number|nil index
function FogOfWar.FindLight(col, row)
    for i, light in ipairs(lightSources) do
        if light.col == col and light.row == row then
            return i
        end
    end
    return nil
end

--- 获取指定索引的光源
---@param index number
---@return table|nil light
function FogOfWar.GetLight(index)
    return lightSources[index]
end

--- 更新光源参数
---@param index number
---@param diameter number|nil
---@param feather number|nil
---@param group number|nil
function FogOfWar.UpdateLight(index, diameter, feather, group)
    local light = lightSources[index]
    if not light then return end
    if diameter then
        local clamped = math.max(2, math.min(100, diameter))
        if light.extinguished then
            -- 熄灭灯：只更新 targetDiameter，diameter 保持 0（点亮后才生效）
            light.targetDiameter = clamped
        else
            light.diameter = clamped
        end
    end
    if feather then light.feather = math.max(0, math.min(1.0, feather)) end
    if group ~= nil then light.group = math.max(0, math.floor(group)) end
    lightCacheDirty = true
end

--- 移动光源到新位置
---@param index number
---@param newCol number
---@param newRow number
function FogOfWar.MoveLight(index, newCol, newRow)
    local light = lightSources[index]
    if not light then return end
    light.col = newCol
    light.row = newRow
    lightCacheDirty = true
end

--- 清空所有光源
function FogOfWar.ClearAll()
    lightSources = {}
    activeTweens = {}
    lightCache = {}
    lightCacheDirty = true
    lastCacheRange = -1
end

--- 获取光源数量
function FogOfWar.Count()
    return #lightSources
end

--- 序列化光源数据（用于保存）
--- 跳过运行时临时光源（如篝火点燃产生的 noLantern 光源）
---@return table[]
function FogOfWar.Serialize()
    local data = {}
    for _, light in ipairs(lightSources) do
        -- 跳过运行时临时光源（篝火等动态光源标记了 noLantern）
        if light.noLantern then goto continue_serialize end
        local entry = {
            col = light.col,
            row = light.row,
            diameter = light.extinguished and (light.targetDiameter or 6) or light.diameter,
            feather = light.feather,
        }
        if light.group and light.group > 0 then
            entry.group = light.group
        end
        if light.extinguished then
            entry.extinguished = true
        end
        table.insert(data, entry)
        ::continue_serialize::
    end
    return data
end

--- 反序列化光源数据（用于加载）
---@param data table[]|nil
function FogOfWar.Deserialize(data)
    lightSources = {}
    if not data then return end
    for _, d in ipairs(data) do
        local light = {
            col = d.col or 1,
            row = d.row or 1,
            diameter = d.extinguished and 0 or (d.diameter or 6),
            feather = d.feather or 0.5,
            group = d.group or 0,
        }
        if d.extinguished then
            light.extinguished = true
            light.targetDiameter = d.diameter or 6
        end
        table.insert(lightSources, light)
    end
end

-- ====================================================================
-- 光源编组区域系统
-- ====================================================================
-- 用于游戏试玩时根据玩家所在区域切换可见光源组
-- 规则：
-- - group 0 的光源始终可见
-- - 编辑器中手动配置矩形区域（lightZones），每个区域关联一个 group
-- - 当玩家进入某个区域时，该区域的 group 对应的光源可见
-- - 切换组时，旧组渐出、新组渐入（0.2 秒过渡）

local ZONE_TRANSITION_DURATION = 0.2  -- 区域切换过渡时长（秒）

-- 光源区域列表（编辑器配置，矩形区域）
-- 每个区域: { col1, row1, col2, row2, group }
local lightZones = {}

-- 区域切换状态
local zoneState = {
    activeGroup = 0,          -- 当前激活的编组号（0=仅默认组可见）
    transitioning = false,    -- 是否正在过渡中
    fadeOutGroup = 0,         -- 正在淡出的组
    fadeInGroup = 0,          -- 正在淡入的组
    transitionElapsed = 0,    -- 过渡已用时间
    fadeOutDiameters = {},    -- { [lightRef] = originalDiameter }
    fadeInDiameters = {},     -- { [lightRef] = targetDiameter }
}

--- 获取光源区域列表
---@return table[]
function FogOfWar.GetLightZones()
    return lightZones
end

--- 设置光源区域列表（编辑器端写入）
---@param zones table[]
function FogOfWar.SetLightZones(zones)
    lightZones = zones or {}
end

--- 添加一个光源区域
---@param col1 number 左上角列
---@param row1 number 左上角行
---@param col2 number 右下角列
---@param row2 number 右下角行
---@return number index 新区域索引
function FogOfWar.AddLightZone(col1, row1, col2, row2)
    -- 规范化：确保 col1<=col2, row1<=row2
    if col1 > col2 then col1, col2 = col2, col1 end
    if row1 > row2 then row1, row2 = row2, row1 end
    table.insert(lightZones, {
        col1 = col1, row1 = row1,
        col2 = col2, row2 = row2,
    })
    return #lightZones
end

--- 删除一个光源区域
---@param index number
function FogOfWar.RemoveLightZone(index)
    if index >= 1 and index <= #lightZones then
        table.remove(lightZones, index)
    end
end

--- 序列化光源区域数据
---@return table[]
function FogOfWar.SerializeZones()
    local data = {}
    for _, z in ipairs(lightZones) do
        table.insert(data, {
            col1 = z.col1, row1 = z.row1,
            col2 = z.col2, row2 = z.row2,
        })
    end
    return data
end

--- 反序列化光源区域数据
---@param data table[]|nil
function FogOfWar.DeserializeZones(data)
    lightZones = {}
    if not data then return end
    for _, d in ipairs(data) do
        table.insert(lightZones, {
            col1 = d.col1 or 1, row1 = d.row1 or 1,
            col2 = d.col2 or 2, row2 = d.row2 or 2,
        })
    end
end

--- 重置区域状态（切换关卡时调用）
function FogOfWar.ResetZoneState()
    zoneState.activeGroup = 0
    zoneState.transitioning = false
    zoneState.fadeOutGroup = 0
    zoneState.fadeInGroup = 0
    zoneState.transitionElapsed = 0
    zoneState.fadeOutDiameters = {}
    zoneState.fadeInDiameters = {}
end

--- 判断一个光源属于哪个区域（由空间位置决定）
--- 光源中心(col,row)落在哪个区域矩形内，就属于那个区域
---@param lightCol number 光源列
---@param lightRow number 光源行
---@return number zoneIndex 区域索引（0=不在任何区域内）
local function GetLightZoneIndex(lightCol, lightRow)
    for i, zone in ipairs(lightZones) do
        if lightCol >= zone.col1 and lightCol <= zone.col2
            and lightRow >= zone.row1 and lightRow <= zone.row2 then
            return i
        end
    end
    return 0
end

--- 检测玩家当前所在的区域索引
---@param playerCol number 玩家格子列
---@param playerRow number 玩家格子行
---@return number zoneIndex 玩家所在区域索引（0=不在任何区域内）
function FogOfWar.DetectPlayerZone(playerCol, playerRow)
    for i, zone in ipairs(lightZones) do
        if playerCol >= zone.col1 and playerCol <= zone.col2
            and playerRow >= zone.row1 and playerRow <= zone.row2 then
            return i
        end
    end
    return 0
end

--- 开始区域过渡（从 oldZone 切换到 newZone）
--- 关闭旧区域内的光源，打开新区域内的光源
--- 不在任何区域内的光源始终可见
---@param oldZone number 旧区域索引（0=无区域）
---@param newZone number 新区域索引（0=无区域）
local function StartZoneTransition(oldZone, newZone)
    zoneState.transitioning = true
    zoneState.fadeOutGroup = oldZone
    zoneState.fadeInGroup = newZone
    zoneState.transitionElapsed = 0
    zoneState.fadeOutDiameters = {}
    zoneState.fadeInDiameters = {}

    for _, light in ipairs(lightSources) do
        local lightZone = GetLightZoneIndex(light.col, light.row)

        if newZone == 0 then
            -- 玩家离开所有光域 → 恢复不属于任何光域的灯，隐藏的光域灯保持隐藏
            if lightZone == 0 then
                -- 无光域的灯：如果之前被隐藏了，恢复它
                if light._originalDiameter then
                    zoneState.fadeInDiameters[light] = light._originalDiameter
                end
            elseif lightZone == oldZone then
                -- 旧光域的灯：淡出
                zoneState.fadeOutDiameters[light] = light.diameter
            end
            -- 其他光域的灯保持隐藏（已经是灭的）

        elseif oldZone == 0 then
            -- 玩家从无光域进入光域 → 新光域灯亮起，无光域的灯灭掉
            if lightZone == newZone then
                -- 新光域的灯：淡入
                local target = light._originalDiameter or light.diameter
                zoneState.fadeInDiameters[light] = target
                light.diameter = 0.1
            elseif lightZone == 0 then
                -- 不属于任何光域的灯：淡出
                if light.diameter > 0 then
                    zoneState.fadeOutDiameters[light] = light.diameter
                end
            end
            -- 其他光域的灯保持隐藏（已经是灭的）

        else
            -- 玩家从区域A切换到区域B → 旧区域灭，新区域亮
            if lightZone == newZone then
                -- 新区域的光：淡入
                local target = light._originalDiameter or light.diameter
                zoneState.fadeInDiameters[light] = target
                light.diameter = 0.1
            elseif lightZone == oldZone then
                -- 旧区域的光：淡出
                zoneState.fadeOutDiameters[light] = light.diameter
            end
            -- 其他区域和无区域的光保持当前状态（已经是灭的）
        end
    end
end

--- 更新区域过渡动画（每帧调用）
---@param dt number deltaTime（秒）
function FogOfWar.UpdateZoneTransition(dt)
    if not zoneState.transitioning then return end

    lightCacheDirty = true  -- 区域过渡改变光源 diameter
    zoneState.transitionElapsed = zoneState.transitionElapsed + dt
    local progress = math.min(1.0, zoneState.transitionElapsed / ZONE_TRANSITION_DURATION)

    -- 淡出：旧组光源直径从原始值 → 0
    local easeOut = EaseInQuad(progress)  -- 加速收缩
    for light, origDiameter in pairs(zoneState.fadeOutDiameters) do
        light.diameter = origDiameter * (1.0 - easeOut)
    end

    -- 淡入：新组光源直径从 0 → 目标值
    local easeIn = EaseOutQuad(progress)  -- 快速展开
    for light, targetDiameter in pairs(zoneState.fadeInDiameters) do
        light.diameter = targetDiameter * easeIn
    end

    -- 过渡完成
    if progress >= 1.0 then
        -- 淡出组保存原始直径并设为0
        for light, origDiameter in pairs(zoneState.fadeOutDiameters) do
            light._originalDiameter = origDiameter
            light.diameter = 0
        end
        -- 淡入组恢复到目标直径，清除原始直径标记
        for light, targetDiameter in pairs(zoneState.fadeInDiameters) do
            light.diameter = targetDiameter
            light._originalDiameter = nil
        end
        zoneState.transitioning = false
        zoneState.activeGroup = zoneState.fadeInGroup
        zoneState.fadeOutDiameters = {}
        zoneState.fadeInDiameters = {}
    end
end

--- 更新玩家区域并处理光源可见性切换
--- 应在每帧 Update 中调用
---@param playerCol number 玩家格子列
---@param playerRow number 玩家格子行
---@param dt number deltaTime
function FogOfWar.UpdatePlayerZone(playerCol, playerRow, dt)
    -- 如果没有配置区域，不处理
    if #lightZones == 0 then return end

    -- 过渡中不检测新区域
    if zoneState.transitioning then
        FogOfWar.UpdateZoneTransition(dt)
        return
    end

    local detectedZone = FogOfWar.DetectPlayerZone(playerCol, playerRow)

    -- 如果检测到的区域和当前激活区域不同，触发切换
    if detectedZone ~= zoneState.activeGroup then
        if detectedZone == 0 and zoneState.activeGroup > 0 then
            -- 离开区域回到无区域状态：显示旧区域的光（恢复所有）
            StartZoneTransition(zoneState.activeGroup, 0)
        elseif detectedZone > 0 then
            -- 进入新区域（或从一个区域切换到另一个）
            StartZoneTransition(zoneState.activeGroup, detectedZone)
        end
    end

    FogOfWar.UpdateZoneTransition(dt)
end

--- 初始化光源可见性（进入试玩模式时调用）
--- 玩家在区域X内 → 只有区域X内的光源亮，其他全灭
--- 玩家不在任何区域 → 所有光源都亮
---@param playerCol number
---@param playerRow number
function FogOfWar.InitZoneVisibility(playerCol, playerRow)
    FogOfWar.ResetZoneState()

    -- 如果没有配置任何区域，所有光源都正常显示
    if #lightZones == 0 then return end

    -- 检测玩家初始所在区域
    local initialZone = FogOfWar.DetectPlayerZone(playerCol, playerRow)
    zoneState.activeGroup = initialZone

    if initialZone == 0 then
        -- 玩家不在任何光域内：隐藏所有属于光域的灯，只保留不属于任何光域的灯
        for _, light in ipairs(lightSources) do
            local lightZone = GetLightZoneIndex(light.col, light.row)
            if lightZone ~= 0 then
                light._originalDiameter = light.diameter
                light.diameter = 0
            end
        end
    else
        -- 玩家在某个区域内：只亮该区域的灯，其他全灭
        for _, light in ipairs(lightSources) do
            local lightZone = GetLightZoneIndex(light.col, light.row)
            if lightZone ~= initialZone then
                light._originalDiameter = light.diameter
                light.diameter = 0
            end
        end
    end
end

--- 恢复所有光源到原始直径（退出试玩模式时调用）
function FogOfWar.RestoreAllLights()
    for _, light in ipairs(lightSources) do
        if light._originalDiameter then
            light.diameter = light._originalDiameter
            light._originalDiameter = nil
        end
    end
    FogOfWar.ResetZoneState()
end

--- 获取当前激活的编组号
---@return number
function FogOfWar.GetActiveGroup()
    return zoneState.activeGroup
end

-- 区域显示颜色（按索引循环）
local ZONE_COLORS = {
    {255, 100, 100},  -- 红
    {100, 180, 255},  -- 蓝
    {100, 220, 100},  -- 绿
    {255, 200, 60},   -- 黄
    {200, 130, 255},  -- 紫
    {255, 150, 80},   -- 橙
}

--- 在编辑器中绘制光源区域矩形
---@param vg userdata NanoVG context
---@param opts table { gridSize, offsetX, offsetY, zoomLevel, mapX, mapY, selectedIndex }
function FogOfWar.DrawLightZones(vg, opts)
    local grid = opts.gridSize or 16
    local ox = opts.offsetX or 0
    local oy = opts.offsetY or 0
    local zoom = opts.zoomLevel or 1.0
    local mapX = opts.mapX or 0
    local mapY = opts.mapY or 0
    local selectedIdx = opts.selectedIndex or 0

    for i, zone in ipairs(lightZones) do
        local x = mapX + (zone.col1 - 1) * grid * zoom - ox
        local y = mapY + (zone.row1 - 1) * grid * zoom - oy
        local w = (zone.col2 - zone.col1 + 1) * grid * zoom
        local h = (zone.row2 - zone.row1 + 1) * grid * zoom

        -- 按区域索引取颜色（循环）
        local gc = ZONE_COLORS[((i - 1) % #ZONE_COLORS) + 1]

        -- 填充半透明
        local alpha = (i == selectedIdx) and 50 or 25
        nvgBeginPath(vg)
        nvgRect(vg, x, y, w, h)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], alpha))
        nvgFill(vg)

        -- 边框
        local strokeAlpha = (i == selectedIdx) and 220 or 140
        nvgBeginPath(vg)
        nvgRect(vg, x, y, w, h)
        nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], strokeAlpha))
        nvgStrokeWidth(vg, (i == selectedIdx) and 2.0 or 1.0)
        nvgStroke(vg)

        -- 左上角标签（带背景）
        local label = "#" .. i
        local fontSize = math.max(11, 13 * zoom)
        nvgFontSize(vg, fontSize)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local tw = nvgTextBounds(vg, 0, 0, label)
        local pad = 2 * zoom
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + pad, y + pad, tw + pad * 2, fontSize + pad, 2 * zoom)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
        nvgText(vg, x + pad * 2, y + pad + 1, label)

        -- 中心标识（区域较大时显示）
        if w > 40 * zoom and h > 30 * zoom then
            local centerLabel = "光域 " .. i
            local centerFontSize = math.max(14, 18 * zoom)
            nvgFontSize(vg, centerFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], (i == selectedIdx) and 180 or 100))
            nvgText(vg, x + w * 0.5, y + h * 0.5, centerLabel)
        end
    end
end

return FogOfWar
