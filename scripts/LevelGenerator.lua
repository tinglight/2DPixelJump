-- ====================================================================
-- LevelGenerator.lua - 基于火焰资源曲线的随机关卡生成器 v2
-- ====================================================================
--
-- 设计核心：
-- 1. 每条主路线维护 fire/jump/fallCount 资源曲线
-- 2. 每个关卡至少一次"下落→高跳通过障碍"的核心机制验证
-- 3. 回复点按资源需求放置，回复后重新校验跳跃高度
-- 4. 终点前必须有明确的机制收束
-- 5. 主路线模拟校验确保可通关
--
-- ====================================================================

local LevelGenerator = {}

-- ====================================================================
-- 常量
-- ====================================================================
local TILE = {
    EMPTY       = 0,
    SOLID       = 1,
    SPAWN       = 2,
    FUEL        = 3,
    GOAL        = 4,
    SPIKE       = 5,
    SWITCH      = 6,
    GATE        = 7,
    HIDDEN_WALL = 8,
}

local BASE_JUMP = 3          -- 满火跳跃高度（格）
local FALL_JUMP_BONUS = 1    -- 每下降1格，跳跃高度+1格
local FALL_FLAME_COST = 10   -- 每下降1格，火焰减少10%
local FUEL_RECOVER = 40      -- 每个燃料恢复40%火焰

local MAP_COLS = 60
local MAP_ROWS = 17

-- 难度配置
local DIFFICULTY = {
    easy = {
        segCount = 4,
        dropMin = 2, dropMax = 3,
        highPlatMax = 5,
        spikeChance = 0.15,
        spikeMax = 3,
        useSwitch = false,
        minEndFlame = 40,
        fuelPlacementThreshold = 50,  -- 火焰低于此值且后续路线长时必须放回复
    },
    normal = {
        segCount = 5,
        dropMin = 3, dropMax = 5,
        highPlatMax = 7,
        spikeChance = 0.25,
        spikeMax = 5,
        useSwitch = true,
        minEndFlame = 25,
        fuelPlacementThreshold = 40,
    },
    hard = {
        segCount = 6,
        dropMin = 4, dropMax = 6,
        highPlatMax = 9,
        spikeChance = 0.35,
        spikeMax = 7,
        useSwitch = true,
        minEndFlame = 10,
        fuelPlacementThreshold = 30,
    },
}

-- ====================================================================
-- 工具函数
-- ====================================================================

local function MakeTileValue(baseType, group)
    if (baseType == TILE.SWITCH or baseType == TILE.GATE or baseType == TILE.HIDDEN_WALL) and group and group > 0 then
        return group * 100 + baseType
    end
    return baseType
end

local function CreateEmptyMap()
    local map = {}
    for row = 1, MAP_ROWS do
        map[row] = {}
        for col = 1, MAP_COLS do
            map[row][col] = TILE.EMPTY
        end
    end
    return map
end

local function FillSolidColumn(map, col, fromRow, toRow)
    if col < 1 or col > MAP_COLS then return end
    for row = math.max(1, fromRow), math.min(MAP_ROWS, toRow) do
        map[row][col] = TILE.SOLID
    end
end

local function FillGround(map, col, groundRow)
    FillSolidColumn(map, col, groundRow, MAP_ROWS)
end

local function FillPlatform(map, row, colStart, colEnd)
    if row < 1 or row > MAP_ROWS then return end
    for col = math.max(1, colStart), math.min(MAP_COLS, colEnd) do
        map[row][col] = TILE.SOLID
    end
end

local function ClearArea(map, rowStart, rowEnd, colStart, colEnd)
    for row = math.max(1, rowStart), math.min(MAP_ROWS, rowEnd) do
        for col = math.max(1, colStart), math.min(MAP_COLS, colEnd) do
            map[row][col] = TILE.EMPTY
        end
    end
end

--- 计算当前跳跃高度
local function CalcJump(fallCount)
    return BASE_JUMP + fallCount * FALL_JUMP_BONUS
end

--- 计算下落后火焰
local function CalcFlameAfterDrop(currentFlame, dropGrids)
    return math.max(0, currentFlame - dropGrids * FALL_FLAME_COST)
end

--- 从火焰百分比反推 fallCount
local function FallCountFromFlame(flame)
    return math.max(0, math.floor((100 - flame) / FALL_FLAME_COST))
end

--- 从火焰百分比计算跳跃高度
local function CalcJumpFromFlame(flame)
    return BASE_JUMP + FallCountFromFlame(flame)
end

--- 限制在地图范围
local function ClampRow(row)
    return math.max(1, math.min(MAP_ROWS, row))
end

local function ClampCol(col)
    return math.max(1, math.min(MAP_COLS, col))
end

-- ====================================================================
-- 资源状态结构
-- ====================================================================

--- 创建初始资源状态
local function MakeState()
    return {
        flame = 100,
        fallCount = 0,
        jump = BASE_JUMP,
    }
end

