------------------------------------------------------------
-- gameplay/FlameDashChain.lua — 灯火跃迁（Flame Dash Chain）
--
-- 玩家解锁火焰后可触发灯火跃迁：
-- 1. 从当前位置寻找光照范围覆盖玩家的亮灯，高速飞向目标灯
-- 2. 到达后在该灯光照范围内搜索下一盏未访问亮灯，连锁移动
-- 3. 找不到下一盏灯 → 检测是否靠近地图边缘，尝试跨地图跃迁
-- 4. 跨地图也找不到灯 → 从最后一盏灯高速下落到地面
-- 全程不消耗能量、不响应移动/跳跃输入、不执行下落剥离像素
--
-- 通用设计：通过 context 表与宿主系统交互，兼容 gameplay/init 和 editor/PlayMode
------------------------------------------------------------
local FogOfWar = require("FogOfWar")

local M = {}

-- 外部依赖（通过 Inject 注入，用于跨地图）
local LevelManager = nil
local PlayerController = nil
local Physics = nil

--- 注入依赖（用于跨地图跃迁）
---@param deps table { LevelManager, PlayerController, Physics }
function M.Inject(deps)
    LevelManager = deps.LevelManager
    PlayerController = deps.PlayerController
    Physics = deps.Physics
end

-- ====================================================================
-- 状态定义
-- ====================================================================
local STATE_IDLE     = "idle"
local STATE_FLYING   = "flying"
local STATE_ARRIVING = "arriving"
local STATE_FALLING  = "falling"

-- ====================================================================
-- 配置
-- ====================================================================
M.FLY_SPEED        = 80    -- 飞行速度（格/秒）
M.ARRIVE_PAUSE     = 0.08  -- 到达灯后的短暂停顿（秒）
M.FALL_SPEED       = 60    -- 下落速度（格/秒）

-- 跨地图配置
local EDGE_THRESHOLD    = 8   -- 灯距地图边缘 <= 此值视为"靠近边缘"
local ENTRY_SEARCH_RADIUS = 12 -- 跨地图后在入口附近搜索灯的半径（格）
local MAX_CROSS_LEVEL   = 20  -- 单次触发允许的最大连续跨图次数

-- ====================================================================
-- 运行时状态
-- ====================================================================
local state = STATE_IDLE
local visited = {}         -- 已访问灯的 "col_row" 集合（当前关卡）
local crossVisited = {}    -- 跨关卡已访问灯的 "file:col_row" 集合（防止跨关卡循环）
local targetLight = nil    -- 当前飞向的灯 {col, row, diameter}
local targetAnchorX = 0    -- 安全锚点 gridX（预计算，不嵌入实体）
local targetAnchorY = 0    -- 安全锚点 gridY
local arriveTimer = 0      -- 到达停顿计时器

-- 插值位置（子像素精度，用于平滑飞行）
local flyX = 0
local flyY = 0

-- 跨地图状态
local crossLevelPending = false  -- 是否正在等待跨地图加载
local crossCount = 0             -- 本次触发已连续跨图次数
local lastCrossDir = nil         -- 上次跨入新关卡的方向（用于连续跨图时方向优先选灯）

-- 缓存的 ctx 引用（仅在一次 Update 调用内有效）
local cachedCtx = nil

-- ====================================================================
-- 公开状态查询
-- ====================================================================

--- 是否正在跃迁中（外部用于屏蔽普通输入/物理）
function M.IsActive()
    return state ~= STATE_IDLE
end

--- 获取当前状态名（调试用）
function M.GetState()
    return state
end

--- 获取飞行中的子像素位置（用于渲染流光）
function M.GetFlyPosition()
    return flyX, flyY
end

--- 获取飞行目标位置（用于计算飞行方向）
function M.GetTarget()
    if targetLight then
        return targetLight.col, targetLight.row
    end
    return nil, nil
end

--- 获取本次触发的连续跨图次数（调试/HUD 用）
function M.GetCrossCount()
    return crossCount
end

-- ====================================================================
-- 内部工具函数
-- ====================================================================

local function LightKey(col, row)
    return col .. "_" .. row
end

local function GridDistance(col1, row1, col2, row2)
    local dx = col1 - col2
    local dy = row1 - row2
    return math.sqrt(dx * dx + dy * dy)
