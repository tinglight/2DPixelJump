------------------------------------------------------------
-- PlayMode.lua — 试玩模式物理与状态管理
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")
local TileUtils = require("editor.TileUtils")
local FlameRenderer = require("editor.FlameRenderer")
local Undo = require("editor.UndoSystem")
local CrossLevel = require("editor.CrossLevel")
local SolidRenderer = require("SolidRenderer")

local M = {}

-- 依赖注入（延迟加载避免循环引用）
local FogOfWar, CloudStorage, WorldMapEditor, LevelGenerator
local cjson

---@param deps table { FogOfWar, CloudStorage, WorldMapEditor, LevelGenerator, cjson }
function M.Inject(deps)
    FogOfWar = deps.FogOfWar
    CloudStorage = deps.CloudStorage
    WorldMapEditor = deps.WorldMapEditor
    LevelGenerator = deps.LevelGenerator
    cjson = deps.cjson
end

------------------------------------------------------------
-- 像素系统
------------------------------------------------------------

function M.InitPlayPixels()
    S.pixelState = {}
    S.playTotalPixels = 0
    local N = C.FLAME_CFG.pixelGridSize
    for row = 1, N do
        S.pixelState[row] = {}
        for col = 1, N do
            if C.CHAR_SHAPE[row][col] == 1 then
                S.pixelState[row][col] = true
                S.playTotalPixels = S.playTotalPixels + 1
            else
                S.pixelState[row][col] = false
            end
        end
    end
    S.playAlivePixels = S.playTotalPixels
    M.BuildStripOrder()
end

function M.BuildStripOrder()
    local N = C.FLAME_CFG.pixelGridSize
    local cx = (N + 1) / 2
    S.stripOrder = {}
    for row = 1, N do
        for col = 1, N do
            if C.CHAR_SHAPE[row][col] == 1 then
                local hDist = math.abs(col - cx)
                local vWeight = (N - row) * 0.1
                table.insert(S.stripOrder, { row = row, col = col, priority = hDist + vWeight })
            end
        end
    end
    table.sort(S.stripOrder, function(a, b) return a.priority > b.priority end)
end

function M.StripPixels(n)
    local stripped = 0
    for _, p in ipairs(S.stripOrder) do
        if stripped >= n then break end
        if S.pixelState[p.row][p.col] then
            S.pixelState[p.row][p.col] = false
            S.playAlivePixels = S.playAlivePixels - 1
            stripped = stripped + 1
        end
    end
end

function M.RecoverPixels(n)
    local recovered = 0
    for i = #S.stripOrder, 1, -1 do
        if recovered >= n then break end
        local p = S.stripOrder[i]
        if not S.pixelState[p.row][p.col] then
            S.pixelState[p.row][p.col] = true
            S.playAlivePixels = S.playAlivePixels + 1
            recovered = recovered + 1
        end
    end
end

------------------------------------------------------------
-- 碰撞与地形判定
------------------------------------------------------------

function M.PlayerGridSize()
    local totalPx = C.FLAME_CFG.pixelGridSize * C.FLAME_CFG.pixelSize
    return math.ceil(totalPx / C.GRID)
end

function M.IsSolid(col, row)
    if col < 1 or col > S.MAP_COLS then return true end
    if row < 1 then return false end
    if row > S.MAP_ROWS then return true end
    local val = S.levelData[row][col]
    local base, group = TileUtils.GetTileType(val)
    if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR then return true end
    if base == C.TILE.GATE and not S.play.switchState[group] then return true end
    if base == C.TILE.HIDDEN_WALL and not S.play.hiddenWallRevealed[group] then return true end
    return false
end

--- 检测玩家是否在梯子上（任意身体格子重叠梯子）
function M.IsOnLadder(gx, gy)
    local s = M.PlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            local col = gx + dx
            local row = gy + dy
            if col >= 1 and col <= S.MAP_COLS and row >= 1 and row <= S.MAP_ROWS then
                local val = S.levelData[row][col]
                local base = TileUtils.GetTileType(val)
                if base == C.TILE.LADDER then return true end
            end
        end
    end
    return false
end

function M.OnGround(gx, gy)
    local s = M.PlayerGridSize()
    local feetRow = gy + s
    for dx = 0, s - 1 do
        if M.IsSolid(gx + dx, feetRow) then return true end
    end
    return false
end

function M.Collides(gx, gy)
    local s = M.PlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            if M.IsSolid(gx + dx, gy + dy) then return true end
        end
    end
    return false
end

------------------------------------------------------------
-- 道具与陷阱检测
------------------------------------------------------------

function M.CheckTilesOverlap()
    -- 每帧重置水状态标志（由 ProcessTileAt 重新设置）
    S.play.inWater = false
    S.play.inBlackWater = false

    local s = M.PlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            local col = S.play.gridX + dx
            local row = S.play.gridY + dy
            M.ProcessTileAt(col, row)
        end
    end
end

function M.ProcessTileAt(col, row)
    if col < 1 or col > S.MAP_COLS or row < 1 or row > S.MAP_ROWS then return end
    local val = S.levelData[row][col]
    local base, group = TileUtils.GetTileType(val)
    local key = row .. "_" .. col

    if base == C.TILE.SPIKE or base == C.TILE.POISON_WATER then
        S.play.alive = false
        S.play.deathTimer = 0
    elseif base == C.TILE.WATER then
        S.play.inWater = true
    elseif base == C.TILE.BLACK_WATER then
        S.play.inBlackWater = true
    elseif base == C.TILE.GOAL then
        S.play.won = true
    elseif base == C.TILE.FUEL and not S.play.collected[key] then
        S.play.collected[key] = true
        M.RecoverPixels(math.floor(S.playTotalPixels * 0.4))
        M.SyncFallGridCount()
        M.ShowBonfireMessage()
    elseif base == C.TILE.SWITCH and not S.play.collected[key] then
        S.play.collected[key] = true
        S.play.switchState[group] = not S.play.switchState[group]
        -- 记录到跨关卡状态（世界试玩模式）
        if S.editorMode == C.MODE_WORLDPLAY and S.worldPlayCurrentFile then
            CrossLevel.ActivateCrossSwitch(S.worldPlayCurrentFile, group)
        end
    elseif base == C.TILE.HIDDEN_WALL and not S.play.hiddenWallRevealed[group] then
        S.play.hiddenWallRevealed[group] = true
    elseif base == C.TILE.CHECKPOINT and not S.checkpointActivated[key] then
        -- 移除之前篝火的光源（带渐出动画）
        if S.checkpointLightPos then
            FogOfWar.RemoveLightAnimated(S.checkpointLightPos.col, S.checkpointLightPos.row)
        end
        -- 熄灭所有其他篝火，激活当前
        S.checkpointActivated = {}
        S.checkpointActivated[key] = true
        S.checkpointCol = col
        S.checkpointRow = row
        -- 世界试玩模式记录关卡文件名
        if S.editorMode == C.MODE_WORLDPLAY and S.worldPlayCurrentFile then
            S.checkpointFile = S.worldPlayCurrentFile
        else
            S.checkpointFile = S.currentLevelName or nil
        end
        -- 为篝火添加战争迷雾光源（直径35，带渐入动画，不显示提灯图片）
        local lightIdx = FogOfWar.AddLightAnimated(col, row, 35, 0.5)
        local light = FogOfWar.GetLight(lightIdx)
        if light then light.noLantern = true end
        S.checkpointLightPos = { col = col, row = row }
        S.lightSources = FogOfWar.GetLightSources()
        -- 补满火焰值
        M.RecoverPixels(S.playTotalPixels)
        M.SyncFallGridCount()
        S.SetMessage("篝火点燃! 火焰已补满!", 1.5)
    end
end

function M.SyncFallGridCount()
    local pixelsPerGrid = math.max(1, math.floor(S.playTotalPixels / 10 + 0.5))
    S.play.fallGridCount = math.max(0, math.floor((S.playTotalPixels - S.playAlivePixels) / pixelsPerGrid))
end

function M.CheckAdjacentHiddenWalls()
    local s = M.PlayerGridSize()
    local gx, gy = S.play.gridX, S.play.gridY
    M.RevealHiddenRow(gx, gy - 1, s, true)
    M.RevealHiddenRow(gx, gy + s, s, true)
    M.RevealHiddenCol(gx - 1, gy, s)
    M.RevealHiddenCol(gx + s, gy, s)
end

function M.RevealHiddenRow(startCol, row, count, isHorizontal)
    for dx = 0, count - 1 do
        local col = startCol + dx
        if col >= 1 and col <= S.MAP_COLS and row >= 1 and row <= S.MAP_ROWS then
            local ab, ag = TileUtils.GetTileType(S.levelData[row][col])
            if ab == C.TILE.HIDDEN_WALL and not S.play.hiddenWallRevealed[ag] then
                S.play.hiddenWallRevealed[ag] = true
            end
        end
    end
end

function M.RevealHiddenCol(col, startRow, count)
    for dy = 0, count - 1 do
        local row = startRow + dy
        if col >= 1 and col <= S.MAP_COLS and row >= 1 and row <= S.MAP_ROWS then
            local ab, ag = TileUtils.GetTileType(S.levelData[row][col])
            if ab == C.TILE.HIDDEN_WALL and not S.play.hiddenWallRevealed[ag] then
                S.play.hiddenWallRevealed[ag] = true
            end
        end
    end
end

function M.CheckTiles()
    M.CheckTilesOverlap()
    M.CheckAdjacentHiddenWalls()
end

------------------------------------------------------------
-- 跳跃计算
------------------------------------------------------------

function M.CalcJump()
    local baseJump = S.playerParams.baseJumpGrids
    local bonus = S.play.fallGridCount * S.playerParams.fallJumpMultiplier
    local jump = math.floor(baseJump + bonus + 0.5)
    -- maxJumpGrids = 0 表示无上限
    if S.playerParams.maxJumpGrids > 0 then
        jump = math.min(jump, S.playerParams.maxJumpGrids)
    end
    return jump
