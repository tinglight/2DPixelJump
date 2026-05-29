------------------------------------------------------------
-- PlayMode.lua — 试玩模式物理与状态管理
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")
local TileUtils = require("editor.TileUtils")
local FlameRenderer = require("editor.FlameRenderer")
local Undo = require("editor.UndoSystem")
local CrossLevel = require("editor.CrossLevel")

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
    if base == C.TILE.SOLID then return true end
    if base == C.TILE.GATE and not S.play.switchState[group] then return true end
    if base == C.TILE.HIDDEN_WALL and not S.play.hiddenWallRevealed[group] then return true end
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

    if base == C.TILE.SPIKE then
        S.play.alive = false
        S.play.deathTimer = 0
    elseif base == C.TILE.GOAL then
        S.play.won = true
    elseif base == C.TILE.FUEL and not S.play.collected[key] then
        S.play.collected[key] = true
        M.RecoverPixels(math.floor(S.playTotalPixels * 0.4))
        M.SyncFallGridCount()
    elseif base == C.TILE.SWITCH and not S.play.collected[key] then
        S.play.collected[key] = true
        S.play.switchState[group] = not S.play.switchState[group]
        -- 记录到跨关卡状态（世界试玩模式）
        if S.editorMode == C.MODE_WORLDPLAY and S.worldPlayCurrentFile then
            CrossLevel.ActivateCrossSwitch(S.worldPlayCurrentFile, group)
        end
    elseif base == C.TILE.HIDDEN_WALL and not S.play.hiddenWallRevealed[group] then
        S.play.hiddenWallRevealed[group] = true
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
-- 帧更新
------------------------------------------------------------

function M.Update(dt)
    if input:GetKeyPress(KEY_ESCAPE) then
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
    if not S.play.alive then
        M.UpdateDeathRespawn(dt)
        return
    end

    S.playGameTime = S.playGameTime + dt
    M.UpdateFlameTime(dt)
    M.UpdateTipPixels(dt)
    M.UpdateFallParticles(dt)
    M.HandleMovementInput(dt)
    M.HandleJumpInput()
    M.HandleProjectileInput()
    M.UpdateVerticalPhysics(dt)
    M.UpdateGroundRecovery(dt)
    CrossLevel.Update(dt)

    if S.playAlivePixels <= 0 then
        S.play.alive = false
        S.play.deathTimer = 0
    end
    M.CheckTiles()
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
    local curLeft = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
    local curRight = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)
    local dir = 0
    if curLeft and not curRight then dir = -1
    elseif curRight and not curLeft then dir = 1 end

    if dir ~= 0 then
        local justPressed = (dir == -1 and not S.prevPlayLeft) or (dir == 1 and not S.prevPlayRight)
        if justPressed then
            M.MoveOneGrid(dir)
            S.play.moveTimer = 0
            S.playMoveFirst = true
        else
            S.play.moveTimer = S.play.moveTimer + dt
            if S.play.moveTimer >= C.PLAY_MOVE_TICK then
                S.play.moveTimer = S.play.moveTimer - C.PLAY_MOVE_TICK
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
    if input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) then
        if S.play.isOnGround and not S.play.isJumping then
            S.play.isJumping = true
            S.play.jumpGridsRemain = M.CalcJump()
            S.play.isOnGround = false
            S.play.jumpTimer = 0
        end
    end
end

function M.UpdateVerticalPhysics(dt)
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
    if not S.play.isOnGround then return end
    if S.playAlivePixels >= S.playTotalPixels then return end
    local recoverCount = math.floor(C.PLAY_RECOVER_PER_SEC * dt + 0.5)
    if recoverCount >= 1 then
        M.RecoverPixels(recoverCount)
        M.SyncFallGridCount()
    end
end