end

local function IsInLightRange(lamp, col, row)
    local radius = lamp.diameter / 2
    return GridDistance(lamp.col, lamp.row, col, row) <= radius
end

--- 获取灯的有效直径（委托给 FogOfWar，正确处理 zone 过渡和 tween 动画）
local function GetEffectiveDiameter(light)
    return FogOfWar.GetEffectiveDiameter(light)
end

-- 前向声明（FindNextLampFromLamp 在定义时需要引用）
local FindDirectionalLitLamp

--- 从指定位置搜索覆盖该位置的最近亮灯
--- @param fromCol number 搜索起点 col
--- @param fromRow number 搜索起点 row
--- @param searchRadius number|nil 搜索范围（nil 时用灯自身 diameter/2 判断）
--- @return table|nil
local function FindNearestLitLamp(fromCol, fromRow, searchRadius)
    local sources = FogOfWar.GetLightSources()
    local bestDist = math.huge
    local bestLamp = nil

    for _, light in ipairs(sources) do
        -- 只考虑亮灯（非熄灭、有灯笼模型）
        -- 使用有效直径（targetDiameter）判断，避免动画渐入期间被错误过滤
        local effDiam = GetEffectiveDiameter(light)
        if not light.extinguished and effDiam > 1 and not light.noLantern then
            local key = LightKey(light.col, light.row)
            if not visited[key] then
                local inRange
                if searchRadius then
                    inRange = GridDistance(fromCol, fromRow, light.col, light.row) <= searchRadius
                else
                    -- 使用有效直径计算光照范围覆盖
                    local radius = effDiam / 2
                    inRange = GridDistance(light.col, light.row, fromCol, fromRow) <= radius
                end
                if inRange then
                    local dist = GridDistance(fromCol, fromRow, light.col, light.row)
                    if dist < bestDist then
                        bestDist = dist
                        bestLamp = light
                    end
                end
            end
        end
    end

    return bestLamp
end

--- 从当前灯的光照范围内搜索下一盏灯
--- @param lamp table 当前灯
--- @param preferDir string|nil 优先方向（跨图后用于偏好跨入方向的灯）
--- @return table|nil
local function FindNextLampFromLamp(lamp, preferDir)
    local radius = GetEffectiveDiameter(lamp) / 2
    if preferDir then
        return FindDirectionalLitLamp(lamp.col, lamp.row, radius, preferDir)
    end
    return FindNearestLitLamp(lamp.col, lamp.row, radius)
end

--- 判断灯是否在 edgeDir 方向的"前方"（即符合跃迁行进方向）
--- @param lampCol number
--- @param lampRow number
--- @param refCol number 入口参考点 col
--- @param refRow number 入口参考点 row
--- @param edgeDir string "left"|"right"|"up"|"down"
--- @return boolean
local function IsInPreferredDirection(lampCol, lampRow, refCol, refRow, edgeDir)
    if edgeDir == "down" then
        return lampRow >= refRow
    elseif edgeDir == "up" then
        return lampRow <= refRow
    elseif edgeDir == "right" then
        return lampCol >= refCol
    elseif edgeDir == "left" then
        return lampCol <= refCol
    end
    return true
end

--- 跨地图专用灯搜索：带方向优先级
--- 先按方向匹配分组（匹配方向的灯优先），同组内按距离排序
--- @param fromCol number 搜索起点 col
--- @param fromRow number 搜索起点 row
--- @param searchRadius number 搜索范围
--- @param edgeDir string 跨图方向
--- @return table|nil
FindDirectionalLitLamp = function(fromCol, fromRow, searchRadius, edgeDir)
    local sources = FogOfWar.GetLightSources()
    local candidates = {}

    for _, light in ipairs(sources) do
        local effDiam = GetEffectiveDiameter(light)
        if not light.extinguished and effDiam > 1 and not light.noLantern then
            local key = LightKey(light.col, light.row)
            if not visited[key] then
                local dist = GridDistance(fromCol, fromRow, light.col, light.row)
                if dist <= searchRadius then
                    local inDir = IsInPreferredDirection(light.col, light.row, fromCol, fromRow, edgeDir)
                    table.insert(candidates, { lamp = light, dist = dist, inDir = inDir })
                end
            end
        end
    end

    if #candidates == 0 then return nil end

    -- 排序：方向匹配优先，其次按距离
    table.sort(candidates, function(a, b)
        if a.inDir ~= b.inDir then
            return a.inDir  -- true 排前面
        end
        return a.dist < b.dist
    end)

    return candidates[1].lamp
