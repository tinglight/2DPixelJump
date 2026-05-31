------------------------------------------------------------
-- gameplay/init.lua — 游戏主入口（模块编排、事件绑定、游戏循环）
------------------------------------------------------------
require "urhox-libs.UI.VirtualControls"
local LevelGenerator = require "LevelGenerator"
local CloudStorage = require "CloudStorage"
local GAME_VERSION = require "version"

-- 加载子模块
local Config = require("gameplay.Config")
local PixelSystem = require("gameplay.PixelSystem")
local Physics = require("gameplay.Physics")
local LevelManager = require("gameplay.LevelManager")
local PlayerController = require("gameplay.PlayerController")
local Animation = require("gameplay.Animation")
local Renderer = require("gameplay.Renderer")
local CurtainRenderer = require("CurtainRenderer")
local FlameDashChain = require("gameplay.FlameDashChain")
local Fireball = require("gameplay.Fireball")
local FogOfWar = require("FogOfWar")

-- ====================================================================
-- 注入依赖
-- ====================================================================
Physics.Inject({
    levelData = {},
    switchState = {},
    hiddenWallRevealed = {},
    TILE = LevelGenerator.TILE,
    LevelManager = LevelManager,
})

LevelManager.Inject({
    LevelGenerator = LevelGenerator,
    CloudStorage = CloudStorage,
    PixelSystem = PixelSystem,
    Physics = Physics,
})
LevelManager.TILE = LevelGenerator.TILE

PlayerController.Inject({
    Physics = Physics,
    PixelSystem = PixelSystem,
    LevelManager = LevelManager,
    Animation = Animation,
    Renderer = Renderer,
    CurtainRenderer = CurtainRenderer,
    Fireball = Fireball,
})

Animation.Inject({
    Physics = Physics,
    PixelSystem = PixelSystem,
    PlayerController = PlayerController,
})

Renderer.Inject({
    Physics = Physics,
    PixelSystem = PixelSystem,
    PlayerController = PlayerController,
    LevelManager = LevelManager,
    Animation = Animation,
})

FlameDashChain.Inject({
    LevelManager = LevelManager,
    PlayerController = PlayerController,
    Physics = Physics,
})

Fireball.Inject({
    Physics = Physics,
    PlayerController = PlayerController,
    LevelManager = LevelManager,
    FlameDashChain = FlameDashChain,
})

-- ====================================================================
-- FogOfWar 光源系统初始化
-- ====================================================================
FogOfWar.SetCollisionChecker(function(col, row)
    return Physics.IsSolidForLight(col, row)
end)
FogOfWar.SetCurtainChecker(function(col, row)
    return CurtainRenderer.IsCurtainAt(col, row, LevelManager.levelData,
        LevelGenerator.TILE, Physics.GetTileType)
end)
FogOfWar.SetWaterChecker(function(col, row)
    if row < 1 or row > Config.MAP_ROWS or col < 1 or col > Config.MAP_COLS then return false end
    local val = LevelManager.levelData[row] and LevelManager.levelData[row][col]
    if not val or val == 0 then return false end
    local base = Physics.GetTileType(val)
    return base == LevelGenerator.TILE.WATER or base == LevelGenerator.TILE.POISON_WATER or base == LevelGenerator.TILE.BLACK_WATER
end)

-- ====================================================================
-- 游戏运行时状态
-- ====================================================================
local gameState = Config.STATE_PLAYING
local gameTime = 0
local cameraX = 0

-- NanoVG
local vg = nil

-- 分辨率
local physW, physH, dpr, logicalW, logicalH
local scale, screenDesignW, screenDesignH, designOffsetX, designOffsetY

-- 输入
local inputState = { jumpPressed = false }
local prevLeft = false
local prevRight = false

-- 网格显示（默认隐藏，Shift 切换）
local gridVisible = false

-- 虚拟控件
local vc_joystick = nil
local vc_jumpBtn = nil

