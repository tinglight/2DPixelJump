-- ====================================================================
-- PixelPlatformer.lua - 火焰像素横板平台跳跃游戏 v3
-- ====================================================================
--
-- 【核心规则】:
-- 1. 格子系统: 每格 16 像素，所有运动严格以格子为单位
-- 2. 逐格移动: 每次按键/持续按住恰好移动 1 格
-- 3. 跳跃高度: 与角色像素点数量成反比（像素越多跳越低）
-- 4. 下落缩小: 下落时从火焰左右两侧逐渐剥离像素
--
-- 【火焰主题】:
-- 角色是一团火焰，下落减少燃烧
-- 火焰有摇晃闪烁效果
-- 移动动画：左右摇晃行走
-- 下落动画：火焰摇晃幅度变大
-- 场景中有燃料奖励，吃到可恢复火焰
--
-- ====================================================================

require "urhox-libs.UI.VirtualControls"
local LevelGenerator = require "LevelGenerator"
local CloudStorage = require "CloudStorage"
local GAME_VERSION = require "version"

-- ====================================================================
-- 游戏常量
-- ====================================================================
local GRID = 16  -- 每格 16 设计像素

-- 设计分辨率
local DESIGN_W = 480
local DESIGN_H = 272  -- 17 格高

-- 地图尺寸（格子数）
local MAP_COLS = 60
local MAP_ROWS = 17

-- ====================================================================
-- 角色配置（开放接口）
-- ====================================================================
local PLAYER_CONFIG = {
    pixelGridSize = 10,    -- 10x10 像素点阵列（火焰更细腻）
    pixelSize = 3,         -- 每个像素点 3px（10*3=30px 总尺寸 ≈ 2格）

    -- 跳跃配置
    baseJumpGrids = 3,     -- 满像素时的基础跳跃格数

    -- 移动节奏（秒/格）
    moveTickRate = 0.10,
    fallTickBase = 0.12,
    fallTickMin = 0.04,
    fallAccel = 0.015,
    jumpTickRate = 0.07,

    -- 下落剥离配置（每下降1格剥离 totalPixels/10 个像素）
    recoverPerSec = 6,

    -- 动画参数
    flickerSpeed = 8.0,     -- 火焰闪烁速度
    walkSwaySpeed = 12.0,   -- 行走摇晃速度
    walkSwayAngle = 0.15,   -- 行走摇晃角度（弧度）
    fallSwaySpeed = 6.0,    -- 下落摇晃速度
    fallSwayAngle = 0.35,   -- 下落摇晃角度（更大）
    idleSwaySpeed = 3.0,    -- 静止微摇
    idleSwayAngle = 0.05,   -- 静止摇晃角度

    -- 灯笼晃动参数
    lanternSwayFreq = 5.0,   -- 灯笼摆动频率
    lanternSwayDamp = 0.80,  -- 阻尼衰减
    lanternMaxAngle = 6.0,   -- 最大摆幅（连续值，映射到像素格）

    -- 下落火苗四散粒子
    fallParticleCount = 8,   -- 最大粒子数
    fallParticleLife = 0.6,  -- 粒子生命周期（秒）

    -- 起跳像素压缩
    jumpSquashFrames = 4,    -- 压缩动画帧数
    jumpStretchFrames = 6,   -- 拉伸动画帧数

    -- 跳不动抖动
    cantJumpShakeDur = 0.25, -- 抖动持续时间
    cantJumpShakeAmp = 2,    -- 抖动幅度（像素格）

    -- 主角默认光源
    defaultLightDiameter = 6, -- 满血时光源直径（格子数），火焰减弱时同步降低，最低为0

    -- 相机配置
    cameraZoom = 1.0,  -- 相机缩放倍率：1.0=默认视野，>1.0=看到更多世界（缩小），<1.0=看到更少（放大）
}

-- 关卡级玩家参数（由 LoadLevelFromFile 从关卡文件覆盖）
local levelPlayerParams = {
    baseJumpGrids = PLAYER_CONFIG.baseJumpGrids,  -- 满血跳跃格数
    fallJumpMultiplier = 1.0,                     -- 每下落1格增加的跳跃高度倍率
    maxFallGrids = 10,                            -- 最大下落格数（超过则死亡）
    maxJumpGrids = 8,                             -- 最大跳跃高度（格）
}

-- ====================================================================
-- 火焰形状定义（尖顶宽底的火焰轮廓）
-- 10x10 像素点阵
-- ====================================================================
local CHAR_SHAPE = {
    { 0, 0, 0, 0, 1, 1, 0, 0, 0, 0 },  -- row1: 火焰尖端
    { 0, 0, 0, 1, 1, 1, 1, 0, 0, 0 },  -- row2
    { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },  -- row3
    { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },  -- row4
    { 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 },  -- row5: 火焰中部
    { 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 },  -- row6
    { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },  -- row7: 宽处
    { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },  -- row8
    { 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 },  -- row9: 底部内收
    { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },  -- row10: 底部
}

-- 火焰颜色：从上到下 白芯→黄→橙→红→深红
-- 每行一个基础颜色，渲染时会叠加闪烁变化
local FLAME_COLORS = {
    [1]  = { 255, 255, 220 },  -- 白黄尖端（最亮）
    [2]  = { 255, 240, 150 },  -- 亮黄
    [3]  = { 255, 220, 80 },   -- 黄色
    [4]  = { 255, 200, 50 },   -- 金黄
    [5]  = { 255, 160, 30 },   -- 橙黄
    [6]  = { 255, 130, 20 },   -- 橙色
    [7]  = { 240, 90, 10 },    -- 深橙
    [8]  = { 220, 60, 5 },     -- 红橙
    [9]  = { 200, 40, 5 },     -- 红色
    [10] = { 160, 20, 5 },     -- 深红底部
}

-- ====================================================================
-- 开关/门系统
-- ====================================================================
local GROUP_COLORS = {
    [1] = { 220, 60, 60 },
    [2] = { 60, 120, 220 },
    [3] = { 60, 200, 60 },
    [4] = { 220, 180, 40 },
}

--- 解码地块值：SWITCH/GATE 编码为 group*100+baseType
local function GetTileType(value)
    if value >= 100 then
        return value % 100, math.floor(value / 100)
    end
    return value, 0
end

-- 开关激活状态（按组跟踪）
local switchState = {}      -- switchState[group] = true/false
local switchCollected = {}  -- switchCollected["row_col"] = true
local hiddenWallRevealed = {} -- hiddenWallRevealed[group] = true（整组消失）

-- ====================================================================
-- 关卡信息
-- ====================================================================
local currentDifficulty = "easy"
local currentTemplateName = ""
local levelNumber = 1

-- ====================================================================
-- 世界地图连通（关卡切换）
-- ====================================================================
local worldMapData = nil        -- { nodes = {...}, connections = {...} }
local currentLevelFile = nil    -- 当前关卡文件名（nil = 随机生成模式）
local worldMapLoaded = false    -- 世界地图是否已加载
local transitionCooldown = 0    -- 切换冷却（防止瞬间来回切换）

-- 关卡切换过渡动画
local levelTransition = {
    active = false,       -- 是否正在过渡
    phase = "none",       -- "fadeOut" | "fadeIn" | "none"
    alpha = 0,            -- 当前遮罩透明度 0~1
    speed = 5.0,          -- 淡入淡出速度
    pendingFile = nil,    -- 待加载的目标关卡文件名
    pendingDir = nil,     -- 来源方向
}

-- ====================================================================
-- 运行时像素状态
-- ====================================================================
local pixelState = {}
local totalPixels = 0
local alivePixels = 0
local stripOrder = {}   -- 从左右两侧向内的剥离顺序

--- 初始化像素状态
local function InitPixelState()
    pixelState = {}
    totalPixels = 0
    local N = PLAYER_CONFIG.pixelGridSize
    for row = 1, N do
        pixelState[row] = {}
        for col = 1, N do
            if CHAR_SHAPE[row][col] == 1 then
                pixelState[row][col] = true
                totalPixels = totalPixels + 1
            else
                pixelState[row][col] = false
            end
        end
    end
    alivePixels = totalPixels

    -- 构建剥离顺序：从左右两侧向内剥离
    -- 优先剥离最外侧的像素，同时从左右交替
    stripOrder = {}
    local cx = (N + 1) / 2  -- 水平中心

    for row = 1, N do
        for col = 1, N do
            if CHAR_SHAPE[row][col] == 1 then
                -- 水平距中心的距离（越远越先被剥离）
                local hDist = math.abs(col - cx)
                -- 垂直从下往上（底部先剥离，火焰从根部熄灭）
                local vWeight = (N - row) * 0.1
                local priority = hDist + vWeight
                table.insert(stripOrder, { row = row, col = col, priority = priority })
            end
        end
    end
    -- 按 priority 从大到小排列（外侧先剥离）
    table.sort(stripOrder, function(a, b) return a.priority > b.priority end)