--- 应用下落到状态（返回新状态，不修改原状态）
local function ApplyDrop(state, dropGrids)
    local s = { flame = state.flame, fallCount = state.fallCount, jump = state.jump }
    s.flame = math.max(0, s.flame - dropGrids * FALL_FLAME_COST)
    s.fallCount = s.fallCount + dropGrids
    s.jump = CalcJump(s.fallCount)
    return s
end

--- 应用回复到状态
local function ApplyRecover(state, recoverAmount)
    recoverAmount = recoverAmount or FUEL_RECOVER
    local s = { flame = state.flame, fallCount = state.fallCount, jump = state.jump }
    s.flame = math.min(100, s.flame + recoverAmount)
    -- 回复后重新计算 fallCount 和 jump
    s.fallCount = FallCountFromFlame(s.flame)
    s.jump = CalcJump(s.fallCount)
    return s
end

-- ====================================================================
-- 段落生成器
-- ====================================================================

--- 出生段：安全平地，3-5格宽
local function GenerateSpawnSegment(map, colStart, colEnd, groundRow)
    -- 填充地面
    for col = colStart, colEnd do
        FillGround(map, col, groundRow)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd)

    local spawnCol = colStart + 1
    local spawnRow = groundRow - 1

    return {
        type = "spawn",
        spawnCol = spawnCol,
        spawnRow = spawnRow,
        exitCol = colEnd,
        exitRow = groundRow,  -- 出口地面行
    }
end

--- 下落强化段：让玩家下降获得高跳，后接需要高跳的高台
--- 这是核心机制验证的主要载体
local function GenerateDropSegment(map, colStart, colEnd, groundRow, state, cfg)
    local segWidth = colEnd - colStart + 1

    -- 决定下落深度（确保火焰不归零）
    local maxDrop = math.min(cfg.dropMax, math.floor((state.flame - 20) / FALL_FLAME_COST))
    maxDrop = math.max(cfg.dropMin, maxDrop)
    local dropDepth = math.random(cfg.dropMin, maxDrop)

    -- 确保下落后不出地图
    local dropBottom = groundRow + dropDepth
    if dropBottom > MAP_ROWS - 1 then
        dropDepth = MAP_ROWS - 1 - groundRow
        dropBottom = groundRow + dropDepth
    end
    if dropDepth < 2 then
        dropDepth = 2
        dropBottom = groundRow + dropDepth
    end

    -- 计算下落后的资源状态
    local afterState = ApplyDrop(state, dropDepth)

    -- 高台高度：必须 > BASE_JUMP（满火跳不上）且 <= afterState.jump（下落后能跳上）
    local minPlatH = BASE_JUMP + 1
    local maxPlatH = math.min(afterState.jump, cfg.highPlatMax)
    if maxPlatH < minPlatH then maxPlatH = minPlatH end
    local highPlatHeight = math.random(minPlatH, maxPlatH)

    -- 布局分配
    local entryW = math.max(2, math.floor(segWidth * 0.15))
    local dropZoneW = math.max(3, math.floor(segWidth * 0.25))
    local landingW = math.max(3, math.floor(segWidth * 0.25))
    local highPlatW = math.max(3, segWidth - entryW - dropZoneW - landingW)

    -- 1. 入口平台（与前段同高）
    local entryEnd = colStart + entryW - 1
    for col = colStart, entryEnd do
        FillGround(map, col, groundRow)
    end
    ClearArea(map, 1, groundRow - 1, colStart, entryEnd)

    -- 2. 下落区（空洞，底部有落点）
    local dropStart = entryEnd + 1
    local dropEnd = dropStart + dropZoneW - 1
    for col = dropStart, dropEnd do
        FillGround(map, col, dropBottom)
    end
    ClearArea(map, 1, dropBottom - 1, dropStart, dropEnd)

    -- 3. 着陆/助跑区（底部）
    local landStart = dropEnd + 1
    local landEnd = landStart + landingW - 1
    landEnd = math.min(landEnd, colEnd - highPlatW)
    for col = landStart, landEnd do
        FillGround(map, col, dropBottom)
    end
    ClearArea(map, 1, dropBottom - 1, landStart, landEnd)

    -- 4. 高台（需要强化跳跃才能上去）
    local highPlatRow = dropBottom - highPlatHeight
    highPlatRow = math.max(2, highPlatRow)
    local highStart = landEnd + 1
    local highEnd = math.min(highStart + highPlatW - 1, colEnd)
    for col = highStart, highEnd do
        FillGround(map, col, highPlatRow)
    end
    ClearArea(map, 1, highPlatRow - 1, highStart, highEnd)

    return {
        type = "drop",
        dropDepth = dropDepth,
        dropBottom = dropBottom,
        highPlatRow = highPlatRow,
        highPlatHeight = highPlatHeight,
        exitCol = highEnd,
        exitRow = highPlatRow,
        afterState = afterState,
    }
end