end

------------------------------------------------------------
-- 移动
------------------------------------------------------------

function M.MoveOneGrid(dir)
    local newX = S.play.gridX + dir
    if not M.Collides(newX, S.play.gridY) then
        S.play.gridX = newX
    end
    S.play.facingRight = (dir > 0)
end

------------------------------------------------------------
-- 篝火光源清理（所有退出试玩路径共用）
------------------------------------------------------------

--- 清理篝火光源和存档点状态
local function CleanupCheckpointLight()
    if S.checkpointLightPos then
        FogOfWar.RemoveLight(S.checkpointLightPos.col, S.checkpointLightPos.row)
        S.checkpointLightPos = nil
    end
    S.checkpointActivated = {}
    S.checkpointFile = nil
    S.checkpointCol = nil
    S.checkpointRow = nil
end

------------------------------------------------------------
-- 帧更新
------------------------------------------------------------

function M.Update(dt)
    -- 死亡中由 deathPhase 自行处理 ESC，此处跳过
    if not S.play.alive then
        FogOfWar.UpdateTweens(dt)
        M.UpdateDeathRespawn(dt)
        M.UpdateBonfireMessage(dt)
        return
    end

    if input:GetKeyPress(KEY_ESCAPE) then
        -- 退出试玩：清理篝火光源和存档点状态
        CleanupCheckpointLight()
        if S.editorMode == C.MODE_PLAY then
            S.editorMode = C.MODE_EDIT
            S.SetMessage("返回编辑模式", 1.5)
            return
        elseif S.editorMode == C.MODE_WORLDPLAY then
            S.editorMode = C.MODE_WORLDMAP
            WorldMapEditor.SetLayout(S.screenDesignW, S.screenDesignH, C.TOPBAR_H, 0, S.sidebarOpen and C.SIDEBAR_W or 0)
            S.SetMessage("返回世界地图编辑", 1.5)
            return
        end
    end
    if S.play.won then return end

    S.playGameTime = S.playGameTime + dt
    M.UpdateFlameTime(dt)
    M.UpdateTipPixels(dt)
    M.UpdateFallParticles(dt)
    M.HandleMovementInput(dt)
    M.HandleClimbInput(dt)
    M.HandleJumpInput()
    M.HandleProjectileInput()
    M.UpdateVerticalPhysics(dt)
    M.UpdateGroundRecovery(dt)
    CrossLevel.Update(dt)
    M.UpdateBonfireMessage(dt)

    if S.playAlivePixels <= 0 then
        S.play.alive = false
        S.play.deathTimer = 0
    end
    M.CheckTiles()

    -- 普通水：持续消耗能量
    if S.play.inWater and S.play.alive then
        S.play.waterDrainAccum = (S.play.waterDrainAccum or 0) + C.WATER_ENERGY_DRAIN_PER_SEC * dt
        if S.play.waterDrainAccum >= 1.0 then
            local drain = math.floor(S.play.waterDrainAccum)
            S.play.waterDrainAccum = S.play.waterDrainAccum - drain
            M.StripPixels(drain)
            M.SyncFallGridCount()
        end
    else
        S.play.waterDrainAccum = 0
    end

    FogOfWar.UpdateTweens(dt)
    M.UpdateCamera(dt)
end

function M.HandleProjectileInput()
    if input:GetKeyPress(KEY_E) then
        CrossLevel.LaunchProjectile(S.play.gridX, S.play.gridY, S.play.facingRight)
    end
end

function M.UpdateFlameTime(dt)
    S.flameTime = S.flameTime + dt
    S.flameAnimTimer = S.flameAnimTimer + dt
    local frameInterval = 1.0 / C.FLAME_ANIM_FPS
    if S.flameAnimTimer >= frameInterval then
        S.flameAnimTimer = S.flameAnimTimer - frameInterval
        S.flameAnimFrame = S.flameAnimFrame + 1
    end
end

function M.UpdateTipPixels(dt)
    local N = C.FLAME_CFG.pixelGridSize
    S.tipSpawnTimer = S.tipSpawnTimer + dt
    local spawnInterval = M.GetTipSpawnInterval()

    if S.tipSpawnTimer >= spawnInterval and #S.tipPixels < 6 then
        S.tipSpawnTimer = 0
        M.SpawnTipPixel(N)
    end
    M.AgeTipPixels(dt)
end

function M.GetTipSpawnInterval()
    if not S.play.isOnGround and not S.play.isJumping then return 0.06 end
    if S.play.isMoving then return 0.08 end
    return 0.15
end

