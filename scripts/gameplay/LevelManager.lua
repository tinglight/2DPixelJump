------------------------------------------------------------
-- gameplay/LevelManager.lua — 关卡加载、世界地图切换、过渡动画
------------------------------------------------------------
local Config = require("gameplay.Config")

local M = {}

-- 外部依赖（通过 Inject 注入）
local LevelGenerator = nil
local CloudStorage = nil
local PixelSystem = nil
local Physics = nil

--- 注入依赖
---@param deps table { LevelGenerator, CloudStorage, PixelSystem, Physics }
function M.Inject(deps)
    LevelGenerator = deps.LevelGenerator
    CloudStorage = deps.CloudStorage
    PixelSystem = deps.PixelSystem
    Physics = deps.Physics
end

-- 地块类型
M.TILE = nil  -- 由 init 设置

-- ====================================================================
-- 关卡状态
-- ====================================================================
M.levelData = {}
M.currentDifficulty = "easy"
M.currentTemplateName = ""
M.levelNumber = 1

-- 开关/门状态
M.switchState = {}
M.switchCollected = {}
M.hiddenWallRevealed = {}
M.collectedItems = {}
M.coinCount = 0
M.fuelCount = 0

-- 存档点（篝火）状态
M.checkpointActivated = {}
M.checkpointCol = nil
M.checkpointRow = nil
M.checkpointFile = nil

-- ====================================================================
-- 世界地图连通
-- ====================================================================
M.worldMapData = nil
M.currentLevelFile = nil
M.worldMapLoaded = false
M.transitionCooldown = 0

-- 关卡切换过渡动画
M.transition = {
    active = false,
    phase = "none",
    alpha = 0,
    speed = 5.0,
    pendingFile = nil,
    pendingDir = nil,
}

-- 对玩家状态的回调引用（由 init 注入）
local playerResetCallback = nil
local recalcLayoutCallback = nil

function M.SetCallbacks(callbacks)
    playerResetCallback = callbacks.playerReset
    recalcLayoutCallback = callbacks.recalcLayout
end

-- ====================================================================
-- 全局玩家参数加载
-- ====================================================================

--- 从 data/player_params.json 加载全局玩家参数并应用到 Config
function M.LoadGlobalPlayerParams()
    local file = File("data/player_params.json", FILE_READ)
    if file and file:IsOpen() then
        local content = file:ReadString()
        file:Close()
        if content and content ~= "" then
            local ok, params = pcall(cjson.decode, content)
            if ok and params then
                Config.levelPlayerParams.baseJumpGrids = params.baseJumpGrids or Config.PLAYER_CONFIG.baseJumpGrids
                Config.levelPlayerParams.fallJumpMultiplier = params.fallJumpMultiplier or 1.0
                Config.levelPlayerParams.maxFallGrids = params.maxFallGrids or 10
                Config.levelPlayerParams.maxJumpGrids = params.maxJumpGrids or 8
                Config.PLAYER_CONFIG.defaultLightDiameter = params.defaultLightDiameter or 6
                Config.PLAYER_CONFIG.cameraZoom = params.cameraZoom or 2.0
                print("[PlayerParams] Loaded global player_params.json")
                return
            end
        end
    end
    -- 文件不存在或解析失败，使用默认值
    Config.levelPlayerParams.baseJumpGrids = Config.PLAYER_CONFIG.baseJumpGrids
    Config.levelPlayerParams.fallJumpMultiplier = 1.0
    Config.levelPlayerParams.maxFallGrids = 10
    Config.levelPlayerParams.maxJumpGrids = 8
    Config.PLAYER_CONFIG.cameraZoom = 2.0
    print("[PlayerParams] Using defaults (no player_params.json)")
end

-- ====================================================================
-- 关卡生成/加载
-- ====================================================================

--- 使用随机关卡生成器初始化关卡
---@param player table 玩家状态引用
function M.InitLevel(player)
    local map, spawnCol, spawnRow, templateName, diff =
        LevelGenerator.GenerateValid(M.currentDifficulty, 5, Config.MAP_COLS, Config.MAP_ROWS)

    M.levelData = map
    M.currentTemplateName = templateName or ""

    local playerH = math.ceil(Config.PLAYER_CONFIG.pixelGridSize * Config.PLAYER_CONFIG.pixelSize / Config.GRID)
    player.gridX = spawnCol
    player.gridY = spawnRow - (playerH - 1)

    -- 重置开关/门状态
    M.switchState = {}
    M.switchCollected = {}
    M.hiddenWallRevealed = {}

    -- 更新 Physics 引用
    Physics.SetLevelData(M.levelData)
    Physics.SetSwitchState(M.switchState)
    Physics.SetHiddenWallRevealed(M.hiddenWallRevealed)

    print(string.format("[Game] Level %d generated: difficulty=%s, template=%s",
        M.levelNumber, M.currentDifficulty, M.currentTemplateName))
end