--- 必要回复段：当火焰过低且后续路线还长时，放置必经回复点
--- 回复后重新校验：后续平台高度适配回复后的跳跃高度
local function GenerateMandatoryRecoverSegment(map, colStart, colEnd, groundRow, state)
    local segWidth = colEnd - colStart + 1

    -- 平坦地面
    for col = colStart, colEnd do
        FillGround(map, col, groundRow)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd)

    -- 回复点放在主路正中，容易看到，无需高难操作
    local fuelCol = ClampCol(colStart + math.floor(segWidth * 0.4))
    local fuelRow = groundRow - 1
    if fuelRow >= 1 then
        map[fuelRow][fuelCol] = TILE.FUEL
    end

    -- 计算回复后状态
    local afterState = ApplyRecover(state)

    return {
        type = "recover_mandatory",
        fuelCol = fuelCol,
        fuelRow = fuelRow,
        exitCol = colEnd,
        exitRow = groundRow,
        afterState = afterState,
    }
end

--- 选择回复段：玩家可选择吃或不吃回复
--- 路线A（吃）：火焰高、跳跃低 → 走低路安全通过
--- 路线B（不吃）：火焰低、跳跃高 → 走高路快速通过
--- 两条路线都必须可通关
local function GenerateChoiceRecoverSegment(map, colStart, colEnd, groundRow, state, cfg)
    local segWidth = colEnd - colStart + 1

    -- 地面
    for col = colStart, colEnd do
        FillGround(map, col, groundRow)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd)

    -- 回复点（主路可达，但不是必须踩上去）
    local fuelCol = ClampCol(colStart + 2)
    local fuelRow = groundRow - 1
    if fuelRow >= 1 then
        map[fuelRow][fuelCol] = TILE.FUEL
    end

    -- 分叉点
    local splitCol = colStart + math.max(4, math.floor(segWidth * 0.3))

    -- 路线B: 高台快速路线（需要保持高跳）
    -- 高度：BASE_JUMP跳不上，但当前state.jump能跳上
    local routeBHeight = math.min(state.jump - 1, cfg.highPlatMax - 1)
    routeBHeight = math.max(BASE_JUMP + 1, routeBHeight)
    local routeBRow = groundRow - routeBHeight
    routeBRow = math.max(2, routeBRow)

    local routeBStart = ClampCol(splitCol + 1)
    local routeBEnd = ClampCol(math.min(routeBStart + 4, colEnd - 1))
    if routeBEnd > routeBStart then
        FillPlatform(map, routeBRow, routeBStart, routeBEnd)
        ClearArea(map, 1, routeBRow - 1, routeBStart, routeBEnd)
    end

    -- 路线A: 主路地面继续（吃回复后跳跃降低也能走）
    -- 路线A可能有少量刺增加代价，但主路安全
    -- 不在这里放刺，由 PlaceSpikes 统一处理

    -- 两种状态
    local stateA = ApplyRecover(state)   -- 吃回复
    local stateB = { flame = state.flame, fallCount = state.fallCount, jump = state.jump }  -- 不吃

    return {
        type = "recover_choice",
        fuelCol = fuelCol,
        fuelRow = fuelRow,
        routeBRow = routeBRow,
        routeBStart = routeBStart,
        routeBEnd = routeBEnd,
        exitCol = colEnd,
        exitRow = groundRow,
        afterState = stateA,    -- 默认假设走安全路线A
        altState = stateB,      -- 备选：不吃回复
    }
end

