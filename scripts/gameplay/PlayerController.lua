------------------------------------------------------------
-- gameplay/PlayerController.lua — 玩家逻辑（移动、跳跃、垂直物理、收集）
------------------------------------------------------------
local Config = require("gameplay.Config")

local M = {}

-- 依赖（通过 Inject 注入）
local Physics = nil
local PixelSystem = nil
local LevelManager = nil
local Animation = nil  -- 用于触发动画回调
local Renderer = nil   -- 用于触发 BONFIRE LIT 消息
local CurtainRenderer = nil  -- 柳条门帘（触碰晃动）
local Fireball = nil   -- 火球系统（吸收动画）

function M.Inject(deps)
    Physics = deps.Physics
    PixelSystem = deps.PixelSystem
    LevelManager = deps.LevelManager
    Animation = deps.Animation
    Renderer = deps.Renderer
    CurtainRenderer = deps.CurtainRenderer
    Fireball = deps.Fireball
end

-- ====================================================================
-- 玩家状态
-- ====================================================================
M.player = {
    gridX = 3,
    gridY = 1,
    isOnGround = false,
    isJumping = false,
    jumpGridsRemain = 0,
    facingRight = true,

    moveTimer = 0,
    movedFirstStep = false,
    fallTimer = 0,
    fallTickCurrent = 0,
    jumpTimer = 0,

    -- 下落计数（基于底部位置的净下降）
    fallGridCount = 0,
    bottomHighestY = 0,  -- 底部到达过的最高位置（Y 值最小 = 位置最高）

    -- 跳跃容错追踪
    jumpOriginBottomY = 0,  -- 起跳时底部的 Y 位置
    jumpEarnedRemain = 0,   -- 正式跳跃格数剩余（不含容错格）

    -- 动画状态
    isMoving = false,
    moveAnimTime = 0,
    fallAnimTime = 0,

    -- 跨关卡保护：切换关卡后不因满血而重置跳跃能力
    transitionProtect = false,

    -- 能力点状态
    hasFireball = false,      -- 是否已获得火球能力
    hasLanternDash = false,   -- 是否已解锁灯间位移
}

--- 重置玩家状态
function M.ResetPlayer()
    local p = M.player
    p.isOnGround = false
    p.isJumping = false
    p.jumpGridsRemain = 0
    p.facingRight = true
    p.moveTimer = 0
    p.movedFirstStep = false
    p.fallTimer = 0
    p.fallTickCurrent = Config.PLAYER_CONFIG.fallTickBase
    p.jumpTimer = 0
    p.fallGridCount = 0
    local s = Physics and Physics.PlayerGridSize() or 2
    p.bottomHighestY = p.gridY + s - 1
    p.jumpOriginBottomY = p.bottomHighestY
    p.jumpEarnedRemain = 0
    p.isMoving = false
    p.moveAnimTime = 0
    p.fallAnimTime = 0
    p.hasFireball = false
    p.hasLanternDash = false
end

-- ====================================================================
-- 跳跃高度计算
-- ====================================================================

--- 计算当前跳跃能力（纯净值，不含容错，用于 HUD 显示）
function M.CalcJumpHeight()
    local p = M.player
    local baseJump = Config.levelPlayerParams.baseJumpGrids
    local bonus = p.fallGridCount * Config.levelPlayerParams.fallJumpMultiplier
    return math.min(math.floor(baseJump + bonus + 0.5), Config.levelPlayerParams.maxJumpGrids)
end

-- ====================================================================
-- 跳跃
-- ====================================================================

