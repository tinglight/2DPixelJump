------------------------------------------------------------
-- gameplay/LevelManager.lua — 关卡加载、世界地图切换、过渡动画
------------------------------------------------------------
local Config = require("gameplay.Config")
local FogOfWar = require("FogOfWar")

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
M.hiddenWallRevealed = {}  -- group => revealTime (gameTime at reveal)
M.collectedItems = {}
M.coinCount = 0
M.fuelCount = 0

-- 装饰物
M.decorations = {}  -- { {col, row, typeId}, ... }

-- 当前游戏时间（由 init.lua 每帧同步）
M.gameTime = 0

-- 隐藏墙渐变消失时长（秒）
M.HIDDEN_WALL_FADE_DURATION = 0.2

-- 存档点（篝火）状态
M.checkpointActivated = {}
M.checkpointCol = nil
M.checkpointRow = nil
M.checkpointFile = nil

-- 永久解锁能力（跨死亡/篝火/跨图保留，仅新游戏重置）
M.playerUnlocks = {
    hasFireball = false,
    hasLanternDash = false,
}

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
    if not fileSystem:FileExists("data/player_params.json") then
        -- 文件不存在，使用默认值（避免 ERROR 日志）
        Config.levelPlayerParams.baseJumpGrids = Config.PLAYER_CONFIG.baseJumpGrids
        Config.levelPlayerParams.fallJumpMultiplier = 1.0
        Config.levelPlayerParams.maxFallGrids = 10
        Config.levelPlayerParams.maxJumpGrids = 8
        Config.PLAYER_CONFIG.cameraZoom = 2.0
        print("[PlayerParams] Using defaults (no player_params.json)")
        return
    end
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

    -- 背景图和明暗度
    local bgImg = (data.backgroundImage and data.backgroundImage ~= "") and data.backgroundImage or ""
    Config.backgroundImage = bgImg
    Config.bgImageAlpha = (data.bgImageAlpha and type(data.bgImageAlpha) == "number") and data.bgImageAlpha or 0.5

    -- 重置开关/门状态
    M.switchState = {}
    M.switchCollected = {}
    M.hiddenWallRevealed = {}
    M.collectedItems = {}

    -- 加载装饰物
    M.decorations = {}
    if data.decorations then
        for _, d in ipairs(data.decorations) do
            if d.col and d.row and d.typeId then
                table.insert(M.decorations, { col = d.col, row = d.row, typeId = d.typeId })
            end
        end
    end

    -- 玩家参数为全局配置（从 data/player_params.json 加载），不再从关卡数据读取

    -- 加载光源数据（灯笼 + 迷雾系统）
    FogOfWar.Deserialize(data.lightSources)
    if data.lightZones then
        FogOfWar.DeserializeZones(data.lightZones)
    end

    -- gameplay 模式：只有编辑器中标记为"无光"(extinguished)的灯才初始熄灭，
    -- 普通光源正常发光
    local lights = FogOfWar.GetLightSources()
    local litCount = 0
    local unlitCount = 0
    for _, light in ipairs(lights) do
        if light.extinguished then
            unlitCount = unlitCount + 1
        else
            litCount = litCount + 1
        end
    end
    print("[Gameplay] Loaded " .. #lights .. " lights: " .. litCount .. " lit, " .. unlitCount .. " unlit (need fireball)")

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
    -- 保存跨关卡持久状态（跳跃能力、血量）
    local savedFallGridCount = player.fallGridCount or 0
    local savedAlivePixels = PixelSystem and PixelSystem.alivePixels or nil

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

    -- 恢复跳跃能力：保留 fallGridCount，更新 bottomHighestY 为新位置
    player.fallGridCount = savedFallGridCount
    local s = Physics.PlayerGridSize()
    player.bottomHighestY = player.gridY + s - 1 - savedFallGridCount
    player.jumpOriginBottomY = player.gridY + s - 1
    -- 设置跨关卡保护，防止满血重置逻辑清零跳跃能力
    player.transitionProtect = true

    -- 保留血量而非满血重置（跨关卡不应回满血）
    if savedAlivePixels then
        -- 先初始化像素网格结构，然后恢复之前的血量
        PixelSystem.Init()
        PixelSystem.SetAliveCount(savedAlivePixels)
    else
        PixelSystem.Init()
    end

    print("[WorldMap] Transition to: " .. targetFile .. " from " .. fromDirection
        .. " (fallGridCount=" .. savedFallGridCount .. ")")
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

local EDGE_THRESHOLD = 4  -- 最多允许 4 格厚的边界墙

--- 检查玩家是否紧贴边缘实体墙（无法再靠近地图边缘）
--- 条件：1) 玩家距离边缘较近（间距 <= EDGE_THRESHOLD 格）
---       2) 玩家与边缘之间全部是实体方块
---@param player table
---@param direction string "left"|"right"|"up"|"down"
---@param playerS number 玩家格子尺寸
---@return boolean
local function IsPlayerAgainstEdgeWall(player, direction, playerS)
    if direction == "left" then
        local gap = player.gridX - 1  -- 玩家左侧到 col=1 的距离
        if gap < 1 or gap > EDGE_THRESHOLD then return false end
        for row = player.gridY, player.gridY + playerS - 1 do
            for col = 1, player.gridX - 1 do
                if not Physics.IsSolid(col, row) then return false end
            end
        end
        return true
    elseif direction == "right" then
        local rightEdge = player.gridX + playerS  -- 玩家右侧第一个空格
        local gap = Config.MAP_COLS - rightEdge + 1
        if gap < 1 or gap > EDGE_THRESHOLD then return false end
        for row = player.gridY, player.gridY + playerS - 1 do
            for col = rightEdge, Config.MAP_COLS do
                if not Physics.IsSolid(col, row) then return false end
            end
        end
        return true
    elseif direction == "up" then
        local gap = player.gridY - 1
        if gap < 1 or gap > EDGE_THRESHOLD then return false end
        for col = player.gridX, player.gridX + playerS - 1 do
            for row = 1, player.gridY - 1 do
                if not Physics.IsSolid(col, row) then return false end
            end
        end
        return true
    elseif direction == "down" then
        local bottomEdge = player.gridY + playerS
        local gap = Config.MAP_ROWS - bottomEdge + 1
        if gap < 1 or gap > EDGE_THRESHOLD then return false end
        for col = player.gridX, player.gridX + playerS - 1 do
            for row = bottomEdge, Config.MAP_ROWS do
                if not Physics.IsSolid(col, row) then return false end
            end
        end
        return true
    end
    return false
