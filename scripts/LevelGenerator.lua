-- ====================================================================
-- LevelGenerator.lua - 基于火焰资源曲线的随机关卡生成器 v2.1
-- ====================================================================
--
-- 设计核心：
-- 1. 每条主路线维护 fire/jump/fallCount 资源曲线
-- 2. 每个关卡至少一次"下落→高跳通过障碍"的核心机制验证
-- 3. 回复点按资源需求放置，回复后重新校验跳跃高度
-- 4. 终点前必须有明确的机制收束
-- 5. 主路线模拟校验确保可通关
-- 6. [v2.1] 关卡生成基于实际画布尺寸，不使用固定地图大小
--
-- ====================================================================

local LevelGenerator = {}

-- ====================================================================
-- 常量
-- ====================================================================
local TILE = {
    EMPTY        = 0,
    SOLID        = 1,
    SPAWN        = 2,
    FUEL         = 3,
    GOAL         = 4,
    SPIKE        = 5,
    SWITCH       = 6,
    GATE         = 7,
    HIDDEN_WALL  = 8,
    CHECKPOINT   = 14,
    SOLID_PILLAR = 13,
    SOLID_SEWER  = 17,
    CURTAIN      = 18,  -- 柳条门帘（不阻挡玩家，略微遮光，触碰晃动）
    SLOPE_TR     = 19,  -- 右上斜坡
    SLOPE_TL     = 20,  -- 左上斜坡
    SLOPE_BR     = 21,  -- 右下斜坡
    SLOPE_BL     = 22,  -- 左下斜坡
    ABILITY_POINT = 23, -- 能力点（每关仅一个，像素化燃烧灯，赋予火球能力）
}

local BASE_JUMP = 3          -- 满火跳跃高度（格）
local FALL_JUMP_BONUS = 1    -- 每下降1格，跳跃高度+1格
local FALL_FLAME_COST = 10   -- 每下降1格，火焰减少10%
local FUEL_RECOVER = 40      -- 每个燃料恢复40%火焰

-- 默认地图尺寸（仅作为兜底值，实际应由调用方传入）
local DEFAULT_COLS = 60
local DEFAULT_ROWS = 17

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
        fuelPlacementThreshold = 50,
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
-- 工具函数（接受 mapCols/mapRows 参数）
-- ====================================================================

local function MakeTileValue(baseType, group)
    if (baseType == TILE.SWITCH or baseType == TILE.GATE or baseType == TILE.HIDDEN_WALL) and group and group > 0 then
        return group * 100 + baseType
    end
    return baseType
end

local function CreateEmptyMap(mapCols, mapRows)
    local map = {}
    for row = 1, mapRows do
        map[row] = {}
        for col = 1, mapCols do
            map[row][col] = TILE.EMPTY
        end
    end
    return map
end

local function FillSolidColumn(map, col, fromRow, toRow, mapCols, mapRows)
    if col < 1 or col > mapCols then return end
    for row = math.max(1, fromRow), math.min(mapRows, toRow) do
        map[row][col] = TILE.SOLID
    end
end

local function FillGround(map, col, groundRow, mapCols, mapRows)
    FillSolidColumn(map, col, groundRow, mapRows, mapCols, mapRows)
end

local function FillPlatform(map, row, colStart, colEnd, mapCols, mapRows)
    if row < 1 or row > mapRows then return end
    for col = math.max(1, colStart), math.min(mapCols, colEnd) do
        map[row][col] = TILE.SOLID
    end
end

local function ClearArea(map, rowStart, rowEnd, colStart, colEnd, mapCols, mapRows)
    for row = math.max(1, rowStart), math.min(mapRows, rowEnd) do
        for col = math.max(1, colStart), math.min(mapCols, colEnd) do
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
local function ClampRow(row, mapRows)
    return math.max(1, math.min(mapRows, row))
end

local function ClampCol(col, mapCols)
    return math.max(1, math.min(mapCols, col))
end

-- ====================================================================
-- 资源状态结构
-- ====================================================================

local function MakeState()
    return {
        flame = 100,
        fallCount = 0,
        jump = BASE_JUMP,
    }
end

local function ApplyDrop(state, dropGrids)
    local s = { flame = state.flame, fallCount = state.fallCount, jump = state.jump }
    s.flame = math.max(0, s.flame - dropGrids * FALL_FLAME_COST)
    s.fallCount = s.fallCount + dropGrids
    s.jump = CalcJump(s.fallCount)
    return s
end

local function ApplyRecover(state, recoverAmount)
    recoverAmount = recoverAmount or FUEL_RECOVER
    local s = { flame = state.flame, fallCount = state.fallCount, jump = state.jump }
    s.flame = math.min(100, s.flame + recoverAmount)
    s.fallCount = FallCountFromFlame(s.flame)
    s.jump = CalcJump(s.fallCount)
    return s