function M.SpawnTipPixel(N)
    local candidates = {}
    for col = 1, N do
        if S.pixelState[1][col] then
            table.insert(candidates, col)
        elseif S.pixelState[2] and S.pixelState[2][col] then
            table.insert(candidates, col)
        end
    end
    if #candidates == 0 then return end
    local srcCol = candidates[math.random(#candidates)]
    local life = 0.3 + math.random() * 0.4
    table.insert(S.tipPixels, {
        col = srcCol, row = 0,
        offX = math.random(-1, 1),
        offY = -math.random(1, 2),
        life = life, maxLife = life,
        phase = math.random() * 6.28,
        colorRow = math.random(1, 2),
    })
end

function M.AgeTipPixels(dt)
    local i = 1
    while i <= #S.tipPixels do
        local tp = S.tipPixels[i]
        tp.life = tp.life - dt
        if math.random() < dt * 4 then
            tp.offX = tp.offX + (math.random() > 0.5 and 1 or -1)
            tp.offX = math.max(-2, math.min(2, tp.offX))
        end
        if math.random() < dt * 3 then
            tp.offY = tp.offY - 1
        end
        if tp.life <= 0 then
            table.remove(S.tipPixels, i)
        else
            i = i + 1
        end
    end
end

function M.UpdateFallParticles(dt)
    local isFalling = not S.play.isOnGround and not S.play.isJumping
    if isFalling and S.playAlivePixels < S.playTotalPixels then
        M.SpawnFallParticles()
    end
    M.AgeFallParticles(dt)
end

function M.SpawnFallParticles()
    local consumeRatio = 1.0 - S.playAlivePixels / math.max(1, S.playTotalPixels)
    local baseRatio = math.max(0.15, consumeRatio)
    local maxP = math.floor(4 + baseRatio * 14)
    local spawnChance = 0.40 + baseRatio * 0.50
    local attempts = 1 + math.floor(baseRatio * 2)
    local groundY = M.FindGroundY()
    local pPS = C.FLAME_CFG.pixelSize
    local totalSize = C.FLAME_CFG.pixelGridSize * pPS

    for _ = 1, attempts do
        if math.random() < spawnChance and #S.playFallParticles < maxP then
            M.EmitFallParticle(totalSize, pPS, groundY, consumeRatio)
        end
    end
end

function M.FindGroundY()
    local playerS = M.PlayerGridSize()
    local feetGridY = S.play.gridY + playerS
    local groundGridY = feetGridY
    for searchY = feetGridY, S.MAP_ROWS do
        if M.IsSolid(S.play.gridX, searchY) then
            groundGridY = searchY
            break
        end
        if searchY == S.MAP_ROWS then groundGridY = S.MAP_ROWS + 1 end
    end
    return (groundGridY - 1) * C.GRID
end

function M.EmitFallParticle(totalSize, pPS, groundY, consumeRatio)
    local worldX = (S.play.gridX - 1) * C.GRID
    local baseY = (S.play.gridY - 1) * C.GRID
    local side = math.random() > 0.5 and 1 or -1
    local emitX = worldX + totalSize * 0.5 + side * (totalSize * 0.3 + math.random() * totalSize * 0.2)
    local emitY = baseY + totalSize * (0.3 + math.random() * 0.5)
    local speedMul = 0.7 + consumeRatio * 0.6
    local life = 1.2 + consumeRatio * 0.6 + math.random() * 0.3
    table.insert(S.playFallParticles, {
        x = emitX, y = emitY,
        vx = side * (30 + math.random() * 40) * speedMul,
        vy = -(20 + math.random() * 30) * speedMul,
        life = life, maxLife = life, size = pPS,
        gravity = 120 + math.random() * 40,
        colorRow = math.random(5, 10),
        groundY = groundY,
        bounces = 0, maxBounces = 1 + math.floor(math.random() * 2),
    })
end

function M.AgeFallParticles(dt)
    local i = 1
    while i <= #S.playFallParticles do
        local p = S.playFallParticles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(S.playFallParticles, i)
        else
            p.vy = p.vy + p.gravity * dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            if p.y >= p.groundY and p.vy > 0 then
                if p.bounces < p.maxBounces then
                    p.vy = -p.vy * 0.4
                    p.vx = p.vx * 0.6
                    p.y = p.groundY
                    p.bounces = p.bounces + 1
                else
                    p.y = p.groundY
                    p.vy = 0
                    p.vx = p.vx * 0.9
                end
            end
            i = i + 1
        end
    end
end

function M.HandleMovementInput(dt)
    -- 梯子上禁止左右移动，只有接触地面才能水平移动
    if S.play.isClimbing then
        S.play.isMoving = false
        S.play.moveAnimTime = 0
        S.prevPlayLeft = false
        S.prevPlayRight = false
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
        if S.play.isOnGround and not S.play.isJumping and not S.play.isClimbing then
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

        -- 在梯子上且不在地面（或按了上键）：进入攀爬状态
        if not S.play.isClimbing then
            S.play.isClimbing = true
            S.play.isJumping = false
            S.play.jumpGridsRemain = 0
            S.play.fallTickCurrent = C.PLAY_FALL_BASE
            S.play.fallGridCount = 0
            S.play.climbTimer = 0
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
                end
            end
        else
            S.play.climbTimer = 0
        end
    else
        -- 离开梯子区域，退出攀爬
        if S.play.isClimbing then
            S.play.isClimbing = false
            S.play.climbTimer = 0
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

function M.UpdateCamera(dt)
    local zoom = S.playerParams.cameraZoom or 1.0

    -- 水平跟随
    local boundLeftPx = (S.camBound.left - 1) * C.GRID
    local boundRightPx = S.camBound.right * C.GRID
    local viewW = S.playViewW * zoom
    local camMinX = boundLeftPx
    local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)
    local targetCamX = (S.play.gridX - 1) * C.GRID - viewW * 0.35
    targetCamX = math.max(camMinX, math.min(targetCamX, camMaxX))
    S.playCameraX = S.playCameraX + (targetCamX - S.playCameraX) * math.min(1, dt * 8)

    -- 垂直跟随
    local boundTopPx = (S.camBound.top - 1) * C.GRID
    local boundBottomPx = S.camBound.bottom * C.GRID
    local viewH = S.playViewH * zoom
    local camMinY = boundTopPx
    local camMaxY = math.max(boundTopPx, boundBottomPx - viewH)
    local targetCamY = (S.play.gridY - 1) * C.GRID - viewH * 0.5
    targetCamY = math.max(camMinY, math.min(targetCamY, camMaxY))
    S.playCameraY = S.playCameraY + (targetCamY - S.playCameraY) * math.min(1, dt * 8)
end

------------------------------------------------------------
-- 世界试玩模式
------------------------------------------------------------

function M.WorldPlayLoadLevel(filename, fromDirection, prevGx, prevGy)
    local json = CloudStorage.Load(filename)
    if not json then return false end
    local ok2, data = pcall(cjson.decode, json)
    if not ok2 or not data then return false end
    M.ApplyWorldLevelData(data)
    M.PositionPlayerOnEntry(fromDirection, prevGx, prevGy)
    M.SnapCameraToPlayer()
    S.worldPlayCurrentFile = filename
    S.worldPlayCooldown = 0.5
    return true
end

function M.ApplyWorldLevelData(data)
    -- 先更新地图尺寸（关键！不同关卡可能有不同尺寸）
    if data.cols and data.cols >= 10 then S.MAP_COLS = data.cols end
    if data.rows and data.rows >= 5 then S.MAP_ROWS = data.rows end

    -- 用新尺寸重建 levelData
    S.levelData = {}
    for row = 1, S.MAP_ROWS do
        S.levelData[row] = {}
        for col = 1, S.MAP_COLS do
            S.levelData[row][col] = C.TILE.EMPTY
        end
    end
    if data.spawn then
        S.spawnCol = data.spawn.col or 3
        S.spawnRow = data.spawn.row or (S.MAP_ROWS - 3)
        S.levelData[S.spawnRow][S.spawnCol] = C.TILE.SPAWN
    end
    if data.tiles then
        for _, t in ipairs(data.tiles) do
            if t.row >= 1 and t.row <= S.MAP_ROWS and t.col >= 1 and t.col <= S.MAP_COLS then
                S.levelData[t.row][t.col] = t.v
            end
        end
    end
    M.ApplyBound(data.camBound)

    -- 确保 MAP_COLS/MAP_ROWS 覆盖 camBound + 玩家尺寸，防止 IsSolid 在边界前挡住玩家
    local ps = M.PlayerGridSize()
    local needCols = S.camBound.right + ps - 1
    local needRows = S.camBound.bottom + ps - 1
    if needCols > S.MAP_COLS then
        local oldCols = S.MAP_COLS
        S.MAP_COLS = needCols
        for row = 1, S.MAP_ROWS do
            for col = oldCols + 1, S.MAP_COLS do
                S.levelData[row][col] = C.TILE.EMPTY
            end
        end
    end
    if needRows > S.MAP_ROWS then
        local oldRows = S.MAP_ROWS
        S.MAP_ROWS = needRows
        for row = oldRows + 1, S.MAP_ROWS do
            S.levelData[row] = {}
            for col = 1, S.MAP_COLS do
                S.levelData[row][col] = C.TILE.EMPTY
            end
        end
    end

    -- 世界试玩模式下不覆盖玩家参数，保持全局配置一致
    -- （全局 playerParams 已在 StartWorldPlayMode 时从 data/player_params.json 加载）

    -- 背景图
    S.backgroundImage = (data.backgroundImage and data.backgroundImage ~= "") and data.backgroundImage or ""
    S.bgImageHandle = nil  -- 切换关卡时清除缓存

    FogOfWar.Deserialize(data.lightSources)
    S.lightSources = FogOfWar.GetLightSources()
end

function M.ApplyBound(bound)
    if bound then
        S.camBound.left = bound.left or 1
        S.camBound.top = bound.top or 1
        S.camBound.right = bound.right or S.MAP_COLS
        S.camBound.bottom = bound.bottom or S.MAP_ROWS
    else
        S.camBound.left = 1
        S.camBound.top = 1
        S.camBound.right = S.MAP_COLS
        S.camBound.bottom = S.MAP_ROWS
    end
end

function M.ApplyParams(params)
    if params then
        S.playerParams.baseJumpGrids = params.baseJumpGrids or 3
        S.playerParams.fallJumpMultiplier = params.fallJumpMultiplier or 1.0
        S.playerParams.maxFallGrids = params.maxFallGrids or 10
        S.playerParams.maxJumpGrids = params.maxJumpGrids or 0
        S.playerParams.defaultLightDiameter = params.defaultLightDiameter or 12
        S.playerParams.cameraZoom = params.cameraZoom or 1.0
    else
        S.playerParams.baseJumpGrids = 3
        S.playerParams.fallJumpMultiplier = 1.0
        S.playerParams.maxFallGrids = 10
        S.playerParams.maxJumpGrids = 0
        S.playerParams.defaultLightDiameter = 12
        S.playerParams.cameraZoom = 1.0
    end
end

function M.PositionPlayerOnEntry(fromDirection, prevGx, prevGy)
    if fromDirection == "right" then
        S.play.gridX = S.camBound.right
        S.play.gridY = prevGy or (S.spawnRow - (C.PLAYER_GRID_H - 1))
    elseif fromDirection == "left" then
        S.play.gridX = S.camBound.left
        S.play.gridY = prevGy or (S.spawnRow - (C.PLAYER_GRID_H - 1))
    elseif fromDirection == "down" then
        S.play.gridX = prevGx or S.spawnCol
        S.play.gridY = S.camBound.bottom
    elseif fromDirection == "up" then
        S.play.gridX = prevGx or S.spawnCol
        S.play.gridY = S.camBound.top
    else
        S.play.gridX = S.spawnCol
        S.play.gridY = S.spawnRow - (C.PLAYER_GRID_H - 1)
    end
    S.play.gridX = math.max(1, math.min(S.play.gridX, S.MAP_COLS))
    S.play.gridY = math.max(1, math.min(S.play.gridY, S.MAP_ROWS))
end

function M.SnapCameraToPlayer()
    local zoom = S.playerParams.cameraZoom or 1.0

    -- 水平
    local boundLeftPx = (S.camBound.left - 1) * C.GRID
    local boundRightPx = S.camBound.right * C.GRID
    local viewW = S.playViewW * zoom
    local camMinX = boundLeftPx
    local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)
    local targetCamX = (S.play.gridX - 1) * C.GRID - viewW * 0.35
    S.playCameraX = math.max(camMinX, math.min(targetCamX, camMaxX))

    -- 垂直
    local boundTopPx = (S.camBound.top - 1) * C.GRID
    local boundBottomPx = S.camBound.bottom * C.GRID
    local viewH = S.playViewH * zoom
    local camMinY = boundTopPx
    local camMaxY = math.max(boundTopPx, boundBottomPx - viewH)
    local targetCamY = (S.play.gridY - 1) * C.GRID - viewH * 0.5
    S.playCameraY = math.max(camMinY, math.min(targetCamY, camMaxY))
end

function M.WorldPlayFindConnection(direction)
    if not S.worldPlayData or not S.worldPlayCurrentFile then return nil end
    local currentNodeId = nil
    for _, node in ipairs(S.worldPlayData.nodes) do
        if node.file == S.worldPlayCurrentFile then
            currentNodeId = node.id
            break
        end
    end
    if not currentNodeId then return nil end
    for _, conn in ipairs(S.worldPlayData.connections) do
        if conn.fromId == currentNodeId and conn.direction == direction then
            for _, node in ipairs(S.worldPlayData.nodes) do
                if node.id == conn.toId then return node.file end
            end
        end
    end
    return nil
end

function M.WorldPlayCheckBoundary()
    if S.worldPlayCooldown > 0 then return end
    if S.transition.active then return end
    local gx, gy = S.play.gridX, S.play.gridY
    local dir, fromDir = M.DetectBoundaryDirection(gx, gy)
    if not dir then return end
    local targetFile = M.WorldPlayFindConnection(dir)
    if targetFile then
        -- 启动过渡动画（先 fadeOut，加载完再 fadeIn）
        S.transition.active = true
        S.transition.phase = "fadeOut"
        S.transition.alpha = 0
        S.transition.pendingFile = targetFile
        S.transition.pendingDir = fromDir
        S.transition.pendingGx = gx
        S.transition.pendingGy = gy
    end
end

--- 更新关卡切换过渡动画（每帧调用）
function M.UpdateTransition(dt)
    if not S.transition.active then return end

    local t = S.transition
    if t.phase == "fadeOut" then
        t.alpha = t.alpha + t.speed * dt
        if t.alpha >= 1.0 then
            t.alpha = 1.0
            -- 全黑时执行实际关卡加载
            if t.pendingFile then
                if M.WorldPlayLoadLevel(t.pendingFile, t.pendingDir, t.pendingGx, t.pendingGy) then
                    CrossLevel.Clear()
                    S.tipPixels = {}
                    S.tipSpawnTimer = 0
                    S.playFallParticles = {}
                    S.play.fallGridCount = 0
                    S.play.fallTickCurrent = C.PLAY_FALL_BASE
                    S.play.collected = {}
                    S.play.switchState = {}
                    S.play.hiddenWallRevealed = {}
                    -- 在 switchState 重置后，重新应用跨关卡开关状态
                    CrossLevel.ApplyCrossSwitches(S.worldPlayCurrentFile)
                    S.SetMessage("进入: " .. t.pendingFile, 1.5)
                end
            end
            t.phase = "fadeIn"
            t.pendingFile = nil
            t.pendingDir = nil
            t.pendingGx = nil
            t.pendingGy = nil
        end
    elseif t.phase == "fadeIn" then
        t.alpha = t.alpha - t.speed * dt
        if t.alpha <= 0 then
            t.alpha = 0
            t.phase = "none"
            t.active = false
        end
    end