function M.UpdateCamera(dt)
    local boundLeftPx = (S.camBound.left - 1) * C.GRID
    local boundRightPx = S.camBound.right * C.GRID
    local viewW = C.DESIGN_W * (S.playerParams.cameraZoom or 1.0)
    local camMinX = boundLeftPx
    local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)
    local targetCam = (S.play.gridX - 1) * C.GRID - viewW * 0.35
    targetCam = math.max(camMinX, math.min(targetCam, camMaxX))
    S.playCameraX = S.playCameraX + (targetCam - S.playCameraX) * math.min(1, dt * 8)
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
    for row = 1, S.MAP_ROWS do
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
    M.ApplyParams(data.playerParams)
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
    local boundLeftPx = (S.camBound.left - 1) * C.GRID
    local boundRightPx = S.camBound.right * C.GRID
    local viewW = C.DESIGN_W * (S.playerParams.cameraZoom or 1.0)
    local camMinX = boundLeftPx
    local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)
    local targetCam = (S.play.gridX - 1) * C.GRID - viewW * 0.35
    S.playCameraX = math.max(camMinX, math.min(targetCam, camMaxX))
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
    local a = math.floor(S.transition.alpha * 255)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, S.screenDesignW, S.screenDesignH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
    nvgFill(vg)
end

function M.DetectBoundaryDirection(gx, gy)
    local pressLeft = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
    local pressRight = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)
    if gx <= S.camBound.left and pressLeft then return "left", "right" end
    if gx >= S.camBound.right and pressRight then return "right", "left" end
    if gy <= S.camBound.top then return "up", "down" end
    if gy >= S.camBound.bottom or gy >= S.MAP_ROWS then return "down", "up" end
    return nil, nil
end

------------------------------------------------------------
-- 启动函数
------------------------------------------------------------

local function ResetPlayState()
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
    S.play.isMoving = false
    S.play.moveAnimTime = 0
    S.play.fallAnimTime = 0
    S.play.switchState = {}
    S.play.collected = {}
    S.play.hiddenWallRevealed = {}
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
    S.playCameraX = math.max(0, (S.spawnCol - 1) * C.GRID - C.DESIGN_W * (S.playerParams.cameraZoom or 1.0) * 0.35)
    M.InitPlayPixels()
end

------------------------------------------------------------
-- 死亡后自动复活（不重置已收集道具和开关状态）
------------------------------------------------------------

local DEATH_RESPAWN_DELAY = 0.8  -- 死亡后等待时间（秒）

function M.UpdateDeathRespawn(dt)
    S.play.deathTimer = S.play.deathTimer + dt
    if S.play.deathTimer >= DEATH_RESPAWN_DELAY then
        M.Respawn()
    end
end

function M.Respawn()
    -- 重置位置到重生点
    S.play.gridX = S.spawnCol
    S.play.gridY = S.spawnRow - (C.PLAYER_GRID_H - 1)
    -- 重置物理状态
    S.play.isOnGround = false
    S.play.isJumping = false
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
    local map, sc, sr, templateName = LevelGenerator.GenerateValid(diff, 5)
    for row = 1, S.MAP_ROWS do
        S.levelData[row] = {}
        for col = 1, S.MAP_COLS do
            if row <= LevelGenerator.MAP_ROWS and col <= LevelGenerator.MAP_COLS then
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
    CrossLevel.Draw(vg, S.playCameraX)
    M.DrawFogOfWar(vg, startCol, endCol)
    M.DrawHUD(vg)
    M.DrawOverlays(vg)
    M.DrawTransition()
end