--- 机关门段：门挡主路→开关在高处→需下落强化高跳触发→门开通过
local function GeneratePuzzleSegment(map, colStart, colEnd, groundRow, state, cfg)
    local segWidth = colEnd - colStart + 1
    local group = math.random(1, 4)

    -- 布局: [入口] [下落坑] [着陆+起跳] [开关高台] [返回通道] [门]
    local entryW = math.max(2, math.floor(segWidth * 0.1))
    local dropW = math.max(3, math.floor(segWidth * 0.15))
    local landW = math.max(3, math.floor(segWidth * 0.15))
    local switchW = math.max(3, math.floor(segWidth * 0.2))
    local returnW = math.max(2, math.floor(segWidth * 0.15))
    local gateW = 1
    local afterW = segWidth - entryW - dropW - landW - switchW - returnW - gateW
    afterW = math.max(2, afterW)

    -- 基础地面
    for col = colStart, colEnd do
        FillGround(map, col, groundRow)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd)

    -- 1. 入口
    local entryEnd = colStart + entryW - 1

    -- 2. 内部下落坑（获得高跳来触发开关）
    local internalDrop = math.random(2, math.min(4, cfg.dropMax - 1))
    -- 确保下落后火焰不归零
    local flameAfterDrop = CalcFlameAfterDrop(state.flame, internalDrop)
    if flameAfterDrop <= 10 then
        internalDrop = math.max(2, math.floor((state.flame - 20) / FALL_FLAME_COST))
        flameAfterDrop = CalcFlameAfterDrop(state.flame, internalDrop)
    end

    local dropBottom = groundRow + internalDrop
    if dropBottom > MAP_ROWS - 1 then
        internalDrop = MAP_ROWS - 1 - groundRow
        dropBottom = groundRow + internalDrop
    end

    local dropStart = entryEnd + 1
    local dropEnd = dropStart + dropW - 1
    for col = dropStart, dropEnd do
        ClearArea(map, groundRow, dropBottom - 1, col, col)
        FillGround(map, col, dropBottom)
    end

    -- 3. 着陆/助跑区
    local landStart = dropEnd + 1
    local landEnd = landStart + landW - 1
    for col = landStart, landEnd do
        ClearArea(map, groundRow, dropBottom - 1, col, col)
        FillGround(map, col, dropBottom)
    end

    -- 4. 开关高台
    local enhancedJump = CalcJump(state.fallCount + internalDrop)
    local switchHeight = math.random(BASE_JUMP + 1, math.min(enhancedJump, cfg.highPlatMax))
    local switchPlatRow = dropBottom - switchHeight
    switchPlatRow = math.max(2, switchPlatRow)

    local switchStart = landEnd + 1
    local switchEnd = switchStart + switchW - 1
    switchEnd = math.min(switchEnd, colEnd - returnW - gateW - afterW)
    FillPlatform(map, switchPlatRow, switchStart, switchEnd)
    ClearArea(map, 1, switchPlatRow - 1, switchStart, switchEnd)

    -- 开关放在平台上
    local switchCol = math.floor((switchStart + switchEnd) / 2)
    local switchTileRow = switchPlatRow - 1
    if switchTileRow >= 1 then
        map[switchTileRow][switchCol] = MakeTileValue(TILE.SWITCH, group)
    end

    -- 5. 返回通道（从开关平台跳回主路高度）
    local returnStart = switchEnd + 1
    local returnEnd = returnStart + returnW - 1
    -- 返回通道地面与主路同高
    for col = returnStart, returnEnd do
        FillGround(map, col, groundRow)
    end
    ClearArea(map, 1, groundRow - 1, returnStart, returnEnd)

    -- 6. 门（阻挡主路，2格高）
    local gateCol = returnEnd + 1
    gateCol = ClampCol(gateCol)
    if gateCol <= colEnd then
        map[groundRow - 1][gateCol] = MakeTileValue(TILE.GATE, group)
        if groundRow - 2 >= 1 then
            map[groundRow - 2][gateCol] = MakeTileValue(TILE.GATE, group)
        end
    end

    -- 7. 门后区域
    local afterStart = gateCol + 1
    for col = afterStart, colEnd do
        FillGround(map, col, groundRow)
    end
    ClearArea(map, 1, groundRow - 1, afterStart, colEnd)

    -- 计算资源：玩家需要下落internalDrop格
    local afterState = ApplyDrop(state, internalDrop)

    return {
        type = "puzzle",
        internalDrop = internalDrop,
        dropBottom = dropBottom,
        switchPlatRow = switchPlatRow,
        switchHeight = switchHeight,
        switchCol = switchCol,
        gateCol = gateCol,
        group = group,
        exitCol = colEnd,
        exitRow = groundRow,
        afterState = afterState,
    }
end