function M.PlayerJump()
    local p = M.player
    if p.isOnGround and not p.isJumping then
        -- 纯净跳跃能力（1:1 对应下落格数）
        local baseJump = Config.levelPlayerParams.baseJumpGrids
        local bonus = p.fallGridCount * Config.levelPlayerParams.fallJumpMultiplier
        local earnedHeight = math.min(math.floor(baseJump + bonus + 0.5), Config.levelPlayerParams.maxJumpGrids)

        if earnedHeight <= 0 then
            if Animation then Animation.TriggerCantJumpShake() end
            return
        end

        -- 手感优化：实际跳跃多 1 格容错，但不计入能量
        local bonusGrids = 1
        local totalJump = math.min(earnedHeight + bonusGrids, Config.levelPlayerParams.maxJumpGrids)

        local s = Physics.PlayerGridSize()
        p.isJumping = true
        p.jumpGridsRemain = totalJump
        p.jumpEarnedRemain = earnedHeight  -- 还剩多少"正式"格可以更新 bottomHighestY
        p.jumpOriginBottomY = p.gridY + s - 1
        p.isOnGround = false
        p.jumpTimer = 0
        if Animation then Animation.TriggerJumpSquash() end
    end
end

-- ====================================================================
-- 水平移动
-- ====================================================================

--- 判断斜坡方向与移动方向是否构成"上坡"/"下坡"
--- @return boolean isUphill, boolean isDownhill
local function SlopeMovementType(slopeType, dir)
    -- SLOPE_TR(19): 右上斜坡 → 向右走上坡，向左走下坡
    -- SLOPE_TL(20): 左上斜坡 → 向左走上坡，向右走下坡
    -- SLOPE_BR(21): 右下斜坡 → 向右走下坡，向左走上坡
    -- SLOPE_BL(22): 左下斜坡 → 向左走下坡，向右走上坡
    if slopeType == 19 then       -- SLOPE_TR
        if dir == 1 then return true, false end
        if dir == -1 then return false, true end
    elseif slopeType == 20 then   -- SLOPE_TL
        if dir == -1 then return true, false end
        if dir == 1 then return false, true end
    elseif slopeType == 21 then   -- SLOPE_BR
        if dir == 1 then return false, true end
        if dir == -1 then return true, false end
    elseif slopeType == 22 then   -- SLOPE_BL
        if dir == -1 then return false, true end
        if dir == 1 then return true, false end
    end
    return false, false
end

--- 检查玩家附近（目标区域+脚下）是否有指定方向的斜坡
--- @return boolean hasUpSlope, boolean hasDownSlope
local function CheckSlopesNearby(gx, gy, newX, dir)
    local s = Physics.PlayerGridSize()
    local hasUp, hasDown = false, false
    -- 检查目标位置区域
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            local slope = Physics.GetSlopeAt(newX + dx, gy + dy)
            if slope then
                local u, d = SlopeMovementType(slope, dir)
                if u then hasUp = true end
                if d then hasDown = true end
            end
        end
    end
    -- 检查当前位置脚下（站在斜坡上）
    local feetRow = gy + s
    for dx = 0, s - 1 do
        local slope = Physics.GetSlopeAt(gx + dx, feetRow)
        if slope then
            local u, d = SlopeMovementType(slope, dir)
            if u then hasUp = true end
            if d then hasDown = true end
        end
        -- 玩家最底行也检查
        slope = Physics.GetSlopeAt(gx + dx, gy + s - 1)
        if slope then
            local u, d = SlopeMovementType(slope, dir)
            if u then hasUp = true end
            if d then hasDown = true end
        end
    end
    return hasUp, hasDown
end