end

-- ====================================================================
-- 跨地图支持
-- ====================================================================

--- 跨关卡 key（包含文件名，防止跨关卡循环）
local function CrossLevelKey(file, col, row)
    return (file or "") .. ":" .. col .. "_" .. row
end

--- 判断灯是否靠近地图某个边缘，返回方向或 nil
--- @param lamp table {col, row}
--- @param mapCols number
--- @param mapRows number
--- @return string|nil "left"|"right"|"up"|"down"
local function GetNearEdgeDirection(lamp, mapCols, mapRows)
    -- 按优先级检查（只返回最近的一个方向）
    local distLeft  = lamp.col
    local distRight = mapCols - lamp.col
    local distUp    = lamp.row
    local distDown  = mapRows - lamp.row

    local minDist = math.huge
    local dir = nil

    if distLeft <= EDGE_THRESHOLD and distLeft < minDist then
        minDist = distLeft
        dir = "left"
    end
    if distRight <= EDGE_THRESHOLD and distRight < minDist then
        minDist = distRight
        dir = "right"
    end
    if distUp <= EDGE_THRESHOLD and distUp < minDist then
        minDist = distUp
        dir = "up"
    end
    if distDown <= EDGE_THRESHOLD and distDown < minDist then
        minDist = distDown
        dir = "down"
    end

    return dir
end

--- 根据进入方向和 exitLamp 坐标计算入口搜索中心点
--- @param fromDir string 从哪个方向进入（"left" 表示从左边界进入，即 direction 连接方向是 left）
--- @param mapCols number 新地图列数
--- @param mapRows number 新地图行数
--- @param exitRow number|nil exitLamp 在旧地图的 row（left/right 跨图时保留）
--- @param exitCol number|nil exitLamp 在旧地图的 col（up/down 跨图时保留）
--- @return number, number  searchCenterCol, searchCenterRow
local function GetEntrySearchCenter(fromDir, mapCols, mapRows, exitRow, exitCol)
    -- fromDir 是 FindConnectedLevel 的方向参数
    -- "left" 意味着玩家向左离开当前关卡 → 从右侧进入新关卡
    -- "right" 意味着玩家向右离开当前关卡 → 从左侧进入新关卡
    if fromDir == "left" then
        -- 从右边界进入新关卡，保留 exitLamp.row，clamp 到新地图范围
        local row = math.max(2, math.min(mapRows - 1, exitRow or math.floor(mapRows / 2)))
        return mapCols - 1, row
    elseif fromDir == "right" then
        -- 从左边界进入新关卡，保留 exitLamp.row，clamp 到新地图范围
        local row = math.max(2, math.min(mapRows - 1, exitRow or math.floor(mapRows / 2)))
        return 2, row
    elseif fromDir == "up" then
        -- 从下边界进入新关卡，保留 exitLamp.col，clamp 到新地图范围
        local col = math.max(2, math.min(mapCols - 1, exitCol or math.floor(mapCols / 2)))
        return col, mapRows - 1
    elseif fromDir == "down" then
        -- 从上边界进入新关卡，保留 exitLamp.col，clamp 到新地图范围
        local col = math.max(2, math.min(mapCols - 1, exitCol or math.floor(mapCols / 2)))
        return col, 2
    end
    return math.floor(mapCols / 2), math.floor(mapRows / 2)
end