--- 终点收束段（三种结构）
--- A: 高跳收束 - 下落→高台→终点门
--- B: 开关门收束 - 门挡路→下落→高台开关→门开→终点
--- C: 回复选择收束 - 回复点→低路/高路→终点
local function GenerateGoalSegment(map, colStart, colEnd, groundRow, state, cfg, goalStructure)
    local segWidth = colEnd - colStart + 1
    goalStructure = goalStructure or "A"

    -- 基础地面
    for col = colStart, colEnd do
        FillGround(map, col, groundRow)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd)

    if goalStructure == "A" and segWidth >= 10 and state.flame > 30 then
        -- 结构A：高跳收束
        -- 小下落(2-3格) → 着陆区 → 高台 → 终点门
        local dropDepth = math.min(3, math.floor((state.flame - 20) / FALL_FLAME_COST))
        dropDepth = math.max(2, dropDepth)
        local dropBottom = groundRow + dropDepth
        if dropBottom > MAP_ROWS - 1 then
            dropDepth = MAP_ROWS - 1 - groundRow
            dropBottom = groundRow + dropDepth
        end

        local afterDrop = ApplyDrop(state, dropDepth)
        -- 高台：满火跳不上，但下落后能跳上
        local platHeight = math.random(BASE_JUMP + 1, math.min(afterDrop.jump, cfg.highPlatMax))
        local platRow = dropBottom - platHeight
        platRow = math.max(2, platRow)

        -- 布局
        local dropStart = colStart + 2
        local dropEnd = math.min(dropStart + 3, colEnd - 7)
        if dropEnd <= dropStart then dropEnd = dropStart + 2 end

        local landStart = dropEnd + 1
        local landEnd = math.min(landStart + 2, colEnd - 4)

        local platStart = landEnd + 1
        local platEnd = math.min(platStart + 3, colEnd)

        -- 下落区
        for col = dropStart, dropEnd do
            ClearArea(map, groundRow, dropBottom - 1, col, col)
            FillGround(map, col, dropBottom)
        end
        -- 着陆区
        for col = landStart, landEnd do
            ClearArea(map, groundRow, dropBottom - 1, col, col)
            FillGround(map, col, dropBottom)
        end
        -- 高台
        for col = platStart, platEnd do
            FillGround(map, col, platRow)
        end
        ClearArea(map, 1, platRow - 1, platStart, platEnd)

        -- 终点门在高台上
        local goalCol = ClampCol(math.floor((platStart + platEnd) / 2))
        local goalRow = platRow - 1
        if goalRow >= 1 then
            map[goalRow][goalCol] = TILE.GOAL
        end

        return {
            type = "goal",
            structure = "A",
            goalCol = goalCol,
            goalRow = goalRow,
            dropDepth = dropDepth,
            exitCol = colEnd,
            exitRow = platRow,
            afterState = afterDrop,
        }

    elseif goalStructure == "B" and segWidth >= 14 and cfg.useSwitch and state.flame > 40 then
        -- 结构B：开关门收束
        local group = math.random(1, 4)

        -- [入口] [下落坑] [着陆] [开关高台] [返回] [门] [终点]
        local internalDrop = math.random(2, 3)
        local dropBottom = groundRow + internalDrop
        if dropBottom > MAP_ROWS - 1 then
            internalDrop = MAP_ROWS - 1 - groundRow
            dropBottom = groundRow + internalDrop
        end

        local afterDrop = ApplyDrop(state, internalDrop)
        local switchHeight = math.random(BASE_JUMP + 1, math.min(afterDrop.jump, cfg.highPlatMax))
        local switchPlatRow = dropBottom - switchHeight
        switchPlatRow = math.max(2, switchPlatRow)

        -- 分区
        local dropStart = colStart + 2
        local dropEnd = math.min(dropStart + 2, colEnd - 11)
        local landStart = dropEnd + 1
        local landEnd = math.min(landStart + 2, colEnd - 8)
        local swStart = landEnd + 1
        local swEnd = math.min(swStart + 2, colEnd - 5)
        local retStart = swEnd + 1
        local retEnd = math.min(retStart + 1, colEnd - 3)
        local gateCol = ClampCol(retEnd + 1)
        local goalCol = ClampCol(gateCol + 2)

        -- 下落区
        for col = dropStart, dropEnd do
            ClearArea(map, groundRow, dropBottom - 1, col, col)
            FillGround(map, col, dropBottom)
        end
        -- 着陆
        for col = landStart, landEnd do
            ClearArea(map, groundRow, dropBottom - 1, col, col)
            FillGround(map, col, dropBottom)
        end
        -- 开关高台
        FillPlatform(map, switchPlatRow, swStart, swEnd)
        ClearArea(map, 1, switchPlatRow - 1, swStart, swEnd)
        local switchCol = math.floor((swStart + swEnd) / 2)
        if switchPlatRow - 1 >= 1 then
            map[switchPlatRow - 1][switchCol] = MakeTileValue(TILE.SWITCH, group)
        end
        -- 返回通道
        for col = retStart, retEnd do
            FillGround(map, col, groundRow)
        end
        ClearArea(map, 1, groundRow - 1, retStart, retEnd)
        -- 门
        if gateCol >= 1 and gateCol <= MAP_COLS then
            map[groundRow - 1][gateCol] = MakeTileValue(TILE.GATE, group)
            if groundRow - 2 >= 1 then
                map[groundRow - 2][gateCol] = MakeTileValue(TILE.GATE, group)
            end
        end
        -- 终点
        local goalRow = groundRow - 1
        if goalCol >= 1 and goalCol <= MAP_COLS and goalRow >= 1 then
            map[goalRow][goalCol] = TILE.GOAL
        end

        return {
            type = "goal",
            structure = "B",
            goalCol = goalCol,
            goalRow = goalRow,
            internalDrop = internalDrop,
            switchCol = switchCol,
            gateCol = gateCol,
            group = group,
            exitCol = colEnd,
            exitRow = groundRow,
            afterState = afterDrop,
        }
    end

    -- 结构C / 回退：简单高台终点
    -- 确保至少有一个小台阶验证（而非直接走到终点）
    local stepHeight = math.min(state.jump - 1, 3)
    stepHeight = math.max(2, stepHeight)
    local stepRow = groundRow - stepHeight
    stepRow = math.max(2, stepRow)

    local stepStart = ClampCol(colEnd - 4)
    local stepEnd = colEnd
    for col = stepStart, stepEnd do
        FillGround(map, col, stepRow)
    end
    ClearArea(map, 1, stepRow - 1, stepStart, stepEnd)

    local goalCol = ClampCol(stepEnd - 1)
    local goalRow = stepRow - 1
    if goalRow >= 1 then
        map[goalRow][goalCol] = TILE.GOAL
    end

    return {
        type = "goal",
        structure = "C",
        goalCol = goalCol,
        goalRow = goalRow,
        exitCol = colEnd,
        exitRow = stepRow,
        afterState = state,
    }
end