-- ====================================================================
-- 布局计算
-- ====================================================================
local function RecalcLayout()
    physW, physH = graphics:GetWidth(), graphics:GetHeight()
    dpr = graphics:GetDPR()
    logicalW, logicalH = physW / dpr, physH / dpr
    local zoom = Config.PLAYER_CONFIG.cameraZoom or 1.0
    local effectiveW = Config.DESIGN_W * zoom
    local effectiveH = Config.DESIGN_H * zoom
    scale = math.min(logicalW / effectiveW, logicalH / effectiveH)
    screenDesignW = logicalW / scale
    screenDesignH = logicalH / scale
    designOffsetX = (screenDesignW - effectiveW) / 2
    designOffsetY = (screenDesignH - effectiveH) / 2
end

-- 注册 RecalcLayout 回调
LevelManager.SetCallbacks({
    recalcLayout = RecalcLayout,
})

-- ====================================================================
-- 游戏流程
-- ====================================================================

--- 进入死亡状态（立即清除飞行中的火球和跃迁链）
local function EnterGameOver()
    gameState = Config.STATE_GAMEOVER
    Fireball.Reset()
    FlameDashChain.Reset()
end

--- 重置游戏（从篝火存档点复活，或重新开始）
local function ResetGame()
    local player = PlayerController.player
    PlayerController.ResetPlayer()
    cameraX = 0
    gameState = Config.STATE_PLAYING
    gameTime = 0
    LevelManager.gameTime = 0

    Animation.Reset()
    CurtainRenderer.ClearSway()
    FlameDashChain.Reset()
    Fireball.Reset()
    FogOfWar.ResetZoneState()

    -- 如果有篝火存档点，从存档点复活
    if LevelManager.checkpointCol and LevelManager.checkpointRow and LevelManager.checkpointFile then
        local cpFile = LevelManager.checkpointFile
        local cpCol = LevelManager.checkpointCol
        local cpRow = LevelManager.checkpointRow

        -- 重置收集品但保留篝火存档信息
        LevelManager.ResetCollectiblesKeepCheckpoint()

        -- 加载存档点所在关卡（可能跨关卡）
        if cpFile ~= LevelManager.currentLevelFile then
            LevelManager.LoadLevelFromFile(cpFile, player)
        else
            LevelManager.LoadLevelFromFile(LevelManager.currentLevelFile, player)
        end

        -- 将玩家放置在篝火位置
        local playerH = math.ceil(Config.PLAYER_CONFIG.pixelGridSize * Config.PLAYER_CONFIG.pixelSize / Config.GRID)
        player.gridX = cpCol
        player.gridY = cpRow - (playerH - 1)

        -- 恢复篝火激活状态
        local key = cpRow .. "_" .. cpCol
        LevelManager.checkpointActivated[key] = true
        LevelManager.checkpointCol = cpCol
        LevelManager.checkpointRow = cpRow
        LevelManager.checkpointFile = cpFile
    else
        -- 没有存档点，正常重置
        LevelManager.ResetCollectibles()
        if LevelManager.currentLevelFile then
            LevelManager.LoadLevelFromFile(LevelManager.currentLevelFile, player)
        else
            LevelManager.InitLevel(player)
        end
    end

    PixelSystem.Init()

    -- 初始化光源区域可见性
    FogOfWar.InitZoneVisibility(player.gridX + 1, player.gridY + 1)
end

--- 进入下一关
local function NextLevel()
    LevelManager.levelNumber = LevelManager.levelNumber + 1
    if LevelManager.levelNumber <= 3 then
        LevelManager.currentDifficulty = "easy"
    elseif LevelManager.levelNumber <= 6 then
        LevelManager.currentDifficulty = "normal"
    else
        LevelManager.currentDifficulty = "hard"
    end
    ResetGame()
end

--- 切换难度并重新生成
local function SetDifficulty(diff)
    LevelManager.currentDifficulty = diff
    ResetGame()
end

-- ====================================================================
-- 关卡加载完成后的统一初始化
-- ====================================================================