end

--- 剥离 n 个像素点（从左右两侧）
local function StripPixels(n)
    local stripped = 0
    for _, p in ipairs(stripOrder) do
        if stripped >= n then break end
        if pixelState[p.row][p.col] then
            pixelState[p.row][p.col] = false
            alivePixels = alivePixels - 1
            stripped = stripped + 1
        end
    end
end

--- 恢复 n 个像素点（从内层开始）
local function RecoverPixels(n)
    local recovered = 0
    for i = #stripOrder, 1, -1 do
        if recovered >= n then break end
        local p = stripOrder[i]
        if not pixelState[p.row][p.col] then
            pixelState[p.row][p.col] = true
            alivePixels = alivePixels + 1
            recovered = recovered + 1
        end
    end
end

-- ====================================================================
-- 游戏状态
-- ====================================================================
local STATE_PLAYING = 1
local STATE_GAMEOVER = 2
local STATE_WIN = 3

local gameState = STATE_PLAYING
local gameTime = 0  -- 全局时间（用于动画）

-- 玩家状态
local player = {
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

    -- 下落计数（用于计算跳跃加成）
    fallGridCount = 0,  -- 累计下落格数

    -- 动画状态
    isMoving = false,
    moveAnimTime = 0,
    fallAnimTime = 0,
}

-- ====================================================================
-- 表现层动画状态
-- ====================================================================

-- 灯笼晃动（移动时）
local lanternSway = {
    angle = 0,       -- 当前摆角（像素格偏移量）
    velocity = 0,    -- 角速度
    active = false,  -- 是否正在摆动
}

-- 下落火苗四散粒子系统
local fallParticles = {}  -- { x, y, vx, vy, life, maxLife, size }

-- 起跳/上升像素压缩
local jumpSquash = {
    active = false,
    frame = 0,          -- 当前帧
    phase = "none",     -- "squash" | "stretch" | "none"
}

-- 跳不动抖动
local cantJumpShake = {
    active = false,
    timer = 0,
    triggered = false,  -- 防止连续触发
}

-- 相机
local cameraX = 0

-- NanoVG
local vg = nil

-- 分辨率
local physW, physH, dpr, logicalW, logicalH
local scale, screenDesignW, screenDesignH, designOffsetX, designOffsetY

-- 前向声明（定义在后面，但 LoadLevelFromFile 需要提前调用）
local RecalcLayout

-- 输入
local inputState = { left = false, right = false, jumpPressed = false }
local prevLeft = false
local prevRight = false

-- 虚拟控件
local vc_joystick = nil
local vc_jumpBtn = nil

-- 收集
local collectedItems = {}
local coinCount = 0
local fuelCount = 0

-- ====================================================================
-- 关卡数据
-- 使用 LevelGenerator 的地块类型:
-- 0=EMPTY, 1=SOLID, 2=SPAWN, 3=FUEL, 4=GOAL, 5=SPIKE, 6=SWITCH, 7=GATE
-- SWITCH/GATE 编码: group*100 + baseType
-- ====================================================================
local TILE = LevelGenerator.TILE
local levelData = {}

--- 使用随机关卡生成器初始化关卡
local function InitLevel()
    local map, spawnCol, spawnRow, templateName, diff =
        LevelGenerator.GenerateValid(currentDifficulty, 5)

    levelData = map
    currentTemplateName = templateName or ""

    -- 设置玩家出生位置（spawnRow 是地表上方 1 格，需减去角色高度使底部贴地）
    local playerH = math.ceil(PLAYER_CONFIG.pixelGridSize * PLAYER_CONFIG.pixelSize / GRID)
    player.gridX = spawnCol
    player.gridY = spawnRow - (playerH - 1)

    -- 重置开关/门状态
    switchState = {}
    switchCollected = {}
    hiddenWallRevealed = {}

    print(string.format("[Game] Level %d generated: difficulty=%s, template=%s",
        levelNumber, currentDifficulty, currentTemplateName))
end

-- ====================================================================
-- 世界地图关卡加载/切换
-- ====================================================================

--- 从云存档加载指定关卡文件到 levelData
local function LoadLevelFromFile(filename)
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
    for row = 1, MAP_ROWS do
        levelData[row] = {}
        for col = 1, MAP_COLS do
            levelData[row][col] = 0
        end
    end

    -- 填充地块
    if data.tiles then
        for _, t in ipairs(data.tiles) do
            if t.row >= 1 and t.row <= MAP_ROWS and t.col >= 1 and t.col <= MAP_COLS then
                levelData[t.row][t.col] = t.v
            end
        end
    end

    -- 设置出生点
    local spawnCol = 3
    local spawnRow = MAP_ROWS - 3
    if data.spawn then
        spawnCol = data.spawn.col or spawnCol
        spawnRow = data.spawn.row or spawnRow
    end

    local playerH = math.ceil(PLAYER_CONFIG.pixelGridSize * PLAYER_CONFIG.pixelSize / GRID)
    player.gridX = spawnCol
    player.gridY = spawnRow - (playerH - 1)

    currentLevelFile = filename
    currentTemplateName = data.levelName or filename

    -- 重置开关/门状态
    switchState = {}
    switchCollected = {}
    hiddenWallRevealed = {}
    collectedItems = {}

    -- 读取关卡玩家参数（编辑器配置的跳跃/下落参数）
    if data.playerParams then
        levelPlayerParams.baseJumpGrids = data.playerParams.baseJumpGrids or 3
        levelPlayerParams.fallJumpMultiplier = data.playerParams.fallJumpMultiplier or 1.0
        levelPlayerParams.maxFallGrids = data.playerParams.maxFallGrids or 10
        levelPlayerParams.maxJumpGrids = data.playerParams.maxJumpGrids or 8
        PLAYER_CONFIG.cameraZoom = data.playerParams.cameraZoom or 1.0
    else
        levelPlayerParams.baseJumpGrids = PLAYER_CONFIG.baseJumpGrids
        levelPlayerParams.fallJumpMultiplier = 1.0
        levelPlayerParams.maxFallGrids = 10
        levelPlayerParams.maxJumpGrids = 8
        PLAYER_CONFIG.cameraZoom = 1.0
    end
    RecalcLayout()

    print("[WorldMap] Loaded level: " .. filename)
    return true
end

--- 查找当前关卡在某方向上连通的目标关卡文件
local function FindConnectedLevel(direction)
    if not worldMapData or not currentLevelFile then return nil end

    -- 找到当前关卡对应的节点 id
    local currentNodeId = nil
    for _, node in ipairs(worldMapData.nodes or {}) do
        if node.file == currentLevelFile then
            currentNodeId = node.id
            break
        end
    end
    if not currentNodeId then return nil end

    -- 在连接中查找从当前节点出发、指定方向的连接
    for _, conn in ipairs(worldMapData.connections or {}) do
        if conn.fromId == currentNodeId and conn.direction == direction then
            -- 找到目标节点的文件名
            for _, node in ipairs(worldMapData.nodes) do
                if node.id == conn.toId then
                    return node.file
                end
            end
        end
    end
    return nil
end

--- 执行关卡切换（direction: "left"/"right"/"up"/"down"）
local function TransitionToLevel(targetFile, fromDirection)
    if not LoadLevelFromFile(targetFile) then return end

    -- 根据来源方向决定玩家出生位置
    local playerH = math.ceil(PLAYER_CONFIG.pixelGridSize * PLAYER_CONFIG.pixelSize / GRID)
    if fromDirection == "right" then
        -- 从右边来，出生在左侧
        player.gridX = 2
    elseif fromDirection == "left" then
        -- 从左边来，出生在右侧
        player.gridX = MAP_COLS - 2
    elseif fromDirection == "down" then
        -- 从下边来，出生在顶部
        player.gridY = 2
    elseif fromDirection == "up" then
        -- 从上边来，出生在底部
        player.gridY = MAP_ROWS - playerH - 1
    end

    -- 重置相关状态
    cameraX = 0
    player.isOnGround = false
    player.isJumping = false
    player.jumpGridsRemain = 0
    player.moveTimer = 0
    player.movedFirstStep = false
    player.fallTimer = 0
    player.fallTickCurrent = PLAYER_CONFIG.fallTickBase
    player.jumpTimer = 0
    transitionCooldown = 0.5  -- 0.5 秒冷却

    InitPixelState()
    print("[WorldMap] Transition to: " .. targetFile .. " from " .. fromDirection)