end

-- ====================================================================
-- 画布规模评估（v2.1 新增）
-- ====================================================================

--- 根据画布大小决定关卡规模等级
--- @return string "small"|"medium"|"large"
local function EvaluateCanvasScale(mapCols, mapRows)
    -- 画布较小：宽 < 30 或 高 < 12
    if mapCols < 30 or mapRows < 12 then
        return "small"
    end
    -- 画布中等：宽 30-59 且 高 12-19
    if mapCols < 60 then
        return "medium"
    end
    -- 画布较大：宽 >= 60
    return "large"
end

--- 根据画布规模调整难度配置（返回调整后的 cfg 副本）
local function AdjustCfgForCanvas(cfg, canvasScale, mapCols, mapRows)
    local adjusted = {}
    for k, v in pairs(cfg) do adjusted[k] = v end

    if canvasScale == "small" then
        -- 小画布：减少段落，降低复杂度
        adjusted.segCount = math.min(adjusted.segCount, 3)
        adjusted.dropMax = math.min(adjusted.dropMax, math.max(2, mapRows - 6))
        adjusted.highPlatMax = math.min(adjusted.highPlatMax, mapRows - 4)
        adjusted.spikeMax = math.min(adjusted.spikeMax, 2)
        adjusted.useSwitch = false  -- 小画布不用开关门
    elseif canvasScale == "medium" then
        -- 中等画布：适度控制
        adjusted.segCount = math.min(adjusted.segCount, 5)
        adjusted.dropMax = math.min(adjusted.dropMax, math.max(2, mapRows - 5))
        adjusted.highPlatMax = math.min(adjusted.highPlatMax, mapRows - 3)
    else
        -- 大画布：下落深度不超出纵向空间
        adjusted.dropMax = math.min(adjusted.dropMax, math.max(2, mapRows - 5))
        adjusted.highPlatMax = math.min(adjusted.highPlatMax, mapRows - 3)
    end

    return adjusted
end

local TEMPLATES_BY_DIFF = {
    easy   = { 1, 2 },
    normal = { 1, 2, 3, 4 },
    hard   = { 3, 4, 5, 6 },
}

--- 根据画布规模选择合适的模板子集
local function GetTemplatesForCanvas(canvasScale, difficulty)
    if canvasScale == "small" then
        -- 小画布只用简单模板（无 puzzle、无复杂终点B）
        return { 1, 2 }  -- 下落教学、回复抉择
    end
    return TEMPLATES_BY_DIFF[difficulty]
end

-- ====================================================================
-- 段落生成器（所有函数通过 ctx 传递 mapCols/mapRows）
-- ====================================================================

--- 出生段：安全平地
local function GenerateSpawnSegment(map, colStart, colEnd, groundRow, ctx)
    for col = colStart, colEnd do
        FillGround(map, col, groundRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd, ctx.mapCols, ctx.mapRows)

    local spawnCol = colStart + 1
    local spawnRow = groundRow - 1

    return {
        type = "spawn",
        spawnCol = spawnCol,
        spawnRow = spawnRow,
        exitCol = colEnd,
        exitRow = groundRow,
    }
end