--- 加载关卡文件并初始化所有运行时系统（PixelSystem、FogOfWar、玩家位置等）
---@param filename string 关卡文件名
---@param player table 玩家状态引用
local function M_LoadAndInitLevel(filename, player)
    local ok = LevelManager.LoadLevelFromFile(filename, player)
    if not ok then
        print("[Gameplay] Failed to load level: " .. tostring(filename))
        -- 回退到第一个节点
        if LevelManager.worldMapData and LevelManager.worldMapData.nodes[1] then
            local fallback = LevelManager.worldMapData.nodes[1].file
            if fallback ~= filename then
                LevelManager.LoadLevelFromFile(fallback, player)
            end
        end
    end

    -- 如果是继续游戏且有存档点，将玩家放在篝火位置
    if LevelManager.checkpointFile == filename and LevelManager.checkpointCol and LevelManager.checkpointRow then
        local playerH = math.ceil(Config.PLAYER_CONFIG.pixelGridSize * Config.PLAYER_CONFIG.pixelSize / Config.GRID)
        player.gridX = LevelManager.checkpointCol
        player.gridY = LevelManager.checkpointRow - (playerH - 1)
    end

    -- 初始化运行时系统
    PixelSystem.Init()
    FogOfWar.InitZoneVisibility(player.gridX + 1, player.gridY + 1)
    CurtainRenderer.ClearSway()
    FlameDashChain.Reset()
    Fireball.Reset()
    player.fallTickCurrent = Config.PLAYER_CONFIG.fallTickBase

    -- 恢复永久能力到玩家状态
    if LevelManager.playerUnlocks.hasFireball then
        player.hasFireball = true
    end

    -- 重置相机和游戏状态
    cameraX = 0
    gameState = Config.STATE_PLAYING
    gameTime = 0
    LevelManager.gameTime = 0

    print("[Gameplay] Level loaded and initialized: " .. tostring(filename))
end