end

--- 启动过渡动画（不直接切换，先 fadeOut）
local function StartLevelTransition(targetFile, fromDirection)
    levelTransition.active = true
    levelTransition.phase = "fadeOut"
    levelTransition.alpha = 0
    levelTransition.pendingFile = targetFile
    levelTransition.pendingDir = fromDirection
end

--- 更新关卡切换过渡动画（每帧调用）
local function UpdateLevelTransition(dt)
    if not levelTransition.active then return end

    local t = levelTransition
    if t.phase == "fadeOut" then
        t.alpha = t.alpha + t.speed * dt
        if t.alpha >= 1.0 then
            t.alpha = 1.0
            -- 全黑时执行实际关卡加载
            if t.pendingFile then
                TransitionToLevel(t.pendingFile, t.pendingDir)
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

--- 绘制过渡遮罩
local function DrawLevelTransition()
    if not levelTransition.active then return end
    if levelTransition.alpha <= 0 then return end
    local a = math.floor(levelTransition.alpha * 255)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, screenDesignH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
    nvgFill(vg)
end

--- 检查玩家是否触碰边界并触发切换
local function CheckBoundaryTransition()
    if not worldMapData or not currentLevelFile then return end
    if transitionCooldown > 0 then return end
    if levelTransition.active then return end

    local playerH = math.ceil(PLAYER_CONFIG.pixelGridSize * PLAYER_CONFIG.pixelSize / GRID)

    -- 检查左边界
    if player.gridX <= 1 then
        local target = FindConnectedLevel("left")
        if target then
            StartLevelTransition(target, "left")
            return
        end
    end

    -- 检查右边界
    if player.gridX + playerH - 1 >= MAP_COLS then
        local target = FindConnectedLevel("right")
        if target then
            StartLevelTransition(target, "right")
            return
        end
    end

    -- 检查上边界
    if player.gridY <= 1 then
        local target = FindConnectedLevel("up")
        if target then
            StartLevelTransition(target, "up")
            return
        end
    end

    -- 检查下边界
    if player.gridY + playerH - 1 >= MAP_ROWS then
        local target = FindConnectedLevel("down")
        if target then
            StartLevelTransition(target, "down")
            return
        else
            -- 没有连通的下方关卡，掉落即死亡
            gameState = STATE_GAMEOVER
            return
        end
    end
end

-- ====================================================================
-- 碰撞检测
-- ====================================================================
local function IsSolid(col, row)
    if col < 1 or col > MAP_COLS then return true end
    if row < 1 then return false end
    if row > MAP_ROWS then return false end  -- 地图底部为空，允许掉落死亡
    local val = levelData[row][col]
    local base, group = GetTileType(val)
    if base == TILE.SOLID then return true end
    -- 门：未激活时视为实体
    if base == TILE.GATE then
        if not switchState[group] then return true end
    end
    -- 隐藏墙：未揭示时视为实体
    if base == TILE.HIDDEN_WALL then
        if not hiddenWallRevealed[group] then return true end
    end
    return false
end

local function IsPlatform(col, row)
    -- 新地图系统不再有"平台"类型，只有 SOLID
    if col < 1 or col > MAP_COLS or row < 1 or row > MAP_ROWS then return false end
    return false
end

local function PlayerGridSize()
    local totalPx = PLAYER_CONFIG.pixelGridSize * PLAYER_CONFIG.pixelSize
    return math.ceil(totalPx / GRID)
end

local function PlayerCollidesAt(gx, gy)
    local s = PlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            if IsSolid(gx + dx, gy + dy) then return true end
        end
    end
    return false
end

local function PlayerOnGround(gx, gy)
    local s = PlayerGridSize()
    local feetRow = gy + s
    for dx = 0, s - 1 do
        if IsSolid(gx + dx, feetRow) or IsPlatform(gx + dx, feetRow) then
            return true
        end
    end
    return false
end

-- ====================================================================
-- 玩家逻辑
-- ====================================================================
local function CalcJumpHeight()
    -- 基础跳跃 + 累计下落格数 × 倍率，受最大跳跃高度限制
    local baseJump = levelPlayerParams.baseJumpGrids
    local bonus = player.fallGridCount * levelPlayerParams.fallJumpMultiplier
    return math.min(math.floor(baseJump + bonus + 0.5), levelPlayerParams.maxJumpGrids)
end

-- 前向声明（实现在渲染部分）
local TriggerJumpSquash
local TriggerCantJumpShake

local function PlayerJump()
    if player.isOnGround and not player.isJumping then
        local jumpHeight = CalcJumpHeight()
        if jumpHeight <= 0 then
            -- 跳跃高度为0：跳不动，触发抖动
            TriggerCantJumpShake()
            return
        end
        player.isJumping = true
        player.jumpGridsRemain = jumpHeight
        player.isOnGround = false
        player.jumpTimer = 0
        -- 触发起跳像素压缩动画
        TriggerJumpSquash()
    end
end

local function PlayerMoveOneGrid(dir)
    local newX = player.gridX + dir
    if not PlayerCollidesAt(newX, player.gridY) then
        player.gridX = newX
    end
    player.facingRight = (dir > 0)
end

local function PlayerUpdateVertical(dt)
    if player.isJumping and player.jumpGridsRemain > 0 then
        player.jumpTimer = player.jumpTimer + dt
        if player.jumpTimer >= PLAYER_CONFIG.jumpTickRate then
            player.jumpTimer = 0
            local newY = player.gridY - 1
            if not PlayerCollidesAt(player.gridX, newY) then
                player.gridY = newY
                player.jumpGridsRemain = player.jumpGridsRemain - 1
            else
                player.jumpGridsRemain = 0
            end
        end
        if player.jumpGridsRemain <= 0 then
            player.isJumping = false
            player.fallTickCurrent = PLAYER_CONFIG.fallTickBase
        end
    else
        if not PlayerOnGround(player.gridX, player.gridY) then
            player.isOnGround = false
            player.fallTimer = player.fallTimer + dt
            player.fallAnimTime = player.fallAnimTime + dt  -- 累积下落动画时间
            if player.fallTimer >= player.fallTickCurrent then
                player.fallTimer = 0
                local newY = player.gridY + 1
                if newY > MAP_ROWS then
                    gameState = STATE_GAMEOVER
                    return
                end
                if not PlayerCollidesAt(player.gridX, newY) then
                    player.gridY = newY
                    player.fallTickCurrent = math.max(
                        PLAYER_CONFIG.fallTickMin,
                        player.fallTickCurrent - PLAYER_CONFIG.fallAccel
                    )
                    -- 每下降1格：剥离总像素的1/10，跳跃高度+1
                    player.fallGridCount = player.fallGridCount + 1
                    local stripCount = math.max(1, math.floor(totalPixels / 10 + 0.5))
                    StripPixels(stripCount)
                    -- 超过最大下落格数则死亡
                    if player.fallGridCount >= levelPlayerParams.maxFallGrids then
                        gameState = STATE_GAMEOVER
                        return
                    end
                else
                    player.isOnGround = true
                    player.fallTickCurrent = PLAYER_CONFIG.fallTickBase
                    player.fallAnimTime = 0
                end
            end
        else
            player.isOnGround = true
            player.isJumping = false
            player.fallTickCurrent = PLAYER_CONFIG.fallTickBase
            player.fallAnimTime = 0
        end
    end

    -- 落地恢复像素（同时减少下落计数，保持跳跃高度与像素同步）
    if player.isOnGround and alivePixels < totalPixels then
        local recoverCount = math.floor(PLAYER_CONFIG.recoverPerSec * dt + 0.5)
        if recoverCount >= 1 then
            RecoverPixels(recoverCount)
            -- 每恢复 totalPixels/10 个像素，减少 1 格下落计数
            local pixelsPerGrid = math.max(1, math.floor(totalPixels / 10 + 0.5))
            local expectedFallCount = math.floor((totalPixels - alivePixels) / pixelsPerGrid)
            player.fallGridCount = math.max(0, expectedFallCount)
        end
    end

    if alivePixels <= 0 then
        gameState = STATE_GAMEOVER
    end
end

