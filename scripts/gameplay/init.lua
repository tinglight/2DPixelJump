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

-- ====================================================================
-- 注入依赖
-- ====================================================================
Physics.Inject({
    levelData = {},
    switchState = {},
    hiddenWallRevealed = {},
    TILE = LevelGenerator.TILE,
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

--- 重置游戏
local function ResetGame()
    local player = PlayerController.player
    PlayerController.ResetPlayer()
    cameraX = 0
    LevelManager.ResetCollectibles()
    gameState = Config.STATE_PLAYING
    gameTime = 0

    Animation.Reset()

    -- 重新初始化关卡
    if LevelManager.currentLevelFile then
        LevelManager.LoadLevelFromFile(LevelManager.currentLevelFile, player)
    else
        LevelManager.InitLevel(player)
    end
    PixelSystem.Init()
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
-- 引擎入口
-- ====================================================================
function Start()
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

    -- 初始化关卡和像素
    local player = PlayerController.player
    LevelManager.InitLevel(player)
    PixelSystem.Init()
    player.fallTickCurrent = Config.PLAYER_CONFIG.fallTickBase

    -- 加载世界地图连通数据（异步）
    CloudStorage.Init(function(ok)
        if ok then
            CloudStorage.InitWorldMap(function(wmOk)
                if wmOk then
                    LevelManager.worldMapData = CloudStorage.LoadWorldMap()
                    if LevelManager.worldMapData and LevelManager.worldMapData.nodes and #LevelManager.worldMapData.nodes > 0 then
                        LevelManager.worldMapLoaded = true
                        local firstNode = LevelManager.worldMapData.nodes[1]
                        if firstNode and firstNode.file then
                            LevelManager.LoadLevelFromFile(firstNode.file, player)
                            PixelSystem.Init()
                        end
                        print("[WorldMap] Loaded with " .. #LevelManager.worldMapData.nodes .. " levels, " .. #LevelManager.worldMapData.connections .. " connections")
                    else
                        print("[WorldMap] No world map data, using random levels")
                    end
                end
            end)
        end
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

    print("Controls: A/D = move, Space = jump, R = reset")
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

    Renderer.DrawGrid()
    Renderer.DrawMap()
    Renderer.DrawFuelBurst()
    Renderer.DrawPlayer()

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

    -- 更新 BONFIRE LIT 消息
    Renderer.UpdateBonfireMessage(dt)

    -- 更新火苗爆裂粒子和像素恢复动画
    Renderer.UpdateFuelBurst(dt)
    Renderer.UpdatePixelRecoverAnim(dt)

    -- 世界地图切换冷却
    if LevelManager.transitionCooldown > 0 then
        LevelManager.transitionCooldown = LevelManager.transitionCooldown - dt
    end

    -- 过渡动画更新
    local cameraState = { x = cameraX }
    LevelManager.UpdateTransition(dt, PlayerController.player, cameraState)
    cameraX = cameraState.x
    if LevelManager.transition.active then return end

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
        gameState = Config.STATE_GAMEOVER
        return
    elseif vertResult == "boundary" then
        -- 玩家下落超出地图底部，检查是否有连接关卡可传送
        if LevelManager.worldMapData and LevelManager.currentLevelFile then
            local target = LevelManager.FindConnectedLevel("down")
            if target and not LevelManager.transition.active then
                LevelManager.StartLevelTransition(target, "down")
            elseif not target then
                gameState = Config.STATE_GAMEOVER
            end
        else
            gameState = Config.STATE_GAMEOVER
        end
        return
    end

    -- 收集检测
    local collectResult = PlayerController.CheckItemCollection()
    if collectResult == "gameover" then
        gameState = Config.STATE_GAMEOVER
        return
    elseif collectResult == "win" then
        gameState = Config.STATE_WIN
        return
    end

    -- 世界地图边界切换检测
    local boundaryResult = LevelManager.CheckBoundaryTransition(player)
    if boundaryResult == "gameover" then
        gameState = Config.STATE_GAMEOVER
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
    if key == KEY_ESCAPE then
        engine:Exit()
    end
end

function HandleScreenMode(eventType, eventData)
    RecalcLayout()
end