end

--- 检查玩家是否触碰边界并触发切换
--- 当画布边界（实体方块）与关卡边界重合时，玩家无法实际移动到最外格，
--- 因此需要检测"紧贴边界"的情况：玩家与地图边缘之间全是实体方块。
---@param player table
---@return string|nil gameStateChange "gameover" if fell out
function M.CheckBoundaryTransition(player)
    if not M.worldMapData or not M.currentLevelFile then return nil end
    if M.transitionCooldown > 0 then return nil end
    if M.transition.active then return nil end

    local playerS = Physics.PlayerGridSize()

    -- 左边界：玩家已到达 col=1，或贴紧左侧边缘实体墙
    local atLeft = player.gridX <= 1 or IsPlayerAgainstEdgeWall(player, "left", playerS)
    if atLeft then
        local target = M.FindConnectedLevel("left")
        if target then
            M.StartLevelTransition(target, "left")
            return nil
        end
    end

    -- 右边界：玩家右端已到达 MAP_COLS，或贴紧右侧边缘实体墙
    local atRight = player.gridX + playerS - 1 >= Config.MAP_COLS
        or IsPlayerAgainstEdgeWall(player, "right", playerS)
    if atRight then
        local target = M.FindConnectedLevel("right")
        if target then
            M.StartLevelTransition(target, "right")
            return nil
        end
    end

    -- 上边界：玩家已到达 row=1，或正在跳跃时贴紧顶部实体
    local atTop = player.gridY <= 1
        or (player.isJumping and IsPlayerAgainstEdgeWall(player, "up", playerS))
    if atTop then
        local target = M.FindConnectedLevel("up")
        if target then
            M.StartLevelTransition(target, "up")
            return nil
        end
    end

    -- 下边界：玩家下端已到达 MAP_ROWS（掉落出底部由 UpdateVertical 的 "boundary" 返回处理）
    if player.gridY + playerS - 1 >= Config.MAP_ROWS then
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

--- 重置收集品但保留篝火存档点信息
function M.ResetCollectiblesKeepCheckpoint()
    M.collectedItems = {}
    M.coinCount = 0
    M.fuelCount = 0
    M.switchState = {}
    M.switchCollected = {}
    M.hiddenWallRevealed = {}
    -- 篝火状态保留，不清除
end

return M