local function CheckItemCollection()
    local s = PlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            local col = player.gridX + dx
            local row = player.gridY + dy
            if col >= 1 and col <= MAP_COLS and row >= 1 and row <= MAP_ROWS then
                local val = levelData[row][col]
                local base, group = GetTileType(val)
                local key = row .. "_" .. col

                if base == TILE.SPIKE then
                    -- 刺陷阱：立即死亡
                    gameState = STATE_GAMEOVER
                    return

                elseif base == TILE.GOAL then
                    -- 终点门：胜利
                    gameState = STATE_WIN
                    return

                elseif base == TILE.FUEL and not collectedItems[key] then
                    -- 燃料：恢复火焰像素
                    collectedItems[key] = true
                    fuelCount = fuelCount + 1
                    levelData[row][col] = TILE.EMPTY
                    -- 立即恢复大量像素
                    RecoverPixels(math.floor(totalPixels * 0.4))
                    -- 同步更新下落计数
                    local pixelsPerGrid = math.max(1, math.floor(totalPixels / 10 + 0.5))
                    local expectedFallCount = math.floor((totalPixels - alivePixels) / pixelsPerGrid)
                    player.fallGridCount = math.max(0, expectedFallCount)

                elseif base == TILE.SWITCH and not switchCollected[key] then
                    -- 开关：切换同组门的状态
                    switchCollected[key] = true
                    switchState[group] = not switchState[group]
                end
            end
        end
    end

    -- 检测邻接的隐藏墙（玩家触碰到但不重叠的墙壁）
    local gx, gy = player.gridX, player.gridY
    -- 左侧一列
    local leftCol = gx - 1
    if leftCol >= 1 then
        for dy = 0, s - 1 do
            local r = gy + dy
            if r >= 1 and r <= MAP_ROWS then
                local ab, ag = GetTileType(levelData[r][leftCol])
                if ab == TILE.HIDDEN_WALL and not hiddenWallRevealed[ag] then
                    hiddenWallRevealed[ag] = true
                end
            end
        end
    end
    -- 右侧一列
    local rightCol = gx + s
    if rightCol <= MAP_COLS then
        for dy = 0, s - 1 do
            local r = gy + dy
            if r >= 1 and r <= MAP_ROWS then
                local ab, ag = GetTileType(levelData[r][rightCol])
                if ab == TILE.HIDDEN_WALL and not hiddenWallRevealed[ag] then
                    hiddenWallRevealed[ag] = true
                end
            end
        end
    end
    -- 上方一行
    local topRow = gy - 1
    if topRow >= 1 then
        for dx = 0, s - 1 do
            local c = gx + dx
            if c >= 1 and c <= MAP_COLS then
                local ab, ag = GetTileType(levelData[topRow][c])
                if ab == TILE.HIDDEN_WALL and not hiddenWallRevealed[ag] then
                    hiddenWallRevealed[ag] = true
                end
            end
        end
    end
    -- 下方一行
    local bottomRow = gy + s
    if bottomRow <= MAP_ROWS then
        for dx = 0, s - 1 do
            local c = gx + dx
            if c >= 1 and c <= MAP_COLS then
                local ab, ag = GetTileType(levelData[bottomRow][c])
                if ab == TILE.HIDDEN_WALL and not hiddenWallRevealed[ag] then
                    hiddenWallRevealed[ag] = true
                end
            end
        end
    end
end

-- ====================================================================
-- 渲染
-- ====================================================================

local function DrawBackground()
    -- 深色夜空背景
    local bg = nvgLinearGradient(vg, 0, 0, 0, screenDesignH,
        nvgRGBA(10, 5, 20, 255), nvgRGBA(30, 15, 40, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, screenDesignH)
    nvgFillPaint(vg, bg)
    nvgFill(vg)
end

local function DrawGrid()
    local startCol = math.max(1, math.floor(cameraX / GRID) + 1)
    local visW = DESIGN_W * (PLAYER_CONFIG.cameraZoom or 1.0)
    local endCol = math.min(MAP_COLS, startCol + math.ceil(visW / GRID) + 2)

    -- 细线
    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        local x = (col - 1) * GRID - cameraX
        nvgMoveTo(vg, x, 0)
        nvgLineTo(vg, x, MAP_ROWS * GRID)
    end
    for row = 1, MAP_ROWS + 1 do
        local y = (row - 1) * GRID
        local x0 = (startCol - 1) * GRID - cameraX
        local x1 = (endCol) * GRID - cameraX
        nvgMoveTo(vg, x0, y)
        nvgLineTo(vg, x1, y)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 15))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 每 5 格加粗
    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        if (col - 1) % 5 == 0 then
            local x = (col - 1) * GRID - cameraX
            nvgMoveTo(vg, x, 0)
            nvgLineTo(vg, x, MAP_ROWS * GRID)
        end
    end
    for row = 1, MAP_ROWS + 1 do
        if (row - 1) % 5 == 0 then
            local y = (row - 1) * GRID
            local x0 = (startCol - 1) * GRID - cameraX
            local x1 = (endCol) * GRID - cameraX
            nvgMoveTo(vg, x0, y)
            nvgLineTo(vg, x1, y)
        end
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 35))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

local function DrawMap()
    local startCol = math.max(1, math.floor(cameraX / GRID) + 1)
    local visW = DESIGN_W * (PLAYER_CONFIG.cameraZoom or 1.0)
    local endCol = math.min(MAP_COLS, startCol + math.ceil(visW / GRID) + 2)

    for row = 1, MAP_ROWS do
        for col = startCol, endCol do
            local val = levelData[row][col]
            if val == TILE.EMPTY then goto continueTile end

            local base, group = GetTileType(val)
            local px = (col - 1) * GRID - cameraX
            local py = (row - 1) * GRID

            if base == TILE.SOLID then
                -- 实体砖块（暗色石头风格）
                nvgBeginPath(vg)
                nvgRect(vg, px + 0.5, py + 0.5, GRID - 1, GRID - 1)
                nvgFillColor(vg, nvgRGBA(40, 45, 55, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + 0.5, py + 0.5, GRID - 1, 2)
                nvgFillColor(vg, nvgRGBA(60, 70, 80, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + 0.5, py + 0.5, 2, GRID - 1)
                nvgFillColor(vg, nvgRGBA(55, 60, 70, 255))
                nvgFill(vg)

            elseif base == TILE.SPAWN then
                -- 出生点标记（半透明光圈）
                nvgBeginPath(vg)
                nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 6)
                nvgFillColor(vg, nvgRGBA(255, 200, 50, 40))
                nvgFill(vg)

            elseif base == TILE.FUEL then
                -- 燃料（火焰恢复物）- 闪烁的火种
                local key = row .. "_" .. col
                if not collectedItems[key] then
                    local flicker = math.sin(gameTime * 6 + col * 1.7) * 0.3 + 0.7
                    local r = math.floor(255 * flicker)
                    local g = math.floor(120 * flicker)
                    -- 外圈光晕
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 7)
                    nvgFillColor(vg, nvgRGBA(255, 100, 0, math.floor(60 * flicker)))
                    nvgFill(vg)
                    -- 核心
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 4)
                    nvgFillColor(vg, nvgRGBA(r, g, 10, 255))
                    nvgFill(vg)
                    -- 内芯
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5 - 1, 2)
                    nvgFillColor(vg, nvgRGBA(255, 255, 200, math.floor(200 * flicker)))
                    nvgFill(vg)
                end

            elseif base == TILE.GOAL then
                -- 终点门（发光门框）
                nvgBeginPath(vg)
                nvgRect(vg, px + 2, py, GRID - 4, GRID)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 60))
                nvgFill(vg)
                -- 门框
                nvgBeginPath(vg)
                nvgRect(vg, px + 2, py, 2, GRID)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 220))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + GRID - 4, py, 2, GRID)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 220))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + 2, py, GRID - 4, 2)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 220))
                nvgFill(vg)
                -- 发光效果
                local glow = math.sin(gameTime * 3) * 0.3 + 0.7
                nvgBeginPath(vg)
                nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 8)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, math.floor(30 * glow)))
                nvgFill(vg)

            elseif base == TILE.SPIKE then
                -- 尖刺（三角形 + 高光）
                nvgBeginPath(vg)
                nvgMoveTo(vg, px + 2, py + GRID - 2)
                nvgLineTo(vg, px + GRID * 0.5, py + 2)
                nvgLineTo(vg, px + GRID - 2, py + GRID - 2)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(200, 30, 30, 255))
                nvgFill(vg)
                -- 尖端高光
                nvgBeginPath(vg)
                nvgMoveTo(vg, px + GRID * 0.5 - 1, py + 3)
                nvgLineTo(vg, px + GRID * 0.5, py + 2)
                nvgLineTo(vg, px + GRID * 0.5 + 1, py + 3)
                nvgStrokeColor(vg, nvgRGBA(255, 180, 180, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

            elseif base == TILE.SWITCH then
                -- 开关（圆形按钮 + 底座）
                local key = row .. "_" .. col
                local gc = GROUP_COLORS[group] or GROUP_COLORS[1]
                local activated = switchCollected[key]
                -- 底座
                nvgBeginPath(vg)
                nvgRoundedRect(vg, px + 3, py + GRID - 5, GRID - 6, 4, 1)
                nvgFillColor(vg, nvgRGBA(80, 80, 80, 255))
                nvgFill(vg)
                -- 按钮
                nvgBeginPath(vg)
                nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 5)
                if activated then
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 80))
                else
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
                end
                nvgFill(vg)
                -- 拨杆
                if not activated then
                    nvgBeginPath(vg)
                    nvgRect(vg, px + GRID * 0.5 - 1, py + 2, 2, 6)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
                    nvgFill(vg)
                end

            elseif base == TILE.GATE then
                -- 门（栏杆效果 / 打开时虚影）
                local gc = GROUP_COLORS[group] or GROUP_COLORS[1]
                local open = switchState[group]
                if not open then
                    -- 闭合门
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 1, py, GRID - 2, GRID)
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 180))
                    nvgFill(vg)
                    -- 栏杆纹路
                    for dx = 0, 2 do
                        nvgBeginPath(vg)
                        nvgRect(vg, px + 3 + dx * 5, py + 2, 2, GRID - 4)
                        nvgFillColor(vg, nvgRGBA(
                            math.floor(gc[1] * 0.3),
                            math.floor(gc[2] * 0.3),
                            math.floor(gc[3] * 0.3), 255))
                        nvgFill(vg)
                    end
                else
                    -- 门打开：虚影
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 1, py, GRID - 2, GRID)
                    nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 50))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)
                end

            elseif base == TILE.HIDDEN_WALL then
                if not hiddenWallRevealed[group] then
                    -- 隐藏墙未揭示时，与实体砖块外观一样
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 0.5, py + 0.5, GRID - 1, GRID - 1)
                    nvgFillColor(vg, nvgRGBA(40, 45, 55, 255))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 0.5, py + 0.5, GRID - 1, 2)
                    nvgFillColor(vg, nvgRGBA(60, 70, 80, 255))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 0.5, py + 0.5, 2, GRID - 1)
                    nvgFillColor(vg, nvgRGBA(55, 60, 70, 255))
                    nvgFill(vg)
                end
            end

            ::continueTile::
        end
    end