-- ====================================================================
-- 引擎入口
-- ====================================================================
function Start()
    -- 如果作为主入口被调用，跳转到 main.lua（保留主菜单和编辑器入口）
    ---@diagnostic disable-next-line: undefined-global
    if not _GAMEPLAY_DIRECT then
        require "main"
        return Start()  -- main.lua 重新定义了 Start()，调用它
    end

    print("=== Pixel Flame Platformer v3 ===")

    RecalcLayout()

    vg = nvgCreate(1)
    if vg == nil then
        print("ERROR: nvgCreate failed")
        return
    end

    if nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf") == -1 then
        print("ERROR: font load failed")
        return
    end

    -- 加载全局玩家参数
    LevelManager.LoadGlobalPlayerParams()

    -- 进入 loading 状态，等待关卡数据加载完成
    gameState = Config.STATE_PLAYING  -- 暂时设为 playing，渲染黑屏直到关卡加载完成
    local player = PlayerController.player

    -- 初始化空地图和像素系统（防止异步加载期间渲染 nil 访问）
    for row = 1, Config.MAP_ROWS do
        LevelManager.levelData[row] = LevelManager.levelData[row] or {}
        for col = 1, Config.MAP_COLS do
            LevelManager.levelData[row][col] = LevelManager.levelData[row][col] or 0
        end
    end
    Physics.SetLevelData(LevelManager.levelData)
    Physics.SetSwitchState(LevelManager.switchState)
    Physics.SetHiddenWallRevealed(LevelManager.hiddenWallRevealed)
    PixelSystem.Init()

    -- CloudStorage.Init（MainMenu 已调用过，这里会快速返回缓存）
    CloudStorage.Init(function(ok)
        if not ok then
            print("[Gameplay] CloudStorage.Init failed, cannot load levels")
            return
        end
        CloudStorage.InitWorldMap(function(wmOk)
            if not wmOk then
                print("[Gameplay] InitWorldMap failed")
                return
            end

            LevelManager.worldMapData = CloudStorage.LoadWorldMap()
            if not LevelManager.worldMapData or not LevelManager.worldMapData.nodes or #LevelManager.worldMapData.nodes == 0 then
                print("[Gameplay] No world map nodes found")
                return
            end
            LevelManager.worldMapLoaded = true

            ---@diagnostic disable-next-line: undefined-global
            local mode = _GAMEPLAY_MODE or "new"
            print("[Gameplay] Mode: " .. mode)

            if mode == "continue" then
                -- 继续游戏：读取存档中的进度
                clientCloud:Get("player_progress", {
                    ok = function(values)
                        local progress = values.player_progress
                        local targetFile = nil
                        if progress then
                            -- 优先使用存档中的 checkpointFile
                            if progress.checkpointFile and progress.checkpointFile ~= "" then
                                targetFile = progress.checkpointFile
                                LevelManager.checkpointFile = progress.checkpointFile
                                LevelManager.checkpointCol = progress.checkpointCol
                                LevelManager.checkpointRow = progress.checkpointRow
                                -- 恢复篝火激活状态
                                if progress.checkpointCol and progress.checkpointRow then
                                    local key = progress.checkpointRow .. "_" .. progress.checkpointCol
                                    LevelManager.checkpointActivated[key] = true
                                end
                            elseif progress.currentLevelFile and progress.currentLevelFile ~= "" then
                                targetFile = progress.currentLevelFile
                            end
                            -- 恢复永久解锁能力
                            if progress.playerUnlocks then
                                LevelManager.playerUnlocks.hasFireball = progress.playerUnlocks.hasFireball or false
                                LevelManager.playerUnlocks.hasLanternDash = progress.playerUnlocks.hasLanternDash or false
                            end
                        end
                        -- 如果没有有效存档文件，回退到第一个节点
                        if not targetFile or not CloudStorage.Exists(targetFile) then
                            targetFile = LevelManager.worldMapData.nodes[1].file
                            LevelManager.checkpointFile = nil
                            LevelManager.checkpointCol = nil
                            LevelManager.checkpointRow = nil
                        end
                        -- 加载关卡
                        M_LoadAndInitLevel(targetFile, player)
                    end,
                    err = function()
                        -- 读取失败，回退到第一个节点
                        print("[Gameplay] Failed to read progress, starting from first node")
                        local targetFile = LevelManager.worldMapData.nodes[1].file
                        M_LoadAndInitLevel(targetFile, player)
                    end
                })
            else
                -- 新游戏：清空进度，从第一个节点开始
                LevelManager.ResetCollectibles()
                LevelManager.playerUnlocks.hasFireball = false
                LevelManager.playerUnlocks.hasLanternDash = false
                player.hasFireball = false

                local firstFile = LevelManager.worldMapData.nodes[1].file
                -- 清空云端进度（异步，不阻塞加载）
                clientCloud:Set("player_progress", {}, {
                    ok = function() print("[Gameplay] Progress cleared for new game") end,
                    err = function() print("[Gameplay] Failed to clear progress") end
                })
                M_LoadAndInitLevel(firstFile, player)
            end

            print("[WorldMap] Loaded with " .. #LevelManager.worldMapData.nodes .. " levels, "
                .. #(LevelManager.worldMapData.connections or {}) .. " connections")
        end)
    end)

    -- 虚拟控件
    vc_joystick = VirtualControls.CreateJoystick({ side = "left" })
    vc_jumpBtn = VirtualControls.CreateButton({
        side = "right",
        label = "Jump",
        onPressed = function()
            inputState.jumpPressed = true
        end,
    })

    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")

    print("Controls: A/D = move, Space = jump, E = flame dash, R = reset")
    print("Collect fuel orbs to restore your flame!")
end

function Stop()
    if vg then nvgDelete(vg); vg = nil end
end

-- ====================================================================
-- 事件处理
-- ====================================================================

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end

    nvgBeginFrame(vg, logicalW, logicalH, dpr)
    nvgScale(vg, scale, scale)

    Renderer.SetContext({
        vg = vg,
        screenDesignW = screenDesignW,
        screenDesignH = screenDesignH,
        cameraX = cameraX,
        gameTime = gameTime,
        gameState = gameState,
    })

    Renderer.DrawBackground()

    nvgSave(vg)
    nvgTranslate(vg, designOffsetX, designOffsetY)

    if gridVisible then
        Renderer.DrawGrid()
    end
    Renderer.DrawDecorations()
    Renderer.DrawMap()
    Renderer.DrawFuelBurst()
    Renderer.DrawFireball()
    Renderer.DrawPlayer()
    Renderer.DrawFogOfWar()

    nvgRestore(vg)

    Renderer.DrawHUD()
    Renderer.DrawLevelTransition()

    nvgEndFrame(vg)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if gameState ~= Config.STATE_PLAYING then return end
    local dt = eventData["TimeStep"]:GetFloat()

    gameTime = gameTime + dt
    LevelManager.gameTime = gameTime

    -- 更新 BONFIRE LIT 消息
    Renderer.UpdateBonfireMessage(dt)
    Renderer.UpdateCampfireParticles(dt)

    -- 更新火苗爆裂粒子和像素恢复动画
    Renderer.UpdateFuelBurst(dt)
    Renderer.UpdatePixelRecoverAnim(dt)

    -- 更新柳条门帘晃动动画
    CurtainRenderer.UpdateSway(dt)

    -- 更新迷雾光源动画和区域可见性
    FogOfWar.UpdateTweens(dt)
    FogOfWar.UpdatePlayerZone(PlayerController.player.gridX + 1, PlayerController.player.gridY + 1, dt)

    -- 世界地图切换冷却
    if LevelManager.transitionCooldown > 0 then
        LevelManager.transitionCooldown = LevelManager.transitionCooldown - dt
    end

    -- 过渡动画更新
    local cameraState = { x = cameraX }
    LevelManager.UpdateTransition(dt, PlayerController.player, cameraState)
    cameraX = cameraState.x
    if LevelManager.transition.active then return end

    -- 灯火跃迁更新
    local dashPlayer = PlayerController.player
    local dashCtx = {
        gridX = dashPlayer.gridX,
        gridY = dashPlayer.gridY,
        gridSize = Config.PLAYER_CONFIG.playerGridSize or 2,
        mapRows = Config.MAP_ROWS,
        onGround = function(gx, gy)
            return Physics.PlayerOnGround(gx, gy)
        end,
        isBodyBlocked = function(gx, gy)
            return Physics.PlayerCollidesAt(gx, gy)
        end,
        setPos = function(gx, gy)
            dashPlayer.gridX = gx
            dashPlayer.gridY = gy
        end,
        onLand = function()
            dashPlayer.isOnGround = true
            dashPlayer.isJumping = false
            dashPlayer.fallGridCount = 0
            dashPlayer.bottomHighestY = dashPlayer.gridY
        end,
        onBoundary = function()
            EnterGameOver()
        end,
        onCrossLevel = function()
            -- 跨关卡跃迁完成后刷新渲染/相机状态
            cameraX = 0
            dashPlayer.isOnGround = false
            dashPlayer.isJumping = false
            dashPlayer.fallGridCount = 0
            dashPlayer.moveTimer = 0
            dashPlayer.fallTimer = 0
            LevelManager.transitionCooldown = 0.5
        end,
    }
    local dashResult = FlameDashChain.Update(dt, dashCtx)

    -- 火球飞行更新
    Fireball.Update(dt)

    -- 跃迁期间跳过普通移动/跳跃/垂直物理
    if FlameDashChain.IsActive() then
        -- 跃迁期间仍更新动画表现
        Animation.Update(dt, gameTime)
        return
    end

    -- 表现层动画更新
    Animation.Update(dt, gameTime)

    -- 读取输入
    local curLeft = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
    local curRight = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)

    if vc_joystick then
        local jx, _ = vc_joystick:getInput()
        if jx < -0.3 then curLeft = true end
        if jx > 0.3 then curRight = true end
    end

    -- 水平移动
    local dir = 0
    if curLeft and not curRight then dir = -1
    elseif curRight and not curLeft then dir = 1 end

    local player = PlayerController.player
    if dir ~= 0 then
        local justPressed = false
        if dir == -1 and not prevLeft then justPressed = true end
        if dir == 1 and not prevRight then justPressed = true end

        if justPressed then
            PlayerController.PlayerMoveOneGrid(dir)
            player.moveTimer = 0
            player.movedFirstStep = true
        else
            player.moveTimer = player.moveTimer + dt
            if player.moveTimer >= Config.PLAYER_CONFIG.moveTickRate then
                player.moveTimer = player.moveTimer - Config.PLAYER_CONFIG.moveTickRate
                PlayerController.PlayerMoveOneGrid(dir)
            end
        end
        player.isMoving = true
        player.moveAnimTime = player.moveAnimTime + dt
    else
        player.moveTimer = 0
        player.movedFirstStep = false
        player.isMoving = false
        player.moveAnimTime = 0
    end

    prevLeft = curLeft
    prevRight = curRight

    -- 跳跃
    if inputState.jumpPressed then
        PlayerController.PlayerJump()
        inputState.jumpPressed = false
    end

    -- 垂直物理
    local vertResult = PlayerController.UpdateVertical(dt)
    if vertResult == "gameover" then
        EnterGameOver()
        return
    elseif vertResult == "boundary" then
        -- 玩家下落超出地图底部，检查是否有连接关卡可传送
        if LevelManager.worldMapData and LevelManager.currentLevelFile then
            local target = LevelManager.FindConnectedLevel("down")
            if target and not LevelManager.transition.active then
                LevelManager.StartLevelTransition(target, "down")
            elseif not target then
                EnterGameOver()
            end
        else
            EnterGameOver()
        end
        return
    end

    -- 收集检测
    local collectResult = PlayerController.CheckItemCollection()
    if collectResult == "gameover" then
        EnterGameOver()
        return
    elseif collectResult == "win" then
        gameState = Config.STATE_WIN
        return
    end

    -- 世界地图边界切换检测
    local boundaryResult = LevelManager.CheckBoundaryTransition(player)
    if boundaryResult == "gameover" then
        EnterGameOver()
        return
    end

    -- 相机
    local zoom = Config.PLAYER_CONFIG.cameraZoom or 1.0
    local visibleW = Config.DESIGN_W * zoom
    local playerPx = (player.gridX - 1) * Config.GRID
    local targetCam = playerPx - visibleW * 0.35
    targetCam = math.max(0, math.min(targetCam, Config.MAP_COLS * Config.GRID - visibleW))
    cameraX = cameraX + (targetCam - cameraX) * math.min(1, dt * 8)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_SPACE or key == KEY_W or key == KEY_UP then
        inputState.jumpPressed = true
    end
    if key == KEY_E then
        -- 火球发射（命中亮灯时由 Fireball 模块触发跃迁）
        if gameState == Config.STATE_PLAYING and not FlameDashChain.IsActive() then
            local player = PlayerController.player
            if player.hasFireball then
                local fdx, fdy = 0, 0
                if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then fdx = fdx - 1 end
                if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then fdx = fdx + 1 end
                if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then fdy = fdy - 1 end
                if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then fdy = fdy + 1 end
                Fireball.Shoot(fdx, fdy)
            end
        end
    end
    if key == KEY_R then
        ResetGame()
    end
    if key == KEY_N then
        NextLevel()
    end
    if key == KEY_1 then
        SetDifficulty("easy")
    end
    if key == KEY_2 then
        SetDifficulty("normal")
    end
    if key == KEY_3 then
        SetDifficulty("hard")
    end
    if key == KEY_LSHIFT or key == KEY_RSHIFT then
        gridVisible = not gridVisible
    end
    if key == KEY_ESCAPE then
        engine:Exit()
    end
end

function HandleScreenMode(eventType, eventData)
    RecalcLayout()
end