--- 下落强化段
local function GenerateDropSegment(map, colStart, colEnd, groundRow, state, cfg, ctx)
    local segWidth = colEnd - colStart + 1

    local maxDrop = math.min(cfg.dropMax, math.floor((state.flame - 20) / FALL_FLAME_COST))
    maxDrop = math.max(cfg.dropMin, maxDrop)
    local dropDepth = math.random(cfg.dropMin, maxDrop)

    -- 确保下落后不出地图
    local dropBottom = groundRow + dropDepth
    if dropBottom > ctx.mapRows - 1 then
        dropDepth = ctx.mapRows - 1 - groundRow
        dropBottom = groundRow + dropDepth
    end
    if dropDepth < 2 then
        dropDepth = 2
        dropBottom = groundRow + dropDepth
    end

    local afterState = ApplyDrop(state, dropDepth)

    local minPlatH = BASE_JUMP + 1
    local maxPlatH = math.min(afterState.jump, cfg.highPlatMax)
    if maxPlatH < minPlatH then maxPlatH = minPlatH end
    local highPlatHeight = math.random(minPlatH, maxPlatH)

    -- 布局分配
    local entryW = math.max(2, math.floor(segWidth * 0.15))
    local dropZoneW = math.max(3, math.floor(segWidth * 0.25))
    local landingW = math.max(3, math.floor(segWidth * 0.25))
    local highPlatW = math.max(3, segWidth - entryW - dropZoneW - landingW)

    -- 1. 入口平台
    local entryEnd = colStart + entryW - 1
    for col = colStart, entryEnd do
        FillGround(map, col, groundRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, groundRow - 1, colStart, entryEnd, ctx.mapCols, ctx.mapRows)

    -- 2. 下落区
    local dropStart = entryEnd + 1
    local dropEnd = dropStart + dropZoneW - 1
    for col = dropStart, dropEnd do
        FillGround(map, col, dropBottom, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, dropBottom - 1, dropStart, dropEnd, ctx.mapCols, ctx.mapRows)

    -- 3. 着陆/助跑区
    local landStart = dropEnd + 1
    local landEnd = landStart + landingW - 1
    landEnd = math.min(landEnd, colEnd - highPlatW)
    for col = landStart, landEnd do
        FillGround(map, col, dropBottom, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, dropBottom - 1, landStart, landEnd, ctx.mapCols, ctx.mapRows)

    -- 4. 高台
    local highPlatRow = dropBottom - highPlatHeight
    highPlatRow = math.max(2, highPlatRow)
    local highStart = landEnd + 1
    local highEnd = math.min(highStart + highPlatW - 1, colEnd)
    for col = highStart, highEnd do
        FillGround(map, col, highPlatRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, highPlatRow - 1, highStart, highEnd, ctx.mapCols, ctx.mapRows)

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

--- 必要回复段
local function GenerateMandatoryRecoverSegment(map, colStart, colEnd, groundRow, state, ctx)
    local segWidth = colEnd - colStart + 1

    for col = colStart, colEnd do
        FillGround(map, col, groundRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd, ctx.mapCols, ctx.mapRows)

    local fuelCol = ClampCol(colStart + math.floor(segWidth * 0.4), ctx.mapCols)
    local fuelRow = groundRow - 1
    if fuelRow >= 1 then
        map[fuelRow][fuelCol] = TILE.FUEL
    end

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

--- 选择回复段
local function GenerateChoiceRecoverSegment(map, colStart, colEnd, groundRow, state, cfg, ctx)
    local segWidth = colEnd - colStart + 1

    for col = colStart, colEnd do
        FillGround(map, col, groundRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd, ctx.mapCols, ctx.mapRows)

    local fuelCol = ClampCol(colStart + 2, ctx.mapCols)
    local fuelRow = groundRow - 1
    if fuelRow >= 1 then
        map[fuelRow][fuelCol] = TILE.FUEL
    end

    local splitCol = colStart + math.max(4, math.floor(segWidth * 0.3))

    local routeBHeight = math.min(state.jump - 1, cfg.highPlatMax - 1)
    routeBHeight = math.max(BASE_JUMP + 1, routeBHeight)
    local routeBRow = groundRow - routeBHeight
    routeBRow = math.max(2, routeBRow)

    local routeBStart = ClampCol(splitCol + 1, ctx.mapCols)
    local routeBEnd = ClampCol(math.min(routeBStart + 4, colEnd - 1), ctx.mapCols)
    if routeBEnd > routeBStart then
        FillPlatform(map, routeBRow, routeBStart, routeBEnd, ctx.mapCols, ctx.mapRows)
        ClearArea(map, 1, routeBRow - 1, routeBStart, routeBEnd, ctx.mapCols, ctx.mapRows)
    end

    local stateA = ApplyRecover(state)
    local stateB = { flame = state.flame, fallCount = state.fallCount, jump = state.jump }

    return {
        type = "recover_choice",
        fuelCol = fuelCol,
        fuelRow = fuelRow,
        routeBRow = routeBRow,
        routeBStart = routeBStart,
        routeBEnd = routeBEnd,
        exitCol = colEnd,
        exitRow = groundRow,
        afterState = stateA,
        altState = stateB,
    }
end