end

-- ====================================================================
-- 火焰像素动画帧系统（严格像素风：所有位移为整数格）
-- ====================================================================
-- 动画帧率（像素风动画通常 8~12fps，不同于渲染帧率）
local FLAME_ANIM_FPS = 10
local flameAnimTimer = 0
local flameAnimFrame = 0  -- 当前动画帧号（递增）

-- 每行像素的水平偏移量（整数格，每帧更新一次）
-- rowOffsets[row] = 整数（-2, -1, 0, 1, 2 表示偏移几个像素格）
local rowOffsets = {}

-- 每行像素的垂直偏移量
local rowVOffsets = {}

--- 更新火焰动画帧（每 1/FLAME_ANIM_FPS 秒执行一次）
local function UpdateFlameAnimFrame()
    flameAnimFrame = flameAnimFrame + 1
    local N = PLAYER_CONFIG.pixelGridSize

    -- 根据状态决定波浪幅度（整数格单位）
    local maxAmp = 1    -- 静止：最多偏移 ±1 格
    local vertAmp = 0   -- 静止：无垂直偏移
    if not player.isOnGround and not player.isJumping then
        maxAmp = 2      -- 下落：最多偏移 ±2 格（过大会导致断裂感）
        vertAmp = 0     -- 不使用垂直偏移
    elseif player.isMoving then
        maxAmp = 2      -- 行走：最多偏移 ±2 格
        vertAmp = 0     -- 不使用垂直偏移
    end

    for row = 1, N do
        -- 行越高（row越小），允许的偏移幅度越大
        local rowFactor = (N - row) / N  -- 0(底部) ~ 1(顶部)
        local amp = math.floor(maxAmp * rowFactor + 0.5)

        -- 主波浪：正弦波量化为整数
        -- 使用帧号驱动，每行有不同相位（产生自底向上的传播效果）
        local phase = flameAnimFrame * 0.7 - row * 0.8
        local rawWave = math.sin(phase)

        -- 量化为整数格偏移（-amp ~ +amp）
        local intOffset = math.floor(rawWave * amp + 0.5)

        -- 行走方向额外倾斜（高处偏移更多）
        if player.isMoving then
            local leanDir = player.facingRight and 1 or -1
            local lean = math.floor(rowFactor * 1.5 + 0.5) * leanDir
            intOffset = intOffset + lean
        end

        rowOffsets[row] = intOffset
        -- 不使用垂直偏移（会导致行间断裂）
        rowVOffsets[row] = 0
    end
end

-- ====================================================================
-- 表现层动画更新（每帧调用）
-- ====================================================================

--- 灯笼每行偏移缓存（保证相邻行差值<=1，无断裂）
local lanternRowShifts = {}  -- lanternRowShifts[row] = 整数偏移
for i = 1, PLAYER_CONFIG.pixelGridSize do lanternRowShifts[i] = 0 end

--- 更新灯笼晃动（钟摆物理 + 连续性保证）
local function UpdateLanternSway(dt)
    if player.isMoving then
        -- 移动时：用正弦力驱动钟摆来回摆动
        local swayForce = math.sin(gameTime * PLAYER_CONFIG.lanternSwayFreq) * 25.0
        -- 移动方向给持续的偏置力（产生"惯性倾斜"）
        local dirBias = player.facingRight and 5.0 or -5.0
        lanternSway.velocity = lanternSway.velocity + (swayForce + dirBias) * dt
        lanternSway.active = true
    else
        -- 停止时自然衰减
        if math.abs(lanternSway.angle) < 0.05 and math.abs(lanternSway.velocity) < 0.05 then
            lanternSway.angle = 0
            lanternSway.velocity = 0
            lanternSway.active = false
        end
    end

    -- 弹簧回复力
    local springK = 18.0
    lanternSway.velocity = lanternSway.velocity - lanternSway.angle * springK * dt
    -- 阻尼
    local damping = player.isMoving and 2.5 or 4.0
    lanternSway.velocity = lanternSway.velocity * (1.0 - damping * dt)
    -- 积分
    lanternSway.angle = lanternSway.angle + lanternSway.velocity * dt
    -- 限幅
    local maxA = PLAYER_CONFIG.lanternMaxAngle
    lanternSway.angle = math.max(-maxA, math.min(maxA, lanternSway.angle))

    -- 计算每行的灯笼偏移（保证相邻行差值 <= 1）
    local N = PLAYER_CONFIG.pixelGridSize
    -- 顶部行(row=1)偏移最大，底部行(row=N)偏移=0
    -- 使用二次曲线让顶部偏移更明显
    local topOffset = lanternSway.angle  -- 浮点数，顶部的目标偏移

    for row = 1, N do
        -- 二次曲线：底部=0，顶部=topOffset
        -- factor: row=1 → 1.0, row=N → 0.0
        local factor = ((N - row) / (N - 1)) ^ 1.5  -- 1.5次方让中部也有明显偏移
        local rawOffset = topOffset * factor
        lanternRowShifts[row] = math.floor(rawOffset + 0.5)
    end

    -- 平滑pass：保证相邻行差值不超过1（从底部向上修正）
    lanternRowShifts[N] = 0  -- 底部锚定
    for row = N - 1, 1, -1 do
        local diff = lanternRowShifts[row] - lanternRowShifts[row + 1]
        if diff > 1 then
            lanternRowShifts[row] = lanternRowShifts[row + 1] + 1
        elseif diff < -1 then
            lanternRowShifts[row] = lanternRowShifts[row + 1] - 1
        end
    end
end