function M.DrawBackground(vg)
    local bg = nvgLinearGradient(vg, 0, 0, 0, S.screenDesignH,
        nvgRGBA(10, 5, 20, 255), nvgRGBA(30, 15, 40, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, S.screenDesignW, S.screenDesignH)
    nvgFillPaint(vg, bg)
    nvgFill(vg)
end

function M.DrawGrid(vg)
    local startCol = math.max(1, math.floor(S.playCameraX / C.GRID) + 1)
    local endCol = math.min(S.MAP_COLS, startCol + math.ceil(S.screenDesignW / C.GRID) + 2)

    -- 细线
    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        local x = (col - 1) * C.GRID - S.playCameraX
        nvgMoveTo(vg, x, 0)
        nvgLineTo(vg, x, S.MAP_ROWS * C.GRID)
    end
    for row = 1, S.MAP_ROWS + 1 do
        local y = (row - 1) * C.GRID
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
            nvgMoveTo(vg, x, 0)
            nvgLineTo(vg, x, S.MAP_ROWS * C.GRID)
        end
    end
    for row = 1, S.MAP_ROWS + 1 do
        if (row - 1) % 5 == 0 then
            local y = (row - 1) * C.GRID
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
    for row = 1, S.MAP_ROWS do
        for col = startCol, endCol do
            local val = S.levelData[row][col]
            if val ~= C.TILE.EMPTY and val ~= C.TILE.SPAWN then
                local px = (col - 1) * C.GRID - S.playCameraX
                local py = (row - 1) * C.GRID
                local base, group = TileUtils.GetTileType(val)
                M.DrawOneTile(vg, px, py, base, group, row, col)
            end
        end
    end
end

function M.DrawOneTile(vg, px, py, base, group, row, col)
    if base == C.TILE.SOLID then
        M.DrawSolidTile(vg, px, py)
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
        M.DrawHiddenWallTile(vg, px, py, group)
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

function M.DrawHiddenWallTile(vg, px, py, group)
    if S.play.hiddenWallRevealed[group] then return end
    M.DrawSolidTile(vg, px, py)
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
        offsetY = 0,
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
        offsetY = 0,
        zoomLevel = 1.0,
        mapX = 0,
        mapY = 0,
    })
end

------------------------------------------------------------
-- HUD
------------------------------------------------------------

function M.DrawHUD(vg)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, S.screenDesignW, 22)
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
    local isWorldPlay = (S.editorMode == C.MODE_WORLDPLAY)
    local backBtnLabel = isWorldPlay and "返回世界" or "返回编辑"
    local backBtnW = isWorldPlay and 60 or 50
    local backBtnH = 16
    local backBtnX = S.screenDesignW - backBtnW - 6
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
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
    nvgText(vg, S.screenDesignW * 0.5, 3, S.worldPlayCurrentFile)
end

------------------------------------------------------------
-- 死亡/通关覆盖
------------------------------------------------------------

function M.DrawOverlays(vg)
    local isWorldPlay = (S.editorMode == C.MODE_WORLDPLAY)
    local escHint = isWorldPlay and "ESC:返回世界地图" or "ESC:返回编辑"

    if not S.play.alive then
        M.DrawDeathOverlay(vg, escHint)
    elseif S.play.won then
        M.DrawWinOverlay(vg, escHint)
    end
end

function M.DrawDeathOverlay(vg, escHint)
    -- 根据 deathTimer 计算渐入透明度
    local progress = math.min(S.play.deathTimer / 0.3, 1.0)  -- 0.3秒内渐入
    local overlayAlpha = math.floor(150 * progress)
    local textAlpha = math.floor(255 * progress)

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, S.screenDesignW, S.screenDesignH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, overlayAlpha))
    nvgFill(vg)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(255, 60, 60, textAlpha))
    nvgText(vg, S.screenDesignW * 0.5, S.screenDesignH * 0.4, "FLAME OUT!")
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(200 * progress)))
    nvgText(vg, S.screenDesignW * 0.5, S.screenDesignH * 0.52, escHint)
end

function M.DrawWinOverlay(vg, escHint)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, S.screenDesignW, S.screenDesignH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
    nvgFill(vg)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
    nvgText(vg, S.screenDesignW * 0.5, S.screenDesignH * 0.4, "FLAME ETERNAL!")
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
    nvgText(vg, S.screenDesignW * 0.5, S.screenDesignH * 0.52, escHint)
end

return M