--- 普通连接段：平坦移动或小台阶，不消耗/恢复资源
local function GenerateConnectorSegment(map, colStart, colEnd, groundRow, state)
    local segWidth = colEnd - colStart + 1

    -- 微小高度变化（不超过当前跳跃的一半，确保安全）
    local maxStep = math.min(2, state.jump - 1)
    local heightChange = math.random(0, maxStep)
    local dir = math.random() > 0.5 and -1 or 1
    local newGround = groundRow + dir * heightChange
    newGround = math.max(4, math.min(MAP_ROWS - 2, newGround))

    -- 如果需要往上跳且超出能力，回退
    if groundRow - newGround > state.jump then
        newGround = groundRow
    end

    -- 渐变台阶
    local steps = math.abs(newGround - groundRow)
    local stepDir = newGround < groundRow and -1 or 1
    local stepW = math.max(1, math.floor(segWidth / (steps + 1)))

    local curGround = groundRow
    for col = colStart, colEnd do
        local localIdx = col - colStart
        if steps > 0 and localIdx > 0 and localIdx % stepW == 0 and math.abs(curGround - newGround) > 0 then
            curGround = curGround + stepDir
        end
        FillGround(map, col, curGround)
        ClearArea(map, 1, curGround - 1, col, col)
    end

    return {
        type = "connector",
        exitCol = colEnd,
        exitRow = newGround,
        afterState = state,  -- 资源不变
    }
end

-- ====================================================================
-- 刺陷阱放置（安全规则）
-- ====================================================================