--- 更新下落火苗四散粒子
local fallParticleDebugTimer = 0
local function UpdateFallParticles(dt)
    local N = PLAYER_CONFIG.pixelGridSize
    local ps = PLAYER_CONFIG.pixelSize

    -- 调试：每2秒打印一次粒子系统状态
    fallParticleDebugTimer = fallParticleDebugTimer + dt
    if fallParticleDebugTimer > 2.0 then
        fallParticleDebugTimer = 0
        print(string.format("[Particles] onGround=%s jumping=%s alive=%d/%d count=%d",
            tostring(player.isOnGround), tostring(player.isJumping),
            alivePixels, totalPixels, #fallParticles))
    end

    -- 仅在下落时生成粒子（不是跳跃上升，不是站在地面）
    -- 火星是重要的消耗提示，只在下落且有消耗时出现
    local isFalling = not player.isOnGround and not player.isJumping
    if isFalling and alivePixels < totalPixels then
        -- 消耗比例：0=刚消耗一点，1=完全消耗
        local consumeRatio = 1.0 - alivePixels / math.max(1, totalPixels)
        -- 保证即使消耗很少，也有基础的粒子数量和概率
        local baseRatio = math.max(0.15, consumeRatio)  -- 最低15%保底

        -- 最大粒子数：最低4颗保底，严重消耗可达18颗
        local maxParticles = math.floor(4 + baseRatio * 14)

        -- 生成概率：最低40%保底，确保粒子稳定出现
        local spawnChance = 0.40 + baseRatio * 0.50

        -- 严重消耗时每帧可生成多颗粒子
        local spawnAttempts = 1 + math.floor(baseRatio * 2)

        -- 计算粒子地面Y坐标：查找玩家下方的第一个实际固体地面
        local playerS = PlayerGridSize()
        local feetGridY = player.gridY + playerS  -- 玩家脚底的格子Y
        local groundGridY = feetGridY
        for searchY = feetGridY, MAP_ROWS do
            if IsSolid(player.gridX, searchY) or IsPlatform(player.gridX, searchY) then
                groundGridY = searchY
                break
            end
            if searchY == MAP_ROWS then
                groundGridY = MAP_ROWS + 1  -- 未找到地面，用地图底部
            end
        end
        local groundY = (groundGridY - 1) * GRID

        for _ = 1, spawnAttempts do
            if math.random() < spawnChance and #fallParticles < maxParticles then
                -- 使用世界坐标（不减cameraX），绘制时再转屏幕坐标
                local worldX = (player.gridX - 1) * GRID
                local baseY = (player.gridY - 1) * GRID
                local totalSize = N * ps
                -- 从火焰两侧随机发射
                local side = math.random() > 0.5 and 1 or -1
                local emitX = worldX + totalSize * 0.5 + side * (totalSize * 0.3 + math.random() * totalSize * 0.2)
                local emitY = baseY + totalSize * (0.3 + math.random() * 0.5)

                -- 粒子速度也随消耗增大（更剧烈的火星飞溅）
                local speedMul = 0.7 + consumeRatio * 0.6
                -- 更长的生命周期，让火星有时间落地反弹
                local life = 1.2 + consumeRatio * 0.6 + math.random() * 0.3
                table.insert(fallParticles, {
                    x = emitX,
                    y = emitY,
                    vx = side * (30 + math.random() * 40) * speedMul,
                    vy = -(20 + math.random() * 30) * speedMul,
                    life = life,
                    maxLife = life,
                    size = ps,
                    gravity = 120 + math.random() * 40,  -- 更强重力，让火星快速落下
                    colorRow = math.random(5, 10),
                    groundY = groundY,  -- 记录地面Y位置
                    bounces = 0,        -- 反弹次数
                    maxBounces = 1 + math.floor(math.random() * 2),  -- 1~2次反弹
                })
            end
        end
    end

    -- 更新已有粒子（含落地反弹逻辑）
    local i = 1
    while i <= #fallParticles do
        local p = fallParticles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(fallParticles, i)
        else
            p.vy = p.vy + p.gravity * dt  -- 重力
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt

            -- 落地反弹检测
            if p.y >= p.groundY and p.vy > 0 then
                if p.bounces < p.maxBounces then
                    -- 反弹：速度衰减，Y回到地面
                    p.y = p.groundY
                    p.vy = -p.vy * (0.3 + math.random() * 0.15)  -- 反弹力 30~45%
                    p.vx = p.vx * 0.6  -- 水平速度衰减
                    p.bounces = p.bounces + 1
                else
                    -- 已用完反弹次数，停在地上缓慢消失
                    p.y = p.groundY
                    p.vy = 0
                    p.vx = 0
                    -- 加速消亡（停在地面后快速淡出）
                    p.life = math.min(p.life, 0.3)
                end
            end

            -- 逐渐缩小（生命后期）
            local lifeRatio = p.life / p.maxLife
            if lifeRatio < 0.2 then
                p.size = math.max(1, math.floor(ps * lifeRatio / 0.2 + 0.5))
            end
            i = i + 1
        end
    end
end

--- 触发起跳压缩动画
TriggerJumpSquash = function()
    jumpSquash.active = true
    jumpSquash.frame = 0
    jumpSquash.phase = "squash"
end

--- 更新起跳像素压缩动画（按动画帧驱动）
local function UpdateJumpSquashFrame()
    if not jumpSquash.active then return end

    jumpSquash.frame = jumpSquash.frame + 1

    if jumpSquash.phase == "squash" then
        if jumpSquash.frame > PLAYER_CONFIG.jumpSquashFrames then
            jumpSquash.phase = "stretch"
            jumpSquash.frame = 0
        end
    elseif jumpSquash.phase == "stretch" then
        if jumpSquash.frame > PLAYER_CONFIG.jumpStretchFrames then
            jumpSquash.phase = "none"
            jumpSquash.active = false
            jumpSquash.frame = 0
        end
    end
end

--- 获取跳跃形变对某个像素的水平挤压偏移
--- 返回: colShift (水平偏移格数), skip (是否隐藏该像素)
local function GetJumpSquashForPixel(row, col)
    if not jumpSquash.active then return 0, false end

    local N = PLAYER_CONFIG.pixelGridSize
    local cx = (N + 1) / 2  -- 水平中心 = 5.5
    local colDist = col - cx  -- 负=左侧, 正=右侧

    if jumpSquash.phase == "squash" then
        -- 压缩阶段：所有像素向中心水平挤压
        -- 底部行挤压更多（蓄力感），顶部行几乎不动
        local progress = jumpSquash.frame / PLAYER_CONFIG.jumpSquashFrames  -- 0~1
        local rowWeight = row / N  -- 0(顶部) ~ 1(底部)，底部挤压大
        local squashAmt = progress * rowWeight * 0.3  -- 最大挤压30%（更温和，避免重叠）
        -- 将像素向中心收缩（不隐藏任何像素，只做位移）
        local shift = -math.floor(colDist * squashAmt + 0.5)
        return shift, false

    elseif jumpSquash.phase == "stretch" then
        -- 拉伸阶段：顶部像素向外水平展开（火焰变高变窄→恢复）
        local progress = jumpSquash.frame / PLAYER_CONFIG.jumpStretchFrames  -- 0~1
        local stretchT = math.sin(progress * math.pi)  -- 0→1→0 钟形
        local rowWeight = 1.0 - row / N  -- 1(顶部) ~ 0(底部)，顶部拉伸大
        local stretchAmt = stretchT * rowWeight * 0.4
        -- 将像素向外扩展
        local shift = math.floor(colDist * stretchAmt + 0.5)
        return shift, false
    end

    return 0, false
end

--- 触发跳不动抖动
TriggerCantJumpShake = function()
    if cantJumpShake.active then return end
    cantJumpShake.active = true
    cantJumpShake.timer = PLAYER_CONFIG.cantJumpShakeDur
end

--- 更新跳不动抖动
local function UpdateCantJumpShake(dt)
    if not cantJumpShake.active then return end
    cantJumpShake.timer = cantJumpShake.timer - dt
    if cantJumpShake.timer <= 0 then
        cantJumpShake.active = false
        cantJumpShake.timer = 0
    end
end

--- 获取跳不动抖动偏移（整数像素格）
local function GetCantJumpShakeOffset()
    if not cantJumpShake.active then return 0, 0 end
    -- 高频抖动，幅度递减
    local progress = 1.0 - cantJumpShake.timer / PLAYER_CONFIG.cantJumpShakeDur
    local decay = 1.0 - progress
    local freq = 30  -- 高频抖动
    local xOff = math.floor(math.sin(cantJumpShake.timer * freq * math.pi * 2) * PLAYER_CONFIG.cantJumpShakeAmp * decay + 0.5)
    local yOff = math.floor(math.cos(cantJumpShake.timer * freq * 1.3 * math.pi * 2) * 1 * decay + 0.5)
    return xOff, yOff
end

--- 绘制下落火苗四散粒子
local function DrawFallParticles()
    for _, p in ipairs(fallParticles) do
        local lifeRatio = p.life / p.maxLife
        local alpha = math.floor(lifeRatio * 255)
        local c = FLAME_COLORS[p.colorRow] or FLAME_COLORS[8]
        -- 粒子颜色随生命变暗
        local bright = 0.5 + lifeRatio * 0.5
        local r = math.floor(c[1] * bright)
        local g = math.floor(c[2] * bright)
        local b = math.floor(c[3] * bright)

        -- 像素风：世界坐标转屏幕坐标，对齐到像素格
        local screenX = p.x - cameraX
        local drawX = math.floor(screenX / PLAYER_CONFIG.pixelSize + 0.5) * PLAYER_CONFIG.pixelSize
        local drawY = math.floor(p.y / PLAYER_CONFIG.pixelSize + 0.5) * PLAYER_CONFIG.pixelSize

        nvgBeginPath(vg)
        nvgRect(vg, drawX, drawY, p.size, p.size)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)

        -- 拖尾：在后方画一个稍暗的像素
        if lifeRatio > 0.3 then
            local tailX = drawX - math.floor(p.vx * 0.02 / PLAYER_CONFIG.pixelSize + 0.5) * PLAYER_CONFIG.pixelSize
            local tailY = drawY - math.floor(p.vy * 0.02 / PLAYER_CONFIG.pixelSize + 0.5) * PLAYER_CONFIG.pixelSize
            nvgBeginPath(vg)
            nvgRect(vg, tailX, tailY, p.size, p.size)
            nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(alpha * 0.4)))
            nvgFill(vg)
        end
    end
