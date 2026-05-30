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

function M.Inject(deps)
    Physics = deps.Physics
    PixelSystem = deps.PixelSystem
    LevelManager = deps.LevelManager
    Animation = deps.Animation
    Renderer = deps.Renderer
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

    -- 下落计数
    fallGridCount = 0,

    -- 动画状态
    isMoving = false,
    moveAnimTime = 0,
    fallAnimTime = 0,
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
    p.isMoving = false
    p.moveAnimTime = 0
    p.fallAnimTime = 0
end

-- ====================================================================
-- 跳跃高度计算
-- ====================================================================

function M.CalcJumpHeight()
    local baseJump = Config.levelPlayerParams.baseJumpGrids
    local bonus = M.player.fallGridCount * Config.levelPlayerParams.fallJumpMultiplier
    return math.min(math.floor(baseJump + bonus + 0.5), Config.levelPlayerParams.maxJumpGrids)
end

-- ====================================================================
-- 跳跃
-- ====================================================================

function M.PlayerJump()
    local p = M.player
    if p.isOnGround and not p.isJumping then
        local jumpHeight = M.CalcJumpHeight()
        if jumpHeight <= 0 then
            if Animation then Animation.TriggerCantJumpShake() end
            return
        end
        p.isJumping = true
        p.jumpGridsRemain = jumpHeight
        p.isOnGround = false
        p.jumpTimer = 0
        if Animation then Animation.TriggerJumpSquash() end
    end
end

-- ====================================================================
-- 水平移动
-- ====================================================================

function M.PlayerMoveOneGrid(dir)
    local p = M.player
    local newX = p.gridX + dir
    if not Physics.PlayerCollidesAt(newX, p.gridY) then
        p.gridX = newX
    end
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

    if p.isJumping and p.jumpGridsRemain > 0 then
        p.jumpTimer = p.jumpTimer + dt
        if p.jumpTimer >= PC.jumpTickRate then
            p.jumpTimer = 0
            local newY = p.gridY - 1
            if not Physics.PlayerCollidesAt(p.gridX, newY) then
                p.gridY = newY
                p.jumpGridsRemain = p.jumpGridsRemain - 1
            else
                p.jumpGridsRemain = 0
            end
        end
        if p.jumpGridsRemain <= 0 then
            p.isJumping = false
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
                    return "gameover"
                end
                if not Physics.PlayerCollidesAt(p.gridX, newY) then
                    p.gridY = newY
                    p.fallTickCurrent = math.max(PC.fallTickMin, p.fallTickCurrent - PC.fallAccel)
                    p.fallGridCount = p.fallGridCount + 1
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

    -- 落地恢复像素
    if p.isOnGround and PixelSystem.alivePixels < PixelSystem.totalPixels then
        local recoverCount = math.floor(PC.recoverPerSec * dt + 0.5)
        if recoverCount >= 1 then
            PixelSystem.RecoverPixels(recoverCount)
            local pixelsPerGrid = math.max(1, math.floor(PixelSystem.totalPixels / 10 + 0.5))
            local expectedFallCount = math.floor((PixelSystem.totalPixels - PixelSystem.alivePixels) / pixelsPerGrid)
            p.fallGridCount = math.max(0, expectedFallCount)
        end
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
            if col >= 1 and col <= Config.MAP_COLS and row >= 1 and row <= Config.MAP_ROWS then
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
                    PixelSystem.RecoverPixels(math.floor(PixelSystem.totalPixels * 0.4))
                    local pixelsPerGrid = math.max(1, math.floor(PixelSystem.totalPixels / 10 + 0.5))
                    local expectedFallCount = math.floor((PixelSystem.totalPixels - PixelSystem.alivePixels) / pixelsPerGrid)
                    p.fallGridCount = math.max(0, expectedFallCount)

                elseif base == TILE.SWITCH and not LevelManager.switchCollected[key] then
                    LevelManager.switchCollected[key] = true
                    LevelManager.switchState[group] = not LevelManager.switchState[group]

                elseif base == TILE.CHECKPOINT and not LevelManager.checkpointActivated[key] then
                    -- 熄灭其他篝火，激活当前
                    LevelManager.checkpointActivated = {}
                    LevelManager.checkpointActivated[key] = true
                    LevelManager.checkpointCol = col
                    LevelManager.checkpointRow = row
                    LevelManager.checkpointFile = LevelManager.currentLevelFile
                    -- 补满火焰
                    PixelSystem.RecoverPixels(PixelSystem.totalPixels)
                    local pixelsPerGrid = math.max(1, math.floor(PixelSystem.totalPixels / 10 + 0.5))
                    p.fallGridCount = 0
                    -- 显示 BONFIRE LIT
                    if Renderer then Renderer.ShowBonfireMessage() end
                end
            end
        end
    end

    -- 检测邻接的隐藏墙
    local gx, gy = p.gridX, p.gridY
    local leftCol = gx - 1
    if leftCol >= 1 then
        for dy = 0, s - 1 do
            local r = gy + dy
            if r >= 1 and r <= Config.MAP_ROWS then
                local ab, ag = Physics.GetTileType(LevelManager.levelData[r][leftCol])
                if ab == TILE.HIDDEN_WALL and not LevelManager.hiddenWallRevealed[ag] then
                    LevelManager.hiddenWallRevealed[ag] = true
                end
            end
        end
    end
    local rightCol = gx + s
    if rightCol <= Config.MAP_COLS then
        for dy = 0, s - 1 do
            local r = gy + dy
            if r >= 1 and r <= Config.MAP_ROWS then
                local ab, ag = Physics.GetTileType(LevelManager.levelData[r][rightCol])
                if ab == TILE.HIDDEN_WALL and not LevelManager.hiddenWallRevealed[ag] then
                    LevelManager.hiddenWallRevealed[ag] = true
                end
            end
        end
    end
    local topRow = gy - 1
    if topRow >= 1 then
        for dx = 0, s - 1 do
            local c = gx + dx
            if c >= 1 and c <= Config.MAP_COLS then
                local ab, ag = Physics.GetTileType(LevelManager.levelData[topRow][c])
                if ab == TILE.HIDDEN_WALL and not LevelManager.hiddenWallRevealed[ag] then
                    LevelManager.hiddenWallRevealed[ag] = true
                end
            end
        end
    end
    local bottomRow = gy + s
    if bottomRow <= Config.MAP_ROWS then
        for dx = 0, s - 1 do
            local c = gx + dx
            if c >= 1 and c <= Config.MAP_COLS then
                local ab, ag = Physics.GetTileType(LevelManager.levelData[bottomRow][c])
                if ab == TILE.HIDDEN_WALL and not LevelManager.hiddenWallRevealed[ag] then
                    LevelManager.hiddenWallRevealed[ag] = true
                end
            end
        end
    end

    return nil
end

return M