end

--- 绘制关卡切换过渡遮罩
function M.DrawTransition()
    if not S.transition.active then return end
    if S.transition.alpha <= 0 then return end
    local vg = S.vg
    local zoom = S.playerParams.cameraZoom or 1.0
    local w = S.playViewW * zoom
    local h = S.playViewH * zoom
    local a = math.floor(S.transition.alpha * 255)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
    nvgFill(vg)
end

function M.DetectBoundaryDirection(gx, gy)
    local pressLeft = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
    local pressRight = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)
    local ps = M.PlayerGridSize()
    if gx <= S.camBound.left and pressLeft then return "left", "right" end
    -- 玩家宽度为 ps 格，最右能到达 camBound.right - ps + 1
    if gx + ps - 1 >= S.camBound.right and pressRight then return "right", "left" end
    if gy <= S.camBound.top then return "up", "down" end
    if gy + ps - 1 >= S.camBound.bottom or gy >= S.MAP_ROWS then return "down", "up" end
    return nil, nil
end

------------------------------------------------------------
-- 启动函数
------------------------------------------------------------

local function ResetPlayState()
    CleanupCheckpointLight()
    S.play.gridX = S.spawnCol
    S.play.gridY = S.spawnRow - (C.PLAYER_GRID_H - 1)
    S.play.isOnGround = false
    S.play.isJumping = false
    S.play.jumpGridsRemain = 0
    S.play.facingRight = true
    S.play.moveTimer = 0
    S.play.fallTimer = 0
    S.play.fallTickCurrent = C.PLAY_FALL_BASE
    S.play.jumpTimer = 0
    S.play.fallGridCount = 0
    S.play.alive = true
    S.play.won = false
    S.play.deathTimer = 0
    M.deathPhase = nil
    M.deathPhaseTimer = 0
    M.bonfireMsg.active = false
    S.play.isMoving = false
    S.play.moveAnimTime = 0
    S.play.fallAnimTime = 0
    S.play.switchState = {}
    S.play.collected = {}
    S.play.hiddenWallRevealed = {}
    S.play.inWater = false
    S.play.inBlackWater = false
    S.play.waterDrainAccum = 0
    S.play.isClimbing = false
    S.play.climbTimer = 0
    S.prevPlayLeft = false
    S.prevPlayRight = false
    S.playMoveFirst = false
    S.playGameTime = 0
    S.flameAnimTimer = 0
    S.flameAnimFrame = 0
    S.flameTime = 0
    S.tipPixels = {}
    S.tipSpawnTimer = 0
    S.playFallParticles = {}
    local zoom = S.playerParams.cameraZoom or 1.0
    S.playCameraX = math.max(0, (S.spawnCol - 1) * C.GRID - S.playViewW * zoom * 0.35)
    -- 垂直初始化
    local boundTopPx = (S.camBound.top - 1) * C.GRID
    local boundBottomPx = S.camBound.bottom * C.GRID
    local viewH = S.playViewH * zoom
    local spawnY = (S.spawnRow - C.PLAYER_GRID_H) * C.GRID
    local camMaxY = math.max(boundTopPx, boundBottomPx - viewH)
    S.playCameraY = math.max(boundTopPx, math.min(spawnY - viewH * 0.5, camMaxY))
    M.InitPlayPixels()
end

------------------------------------------------------------
-- 死亡后自动复活（不重置已收集道具和开关状态）
------------------------------------------------------------

local CIRCLE_CLOSE_TIME = 0.6   -- 缩圈时间
local BLACKOUT_TIME = 0.3       -- 全黑停顿时间

function M.UpdateDeathRespawn(dt)
    S.play.deathTimer = S.play.deathTimer + dt

    -- 首帧启动 deathPhase
    if M.deathPhase == nil then
        M.deathPhase = "circleClose"
        M.deathPhaseTimer = 0
    end

    M.deathPhaseTimer = M.deathPhaseTimer + dt

    if M.deathPhase == "circleClose" then
        if M.deathPhaseTimer >= CIRCLE_CLOSE_TIME then
            M.deathPhase = "blackout"
            M.deathPhaseTimer = 0
        end
    elseif M.deathPhase == "blackout" then
        if M.deathPhaseTimer >= BLACKOUT_TIME then
            M.deathPhase = "waitKey"
            M.deathPhaseTimer = 0
        end
    elseif M.deathPhase == "waitKey" then
        -- 等待任意键按下
        if input:GetKeyPress(KEY_ESCAPE) then
            -- ESC 返回编辑
            CleanupCheckpointLight()
            M.deathPhase = nil
            M.deathPhaseTimer = 0
            if S.editorMode == C.MODE_WORLDPLAY then
                S.editorMode = C.MODE_WORLDMAP
                WorldMapEditor.SetLayout(S.screenDesignW, S.screenDesignH, C.TOPBAR_H, 0, S.sidebarOpen and C.SIDEBAR_W or 0)
            else
                S.editorMode = C.MODE_EDIT
            end
            return
        end
        -- 任意其他键 → 复活
        if input:GetNumTouches() > 0 or M.AnyKeyPressed() then
            M.deathPhase = nil
            M.deathPhaseTimer = 0
            M.Respawn()
        end
    end
end

--- 检测是否有任意键被按下（不含ESC，已在上面处理）
function M.AnyKeyPressed()
    for i = KEY_A, KEY_Z do
        if input:GetKeyPress(i) then return true end
    end
    if input:GetKeyPress(KEY_SPACE) then return true end
    if input:GetKeyPress(KEY_RETURN) then return true end
    if input:GetMouseButtonPress(MOUSEB_LEFT) then return true end
    if input:GetMouseButtonPress(MOUSEB_RIGHT) then return true end
    return false
end

function M.Respawn()
    -- 重置位置到重生点
    S.play.gridX = S.spawnCol
    S.play.gridY = S.spawnRow - (C.PLAYER_GRID_H - 1)
    -- 重置物理状态
    S.play.isOnGround = false
    S.play.isJumping = false
    S.play.isClimbing = false
    S.play.climbTimer = 0
    S.play.jumpGridsRemain = 0
    S.play.moveTimer = 0
    S.play.fallTimer = 0
    S.play.fallTickCurrent = C.PLAY_FALL_BASE
    S.play.jumpTimer = 0
    S.play.fallGridCount = 0
    S.play.isMoving = false
    S.play.moveAnimTime = 0
    S.play.fallAnimTime = 0
    -- 复活
    S.play.alive = true
    S.play.deathTimer = 0
    -- 重置输入记忆
    S.prevPlayLeft = false
    S.prevPlayRight = false
    S.playMoveFirst = false
    -- 恢复火焰像素
    M.InitPlayPixels()
    S.tipPixels = {}
    S.tipSpawnTimer = 0
    S.playFallParticles = {}
    -- 相机立即跟随到重生点
    M.SnapCameraToPlayer()
end

function M.StartPlayMode()
    S.editorMode = C.MODE_PLAY
    ResetPlayState()
    S.SetMessage("试玩中! ESC返回编辑", 2.0)
end

function M.StartWorldPlayMode()
    S.worldPlayData = WorldMapEditor.GetMapData()
    if not S.worldPlayData or not S.worldPlayData.nodes or #S.worldPlayData.nodes == 0 then
        S.SetMessage("世界地图为空，请先添加关卡节点", 3.0)
        return
    end
    local firstNode = S.worldPlayData.nodes[1]
    if not firstNode or not firstNode.file then
        S.SetMessage("首个节点无关卡文件", 3.0)
        return
    end
    if not M.WorldPlayLoadLevel(firstNode.file, nil) then
        S.SetMessage("加载关卡失败: " .. firstNode.file, 3.0)
        return
    end
    S.worldPlayCurrentFile = firstNode.file
    S.worldPlayCooldown = 0
    S.editorMode = C.MODE_WORLDPLAY
    ResetPlayState()
    CrossLevel.Reset()
    S.SetMessage("世界试玩中! ESC返回 | 到达边界自动切换关卡", 3.0)
end

------------------------------------------------------------
-- 随机关卡生成
------------------------------------------------------------

function M.GenerateRandomLevel()
    local diff = C.DIFFICULTIES[S.currentDifficulty]
    -- v2.1: 传入当前画布尺寸，不使用固定地图大小
    local map, sc, sr, templateName = LevelGenerator.GenerateValid(diff, 5, S.MAP_COLS, S.MAP_ROWS)
    for row = 1, S.MAP_ROWS do
        S.levelData[row] = {}
        for col = 1, S.MAP_COLS do
            if map[row] and map[row][col] then
                S.levelData[row][col] = map[row][col]
            else
                S.levelData[row][col] = C.TILE.EMPTY
            end
        end
    end
    S.spawnCol = sc
    S.spawnRow = sr
    S.camBound.left = 1
    S.camBound.top = 1
    S.camBound.right = S.MAP_COLS
    S.camBound.bottom = S.MAP_ROWS
    S.cameraX = 0
    S.currentLevelName = ""
    Undo.stack = {}
    Undo.currentAction = nil
    Undo.dirty = false
    Undo.saveTimer = 0
    FogOfWar.ClearAll()
    S.lightSources = FogOfWar.GetLightSources()
    S.selectedLightIndex = 0
    local diffName = C.DIFFICULTY_NAMES[diff] or diff
    S.SetMessage("随机[" .. diffName .. "] 模板:" .. templateName, 4.0)
