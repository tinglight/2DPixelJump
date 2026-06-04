------------------------------------------------------------
-- editor/play/Movement.lua — 移动、跳跃、攀爬、重力
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")
local TileUtils = require("editor.TileUtils")

local Movement = {}

---@param M table PlayMode module
function Movement.Attach(M)

    function M.MoveOneGrid(dir)
        local newX = S.play.gridX + dir
        local gy = S.play.gridY

        -- 用忽略斜坡的碰撞检测（斜坡不阻挡玩家水平移动）
        if not M.CollidesIgnoreSlopes(newX, gy) then
            -- 平移成功
            S.play.gridX = newX

            -- 下坡贴合：移动后检查脚下是否有下坡方向的斜坡
            local s = M.PlayerGridSize()
            local feetRow = gy + s
            local shouldSnapDown = false
            for dx = 0, s - 1 do
                local slope = M.GetSlopeAt(S.play.gridX + dx, feetRow)
                if slope then
                    local _, isDown = M.PlaySlopeMovementType(slope, dir)
                    if isDown then shouldSnapDown = true; break end
                end
                -- 也检查玩家底行（正在斜坡内部）
                slope = M.GetSlopeAt(S.play.gridX + dx, gy + s - 1)
                if slope then
                    local _, isDown = M.PlaySlopeMovementType(slope, dir)
                    if isDown then shouldSnapDown = true; break end
                end
            end

            if shouldSnapDown then
                local downY = gy + 1
                if not M.CollidesIgnoreSlopes(S.play.gridX, downY) then
                    S.play.gridY = downY
                    -- 斜坡下降时减小火焰（与普通下落一致：下滑一格降低一格）
                    local stripCount = math.max(1, math.floor(S.playTotalPixels / 10 + 0.5))
                    M.StripPixels(stripCount)
                    S.play.fallGridCount = S.play.fallGridCount + 1
                    if S.play.fallGridCount >= S.playerParams.maxFallGrids then
                        S.play.alive = false
                        S.play.deathTimer = 0
                        return
                    end
                end
            end

            S.play.facingRight = (dir > 0)
            return
        end

        -- 平移被实体阻挡 → 检查是否有斜坡暗示上坡
        local s = M.PlayerGridSize()
        local hasUp = false
        -- 检查目标位置区域
        for dy = 0, s - 1 do
            for dx = 0, s - 1 do
                local slope = M.GetSlopeAt(newX + dx, gy + dy)
                if slope then
                    local u, _ = M.PlaySlopeMovementType(slope, dir)
                    if u then hasUp = true; break end
                end
            end
            if hasUp then break end
        end
        -- 检查当前位置脚下
        if not hasUp then
            local feetRow = gy + s
            for dx = 0, s - 1 do
                local slope = M.GetSlopeAt(S.play.gridX + dx, feetRow)
                if slope then
                    local u, _ = M.PlaySlopeMovementType(slope, dir)
                    if u then hasUp = true; break end
                end
                slope = M.GetSlopeAt(S.play.gridX + dx, gy + s - 1)
                if slope then
                    local u, _ = M.PlaySlopeMovementType(slope, dir)
                    if u then hasUp = true; break end
                end
            end
        end

        if hasUp then
            local upY = gy - 1
            if not M.CollidesIgnoreSlopes(newX, upY) then
                S.play.gridX = newX
                S.play.gridY = upY
                S.play.facingRight = (dir > 0)
                return
            end
        end

        -- 都失败，玩家被阻挡
        S.play.facingRight = (dir > 0)
    end

    function M.HandleMovementInput(dt)
        -- 攀爬中：只能在梯子范围内左右移动，不能移出梯子
        -- 例外：梯子顶端可以"翻上"旁边的平台（对角线上移+水平移动）
        if S.play.isClimbing then
            local curLeft = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
            local curRight = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)
            local dir = 0
            if curLeft and not curRight then dir = -1
            elseif curRight and not curLeft then dir = 1 end
            if dir ~= 0 then
                local newX = S.play.gridX + dir
                if not M.Collides(newX, S.play.gridY) then
                    if M.IsOnLadder(newX, S.play.gridY) then
                        -- 目标位置仍在梯子上，正常移动
                        S.play.gridX = newX
                        S.play.facingRight = (dir > 0)
                    elseif M.OnGround(newX, S.play.gridY) then
                        -- 目标位置不在梯子上但有地面支撑：走上平台，退出攀爬
                        S.play.gridX = newX
                        S.play.facingRight = (dir > 0)
                        S.play.isClimbing = false
                        S.play.climbTimer = 0
                        S.play.isOnGround = true
                    end
                else
                    -- 水平方向被平台实体阻挡：尝试对角线上移（翻上平台）
                    local upY = S.play.gridY - 1
                    if not M.Collides(newX, upY) and M.OnGround(newX, upY) then
                        -- 上移一格后可以水平移动且有地面支撑
                        S.play.gridX = newX
                        S.play.gridY = upY
                        S.play.facingRight = (dir > 0)
                        S.play.isClimbing = false
                        S.play.climbTimer = 0
                        S.play.isOnGround = true
                    end
                end
            end
            S.play.isMoving = false
            S.play.moveAnimTime = 0
            S.prevPlayLeft = curLeft
            S.prevPlayRight = curRight
            return
        end

        local curLeft = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
        local curRight = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)
        local dir = 0
        if curLeft and not curRight then dir = -1
        elseif curRight and not curLeft then dir = 1 end

        -- 黑水减速：增大移动间隔
        local moveTick = C.PLAY_MOVE_TICK
        if S.play.inBlackWater then
            moveTick = moveTick * C.BLACK_WATER_SPEED_MULT
        end

        if dir ~= 0 then
            local justPressed = (dir == -1 and not S.prevPlayLeft) or (dir == 1 and not S.prevPlayRight)
            if justPressed then
                M.MoveOneGrid(dir)
                S.play.moveTimer = 0
                S.playMoveFirst = true
            else
                S.play.moveTimer = S.play.moveTimer + dt
                if S.play.moveTimer >= moveTick then
                    S.play.moveTimer = S.play.moveTimer - moveTick
                    M.MoveOneGrid(dir)
                end
            end
            S.play.isMoving = true
            S.play.moveAnimTime = S.play.moveAnimTime + dt
        else
            S.play.moveTimer = 0
            S.playMoveFirst = false
            S.play.isMoving = false
            S.play.moveAnimTime = 0
        end
        S.prevPlayLeft = curLeft
        S.prevPlayRight = curRight
    end

    function M.HandleJumpInput()
        if input:GetKeyPress(KEY_SPACE) then
            -- 在梯子范围内一律禁止跳跃（无论是否处于攀爬状态）
            if S.play.isOnGround and not S.play.isJumping and not S.play.isClimbing
                and not M.IsOnLadder(S.play.gridX, S.play.gridY) then
                S.play.isJumping = true
                S.play.jumpGridsRemain = M.CalcJump()
                S.play.isOnGround = false
                S.play.jumpTimer = 0
            end
        end
    end

    function M.HandleClimbInput(dt)
        local onLadder = M.IsOnLadder(S.play.gridX, S.play.gridY)
        local onGround = M.OnGround(S.play.gridX, S.play.gridY)
        local pressUp = input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP)
        local pressDown = input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN)

        if onLadder then
            -- 在梯子上且脚踏地面：退出攀爬（除非按上键要往上爬）
            if onGround and not pressUp then
                if S.play.isClimbing then
                    S.play.isClimbing = false
                    S.play.climbTimer = 0
                end
                return
            end

            -- 在梯子上且不在地面（或按了上键）：只有按上/下才进入攀爬
            if not S.play.isClimbing then
                if pressUp or pressDown then
                    S.play.isClimbing = true
                    S.play.isJumping = false
                    S.play.jumpGridsRemain = 0
                    S.play.fallTickCurrent = C.PLAY_FALL_BASE
                    M.SyncFallGridCount()
                    S.play.climbTimer = 0
                else
                    -- 没按方向键：不自动进入攀爬（站在梯子顶端可以正常站立）
                    return
                end
            end

            -- 只有按上/下才移动
            if pressUp or pressDown then
                S.play.climbTimer = S.play.climbTimer + dt
                if S.play.climbTimer >= C.PLAY_CLIMB_TICK then
                    S.play.climbTimer = S.play.climbTimer - C.PLAY_CLIMB_TICK
                    local dir = pressUp and -1 or 1
                    local newY = S.play.gridY + dir
                    if not M.Collides(S.play.gridX, newY) then
                        S.play.gridY = newY
                        -- 移动后超出梯子范围：检查是否有地面支撑
                        if not M.IsOnLadder(S.play.gridX, newY) then
                            if M.OnGround(S.play.gridX, newY) then
                                -- 有地面支撑：退出攀爬，站在平台上
                                S.play.isClimbing = false
                                S.play.climbTimer = 0
                                S.play.isOnGround = true
                            else
                                -- 无地面支撑：保持攀爬状态，不要退出（否则重力会拉回）
                                -- 玩家可以通过水平移动走上旁边的平台
                            end
                        end
                    end
                end
            else
                S.play.climbTimer = 0
            end
        else
            -- 离开梯子区域
            if S.play.isClimbing then
                -- 刚从攀爬退出（爬到梯子顶端上方）
                S.play.isClimbing = false
                S.play.climbTimer = 0
                -- 检查脚下是否有梯子：梯子顶部作为地面支撑
                local s = M.PlayerGridSize()
                local feetRow = S.play.gridY + s
                for dx = 0, s - 1 do
                    local col = S.play.gridX + dx
                    if col >= 1 and col <= S.MAP_COLS and feetRow >= 1 and feetRow <= S.MAP_ROWS then
                        local val = S.levelData[feetRow][col]
                        local base = TileUtils.GetTileType(val)
                        if base == C.TILE.LADDER then
                            S.play.isOnGround = true
                            break
                        end
                    end
                end
            elseif pressDown and not S.play.isClimbing then
                -- 站在梯子顶部上方按下键：向下移入梯子，进入攀爬
                local s = M.PlayerGridSize()
                local feetRow = S.play.gridY + s
                local ladderBelow = false
                for dx = 0, s - 1 do
                    local col = S.play.gridX + dx
                    if col >= 1 and col <= S.MAP_COLS and feetRow >= 1 and feetRow <= S.MAP_ROWS then
                        local val = S.levelData[feetRow][col]
                        local base = TileUtils.GetTileType(val)
                        if base == C.TILE.LADDER then ladderBelow = true; break end
                    end
                end
                if ladderBelow then
                    local newY = S.play.gridY + 1
                    if not M.Collides(S.play.gridX, newY) then
                        S.play.gridY = newY
                        S.play.isClimbing = true
                        S.play.isJumping = false
                        S.play.jumpGridsRemain = 0
                        S.play.fallTickCurrent = C.PLAY_FALL_BASE
                        M.SyncFallGridCount()
                        S.play.climbTimer = 0
                        S.play.isOnGround = false
                    end
                end
            end
        end
    end

    function M.UpdateVerticalPhysics(dt)
        if S.play.isClimbing then return end -- 攀爬中不受重力影响
        if S.play.isJumping and S.play.jumpGridsRemain > 0 then
            M.ProcessJumpTick(dt)
        else
            M.ProcessFallTick(dt)
        end
    end

    function M.ProcessJumpTick(dt)
        S.play.jumpTimer = S.play.jumpTimer + dt
        if S.play.jumpTimer >= C.PLAY_JUMP_TICK then
            S.play.jumpTimer = 0
            local newY = S.play.gridY - 1
            if not M.Collides(S.play.gridX, newY) then
                S.play.gridY = newY
                S.play.jumpGridsRemain = S.play.jumpGridsRemain - 1
            else
                S.play.jumpGridsRemain = 0
            end
        end
        if S.play.jumpGridsRemain <= 0 then
            S.play.isJumping = false
            S.play.fallTickCurrent = C.PLAY_FALL_BASE
        end
    end

    function M.ProcessFallTick(dt)
        if not M.OnGround(S.play.gridX, S.play.gridY) then
            -- 在梯子范围内：
            if M.IsOnLadder(S.play.gridX, S.play.gridY) then
                if S.play.isClimbing then
                    -- 已经在攀爬状态：保持攀爬，不掉落
                    return
                end
                -- 未在攀爬状态（如从平台走到梯子顶端上方）：视为站在梯子顶部，不掉落也不自动进入攀爬
                S.play.isOnGround = true
                S.play.fallTimer = 0
                S.play.fallAnimTime = 0
                return
            end
            -- 脚下紧贴梯子顶部（玩家2x2区域在梯子正上方）：梯子顶部作为地面支撑
            local s = M.PlayerGridSize()
            local feetRow = S.play.gridY + s
            local ladderBelow = false
            for dx = 0, s - 1 do
                local col = S.play.gridX + dx
                if col >= 1 and col <= S.MAP_COLS and feetRow >= 1 and feetRow <= S.MAP_ROWS then
                    local val = S.levelData[feetRow][col]
                    local base = TileUtils.GetTileType(val)
                    if base == C.TILE.LADDER then ladderBelow = true; break end
                end
            end
            if ladderBelow then
                S.play.isOnGround = true
                S.play.fallTimer = 0
                S.play.fallAnimTime = 0
                return
            end
            S.play.isOnGround = false
            S.play.fallTimer = S.play.fallTimer + dt
            S.play.fallAnimTime = S.play.fallAnimTime + dt
            if S.play.fallTimer >= S.play.fallTickCurrent then
                S.play.fallTimer = 0
                M.ApplyFallOneGrid()
            end
        else
            S.play.isOnGround = true
            S.play.isJumping = false
            S.play.fallTickCurrent = C.PLAY_FALL_BASE
            S.play.fallAnimTime = 0
        end
    end

    function M.ApplyFallOneGrid()
        local newY = S.play.gridY + 1
        if newY > S.MAP_ROWS then
            if S.editorMode == C.MODE_WORLDPLAY then
                -- 有下方连接的关卡时，保持在底部等待过渡
                local targetFile = M.WorldPlayFindConnection("down")
                if targetFile then
                    S.play.gridY = S.MAP_ROWS
                    return
                end
            end
            -- 单关卡或无连接：坠落死亡
            S.play.alive = false
            S.play.deathTimer = 0
            return
        end
        if not M.Collides(S.play.gridX, newY) then
            S.play.gridY = newY
            -- 落到梯子上：立即进入攀爬，不扣能量
            if M.IsOnLadder(S.play.gridX, newY) then
                S.play.isClimbing = true
                S.play.isJumping = false
                S.play.fallTickCurrent = C.PLAY_FALL_BASE
                M.SyncFallGridCount()
                S.play.fallTimer = 0
                S.play.fallAnimTime = 0
                S.play.climbTimer = 0
                return
            end
            S.play.fallTickCurrent = math.max(C.PLAY_FALL_MIN, S.play.fallTickCurrent - C.PLAY_FALL_ACCEL)
            S.play.fallGridCount = S.play.fallGridCount + 1
            if S.play.fallGridCount >= S.playerParams.maxFallGrids then
                S.play.alive = false
                S.play.deathTimer = 0
                return
            end
            local stripCount = math.max(1, math.floor(S.playTotalPixels / 10 + 0.5))
            M.StripPixels(stripCount)
        else
            S.play.isOnGround = true
            S.play.fallTickCurrent = C.PLAY_FALL_BASE
            S.play.fallAnimTime = 0
        end
    end

    function M.UpdateGroundRecovery(dt)
        if not S.play.isOnGround and not S.play.isClimbing then return end
        if S.playAlivePixels >= S.playTotalPixels then return end
        local recoverCount = math.floor(C.PLAY_RECOVER_PER_SEC * dt + 0.5)
        if recoverCount >= 1 then
            M.RecoverPixels(recoverCount)
            M.SyncFallGridCount()
        end
    end

end

return Movement