--- 机关门段
local function GeneratePuzzleSegment(map, colStart, colEnd, groundRow, state, cfg, ctx)
    local segWidth = colEnd - colStart + 1
    local group = math.random(1, 4)

    local entryW = math.max(2, math.floor(segWidth * 0.1))
    local dropW = math.max(3, math.floor(segWidth * 0.15))
    local landW = math.max(3, math.floor(segWidth * 0.15))
    local switchW = math.max(3, math.floor(segWidth * 0.2))
    local returnW = math.max(2, math.floor(segWidth * 0.15))
    local gateW = 1
    local afterW = segWidth - entryW - dropW - landW - switchW - returnW - gateW
    afterW = math.max(2, afterW)

    for col = colStart, colEnd do
        FillGround(map, col, groundRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd, ctx.mapCols, ctx.mapRows)

    local entryEnd = colStart + entryW - 1

    local internalDrop = math.random(2, math.min(4, cfg.dropMax - 1))
    local flameAfterDrop = CalcFlameAfterDrop(state.flame, internalDrop)
    if flameAfterDrop <= 10 then
        internalDrop = math.max(2, math.floor((state.flame - 20) / FALL_FLAME_COST))
        flameAfterDrop = CalcFlameAfterDrop(state.flame, internalDrop)
    end

    local dropBottom = groundRow + internalDrop
    if dropBottom > ctx.mapRows - 1 then
        internalDrop = ctx.mapRows - 1 - groundRow
        dropBottom = groundRow + internalDrop
    end

    local dropStart = entryEnd + 1
    local dropEnd = dropStart + dropW - 1
    for col = dropStart, dropEnd do
        ClearArea(map, groundRow, dropBottom - 1, col, col, ctx.mapCols, ctx.mapRows)
        FillGround(map, col, dropBottom, ctx.mapCols, ctx.mapRows)
    end

    local landStart = dropEnd + 1
    local landEnd = landStart + landW - 1
    for col = landStart, landEnd do
        ClearArea(map, groundRow, dropBottom - 1, col, col, ctx.mapCols, ctx.mapRows)
        FillGround(map, col, dropBottom, ctx.mapCols, ctx.mapRows)
    end

    local enhancedJump = CalcJump(state.fallCount + internalDrop)
    local switchHeight = math.random(BASE_JUMP + 1, math.min(enhancedJump, cfg.highPlatMax))
    local switchPlatRow = dropBottom - switchHeight
    switchPlatRow = math.max(2, switchPlatRow)

    local switchStart = landEnd + 1
    local switchEnd = switchStart + switchW - 1
    switchEnd = math.min(switchEnd, colEnd - returnW - gateW - afterW)
    FillPlatform(map, switchPlatRow, switchStart, switchEnd, ctx.mapCols, ctx.mapRows)
    ClearArea(map, 1, switchPlatRow - 1, switchStart, switchEnd, ctx.mapCols, ctx.mapRows)

    local switchCol = math.floor((switchStart + switchEnd) / 2)
    local switchTileRow = switchPlatRow - 1
    if switchTileRow >= 1 then
        map[switchTileRow][switchCol] = MakeTileValue(TILE.SWITCH, group)
    end

    local returnStart = switchEnd + 1
    local returnEnd = returnStart + returnW - 1
    for col = returnStart, returnEnd do
        FillGround(map, col, groundRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, groundRow - 1, returnStart, returnEnd, ctx.mapCols, ctx.mapRows)

    local gateCol = ClampCol(returnEnd + 1, ctx.mapCols)
    if gateCol <= colEnd then
        map[groundRow - 1][gateCol] = MakeTileValue(TILE.GATE, group)
        if groundRow - 2 >= 1 then
            map[groundRow - 2][gateCol] = MakeTileValue(TILE.GATE, group)
        end
    end

    local afterStart = gateCol + 1
    for col = afterStart, colEnd do
        FillGround(map, col, groundRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, groundRow - 1, afterStart, colEnd, ctx.mapCols, ctx.mapRows)

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