--- 根据进入方向和 exitLamp 坐标计算安全落地位置
--- @param fromDir string
--- @param mapCols number 新地图列数
--- @param mapRows number 新地图行数
--- @param gridSize number 玩家格子尺寸
--- @param exitRow number|nil exitLamp 在旧地图的 row（left/right 跨图时保留）
--- @param exitCol number|nil exitLamp 在旧地图的 col（up/down 跨图时保留）
--- @return number, number  gridX, gridY
local function GetEntrySafePosition(fromDir, mapCols, mapRows, gridSize, exitRow, exitCol)
    if fromDir == "left" then
        -- 从右边界进入，保留 exitLamp.row
        local row = math.max(2, math.min(mapRows - gridSize - 1, exitRow or math.floor(mapRows / 2)))
        return mapCols - gridSize - 1, row
    elseif fromDir == "right" then
        -- 从左边界进入，保留 exitLamp.row
        local row = math.max(2, math.min(mapRows - gridSize - 1, exitRow or math.floor(mapRows / 2)))
        return 2, row
    elseif fromDir == "up" then
        -- 从下边界进入，保留 exitLamp.col
        local col = math.max(2, math.min(mapCols - gridSize - 1, exitCol or math.floor(mapCols / 2)))
        return col, mapRows - gridSize - 1
    elseif fromDir == "down" then
        -- 从上边界进入，保留 exitLamp.col
        local col = math.max(2, math.min(mapCols - gridSize - 1, exitCol or math.floor(mapCols / 2)))
        return col, 2
    end
    return math.floor(mapCols / 2), math.floor(mapRows / 2)
end

