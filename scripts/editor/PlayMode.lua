------------------------------------------------------------
-- PlayMode.lua — 试玩模式薄协调器
-- 所有具体功能已拆分到 editor/play/ 子模块，
-- 本文件只负责：依赖注入、提升的内部辅助函数、像素系统、主循环。
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")
local TileUtils = require("editor.TileUtils")
local FlameRenderer = require("editor.FlameRenderer")
local Undo = require("editor.UndoSystem")
local CrossLevel = require("editor.CrossLevel")
local SolidRenderer = require("rendering.SolidRenderer")
local CurtainRenderer = require("rendering.CurtainRenderer")
local PipeSystem = require("editor.PipeSystem")
local PauseMenu = require("ui.PauseMenu")
local FlameDashChain = require("gameplay.FlameDashChain")
local GMTool = require("editor.GMTool")

local M = {}

-- 依赖注入（延迟加载避免循环引用）
local FogOfWar, CloudStorage, WorldMapEditor, LevelGenerator
local cjson

------------------------------------------------------------
-- 内部辅助：深拷贝光源列表
------------------------------------------------------------

--- 深拷贝光源列表（每个 light 是独立副本，避免试玩时修改影响编辑器）
function M._DeepCopyLightSources(sources)
    if not sources then return {} end
    local copy = {}
    for i, light in ipairs(sources) do
        copy[i] = {
            col = light.col,
            row = light.row,
            diameter = light.diameter,
            feather = light.feather,
            group = light.group,
            noLantern = light.noLantern,
            extinguished = light.extinguished,
            targetDiameter = light.targetDiameter,
            _originalDiameter = light._originalDiameter,
        }
    end
    return copy
end

--- 试玩开始前保存的编辑器原始光源快照（子模块通过 M._savedEditorLightSources 访问）
M._savedEditorLightSources = nil

--- 重新进入编辑器时清理 PlayMode 模块级状态
function M.ResetModuleState()
    M._savedEditorLightSources = nil
end

------------------------------------------------------------
-- 依赖注入
------------------------------------------------------------