end

--- 绘制火焰玩家（像素风格：所有位移对齐像素格）
local function DrawPlayer()
    local baseX = (player.gridX - 1) * GRID - cameraX
    local baseY = (player.gridY - 1) * GRID
    local ps = PLAYER_CONFIG.pixelSize
    local N = PLAYER_CONFIG.pixelGridSize
    local totalSize = N * ps

    -- 跳不动抖动偏移
    local shakeX, shakeY = GetCantJumpShakeOffset()
    baseX = baseX + shakeX * ps
    baseY = baseY + shakeY * ps

    -- 火焰中心点
    local pivotX = baseX + totalSize * 0.5
    local pivotY = baseY + totalSize

    -- 主角光源：直径随火焰强度线性缩放（满血=defaultLightDiameter格，最低=0）
    local flameRatio = alivePixels / math.max(1, totalPixels)
    local lightDiameter = PLAYER_CONFIG.defaultLightDiameter * GRID * flameRatio
    local lightRadius = lightDiameter * 0.5
    if lightRadius > 0 then
        local lightCX = pivotX
        local lightCY = baseY + totalSize * 0.5
        -- 外层柔和光晕（径向渐变：中心暖光 → 边缘透明）
        local lightAlphaBase = math.floor(30 + 10 * math.sin(gameTime * PLAYER_CONFIG.flickerSpeed * 0.7))
        local outerGlow = nvgRadialGradient(vg, lightCX, lightCY, lightRadius * 0.2, lightRadius,
            nvgRGBA(255, 150, 40, lightAlphaBase),
            nvgRGBA(255, 80, 0, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, lightCX, lightCY, lightRadius)
        nvgFillPaint(vg, outerGlow)
        nvgFill(vg)
    end

    -- 绘制近距光晕（原有逻辑）
    local glowRadius = totalSize * 0.6 * flameRatio
    local glowAlpha = math.floor(40 + 20 * math.sin(gameTime * PLAYER_CONFIG.flickerSpeed))
    nvgBeginPath(vg)
    nvgCircle(vg, pivotX, pivotY - totalSize * 0.5, glowRadius)
    nvgFillColor(vg, nvgRGBA(255, 120, 0, glowAlpha))
    nvgFill(vg)

    -- 颜色闪烁帧（也是离散的：每个动画帧切换亮度等级）
    local brightFrame = flameAnimFrame

    -- 预计算所有行的合并水平偏移
    -- 关键：严格限制偏移，防止窄行飘出主体导致视觉断裂
    local combinedH = {}

    -- 计算每行的活跃像素宽度（左边界到右边界）
    local rowWidth = {}
    for row = 1, N do
        local minCol, maxCol = N + 1, 0
        for col = 1, N do
            if pixelState[row][col] then
                if col < minCol then minCol = col end
                if col > maxCol then maxCol = col end
            end
        end
        rowWidth[row] = (maxCol >= minCol) and (maxCol - minCol + 1) or 0
    end

    for row = 1, N do
        local raw = (rowOffsets[row] or 0) + (lanternRowShifts[row] or 0)
        -- 严格限制偏移量：
        -- 窄行(<=4像素)：最多偏移0-1格，防止视觉断裂
        -- 宽行(>4像素)：最多偏移宽度的30%
        local w = rowWidth[row]
        local maxShift
        if w <= 2 then
            maxShift = 0  -- 极窄行（火焰尖端）不偏移
        elseif w <= 4 then
            maxShift = 1  -- 窄行最多1格
        else
            maxShift = math.max(1, math.floor(w * 0.3))
        end
        combinedH[row] = math.max(-maxShift, math.min(maxShift, raw))
    end

    -- 底部两行固定为0（火焰底部不偏移，保证稳定基座）
    combinedH[N] = 0
    combinedH[N - 1] = 0
    -- 从底部向上平滑：每行相对下方行偏差不超过1
    for row = N - 2, 1, -1 do
        local diff = combinedH[row] - combinedH[row + 1]
        if diff > 1 then
            combinedH[row] = combinedH[row + 1] + 1
        elseif diff < -1 then
            combinedH[row] = combinedH[row + 1] - 1
        end
    end
    -- 再从顶部向下做一次平滑（双向约束更稳定）
    for row = 2, N do
        local diff = combinedH[row] - combinedH[row - 1]
        if diff > 1 then
            combinedH[row] = combinedH[row - 1] + 1
        elseif diff < -1 then
            combinedH[row] = combinedH[row - 1] - 1
        end
    end
    -- 第三遍：再次从底向上确保约束（消除双向传播残留冲突）
    for row = N - 2, 1, -1 do
        local diff = combinedH[row] - combinedH[row + 1]
        if diff > 1 then
            combinedH[row] = combinedH[row + 1] + 1
        elseif diff < -1 then
            combinedH[row] = combinedH[row + 1] - 1
        end
    end

    -- 绘制每个火焰像素
    for row = 1, N do
        -- 本行的合并水平偏移（已平滑，无断裂）
        local hShift = combinedH[row]

        for col = 1, N do
            if pixelState[row][col] then
                -- 跳跃形变：per-pixel水平挤压/拉伸（不做垂直位移）
                local squashShift, squashSkip = GetJumpSquashForPixel(row, col)
                if not squashSkip then
                    local baseColor = FLAME_COLORS[row]

                    -- 亮度闪烁（离散2~3级跳变）
                    local flickSeed = (brightFrame * 3 + row * 7 + col * 13) % 10
                    local brightness
                    if flickSeed < 2 then
                        brightness = 1.25
                    elseif flickSeed < 5 then
                        brightness = 1.0
                    else
                        brightness = 0.85
                    end

                    -- 顶部行整体更亮
                    if row <= 2 then
                        brightness = brightness + 0.15
                    end

                    -- 边缘像素稍暗
                    local cx = (N + 1) / 2
                    if math.abs(col - cx) >= 3 then
                        brightness = brightness * 0.85
                    end

                    local r = math.min(255, math.max(0, math.floor(baseColor[1] * brightness)))
                    local g = math.min(255, math.max(0, math.floor(baseColor[2] * brightness)))
                    local b = math.min(255, math.max(0, math.floor(baseColor[3] * brightness)))

                    -- 最终绘制位置：水平偏移（晃动+形变），垂直无偏移
                    local drawCol = col
                    if not player.facingRight then
                        drawCol = N - col + 1
                    end
                    local px = baseX + (drawCol - 1 + hShift + squashShift) * ps
                    local py = baseY + (row - 1) * ps

                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, ps, ps)
                    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
                    nvgFill(vg)
                end
            end
        end
    end

    -- 火星粒子（也对齐像素格）
    if alivePixels > totalPixels * 0.2 then
        for i = 1, 4 do
            local life = (flameAnimFrame + i * 3) % 8
            local progress = life / 7

            local emitCol = math.floor(N * 0.3 + (i * 2.7 + flameAnimFrame * 0.3) % (N * 0.4))
            local emitX = baseX + emitCol * ps
            local emitY = baseY - life * ps

            local sparkAlpha = math.floor((1.0 - progress) * 240)
            if sparkAlpha > 20 and life > 0 then
                local pr = 255
                local pg = math.floor(200 * (1.0 - progress * 0.6))
                local pb = math.floor(40 * (1.0 - progress))
                nvgBeginPath(vg)
                nvgRect(vg, emitX, emitY, ps, ps)
                nvgFillColor(vg, nvgRGBA(pr, pg, pb, sparkAlpha))
                nvgFill(vg)
            end
        end
    end

    -- 绘制下落火苗四散粒子
    DrawFallParticles()