end

function M.CycleDifficulty()
    S.currentDifficulty = S.currentDifficulty % #C.DIFFICULTIES + 1
    local diff = C.DIFFICULTIES[S.currentDifficulty]
    local diffName = C.DIFFICULTY_NAMES[diff]
    S.SetMessage("难度: " .. diffName, 2.0)
end

------------------------------------------------------------
-- 试玩模式渲染
------------------------------------------------------------

function M.Draw()
    local vg = S.vg
    M.DrawBackground(vg)
    local startCol, endCol = M.DrawGrid(vg)
    M.DrawTiles(vg, startCol, endCol)
    FlameRenderer.UpdateFlameAnim()
    FlameRenderer.Draw()
    CrossLevel.Draw(vg, S.playCameraX, S.playCameraY)
    M.DrawFogOfWar(vg, startCol, endCol)
    M.DrawHUD(vg)
    M.DrawOverlays(vg)
    M.DrawTransition()
end

function M.DrawBackground(vg)
    local zoom = S.playerParams.cameraZoom or 1.0
    local bgW = S.playViewW * zoom
    local bgH = S.playViewH * zoom
    local bg = nvgLinearGradient(vg, 0, 0, 0, bgH,
        nvgRGBA(10, 5, 20, 255), nvgRGBA(30, 15, 40, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, bgW, bgH)
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    -- 背景图铺满 camBound 区域
    if S.backgroundImage ~= "" then
        if not S.bgImageHandle then
            S.bgImageHandle = nvgCreateImage(vg, S.backgroundImage, 0)
        end
        if S.bgImageHandle and S.bgImageHandle > 0 then
            local bx = (S.camBound.left - 1) * C.GRID - S.playCameraX
            local by = (S.camBound.top - 1) * C.GRID - (S.playCameraY or 0)
            local bw = (S.camBound.right - S.camBound.left + 1) * C.GRID
            local bh = (S.camBound.bottom - S.camBound.top + 1) * C.GRID
            local imgPaint = nvgImagePattern(vg, bx, by, bw, bh, 0, S.bgImageHandle, S.bgImageAlpha or 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, bx, by, bw, bh)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        end
    end
end

function M.DrawGrid(vg)
    local zoom = S.playerParams.cameraZoom or 1.0
    local visibleW = S.playViewW * zoom
    local visibleH = S.playViewH * zoom
    local startCol = math.max(1, math.floor(S.playCameraX / C.GRID) + 1)
    local endCol = math.min(S.MAP_COLS, startCol + math.ceil(visibleW / C.GRID) + 2)
    local startRow = math.max(1, math.floor(S.playCameraY / C.GRID) + 1)
    local endRow = math.min(S.MAP_ROWS, startRow + math.ceil(visibleH / C.GRID) + 2)

    -- 细线
    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        local x = (col - 1) * C.GRID - S.playCameraX
        nvgMoveTo(vg, x, (startRow - 1) * C.GRID - S.playCameraY)
        nvgLineTo(vg, x, endRow * C.GRID - S.playCameraY)
    end
    for row = startRow, endRow + 1 do
        local y = (row - 1) * C.GRID - S.playCameraY
        nvgMoveTo(vg, (startCol - 1) * C.GRID - S.playCameraX, y)
        nvgLineTo(vg, endCol * C.GRID - S.playCameraX, y)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 15))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 每5格加粗
    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        if (col - 1) % 5 == 0 then
            local x = (col - 1) * C.GRID - S.playCameraX
            nvgMoveTo(vg, x, (startRow - 1) * C.GRID - S.playCameraY)
            nvgLineTo(vg, x, endRow * C.GRID - S.playCameraY)
        end
    end
    for row = startRow, endRow + 1 do
        if (row - 1) % 5 == 0 then
            local y = (row - 1) * C.GRID - S.playCameraY
            nvgMoveTo(vg, (startCol - 1) * C.GRID - S.playCameraX, y)
            nvgLineTo(vg, endCol * C.GRID - S.playCameraX, y)
        end
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 35))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    return startCol, endCol
end

function M.DrawTiles(vg, startCol, endCol)
    local zoom = S.playerParams.cameraZoom or 1.0
    local visibleH = S.playViewH * zoom
    local startRow = math.max(1, math.floor(S.playCameraY / C.GRID) + 1)
    local endRow = math.min(S.MAP_ROWS, startRow + math.ceil(visibleH / C.GRID) + 2)
    for row = startRow, endRow do
        for col = startCol, endCol do
            local val = S.levelData[row][col]
            if val ~= C.TILE.EMPTY and val ~= C.TILE.SPAWN then
                local px = (col - 1) * C.GRID - S.playCameraX
                local py = (row - 1) * C.GRID - S.playCameraY
                local base, group = TileUtils.GetTileType(val)
                M.DrawOneTile(vg, px, py, base, group, row, col)
            end
        end
    end
end

function M.DrawOneTile(vg, px, py, base, group, row, col)
    if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR then
        M.DrawSolidTileWithLight(vg, px, py, base, row, col)
    elseif base == C.TILE.FUEL then
        M.DrawFuelTile(vg, px, py, row, col)
    elseif base == C.TILE.GOAL then
        M.DrawGoalTile(vg, px, py)
    elseif base == C.TILE.SPIKE then
        M.DrawSpikeTile(vg, px, py)
    elseif base == C.TILE.SWITCH then
        M.DrawSwitchTile(vg, px, py, group, row, col)
    elseif base == C.TILE.GATE then
        M.DrawGateTile(vg, px, py, group)
    elseif base == C.TILE.HIDDEN_WALL then
        M.DrawHiddenWallTile(vg, px, py, group, row, col)
    elseif base == C.TILE.WATER then
        M.DrawWaterTile(vg, px, py, row, col)
    elseif base == C.TILE.POISON_WATER then
        M.DrawPoisonWaterTile(vg, px, py, row, col)
    elseif base == C.TILE.BLACK_WATER then
        M.DrawBlackWaterTile(vg, px, py, row, col)
    elseif base == C.TILE.LADDER then
        M.DrawLadderTile(vg, px, py, row, col)
    elseif base == C.TILE.CHECKPOINT then
        M.DrawCheckpointTile(vg, px, py, row, col)
    end
end

function M.DrawSolidTile(vg, px, py)
    nvgBeginPath(vg)
    nvgRect(vg, px + 0.5, py + 0.5, C.GRID - 1, C.GRID - 1)
    nvgFillColor(vg, nvgRGBA(40, 45, 55, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, px + 0.5, py + 0.5, C.GRID - 1, 2)
    nvgFillColor(vg, nvgRGBA(60, 70, 80, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, px + 0.5, py + 0.5, 2, C.GRID - 1)
    nvgFillColor(vg, nvgRGBA(55, 60, 70, 255))
    nvgFill(vg)
end

--- 带光源的像素碰撞渲染（试玩模式中使用）
function M.DrawSolidTileWithLight(vg, px, py, tileType, row, col)
    -- 计算玩家光源
    local playerCol = S.play.gridX
    local playerRow = S.play.gridY + 1
    local flameRatio = S.playAlivePixels / math.max(1, S.playTotalPixels)
    local playerRadius = (S.playerParams and S.playerParams.defaultLightDiameter or 6) * 0.5 * flameRatio
    local pLit, pLdx, pLdy = SolidRenderer.CalcPlayerLightDirection(col, row, playerCol, playerRow, playerRadius)

    -- 计算放置的光源
    local sLit, sLdx, sLdy = SolidRenderer.CalcLightDirection(col, row, S.lightSources)

    -- 合并光源
    local totalLit = math.min(1.0, pLit + sLit)
    local totalLdx = pLdx * pLit + sLdx * sLit
    local totalLdy = pLdy * pLit + sLdy * sLit
    local len = math.sqrt(totalLdx * totalLdx + totalLdy * totalLdy)
    if len > 0.01 then
        totalLdx = totalLdx / len
        totalLdy = totalLdy / len
    end

    SolidRenderer.DrawSolid(vg, tileType, px + 0.5, py + 0.5, C.GRID - 1, totalLit, totalLdx, totalLdy)
end

function M.DrawFuelTile(vg, px, py, row, col)
    local key = row .. "_" .. col
    if S.play.collected[key] then return end
    local flicker = math.sin(S.playGameTime * 6 + col * 1.7) * 0.3 + 0.7
    local fr = math.floor(255 * flicker)
    local fg = math.floor(120 * flicker)
    nvgBeginPath(vg)
    nvgCircle(vg, px + C.GRID * 0.5, py + C.GRID * 0.5, 7)
    nvgFillColor(vg, nvgRGBA(255, 100, 0, math.floor(60 * flicker)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, px + C.GRID * 0.5, py + C.GRID * 0.5, 4)
    nvgFillColor(vg, nvgRGBA(fr, fg, 10, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, px + C.GRID * 0.5, py + C.GRID * 0.5 - 1, 2)
    nvgFillColor(vg, nvgRGBA(255, 255, 200, math.floor(200 * flicker)))
    nvgFill(vg)
end

function M.DrawGoalTile(vg, px, py)
    nvgBeginPath(vg)
    nvgRect(vg, px + 7, py, 2, C.GRID)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 9, py + 2)
    nvgLineTo(vg, px + 9 + 6, py + 5)
    nvgLineTo(vg, px + 9, py + 8)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(100, 255, 100, 255))
    nvgFill(vg)
end

function M.DrawSpikeTile(vg, px, py)
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 2, py + C.GRID - 2)
    nvgLineTo(vg, px + C.GRID * 0.5, py + 2)
    nvgLineTo(vg, px + C.GRID - 2, py + C.GRID - 2)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(200, 30, 30, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + C.GRID * 0.5 - 1, py + 3)
    nvgLineTo(vg, px + C.GRID * 0.5, py + 2)
    nvgLineTo(vg, px + C.GRID * 0.5 + 1, py + 3)
    nvgStrokeColor(vg, nvgRGBA(255, 180, 180, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

function M.DrawSwitchTile(vg, px, py, group, row, col)
    local key = row .. "_" .. col
    local gc = C.GROUP_COLORS[group] or C.GROUP_COLORS[1]
    local activated = S.play.collected[key]
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + 3, py + C.GRID - 5, C.GRID - 6, 4, 1)
    nvgFillColor(vg, nvgRGBA(80, 80, 80, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, px + C.GRID * 0.5, py + C.GRID * 0.5, 5)
    if activated then
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 80))
    else
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
    end
    nvgFill(vg)
    if not activated then
        nvgBeginPath(vg)
        nvgRect(vg, px + C.GRID * 0.5 - 1, py + 2, 2, 6)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgFill(vg)
    end
end

function M.DrawGateTile(vg, px, py, group)
    local gc = C.GROUP_COLORS[group] or C.GROUP_COLORS[1]
    local open = S.play.switchState[group]
    if not open then
        nvgBeginPath(vg)
        nvgRect(vg, px + 1, py, C.GRID - 2, C.GRID)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 180))
        nvgFill(vg)
        for dx = 0, 2 do
            nvgBeginPath(vg)
            nvgRect(vg, px + 3 + dx * 5, py + 2, 2, C.GRID - 4)
            nvgFillColor(vg, nvgRGBA(
                math.floor(gc[1] * 0.3),
                math.floor(gc[2] * 0.3),
                math.floor(gc[3] * 0.3), 255))
            nvgFill(vg)
        end
    else
        nvgBeginPath(vg)
        nvgRect(vg, px + 1, py, C.GRID - 2, C.GRID)
        nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 50))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end