function M.PlayerMoveOneGrid(dir)
    local p = M.player
    local newX = p.gridX + dir

    -- 用忽略斜坡的碰撞检测（斜坡不阻挡玩家水平移动）
    if not Physics.PlayerCollidesAtIgnoreSlopes(newX, p.gridY) then
        -- 平移成功
        p.gridX = newX

        -- 下坡贴合：移动后检查是否应该向下贴合斜坡
        -- 条件：脚下有下坡方向的斜坡，且下移后不会碰到非斜坡实体
        local s = Physics.PlayerGridSize()
        local feetRow = p.gridY + s
        local shouldSnapDown = false
        for dx = 0, s - 1 do
            local slope = Physics.GetSlopeAt(p.gridX + dx, feetRow)
            if slope then
                local _, isDown = SlopeMovementType(slope, dir)
                if isDown then shouldSnapDown = true; break end
            end
            -- 也检查玩家底行（正在斜坡内部）
            slope = Physics.GetSlopeAt(p.gridX + dx, p.gridY + s - 1)
            if slope then
                local _, isDown = SlopeMovementType(slope, dir)
                if isDown then shouldSnapDown = true; break end
            end
        end

        if shouldSnapDown then
            local downY = p.gridY + 1
            if not Physics.PlayerCollidesAtIgnoreSlopes(p.gridX, downY) then
                p.gridY = downY
                -- 斜坡下降时减小火焰（与普通下落一致：下滑一格降低一格）
                local currentBottomY = p.gridY + s - 1
                local netFall = currentBottomY - p.bottomHighestY
                if netFall >= 1 then
                    p.fallGridCount = netFall
                end
                local stripCount = math.max(1, math.floor(PixelSystem.totalPixels / 10 + 0.5))
                PixelSystem.StripPixels(stripCount)
            end
        end

        p.facingRight = (dir > 0)
        return
    end

    -- 平移被（非斜坡的）实体阻挡 → 检查是否有斜坡暗示上坡
    local hasUp, _ = CheckSlopesNearby(p.gridX, p.gridY, newX, dir)
    if hasUp then
        local upY = p.gridY - 1
        if not Physics.PlayerCollidesAtIgnoreSlopes(newX, upY) then
            p.gridX = newX
            p.gridY = upY
            p.facingRight = (dir > 0)
            return
        end
    end

    -- 都失败，玩家被阻挡
    p.facingRight = (dir > 0)
end

-- ====================================================================
-- 垂直物理
-- ====================================================================

--- 更新垂直物理
---@param dt number
---@return string|nil "gameover" if dead
function M.UpdateVertical(dt)
    local p = M.player
    local PC = Config.PLAYER_CONFIG

    local s = Physics.PlayerGridSize()

    if p.isJumping and p.jumpGridsRemain > 0 then
        p.jumpTimer = p.jumpTimer + dt
        if p.jumpTimer >= PC.jumpTickRate then
            p.jumpTimer = 0
            local newY = p.gridY - 1
            if not Physics.PlayerCollidesAt(p.gridX, newY) then
                p.gridY = newY
                p.jumpGridsRemain = p.jumpGridsRemain - 1
                -- 只在"正式格"范围内更新 bottomHighestY（容错格不计入能量）
                if p.jumpEarnedRemain > 0 then
                    p.jumpEarnedRemain = p.jumpEarnedRemain - 1
                    local currentBottomY = p.gridY + s - 1
                    if currentBottomY < p.bottomHighestY then
                        p.bottomHighestY = currentBottomY
                    end
                end
            else
                p.jumpGridsRemain = 0
            end
        end
        if p.jumpGridsRemain <= 0 then
            p.isJumping = false
            p.jumpEarnedRemain = 0
            p.fallTickCurrent = PC.fallTickBase
        end
    else
        if not Physics.PlayerOnGround(p.gridX, p.gridY) then
            p.isOnGround = false
            p.fallTimer = p.fallTimer + dt
            p.fallAnimTime = p.fallAnimTime + dt
            if p.fallTimer >= p.fallTickCurrent then
                p.fallTimer = 0
                local newY = p.gridY + 1
                if newY > Config.MAP_ROWS then
                    return "boundary"
                end
                if not Physics.PlayerCollidesAt(p.gridX, newY) then
                    p.gridY = newY
                    p.fallTickCurrent = math.max(PC.fallTickMin, p.fallTickCurrent - PC.fallAccel)

                    -- 基于底部位置计算净下降格数
                    local currentBottomY = p.gridY + s - 1
                    local netFall = currentBottomY - p.bottomHighestY
                    -- 只有净下降 >= 1 格才计入跳跃能力（不足1格忽略）
                    if netFall >= 1 then
                        p.fallGridCount = netFall
                    else
                        p.fallGridCount = 0
                    end

                    local stripCount = math.max(1, math.floor(PixelSystem.totalPixels / 10 + 0.5))
                    PixelSystem.StripPixels(stripCount)
                    if p.fallGridCount >= Config.levelPlayerParams.maxFallGrids then
                        return "gameover"
                    end
                else
                    p.isOnGround = true
                    p.fallTickCurrent = PC.fallTickBase
                    p.fallAnimTime = 0
                end
            end
        else
            p.isOnGround = true
            p.isJumping = false
            p.fallTickCurrent = PC.fallTickBase
            p.fallAnimTime = 0
        end
    end

    -- 像素完全恢复时（通过燃料/篝火），重置位置能量
    -- 但跨关卡保护期间不重置（保留切换前积累的跳跃能力）
    if p.isOnGround and PixelSystem.alivePixels >= PixelSystem.totalPixels then
        if p.transitionProtect then
            -- 跨关卡保护：落地后解除保护，但不重置跳跃能力
            p.transitionProtect = false
        else
            local currentBottomY = p.gridY + s - 1
            p.bottomHighestY = currentBottomY
            p.fallGridCount = 0
        end
    end

    -- 斜坡下降累积的 fallGridCount 也需要触发坠落死亡
    if p.fallGridCount >= Config.levelPlayerParams.maxFallGrids then
        return "gameover"
    end

    if PixelSystem.alivePixels <= 0 then
        return "gameover"
    end

    return nil