--- 终点收束段
local function GenerateGoalSegment(map, colStart, colEnd, groundRow, state, cfg, goalStructure, ctx)
    local segWidth = colEnd - colStart + 1
    goalStructure = goalStructure or "A"

    for col = colStart, colEnd do
        FillGround(map, col, groundRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, groundRow - 1, colStart, colEnd, ctx.mapCols, ctx.mapRows)

    if goalStructure == "A" and segWidth >= 10 and state.flame > 30 then
        local dropDepth = math.min(3, math.floor((state.flame - 20) / FALL_FLAME_COST))
        dropDepth = math.max(2, dropDepth)
        local dropBottom = groundRow + dropDepth
        if dropBottom > ctx.mapRows - 1 then
            dropDepth = ctx.mapRows - 1 - groundRow
            dropBottom = groundRow + dropDepth
        end

        local afterDrop = ApplyDrop(state, dropDepth)
        local platHeight = math.random(BASE_JUMP + 1, math.min(afterDrop.jump, cfg.highPlatMax))
        local platRow = dropBottom - platHeight
        platRow = math.max(2, platRow)

        local dropStart = colStart + 2
        local dropEnd = math.min(dropStart + 3, colEnd - 7)
        if dropEnd <= dropStart then dropEnd = dropStart + 2 end

        local landStart = dropEnd + 1
        local landEnd = math.min(landStart + 2, colEnd - 4)

        local platStart = landEnd + 1
        local platEnd = math.min(platStart + 3, colEnd)

        for col = dropStart, dropEnd do
            ClearArea(map, groundRow, dropBottom - 1, col, col, ctx.mapCols, ctx.mapRows)
            FillGround(map, col, dropBottom, ctx.mapCols, ctx.mapRows)
        end
        for col = landStart, landEnd do
            ClearArea(map, groundRow, dropBottom - 1, col, col, ctx.mapCols, ctx.mapRows)
            FillGround(map, col, dropBottom, ctx.mapCols, ctx.mapRows)
        end
        for col = platStart, platEnd do
            FillGround(map, col, platRow, ctx.mapCols, ctx.mapRows)
        end
        ClearArea(map, 1, platRow - 1, platStart, platEnd, ctx.mapCols, ctx.mapRows)

        local goalCol = ClampCol(math.floor((platStart + platEnd) / 2), ctx.mapCols)
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
        local group = math.random(1, 4)

        local internalDrop = math.random(2, 3)
        local dropBottom = groundRow + internalDrop
        if dropBottom > ctx.mapRows - 1 then
            internalDrop = ctx.mapRows - 1 - groundRow
            dropBottom = groundRow + internalDrop
        end

        local afterDrop = ApplyDrop(state, internalDrop)
        local switchHeight = math.random(BASE_JUMP + 1, math.min(afterDrop.jump, cfg.highPlatMax))
        local switchPlatRow = dropBottom - switchHeight
        switchPlatRow = math.max(2, switchPlatRow)

        local dropStart = colStart + 2
        local dropEnd = math.min(dropStart + 2, colEnd - 11)
        local landStart = dropEnd + 1
        local landEnd = math.min(landStart + 2, colEnd - 8)
        local swStart = landEnd + 1
        local swEnd = math.min(swStart + 2, colEnd - 5)
        local retStart = swEnd + 1
        local retEnd = math.min(retStart + 1, colEnd - 3)
        local gateCol = ClampCol(retEnd + 1, ctx.mapCols)
        local goalCol = ClampCol(gateCol + 2, ctx.mapCols)

        for col = dropStart, dropEnd do
            ClearArea(map, groundRow, dropBottom - 1, col, col, ctx.mapCols, ctx.mapRows)
            FillGround(map, col, dropBottom, ctx.mapCols, ctx.mapRows)
        end
        for col = landStart, landEnd do
            ClearArea(map, groundRow, dropBottom - 1, col, col, ctx.mapCols, ctx.mapRows)
            FillGround(map, col, dropBottom, ctx.mapCols, ctx.mapRows)
        end
        FillPlatform(map, switchPlatRow, swStart, swEnd, ctx.mapCols, ctx.mapRows)
        ClearArea(map, 1, switchPlatRow - 1, swStart, swEnd, ctx.mapCols, ctx.mapRows)
        local switchCol = math.floor((swStart + swEnd) / 2)
        if switchPlatRow - 1 >= 1 then
            map[switchPlatRow - 1][switchCol] = MakeTileValue(TILE.SWITCH, group)
        end
        for col = retStart, retEnd do
            FillGround(map, col, groundRow, ctx.mapCols, ctx.mapRows)
        end
        ClearArea(map, 1, groundRow - 1, retStart, retEnd, ctx.mapCols, ctx.mapRows)
        if gateCol >= 1 and gateCol <= ctx.mapCols then
            map[groundRow - 1][gateCol] = MakeTileValue(TILE.GATE, group)
            if groundRow - 2 >= 1 then
                map[groundRow - 2][gateCol] = MakeTileValue(TILE.GATE, group)
            end
        end
        local goalRow = groundRow - 1
        if goalCol >= 1 and goalCol <= ctx.mapCols and goalRow >= 1 then
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
    local stepHeight = math.min(state.jump - 1, 3)
    stepHeight = math.max(2, stepHeight)
    local stepRow = groundRow - stepHeight
    stepRow = math.max(2, stepRow)

    local stepStart = ClampCol(colEnd - 4, ctx.mapCols)
    local stepEnd = colEnd
    for col = stepStart, stepEnd do
        FillGround(map, col, stepRow, ctx.mapCols, ctx.mapRows)
    end
    ClearArea(map, 1, stepRow - 1, stepStart, stepEnd, ctx.mapCols, ctx.mapRows)

    local goalCol = ClampCol(stepEnd - 1, ctx.mapCols)
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