end

function M.DrawHiddenWallTile(vg, px, py, group, row, col)
    if S.play.hiddenWallRevealed[group] then return end
    if row and col then
        M.DrawSolidTileWithLight(vg, px, py, C.TILE.SOLID, row, col)
    else
        M.DrawSolidTile(vg, px, py)
    end
end

------------------------------------------------------------
-- 水方块渲染
------------------------------------------------------------

function M.DrawWaterTile(vg, px, py, row, col)
    local t = S.playGameTime
    local G = C.GRID
    local worldX = (col - 1) * G  -- 世界坐标，用于跨格子连续波浪

    -- 检测上方是否也是水（同类），决定是否为表面
    local hasWaterAbove = false
    if row > 1 and S.levelData[row - 1] then
        local aboveVal = S.levelData[row - 1][col]
        if aboveVal then
            local aboveBase = TileUtils.GetTileType(aboveVal)
            if aboveBase == C.TILE.WATER then hasWaterAbove = true end
        end
    end

    if not hasWaterAbove then
        -- 表面格：绘制波浪（只在最顶层水格出现）
        local freq = 0.35
        for layer = 1, 3 do
            local speed = 2.5 + layer * 0.8
            local amp = 1.5 - layer * 0.3
            local yBase = py + 2 + layer * 3.5
            local phase = t * speed + layer * 2.1
            nvgBeginPath(vg)
            nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
            for sx = 1, 4 do
                local localX = sx * (G / 4)
                nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
            end
            nvgLineTo(vg, px + G, py + G)
            nvgLineTo(vg, px, py + G)
            nvgClosePath(vg)
            local a = math.floor(40 + layer * 15)
            nvgFillColor(vg, nvgRGBA(40 + layer * 20, 100 + layer * 25, 240, a))
            nvgFill(vg)
        end
    else
        -- 内部格：深层底色 + 缓慢水纹
        nvgBeginPath(vg)
        nvgRect(vg, px, py, G, G)
        nvgFillColor(vg, nvgRGBA(20, 60, 160, 180))
        nvgFill(vg)
        local freq = 0.25
        for layer = 1, 2 do
            local speed = 1.0 + layer * 0.3
            local amp = 0.8
            local yBase = py + G * (0.3 + layer * 0.25)
            local phase = t * speed + row * 1.7 + layer * 3.0
            nvgBeginPath(vg)
            nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
            for sx = 1, 4 do
                local localX = sx * (G / 4)
                nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
            end
            nvgLineTo(vg, px + G, yBase + math.sin(phase + (worldX + G) * freq) * amp - 1)
            nvgLineTo(vg, px + G, yBase + 2)
            nvgLineTo(vg, px, yBase + 2)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(30 + layer * 15, 80 + layer * 20, 220, 30 + layer * 12))
            nvgFill(vg)
        end
    end

    -- 荧光粒子散布（小亮点闪烁，限制在水面以下）
    local sparkTopY = hasWaterAbove and 2 or math.floor(G * 0.55)
    local sparkRangeH = G - sparkTopY - 2
    local seed = col * 7 + row * 13
    for i = 1, 3 do
        local phase_i = t * (3.0 + i * 0.7) + seed + i * 5.3
        local sparkAlpha = math.sin(phase_i) * 0.5 + 0.5
        if sparkAlpha > 0.3 then
            local sx = px + 2 + math.fmod(seed * i * 3.7, G - 4)
            local sy = py + sparkTopY + math.fmod(seed * i * 2.3, sparkRangeH)
            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, 1, 1)
            nvgFillColor(vg, nvgRGBA(150, 220, 255, math.floor(200 * sparkAlpha)))
            nvgFill(vg)
        end
    end
end

function M.DrawPoisonWaterTile(vg, px, py, row, col)
    local t = S.playGameTime
    local G = C.GRID
    local worldX = (col - 1) * G

    -- 检测上方是否也是毒水
    local hasWaterAbove = false
    if row > 1 and S.levelData[row - 1] then
        local aboveVal = S.levelData[row - 1][col]
        if aboveVal then
            local aboveBase = TileUtils.GetTileType(aboveVal)
            if aboveBase == C.TILE.POISON_WATER then hasWaterAbove = true end
        end
    end

    if not hasWaterAbove then
        -- 表面格：多层波浪（无底色，只有波浪形状）
        local freq = 0.4
        for layer = 1, 3 do
            local speed = 2.0 + layer * 0.6
            local amp = 1.8 - layer * 0.4
            local yBase = py + 2 + layer * 3.5
            local phase = t * speed + layer * 1.9
            nvgBeginPath(vg)
            nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
            for sx = 1, 4 do
                local localX = sx * (G / 4)
                nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
            end
            nvgLineTo(vg, px + G, py + G)
            nvgLineTo(vg, px, py + G)
            nvgClosePath(vg)
            local a = math.floor(35 + layer * 18)
            nvgFillColor(vg, nvgRGBA(20 + layer * 10, 140 + layer * 30, 40 + layer * 10, a))
            nvgFill(vg)
        end
    else
        -- 内部格：深层底色 + 缓慢水纹
        nvgBeginPath(vg)
        nvgRect(vg, px, py, G, G)
        nvgFillColor(vg, nvgRGBA(10, 100, 25, 190))
        nvgFill(vg)
        local freq = 0.3
        for layer = 1, 2 do
            local speed = 0.8 + layer * 0.3
            local amp = 0.7
            local yBase = py + G * (0.3 + layer * 0.25)
            local phase = t * speed + row * 1.5 + layer * 2.7
            nvgBeginPath(vg)
            nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
            for sx = 1, 4 do
                local localX = sx * (G / 4)
                nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
            end
            nvgLineTo(vg, px + G, yBase + math.sin(phase + (worldX + G) * freq) * amp - 1)
            nvgLineTo(vg, px + G, yBase + 2)
            nvgLineTo(vg, px, yBase + 2)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(15 + layer * 8, 120 + layer * 20, 30 + layer * 8, 30 + layer * 12))
            nvgFill(vg)
        end
    end

    -- 荧光粒子（绿色亮点，限制在水面以下）
    local sparkTopY = hasWaterAbove and 1 or math.floor(G * 0.55)
    local sparkRangeH = G - sparkTopY - 2
    local seed = col * 11 + row * 17
    for i = 1, 4 do
        local phase_i = t * (3.5 + i * 0.9) + seed + i * 4.1
        local sparkAlpha = math.sin(phase_i) * 0.5 + 0.5
        if sparkAlpha > 0.2 then
            local sx = px + 1 + math.fmod(seed * i * 2.9, G - 3)
            local sy = py + sparkTopY + math.fmod(seed * i * 1.7, sparkRangeH)
            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, 1, 1)
            nvgFillColor(vg, nvgRGBA(120, 255, 130, math.floor(230 * sparkAlpha)))
            nvgFill(vg)
        end
    end
end

function M.DrawBlackWaterTile(vg, px, py, row, col)
    local t = S.playGameTime
    local G = C.GRID
    local worldX = (col - 1) * G

    -- 检测上方是否也是黑水
    local hasWaterAbove = false
    if row > 1 and S.levelData[row - 1] then
        local aboveVal = S.levelData[row - 1][col]
        if aboveVal then
            local aboveBase = TileUtils.GetTileType(aboveVal)
            if aboveBase == C.TILE.BLACK_WATER then hasWaterAbove = true end
        end
    end

    if not hasWaterAbove then
        -- 表面格：缓慢波浪（黏稠感）
        local freq = 0.28
        for layer = 1, 2 do
            local speed = 1.2 + layer * 0.4
            local amp = 1.2 - layer * 0.3
            local yBase = py + 3 + layer * 4.5
            local phase = t * speed + layer * 2.5
            nvgBeginPath(vg)
            nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
            for sx = 1, 4 do
                local localX = sx * (G / 4)
                nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
            end
            nvgLineTo(vg, px + G, py + G)
            nvgLineTo(vg, px, py + G)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(40 + layer * 5, 40 + layer * 5, 50 + layer * 5, 80 + layer * 30))
            nvgFill(vg)
        end
    else
        -- 内部格：深层底色 + 极淡水纹
        nvgBeginPath(vg)
        nvgRect(vg, px, py, G, G)
        nvgFillColor(vg, nvgRGBA(30, 30, 38, 220))
        nvgFill(vg)
        local freq = 0.2
        local speed = 0.6
        local amp = 0.5
        local yBase = py + G * 0.5
        local phase = t * speed + row * 1.2 + 4.0
        nvgBeginPath(vg)
        nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
        for sx = 1, 4 do
            local localX = sx * (G / 4)
            nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
        end
        nvgLineTo(vg, px + G, yBase + math.sin(phase + (worldX + G) * freq) * amp - 1)
        nvgLineTo(vg, px + G, yBase + 2)
        nvgLineTo(vg, px, yBase + 2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(38, 38, 48, 40))
        nvgFill(vg)
    end

    -- 暗淡荧光粒子（灰白微光，限制在水面以下）
    local sparkTopY = hasWaterAbove and 3 or math.floor(G * 0.6)
    local sparkRangeH = G - sparkTopY - 3
    local seed = col * 5 + row * 9
    for i = 1, 2 do
        local phase_i = t * (1.8 + i * 0.5) + seed + i * 6.7
        local sparkAlpha = math.sin(phase_i) * 0.4 + 0.4
        if sparkAlpha > 0.35 then
            local sx = px + 3 + math.fmod(seed * i * 3.1, G - 6)
            local sy = py + sparkTopY + math.fmod(seed * i * 2.7, sparkRangeH)
            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, 1, 1)
            nvgFillColor(vg, nvgRGBA(140, 140, 160, math.floor(120 * sparkAlpha)))
            nvgFill(vg)
        end
    end