local function PlaceSpikes(map, segments, cfg, spawnCol, spawnRow, goalCol, goalRow)
    local placed = 0
    local maxSpikes = cfg.spikeMax

    for _, seg in ipairs(segments) do
        if placed >= maxSpikes then break end
        -- 出生段和终点段不放刺
        if seg.type == "spawn" or seg.type == "goal" then goto continue end

        if math.random() > cfg.spikeChance then goto continue end

        -- 找合适位置
        local exitCol = seg.exitCol or 10
        local exitRow = seg.exitRow or MAP_ROWS - 2

        -- 在段的中后部找位置
        local candidates = {}
        local searchStart = math.max(1, exitCol - 8)
        local searchEnd = math.max(searchStart, exitCol - 2)
        for col = searchStart, searchEnd do
            local row = exitRow - 1
            if col >= 1 and col <= MAP_COLS and row >= 1 and row <= MAP_ROWS then
                -- 必须是空格，下面有实体
                if map[row][col] == TILE.EMPTY and row + 1 <= MAP_ROWS and map[row + 1][col] == TILE.SOLID then
                    -- 不能在出生点附近（5格内）
                    local distSpawn = math.abs(col - spawnCol) + math.abs(row - spawnRow)
                    if distSpawn < 5 then goto skipCandidate end
                    -- 不能在终点附近（3格内）
                    if goalCol then
                        local distGoal = math.abs(col - goalCol) + math.abs(row - goalRow)
                        if distGoal < 3 then goto skipCandidate end
                    end
                    -- 两侧至少有一边可通行
                    local leftOk = col > 1 and map[row][col - 1] == TILE.EMPTY
                    local rightOk = col < MAP_COLS and map[row][col + 1] == TILE.EMPTY
                    if leftOk or rightOk then
                        table.insert(candidates, { col = col, row = row })
                    end
                end
            end
            ::skipCandidate::
        end

        if #candidates > 0 then
            local pick = candidates[math.random(1, #candidates)]
            map[pick.row][pick.col] = TILE.SPIKE
            placed = placed + 1
        end

        ::continue::
    end
end

-- ====================================================================
-- 关卡结构模板
-- ====================================================================

-- 模板定义了段落类型序列
-- 每个模板必须包含至少一个 "drop" 段（核心机制验证）
local TEMPLATES = {
    -- 基础教学型：下落→高台→终点
    {
        name = "下落教学",
        segments = { "spawn", "connector", "drop", "goal_A" },
        minDiff = "easy",
    },
    -- 回复选择型：下落→选择回复→终点
    {
        name = "回复抉择",
        segments = { "spawn", "drop", "recover_choice", "goal_A" },
        minDiff = "easy",
    },
    -- 机关门型：主路机关→终点
    {
        name = "机关挑战",
        segments = { "spawn", "connector", "puzzle", "goal_C" },
        minDiff = "normal",
    },
    -- 开关门终点型：先下落强化，再开关门收束
    {
        name = "机关收束",
        segments = { "spawn", "drop", "connector", "goal_B" },
        minDiff = "normal",
    },
    -- 完整体验型：下落→回复→机关→终点
    {
        name = "完整体验",
        segments = { "spawn", "drop", "recover_mandatory", "puzzle", "goal_A" },
        minDiff = "hard",
    },
    -- 双重挑战型：下落→高台→下落→终点
    {
        name = "双重强化",
        segments = { "spawn", "drop", "connector", "drop", "goal_A" },
        minDiff = "hard",
    },
}

-- 按难度可用模板
local TEMPLATES_BY_DIFF = {
    easy   = { 1, 2 },
    normal = { 1, 2, 3, 4 },
    hard   = { 3, 4, 5, 6 },
}

-- ====================================================================
-- 主路线模拟校验器
-- ====================================================================

--- 模拟主路线通关过程，验证资源管理合法性
--- @return boolean ok
--- @return string|nil errorMsg
local function SimulateRoute(segments, cfg)
    local state = MakeState()

    for i, seg in ipairs(segments) do
        -- 每段前检查火焰
        if state.flame <= 0 then
            return false, string.format("段%d(%s)前火焰已耗尽", i, seg.type)
        end

        if seg.type == "drop" then
            local drop = seg.dropDepth or 0
            state = ApplyDrop(state, drop)
            if state.flame <= 0 then
                return false, string.format("段%d(drop)导致火焰耗尽", i)
            end
            -- 验证高台可达
            if seg.highPlatHeight and state.jump < seg.highPlatHeight then
                return false, string.format("段%d(drop)高台不可达: 需%d格, 有%d格跳跃",
                    i, seg.highPlatHeight, state.jump)
            end

        elseif seg.type == "recover_mandatory" then
            state = ApplyRecover(state)

        elseif seg.type == "recover_choice" then
            -- 假设走安全路线A（吃回复）
            state = ApplyRecover(state)

        elseif seg.type == "puzzle" then
            local drop = seg.internalDrop or 0
            local stateAfterDrop = ApplyDrop(state, drop)
            if stateAfterDrop.flame <= 0 then
                return false, string.format("段%d(puzzle)下落导致火焰耗尽", i)
            end
            -- 验证开关可达
            if seg.switchHeight and stateAfterDrop.jump < seg.switchHeight then
                return false, string.format("段%d(puzzle)开关不可达: 需%d, 有%d",
                    i, seg.switchHeight, stateAfterDrop.jump)
            end
            state = stateAfterDrop

        elseif seg.type == "goal" then
            if seg.dropDepth then
                local afterGoalDrop = ApplyDrop(state, seg.dropDepth)
                if afterGoalDrop.flame <= 0 then
                    return false, "终点收束下落导致火焰耗尽"
                end
                state = afterGoalDrop
            end
            if seg.internalDrop then
                local afterGoalDrop = ApplyDrop(state, seg.internalDrop)
                if afterGoalDrop.flame <= 0 then
                    return false, "终点(B)下落导致火焰耗尽"
                end
                if seg.switchHeight and afterGoalDrop.jump < seg.switchHeight then
                    return false, string.format("终点(B)开关不可达: 需%d, 有%d",
                        seg.switchHeight, afterGoalDrop.jump)
                end
                state = afterGoalDrop
            end
        end
        -- connector 不改变资源
    end

    -- 终点火焰余量检查
    if state.flame < cfg.minEndFlame then
        return false, string.format("终点火焰不足: %.0f%% < %d%%", state.flame, cfg.minEndFlame)
    end

    return true, nil
end

--- 验证关卡是否有核心机制验证
local function HasCoreMechanicValidation(segments)
    for _, seg in ipairs(segments) do
        if seg.type == "drop" or seg.type == "puzzle" then
            return true
        end
        -- goal结构A/B也包含下落强化
        if seg.type == "goal" and (seg.structure == "A" or seg.structure == "B") then
            if seg.dropDepth and seg.dropDepth >= 2 then return true end
            if seg.internalDrop and seg.internalDrop >= 2 then return true end
        end
    end
    return false
end

-- ====================================================================
-- 主生成函数
-- ====================================================================

function LevelGenerator.Generate(difficulty)
    difficulty = difficulty or "normal"
    local cfg = DIFFICULTY[difficulty]
    if not cfg then
        difficulty = "normal"
        cfg = DIFFICULTY[difficulty]
    end

    -- 选择模板
    local availableTemplates = TEMPLATES_BY_DIFF[difficulty]
    local tidx = availableTemplates[math.random(1, #availableTemplates)]
    local tmpl = TEMPLATES[tidx]
    local segDefs = tmpl.segments

    -- 分配每段宽度
    local segCount = #segDefs
    local usableCols = MAP_COLS - 2  -- 左右各留1格边界
    local baseSegWidth = math.floor(usableCols / segCount)
    local extraCols = usableCols - baseSegWidth * segCount

    -- 初始化
    local map = CreateEmptyMap()
    local baseGround = MAP_ROWS - 2  -- 默认地面在倒数第3行
    local state = MakeState()
    local segments = {}

    local currentCol = 2
    local currentGround = baseGround
    local spawnCol, spawnRow
    local goalCol, goalRow

    for i, segDef in ipairs(segDefs) do
        local segStart = currentCol
        local segW = baseSegWidth + (i <= extraCols and 1 or 0)
        local segEnd = math.min(segStart + segW - 1, MAP_COLS - 1)
        if i == segCount then segEnd = MAP_COLS - 1 end

        -- 决定是否需要强制回复（火焰低且后面还长）
        local remainingSegs = segCount - i
        if state.flame < cfg.fuelPlacementThreshold and remainingSegs >= 2
            and segDef ~= "recover_mandatory" and segDef ~= "recover_choice"
            and segDef ~= "goal_A" and segDef ~= "goal_B" and segDef ~= "goal_C"
            and segDef ~= "spawn" then
            -- 替换当前段为必要回复段
            segDef = "recover_mandatory"
        end

        local seg

        if segDef == "spawn" then
            seg = GenerateSpawnSegment(map, segStart, segEnd, currentGround)
            spawnCol = seg.spawnCol
            spawnRow = seg.spawnRow

        elseif segDef == "connector" then
            seg = GenerateConnectorSegment(map, segStart, segEnd, currentGround, state)

        elseif segDef == "drop" then
            seg = GenerateDropSegment(map, segStart, segEnd, currentGround, state, cfg)

        elseif segDef == "recover_mandatory" then
            seg = GenerateMandatoryRecoverSegment(map, segStart, segEnd, currentGround, state)

        elseif segDef == "recover_choice" then
            seg = GenerateChoiceRecoverSegment(map, segStart, segEnd, currentGround, state, cfg)

        elseif segDef == "puzzle" then
            if not cfg.useSwitch then
                -- 难度不支持开关，降级为下落段
                seg = GenerateDropSegment(map, segStart, segEnd, currentGround, state, cfg)
            else
                seg = GeneratePuzzleSegment(map, segStart, segEnd, currentGround, state, cfg)
            end

        elseif segDef == "goal_A" then
            seg = GenerateGoalSegment(map, segStart, segEnd, currentGround, state, cfg, "A")

        elseif segDef == "goal_B" then
            seg = GenerateGoalSegment(map, segStart, segEnd, currentGround, state, cfg, "B")

        elseif segDef == "goal_C" then
            seg = GenerateGoalSegment(map, segStart, segEnd, currentGround, state, cfg, "C")
        end

        if seg then
            table.insert(segments, seg)
            -- 更新状态
            if seg.afterState then
                state = seg.afterState
            end
            -- 更新位置
            if seg.exitRow then currentGround = seg.exitRow end
            currentCol = (seg.exitCol or segEnd) + 1

            -- 记录终点
            if seg.type == "goal" then
                goalCol = seg.goalCol
                goalRow = seg.goalRow
            end
        else
            -- 段生成失败，填充平地
            for col = segStart, segEnd do
                FillGround(map, col, currentGround)
            end
            ClearArea(map, 1, currentGround - 1, segStart, segEnd)
            currentCol = segEnd + 1
        end
    end

    -- 放置刺陷阱
    PlaceSpikes(map, segments, cfg, spawnCol or 3, spawnRow or baseGround - 1, goalCol, goalRow)

    -- 确保出生点标记和脚下实体
    if spawnRow and spawnCol then
        if spawnRow >= 1 and spawnRow <= MAP_ROWS and spawnCol >= 1 and spawnCol <= MAP_COLS then
            map[spawnRow][spawnCol] = TILE.SPAWN
            if spawnRow + 1 <= MAP_ROWS then
                map[spawnRow + 1][spawnCol] = TILE.SOLID
            end
        end
    end

    -- 确保终点门和脚下实体
    if goalRow and goalCol then
        if goalRow >= 1 and goalRow <= MAP_ROWS and goalCol >= 1 and goalCol <= MAP_COLS then
            if map[goalRow][goalCol] ~= TILE.GOAL then
                map[goalRow][goalCol] = TILE.GOAL
            end
            if goalRow + 1 <= MAP_ROWS then
                map[goalRow + 1][goalCol] = TILE.SOLID
            end
        end
    end

    return map, spawnCol or 3, spawnRow or (baseGround - 1), tmpl.name, difficulty, segments
end

--- 带校验的生成（失败重试）
function LevelGenerator.GenerateValid(difficulty, maxRetries)
    maxRetries = maxRetries or 8
    local cfg = DIFFICULTY[difficulty or "normal"]

    for attempt = 1, maxRetries do
        local map, sc, sr, tName, diff, segs = LevelGenerator.Generate(difficulty)
        local valid = true
        local reason = ""

        -- 查找终点
        local gc, gr
        for _, seg in ipairs(segs) do
            if seg.type == "goal" then
                gc = seg.goalCol
                gr = seg.goalRow
                break
            end
        end

        if not gc or not gr then
            valid = false
            reason = "no goal found"
        end

        -- 核心机制验证
        if valid and not HasCoreMechanicValidation(segs) then
            valid = false
            reason = "no core mechanic validation"
        end

        -- 资源模拟
        if valid then
            local ok, errMsg = SimulateRoute(segs, cfg)
            if not ok then
                valid = false
                reason = errMsg
            end
        end

        if valid then
            return map, sc, sr, tName
        else
            print(string.format("[LevelGen] Attempt %d: %s", attempt, reason))
        end
    end

    -- 兜底：用简单的教学模板保证能生成
    print("[LevelGen] All attempts failed, using fallback")
    local map, sc, sr, tName = LevelGenerator.Generate("easy")
    return map, sc, sr, tName
end

-- 导出
LevelGenerator.TILE = TILE
LevelGenerator.MAP_COLS = MAP_COLS
LevelGenerator.MAP_ROWS = MAP_ROWS

return LevelGenerator