end

local function DrawHUD()
    -- 顶部信息栏
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, 22)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 关卡信息
    local diffNames = { easy = "Easy", normal = "Normal", hard = "Hard" }
    local diffColors = {
        easy   = { 100, 220, 100 },
        normal = { 220, 200, 60 },
        hard   = { 255, 80, 60 },
    }
    local dc = diffColors[currentDifficulty] or { 200, 200, 200 }
    nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 255))
    nvgText(vg, 6, 11, "Lv" .. levelNumber .. " " .. (diffNames[currentDifficulty] or "?"))

    -- 火焰状态
    local flamePercent = math.floor(alivePixels / math.max(1, totalPixels) * 100)
    local flameR = 255
    local flameG = math.floor(200 * (flamePercent / 100))
    nvgFillColor(vg, nvgRGBA(flameR, flameG, 30, 255))
    nvgText(vg, 90, 11, "FLAME:" .. flamePercent .. "%")

    -- 跳跃高度
    nvgFillColor(vg, nvgRGBA(150, 255, 150, 255))
    nvgText(vg, 175, 11, "JUMP:" .. CalcJumpHeight() .. "G")

    -- 燃料计数
    nvgFillColor(vg, nvgRGBA(255, 140, 40, 255))
    nvgText(vg, 235, 11, "FUEL:" .. fuelCount)

    -- 右侧：版本号
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 8)
    nvgFillColor(vg, nvgRGBA(100, 105, 120, 150))
    nvgText(vg, screenDesignW - 6, 11, "v" .. GAME_VERSION)

    -- 操作提示（版本号下方）
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 150))
    local versionW = nvgTextBounds(vg, 0, 0, "v" .. GAME_VERSION) + 8
    nvgText(vg, screenDesignW - 6 - versionW, 11, "R:Retry N:Next 1/2/3:Diff")

    -- 游戏结束/胜利
    if gameState == STATE_GAMEOVER then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
        nvgText(vg, screenDesignW * 0.5, screenDesignH * 0.4, "FLAME OUT!")
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, screenDesignW * 0.5, screenDesignH * 0.52, "R:Retry  N:New Level")
    elseif gameState == STATE_WIN then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
        nvgText(vg, screenDesignW * 0.5, screenDesignH * 0.4, "FLAME ETERNAL!")
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, screenDesignW * 0.5, screenDesignH * 0.52, "N:Next Level  R:Replay")
    end
end

-- ====================================================================
-- 重置 / 关卡进度
-- ====================================================================
local function ResetGame()
    player.isOnGround = false
    player.isJumping = false
    player.jumpGridsRemain = 0
    player.facingRight = true
    player.moveTimer = 0
    player.movedFirstStep = false
    player.fallTimer = 0
    player.fallTickCurrent = PLAYER_CONFIG.fallTickBase
    player.jumpTimer = 0
    player.fallGridCount = 0
    player.isMoving = false
    player.moveAnimTime = 0
    player.fallAnimTime = 0

    cameraX = 0
    coinCount = 0
    fuelCount = 0
    collectedItems = {}
    switchState = {}
    switchCollected = {}
    hiddenWallRevealed = {}
    gameState = STATE_PLAYING
    gameTime = 0

    -- 重置表现层动画状态
    lanternSway.angle = 0
    lanternSway.velocity = 0
    lanternSway.active = false
    fallParticles = {}
    jumpSquash.active = false
    jumpSquash.frame = 0
    jumpSquash.phase = "none"
    cantJumpShake.active = false
    cantJumpShake.timer = 0

    InitLevel()  -- 生成随机关卡（会设置 player.gridX/gridY）
    InitPixelState()
end

--- 进入下一关
local function NextLevel()
    levelNumber = levelNumber + 1
    -- 每 3 关提升难度
    if levelNumber <= 3 then
        currentDifficulty = "easy"
    elseif levelNumber <= 6 then
        currentDifficulty = "normal"
    else
        currentDifficulty = "hard"
    end
    ResetGame()
end

--- 切换难度并重新生成
local function SetDifficulty(diff)
    currentDifficulty = diff
    ResetGame()
end

-- ====================================================================
-- 分辨率
-- ====================================================================
RecalcLayout = function()
    physW, physH = graphics:GetWidth(), graphics:GetHeight()
    dpr = graphics:GetDPR()
    logicalW, logicalH = physW / dpr, physH / dpr
    -- cameraZoom > 1 表示看到更多世界（设计尺寸等效放大），< 1 表示放大局部
    local zoom = PLAYER_CONFIG.cameraZoom or 1.0
    local effectiveW = DESIGN_W * zoom
    local effectiveH = DESIGN_H * zoom
    scale = math.min(logicalW / effectiveW, logicalH / effectiveH)
    screenDesignW = logicalW / scale
    screenDesignH = logicalH / scale
    designOffsetX = (screenDesignW - effectiveW) / 2
    designOffsetY = (screenDesignH - effectiveH) / 2
end

-- ====================================================================
-- 入口
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

    InitLevel()
    InitPixelState()

    player.fallTickCurrent = PLAYER_CONFIG.fallTickBase

    -- 加载世界地图连通数据（异步）
    CloudStorage.Init(function(ok)
        if ok then
            CloudStorage.InitWorldMap(function(wmOk)
                if wmOk then
                    worldMapData = CloudStorage.LoadWorldMap()
                    if worldMapData and worldMapData.nodes and #worldMapData.nodes > 0 then
                        worldMapLoaded = true
                        -- 自动加载世界地图的第一个关卡
                        local firstNode = worldMapData.nodes[1]
                        if firstNode and firstNode.file then
                            LoadLevelFromFile(firstNode.file)
                            InitPixelState()
                        end
                        print("[WorldMap] Loaded with " .. #worldMapData.nodes .. " levels, " .. #worldMapData.connections .. " connections")
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
-- 事件
-- ====================================================================

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end

    nvgBeginFrame(vg, logicalW, logicalH, dpr)
    nvgScale(vg, scale, scale)

    DrawBackground()

    nvgSave(vg)
    nvgTranslate(vg, designOffsetX, designOffsetY)

    DrawGrid()
    DrawMap()
    DrawPlayer()

    nvgRestore(vg)

    DrawHUD()
    DrawLevelTransition()

    nvgEndFrame(vg)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if gameState ~= STATE_PLAYING then return end
    local dt = eventData["TimeStep"]:GetFloat()

    gameTime = gameTime + dt

    -- 世界地图切换冷却
    if transitionCooldown > 0 then
        transitionCooldown = transitionCooldown - dt
    end

    -- 过渡动画更新
    UpdateLevelTransition(dt)
    if levelTransition.active then return end

    -- 火焰动画帧驱动（固定帧率，像素风离散更新）
    flameAnimTimer = flameAnimTimer + dt
    local frameInterval = 1.0 / FLAME_ANIM_FPS
    if flameAnimTimer >= frameInterval then
        flameAnimTimer = flameAnimTimer - frameInterval
        UpdateFlameAnimFrame()
        UpdateJumpSquashFrame()  -- 起跳压缩也按动画帧率驱动
    end

    -- 表现层动画更新（每帧，非离散）
    UpdateLanternSway(dt)
    UpdateFallParticles(dt)
    UpdateCantJumpShake(dt)

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

    if dir ~= 0 then
        local justPressed = false
        if dir == -1 and not prevLeft then justPressed = true end
        if dir == 1 and not prevRight then justPressed = true end

        if justPressed then
            PlayerMoveOneGrid(dir)
            player.moveTimer = 0
            player.movedFirstStep = true
        else
            player.moveTimer = player.moveTimer + dt
            if player.moveTimer >= PLAYER_CONFIG.moveTickRate then
                player.moveTimer = player.moveTimer - PLAYER_CONFIG.moveTickRate
                PlayerMoveOneGrid(dir)
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
        PlayerJump()
        inputState.jumpPressed = false
    end

    -- 垂直物理
    PlayerUpdateVertical(dt)

    -- 收集检测
    CheckItemCollection()

    -- 世界地图边界切换检测
    CheckBoundaryTransition()

    -- 相机（使用 cameraZoom 调整可视范围）
    local zoom = PLAYER_CONFIG.cameraZoom or 1.0
    local visibleW = DESIGN_W * zoom
    local playerPx = (player.gridX - 1) * GRID
    local targetCam = playerPx - visibleW * 0.35
    targetCam = math.max(0, math.min(targetCam, MAP_COLS * GRID - visibleW))
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