--- 普通连接段
local function GenerateConnectorSegment(map, colStart, colEnd, groundRow, state, ctx)
    local segWidth = colEnd - colStart + 1

    local maxStep = math.min(2, state.jump - 1)
    local heightChange = math.random(0, maxStep)
    local dir = math.random() > 0.5 and -1 or 1
    local newGround = groundRow + dir * heightChange
    newGround = math.max(4, math.min(ctx.mapRows - 2, newGround))

    if groundRow - newGround > state.jump then
        newGround = groundRow
    end

    local steps = math.abs(newGround - groundRow)
    local stepDir = newGround < groundRow and -1 or 1
    local stepW = math.max(1, math.floor(segWidth / (steps + 1)))

    local curGround = groundRow
    for col = colStart, colEnd do
        local localIdx = col - colStart
        if steps > 0 and localIdx > 0 and localIdx % stepW == 0 and math.abs(curGround - newGround) > 0 then
            curGround = curGround + stepDir
        end
        FillGround(map, col, curGround, ctx.mapCols, ctx.mapRows)
        ClearArea(map, 1, curGround - 1, col, col, ctx.mapCols, ctx.mapRows)
    end

    return {
        type = "connector",
        exitCol = colEnd,
        exitRow = newGround,
        afterState = state,
    }
end

-- ====================================================================
-- 刺陷阱放置
-- ====================================================================

local function PlaceSpikes(map, segments, cfg, spawnCol, spawnRow, goalCol, goalRow, ctx)
    local placed = 0
    local maxSpikes = cfg.spikeMax

    for _, seg in ipairs(segments) do
        if placed >= maxSpikes then break end
        if seg.type == "spawn" or seg.type == "goal" then goto continue end
        if math.random() > cfg.spikeChance then goto continue end

        local exitCol = seg.exitCol or 10
        local exitRow = seg.exitRow or ctx.mapRows - 2

        local candidates = {}
        local searchStart = math.max(1, exitCol - 8)
        local searchEnd = math.max(searchStart, exitCol - 2)
        for col = searchStart, searchEnd do
            local row = exitRow - 1
            if col >= 1 and col <= ctx.mapCols and row >= 1 and row <= ctx.mapRows then
                if map[row][col] == TILE.EMPTY and row + 1 <= ctx.mapRows and map[row + 1][col] == TILE.SOLID then
                    local distSpawn = math.abs(col - spawnCol) + math.abs(row - spawnRow)
                    if distSpawn < 5 then goto skipCandidate end
                    if goalCol then
                        local distGoal = math.abs(col - goalCol) + math.abs(row - goalRow)
                        if distGoal < 3 then goto skipCandidate end
                    end
                    local leftOk = col > 1 and map[row][col - 1] == TILE.EMPTY
                    local rightOk = col < ctx.mapCols and map[row][col + 1] == TILE.EMPTY
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

local TEMPLATES = {
    {
        name = "下落教学",
        segments = { "spawn", "connector", "drop", "goal_A" },
        minDiff = "easy",
    },
    {
        name = "回复抉择",
        segments = { "spawn", "drop", "recover_choice", "goal_A" },
        minDiff = "easy",
    },
    {
        name = "机关挑战",
        segments = { "spawn", "connector", "puzzle", "goal_C" },
        minDiff = "normal",
    },
    {
        name = "机关收束",
        segments = { "spawn", "drop", "connector", "goal_B" },
        minDiff = "normal",
    },
    {
        name = "完整体验",
        segments = { "spawn", "drop", "recover_mandatory", "puzzle", "goal_A" },
        minDiff = "hard",
    },
    {
        name = "双重强化",
        segments = { "spawn", "drop", "connector", "drop", "goal_A" },
        minDiff = "hard",
    },
}

-- ====================================================================
-- 主路线模拟校验器
-- ====================================================================

local function SimulateRoute(segments, cfg)
    local state = MakeState()

    for i, seg in ipairs(segments) do
        if state.flame <= 0 then
            return false, string.format("段%d(%s)前火焰已耗尽", i, seg.type)
        end

        if seg.type == "drop" then
            local drop = seg.dropDepth or 0
            state = ApplyDrop(state, drop)
            if state.flame <= 0 then
                return false, string.format("段%d(drop)导致火焰耗尽", i)
            end
            if seg.highPlatHeight and state.jump < seg.highPlatHeight then
                return false, string.format("段%d(drop)高台不可达: 需%d格, 有%d格跳跃",
                    i, seg.highPlatHeight, state.jump)
            end

        elseif seg.type == "recover_mandatory" then
            state = ApplyRecover(state)

        elseif seg.type == "recover_choice" then
            state = ApplyRecover(state)

        elseif seg.type == "puzzle" then
            local drop = seg.internalDrop or 0
            local stateAfterDrop = ApplyDrop(state, drop)
            if stateAfterDrop.flame <= 0 then
                return false, string.format("段%d(puzzle)下落导致火焰耗尽", i)
            end
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
    end

    if state.flame < cfg.minEndFlame then
        return false, string.format("终点火焰不足: %.0f%% < %d%%", state.flame, cfg.minEndFlame)
    end

    return true, nil