--- 从云存档加载指定关卡文件到 levelData
---@param filename string
---@param player table 玩家状态引用
---@return boolean
function M.LoadLevelFromFile(filename, player)
    local json = CloudStorage.Load(filename)
    if not json then
        print("[WorldMap] Level not found: " .. filename)
        return false
    end
    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then
        print("[WorldMap] Parse failed: " .. filename)
        return false
    end

    -- 清空地图
    for row = 1, Config.MAP_ROWS do
        M.levelData[row] = {}
        for col = 1, Config.MAP_COLS do
            M.levelData[row][col] = 0
        end
    end

    -- 填充地块
    if data.tiles then
        for _, t in ipairs(data.tiles) do
            if t.row >= 1 and t.row <= Config.MAP_ROWS and t.col >= 1 and t.col <= Config.MAP_COLS then
                M.levelData[t.row][t.col] = t.v
            end
        end
    end

    -- 设置出生点
    local spawnCol = 3
    local spawnRow = Config.MAP_ROWS - 3
    if data.spawn then
        spawnCol = data.spawn.col or spawnCol
        spawnRow = data.spawn.row or spawnRow
    end

    local playerH = math.ceil(Config.PLAYER_CONFIG.pixelGridSize * Config.PLAYER_CONFIG.pixelSize / Config.GRID)
    player.gridX = spawnCol
    player.gridY = spawnRow - (playerH - 1)

    M.currentLevelFile = filename
    M.currentTemplateName = data.levelName or filename

    -- 重置开关/门状态
    M.switchState = {}
    M.switchCollected = {}
    M.hiddenWallRevealed = {}
    M.collectedItems = {}

    -- 玩家参数为全局配置（从 data/player_params.json 加载），不再从关卡数据读取

    if recalcLayoutCallback then recalcLayoutCallback() end

    -- 更新 Physics 引用
    Physics.SetLevelData(M.levelData)
    Physics.SetSwitchState(M.switchState)
    Physics.SetHiddenWallRevealed(M.hiddenWallRevealed)

    print("[WorldMap] Loaded level: " .. filename)
    return true
end

-- ====================================================================
-- 世界地图关卡切换
-- ====================================================================

--- 查找当前关卡在某方向上连通的目标关卡文件
function M.FindConnectedLevel(direction)
    if not M.worldMapData or not M.currentLevelFile then return nil end

    local currentNodeId = nil
    for _, node in ipairs(M.worldMapData.nodes or {}) do
        if node.file == M.currentLevelFile then
            currentNodeId = node.id
            break
        end
    end
    if not currentNodeId then return nil end

    for _, conn in ipairs(M.worldMapData.connections or {}) do
        if conn.fromId == currentNodeId and conn.direction == direction then
            for _, node in ipairs(M.worldMapData.nodes) do
                if node.id == conn.toId then
                    return node.file
                end
            end
        end
    end
    return nil
end

--- 执行关卡切换
---@param targetFile string
---@param fromDirection string "left"/"right"/"up"/"down"
---@param player table
---@param cameraState table { x }
function M.TransitionToLevel(targetFile, fromDirection, player, cameraState)
    if not M.LoadLevelFromFile(targetFile, player) then return end

    local playerH = math.ceil(Config.PLAYER_CONFIG.pixelGridSize * Config.PLAYER_CONFIG.pixelSize / Config.GRID)
    if fromDirection == "right" then
        player.gridX = 2
    elseif fromDirection == "left" then
        player.gridX = Config.MAP_COLS - 2
    elseif fromDirection == "down" then
        player.gridY = 2
    elseif fromDirection == "up" then
        player.gridY = Config.MAP_ROWS - playerH - 1
    end

    cameraState.x = 0
    player.isOnGround = false
    player.isJumping = false
    player.jumpGridsRemain = 0
    player.moveTimer = 0
    player.movedFirstStep = false
    player.fallTimer = 0
    player.fallTickCurrent = Config.PLAYER_CONFIG.fallTickBase
    player.jumpTimer = 0
    M.transitionCooldown = 0.5

    PixelSystem.Init()
    print("[WorldMap] Transition to: " .. targetFile .. " from " .. fromDirection)
end

--- 启动过渡动画
function M.StartLevelTransition(targetFile, fromDirection)
    M.transition.active = true
    M.transition.phase = "fadeOut"
    M.transition.alpha = 0
    M.transition.pendingFile = targetFile
    M.transition.pendingDir = fromDirection
end

--- 更新关卡切换过渡动画
---@param dt number
---@param player table
---@param cameraState table
function M.UpdateTransition(dt, player, cameraState)
    if not M.transition.active then return end

    local t = M.transition
    if t.phase == "fadeOut" then
        t.alpha = t.alpha + t.speed * dt
        if t.alpha >= 1.0 then
            t.alpha = 1.0
            if t.pendingFile then
                M.TransitionToLevel(t.pendingFile, t.pendingDir, player, cameraState)
            end
            t.phase = "fadeIn"
            t.pendingFile = nil
            t.pendingDir = nil
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

--- 检查玩家是否触碰边界并触发切换
---@param player table
---@return string|nil gameStateChange "gameover" if fell out
function M.CheckBoundaryTransition(player)
    if not M.worldMapData or not M.currentLevelFile then return nil end
    if M.transitionCooldown > 0 then return nil end
    if M.transition.active then return nil end

    local playerH = Physics.PlayerGridSize()

    if player.gridX <= 1 then
        local target = M.FindConnectedLevel("left")
        if target then
            M.StartLevelTransition(target, "left")
            return nil
        end
    end

    if player.gridX + playerH - 1 >= Config.MAP_COLS then
        local target = M.FindConnectedLevel("right")
        if target then
            M.StartLevelTransition(target, "right")
            return nil
        end
    end

    if player.gridY <= 1 then
        local target = M.FindConnectedLevel("up")
        if target then
            M.StartLevelTransition(target, "up")
            return nil
        end
    end

    if player.gridY + playerH - 1 >= Config.MAP_ROWS then
        local target = M.FindConnectedLevel("down")
        if target then
            M.StartLevelTransition(target, "down")
            return nil
        else
            return "gameover"
        end
    end

    return nil
end

--- 重置收集品状态
function M.ResetCollectibles()
    M.collectedItems = {}
    M.coinCount = 0
    M.fuelCount = 0
    M.switchState = {}
    M.switchCollected = {}
    M.hiddenWallRevealed = {}
    M.checkpointActivated = {}
    M.checkpointCol = nil
    M.checkpointRow = nil
    M.checkpointFile = nil
end

return M