end

-- ====================================================================
-- 收集检测
-- ====================================================================

--- 检查物品收集
---@return string|nil "gameover"|"win" 或 nil
function M.CheckItemCollection()
    local p = M.player
    local s = Physics.PlayerGridSize()
    local TILE = LevelManager.TILE

    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            local col = p.gridX + dx
            local row = p.gridY + dy
            if col >= 1 and col <= Config.MAP_COLS and row >= 1 and row <= Config.MAP_ROWS
                and LevelManager.levelData[row] then
                local val = LevelManager.levelData[row][col]
                local base, group = Physics.GetTileType(val)
                local key = row .. "_" .. col

                if base == TILE.SPIKE then
                    return "gameover"

                elseif base == TILE.GOAL then
                    return "win"

                elseif base == TILE.FUEL and not LevelManager.collectedItems[key] then
                    LevelManager.collectedItems[key] = true
                    LevelManager.fuelCount = LevelManager.fuelCount + 1
                    LevelManager.levelData[row][col] = TILE.EMPTY
                    -- 使用渐进式像素恢复动画（不再瞬间恢复）
                    local toRecover = math.floor(PixelSystem.totalPixels * 0.4)
                    -- 限制恢复量不超过已损失的像素
                    local lost = PixelSystem.totalPixels - PixelSystem.alivePixels
                    toRecover = math.min(toRecover, lost)
                    if toRecover > 0 and Renderer then
                        Renderer.StartPixelRecoverAnim(toRecover)
                    end
                    -- fallGridCount 由位置系统驱动，不再从像素反推
                    -- 触发火苗爆裂特效
                    if Renderer then
                        local GRID = require("gameplay.Config").GRID
                        local worldX = (col - 1) * GRID + GRID * 0.5
                        local worldY = (row - 1) * GRID + GRID * 0.5
                        Renderer.TriggerFuelBurst(worldX, worldY)
                    end

                elseif base == TILE.SWITCH and not LevelManager.switchCollected[key] then
                    LevelManager.switchCollected[key] = true
                    LevelManager.switchState[group] = not LevelManager.switchState[group]

                elseif base == TILE.CHECKPOINT then
                    local isNewBonfire = not LevelManager.checkpointActivated[key]
                    local isHealthNotFull = PixelSystem.alivePixels < PixelSystem.totalPixels

                    if isNewBonfire or isHealthNotFull then
                        -- 熄灭其他篝火，激活当前
                        LevelManager.checkpointActivated = {}
                        LevelManager.checkpointActivated[key] = true
                        LevelManager.checkpointCol = col
                        LevelManager.checkpointRow = row
                        LevelManager.checkpointFile = LevelManager.currentLevelFile
                        -- 补满火焰
                        PixelSystem.RecoverPixels(PixelSystem.totalPixels)
                        -- 篝火重置：位置能量归零
                        local siz = Physics.PlayerGridSize()
                        p.bottomHighestY = p.gridY + siz - 1
                        p.fallGridCount = 0
                        -- 显示 BONFIRE LIT + 点燃特效
                        if Renderer then
                            Renderer.ShowBonfireMessage()
                            Renderer.TriggerCampfireIgnite(key)
                        end
                    end

                elseif base == TILE.ABILITY_POINT and not LevelManager.collectedItems[key] then
                    -- 能力点：吸收动画 + 清除 tile + 赋予火球能力
                    LevelManager.collectedItems[key] = true
                    LevelManager.levelData[row][col] = TILE.EMPTY
                    p.hasFireball = true
                    -- 触发吸收动画
                    if Fireball then
                        local worldX = (col - 1) * Config.GRID + Config.GRID * 0.5
                        local worldY = (row - 1) * Config.GRID + Config.GRID * 0.5
                        Fireball.StartAbsorbAnim(worldX, worldY)
                    end
                end
            end
        end
    end

    -- 检测邻接的隐藏墙（存储揭示时间戳，用于渐变消失）
    local gx, gy = p.gridX, p.gridY
    local leftCol = gx - 1
    if leftCol >= 1 then
        for dy = 0, s - 1 do
            local r = gy + dy
            if r >= 1 and r <= Config.MAP_ROWS and LevelManager.levelData[r] then
                local ab, ag = Physics.GetTileType(LevelManager.levelData[r][leftCol])
                if ab == TILE.HIDDEN_WALL and not LevelManager.hiddenWallRevealed[ag] then
                    LevelManager.hiddenWallRevealed[ag] = LevelManager.gameTime
                end
            end
        end
    end
    local rightCol = gx + s
    if rightCol <= Config.MAP_COLS then
        for dy = 0, s - 1 do
            local r = gy + dy
            if r >= 1 and r <= Config.MAP_ROWS and LevelManager.levelData[r] then
                local ab, ag = Physics.GetTileType(LevelManager.levelData[r][rightCol])
                if ab == TILE.HIDDEN_WALL and not LevelManager.hiddenWallRevealed[ag] then
                    LevelManager.hiddenWallRevealed[ag] = LevelManager.gameTime
                end
            end
        end
    end
    local topRow = gy - 1
    if topRow >= 1 and topRow <= Config.MAP_ROWS and LevelManager.levelData[topRow] then
        for dx = 0, s - 1 do
            local c = gx + dx
            if c >= 1 and c <= Config.MAP_COLS then
                local ab, ag = Physics.GetTileType(LevelManager.levelData[topRow][c])
                if ab == TILE.HIDDEN_WALL and not LevelManager.hiddenWallRevealed[ag] then
                    LevelManager.hiddenWallRevealed[ag] = LevelManager.gameTime
                end
            end
        end
    end
    local bottomRow = gy + s
    if bottomRow >= 1 and bottomRow <= Config.MAP_ROWS and LevelManager.levelData[bottomRow] then
        for dx = 0, s - 1 do
            local c = gx + dx
            if c >= 1 and c <= Config.MAP_COLS then
                local ab, ag = Physics.GetTileType(LevelManager.levelData[bottomRow][c])
                if ab == TILE.HIDDEN_WALL and not LevelManager.hiddenWallRevealed[ag] then
                    LevelManager.hiddenWallRevealed[ag] = LevelManager.gameTime
                end
            end
        end
    end

    -- 柳条门帘触碰检测：玩家占据的格子如果有柳条，触发晃动
    if CurtainRenderer then
        for dy = 0, s - 1 do
            for dx = 0, s - 1 do
                local col = gx + dx
                local row = gy + dy
                if col >= 1 and col <= Config.MAP_COLS and row >= 1 and row <= Config.MAP_ROWS
                    and LevelManager.levelData[row] then
                    local ab = Physics.GetTileType(LevelManager.levelData[row][col])
                    if ab == TILE.CURTAIN then
                        CurtainRenderer.TriggerSway(col, row, 1.0)
                        CurtainRenderer.PropagateSwayToNeighbors(col, row, 1.0,
                            LevelManager.levelData, TILE, Physics.GetTileType)
                    end
                end
            end
        end
    end

    return nil
end

return M