end

function M.DrawLadderTile(vg, px, py, row, col)
    -- 只由左半格负责绘制整个2格宽梯子
    -- 如果左边邻格也是梯子，则当前格是右半部分，跳过
    if col > 1 then
        local leftVal = S.levelData[row][col - 1]
        local leftBase = TileUtils.GetTileType(leftVal)
        if leftBase == C.TILE.LADDER then return end
    end

    local G = C.GRID
    local W = G * 2  -- 2格宽
    -- 两根竖直侧柱（深棕色）
    local railW = 2
    local railL = px + 1
    local railR = px + W - 3
    nvgBeginPath(vg)
    nvgRect(vg, railL, py, railW, G)
    nvgFillColor(vg, nvgRGBA(120, 75, 30, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, railR, py, railW, G)
    nvgFillColor(vg, nvgRGBA(120, 75, 30, 255))
    nvgFill(vg)
    -- 横档（浅棕色，2根，跨越2格宽）
    local rungH = 2
    local rungY1 = py + G * 0.3
    local rungY2 = py + G * 0.7
    nvgBeginPath(vg)
    nvgRect(vg, railL, rungY1, railR + railW - railL, rungH)
    nvgFillColor(vg, nvgRGBA(180, 130, 60, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, railL, rungY2, railR + railW - railL, rungH)
    nvgFillColor(vg, nvgRGBA(180, 130, 60, 255))
    nvgFill(vg)
end

------------------------------------------------------------
-- 战争迷雾
------------------------------------------------------------

function M.DrawFogOfWar(vg, startCol, endCol)
    -- 将玩家动态光源临时加入光源列表
    local sources = FogOfWar.GetLightSources()
    local playerLightIdx = nil
    local flameRatio = S.playAlivePixels / math.max(1, S.playTotalPixels)
    local playerDiameter = S.playerParams.defaultLightDiameter * flameRatio
    if playerDiameter >= 1 then
        local playerS = M.PlayerGridSize()
        local lightCol = S.play.gridX + math.floor(playerS * 0.5)
        local lightRow = S.play.gridY + math.floor(playerS * 0.5)
        table.insert(sources, {
            col = lightCol,
            row = lightRow,
            diameter = playerDiameter,
            feather = 0.5,
        })
        playerLightIdx = #sources
    end

    FogOfWar.SetLightSources(sources)
    FogOfWar.Draw(vg, {
        gridSize = C.GRID,
        startCol = startCol,
        endCol = endCol,
        startRow = 1,
        endRow = S.MAP_ROWS,
        offsetX = S.playCameraX,
        offsetY = S.playCameraY,
        zoomLevel = 1.0,
        mapX = 0,
        mapY = 0,
    })

    -- 移除临时的玩家动态光源，恢复原始列表（玩家不挂灯笼）
    if playerLightIdx then
        table.remove(sources, playerLightIdx)
    end

    -- 在迷雾上方绘制像素提灯（仅地图光源，不含玩家）
    FogOfWar.DrawLanterns(vg, {
        gridSize = C.GRID,
        offsetX = S.playCameraX,
        offsetY = S.playCameraY,
        zoomLevel = 1.0,
        mapX = 0,
        mapY = 0,
    })
end

------------------------------------------------------------
-- HUD
------------------------------------------------------------

function M.DrawHUD(vg)
    local zoom = S.playerParams.cameraZoom or 1.0
    local hudW = S.playViewW * zoom
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, hudW, 22)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local flamePercent = math.floor(S.playAlivePixels / math.max(1, S.playTotalPixels) * 100)
    local flameG = math.floor(200 * (flamePercent / 100))
    nvgFillColor(vg, nvgRGBA(255, flameG, 30, 255))
    nvgText(vg, 6, 11, "FLAME:" .. flamePercent .. "%")

    nvgFillColor(vg, nvgRGBA(150, 255, 150, 255))
    nvgText(vg, 100, 11, "JUMP:" .. M.CalcJump() .. "G")

    M.DrawBackButton(vg)
    M.DrawWorldPlayFileName(vg)
end

function M.DrawBackButton(vg)
    local zoom = S.playerParams.cameraZoom or 1.0
    local hudW = S.playViewW * zoom
    local isWorldPlay = (S.editorMode == C.MODE_WORLDPLAY)
    local backBtnLabel = isWorldPlay and "返回世界" or "返回编辑"
    local backBtnW = isWorldPlay and 60 or 50
    local backBtnH = 16
    local backBtnX = hudW - backBtnW - 6
    local backBtnY = (22 - backBtnH) * 0.5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, backBtnX, backBtnY, backBtnW, backBtnH, 3)
    nvgFillColor(vg, nvgRGBA(80, 60, 40, 230))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, backBtnX, backBtnY, backBtnW, backBtnH, 3)
    nvgStrokeColor(vg, nvgRGBA(255, 180, 80, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 150, 255))
    nvgText(vg, backBtnX + backBtnW * 0.5, backBtnY + backBtnH * 0.5, backBtnLabel)
end

function M.DrawWorldPlayFileName(vg)
    if S.editorMode ~= C.MODE_WORLDPLAY or not S.worldPlayCurrentFile then return end
    local zoom = S.playerParams.cameraZoom or 1.0
    local hudW = S.playViewW * zoom
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
    nvgText(vg, hudW * 0.5, 3, S.worldPlayCurrentFile)
end

------------------------------------------------------------
-- 像素字体系统 (5x7 bitmap)
------------------------------------------------------------

local PIXEL_FONT = {
    A = { "01110", "10001", "10001", "11111", "10001", "10001", "10001" },
    B = { "11110", "10001", "10001", "11110", "10001", "10001", "11110" },
    C = { "01110", "10001", "10000", "10000", "10000", "10001", "01110" },
    D = { "11100", "10010", "10001", "10001", "10001", "10010", "11100" },
    E = { "11111", "10000", "10000", "11110", "10000", "10000", "11111" },
    F = { "11111", "10000", "10000", "11110", "10000", "10000", "10000" },
    G = { "01110", "10001", "10000", "10111", "10001", "10001", "01110" },
    H = { "10001", "10001", "10001", "11111", "10001", "10001", "10001" },
    I = { "11111", "00100", "00100", "00100", "00100", "00100", "11111" },
    K = { "10001", "10010", "10100", "11000", "10100", "10010", "10001" },
    L = { "10000", "10000", "10000", "10000", "10000", "10000", "11111" },
    M = { "10001", "11011", "10101", "10101", "10001", "10001", "10001" },
    N = { "10001", "11001", "10101", "10011", "10001", "10001", "10001" },
    O = { "01110", "10001", "10001", "10001", "10001", "10001", "01110" },
    P = { "11110", "10001", "10001", "11110", "10000", "10000", "10000" },
    R = { "11110", "10001", "10001", "11110", "10100", "10010", "10001" },
    S = { "01111", "10000", "10000", "01110", "00001", "00001", "11110" },
    T = { "11111", "00100", "00100", "00100", "00100", "00100", "00100" },
    U = { "10001", "10001", "10001", "10001", "10001", "10001", "01110" },
    W = { "10001", "10001", "10001", "10101", "10101", "11011", "10001" },
    X = { "10001", "01010", "00100", "00100", "00100", "01010", "10001" },
    Y = { "10001", "10001", "01010", "00100", "00100", "00100", "00100" },
    [" "] = { "00000", "00000", "00000", "00000", "00000", "00000", "00000" },
    [":"] = { "00000", "00100", "00100", "00000", "00100", "00100", "00000" },
}

--- 绘制像素字体文本（居中）
---@param vg userdata
---@param text string 大写英文+空格
---@param cx number 中心X
---@param cy number 中心Y
---@param pixSize number 每像素块大小
---@param r number
---@param g number
---@param b number
---@param a number
function M.DrawPixelText(vg, text, cx, cy, pixSize, r, g, b, a)
    local gap = 1  -- 字间距(像素块)
    local charW = 5
    local charH = 7
    local totalW = #text * (charW + gap) - gap
    local startX = cx - totalW * pixSize * 0.5
    local startY = cy - charH * pixSize * 0.5

    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    for ci = 1, #text do
        local ch = text:sub(ci, ci)
        local glyph = PIXEL_FONT[ch]
        if glyph then
            local ox = startX + (ci - 1) * (charW + gap) * pixSize
            for row = 1, charH do
                local rowStr = glyph[row]
                for col = 1, charW do
                    if rowStr:sub(col, col) == "1" then
                        nvgBeginPath(vg)
                        nvgRect(vg, ox + (col - 1) * pixSize, startY + (row - 1) * pixSize, pixSize, pixSize)
                        nvgFill(vg)
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- 死亡过渡状态
------------------------------------------------------------

