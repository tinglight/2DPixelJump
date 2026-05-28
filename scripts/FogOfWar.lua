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
-- 计算某个格子的光照强度（像素圆 + 阶梯式环形羽化）
-- ====================================================================
local function CalcCellLightingWithNoise(cellCol, cellRow)
    if #lightSources == 0 then return 0 end

    local maxLight = 0
    for _, light in ipairs(lightSources) do
        local dx = cellCol - light.col
        local dy = cellRow - light.row

        local radius = light.diameter * 0.5
        local featherAmount = light.feather  -- 0.0 ~ 1.0
        local innerRadius = radius * (1.0 - featherAmount)

        -- 快速排除：超出外接正方形
        local absDx = (dx >= 0) and dx or -dx
        local absDy = (dy >= 0) and dy or -dy
        if absDx > radius + 1 or absDy > radius + 1 then
            goto continueLight
        end

        -- 判断是否在完整内圈像素圆内（全亮区域）
        if innerRadius >= 1 and IsInsidePixelCircle(dx, dy, innerRadius) then
            maxLight = 1.0
            return 1.0
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

            if intensity > maxLight then
                maxLight = intensity
            end
        end

        ::continueLight::
    end

    return maxLight
end

-- ====================================================================
-- 绘制迷雾遮罩
-- ====================================================================
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

    -- 逐格渲染迷雾
    for row = startRow, endRow do
        for col = startCol, endCol do
            -- 计算该格子的光照强度（像素圆环形判定）
            local lighting = CalcCellLightingWithNoise(col, row)

            -- 计算迷雾不透明度（1 - 光照 = 黑暗度）
            local fogAlpha = 1.0 - lighting

            if fogAlpha <= 0 then goto continueFog end

            -- 将 fogAlpha 映射到 0~240（不完全 255，保留一点可见度感）
            local alpha = math.floor(fogAlpha * 240)

            local px = mapX + (col - 1) * zGrid - offsetX
            local py = mapY + (row - 1) * zGrid - offsetY

            nvgBeginPath(vg)
            nvgRect(vg, px, py, zGrid + 0.5, zGrid + 0.5)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
            nvgFill(vg)

            ::continueFog::
        end
    end
end

-- ====================================================================
-- 编辑模式：绘制光源标记（像素方块风格）
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

    for i, light in ipairs(lightSources) do
        local isSelected = (i == selectedIndex)
        local radius = light.diameter * 0.5
        local innerRadius = radius * (1.0 - light.feather)
        local ri = math.floor(radius + 0.5)
        local iri = math.floor(innerRadius + 0.5)

        -- 绘制外圈像素圆边框（用方块描边）
        local outerScan = GetCircleScanlines(radius)
        local outerAlpha = isSelected and 180 or 80
        nvgFillColor(vg, nvgRGBA(255, 200, 50, outerAlpha))
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
            nvgFillColor(vg, nvgRGBA(200, 200, 100, innerAlpha))
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

        -- 中心标记（小十字 + 点）
        local cx = mapX + (light.col - 1) * zGrid - offsetX
        local cy = mapY + (light.row - 1) * zGrid - offsetY
        local markAlpha = isSelected and 255 or 160

        -- 中心格高亮
        nvgBeginPath(vg)
        nvgRect(vg, cx, cy, zGrid, zGrid)
        nvgFillColor(vg, nvgRGBA(255, 220, 50, markAlpha))
        nvgFill(vg)

        -- 选中时边框加亮
        if isSelected then
            nvgBeginPath(vg)
            nvgRect(vg, cx - 1, cy - 1, zGrid + 2, zGrid + 2)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 220))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
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
---@return number index 新光源的索引
function FogOfWar.AddLight(col, row, diameter, feather)
    local light = {
        col = col,
        row = row,
        diameter = diameter or 6,
        feather = feather or 0.5,
    }
    table.insert(lightSources, light)
    return #lightSources
end

--- 移除指定位置的光源（返回是否成功）
---@param col number
---@param row number
---@return boolean removed
function FogOfWar.RemoveLight(col, row)
    for i = #lightSources, 1, -1 do
        if lightSources[i].col == col and lightSources[i].row == row then
            table.remove(lightSources, i)
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
function FogOfWar.UpdateLight(index, diameter, feather)
    local light = lightSources[index]
    if not light then return end
    if diameter then light.diameter = math.max(2, math.min(30, diameter)) end
    if feather then light.feather = math.max(0, math.min(1.0, feather)) end
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
end

--- 清空所有光源
function FogOfWar.ClearAll()
    lightSources = {}
end

--- 获取光源数量
function FogOfWar.Count()
    return #lightSources
end

--- 序列化光源数据（用于保存）
---@return table[]
function FogOfWar.Serialize()
    local data = {}
    for _, light in ipairs(lightSources) do
        table.insert(data, {
            col = light.col,
            row = light.row,
            diameter = light.diameter,
            feather = light.feather,
        })
    end
    return data
end

--- 反序列化光源数据（用于加载）
---@param data table[]|nil
function FogOfWar.Deserialize(data)
    lightSources = {}
    if not data then return end
    for _, d in ipairs(data) do
        table.insert(lightSources, {
            col = d.col or 1,
            row = d.row or 1,
            diameter = d.diameter or 6,
            feather = d.feather or 0.5,
        })
    end
end

return FogOfWar