end

local function HasCoreMechanicValidation(segments)
    for _, seg in ipairs(segments) do
        if seg.type == "drop" or seg.type == "puzzle" then
            return true
        end
        if seg.type == "goal" and (seg.structure == "A" or seg.structure == "B") then
            if seg.dropDepth and seg.dropDepth >= 2 then return true end
            if seg.internalDrop and seg.internalDrop >= 2 then return true end
        end
    end
    return false
end

-- ====================================================================
-- 主生成函数（v2.1: 接受 gridWidth/gridHeight 参数）
-- ====================================================================

--- 生成随机关卡
--- @param difficulty string "easy"|"normal"|"hard"
--- @param gridWidth number|nil 画布横向格子数（不传则使用默认值）
--- @param gridHeight number|nil 画布纵向格子数（不传则使用默认值）
--- @return table map, number spawnCol, number spawnRow, string templateName, string difficulty, table segments
function LevelGenerator.Generate(difficulty, gridWidth, gridHeight)
    difficulty = difficulty or "normal"
    local cfg = DIFFICULTY[difficulty]
    if not cfg then
        difficulty = "normal"
        cfg = DIFFICULTY[difficulty]
    end

    -- 读取画布尺寸（不使用固定值）
    local mapCols = gridWidth or DEFAULT_COLS
    local mapRows = gridHeight or DEFAULT_ROWS

    -- 画布最小保障
    mapCols = math.max(15, mapCols)
    mapRows = math.max(8, mapRows)

    -- 构建上下文对象，传递给所有段落生成器
    local ctx = {
        mapCols = mapCols,
        mapRows = mapRows,
    }

    -- 根据画布规模调整配置
    local canvasScale = EvaluateCanvasScale(mapCols, mapRows)
    cfg = AdjustCfgForCanvas(cfg, canvasScale, mapCols, mapRows)

    -- 选择模板（根据画布规模过滤）
    local availableTemplates = GetTemplatesForCanvas(canvasScale, difficulty)
    local tidx = availableTemplates[math.random(1, #availableTemplates)]
    local tmpl = TEMPLATES[tidx]
    local segDefs = tmpl.segments

    -- 根据画布宽度动态调整段落数（不使用固定段数）
    local segCount = #segDefs
    -- 如果画布宽度不足以容纳所有段落（每段至少需 6 格宽），截断尾部段落保留核心
    local maxSegsForWidth = math.max(3, math.floor(mapCols / 6))
    if segCount > maxSegsForWidth then
        -- 保留 spawn + 至少一个中间段 + goal（最后一个）
        local newDefs = {}
        newDefs[1] = segDefs[1]  -- spawn
        -- 中间保留尽可能多的核心段
        for i = 2, maxSegsForWidth - 1 do
            if i <= segCount - 1 then
                newDefs[i] = segDefs[i]
            end
        end
        newDefs[#newDefs + 1] = segDefs[segCount]  -- goal
        segDefs = newDefs
        segCount = #segDefs
    end

    -- 动态分配每段宽度（基于实际画布宽度）
    local usableCols = mapCols - 2  -- 左右各留1格边界
    local baseSegWidth = math.floor(usableCols / segCount)
    local extraCols = usableCols - baseSegWidth * segCount

    -- 初始化
    local map = CreateEmptyMap(mapCols, mapRows)
    local baseGround = mapRows - 2  -- 默认地面在倒数第3行
    local state = MakeState()
    local segments = {}

    local currentCol = 2  -- 出生点在左侧安全区域（x=2~4）
    local currentGround = baseGround
    local spawnCol, spawnRow
    local goalCol, goalRow

    for i, segDef in ipairs(segDefs) do
        local segStart = currentCol
        local segW = baseSegWidth + (i <= extraCols and 1 or 0)
        local segEnd = math.min(segStart + segW - 1, mapCols - 1)
        if i == segCount then segEnd = mapCols - 1 end

        -- 边界校验：确保段不超出画布
        segEnd = math.min(segEnd, mapCols - 1)
        if segStart >= segEnd then break end

        -- 决定是否需要强制回复
        local remainingSegs = segCount - i
        if state.flame < cfg.fuelPlacementThreshold and remainingSegs >= 2
            and segDef ~= "recover_mandatory" and segDef ~= "recover_choice"
            and segDef ~= "goal_A" and segDef ~= "goal_B" and segDef ~= "goal_C"
            and segDef ~= "spawn" then
            segDef = "recover_mandatory"
        end

        local seg

        if segDef == "spawn" then
            seg = GenerateSpawnSegment(map, segStart, segEnd, currentGround, ctx)
            spawnCol = seg.spawnCol
            spawnRow = seg.spawnRow

        elseif segDef == "connector" then
            seg = GenerateConnectorSegment(map, segStart, segEnd, currentGround, state, ctx)

        elseif segDef == "drop" then
            seg = GenerateDropSegment(map, segStart, segEnd, currentGround, state, cfg, ctx)

        elseif segDef == "recover_mandatory" then
            seg = GenerateMandatoryRecoverSegment(map, segStart, segEnd, currentGround, state, ctx)

        elseif segDef == "recover_choice" then
            seg = GenerateChoiceRecoverSegment(map, segStart, segEnd, currentGround, state, cfg, ctx)

        elseif segDef == "puzzle" then
            if not cfg.useSwitch then
                seg = GenerateDropSegment(map, segStart, segEnd, currentGround, state, cfg, ctx)
            else
                seg = GeneratePuzzleSegment(map, segStart, segEnd, currentGround, state, cfg, ctx)
            end

        elseif segDef == "goal_A" then
            seg = GenerateGoalSegment(map, segStart, segEnd, currentGround, state, cfg, "A", ctx)

        elseif segDef == "goal_B" then
            seg = GenerateGoalSegment(map, segStart, segEnd, currentGround, state, cfg, "B", ctx)

        elseif segDef == "goal_C" then
            seg = GenerateGoalSegment(map, segStart, segEnd, currentGround, state, cfg, "C", ctx)
        end

        if seg then
            table.insert(segments, seg)
            if seg.afterState then
                state = seg.afterState
            end
            if seg.exitRow then currentGround = seg.exitRow end
            currentCol = (seg.exitCol or segEnd) + 1

            if seg.type == "goal" then
                goalCol = seg.goalCol
                goalRow = seg.goalRow
            end
        else
            for col = segStart, segEnd do
                FillGround(map, col, currentGround, ctx.mapCols, ctx.mapRows)
            end
            ClearArea(map, 1, currentGround - 1, segStart, segEnd, ctx.mapCols, ctx.mapRows)
            currentCol = segEnd + 1
        end
    end

    -- 放置刺陷阱
    PlaceSpikes(map, segments, cfg, spawnCol or 3, spawnRow or baseGround - 1, goalCol, goalRow, ctx)

    -- 确保出生点标记和脚下实体（边界校验）
    if spawnRow and spawnCol then
        if spawnRow >= 1 and spawnRow <= mapRows and spawnCol >= 1 and spawnCol <= mapCols then
            map[spawnRow][spawnCol] = TILE.SPAWN
            if spawnRow + 1 <= mapRows then
                map[spawnRow + 1][spawnCol] = TILE.SOLID
            end
        end
    end

    -- 确保终点门和脚下实体（边界校验）
    if goalRow and goalCol then
        if goalRow >= 1 and goalRow <= mapRows and goalCol >= 1 and goalCol <= mapCols then
            if map[goalRow][goalCol] ~= TILE.GOAL then
                map[goalRow][goalCol] = TILE.GOAL
            end
            if goalRow + 1 <= mapRows then
                map[goalRow + 1][goalCol] = TILE.SOLID
            end
        end
    end

    return map, spawnCol or 3, spawnRow or (baseGround - 1), tmpl.name, difficulty, segments
end

--- 带校验的生成（失败重试）
--- @param difficulty string "easy"|"normal"|"hard"
--- @param maxRetries number|nil 最大重试次数（默认8）
--- @param gridWidth number|nil 画布横向格子数
--- @param gridHeight number|nil 画布纵向格子数
function LevelGenerator.GenerateValid(difficulty, maxRetries, gridWidth, gridHeight)
    maxRetries = maxRetries or 8
    local cfg = DIFFICULTY[difficulty or "normal"]

    for attempt = 1, maxRetries do
        local map, sc, sr, tName, diff, segs = LevelGenerator.Generate(difficulty, gridWidth, gridHeight)
        local valid = true
        local reason = ""

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

        if valid and not HasCoreMechanicValidation(segs) then
            valid = false
            reason = "no core mechanic validation"
        end

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
    local map, sc, sr, tName = LevelGenerator.Generate("easy", gridWidth, gridHeight)
    return map, sc, sr, tName
end

-- 导出（保留兼容性，默认值仅供参考）
LevelGenerator.TILE = TILE
LevelGenerator.MAP_COLS = DEFAULT_COLS
LevelGenerator.MAP_ROWS = DEFAULT_ROWS

return LevelGenerator