-- 阶段: nil=正常, "circleClose"=缩圈, "blackout"=全黑停顿, "waitKey"=等待按键
M.deathPhase = nil
M.deathPhaseTimer = 0

-- 篝火点亮消息
M.bonfireMsg = { active = false, timer = 0, duration = 1.8 }

function M.ShowBonfireMessage()
    M.bonfireMsg.active = true
    M.bonfireMsg.timer = 0
end

function M.UpdateBonfireMessage(dt)
    if M.bonfireMsg.active then
        M.bonfireMsg.timer = M.bonfireMsg.timer + dt
        if M.bonfireMsg.timer >= M.bonfireMsg.duration then
            M.bonfireMsg.active = false
        end
    end
end

------------------------------------------------------------
-- 死亡/通关覆盖
------------------------------------------------------------

function M.DrawOverlays(vg)
    local isWorldPlay = (S.editorMode == C.MODE_WORLDPLAY)
    local escHint = isWorldPlay and "ESC:WORLD" or "ESC:EDIT"

    if not S.play.alive then
        M.DrawDeathOverlay(vg, escHint)
    elseif S.play.won then
        M.DrawWinOverlay(vg, escHint)
    end

    M.DrawBonfireMessage(vg)
end

function M.DrawDeathOverlay(vg, escHint)
    local zoom = S.playerParams.cameraZoom or 1.0
    local w = S.playViewW * zoom
    local h = S.playViewH * zoom
    local centerX = w * 0.5
    local centerY = h * 0.5
    -- 使用视口对角线作为最大半径（避免过大导致卡顿）
    local maxRadius = math.sqrt(w * w + h * h) * 0.5

    local phase = M.deathPhase
    if phase == "circleClose" then
        -- 缩圈: 0.6秒内从 maxRadius 缩到 0
        local progress = math.min(M.deathPhaseTimer / 0.6, 1.0)
        local radius = maxRadius * (1.0 - progress)
        -- 用大矩形 + 圆形减去实现遮罩
        nvgBeginPath(vg)
        nvgRect(vg, -100, -100, w + 200, h + 200)
        -- 顺时针大矩形 + 逆时针圆洞 = 环形遮罩
        nvgPathWinding(vg, NVG_SOLID)
        nvgBeginPath(vg)
        nvgRect(vg, -100, -100, w + 200, h + 200)
        if radius > 0.5 then
            nvgCircle(vg, centerX, centerY, radius)
            nvgPathWinding(vg, NVG_HOLE)
        end
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)

    elseif phase == "blackout" then
        -- 全黑停顿 0.3秒
        nvgBeginPath(vg)
        nvgRect(vg, -100, -100, w + 200, h + 200)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)

    elseif phase == "waitKey" then
        -- 全黑 + 显示文本
        nvgBeginPath(vg)
        nvgRect(vg, -100, -100, w + 200, h + 200)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)

        -- "YOU DIE" 像素字体
        local pixSize = 3.0 * zoom
        M.DrawPixelText(vg, "YOU DIE", centerX, centerY - 10 * zoom, pixSize, 255, 60, 60, 255)

        -- 闪烁 "PRESS ANY KEY"
        local blink = math.floor(M.deathPhaseTimer * 3) % 2
        if blink == 0 then
            local hintPixSize = 1.5 * zoom
            M.DrawPixelText(vg, "PRESS ANY KEY", centerX, centerY + 20 * zoom, hintPixSize, 255, 255, 255, 200)
        end

        -- ESC 提示
        local escPixSize = 1.2 * zoom
        M.DrawPixelText(vg, escHint, centerX, centerY + 38 * zoom, escPixSize, 180, 180, 180, 180)

    else
        -- fallback: 还没进入 deathPhase 的第一帧，画一帧渐入
        local progress = math.min(S.play.deathTimer / 0.1, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -100, -100, w + 200, h + 200)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(255 * progress)))
        nvgFill(vg)
    end
end

function M.DrawBonfireMessage(vg)
    if not M.bonfireMsg.active then return end
    local zoom = S.playerParams.cameraZoom or 1.0
    local w = S.playViewW * zoom
    local h = S.playViewH * zoom
    local t = M.bonfireMsg.timer
    local dur = M.bonfireMsg.duration
    -- fade in 0.3s, hold, fade out 0.3s
    local alpha = 255
    if t < 0.3 then
        alpha = math.floor(255 * t / 0.3)
    elseif t > dur - 0.3 then
        alpha = math.floor(255 * (dur - t) / 0.3)
    end
    local pixSize = 2.5 * zoom
    M.DrawPixelText(vg, "BONFIRE LIT", w * 0.5, h * 0.4, pixSize, 255, 180, 50, alpha)
end

function M.DrawWinOverlay(vg, escHint)
    local zoom = S.playerParams.cameraZoom or 1.0
    local w = S.playViewW * zoom
    local h = S.playViewH * zoom
    nvgBeginPath(vg)
    nvgRect(vg, -100, -100, w + 200, h + 200)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)
    -- "FLAME ETERNAL" 像素字体
    local pixSize = 2.5 * zoom
    M.DrawPixelText(vg, "FLAME ETERNAL", w * 0.5, h * 0.4, pixSize, 255, 200, 50, 255)
    local escPixSize = 1.2 * zoom
    M.DrawPixelText(vg, escHint, w * 0.5, h * 0.55, escPixSize, 255, 255, 255, 200)
end

------------------------------------------------------------
-- 篝火 (CHECKPOINT) 渲染 — 放大版（ps=3，约2格高，匹配玩家大小）
------------------------------------------------------------
function M.DrawCheckpointTile(vg, px, py, row, col)
    local key = row .. "_" .. col
    local activated = S.checkpointActivated[key]
    local ps = 3  -- 像素块大小（放大到与玩家相当）

    -- 篝火从格子底部向上绘制，占 10 行 × 10 列 像素格
    local drawBaseY = py + C.GRID  -- 格子底边
    local drawTopY = drawBaseY - 10 * ps
    local drawLeftX = px + (C.GRID - 10 * ps) * 0.5  -- 水平居中

    -- 石头底座（行 8-9，从 drawTopY 算起）
    local stones = {
        {2,8},{3,8},{4,8},{5,8},{6,8},{7,8},
        {1,9},{2,9},{3,9},{4,9},{5,9},{6,9},{7,9},{8,9},
    }
    for _, s in ipairs(stones) do
        local sx = drawLeftX + s[1] * ps
        local sy = drawTopY + s[2] * ps
        nvgBeginPath(vg)
        nvgRect(vg, sx, sy, ps, ps)
        if s[2] == 9 then
            nvgFillColor(vg, nvgRGBA(50, 45, 40, 255))
        else
            nvgFillColor(vg, nvgRGBA(75, 70, 60, 255))
        end
        nvgFill(vg)
    end

    -- 木柴（行 5-7）
    local logs = {
        {3,7},{4,7},{5,7},{6,7},
        {2,6},{3,6},{4,6},{5,6},{6,6},{7,6},
        {3,5},{4,5},{5,5},{6,5},
    }
    for _, l in ipairs(logs) do
        local lx = drawLeftX + l[1] * ps
        local ly = drawTopY + l[2] * ps
        nvgBeginPath(vg)
        nvgRect(vg, lx, ly, ps, ps)
        nvgFillColor(vg, nvgRGBA(100, 60, 25, 255))
        nvgFill(vg)
    end

    if activated then
        -- 点燃状态：像素火焰（行 0-5）
        local t = S.flameTime or 0
        local flicker1 = math.sin(t * 8 + col * 2.1) * 0.5 + 0.5
        local flicker2 = math.sin(t * 11 + row * 1.7) * 0.5 + 0.5

        local flames = {
            -- 外焰（橙红色）
            {2,4,{255,80,10}}, {3,4,{255,100,15}}, {6,4,{255,90,10}}, {7,4,{255,100,15}},
            {2,3,{255,110,20}}, {7,3,{255,100,15}},
            -- 中焰（橙色）
            {3,3,{255,140,30}}, {4,3,{255,160,40}}, {5,3,{255,150,35}}, {6,3,{255,140,30}},
            {3,2,{255,170,50}}, {4,2,{255,190,60}}, {5,2,{255,180,55}}, {6,2,{255,170,50}},
            -- 内焰（黄色）
            {4,1,{255,220,80}}, {5,1,{255,210,70}},
            {4,0,{255,240,120}}, {5,0,{255,230,100}},
        }
        for _, f in ipairs(flames) do
            local fx = drawLeftX + f[1] * ps
            local fy = drawTopY + f[2] * ps
            local c = f[3]
            local flick = (f[2] <= 2) and flicker1 or flicker2
            local a = math.floor(180 + 75 * flick)
            nvgBeginPath(vg)
            nvgRect(vg, fx, fy, ps, ps)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
            nvgFill(vg)
        end

        -- 火焰光晕
        local glowA = math.floor(25 + 20 * flicker1)
        nvgBeginPath(vg)
        nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 2 * ps, 12)
        nvgFillColor(vg, nvgRGBA(255, 150, 30, glowA))
        nvgFill(vg)
    else
        -- 未点燃：暗灰余烬 + 微弱闪烁
        local t = S.flameTime or 0
        local embers = {
            {3,5},{4,5},{5,5},{6,5},
            {4,4},{5,4},
        }
        local emberFlick = math.sin(t * 3 + col) * 0.3 + 0.7
        for _, e in ipairs(embers) do
            local ex = drawLeftX + e[1] * ps
            local ey = drawTopY + e[2] * ps
            nvgBeginPath(vg)
            nvgRect(vg, ex, ey, ps, ps)
            nvgFillColor(vg, nvgRGBA(60, 30, 15, math.floor(120 * emberFlick)))
            nvgFill(vg)
        end
    end
end

return M