---@param deps table { FogOfWar, CloudStorage, WorldMapEditor, LevelGenerator, cjson }
function M.Inject(deps)
    FogOfWar      = deps.FogOfWar
    CloudStorage  = deps.CloudStorage
    WorldMapEditor = deps.WorldMapEditor
    LevelGenerator = deps.LevelGenerator
    cjson         = deps.cjson

    -- 将注入依赖暴露为 M 字段，供子模块（editor/play/*.lua）在运行时访问
    M._fogOfWar      = FogOfWar
    M._cloudStorage  = CloudStorage
    M._worldMapEditor = WorldMapEditor
    M._levelGenerator = LevelGenerator
    M._cjson         = cjson

    -- 碰撞检测器：用于光照阴影遮挡
    local function isSolidForLight(col, row)
        if col < 1 or col > S.MAP_COLS then return false end
        if row < 1 or row > S.MAP_ROWS then return false end
        local val = S.levelData[row] and S.levelData[row][col]
        if not val or val == 0 then return false end
        local base, group = TileUtils.GetTileType(val)
        if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR or base == C.TILE.SOLID_SEWER
            or base == C.TILE.SLOPE_TR or base == C.TILE.SLOPE_TL or base == C.TILE.SLOPE_BR or base == C.TILE.SLOPE_BL then
            return true
        end
        if base == C.TILE.HIDDEN_WALL then
            local revealTime = S.play.hiddenWallRevealed[group]
            if not revealTime then return true end
            if S.play.gameTime - revealTime < C.HIDDEN_WALL_FADE_DURATION then return true end
        end
        return false
    end
    FogOfWar.SetCollisionChecker(isSolidForLight)
    SolidRenderer.SetCollisionChecker(isSolidForLight)

    -- 柳条检测器：用于光照衰减
    local function isCurtainAt(col, row)
        if col < 1 or col > S.MAP_COLS then return false end
        if row < 1 or row > S.MAP_ROWS then return false end
        local val = S.levelData[row] and S.levelData[row][col]
        if not val or val == 0 then return false end
        local base = TileUtils.GetTileType(val)
        return base == C.TILE.CURTAIN
    end
    FogOfWar.SetCurtainChecker(isCurtainAt)
    SolidRenderer.SetCurtainChecker(isCurtainAt)

    -- 水方块检测器：用于水面自发光
    local function isWaterAt(col, row)
        if col < 1 or col > S.MAP_COLS then return false end
        if row < 1 or row > S.MAP_ROWS then return false end
        local val = S.levelData[row] and S.levelData[row][col]
        if not val or val == 0 then return false end
        local base = TileUtils.GetTileType(val)
        return base == C.TILE.WATER or base == C.TILE.POISON_WATER or base == C.TILE.BLACK_WATER
    end
    FogOfWar.SetWaterChecker(isWaterAt)
end

------------------------------------------------------------
-- 内部辅助：篝火光源清理与恢复（所有退出路径共用）
------------------------------------------------------------

--- 清理篝火光源和存档点状态
function M._CleanupCheckpointLight()
    if S.checkpointLightPos then
        FogOfWar.RemoveLight(S.checkpointLightPos.col, S.checkpointLightPos.row)
        S.checkpointLightPos = nil
    end
    S.lightSources = FogOfWar.GetLightSources()
    S.checkpointActivated = {}
    S.checkpointFile = nil
    S.checkpointCol = nil
    S.checkpointRow = nil
end

--- 恢复篝火光源（关卡加载/重生后临时光源丢失时调用）
--- 注意：篝火光源是试玩模式的临时光源（noLantern=true），不会被序列化保存，
--- 因此在 WorldPlayLoadLevel 反序列化关卡光源后需要重新创建。
function M._RestoreCampfireLight()
    if not S.checkpointCol or not S.checkpointRow then return end
    if S.editorMode == C.MODE_WORLDPLAY and S.checkpointFile
        and S.worldPlayCurrentFile ~= S.checkpointFile then
        return
    end
    if S.checkpointLightPos then
        FogOfWar.RemoveLight(S.checkpointLightPos.col, S.checkpointLightPos.row)
    end
    local lightIdx = FogOfWar.AddLightAnimated(S.checkpointCol, S.checkpointRow, 35, 0.5)
    local light = FogOfWar.GetLight(lightIdx)
    if light then light.noLantern = true end
    S.checkpointLightPos = { col = S.checkpointCol, row = S.checkpointRow }
    S.lightSources = FogOfWar.GetLightSources()
end

------------------------------------------------------------
-- 内部辅助：重置试玩状态（供 StartPlayMode / StartWorldPlayMode 调用）
------------------------------------------------------------

function M._ResetPlayState()
    M._CleanupCheckpointLight()
    FlameDashChain.Reset()
    M._resetDashTrailParticles()
    GMTool.Reset()
    GMTool.InitPosition()

    -- 将 FogOfWar 内部光源替换为克隆副本，避免试玩修改影响编辑器
    if M._savedEditorLightSources then
        local clonedLights = M._DeepCopyLightSources(M._savedEditorLightSources)
        FogOfWar.SetLightSources(clonedLights)
        S.lightSources = FogOfWar.GetLightSources()
    end

    S.play.gridX = S.spawnCol
    S.play.gridY = S.spawnRow - (C.PLAYER_GRID_H - 1)

    local ps = M.PlayerGridSize()
    S.play.gridX = math.max(S.camBound.left, math.min(S.play.gridX, S.camBound.right - ps + 1))
    S.play.gridY = math.max(S.camBound.top, math.min(S.play.gridY, S.camBound.bottom - C.PLAYER_GRID_H + 1))

    -- 安全检查：玩家初始位置卡在实心方块中时向上搜索有效位置
    if M.Collides(S.play.gridX, S.play.gridY) then
        log:Write(LOG_WARNING, string.format(
            "[RESET] Player spawned inside solid at (%d,%d), searching valid position...",
            S.play.gridX, S.play.gridY))
        local found = false
        for tryY = S.play.gridY - 1, S.camBound.top, -1 do
            if not M.Collides(S.play.gridX, tryY) then
                S.play.gridY = tryY
                found = true
                break
            end
        end
        if not found then
            for tryY = S.play.gridY + 1, S.camBound.bottom - C.PLAYER_GRID_H + 1 do
                if not M.Collides(S.play.gridX, tryY) then
                    S.play.gridY = tryY
                    found = true
                    break
                end
            end
        end
        if found then
            log:Write(LOG_INFO, string.format("[RESET] Found valid position at (%d,%d)", S.play.gridX, S.play.gridY))
        else
            log:Write(LOG_WARNING, "[RESET] Could not find valid position, using spawn as-is")
        end
    end

    S.play.isOnGround        = false
    S.play.isJumping         = false
    S.play.jumpGridsRemain   = 0
    S.play.facingRight       = true
    S.play.moveTimer         = 0
    S.play.fallTimer         = 0
    S.play.fallTickCurrent   = C.PLAY_FALL_BASE
    S.play.jumpTimer         = 0
    S.play.fallGridCount     = 0
    S.play.alive             = true
    S.play.won               = false
    S.play.deathTimer        = 0
    M.deathPhase             = nil
    M.deathPhaseTimer        = 0
    M.bonfireMsg.active      = false
    S.play.isMoving          = false
    S.play.moveAnimTime      = 0
    S.play.fallAnimTime      = 0
    S.play.switchState       = {}
    S.play.collected         = {}
    S.play.hiddenWallRevealed = {}
    S.play.fragilePrevPlatform = nil
    S.play.fragileGone       = {}
    S.play.fragileParticles  = {}
    S.play.inWater           = false
    S.play.hasFireball       = false
    S.play.inBlackWater      = false
    S.play.waterDrainAccum   = 0
    S.play.isClimbing        = false
    S.play.climbTimer        = 0
    S.prevPlayLeft           = false
    S.prevPlayRight          = false
    S.playMoveFirst          = false
    S.playGameTime           = 0
    S.flameAnimTimer         = 0
    S.flameAnimFrame         = 0
    S.flameTime              = 0
    S.tipPixels              = {}
    S.tipSpawnTimer          = 0
    S.playFallParticles      = {}
    M.campfireParticles      = {}
    M.campfireIgniteEffect   = {}

    local zoom = S.playerParams.cameraZoom or 1.0
    local boundLeftPx  = (S.camBound.left - 1) * C.GRID
    local boundRightPx = S.camBound.right * C.GRID
    local viewW = S.playViewW * zoom
    local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)
    S.playCameraX = math.max(boundLeftPx, math.min((S.play.gridX - 1) * C.GRID - viewW * 0.35, camMaxX))

    local boundTopPx    = (S.camBound.top - 1) * C.GRID
    local boundBottomPx = S.camBound.bottom * C.GRID
    local viewH = S.playViewH * zoom
    local spawnY = (S.play.gridY - 1) * C.GRID
    local camMaxY = math.max(boundTopPx, boundBottomPx - viewH)
    S.playCameraY = math.max(boundTopPx, math.min(spawnY - viewH * 0.5, camMaxY))

    M.InitPlayPixels()
    PipeSystem.Init()
    FogOfWar.InitZoneVisibility(S.play.gridX + 1, S.play.gridY + 1)
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
-- 像素值同步
------------------------------------------------------------

function M.SyncFallGridCount()
    local pixelsPerGrid = math.max(1, math.floor(S.playTotalPixels / 10 + 0.5))
    S.play.fallGridCount = math.max(0, math.floor((S.playTotalPixels - S.playAlivePixels) / pixelsPerGrid))
end

------------------------------------------------------------
-- 投射物输入
------------------------------------------------------------

function M.HandleProjectileInput()
    if input:GetKeyPress(KEY_E) and not FlameDashChain.IsActive() then
        if not S.play.hasFireball then return end
        local fdx, fdy = 0, 0
        if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)  then fdx = fdx - 1 end
        if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then fdx = fdx + 1 end
        if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP)    then fdy = fdy - 1 end
        if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN)  then fdy = fdy + 1 end
        CrossLevel.LaunchProjectile(S.play.gridX, S.play.gridY, S.play.facingRight, fdx, fdy)
    end
end

------------------------------------------------------------
-- 主帧更新
------------------------------------------------------------

function M.Update(dt)
    -- GM 工具拖拽追踪（在所有逻辑之前，确保死亡/暂停时也能拖拽）
    if GMTool.IsDragging() then
        local mx = input:GetMousePosition().x / S.dpr / S.scaleF
        local my = input:GetMousePosition().y / S.dpr / S.scaleF
        local fitScale = math.min(S.screenDesignW / S.playViewW, S.screenDesignH / S.playViewH)
        local offsetX = (S.screenDesignW - S.playViewW * fitScale) * 0.5
        local offsetY = (S.screenDesignH - S.playViewH * fitScale) * 0.5
        GMTool.HandleMouseMove((mx - offsetX) / fitScale, (my - offsetY) / fitScale)
    end

    S.play.gameTime = S.play.gameTime + dt

    -- 死亡中由 deathPhase 自行处理 ESC，此处跳过
    if not S.play.alive then
        FogOfWar.UpdateTweens(dt)
        M.UpdateDeathRespawn(dt)
        M.UpdateBonfireMessage(dt)
        M.UpdateCampfireParticles(dt)
        M.UpdateFuelBurst(dt)
        return
    end

    -- 暂停时跳过游戏逻辑
    if PauseMenu.IsPaused() then
        return
    end

    if S.play.won then return end

    S.playGameTime = S.playGameTime + dt
    M.UpdateFlameTime(dt)
    M.UpdateTipPixels(dt)
    M.UpdateFallParticles(dt)

    -- 灯火跃迁更新
    local dashCtx = {
        gridX    = S.play.gridX,
        gridY    = S.play.gridY,
        gridSize = M.PlayerGridSize(),
        mapRows  = S.MAP_ROWS,
        onGround = function(gx, gy) return M.OnGround(gx, gy) end,
        isBodyBlocked = function(gx, gy)
            local s = M.PlayerGridSize()
            for dy = 0, s - 1 do
                for dx = 0, s - 1 do
                    if M.IsSolid(gx + dx, gy + dy) then return true end
                end
            end
            return false
        end,
        setPos = function(gx, gy)
            S.play.gridX = gx
            S.play.gridY = gy
        end,
        onLand = function()
            S.play.isOnGround      = true
            S.play.isJumping       = false
            S.play.fallTickCurrent = C.PLAY_FALL_BASE
            S.play.fallGridCount   = 0
            S.play.fallAnimTime    = 0
        end,
        onBoundary = function()
            S.play.alive      = false
            S.play.deathTimer = 0
        end,
        -- 跨地图跃迁支持（编辑器世界试玩模式）
        crossLevel = (S.editorMode == C.MODE_WORLDPLAY and S.worldPlayData and S.worldPlayCurrentFile) and {
            worldMapData       = S.worldPlayData,
            currentLevelFile   = S.worldPlayCurrentFile,
            findConnectedLevel = function(dir) return M.WorldPlayFindConnection(dir) end,
            loadLevel = function(targetFile)
                local json = CloudStorage.Load(targetFile)
                if not json then return false end
                local ok2, data = pcall(cjson.decode, json)
                if not ok2 or not data then return false end
                M.ApplyWorldLevelData(data)
                S.worldPlayCurrentFile = targetFile
                CrossLevel.ApplyCrossSwitches(targetFile)
                M._savedEditorLightSources = M._DeepCopyLightSources(FogOfWar.GetLightSources())
                M._RestoreCampfireLight()
                return true
            end,
            getMapSize = function() return S.MAP_COLS, S.MAP_ROWS end,
            player     = S.play,
            setCooldown = function(v) S.worldPlayCooldown = v end,
        } or nil,
        onCrossLevel = function()
            S.worldPlayCooldown    = 0.5
            S.play.isOnGround      = false
            S.play.isJumping       = false
            S.play.fallGridCount   = 0
            S.play.fallAnimTime    = 0
            M.SnapCameraToPlayer()
        end,
    }
    FlameDashChain.Update(dt, dashCtx)

    -- 跃迁期间跳过普通移动/跳跃/物理，只处理道具输入和视觉更新
    if FlameDashChain.IsActive() then
        M.HandleProjectileInput()
        CrossLevel.Update(dt)
    else
        M.HandleMovementInput(dt)
        M.HandleClimbInput(dt)
        M.HandleJumpInput()
        M.HandleProjectileInput()
        M.UpdateVerticalPhysics(dt)
        M.UpdateFragilePlatform(dt)
        CrossLevel.Update(dt)
    end
    M.UpdateBonfireMessage(dt)
    M.UpdateCampfireParticles(dt)
    M.UpdateFuelBurst(dt)
    M.UpdatePixelRecoverAnim(dt)

    if S.playAlivePixels <= 0 then
        S.play.alive      = false
        S.play.deathTimer = 0
    end
    M.CheckTiles()
    PipeSystem.Update(dt)

    -- 管道水流碰撞玩家（在水效果判定之前设置标志）
    if S.play.alive then
        local pipeHitType = PipeSystem.CheckPlayerHit()
        if pipeHitType then
            local tileType = C.PIPE_WATER_TYPES[pipeHitType]
            if tileType == C.TILE.POISON_WATER then
                S.play.alive      = false
                S.play.deathTimer = 0
            elseif tileType == C.TILE.WATER then
                S.play.inWater = true
            elseif tileType == C.TILE.BLACK_WATER then
                S.play.inBlackWater = true
            end
        end
    end

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

    CurtainRenderer.UpdateSway(dt)

    FogOfWar.UpdateTweens(dt)
    FogOfWar.UpdatePlayerZone(S.play.gridX + 1, S.play.gridY + 1, dt)

    -- GM 工具效果（覆盖本帧所有伤害/能量消耗）
    GMTool.ApplyEffects()

    -- 世界试玩模式：冷却递减
    if S.editorMode == C.MODE_WORLDPLAY then
        if S.worldPlayCooldown > 0 then
            S.worldPlayCooldown = S.worldPlayCooldown - dt
        end
        -- 过渡动画和边界检测由 editor.lua 统一调度
    end

    M.UpdateCamera(dt)
end

------------------------------------------------------------
-- 子模块挂载（Attach 顺序：被依赖的先挂）
------------------------------------------------------------

require("editor.play.Physics").Attach(M)
require("editor.play.TileCheck").Attach(M)
require("editor.play.Movement").Attach(M)
require("editor.play.FragilePlatform").Attach(M)
require("editor.play.Particles").Attach(M)
require("editor.play.Camera").Attach(M)
require("editor.play.WorldPlay").Attach(M)
require("editor.play.DeathRespawn").Attach(M)
require("editor.play.Lifecycle").Attach(M)
require("editor.play.Renderer").Attach(M)

return M