--- 尝试跨地图跃迁
--- 条件：当前关卡找不到下一盏灯 + 最后一盏灯靠近边缘 + 有相邻关卡
--- 支持两种模式：
---   1. 通过 Inject 注入的 LevelManager（gameplay 模式）
---   2. 通过 ctx.crossLevel 传入回调（editor PlayMode 模式）
--- @param lamp table 最后一盏灯
--- @param ctx table 上下文
--- @return table|nil 新关卡中找到的灯（已设置为 targetLight），nil 表示跨地图失败
--- @return string|nil 跨入方向 edgeDir（成功时返回）
local function TryCrossLevelDash(lamp, ctx)
    -- 连续跨图次数上限
    if crossCount >= MAX_CROSS_LEVEL then
        print("[FlameDash-Cross] Max cross-level count reached (" .. MAX_CROSS_LEVEL .. "), stop")
        return nil, nil
    end

    local cl = ctx.crossLevel  -- editor 模式的回调接口

    -- 必须有 LevelManager 或 ctx.crossLevel
    if not cl and not LevelManager then return nil, nil end

    local worldMapData = cl and cl.worldMapData or (LevelManager and LevelManager.worldMapData)
    local currentFile = cl and cl.currentLevelFile or (LevelManager and LevelManager.currentLevelFile)
    if not worldMapData or not currentFile then return nil, nil end

    -- 获取当前关卡地图尺寸
    local mapCols, mapRows
    if cl and cl.getMapSize then
        mapCols, mapRows = cl.getMapSize()
    else
        local Config = require("gameplay.Config")
        mapCols = Config.MAP_COLS
        mapRows = Config.MAP_ROWS
    end

    -- 1. 判断灯是否靠近边缘
    local edgeDir = GetNearEdgeDirection(lamp, mapCols, mapRows)
    if not edgeDir then
        print("[FlameDash-Cross] Last lamp not near edge, no cross-level")
        return nil, nil
    end

    -- 2. 查找该方向相邻关卡
    local targetFile
    if cl and cl.findConnectedLevel then
        targetFile = cl.findConnectedLevel(edgeDir)
    else
        targetFile = LevelManager.FindConnectedLevel(edgeDir)
    end
    if not targetFile then
        print("[FlameDash-Cross] No connected level in direction: " .. edgeDir)
        return nil, nil
    end

    -- 3. 检查该关卡是否已在 crossVisited 中被标记（防止 A→B→A 循环）
    for k, _ in pairs(crossVisited) do
        if k:sub(1, #targetFile + 1) == targetFile .. ":" then
            print("[FlameDash-Cross] Target level already visited, abort: " .. targetFile)
            return nil, nil
        end
    end

    -- 4. 标记当前关卡所有已访问灯到 crossVisited
    for key, _ in pairs(visited) do
        crossVisited[currentFile .. ":" .. key] = true
    end

    -- 5. 获取玩家对象
    local player = cl and cl.player or (PlayerController and PlayerController.player)
    if not player then return nil, nil end

    -- 保存跨关卡状态
    local savedFallGridCount = player.fallGridCount or 0

    -- 记录 exitLamp 的相对坐标（用于在新地图中定位入口点）
    local exitRow = lamp.row
    local exitCol = lamp.col

    print("[FlameDash-Cross] Loading adjacent level: " .. targetFile .. " (dir=" .. edgeDir
        .. ") exitLamp=(" .. exitCol .. "," .. exitRow .. ")")

    -- 6. 执行关卡加载
    local loadSuccess
    if cl and cl.loadLevel then
        loadSuccess = cl.loadLevel(targetFile)
    else
        loadSuccess = LevelManager.LoadLevelFromFile(targetFile, player)
    end
    if not loadSuccess then
        print("[FlameDash-Cross] Failed to load level: " .. targetFile)
        return nil, nil
    end

    -- 加载后立刻刷新地图尺寸（新关卡可能尺寸不同，后续不再使用旧值）
    if cl and cl.getMapSize then
        mapCols, mapRows = cl.getMapSize()
    else
        local Config = require("gameplay.Config")
        mapCols = Config.MAP_COLS
        mapRows = Config.MAP_ROWS
    end

    -- 7. 设置玩家入口位置（使用 exitLamp 坐标推算入口点）
    local gridSize = ctx.gridSize or 2
    local entryX, entryY = GetEntrySafePosition(edgeDir, mapCols, mapRows, gridSize, exitRow, exitCol)
    player.gridX = entryX
    player.gridY = entryY
    flyX = entryX
    flyY = entryY

    -- 设置过渡冷却
    if cl and cl.setCooldown then
        cl.setCooldown(0.5)
    elseif LevelManager then
        LevelManager.transitionCooldown = 0.5
    end

    -- 更新 Physics 引用（仅 gameplay 模式有独立 Physics 模块）
    if Physics and LevelManager then
        Physics.SetLevelData(LevelManager.levelData)
        Physics.SetSwitchState(LevelManager.switchState)
        Physics.SetHiddenWallRevealed(LevelManager.hiddenWallRevealed)
    end

    -- 初始化 zone visibility（否则 zone 内的灯会被隐藏）
    FogOfWar.InitZoneVisibility(entryX + 1, entryY + 1)

    -- 8. 在入口附近搜索已点亮灯（带方向优先级）
    -- 重置当前关卡的 visited（新关卡是新的灯集合）
    visited = {}

    -- 使用 exitLamp 坐标计算入口搜索中心（而非地图中心）
    local searchCol, searchRow = GetEntrySearchCenter(edgeDir, mapCols, mapRows, exitRow, exitCol)
    local entryLamp = FindDirectionalLitLamp(searchCol, searchRow, ENTRY_SEARCH_RADIUS, edgeDir)

    if entryLamp then
        -- 检查 crossVisited 防循环
        local entryKey = CrossLevelKey(targetFile, entryLamp.col, entryLamp.row)
        if crossVisited[entryKey] then
            print("[FlameDash-Cross] Entry lamp already cross-visited, land at entry")
            -- loadLevel 已成功，不能回旧地图。落在入口安全点，进入 falling
            crossCount = crossCount + 1
            lastCrossDir = edgeDir
            if ctx.onCrossLevel then ctx.onCrossLevel() end
            return nil, edgeDir
        end

        -- 找到灯！继续 dash chain，增加跨图计数
        crossCount = crossCount + 1
        lastCrossDir = edgeDir
        visited[LightKey(entryLamp.col, entryLamp.row)] = true
        crossVisited[entryKey] = true
        print("[FlameDash-Cross] Found entry lamp at (" .. entryLamp.col .. "," .. entryLamp.row
            .. "), continue chain! (crossCount=" .. crossCount .. "/" .. MAX_CROSS_LEVEL .. ")")
        return entryLamp, edgeDir
    else
        -- loadLevel 已成功，地图已切换，不能回旧 ctx。
        -- 把玩家放在新地图入口安全点，进入 falling 状态。
        print("[FlameDash-Cross] No lit lamp near entry, landing at safe point in new level")
        crossCount = crossCount + 1
        lastCrossDir = edgeDir
        if ctx.onCrossLevel then ctx.onCrossLevel() end
        return nil, edgeDir
    end
end

-- ====================================================================
-- 安全锚点搜索
-- ====================================================================

--- 在灯周围搜索一个玩家碰撞盒不会重叠实体的安全 grid 坐标
--- 搜索策略：以灯为中心，优先正上方，然后螺旋式向外扩展
--- @param lamp table {col, row, diameter}
--- @param ctx table 上下文（需包含 gridSize, isBodyBlocked）
--- @return number, number, boolean  safeX, safeY, found
local function FindSafeDashAnchor(lamp, ctx)
    local s = ctx.gridSize or 2
    -- 灯中心对应的玩家 grid 坐标
    local baseX = lamp.col - math.floor(s / 2)
    local baseY = lamp.row - math.floor(s / 2)

    -- 如果没有碰撞检测回调，直接返回原始坐标
    if not ctx.isBodyBlocked then
        return baseX, baseY, true
    end

    -- 如果灯中心位置本身就安全，直接用
    if not ctx.isBodyBlocked(baseX, baseY) then
        return baseX, baseY, true
    end

    -- 优先向上搜索（最符合"在灯上方出现"的预期）
    for dy = -1, -4, -1 do
        if not ctx.isBodyBlocked(baseX, baseY + dy) then
            return baseX, baseY + dy, true
        end
    end

    -- 向上没找到，尝试左右偏移 + 向上搜索
    for dx = -1, 1, 2 do
        for dy = 0, -4, -1 do
            local testX = baseX + dx
            local testY = baseY + dy
            if not ctx.isBodyBlocked(testX, testY) then
                return testX, testY, true
            end
        end
    end

    -- 都找不到安全位置
    return baseX, baseY, false
end

--- 向下扫描寻找 onGround 的安全落地位置
--- @param gx number 起始 gridX
--- @param gy number 起始 gridY
--- @param ctx table 上下文
--- @param maxDown number 最大向下搜索格数
--- @return number 安全的 gridY
local function ScanDownForGround(gx, gy, ctx, maxDown)
    maxDown = maxDown or 20
    for i = 0, maxDown do
        local testY = gy + i
        if testY > ctx.mapRows then
            return testY  -- 越界，交给后续 boundary 判定
        end
        if ctx.onGround(gx, testY) then
            -- 找到地面，但需确认身体不嵌入
            if not ctx.isBodyBlocked or not ctx.isBodyBlocked(gx, testY) then
                return testY
            end
            -- 身体嵌入，向上微调
            for up = 1, 4 do
                if not ctx.isBodyBlocked(gx, testY - up) then
                    return testY - up
                end
            end
            return testY  -- fallback
        end
    end
    return gy + maxDown
end

-- ====================================================================
-- 触发
-- ====================================================================

--- 尝试触发灯火跃迁
--- @param ctx table 上下文 { gridX, gridY, gridSize, mapRows, forceLamp?, isBodyBlocked? }
--- @return boolean 是否成功触发
function M.TryTrigger(ctx)
    if state ~= STATE_IDLE then return false end

    local gridX = ctx.gridX
    local gridY = ctx.gridY
    local s = ctx.gridSize or 2

    -- 玩家中心位置
    local playerCenterCol = gridX + (s - 1) / 2
    local playerCenterRow = gridY + (s - 1) / 2

    -- 清空访问记录和跨图计数
    visited = {}
    crossVisited = {}
    crossCount = 0
    lastCrossDir = nil

    -- 如果有 forceLamp（火球命中的灯），直接用它作为第一个目标
    -- 否则搜索覆盖玩家位置的最近亮灯
    local lamp = ctx.forceLamp or FindNearestLitLamp(playerCenterCol, playerCenterRow, nil)
    if not lamp then
        return false
    end

    -- 预计算安全锚点
    local safeX, safeY, found = FindSafeDashAnchor(lamp, ctx)
    if not found then
        print("[FlameDash] No safe anchor for lamp at (" .. lamp.col .. "," .. lamp.row .. "), abort")
        return false
    end

    -- 标记已访问
    visited[LightKey(lamp.col, lamp.row)] = true
    targetLight = lamp
    targetAnchorX = safeX
    targetAnchorY = safeY

    -- 初始化飞行起始位置
    flyX = gridX
    flyY = gridY

    state = STATE_FLYING
    print("[FlameDash] Triggered! Flying to lamp at (" .. lamp.col .. "," .. lamp.row .. ") anchor=(" .. safeX .. "," .. safeY .. ")")
    return true
end

-- ====================================================================
-- 更新（每帧调用）
-- ====================================================================

--- 主更新函数
--- @param dt number
--- @param ctx table { gridX, gridY, gridSize, mapRows, onGround(gx,gy)->bool, isBodyBlocked(gx,gy)->bool, setPos(gx,gy), onLand(), onBoundary() }
--- @return string|nil "landed"|"boundary" 或 nil
function M.Update(dt, ctx)
    if state == STATE_IDLE then return nil end

    local s = ctx.gridSize or 2

    if state == STATE_FLYING then
        -- 飞行目标是预计算的安全锚点，不是灯的原始 col/row
        local dx = targetAnchorX - flyX
        local dy = targetAnchorY - flyY
        local dist = math.sqrt(dx * dx + dy * dy)

        local arrived = dist < 0.5
        if not arrived then
            local moveStep = M.FLY_SPEED * dt
            if moveStep >= dist then
                arrived = true
            else
                flyX = flyX + (dx / dist) * moveStep
                flyY = flyY + (dy / dist) * moveStep
                ctx.setPos(math.floor(flyX + 0.5), math.floor(flyY + 0.5))
            end
        end

        if arrived then
            flyX = targetAnchorX
            flyY = targetAnchorY
            ctx.setPos(targetAnchorX, targetAnchorY)
            state = STATE_ARRIVING
            arriveTimer = M.ARRIVE_PAUSE
        end

    elseif state == STATE_ARRIVING then
        arriveTimer = arriveTimer - dt
        if arriveTimer <= 0 then
            -- 如果刚跨图进来，用跨入方向优先选灯；找到后清除方向偏好
            local nextLamp = FindNextLampFromLamp(targetLight, lastCrossDir)
            if nextLamp then
                -- 为下一盏灯计算安全锚点
                local safeX, safeY, found = FindSafeDashAnchor(nextLamp, ctx)
                if found then
                    visited[LightKey(nextLamp.col, nextLamp.row)] = true
                    targetLight = nextLamp
                    targetAnchorX = safeX
                    targetAnchorY = safeY
                    flyX = ctx.gridX
                    flyY = ctx.gridY
                    state = STATE_FLYING
                    lastCrossDir = nil  -- 成功找到同关卡内下一灯后清除方向偏好
                    print("[FlameDash] Chain to lamp at (" .. nextLamp.col .. "," .. nextLamp.row .. ") anchor=(" .. safeX .. "," .. safeY .. ")")
                else
                    -- 下一盏灯找不到安全锚点，当作链式结束
                    print("[FlameDash] Next lamp has no safe anchor, ending chain")
                    nextLamp = nil  -- 走下方 fall 逻辑
                end
            end

            if not nextLamp then
                -- 尝试跨地图跃迁
                local crossLamp, crossDir = TryCrossLevelDash(targetLight, ctx)
                if crossLamp then
                    -- 跨地图成功，计算新关卡中灯的安全锚点
                    local safeX, safeY, found = FindSafeDashAnchor(crossLamp, ctx)
                    if found then
                        targetLight = crossLamp
                        targetAnchorX = safeX
                        targetAnchorY = safeY
                        -- 注意：TryCrossLevelDash 内部已更新 player 位置和 flyX/flyY
                        -- 这里不能用 ctx.gridX/gridY（那是帧开始时的快照，已经过时）
                        state = STATE_FLYING
                        print("[FlameDash-Cross] Continue chain to cross-level lamp at ("
                            .. crossLamp.col .. "," .. crossLamp.row .. ") anchor=(" .. safeX .. "," .. safeY .. ")")
                        -- 通知外部关卡已切换（用于刷新渲染等）
                        if ctx.onCrossLevel then ctx.onCrossLevel() end
                        return "cross_level"
                    end
                    -- 锚点计算失败，但地图已切换（crossDir ~= nil），进入 falling
                    -- 落在 TryCrossLevelDash 设置的入口安全点
                    state = STATE_FALLING
                    -- flyX/flyY 已在 TryCrossLevelDash 中设置为入口安全点
                    print("[FlameDash-Cross] Anchor failed after cross-level, falling in new map")
                    return "cross_level"
                elseif crossDir then
                    -- crossLamp 为 nil 但 crossDir 不为 nil：
                    -- 地图已成功切换，但没找到 entryLamp。
                    -- 玩家已在 TryCrossLevelDash 中被放到入口安全点，直接进入 falling。
                    state = STATE_FALLING
                    -- flyX/flyY 已在 TryCrossLevelDash 中设置
                    print("[FlameDash-Cross] Cross-level succeeded but no lamp, falling at entry")
                    return "cross_level"
                end

                -- 链式结束（未跨图或跨图彻底失败） → 进入落地阶段
                -- 二次校验当前位置
                local curX, curY = ctx.gridX, ctx.gridY
                if ctx.isBodyBlocked and ctx.isBodyBlocked(curX, curY) then
                    -- 仍然碰撞（不应该发生），向上搜索 1~4 格
                    local fixed = false
                    for up = 1, 4 do
                        if not ctx.isBodyBlocked(curX, curY - up) then
                            curY = curY - up
                            ctx.setPos(curX, curY)
                            flyY = curY
                            fixed = true
                            break
                        end
                    end
                    if not fixed then
                        -- 无法修正，取消本次位移回到触发前位置无法做到（已移动了），强制停止
                        state = STATE_IDLE
                        targetLight = nil
                        visited = {}
                        crossVisited = {}
                        print("[FlameDash] ABORT: cannot resolve collision!")
                        return "landed"
                    end
                end

                -- 检查是否已经站在地面上
                if ctx.onGround(curX, curY) then
                    state = STATE_IDLE
                    targetLight = nil
                    visited = {}
                    crossVisited = {}
                    if ctx.onLand then ctx.onLand() end
                    print("[FlameDash] Chain ended, already on ground!")
                    return "landed"
                else
                    state = STATE_FALLING
                    flyX = curX
                    flyY = curY
                    print("[FlameDash] Chain ended, falling to ground")
                end
            end
        end

    elseif state == STATE_FALLING then
        -- 向下扫描式下落：逐格检测，找到 onGround 的安全位置
        local moveStep = M.FALL_SPEED * dt
        flyY = flyY + moveStep
        local newY = math.floor(flyY + 0.5)
        local curX = ctx.gridX
        local startY = ctx.gridY
        local blockedThisFrame = false  -- 标记是否在本帧已修正位置

        -- 逐格检测从当前位置到目标位置
        for testY = startY, newY do
            if testY > ctx.mapRows then
                state = STATE_IDLE
                targetLight = nil
                visited = {}
                crossVisited = {}
                if ctx.onBoundary then ctx.onBoundary() end
                return "boundary"
            end

            if ctx.onGround(curX, testY) then
                -- 找到地面支撑，确认身体不嵌入
                local landY = testY
                if ctx.isBodyBlocked and ctx.isBodyBlocked(curX, landY) then
                    -- 嵌入了，向上微调
                    for up = 1, 4 do
                        if not ctx.isBodyBlocked(curX, landY - up) then
                            landY = landY - up
                            break
                        end
                    end
                end
                ctx.setPos(curX, landY)
                flyY = landY
                state = STATE_IDLE
                targetLight = nil
                visited = {}
                crossVisited = {}
                if ctx.onLand then ctx.onLand() end
                print("[FlameDash] Landed at Y=" .. landY)
                return "landed"
            end

            -- 如果身体碰到实体但不是 onGround 情况（头撞天花板等），停在上一格
            if testY > startY and ctx.isBodyBlocked and ctx.isBodyBlocked(curX, testY) then
                local landY = testY - 1
                ctx.setPos(curX, landY)
                flyY = landY
                blockedThisFrame = true
                -- 不算正式落地，继续下一帧尝试
                break
            end
        end

        -- 未找到地面且未被阻挡修正，正常更新位置
        if state == STATE_FALLING and not blockedThisFrame then
            ctx.setPos(curX, newY)
        end
    end

    return nil
end

--- 重置状态
function M.Reset()
    state = STATE_IDLE
    visited = {}
    crossVisited = {}
    crossLevelPending = false
    crossCount = 0
    lastCrossDir = nil
    targetLight = nil
    targetAnchorX = 0
    targetAnchorY = 0
    arriveTimer = 0
    flyX = 0
    flyY = 0
end

return M
